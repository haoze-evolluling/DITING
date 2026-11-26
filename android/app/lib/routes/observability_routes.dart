import 'package:diting_android/pages/observability/request_export_page.dart';
import 'package:diting_android/pages/observability/requests_page.dart';
import 'package:diting_android/routes/page.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class ObservabilityPaths {
  static const requests = '/requests';

  static const requestExport = '/requests/export';

  static const requestApps = '/requests/apps';

  static String appRequests(String packageName) =>
      '$requestApps/${Uri.encodeComponent(packageName)}';
}

List<RouteBase> observabilityRoutes() => [
  GoRoute(
    path: ObservabilityPaths.requests,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const RequestsPage()),
  ),
  GoRoute(
    path: ObservabilityPaths.requestExport,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const RequestLogExportPage()),
  ),
  GoRoute(
    path: ObservabilityPaths.requestApps,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const RequestAppsPage()),
  ),
  GoRoute(
    path: '${ObservabilityPaths.requestApps}/:packageName',
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => androidDefaultPage(
      state,
      AppRequestsPage(packageName: state.pathParameters['packageName'] ?? ''),
    ),
  ),
];
