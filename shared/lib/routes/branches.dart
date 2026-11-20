library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

abstract final class Routes {
  static const home = '/';
  static const hub = '/hub';
  static const logs = '/logs';
  static const traffic = '/traffic';
  static const tools = '/tools';
  static const settings = '/settings';

  static const rules = '/rules';
  static const batchEditor = '/rules/batch';
  static const subscriptions = '/subscriptions';
  static const about = '/about';
  static const modeSelect = '/mode/select';
  static const modeOnboarding = '/mode/onboarding';
  static const server = '/server';
  static const serverHub = '/server/hub';
  static const serverLogs = '/server/logs';

  static String rulesOf(String kind) => '$rules/$kind';
}

const branchOrder = <String>[
  Routes.home,
  Routes.hub,
  Routes.logs,
  Routes.traffic,
  Routes.tools,
  Routes.settings,
];

const desktopBranchOrder = <String>[Routes.home, Routes.hub, Routes.about];

int branchIndexOf(String location) {
  var bestIndex = 0;
  var bestLength = -1;
  for (var index = 0; index < branchOrder.length; index++) {
    final prefix = branchOrder[index];
    if (!location.startsWith(prefix)) continue;
    final isBoundary =
        location.length == prefix.length ||
        prefix.endsWith('/') ||
        location[prefix.length] == '/';
    if (!isBoundary) continue;
    if (prefix.length > bestLength) {
      bestLength = prefix.length;
      bestIndex = index;
    }
  }
  return bestIndex;
}

String branchLocationOf(int index) =>
    index >= 0 && index < branchOrder.length ? branchOrder[index] : Routes.home;

bool isBranchRoot(String location) {
  for (final root in branchOrder) {
    if (root == location) return true;
  }
  return false;
}

bool goToBranch(BuildContext context, String location) {
  final shell = StatefulNavigationShell.maybeOf(context);
  if (shell == null) {
    return false;
  }
  shell.goBranch(branchIndexOf(location));
  return true;
}

void openLocation(BuildContext context, String location) {
  if (isBranchRoot(location) && goToBranch(context, location)) {
    return;
  }
  context.push(location);
}
