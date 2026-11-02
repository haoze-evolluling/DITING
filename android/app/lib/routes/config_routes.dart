import 'package:diting_android/pages/config/custom_resources_page.dart';
import 'package:diting_android/pages/config/on_demand_page.dart';
import 'package:diting_android/pages/config/user_agents_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// Custom resource routes: User-Agent and on-demand, both reached through
/// `/config/custom-resources` from the developer page.
abstract final class ConfigPaths {
  /// Entry page listing the two resource tables.
  static const customResources = '/config/custom-resources';
  static const userAgents = '/config/user-agents';
  static const onDemand = '/config/on-demand';
}

/// Config routes, assembled by `lib/router.dart`.
List<RouteBase> configRoutes() => [
  GoRoute(
    path: ConfigPaths.customResources,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const CustomResourcesConfigPage()),
  ),
  GoRoute(
    path: ConfigPaths.userAgents,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const UserAgentsConfigPage()),
  ),
  GoRoute(
    path: ConfigPaths.onDemand,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const OnDemandConfigPage()),
  ),
];
