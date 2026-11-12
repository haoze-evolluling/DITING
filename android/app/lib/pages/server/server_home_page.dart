import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/vpn/power_state.dart';
import 'package:diting_android/pages/home/widgets/home_power_button.dart';
import 'package:diting_android/pages/server/dashboard/server_dashboard_board.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_android/state/server_dashboard_layout_providers.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Server-mode home: the same dashboard language as the normal/express home (power headline plus
/// an editable card board), with server-specific widgets for state, upstream, LAN access, cache,
/// rules and the domain-rule tables. Replaces the legacy single-column overview.
class ServerHomePage extends ConsumerStatefulWidget {
  const ServerHomePage({super.key});

  @override
  ConsumerState<ServerHomePage> createState() => _ServerHomePageState();
}

class _ServerHomePageState extends ConsumerState<ServerHomePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // `ServerStatusNotifier.build` only probes the native side when the persisted `service_active`
    // flag is set. A direct sync on entry covers the edge where the service is already listening
    // but the flag was cleared (for example by a failed previous attempt).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(serverStatusProvider.notifier).syncStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Unlike the normal/express home (which observes the same lifecycle), server mode replaced that
  /// page with this one; without this hook a stop started from the notification or tile while the
  /// app was backgrounded would leave the UI claiming "running" until the next stats poll.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(serverStatusProvider.notifier).syncStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = ref.watch(serverDashboardEditingProvider);
    return DashboardDensityScopeHost(
      child: CommonScaffold(
        title: context.l10n.homeTitleServer,
        primaryAction: IconButtonData(
          glyph: editing ? AppGlyphs.check : AppGlyphs.customize,
          tooltip: editing
              ? context.l10n.homeDone
              : context.l10n.homeEditDashboard,
          onPressed: () =>
              ref.read(serverDashboardEditingProvider.notifier).toggle(),
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.homeSwitchWorkMode,
            onPressed: () => context.push(Routes.modeSelect),
            icon: const GlyphIcon(AppGlyphs.swap),
          ),
          IconButton(
            tooltip: context.l10n.serverModeSettings,
            onPressed: () => context.push(ServerPaths.settings),
            icon: const GlyphIcon(AppGlyphs.sliders),
          ),
        ],
        body: PageBody(
          children: [
            // Edit mode hides the fixed headline so only cards remain, matching the normal home.
            if (!editing) ..._headline(context, ref),
            const ServerDashboardBoard(),
            if (!editing)
              ListFooter(text: context.l10n.serverModeNote)
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Power button, listening address and the five-state sentence. Kept out of the card board so
  /// the main control never scrolls away behind the cards.
  List<Widget> _headline(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider);
    final errorDetail = ref.read(serverStatusProvider.notifier).lastError;
    final port = ref.watch(serverPortProvider);
    final busy =
        status == ServerStatus.starting || status == ServerStatus.stopping;
    return [
      const SizedBox(height: 4),
      HomePowerButton(
        state: _powerStateOf(status),
        busyLabel: busy
            ? context.l10n.serverBusyStarting
            : context.l10n.serverBusyStopping,
        runningLabel: context.l10n.serverRunning,
        stoppedLabel: context.l10n.serverStopped,
        onPressed: () => ref.read(serverStatusProvider.notifier).toggle(),
      ),
      Text(
        context.l10n.serverListening('$port'),
        textAlign: TextAlign.center,
        style: context.listCaptionStyle.copyWith(
          fontFeatures: appTabularFigures,
        ),
      ),
      _StatusText(status: status, errorDetail: errorDetail),
      const SizedBox(height: 8),
    ];
  }

  static PowerState _powerStateOf(ServerStatus status) => switch (status) {
    ServerStatus.stopped => PowerState.stopped,
    ServerStatus.starting => PowerState.starting,
    ServerStatus.running => PowerState.running,
    ServerStatus.stopping => PowerState.stopping,
    ServerStatus.error => PowerState.error,
  };
}

/// Five-state status sentence; colour and wording follow the state. A separate line because the
/// button only conveys "tappable" and a failure needs a readable sentence.
class _StatusText extends StatelessWidget {
  const _StatusText({required this.status, this.errorDetail});

  final ServerStatus status;

  /// The concrete failure the notifier captured (`lastError`); shown under the generic sentence so
  /// the user sees e.g. the bind error instead of a guessed "port may be in use".
  final String? errorDetail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (text, color) = switch (status) {
      ServerStatus.stopped => (
        context.l10n.serverStatusStopped,
        colorScheme.onSurfaceVariant,
      ),
      ServerStatus.starting => (
        context.l10n.serverStatusStarting,
        colorScheme.primary,
      ),
      ServerStatus.running => (
        context.l10n.serverStatusRunning,
        colorScheme.primary,
      ),
      ServerStatus.stopping => (
        context.l10n.serverStatusStopping,
        colorScheme.onSurfaceVariant,
      ),
      ServerStatus.error => (
        context.l10n.serverStatusErrorText,
        colorScheme.error,
      ),
    };
    final detail =
        status == ServerStatus.error ? errorDetail?.trim() ?? '' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyle.subheadline
                .of(context, emphasized: true)
                .copyWith(color: color),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppTextStyle.footnote.of(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
