import 'package:diting_android/pages/tools/tools_page.dart';
import 'package:diting_android/routes/tools_paths.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// The four probe tools, pushed as full pages over the tools tab. Their routes live here rather
/// than under the tab's `GoRoute` so the bottom dock disappears and the title bar gains a back
/// arrow.
List<RouteBase> toolsRoutes() => [
  GoRoute(
    path: ToolPaths.speedTest,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const SpeedTestPage()),
  ),
  GoRoute(
    path: ToolPaths.ping,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const PingTestPage()),
  ),
  GoRoute(
    path: ToolPaths.dnsLookup,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const DnsLookupPage()),
  ),
  GoRoute(
    path: ToolPaths.traceroute,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const TraceroutePage()),
  ),
];
