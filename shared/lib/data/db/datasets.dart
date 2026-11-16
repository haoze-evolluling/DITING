/// The work-mode data sets: every mode owns one prefs container, one rules database and one logs
/// database, so switching modes switches all three. The legacy combined files are kept as the
/// pre-migration fallback.
library;

import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/db/rule_index_bridge.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum DataSet {
  normal(
    prefsContainer: LegacySettings.uiContainer,
    legacyRuleDatabase: LegacyDatabase.mainFile,
    ruleDatabase: LegacyDatabase.normalRulesFile,
    legacyLogsDatabase: LegacyDatabase.mainFile,
    logsDatabase: LegacyDatabase.normalLogsFile,
    ruleIndex: RuleIndexDataset.normal,
    seedsPresetWhitelist: true,
  ),
  express(
    prefsContainer: LegacySettings.expressContainer,
    legacyRuleDatabase: LegacyDatabase.expressFile,
    ruleDatabase: LegacyDatabase.expressRulesFile,
    legacyLogsDatabase: LegacyDatabase.expressFile,
    logsDatabase: LegacyDatabase.expressLogsFile,
    ruleIndex: RuleIndexDataset.express,
    seedsPresetWhitelist: true,
  ),
  server(
    prefsContainer: LegacySettings.serverContainer,
    legacyRuleDatabase: LegacyDatabase.serverFile,
    ruleDatabase: LegacyDatabase.serverFile,
    legacyLogsDatabase: LegacyDatabase.serverLogFile,
    logsDatabase: LegacyDatabase.serverLogsFile,
    ruleIndex: RuleIndexDataset.server,
    seedsPresetWhitelist: false,
  );

  const DataSet({
    required this.prefsContainer,
    required this.legacyRuleDatabase,
    required this.ruleDatabase,
    required this.legacyLogsDatabase,
    required this.logsDatabase,
    required this.ruleIndex,
    required this.seedsPresetWhitelist,
  });

  /// Container for every DNS-domain key (providers, resolution mode, cache, rules toggles…).
  final String prefsContainer;

  /// Pre-split SQLite file holding this data set's rules, subscriptions and (for the tunnel modes)
  /// logs. Kept for migration and for installs whose migration has not completed.
  final String legacyRuleDatabase;

  /// Split-layout SQLite file holding only rules and subscriptions.
  final String ruleDatabase;

  /// Pre-split file the log tables were read from.
  final String legacyLogsDatabase;

  /// Split-layout SQLite file holding only runtime tables.
  final String logsDatabase;

  String ruleDatabaseFor(StorageLayout layout) =>
      layout.isSplit ? ruleDatabase : legacyRuleDatabase;

  String logsDatabaseFor(StorageLayout layout) =>
      layout.isSplit ? logsDatabase : legacyLogsDatabase;

  /// Native rule-trie namespace refreshed after writes to this data set.
  final RuleIndexDataset ruleIndex;

  /// Legacy seeded the passthrough whitelist into normal and express only; server mode never had
  /// one, so seeding it would change its blocking behavior.
  final bool seedsPresetWhitelist;

  /// `app_work_mode` storage values: `normal` / `express` / `dns` (server mode keeps the legacy
  /// `dns` value).
  static DataSet fromWorkModeValue(String value) => switch (value) {
    'express' => DataSet.express,
    'dns' => DataSet.server,
    _ => DataSet.normal,
  };
}
