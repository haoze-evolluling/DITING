import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/home/dashboard/dashboard_board.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_android/pages/home/widgets/home_headline.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/log_refresh_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver, PageVisibilityMixin<HomePage> {
  SpeedSeriesNotifier? _speed;
  LogLiveRefreshNotifier? _logRefresh;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speed = ref.read(speedSeriesProvider.notifier);
    _logRefresh = ref.read(logLiveRefreshProvider.notifier);
  }

  @override
  void onPageVisibilityChanged(bool visible) {
    if (visible == _polling) return;
    _polling = visible;
    if (visible) {
      _speed?.attachPolling();
      _logRefresh?.attachPolling();
    } else {
      _speed?.detachPolling();
      _logRefresh?.detachPolling();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(powerProvider.notifier).syncStatus();
    }
  }

  @override
  void dispose() {
    if (_polling) {
      _speed?.detachPolling();
      _logRefresh?.detachPolling();
    }
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
    AppWorkMode.express => l10n.homeTitleExpress,
    AppWorkMode.server => l10n.homeTitleServer,
  };
}
