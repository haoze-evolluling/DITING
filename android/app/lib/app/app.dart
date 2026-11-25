import 'dart:async';

import 'package:diting_shared/app/bootstrap.dart';
import 'package:diting_android/app/initial_agreement.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/l10n/ui_strings.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/app/theme/manager.dart';
import 'package:diting_android/data/native/deep_link_bridge.dart';
import 'package:diting_android/data/native/tile_bridge.dart';
import 'package:diting_android/data/subscriptions/subscription_deeplink.dart';
import 'package:diting_android/router.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/auto_update_providers.dart';
import 'package:diting_android/state/auto_update_runner.dart';
import 'package:diting_android/state/db_health_providers.dart';
import 'package:diting_android/state/deep_link_providers.dart';
import 'package:diting_android/state/on_demand_runner.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/background_layer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DitingApp extends ConsumerStatefulWidget {
  const DitingApp({super.key, this.initialLocation});

  final String? initialLocation;

  @override
  ConsumerState<DitingApp> createState() => _DitingAppState();
}

class _DitingAppState extends ConsumerState<DitingApp> {
  final _themes = AppThemeCache();
  late final GoRouter _router = createRouter(
    initialLocation: widget.initialLocation ?? Routes.home,
  );

  AppLifecycleListener? _lifecycle;
  bool _autoUpdateChecking = false;

  static const _autoUpdateDelay = Duration(seconds: 5);

  Timer? _autoUpdateDelayTimer;

  Timer? _autoUpdateDueTimer;

  static const _autoUpdateBusyRetry = Duration(minutes: 1);

  /// 冷启动首帧后仍有一些可延后的探活/状态同步任务，统一放到这段时间之后再跑，
  /// 避免与用户第一次滑动争抢主线程。
  static const _deferredStartupDelay = Duration(milliseconds: 1500);

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  bool _dbHealthReported = false;

  Timer? _deferredStartupTimer;

  String? _deferredImportUrl;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _onResume,
      onPause: _cancelAutoUpdateDue,
    );
    ref.read(deepLinkBridgeProvider).listen(_handleDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupChecks(immediate: true);
      _deferredStartupTimer = Timer(
        _deferredStartupDelay,
        _runDeferredStartupChecks,
      );
    });
  }

  void _onResume() => _runStartupChecks();

  void _runStartupChecks({bool immediate = false}) {
    // 用户主动触发的入口（桌面磁贴、深链）必须第一时间处理。
    _maybeApplyTileStart();
    _maybeApplyDeepLink();
    _maybeRunAutoUpdate();
    if (immediate) return;
    _maybeApplyOnDemand();
    _maybeReportDbHealth();
  }

  /// 冷启动时把非关键任务推迟到首帧渲染完成、且用户没有在滑动时再执行，
  /// 避免启动初期的主线程被状态同步和数据库探活占满。
  void _runDeferredStartupChecks() {
    if (!mounted) return;
    ScrollActivityGate.whenIdle(() {
      if (!mounted) return;
      _maybeApplyOnDemand();
      _maybeReportDbHealth();
    });
  }

  bool get _agreementAccepted => ref.read(initialAgreementProvider);

  Future<void> _maybeApplyOnDemand() async {
    if (!mounted || !_agreementAccepted) return;
    try {
      await ref.read(onDemandRunnerProvider).apply();
    } catch (_) {
    }
  }

  Future<void> _maybeApplyTileStart() async {
    if (!mounted || !_agreementAccepted) return;
    if (!await ref.read(tileBridgeProvider).consumeStartRequest()) return;
    if (!mounted) return;
    if (ref.read(powerProvider) == PowerState.stopped) {
      await ref.read(powerProvider.notifier).toggle();
    }
  }

  Future<void> _maybeApplyDeepLink() async {
    if (!mounted) return;
    final link = await ref.read(deepLinkBridgeProvider).consumeInitialLink();
    if (link != null) _handleDeepLink(link);
  }

  void _handleDeepLink(String link) {
    if (!mounted) return;
    final url = parseSubscriptionDeepLink(link);
    if (url == null) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(currentL10n.deepLinkImportInvalid),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_agreementAccepted) {
      _deferredImportUrl = url;
      return;
    }
    _importSubscription(url);
  }

  void _importSubscription(String url) {
    ref.read(pendingSubscriptionImportProvider.notifier).set(url);
    _router.go(Routes.subscriptions);
  }

  Future<void> _maybeReportDbHealth() async {
    if (_dbHealthReported || !mounted || !_agreementAccepted) return;
    _dbHealthReported = true;
    final health = await ref.read(dbWriteHealthProvider.notifier).refresh();
    if (!mounted || health.healthy) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          currentL10n.dbWriteUnhealthy(health.droppedRows, health.openFailures),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _autoUpdateDelayTimer?.cancel();
    _autoUpdateDueTimer?.cancel();
    _deferredStartupTimer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

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
    ref.listen(initialAgreementProvider, (_, accepted) {
      if (accepted) {
        _router.refresh();
        final deferred = _deferredImportUrl;
        if (deferred != null) {
          _deferredImportUrl = null;
          _importSubscription(deferred);
        }
      }
    });
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
    final haptic = ref.watch(hapticProvider);
    final fontFamily = ref.watch(selectedFontFamilyProvider);
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
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppL10n.supportedLocales,
      locale: ref.watch(appLocaleProvider),
      builder: (context, child) {
        setCurrentL10n(AppL10n.of(context));
        final glass = ref.watch(liquidGlassModeProvider);
        final content = ScrollActivityScope(
          child: child ?? const SizedBox.shrink(),
        );
        return ThemeCrossFade(
          child: AppSystemUi(
            child: AppScopes(
              textScale: textScale,
              child: HapticFeedbackScope(
                enabled: haptic,
                child: AppHapticTapFeedback(
                  child: LiquidGlassScope(
                    enabled: glass.enabled,
                    quality: glass.quality,
                    child: LiquidGlassHost(
                      enabled: glass.enabled,
                      child: InitialAgreementGate(
                        child: showBackground
                            ? AppBackgroundLayer(
                                uri: backgroundUri,
                                child: content,
                              )
                            : content,
                      ),
                    ),
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
