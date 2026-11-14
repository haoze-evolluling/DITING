import 'package:diting_android/pages/logs/logs_bootstrap_page.dart';
import 'package:diting_android/pages/logs/logs_cache_page.dart';
import 'package:diting_android/pages/logs/logs_race_page.dart';
import 'package:diting_android/pages/logs/logs_subscription_stats_page.dart';
import 'package:diting_android/pages/logs/hit_ranking_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// Drill-down pages behind the cards of the log dashboard.
abstract final class LogPaths {
  /// DNS cache table (upstream `DnsCacheScreen`).
  static const cache = '/logs/cache';

  /// Race ranking (upstream `RaceStatsScreen`).
  static const race = '/logs/race';

  /// Bootstrap DNS stats (upstream `BootstrapStatsScreen`).
  static const bootstrap = '/logs/bootstrap';

  /// Subscription interception stats (upstream `SubscriptionInterceptionStatsScreen`).
  static const subscriptionStats = '/logs/subscription-stats';

  /// R2 命中排行：被拦截最多的域名与命中原因。
  static const hitRanking = '/logs/hit-ranking';
}

/// Log drill-down routes. All hang off `rootNavigatorKey`, otherwise the
/// shell's nested navigator would keep the bottom dock visible.
List<RouteBase> logsRoutes() => [
  GoRoute(
    path: LogPaths.cache,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LogsCachePage()),
  ),
  GoRoute(
    path: LogPaths.race,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LogsRacePage()),
  ),
  GoRoute(
    path: LogPaths.bootstrap,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LogsBootstrapPage()),
  ),
  GoRoute(
    path: LogPaths.subscriptionStats,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LogsSubscriptionStatsPage()),
  ),
  GoRoute(
    path: LogPaths.hitRanking,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const HitRankingPage()),
  ),
];
