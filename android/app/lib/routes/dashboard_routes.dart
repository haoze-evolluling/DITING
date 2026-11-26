library;

import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

abstract final class DashboardPaths {
  static const dashboard = '/';

  static const edit = '/dashboard/edit';
}

List<RouteBase> dashboardRoutes() => [
  GoRoute(
    path: DashboardPaths.edit,
    parentNavigatorKey: rootNavigatorKey,
    redirect: (context, state) {
      _enterEditing(context);
      return DashboardPaths.dashboard;
    },
  ),
];

void _enterEditing(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(dashboardEditingProvider.notifier).enter();
}
