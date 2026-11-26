import 'package:diting_android/pages/config/user_agents_page.dart';
import 'package:diting_android/routes/page.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class ConfigPaths {
  static const userAgents = '/config/user-agents';
}

List<RouteBase> configRoutes() => [
  GoRoute(
    path: ConfigPaths.userAgents,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const UserAgentsConfigPage()),
  ),
];
