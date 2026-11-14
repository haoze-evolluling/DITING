import 'package:diting_android/pages/network/local_api_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// A10 本地 HTTP API 设置。
abstract final class LocalApiPaths {
  static const root = '/network/local-api';
}

List<RouteBase> localApiRoutes() => [
  GoRoute(
    path: LocalApiPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LocalApiPage()),
  ),
];
