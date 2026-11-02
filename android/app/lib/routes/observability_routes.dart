import 'package:diting_android/pages/observability/requests_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// Observability routes.
/// `/dns-queries` was dropped: it duplicated `/requests` with source = DNS.
/// `/connections` and `/resources` were dropped: they had no backing data source
/// and only rendered placeholder rows.
abstract final class ObservabilityPaths {
  /// Request log: upstream `RequestLogScreen`.
  static const requests = '/requests';

  /// Apps found in the request log, each leading to [appRequests].
  static const requestApps = '/requests/apps';

  /// Requests of one app.
  static String appRequests(String packageName) =>
      '$requestApps/${Uri.encodeComponent(packageName)}';
}

/// Observability routes.
List<RouteBase> observabilityRoutes() => [
  GoRoute(
    path: ObservabilityPaths.requests,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const RequestsPage()),
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
