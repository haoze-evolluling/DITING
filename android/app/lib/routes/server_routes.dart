import 'package:diting_android/pages/server/server_cache_page.dart';
import 'package:diting_android/pages/server/server_cache_advanced_page.dart';
import 'package:diting_android/pages/server/server_filter_page.dart';
import 'package:diting_android/pages/server/server_filter_rules_page.dart';
import 'package:diting_android/pages/server/server_filter_subscriptions_page.dart';
import 'package:diting_android/pages/server/server_filter_test_page.dart';
import 'package:diting_android/pages/server/server_home_page.dart';
import 'package:diting_android/pages/server/server_hub_page.dart';
import 'package:diting_android/pages/server/server_logs_page.dart';
import 'package:diting_android/pages/server/server_query_log_page.dart';
import 'package:diting_android/pages/server/server_settings_page.dart';
import 'package:diting_android/pages/server/server_shell.dart';
import 'package:diting_android/pages/server/server_upstream_providers_page.dart';
import 'package:diting_android/pages/server/server_upstream_page.dart';
import 'package:diting_android/pages/server/server_upstream_bootstrap_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/shell/branch_transition_shell.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

abstract final class ServerRoutes {
  static const root = '/server';
  static const hub = '/server/hub';
  static const logs = '/server/logs';
  static const upstream = '/server/upstream';
  static const upstreamProviders = '/server/upstream/providers';
  static const upstreamBootstrap = '/server/upstream/bootstrap';
  static const filter = '/server/filter';
  static const filterRules = '/server/filter/rules';
  static const filterSubscriptions = '/server/filter/subscriptions';
  static const filterTest = '/server/filter/test';
  static const cache = '/server/cache';
  static const cacheAdvanced = '/server/cache/advanced';
  static const queryLog = '/server/query-log';
  static const settings = '/server/settings';
}

GoRoute _leaf(String path, Widget page) => GoRoute(
  path: path,
  parentNavigatorKey: rootNavigatorKey,
  pageBuilder: (context, state) => androidDefaultPage(state, page),
);

List<RouteBase> serverRoutes() => [
  StatefulShellRoute(
    pageBuilder: (context, state, navigationShell) => RootShellPage<void>(
      key: state.pageKey,
      name: state.name,
      child: ServerDockShell(navigationShell: navigationShell),
    ),
    navigatorContainerBuilder: (context, navigationShell, children) =>
        BranchTransitionShell(
          navigationShell: navigationShell,
          children: children,
        ),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: ServerRoutes.root,
            builder: (context, state) => const ServerHomePage(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: ServerRoutes.hub,
            builder: (context, state) => const ServerHubPage(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: ServerRoutes.logs,
            builder: (context, state) => const ServerLogsPage(),
          ),
        ],
      ),
    ],
  ),
  _leaf(ServerRoutes.upstream, const ServerUpstreamPage()),
  _leaf(ServerRoutes.upstreamProviders, const ServerUpstreamProvidersPage()),
  _leaf(ServerRoutes.upstreamBootstrap, const ServerUpstreamBootstrapPage()),
  _leaf(ServerRoutes.filter, const ServerFilterPage()),
  _leaf(ServerRoutes.filterRules, const ServerFilterRulesPage()),
  _leaf(
    ServerRoutes.filterSubscriptions,
    const ServerFilterSubscriptionsPage(),
  ),
  _leaf(ServerRoutes.filterTest, const ServerFilterTestPage()),
  _leaf(ServerRoutes.cache, const ServerCachePage()),
  _leaf(ServerRoutes.cacheAdvanced, const ServerCacheAdvancedPage()),
  _leaf(ServerRoutes.queryLog, const ServerQueryLogPage()),
  _leaf(ServerRoutes.settings, const ServerSettingsPage()),
];
