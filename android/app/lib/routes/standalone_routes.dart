library;

import 'package:diting_android/pages/logs/logs_page.dart';
import 'package:diting_android/pages/settings/settings_page.dart';
import 'package:diting_android/pages/tools/tools_page.dart';
import 'package:diting_android/pages/traffic/traffic_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

abstract final class StandalonePaths {
  static const logs = '/standalone/logs';
  static const traffic = '/standalone/traffic';
  static const tools = '/standalone/tools';
  static const settings = '/standalone/settings';
}

const _tabRoots = <String, String>{
  '/logs': StandalonePaths.logs,
  '/traffic': StandalonePaths.traffic,
  '/tools': StandalonePaths.tools,
  '/settings': StandalonePaths.settings,
};

String? standaloneOf(String location) => _tabRoots[location];

bool pushStandalone(BuildContext context, String location) {
  final path = standaloneOf(location);
  if (path == null) {
    return false;
  }
  context.push(path);
  return true;
}

List<RouteBase> standaloneRoutes() => [
  GoRoute(
    path: StandalonePaths.logs,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LogsPage()),
  ),
  GoRoute(
    path: StandalonePaths.traffic,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const TrafficPage()),
  ),
  GoRoute(
    path: StandalonePaths.tools,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ToolsPage()),
  ),
  GoRoute(
    path: StandalonePaths.settings,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const SettingsPage()),
  ),
];
