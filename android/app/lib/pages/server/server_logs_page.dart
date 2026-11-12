/// Server-mode log dashboard.
///
/// Mirrors the normal/express log dashboards in look and card language, but only offers the cards
/// that make sense without a VPN tunnel: DNS request totals, recent requests and blocks, rule
/// sources, cache hotspots, race winners and bootstrap DNS. Traffic bytes and HTTPS inspection are
/// deliberately absent.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/home/dashboard/cards/log_list_cards.dart';
import 'package:diting_android/pages/logs/log_stats_card.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/routes/logs_routes.dart';
import 'package:diting_android/routes/observability_routes.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/log_refresh_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerLogsPage extends ConsumerStatefulWidget {
  const ServerLogsPage({super.key, this.active = true});

  /// The shell keeps all tabs mounted; only the visible one should poll.
  final bool active;

  @override
  ConsumerState<ServerLogsPage> createState() => _ServerLogsPageState();
}

class _ServerLogsPageState extends ConsumerState<ServerLogsPage> {
  LogLiveRefreshNotifier? _logRefresh;
  bool _attached = false;

  @override
  void initState() {
    super.initState();
    _logRefresh = ref.read(logLiveRefreshProvider.notifier);
    _syncPolling();
    // The first frame should show rows written while the page was offstage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(dnsLogRevisionProvider.notifier).bump();
    });
  }

  @override
  void didUpdateWidget(covariant ServerLogsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncPolling();
    }
  }

  void _syncPolling() {
    if (widget.active && !_attached) {
      _attached = true;
      _logRefresh?.attachPolling();
    } else if (!widget.active && _attached) {
      _attached = false;
      _logRefresh?.detachPolling();
    }
  }

  @override
  void dispose() {
    if (_attached) _logRefresh?.detachPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final side = dashboardMobileSideOf(MediaQuery.sizeOf(context).width);
    VoidCallback open(String path) =>
        () => context.push(path);
    return DashboardDensityScopeHost(
      child: CommonScaffold(
        title: l10n.logsDashboardTitle,
        actions: [
          IconButton(
            tooltip: l10n.logsRefresh,
            onPressed: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
            icon: const GlyphIcon(AppGlyphs.refresh),
          ),
        ],
        body: PageBody(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: dashboardCardGap,
                children: [
                  LogsDashboardHero(
                    title: l10n.serverLogsTitle,
                    description: l10n.serverLogsBody,
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                  ),
                  LogStatsCard(
                    showData: false,
                    onRecentActivity: open(ObservabilityPaths.requests),
                  ),
                  RecentRequestsLogCard(
                    onDetail: open(ObservabilityPaths.requests),
                  ),
                  FilteredRecentLogCard(
                    onDetail: open(ObservabilityPaths.requests),
                  ),
                  CacheHotspotsCard(onDetail: open(LogPaths.cache)),
                  RaceWinnersCard(onDetail: open(LogPaths.race)),
                  BootstrapDnsCard(onDetail: open(LogPaths.bootstrap)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
