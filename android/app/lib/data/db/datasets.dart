library;

import 'package:diting_android/data/db/rule_index_bridge.dart';
import 'package:diting_android/data/db/storage_contract.dart';
import 'package:diting_android/data/prefs/legacy_settings.dart';

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

  final String prefsContainer;

  final String ruleDatabase;

  final String logsDatabase;

  final RuleIndexDataset ruleIndex;

  static DataSet fromWorkModeValue(String value) => switch (value) {
    'express' => DataSet.express,
    _ => DataSet.normal,
  };
}
