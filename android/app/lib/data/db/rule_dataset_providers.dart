library;

import 'dart:async';

import 'package:diting_android/data/db/rule_index_bridge.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../vpn/vpn_bridge.dart';

final activeRuleDatabaseProvider = Provider<String>((ref) {
  return ref.watch(activeDataSetProvider).ruleDatabase;
});

Timer? _refreshTimer;
RuleIndexDataset? _pendingDataset;

/// 规则变更后刷新索引并通知引擎重载。
///
/// 批量更新订阅时每个订阅都会触发一次，这里合并成一次索引重建和一次重载；
/// 数据集立即读取，避免定时器触发时 Ref 已释放。
void refreshRuleIndexesForCurrentMode(Ref ref) =>
    scheduleRuleIndexRefresh(ref.read(activeDataSetProvider).ruleIndex);

/// 供页面（`WidgetRef`）等无法直接传 `Ref` 的调用点使用。
void scheduleRuleIndexRefresh(RuleIndexDataset dataset) {
  _pendingDataset = dataset;
  _refreshTimer?.cancel();
  _refreshTimer = Timer(const Duration(milliseconds: 300), () async {
    _refreshTimer = null;
    final dataset = _pendingDataset;
    _pendingDataset = null;
    // 先等索引编译完成，再让引擎重载，避免两边同时重建索引。
    if (dataset != null) {
      await refreshRuleIndexes(dataset);
    }
    await requestVpnRuleReload();
  });
}
