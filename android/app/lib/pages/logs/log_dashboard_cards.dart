import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/log_dashboard_widgets.dart';
import 'package:diting_android/pages/home/dashboard/cards/log_list_cards.dart';
import 'package:diting_android/pages/home/dashboard/cards/traffic_monitor_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/traffic_structure_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_android/pages/logs/ai_insight_card.dart';
import 'package:diting_android/pages/logs/log_stats_card.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_android/routes/standalone_routes.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Builds one log dashboard card. [interactive] is false in edit mode, where no card navigates:
/// leaving the page mid-arrangement reads as a lost drag.
Widget buildLogDashboardCard(
  BuildContext context,
  LogDashboardWidget widget,
  LegacyLogMode mode, {
  bool interactive = true,
}) {
  VoidCallback? push(String path) =>
      interactive ? () => context.push(path) : null;
  return switch (widget) {
    LogDashboardWidget.hero => _HeroBlock(mode: mode),
    LogDashboardWidget.stats => LogStatsCard(
      onRecentActivity: push(ObservabilityPaths.requests),
    ),
    LogDashboardWidget.trafficMonitor => TrafficMonitorCard(
      // Full screen like the hub entry: the bar belongs to the shell, so only a push on the root
      // navigator hides it and gives the title bar a back arrow.
      onDetail: interactive
          ? () => pushStandalone(context, Routes.traffic)
          : null,
    ),
    LogDashboardWidget.requestOverview => const RequestOverviewCard(),
    LogDashboardWidget.filteredHighlight => const FilteredHighlightCard(),
    LogDashboardWidget.privacyMode => const PrivacyModeCard(),
    LogDashboardWidget.offModeMetric => const OffModeMetricCard(),
    LogDashboardWidget.resolutionPerf => const ResolutionPerfCard(),
    LogDashboardWidget.aiInsight => const AiInsightCard(),
    LogDashboardWidget.trafficStructure => LogTrafficStructureCard(
      mode: mode == LegacyLogMode.blockedAndErrors
          ? TrafficStructureMode.filtered
          : TrafficStructureMode.all,
    ),
    LogDashboardWidget.recentRequests => RecentRequestsLogCard(
      onDetail: push(ObservabilityPaths.requests),
    ),
    LogDashboardWidget.recentBlocked => FilteredRecentLogCard(
      onDetail: push(ObservabilityPaths.requests),
    ),
    LogDashboardWidget.cacheHotspots => CacheHotspotsCard(
      onDetail: push(LogPaths.cache),
    ),
    LogDashboardWidget.raceWinners => RaceWinnersCard(
      onDetail: push(LogPaths.race),
    ),
    LogDashboardWidget.bootstrapDns => BootstrapDnsCard(
      onDetail: push(LogPaths.bootstrap),
    ),
    LogDashboardWidget.ruleBlocks => RuleBlocksCard(
      onDetail: push(LogPaths.subscriptionStats),
    ),
  };
}

/// Bare title block in view mode; edit mode wraps it in a card so it can carry the edit bar.
class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.mode});

  final LegacyLogMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (title, description) = switch (mode) {
      LegacyLogMode.all => (
        l10n.logsRequestsDashboard,
        l10n.logsRequestsDashboardBody,
      ),
      LegacyLogMode.blockedAndErrors => (
        l10n.logsFocusedDashboard,
        l10n.logsFocusedDashboardBody,
      ),
      LegacyLogMode.off => (l10n.logsServiceOverview, l10n.logsPrivacyBody),
    };
    final editing = DashboardEditBar.of(context) != null;
    final hero = LogsDashboardHero(
      title: title,
      description: description,
      padding: editing
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(0, 8, 0, 4),
    );
    return editing ? DashboardCard(semanticLabel: title, child: hero) : hero;
  }
}
