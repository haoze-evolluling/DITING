import 'dart:async';

import 'package:diting/app/bootstrap.dart';
import 'package:diting/app/initial_agreement.dart';
import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/app/l10n/ui_strings.dart';
import 'package:diting/app/theme/colors.dart';
import 'package:diting/app/theme/manager.dart';
import 'package:diting/data/native/tile_bridge.dart';
import 'package:diting/router.dart';
import 'package:diting/state/appearance_extra_providers.dart';
import 'package:diting/state/appearance_providers.dart';
import 'package:diting/state/auto_update_providers.dart';
import 'package:diting/state/auto_update_runner.dart';
import 'package:diting/state/db_health_providers.dart';
import 'package:diting/state/installed_apps_providers.dart';
import 'package:diting/state/on_demand_runner.dart';
import 'package:diting/state/rules_providers.dart';
import 'package:diting/state/server_status_providers.dart';
import 'package:diting/state/settings_providers.dart';
import 'package:diting/state/work_mode_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/background_layer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// App root. Layer order matters: [ThemeCrossFade] relies on [ThemeData] comparing unequal on every
/// rebuild, so themes come from [AppThemeCache]; [AppScopes] must sit above the `Navigator` (in
/// `builder`), else overlay routes cannot resolve their scopes.
class DitingApp extends ConsumerStatefulWidget {
  const DitingApp({super.key, this.initialLocation});

  /// Test-only: start at a route directly instead of navigating there.
  final String? initialLocation;

  @override
  ConsumerState<DitingApp> createState() => _DitingAppState();
}

class _DitingAppState extends ConsumerState<DitingApp> {
  final _themes = AppThemeCache();
  late final GoRouter _router = createRouter(
    initialLocation: widget.initialLocation ?? Routes.home,
  );

  /// Foreground catch-up for auto update on start and resume: start-only starves backgrounded
  /// users, resume-only skips the first launch. `_autoUpdateChecking` is only a debounce; the due
  /// check lives in [AutoUpdateRunner].
  AppLifecycleListener? _lifecycle;
  bool _autoUpdateChecking = false;

  /// The update rewrites the rule tables in long transactions. Running it in the same seconds as
  /// the first frame's queries is what let a big subscription lock `diting_database` while the
  /// tunnel's log writers were opening it (2.1.7: 183 failed opens, zero successes). A few seconds
  /// of head start is enough for the first frame and is invisible to the user.
  static const _autoUpdateDelay = Duration(seconds: 5);

  Timer? _autoUpdateDelayTimer;

  /// Fires at the next due moment while the app stays in the foreground, so a daily slot is met
  /// without waiting for the next resume. Cancelled on pause: a backgrounded isolate does not
  /// run timers reliably, and resume catches up anyway.
  Timer? _autoUpdateDueTimer;

  /// Retry delay when a manual update made the runner yield.
  static const _autoUpdateBusyRetry = Duration(minutes: 1);

  /// Icons are fetched ahead of the first app list, but after startup has settled so the batches
  /// do not compete with the first frame's queries.
  static const _appIconsWarmDelay = Duration(seconds: 3);

  Timer? _appIconsWarmTimer;

  /// Needed because this state sits above `MaterialApp`: the snack bar that reports a silent
  /// log-write failure has no `ScaffoldMessenger` ancestor here.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Only once per app run; a stuck database would otherwise re-toast on every resume.
  bool _dbHealthReported = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _onResume,
      onPause: _cancelAutoUpdateDue,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeApplyTileStart();
      _maybeRunAutoUpdate();
      _maybeApplyOnDemand();
      _maybeReportDbHealth();
      _scheduleAppIconsWarm();
    });
  }

  /// Reading the provider starts the fill; it is never disposed, so every app list opened later
  /// finds the icons already in memory. Gated on the agreement like every other startup reader.
  void _scheduleAppIconsWarm() {
    _appIconsWarmTimer?.cancel();
    _appIconsWarmTimer = Timer(_appIconsWarmDelay, () {
      if (mounted && _agreementAccepted) ref.read(appIconsProvider);
    });
  }

  void _onResume() {
    _maybeApplyTileStart();
    _maybeRunAutoUpdate();
    _maybeApplyOnDemand();
    _maybeReportDbHealth();
  }

  /// Nothing may reach the network or the tunnel before the first-run agreement is accepted;
  /// the gate widget only hides the UI, the runners are guarded here.
  bool get _agreementAccepted => ref.read(initialAgreementProvider);

  /// Applies the on-demand whitelist to the tunnel. The platform reports the joined SSID only on
  /// request, so start and resume are the two moments where the answer can have changed.
  Future<void> _maybeApplyOnDemand() async {
    if (!mounted || !_agreementAccepted) return;
    try {
      await ref.read(onDemandRunnerProvider).apply();
    } catch (_) {
      // A missing channel on desktop simply means there is no tunnel to switch.
    }
  }

  /// The quick settings tile starts the data plane itself whenever it can; when it cannot (no VPN
  /// consent, or no persisted start config yet) it opens the app with a one-shot request instead.
  /// Only a running service needs no work: a mid-transition one is left to settle on its own.
  Future<void> _maybeApplyTileStart() async {
    if (!mounted || !_agreementAccepted) return;
    if (!await ref.read(tileBridgeProvider).consumeStartRequest()) return;
    if (!mounted) return;
    if (ref.read(workModeProvider) == AppWorkMode.server) {
      if (ref.read(serverStatusProvider) == ServerStatus.stopped) {
        await ref.read(serverStatusProvider.notifier).toggle();
      }
      return;
    }
    if (ref.read(powerProvider) == PowerState.stopped) {
      await ref.read(powerProvider.notifier).toggle();
    }
  }

  /// A locked `diting_database` used to fail silently: log pages stayed empty and nothing said so.
  /// The native writers count what they dropped, so the first frame can say it out loud.
  Future<void> _maybeReportDbHealth() async {
    if (_dbHealthReported || !mounted || !_agreementAccepted) return;
    final health = await ref.read(dbWriteHealthProvider.notifier).refresh();
    if (!mounted || health.healthy) return;
    _dbHealthReported = true;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          currentL10n.dbWriteUnhealthy(
            health.droppedRows,
            health.openFailures,
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _autoUpdateDelayTimer?.cancel();
    _autoUpdateDueTimer?.cancel();
    _appIconsWarmTimer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Cancellable so a disposed tree leaves no pending timer behind (widget tests check that).
  void _maybeRunAutoUpdate() {
    if (_autoUpdateChecking || !mounted || !_agreementAccepted) {
      return;
    }
    _autoUpdateChecking = true;
    _autoUpdateDelayTimer = Timer(_autoUpdateDelay, _runAutoUpdate);
  }

  Future<void> _runAutoUpdate() async {
    _autoUpdateDelayTimer = null;
    try {
      if (!mounted || !_agreementAccepted) return;
      final run = await ref.read(autoUpdateRunnerProvider).runIfDue();
      if (!mounted) {
        return;
      }
      if (run.didRun) {
        // Only a real run refreshes the timestamp; a skip (not due / disabled)
        // must not be shown as "just updated".
        ref.read(autoUpdateLastRunProvider.notifier).record(run);
      }
      _armAutoUpdateDue(
        run.skip == AutoUpdateSkip.busy
            ? DateTime.now().add(_autoUpdateBusyRetry).millisecondsSinceEpoch
            : run.dueAt,
      );
    } finally {
      _autoUpdateChecking = false;
    }
  }

  void _cancelAutoUpdateDue() {
    _autoUpdateDueTimer?.cancel();
    _autoUpdateDueTimer = null;
  }

  /// One second of slack so the check lands after the slot, not a hair before it. A run that
  /// still reports "due now" (a row whose attempt was not recorded) waits the retry delay
  /// instead of spinning.
  void _armAutoUpdateDue(int? dueAt) {
    _cancelAutoUpdateDue();
    if (dueAt == null || !mounted) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    final wait = dueAt - DateTime.now().millisecondsSinceEpoch;
    _autoUpdateDueTimer = Timer(
      wait <= 0 ? _autoUpdateBusyRetry : Duration(milliseconds: wait + 1000),
      _maybeRunAutoUpdate,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Accepting the agreement is the one startup gate change that does not navigate itself
    // (`InitialAgreementGate` only hides the UI), so refresh the router to run the first-run
    // redirect. Mode selection and onboarding navigate on their own.
    ref.listen(initialAgreementProvider, (_, accepted) {
      if (accepted) {
        _router.refresh();
        _scheduleAppIconsWarm();
      }
    });
    // A new schedule moves the next due moment; re-check so the foreground timer follows it.
    ref.listen(
      autoUpdateSettingsProvider.select(
        (s) =>
            (s.enabled, s.intervalHours, s.schedule, s.timeMinutes, s.sinceMs),
      ),
      (_, _) => _maybeRunAutoUpdate(),
    );
    final mode = ref.watch(themeModeProvider);
    final palette = ref.watch(paletteProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final textScale = ref.watch(textScaleProvider);
    // Keeps the rule list in step with the work mode's data set (see ruleSnapshotSyncProvider).
    ref.watch(ruleSnapshotSyncProvider);
    // Font family: `null` follows the platform, otherwise `ThemeData.fontFamily` overrides the whole
    // text theme.
    final fontFamily = ref.watch(selectedFontFamilyProvider);
    // Custom background: a wallpaper behind the root, pages go transparent.
    final background = ref.watch(customBackgroundProvider);
    final backgroundUri = background.enabled ? background.currentUri : null;
    final showBackground = backgroundUri != null && backgroundUri.isNotEmpty;
    final pair = AppThemePair(
      seedColor: palette.effectiveSeed,
      pureBlack: pureBlack,
      transparentPage: showBackground,
      fontFamily: fontFamily,
    );

    return MaterialApp.router(
      // Localized from the same ARB resources as the pages, so the task switcher follows the
      // selected language too.
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      routerConfig: _router,
      themeMode: switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      theme: _themes.of(pair.lightSpec),
      darkTheme: _themes.of(pair.darkSpec),
      localizationsDelegates: const [
        AppUiLocalizations.delegate,
        AppL10n.delegate,
        // `DefaultMaterialLocalizations` is English only; zh_CN needs the generated globals or
        // AppBar throws "No MaterialLocalizations".
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppL10n.supportedLocales,
      // `null` follows the device language; unsupported ones fall back to the first supported
      // locale, Chinese.
      locale: ref.watch(appLocaleProvider),
      builder: (context, child) {
        // Keeps the context-free [currentL10n] in step for providers and models that format a
        // message outside a widget.
        setCurrentL10n(AppL10n.of(context));
        // `child` is the Navigator; all scopes sit above it. `LiquidGlassScope` and
        // `LiquidGlassHost` are a pair, else panes fall back to tint + border. The agreement
        // gate lives here so it also covers overlay routes.
        final glass = ref.watch(liquidGlassModeProvider);
        // Below the Navigator, so every page's transparent fill shows the same wallpaper.
        final content = child ?? const SizedBox.shrink();
        return ThemeCrossFade(
          child: AppSystemUi(
            child: AppScopes(
              textScale: textScale,
              child: LiquidGlassScope(
                enabled: glass.enabled,
                quality: glass.quality,
                child: LiquidGlassHost(
                  enabled: glass.enabled,
                  child: InitialAgreementGate(
                    child: showBackground
                        ? AppBackgroundLayer(uri: backgroundUri, child: content)
                        : content,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
