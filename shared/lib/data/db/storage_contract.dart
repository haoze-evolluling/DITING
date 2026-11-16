/// Names and versioning of the work-mode data stores.
///
/// The app used to keep one combined database per tunnel mode (rules + logs in the same file) and
/// a separate log store for server mode. The split layout gives every mode a rules database and a
/// logs database of its own, and moves global automation data into [appDatabase].
///
/// Both layouts are supported while the one-time migration runs:
/// [StorageLayout.legacy] keeps reading/writing the legacy files, [StorageLayout.split] uses the
/// per-mode stores. Nothing here decides when the switch happens; `storage_layout_version` in the
/// settings container does, and the migrator writes it only after every copy verifies.
library;

enum StorageLayout {
  legacy,
  split;

  /// `storage_layout_version` at or above this value means the split layout is in use.
  static const splitVersion = 1;

  static StorageLayout fromVersion(int version) =>
      version >= splitVersion ? split : legacy;

  bool get isSplit => this == split;
}

abstract final class StorageContract {
  /// Mode selection and the layout marker share the global settings container.
  static const settingsContainer = 'diting_settings';

  static const layoutVersionKey = 'storage_layout_version';

  // ---- Legacy files; these names are an upgrade contract, never rename them in place ----

  static const legacyNormalDatabase = 'diting_database';

  static const legacyExpressDatabase = 'diting_express';

  static const legacyServerRulesDatabase = 'diting_dns_rules';

  static const legacyServerLogsDatabase = 'diting_server_logs';

  // ---- Split layout: one rules and one logs database per mode ----

  static const normalRulesDatabase = 'diting_normal_rules';

  static const normalLogsDatabase = 'diting_normal_logs';

  static const expressRulesDatabase = 'diting_express_rules';

  static const expressLogsDatabase = 'diting_express_logs';

  /// Server rules keep their legacy name: the file was already rule-only.
  static const serverRulesDatabase = 'diting_dns_rules';

  static const serverLogsDatabase = 'diting_dns_logs';

  /// Global data that must outlive a mode switch (automation rules, profiles and events).
  static const appDatabase = 'diting_app';

  static const splitRuleDatabases = <String>[
    normalRulesDatabase,
    expressRulesDatabase,
    serverRulesDatabase,
  ];

  static const splitLogDatabases = <String>[
    normalLogsDatabase,
    expressLogsDatabase,
    serverLogsDatabase,
  ];

  static const splitDatabases = <String>[
    ...splitRuleDatabases,
    ...splitLogDatabases,
    appDatabase,
  ];

  static const legacyDatabases = <String>[
    legacyNormalDatabase,
    legacyExpressDatabase,
    legacyServerRulesDatabase,
    legacyServerLogsDatabase,
  ];

  static List<String> databasesFor(StorageLayout layout) =>
      layout.isSplit ? splitDatabases : legacyDatabases;

  static List<String> ruleDatabasesFor(StorageLayout layout) => layout.isSplit
      ? splitRuleDatabases
      : const [
          legacyNormalDatabase,
          legacyExpressDatabase,
          legacyServerRulesDatabase,
        ];

  static List<String> logDatabasesFor(StorageLayout layout) => layout.isSplit
      ? splitLogDatabases
      : const [
          legacyNormalDatabase,
          legacyExpressDatabase,
          legacyServerLogsDatabase,
        ];

  /// Every file this build may read, including leftovers from the legacy layout. Used by
  /// diagnostics and cleanup so a migrated install can still inspect or remove the old files.
  static List<String> get allKnownDatabases =>
      [...legacyDatabases, ...splitDatabases].toSet().toList(growable: false);
}
