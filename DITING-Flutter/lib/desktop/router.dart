import 'package:diting/desktop/pages/desktop_pages.dart';
import 'package:diting/desktop/pages/home/desktop_home_page.dart';
import 'package:diting/desktop/shell/desktop_shell.dart';
import 'package:diting/routes/branches.dart';
import 'package:diting/routes/page.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Desktop route table: the same six branches, in the same order, at the same paths as
/// `lib/router.dart` (see [branchOrder]). Only the pages differ, because their data sources do.
///
/// No first-run redirect: the agreement, work-mode and onboarding gates belong to the Android
/// startup flow, and a desktop session that has not accepted anything yet has no tunnel to guard.
GoRouter createDesktopRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            DesktopShell(navigationShell: navigationShell),
        branches: [
          // Driven by [branchOrder] so a path can never drift from the shared information
          // architecture; the guard test compares the two lists.
          for (final location in branchOrder)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: location,
                  pageBuilder: (context, state) =>
                      androidDefaultPage(state, _pageOf(location)),
                ),
              ],
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        DesktopUnknownRoutePage(location: state.uri.toString()),
  );
}

/// Branch root to page. Every [branchOrder] entry must be handled; the throw is a build-time
/// tripwire for a branch added to the shared table without a desktop page.
Widget _pageOf(String location) => switch (location) {
  Routes.home => const DesktopHomePage(),
  Routes.hub => const DesktopFeatureHubPage(),
  Routes.logs => const DesktopLogsPage(),
  Routes.traffic => const DesktopTrafficPage(),
  Routes.tools => const DesktopToolsPage(),
  Routes.settings => const DesktopSettingsPage(),
  _ => throw StateError('No desktop page for branch $location'),
};
