library;

import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/native/permissions_bridge.dart';
import 'package:diting_android/pages/health/health_score.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/permission_providers.dart';
import 'package:diting_android/state/primary_provider_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _criticalPermissions = [AppPermission.vpn, AppPermission.notification];

final healthReportProvider = FutureProvider<HealthReport>((ref) async {
  final core = ref.watch(coreStateProvider);
  final stats = ref.watch(serviceStatsProvider);
  final primary = ref.watch(primaryProviderProvider);
  final subs = ref
      .watch(subscriptionEntriesProvider)
      .maybeWhen(
        data: (value) => value,
        orElse: () => const <SubscriptionEntry>[],
      );

  final rootTakeover =
      ref.watch(workModeProvider).supportsRootDns &&
      ref.watch(rootDnsTakeoverProvider);
  final critical = rootTakeover
      ? const [AppPermission.notification]
      : _criticalPermissions;

  var granted = critical.length;
  try {
    final perms = await ref.watch(permissionStatesProvider.future);
    granted = critical
        .where((permission) => perms.states[permission] == true)
        .length;
  } catch (_) {
    granted = critical.length;
  }

  var totalRules = 0;
  var failedSubs = 0;
  for (final entry in subs) {
    totalRules += entry.ruleCount;
    try {
      if (entry.health == SubscriptionHealth.failed) failedSubs++;
    } catch (_) {}
  }

  return computeHealth(
    HealthInput(
      criticalPermissionsGranted: granted,
      criticalPermissionsTotal: critical.length,
      running: core.isRunning,
      hasProvider: primary != null,
      totalRules: totalRules,
      failedSubs: failedSubs,
      totalSubs: subs.length,
      queries: stats.queries,
      cacheHits: stats.cacheHits,
      blocked: stats.blocked,
    ),
  );
});
