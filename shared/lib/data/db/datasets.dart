/// The work-mode data sets: every mode owns one prefs container, one rules database and one logs
/// database, so switching modes switches all three.
library;

import 'package:diting_shared/data/db/rule_index_bridge.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum DataSet {
  normal(
    prefsContainer: LegacySettings.uiContainer,
    ruleDatabase: StorageContract.normalRulesDatabase,
    logsDatabase: StorageContract.normalLogsDatabase,
    ruleIndex: RuleIndexDataset.normal,
  ),
  express(
    prefsContainer: LegacySettings.expressContainer,
    ruleDatabase: StorageContract.expressRulesDatabase,
    logsDatabase: StorageContract.expressLogsDatabase,
    ruleIndex: RuleIndexDataset.express,
  );

  const DataSet({
    required this.prefsContainer,
    required this.ruleDatabase,
    required this.logsDatabase,
    required this.ruleIndex,
  });

  /// Container for every DNS-domain key (providers, resolution mode, cache, rules toggles…).
  final String prefsContainer;

  /// Rules and subscriptions of this mode.
  final String ruleDatabase;

  /// Runtime tables (logs, cache, traffic) of this mode.
  final String logsDatabase;

  /// Native rule-trie namespace refreshed after writes to this data set.
  final RuleIndexDataset ruleIndex;

  /// `app_work_mode` storage values: `normal` / `express`.
  static DataSet fromWorkModeValue(String value) => switch (value) {
    'express' => DataSet.express,
    _ => DataSet.normal,
  };
}
