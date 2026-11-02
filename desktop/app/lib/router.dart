import 'package:diting_desktop/pages/about/desktop_about_page.dart';
import 'package:diting_desktop/pages/desktop_pages.dart';
import 'package:diting_desktop/pages/hub/desktop_adapters_page.dart';
import 'package:diting_desktop/pages/hub/desktop_cache_page.dart';
import 'package:diting_desktop/pages/hub/desktop_client_access_page.dart';
import 'package:diting_desktop/pages/hub/desktop_dns64_page.dart';
import 'package:diting_desktop/pages/hub/desktop_encrypted_page.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_config_page.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_lists_page.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_rules_page.dart';
import 'package:diting_desktop/pages/hub/desktop_lan_dns_page.dart';
import 'package:diting_desktop/pages/hub/desktop_schedule_page.dart';
import 'package:diting_desktop/pages/hub/desktop_privacy_page.dart';
import 'package:diting_desktop/pages/hub/desktop_query_log_page.dart';
import 'package:diting_desktop/pages/hub/desktop_services_page.dart';
import 'package:diting_desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting_desktop/pages/hub/desktop_rewrite_page.dart';
import 'package:diting_desktop/pages/hub/desktop_upstream_page.dart';
import 'package:diting_desktop/pages/home/desktop_home_page.dart';
import 'package:diting_desktop/pages/tools/desktop_rule_check_page.dart';
import 'package:diting_desktop/pages/settings/desktop_appearance_page.dart';
import 'package:diting_desktop/pages/settings/desktop_lan_web_page.dart';
import 'package:diting_desktop/pages/settings/desktop_service_page.dart';
import 'package:diting_desktop/pages/traffic/desktop_client_groups_page.dart';
import 'package:diting_desktop/shell/desktop_shell.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Desktop route table: [desktopBranchOrder], the desktop's own grouping of the shared paths. Only
/// the pages differ from Android's table, because their data sources do.
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
          // Driven by [desktopBranchOrder] so a path can never drift from the desktop information
          // architecture; the guard test compares the two lists.
          for (final location in desktopBranchOrder)
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

/// Branch root to page. Every [desktopBranchOrder] entry must be handled; the throw is a build-time
/// tripwire for a branch added to the table without a desktop page.
Widget _pageOf(String location) => switch (location) {
  Routes.home => const DesktopHomePage(),
  Routes.hub => const DesktopFeatureHubPage(),
  Routes.about => const DesktopAboutPage(),
  _ => throw StateError('No desktop page for branch $location'),
};

/// Sub-pages live inside the branch, so the branch's record (and its tab) stays current while the
/// page is open. Each one hangs off the branch that owns its entry, which is why the redirects of
/// the old six-branch table land under `home` and `hub` instead of keeping their old prefixes.
List<RouteBase> _subRoutesOf(String location) => switch (location) {
  Routes.home => [
    GoRoute(
      path: DesktopClientGroupsPage.path.substring(1),
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
      path: 'adapters',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopAdaptersPage()),
    ),
    GoRoute(
      path: 'lan-dns',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopLanDnsPage()),
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
    GoRoute(
      path: 'appearance',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopAppearancePage()),
    ),
    GoRoute(
      path: 'service',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopServicePage()),
    ),
    GoRoute(
      path: 'lan-web',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopLanWebPage()),
    ),
    GoRoute(
      path: 'client-access',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopClientAccessPage()),
    ),
    GoRoute(
      path: 'query-log',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopQueryLogPage()),
    ),
    GoRoute(
      path: 'rule-test',
      pageBuilder: (context, state) =>
          androidDefaultPage(state, const DesktopRuleCheckPage()),
    ),
  ],
  _ => const [],
};
