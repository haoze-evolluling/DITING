import 'package:diting_android/pages/server/server_filter_page.dart';
import 'package:diting_android/pages/server/server_filter_rules_page.dart';
import 'package:diting_android/pages/server/server_filter_test_page.dart';
import 'package:diting_android/pages/server/server_query_log_page.dart';
import 'package:diting_android/pages/server/server_settings_page.dart';
import 'package:diting_android/pages/server/server_upstream_advanced_page.dart';
import 'package:diting_android/pages/server/server_upstream_providers_page.dart';
import 'package:diting_android/pages/server/server_upstream_page.dart';
import 'package:diting_android/pages/server/server_upstream_bootstrap_page.dart';
import 'package:diting_android/pages/subscriptions/subscriptions_page.dart';
import 'package:diting_android/routes/branches.dart';
import 'package:diting_android/routes/page.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 服务器模式复用普通 Shell 的三个主入口，只有配置子页保留独立路径。
abstract final class ServerRoutes {
  static const root = Routes.home;
  static const hub = Routes.hub;
  static const logs = Routes.logs;
  static const upstream = '/server/upstream';
  static const upstreamAdvanced = '/server/upstream/advanced';
  static const upstreamProviders = '/server/upstream/providers';
  static const upstreamBootstrap = '/server/upstream/bootstrap';
  static const filter = '/server/filter';
  static const filterRules = '/server/filter/rules';
  static const filterSubscriptions = '/server/filter/subscriptions';
  static const filterTest = '/server/filter/test';
  static const queryLog = '/server/query-log';
  static const settings = '/server/settings';
}

GoRoute _leaf(String path, Widget page) => GoRoute(
  path: path,
  parentNavigatorKey: rootNavigatorKey,
  pageBuilder: (context, state) => androidDefaultPage(state, page),
);

List<RouteBase> serverRoutes() => [
  _leaf(ServerRoutes.upstream, const ServerUpstreamPage()),
  _leaf(ServerRoutes.upstreamAdvanced, const ServerUpstreamAdvancedPage()),
  _leaf(ServerRoutes.upstreamProviders, const ServerUpstreamProvidersPage()),
  _leaf(ServerRoutes.upstreamBootstrap, const ServerUpstreamBootstrapPage()),
  _leaf(ServerRoutes.filter, const ServerFilterPage()),
  _leaf(ServerRoutes.filterRules, const ServerFilterRulesPage()),
  // 订阅与普通/简洁模式共用同一套页面与规则库。
  _leaf(ServerRoutes.filterSubscriptions, const SubscriptionsPage()),
  _leaf(ServerRoutes.filterTest, const ServerFilterTestPage()),
  _leaf(ServerRoutes.queryLog, const ServerQueryLogPage()),
  _leaf(ServerRoutes.settings, const ServerSettingsPage()),
];
