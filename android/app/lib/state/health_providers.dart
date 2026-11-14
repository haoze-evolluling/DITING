/// U1 保护健康评分的数据采集：把各子系统的状态汇成 [HealthInput]，交给纯函数打分。
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

/// 关键权限：没有 VPN 权限保护根本起不来；通知权限关系到前台状态可见与快捷动作。
const _criticalPermissions = [AppPermission.vpn, AppPermission.notification];

/// 保护健康报告。任一数据源不可用时降级而不是报错，避免把「读不到」误报成「不健康」。
final healthReportProvider = FutureProvider<HealthReport>((ref) async {
  final core = ref.watch(coreStateProvider);
  final stats = ref.watch(serviceStatsProvider);
  final primary = ref.watch(primaryProviderProvider);
  final subs = ref
      .watch(subscriptionEntriesProvider)
      .maybeWhen(data: (value) => value, orElse: () => const <SubscriptionEntry>[]);

  var granted = _criticalPermissions.length;
  try {
    final perms = await ref.watch(permissionStatesProvider.future);
    granted = _criticalPermissions
        .where((permission) => perms.states[permission] == true)
        .length;
  } catch (_) {
    // 权限渠道不可用：按已授予处理，宁可少报也不谎报缺权限。
    granted = _criticalPermissions.length;
  }

  var totalRules = 0;
  var failedSubs = 0;
  for (final entry in subs) {
    totalRules += entry.ruleCount;
    try {
      if (entry.health == SubscriptionHealth.failed) failedSubs++;
    } catch (_) {
      // 订阅健康需要原生分类器；不可用时不计失败。
    }
  }

  return computeHealth(
    HealthInput(
      criticalPermissionsGranted: granted,
      criticalPermissionsTotal: _criticalPermissions.length,
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
