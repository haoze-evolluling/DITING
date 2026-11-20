import 'package:diting_android/pages/network/connection_rate_limit_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class ConnectionRateLimitPaths {
  static const root = '/network/connection-rate-limit';
}

List<RouteBase> connectionRateLimitRoutes() => [
  GoRoute(
    path: ConnectionRateLimitPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ConnectionRateLimitPage()),
  ),
];
