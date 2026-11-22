library;

import 'dart:async';

import 'package:diting_shared/data/db/rule_index_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../vpn/vpn_bridge.dart';

final activeRuleDatabaseProvider = Provider<String>((ref) {
  return ref.watch(activeDataSetProvider).ruleDatabase;
});

void refreshRuleIndexesForCurrentMode(Ref ref) {
  unawaited(refreshRuleIndexes(ref.read(activeDataSetProvider).ruleIndex));
  unawaited(requestVpnRuleReload());
}
