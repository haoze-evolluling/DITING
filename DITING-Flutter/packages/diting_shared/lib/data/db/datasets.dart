/// The legacy `RuleDataset` triple: every work mode owns one prefs container and one rule
/// database, so switching modes switches both, exactly like the 1.4.3 app.
library;

import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/db/rule_index_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum DataSet {
  normal(
    prefsContainer: LegacySettings.uiContainer,
    ruleDatabase: LegacyDatabase.mainFile,
    ruleIndex: RuleIndexDataset.normal,
    seedsPresetWhitelist: true,
  ),
  express(
    prefsContainer: LegacySettings.expressContainer,
    ruleDatabase: LegacyDatabase.expressFile,
    ruleIndex: RuleIndexDataset.express,
    seedsPresetWhitelist: true,
  ),
  server(
    prefsContainer: LegacySettings.serverContainer,
    ruleDatabase: LegacyDatabase.serverFile,
    ruleIndex: RuleIndexDataset.server,
    seedsPresetWhitelist: false,
  );

  const DataSet({
    required this.prefsContainer,
    required this.ruleDatabase,
    required this.ruleIndex,
    required this.seedsPresetWhitelist,
  });

  /// Container for every DNS-domain key (providers, resolution mode, cache, rules toggles…).
  final String prefsContainer;

  /// Legacy SQLite file holding this data set's rules and subscriptions.
  final String ruleDatabase;

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
