import 'package:diting_android/pages/config/user_agents_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// Resource routes reached from the feature hub. The former custom-resources wrapper page was
/// removed: its only remaining entry is the User-Agent editor, and the on-demand connection now
/// lives under `/automation/on-demand`.
abstract final class ConfigPaths {
  static const userAgents = '/config/user-agents';
}

/// Config routes, assembled by `lib/router.dart`.
List<RouteBase> configRoutes() => [
  GoRoute(
    path: ConfigPaths.userAgents,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const UserAgentsConfigPage()),
  ),
];
