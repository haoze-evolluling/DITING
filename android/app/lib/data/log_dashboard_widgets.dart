library;

import 'package:diting_shared/app/l10n/l10n.dart';

/// Cards of the log dashboard (`/logs`). Each log mode offers its own subset, see
/// `logDashboardCatalogOf`; persisted by [name], so renaming a value drops it from stored layouts.
enum LogDashboardWidget {
  /// Title and description block at the top; its text follows the log mode.
  hero,

  /// Request and data-usage totals over a picked window, with proportion bars.
  stats,
  trafficMonitor,
  requestOverview,
  filteredHighlight,
  privacyMode,
  offModeMetric,
  resolutionPerf,

  /// Only offered while an agent API key is configured.
  aiInsight,
  trafficStructure,
  recentRequests,
  recentBlocked,
  cacheHotspots,
  raceWinners,
  bootstrapDns,
  ruleBlocks;

  String label(AppL10n l10n) => switch (this) {
    LogDashboardWidget.hero => l10n.logDashboardCardHero,
    LogDashboardWidget.stats => l10n.logStatsTitle,
    LogDashboardWidget.trafficMonitor => l10n.trafficMonitorTitle,
    LogDashboardWidget.requestOverview => l10n.logRequestsOverview,
    LogDashboardWidget.filteredHighlight => l10n.logHighlights,
    LogDashboardWidget.privacyMode => l10n.logPrivacyMode,
    LogDashboardWidget.offModeMetric => l10n.logOffModeTitle,
    LogDashboardWidget.resolutionPerf => l10n.logPerfTitle,
    LogDashboardWidget.aiInsight => l10n.logsAiInsight,
    LogDashboardWidget.trafficStructure =>
      l10n.logDashboardCardTrafficStructure,
    LogDashboardWidget.recentRequests => l10n.logRecentRequests,
    LogDashboardWidget.recentBlocked => l10n.logRecentBlocked,
    LogDashboardWidget.cacheHotspots => l10n.logCacheHotspots,
    LogDashboardWidget.raceWinners => l10n.logRaceWinners,
    LogDashboardWidget.bootstrapDns => 'Bootstrap DNS',
    LogDashboardWidget.ruleBlocks => l10n.logRuleBlocks,
  };

  String description(AppL10n l10n) => switch (this) {
    LogDashboardWidget.hero => l10n.logDashboardCardHeroDescription,
    LogDashboardWidget.stats => l10n.logDashboardCardStatsDescription,
    LogDashboardWidget.trafficMonitor =>
      l10n.logDashboardCardTrafficMonitorDescription,
    LogDashboardWidget.requestOverview =>
      l10n.logDashboardCardRequestOverviewDescription,
    LogDashboardWidget.filteredHighlight =>
      l10n.logDashboardCardHighlightDescription,
    LogDashboardWidget.privacyMode => l10n.logDashboardCardPrivacyDescription,
    LogDashboardWidget.offModeMetric =>
      l10n.logDashboardCardOffMetricDescription,
    LogDashboardWidget.resolutionPerf => l10n.logDashboardCardPerfDescription,
    LogDashboardWidget.aiInsight => l10n.logDashboardCardAiDescription,
    LogDashboardWidget.trafficStructure =>
      l10n.logDashboardCardTrafficStructureDescription,
    LogDashboardWidget.recentRequests =>
      l10n.logDashboardCardRecentRequestsDescription,
    LogDashboardWidget.recentBlocked =>
      l10n.logDashboardCardRecentBlockedDescription,
    LogDashboardWidget.cacheHotspots => l10n.logDashboardCardCacheDescription,
    LogDashboardWidget.raceWinners => l10n.logDashboardCardRaceDescription,
    LogDashboardWidget.bootstrapDns =>
      l10n.logDashboardCardBootstrapDescription,
    LogDashboardWidget.ruleBlocks => l10n.logDashboardCardRuleBlocksDescription,
  };
}
