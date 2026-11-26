import 'package:diting_android/pages/health/health_page.dart';
import 'package:diting_android/routes/page.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class HealthPaths {
  static const root = '/health';
}

List<RouteBase> healthRoutes() => [
  GoRoute(
    path: HealthPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const HealthPage()),
  ),
];
