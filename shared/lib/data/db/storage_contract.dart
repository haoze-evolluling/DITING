library;

enum DatabaseKind {
  normalRules(StorageContract.normalRulesDatabase, 0x44495431),
  normalLogs(StorageContract.normalLogsDatabase, 0x44495432),
  expressRules(StorageContract.expressRulesDatabase, 0x44495433),
  expressLogs(StorageContract.expressLogsDatabase, 0x44495434),
  global(StorageContract.globalDatabase, 0x44495437);

  const DatabaseKind(this.fileName, this.applicationId);

  final String fileName;

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
  static const globalDatabase = 'diting_global_v2';

  /// v2：简洁模式日志库补齐 http_request_log / app_traffic_daily 两张表，
  /// 使简洁模式与普通模式具备相同的 HTTP 记录与按应用流量统计能力。
  static const schemaVersion = 2;

  static const allDatabases = <String>[
    normalRulesDatabase,
    normalLogsDatabase,
    expressRulesDatabase,
    expressLogsDatabase,
    globalDatabase,
  ];
}
