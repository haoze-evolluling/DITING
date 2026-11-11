import 'package:diting_android/pages/server/server_settings_page.dart';
import 'package:diting_android/pages/server/server_upstream_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/navigator.dart';
import 'package:go_router/go_router.dart';

/// Server-mode pages that used to be dock tabs. They are now opened from the feature center, so
/// they live as pushed routes (full screen with a back arrow) instead of shell branches.
abstract final class ServerPaths {
  static const upstream = '/server/upstream';
  static const settings = '/server/settings';
}

List<RouteBase> serverRoutes() => [
  GoRoute(
    path: ServerPaths.upstream,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ServerUpstreamPage()),
  ),
  GoRoute(
    path: ServerPaths.settings,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ServerSettingsPage()),
  ),
];
