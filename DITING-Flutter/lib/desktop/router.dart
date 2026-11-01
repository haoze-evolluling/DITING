import 'package:diting/desktop/pages/desktop_pages.dart';
import 'package:diting/desktop/pages/hub/desktop_cache_page.dart';
import 'package:diting/desktop/pages/hub/desktop_dns64_page.dart';
import 'package:diting/desktop/pages/hub/desktop_encrypted_page.dart';
import 'package:diting/desktop/pages/hub/desktop_filter_config_page.dart';
import 'package:diting/desktop/pages/hub/desktop_filter_lists_page.dart';
import 'package:diting/desktop/pages/hub/desktop_filter_rules_page.dart';
import 'package:diting/desktop/pages/hub/desktop_schedule_page.dart';
import 'package:diting/desktop/pages/hub/desktop_privacy_page.dart';
import 'package:diting/desktop/pages/hub/desktop_services_page.dart';
import 'package:diting/desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting/desktop/pages/hub/desktop_rewrite_page.dart';
import 'package:diting/desktop/pages/hub/desktop_upstream_page.dart';
import 'package:diting/desktop/pages/home/desktop_home_page.dart';
import 'package:diting/desktop/pages/tools/desktop_rule_check_page.dart';
import 'package:diting/desktop/pages/settings/desktop_appearance_page.dart';
import 'package:diting/desktop/pages/settings/desktop_settings_page.dart';
import 'package:diting/desktop/pages/tools/desktop_tools_page.dart';
import 'package:diting/desktop/pages/traffic/desktop_client_groups_page.dart';
import 'package:diting/desktop/pages/traffic/desktop_traffic_page.dart';
import 'package:diting/desktop/pages/logs/desktop_logs_page.dart';
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
                  routes: _subRoutesOf(location),
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

/// Sub-pages live inside the branch, so the branch's record (and its tab) stays current while the
/// page is open. Only branches that actually have sub-pages return routes.
List<RouteBase> _subRoutesOf(String location) => switch (location) {
  Routes.settings => [
    GoRoute(
      path: 'appearance',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopAppearancePage()),
    ),
  ],
  Routes.tools => [
    GoRoute(
      path: 'rule-test',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopRuleCheckPage()),
    ),
  ],
  Routes.traffic => [
    GoRoute(
      path: 'groups',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopClientGroupsPage()),
    ),
  ],
  Routes.hub => [
    GoRoute(
      path: 'upstream',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopUpstreamPage()),
    ),
    GoRoute(
      path: 'cache',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopCachePage()),
    ),
    GoRoute(
      path: 'rewrite',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopRewritePage()),
    ),
    GoRoute(
      path: 'dns64',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopDns64Page()),
    ),
    GoRoute(
      path: 'filter-lists',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopFilterListsPage()),
    ),
    GoRoute(
      path: 'filter-rules',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopFilterRulesPage()),
    ),
    GoRoute(
      path: 'filter-config',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopFilterConfigPage()),
    ),
    GoRoute(
      path: 'filter-schedule',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopSchedulePage()),
    ),
    GoRoute(
      path: 'filter-services',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopServicesPage()),
    ),
    GoRoute(
      path: 'privacy',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopPrivacyPage()),
    ),
    GoRoute(
      path: 'encrypted-dns',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopEncryptedPage()),
    ),
  ],
  _ => const [],
};
