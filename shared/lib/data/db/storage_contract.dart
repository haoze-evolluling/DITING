/// Names, application ids and lifecycle markers of the work-mode data stores.
///
/// Each work mode owns a rules database and a logs database. Global automation data lives in its
/// own store because it must survive a mode switch. The V2 stores were created together with this
/// layout; the only code that may know the pre-V2 file names is `legacy_storage_source.dart`.
library;

/// The seven database files of the current layout.
enum DatabaseKind {
  normalRules(StorageContract.normalRulesDatabase, 0x44495431),
  normalLogs(StorageContract.normalLogsDatabase, 0x44495432),
  expressRules(StorageContract.expressRulesDatabase, 0x44495433),
  expressLogs(StorageContract.expressLogsDatabase, 0x44495434),
  serverRules(StorageContract.serverRulesDatabase, 0x44495435),
  serverLogs(StorageContract.serverLogsDatabase, 0x44495436),
  global(StorageContract.globalDatabase, 0x44495437);

  const DatabaseKind(this.fileName, this.applicationId);

  final String fileName;

  /// Stored in the SQLite header. A file at this path with another id is not ours and is rebuilt.
  final int applicationId;

  static DatabaseKind? fromFileName(String fileName) {
    for (final kind in values) {
      if (kind.fileName == fileName) return kind;
    }
    return null;
  }
}

abstract final class StorageContract {
  static const normalRulesDatabase = 'diting_normal_rules_v2';
  static const normalLogsDatabase = 'diting_normal_logs_v2';
  static const expressRulesDatabase = 'diting_express_rules_v2';
  static const expressLogsDatabase = 'diting_express_logs_v2';
  static const serverRulesDatabase = 'diting_dns_rules_v2';
  static const serverLogsDatabase = 'diting_dns_logs_v2';
  static const globalDatabase = 'diting_global_v2';

  /// Version stored in every V2 file's `user_version`.
  static const schemaVersion = 1;

  /// Mode selection and the storage lifecycle marker share the global settings container.
  static const settingsContainer = 'diting_settings';

  static const stateKey = 'storage_v2_state';

  static const completedAtKey = 'storage_v2_completed_at';

  static const errorKey = 'storage_v2_error';

  /// JSON summary of the last migration: copied tables, dropped rows and verification results.
  static const reportKey = 'storage_v2_report';

  static const stateIdle = 0;

  static const stateCopying = 1;

  static const stateVerified = 2;

  static const stateCleaned = 3;

  /// File created by the migrator so native services do not open a half-copied store.
  static const migrationLockName = '.storage_v2_migrating';

  static const allDatabases = <String>[
    normalRulesDatabase,
    normalLogsDatabase,
    expressRulesDatabase,
    expressLogsDatabase,
    serverRulesDatabase,
    serverLogsDatabase,
    globalDatabase,
  ];

  static Iterable<DatabaseKind> get kinds => DatabaseKind.values;

  static bool isReadyState(int state) => state >= stateVerified;
}
