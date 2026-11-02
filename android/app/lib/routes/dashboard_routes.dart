/// Dashboard (home) routes. Editing is same-screen state, but a dedicated route gives deep
/// links and tests a way into edit mode; it redirects straight back to `/`.
library;

import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

abstract final class DashboardPaths {
  static const dashboard = '/';

  /// Deep link that enters edit mode and returns to home.
  static const edit = '/dashboard/edit';
}

/// Dashboard routes, assembled by `lib/router.dart`. Uses `redirect` rather than `builder`:
/// redirects run during navigation resolution, when `ProviderScope` is mounted, while
/// mutating state in `builder` is a side effect during build.
List<RouteBase> dashboardRoutes() => [
  GoRoute(
    path: DashboardPaths.edit,
    parentNavigatorKey: rootNavigatorKey,
    redirect: (context, state) {
      _setEditing(context, true);
      return DashboardPaths.dashboard;
    },
  ),
];

/// Sets the editing provider from a redirect. Redirect callbacks get no `WidgetRef`, so the
/// container is read from the `BuildContext`; without a `ProviderScope` ancestor navigation
/// still succeeds.
void _setEditing(BuildContext context, bool value) {
  final container = ProviderScope.containerOf(context, listen: false);
  final notifier = container.read(dashboardEditingProvider.notifier);
  if (value) {
    notifier.enter();
  } else {
    notifier.exit();
  }
}
