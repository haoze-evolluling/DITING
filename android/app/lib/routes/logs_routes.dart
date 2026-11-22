import 'package:diting_android/pages/logs/logs_bootstrap_page.dart';
import 'package:diting_android/pages/logs/logs_cache_page.dart';
import 'package:diting_android/pages/logs/logs_race_page.dart';
import 'package:diting_android/pages/logs/logs_subscription_stats_page.dart';
import 'package:diting_android/pages/logs/hit_ranking_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class LogPaths {
  static const cache = '/logs/cache';

  static const race = '/logs/race';

  static const bootstrap = '/logs/bootstrap';

  static const subscriptionStats = '/logs/subscription-stats';

  static const hitRanking = '/logs/hit-ranking';
}

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
