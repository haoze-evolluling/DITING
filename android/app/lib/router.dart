import 'package:diting_android/pages/about/about_page.dart';
import 'package:diting_android/pages/home/home_page.dart';
import 'package:diting_android/pages/hub/feature_hub_page.dart';
import 'package:diting_android/pages/logs/logs_page.dart';
import 'package:diting_android/pages/mode/mode_onboarding_page.dart';
import 'package:diting_android/pages/mode/mode_select_page.dart';
import 'package:diting_android/pages/rules/batch_editor_page.dart';
import 'package:diting_android/pages/rules/rules_page.dart';
import 'package:diting_android/pages/settings/settings_page.dart';
import 'package:diting_android/pages/subscriptions/subscriptions_page.dart';
import 'package:diting_android/pages/system/unknown_route_page.dart';
import 'package:diting_android/pages/tools/tools_page.dart';
import 'package:diting_android/pages/traffic/traffic_page.dart';
import 'package:diting_android/routes/branches.dart';
import 'package:diting_android/shell/branch_transition_shell.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_android/routes/standalone_routes.dart';
import 'package:diting_android/routes/tools_routes.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/shell/dock_shell.dart';
import 'package:diting_android/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

export 'package:diting_android/routes/branches.dart';

String? startupOnboardingRedirect(BuildContext context, GoRouterState state) {
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
  if (container.read(workModeProvider) == AppWorkMode.server) {
    if (_mainShellRoots.contains(location)) return Routes.server;
  } else if (location == Routes.server ||
      location.startsWith('${Routes.server}/')) {
    return Routes.home;
  }
  return null;
}

const _mainShellRoots = {
  Routes.home,
  Routes.hub,
  Routes.logs,
  Routes.traffic,
  Routes.tools,
  Routes.settings,
};

GoRouter createRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    navigatorKey: rootNavigatorKey,
    redirect: startupOnboardingRedirect,
    routes: [
      StatefulShellRoute(
        pageBuilder: (context, state, navigationShell) => RootShellPage<void>(
          key: state.pageKey,
          name: state.name,
          child: DockShell(navigationShell: navigationShell),
        ),
        navigatorContainerBuilder: (context, navigationShell, children) =>
            BranchTransitionShell(
              navigationShell: navigationShell,
              children: children,
            ),
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
      ...dashboardRoutes(),
      ...homeDetailRoutes(),
      ...hubRoutes(),
      ...healthRoutes(),
      ...flowRoutes(),
      ...privacySuiteRoutes(),
      ...dns64Routes(),
      ...connectionRateLimitRoutes(),
      ...subscriptionFormRoutes(),
      ...subscriptionVersionRoutes(),
      ...networkDiagnosticsRoutes(),
      ...toolsRoutes(),
      ...automationRoutes(),
      ...networkProfileRoutes(),
      ...logsRoutes(),
      ...observabilityRoutes(),
      ...searchRoutes(),
      ...configRoutes(),
      ...systemRoutes(),
      ...standaloneRoutes(),
      ...serverRoutes(),
    ],
    errorBuilder: (context, state) =>
        UnknownRoutePage(location: state.uri.toString()),
  );
}
