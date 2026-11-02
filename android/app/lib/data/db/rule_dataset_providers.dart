/// Data-set-aware rule plumbing: which database the current work mode writes, and which native
/// rule-trie namespace has to be recompiled after those writes.
library;

import 'dart:async';

import 'package:diting_shared/data/db/rule_index_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Legacy SQLite file of the active data set.
final activeRuleDatabaseProvider = Provider<String>(
  (ref) => ref.watch(activeDataSetProvider).ruleDatabase,
);

/// Recompiles the native rule tries of the active data set. Fire-and-forget like every other
/// refresh: a missed call only costs one compile at the next service start.
void refreshRuleIndexesForCurrentMode(Ref ref) {
  unawaited(refreshRuleIndexes(ref.read(activeDataSetProvider).ruleIndex));
}
