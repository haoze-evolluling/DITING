/// Full-screen copies of the tab pages that the feature hub links to.
///
/// The hub used to send "日志 / 应用流量 / 网络工具 / 设置" through `goBranch`, which switches
/// tabs: the bottom bar stayed on screen and the title bar had no back arrow, so the only way out
/// was another tab. These routes push the same widgets on the root navigator instead, which hides
/// the bar (it belongs to `AppShell`) and gives the title bar a back button, because
/// `impliesAppBarDismissal` is true for a pushed page.
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

/// Tab roots as registered in `lib/router.dart`; kept as literals so this file does not import the
/// router that assembles it.
const _tabRoots = <String, String>{
  '/logs': StandalonePaths.logs,
  '/traffic': StandalonePaths.traffic,
  '/tools': StandalonePaths.tools,
  '/settings': StandalonePaths.settings,
};

/// Maps a tab root to its full-screen twin; null for anything that is not a tab root.
String? standaloneOf(String location) => _tabRoots[location];

/// Pushes [location] full screen when it is a tab root, so entry points that are not the bottom
/// bar never show the bar. Returns false when the caller should use its normal navigation.
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
