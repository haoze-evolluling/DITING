import 'package:diting_android/pages/health/health_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// U1 保护健康评分页。
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
