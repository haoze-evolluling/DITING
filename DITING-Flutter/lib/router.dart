import 'package:diting/pages/about/about_page.dart';
import 'package:diting/pages/home/home_page.dart';
import 'package:diting/pages/hub/feature_hub_page.dart';
import 'package:diting/pages/logs/logs_page.dart';
import 'package:diting/pages/mode/mode_onboarding_page.dart';
import 'package:diting/pages/mode/mode_select_page.dart';
import 'package:diting/pages/rules/batch_editor_page.dart';
import 'package:diting/pages/rules/rules_page.dart';
import 'package:diting/pages/settings/settings_page.dart';
import 'package:diting/pages/subscriptions/subscriptions_page.dart';
import 'package:diting/pages/system/unknown_route_page.dart';
import 'package:diting/pages/tools/tools_page.dart';
import 'package:diting/pages/traffic/traffic_page.dart';
import 'package:diting/routes/branches.dart';
import 'package:diting/routes/routes.dart';
import 'package:diting/routes/standalone_routes.dart';
import 'package:diting/shell/app_shell.dart';
import 'package:diting/state/settings_providers.dart';
import 'package:diting/state/work_mode_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// The branch paths and tab helpers live in `routes/branches.dart` so the desktop shell can share
// them without importing the Android pages below.
export 'package:diting/routes/branches.dart';

/// First-run gate, mirroring legacy `MainWorkModeCoordinator.checkStartupOnboarding`: the
/// agreement dialog owns the very first step, then an unchosen work mode goes to mode selection
/// and an unfinished guide to onboarding. Returning a location on every navigation is what keeps
/// a first-run user from reaching the home page before the guide; the mode and onboarding pages
/// are allowed through so their own flow can run.
String? startupOnboardingRedirect(BuildContext context, GoRouterState state) {
  // Redirects get no `WidgetRef`; the scope is above the router (see `DitingApp`).
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.read(initialAgreementProvider)) {
    return null;
  }
  final location = state.matchedLocation;
  if (!container.read(workModeSelectedProvider)) {
    return location == Routes.modeSelect ? null : Routes.modeSelect;
  }
  if (!container.read(onboardingProvider)) {
    return location == Routes.modeOnboarding ? null : Routes.modeOnboarding;
  }
  return null;
}

GoRouter createRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    navigatorKey: rootNavigatorKey,
    redirect: startupOnboardingRedirect,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.hub,
                builder: (context, state) => const FeatureHubPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.logs,
                builder: (context, state) => const LogsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.traffic,
                builder: (context, state) => const TrafficPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.tools,
                builder: (context, state) => const ToolsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.batchEditor,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            androidDefaultPage(state, const BatchEditorPage()),
      ),
      GoRoute(
        path: '${Routes.rules}/:kind',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => androidDefaultPage(
          state,
          RulesPage(kind: state.pathParameters['kind'] ?? 'block'),
        ),
      ),
      GoRoute(
        path: Routes.subscriptions,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            androidDefaultPage(state, const SubscriptionsPage()),
      ),
      GoRoute(
        path: Routes.about,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            androidDefaultPage(state, const AboutPage()),
      ),
      GoRoute(
        path: Routes.modeSelect,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            androidDefaultPage(state, const ModeSelectPage()),
      ),
      GoRoute(
        path: Routes.modeOnboarding,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            androidDefaultPage(state, const ModeOnboardingPage()),
      ),
      // Domain routes live in `lib/routes/<domain>_routes.dart`; a new domain
      // means one more `...<domain>Routes()` entry here.
      ...dashboardRoutes(),
      ...homeDetailRoutes(),
      ...hubRoutes(),
      ...logsRoutes(),
      ...observabilityRoutes(),
      ...configRoutes(),
      ...systemRoutes(),
      ...standaloneRoutes(),
    ],
    // Without this, unmatched routes render a blank page instead of failing, so a missing
    // registration goes unnoticed. `UnknownRoutePage` shows "page not found".
    errorBuilder: (context, state) =>
        UnknownRoutePage(location: state.uri.toString()),
  );
}
