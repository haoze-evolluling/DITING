import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/pages/home/dashboard/dashboard_board.dart';
import 'package:diting/pages/home/dashboard/dashboard_density.dart';
import 'package:diting/pages/home/widgets/home_headline.dart';
import 'package:diting/router.dart';
import 'package:diting/routes/routes.dart';
import 'package:diting/state/dashboard_providers.dart';
import 'package:diting/state/log_refresh_providers.dart';
import 'package:diting/state/server_status_providers.dart';
import 'package:diting/state/work_mode_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Home page / dashboard: power, tagline, then the editable card board. Server mode
/// does not branch here: app_shell swaps the whole tree and would double the bottom bar.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  /// Capture the notifier while mounted: dispose() cannot call ref.read, Riverpod 3
  /// throws when ref is used on an unmounted widget.
  SpeedSeriesNotifier? _speed;
  LogLiveRefreshNotifier? _logRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The provider's own timer drives the curve; home and /traffic share one series,
    // and a second timer would halve the 60-point window. Tests disable it.
    _speed = ref.read(speedSeriesProvider.notifier);
    _speed!.attachPolling();
    // Cache, bootstrap and log cards read tables the native writers fill while the tunnel
    // runs; without this timer they would only refresh on a manual bump. Tests disable it.
    _logRefresh = ref.read(logLiveRefreshProvider.notifier);
    _logRefresh!.attachPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The notification action can stop the tunnel while the app is in the
      // background; re-read the native status instead of trusting local state.
      ref.read(powerProvider.notifier).syncStatus();
      // Server mode can likewise be stopped in the background.
      ref.read(serverStatusProvider.notifier).syncStatus();
    }
  }

  @override
  void dispose() {
    _speed?.detachPolling();
    _logRefresh?.detachPolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(workModeProvider);
    final power = ref.watch(powerProvider);
    final editing = ref.watch(dashboardEditingProvider);
    return DashboardDensityScopeHost(
      child: CommonScaffold(
        title: editing
            ? context.l10n.homeEditDashboard
            : _titleOf(mode, context.l10n),
        primaryAction: IconButtonData(
          glyph: editing ? AppGlyphs.check : AppGlyphs.customize,
          tooltip: editing
              ? context.l10n.homeDone
              : context.l10n.homeEditDashboard,
          onPressed: () => ref.read(dashboardEditingProvider.notifier).toggle(),
        ),
        // The mode is already in the title, so the bar uses a round icon of the same
        // size as its neighbour instead of a text pill wedged between two buttons.
        actions: [
          if (!editing)
            IconButton(
              tooltip: context.l10n.homeSwitchWorkMode,
              onPressed: () => context.push(Routes.modeSelect),
              icon: const GlyphIcon(AppGlyphs.swap),
            ),
        ],
        body: PageBody(
          children: [
            // Edit mode hides the fixed blocks so only cards remain and the drag targets
            // are obvious.
            if (!editing)
              ...buildHomeHeadline(
                context: context,
                ref: ref,
                state: power,
                onPressed: () => ref.read(powerProvider.notifier).toggle(),
              ),
            DashboardBoard(
              actions: DashboardCardActions(
                onOpenDetail: (widget) {
                  final path = homeDetailPathOf(widget);
                  if (path != null) context.push(path);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _titleOf(AppWorkMode mode, AppL10n l10n) => switch (mode) {
    AppWorkMode.normal => l10n.homeTitleNormal,
    AppWorkMode.server => l10n.homeTitleServer,
    AppWorkMode.express => l10n.homeTitleExpress,
  };
}
