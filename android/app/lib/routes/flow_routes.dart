import 'package:diting_android/pages/network/connection_monitor_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class FlowPaths {
  static const root = '/network/flow';
}

List<RouteBase> flowRoutes() => [
  GoRoute(
    path: FlowPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ConnectionMonitorPage()),
  ),
];
