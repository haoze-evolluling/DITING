import 'package:diting_android/pages/network/profiles/net_profile_page.dart';
import 'package:diting_android/routes/page.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class NetworkProfilePaths {
  static const root = '/network/profiles';
}

List<RouteBase> networkProfileRoutes() => [
  GoRoute(
    path: NetworkProfilePaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const NetProfilePage()),
  ),
];
