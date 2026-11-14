import 'package:diting_android/pages/automation/automation_edit_page.dart';
import 'package:diting_android/pages/automation/automation_page.dart';
import 'package:diting_android/pages/automation/profiles_page.dart';
import 'package:diting_android/pages/automation/timetable_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// Automation surface (A1 / A3 / A12 / A14).
abstract final class AutomationPaths {
  static const root = '/automation';
  static const profiles = '/automation/profiles';
  static const timetable = '/automation/timetable';
  static String edit(String id) => '/automation/edit/$id';
}

List<RouteBase> automationRoutes() => [
  GoRoute(
    path: AutomationPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const AutomationPage()),
  ),
  GoRoute(
    path: AutomationPaths.profiles,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ProfilesPage()),
  ),
  GoRoute(
    path: AutomationPaths.timetable,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const TimetablePage()),
  ),
  GoRoute(
    path: '/automation/edit/:id',
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => androidDefaultPage(
      state,
      AutomationEditPage(ruleId: state.pathParameters['id'] ?? 'new'),
    ),
  ),
];
