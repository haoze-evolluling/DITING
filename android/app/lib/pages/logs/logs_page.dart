import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_android/pages/logs/log_dashboard_board.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_android/state/log_dashboard_layout_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/log_refresh_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage>
    with PageVisibilityMixin<LogsPage> {
  LogLiveRefreshNotifier? _logRefresh;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(powerProvider.notifier).syncStatus();
    });
    _logRefresh = ref.read(logLiveRefreshProvider.notifier);
  }

  @override
  void onPageVisibilityChanged(bool visible) {
    if (visible == _polling) return;
    _polling = visible;
    if (visible) {
      _logRefresh?.attachPolling();
    } else {
      _logRefresh?.detachPolling();
    }
  }

  @override
  void dispose() {
    if (_polling) _logRefresh?.detachPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(logModeProvider);
    final editing = ref.watch(logDashboardEditingProvider);
    return DashboardDensityScopeHost(
      child: CommonScaffold(
        title: editing
            ? context.l10n.homeEditDashboard
            : context.l10n.logsDashboardTitle,
        primaryAction: IconButtonData(
          glyph: editing ? AppGlyphs.check : AppGlyphs.customize,
          tooltip: editing
              ? context.l10n.homeDone
              : context.l10n.homeEditDashboard,
          onPressed: () =>
              ref.read(logDashboardEditingProvider.notifier).toggle(),
        ),
        actions: [
          if (!editing) ...[
            IconButton(
              tooltip: context.l10n.logsModeTooltip,
              onPressed: () => context.push(HubPaths.logRetention),
              icon: const GlyphIcon(AppGlyphs.sliders),
            ),
            IconButton(
              tooltip: context.l10n.logsRefresh,
              onPressed: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
              icon: const GlyphIcon(AppGlyphs.refresh),
            ),
          ],
        ],
        body: PageBody(
          children: [
            const SizedBox(height: 8),
            LogDashboardBoard(mode: mode),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
