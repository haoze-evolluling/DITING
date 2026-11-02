/// DDL for the three legacy Room databases, verbatim from `sqlite_master`. A mismatch raises no
/// error; it makes reads look right while writes differ (no unique index lets a rule be inserted
/// twice).
library;

abstract final class LegacySchema {
  static const mainVersion = 3;

  static const expressVersion = 2;

  static const serverVersion = 3;

  static int versionOf(String fileName) => switch (fileName) {
    'diting_express' => expressVersion,
    'diting_dns_rules' => serverVersion,
    _ => mainVersion,
  };

  /// Order matters: `*_source` tables reference the main tables, so parents come first to keep
  /// `PRAGMA foreign_key_check` output readable.
  static List<String> statementsFor(String fileName) => switch (fileName) {
    'diting_dns_rules' => [
      ..._ruleTables,
      ..._subscriptionTables,
      ..._ruleIndexes,
    ],
    'diting_express' => [
      ..._ruleTables,
      ..._subscriptionTables,
      ..._logTables,
      ..._ruleIndexes,
      ..._subscriptionIndexes,
      ..._logIndexes,
    ],
    _ => [
      ..._ruleTables,
      ..._subscriptionTables,
      ..._logTables,
      _httpRequestLog,
      ..._httpRequestLogIndexes,
      _appTrafficDaily,
      ..._appTrafficDailyIndexes,
      ..._ruleIndexes,
      ..._subscriptionIndexes,
      ..._logIndexes,
    ],
  };

  static const _blockRule = '''
CREATE TABLE `block_rule` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `pattern` TEXT NOT NULL, `rawLine` TEXT NOT NULL, `addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL, `groupName` TEXT, `important` INTEGER NOT NULL, `appScope` TEXT, `appInverted` INTEGER NOT NULL, `isWildcard` INTEGER NOT NULL, `denyallow` TEXT, `isRegex` INTEGER NOT NULL, `dnsType` TEXT)''';

  static const _blockRuleSource = '''
CREATE TABLE `block_rule_source` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, PRIMARY KEY(`ruleId`, `source`), FOREIGN KEY(`ruleId`) REFERENCES `block_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )''';

  /// `important` sits at a different position than in `block_rule`: Room emits columns in
  /// declaration order, and a wrong order shifts `SELECT *`.
  static const _allowRule = '''
CREATE TABLE `allow_rule` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `pattern` TEXT NOT NULL, `rawLine` TEXT NOT NULL, `addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL, `groupName` TEXT, `appScope` TEXT, `appInverted` INTEGER NOT NULL, `isWildcard` INTEGER NOT NULL, `important` INTEGER NOT NULL, `denyallow` TEXT, `isRegex` INTEGER NOT NULL, `dnsType` TEXT)''';

  static const _allowRuleSource = '''
CREATE TABLE `allow_rule_source` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, PRIMARY KEY(`ruleId`, `source`), FOREIGN KEY(`ruleId`) REFERENCES `allow_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )''';

  static const _rewriteRule = '''
CREATE TABLE `rewrite_rule` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `pattern` TEXT NOT NULL, `targetType` TEXT NOT NULL, `targetValue` TEXT NOT NULL, `rawLine` TEXT NOT NULL, `addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL)''';

  static const _rewriteRuleSource = '''
CREATE TABLE `rewrite_rule_source` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, PRIMARY KEY(`ruleId`, `source`), FOREIGN KEY(`ruleId`) REFERENCES `rewrite_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )''';

  static const _goUrlRule = '''
CREATE TABLE `go_url_rule` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `pattern` TEXT NOT NULL, `kind` TEXT NOT NULL, `rawLine` TEXT NOT NULL, `addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL)''';

  static const _goUrlRuleSource = '''
CREATE TABLE `go_url_rule_source` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, PRIMARY KEY(`ruleId`, `source`), FOREIGN KEY(`ruleId`) REFERENCES `go_url_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )''';

  static const _cosmeticRule = '''
CREATE TABLE `cosmetic_rule` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `domain` TEXT NOT NULL, `selector` TEXT NOT NULL, `rawLine` TEXT NOT NULL, `addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL, `isException` INTEGER NOT NULL)''';

  /// The only source table without a foreign key: the legacy entity had none.
  static const _cosmeticRuleSource = '''
CREATE TABLE `cosmetic_rule_source` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, PRIMARY KEY(`ruleId`, `source`))''';

  static const _mirrorTemplate = '''
CREATE TABLE `mirror_template` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `name` TEXT NOT NULL, `template` TEXT NOT NULL, `addedAt` INTEGER NOT NULL)''';

  static const _ruleTables = <String>[
    _blockRule,
    _blockRuleSource,
    _allowRule,
    _allowRuleSource,
    _rewriteRule,
    _rewriteRuleSource,
    _goUrlRule,
    _goUrlRuleSource,
    _cosmeticRule,
    _cosmeticRuleSource,
    _mirrorTemplate,
  ];

  static const _subscription = '''
CREATE TABLE `subscription` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `url` TEXT NOT NULL, `name` TEXT NOT NULL, `sourceType` TEXT NOT NULL, `kind` TEXT NOT NULL, `enabled` INTEGER NOT NULL, `ruleCount` INTEGER NOT NULL, `lastUpdated` INTEGER NOT NULL, `addedAt` INTEGER NOT NULL, `importState` TEXT NOT NULL, `importError` TEXT, `httpEtag` TEXT, `httpLastModified` TEXT, `ruleSetHash` TEXT, `lastAttemptAt` INTEGER NOT NULL, `consecutiveFailureCount` INTEGER NOT NULL, `mirrorTemplate` TEXT, `mirrorFallback` INTEGER NOT NULL, `groupId` INTEGER)''';

  static const _subscriptionGroup = '''
CREATE TABLE `subscription_group` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `name` TEXT NOT NULL, `autoUpdateEnabled` INTEGER NOT NULL, `addedAt` INTEGER NOT NULL)''';

  static const _subscriptionAutoUpdateItem = '''
CREATE TABLE `subscription_auto_update_item` (`batchId` TEXT NOT NULL, `subscriptionId` INTEGER NOT NULL, `status` TEXT NOT NULL, `changed` INTEGER NOT NULL, `ruleCount` INTEGER NOT NULL, PRIMARY KEY(`batchId`, `subscriptionId`), FOREIGN KEY(`subscriptionId`) REFERENCES `subscription`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )''';

  static const _subscriptionTables = <String>[
    _subscription,
    _subscriptionGroup,
    _subscriptionAutoUpdateItem,
  ];

  static const _dnsCache = '''
CREATE TABLE `dns_cache` (`key` TEXT NOT NULL, `queryName` TEXT NOT NULL, `queryType` INTEGER NOT NULL, `queryClass` INTEGER NOT NULL, `createdAt` INTEGER NOT NULL, `expiresAt` INTEGER NOT NULL, `lastHitAt` INTEGER, `hitCount` INTEGER NOT NULL DEFAULT 0, `originalTtlSeconds` INTEGER NOT NULL, `ttlOffsets` TEXT NOT NULL, `response` BLOB NOT NULL, `responseSize` INTEGER NOT NULL, PRIMARY KEY(`key`))''';

  static const _dnsLog = '''
CREATE TABLE `dns_log` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `timestamp` INTEGER NOT NULL, `queryName` TEXT NOT NULL, `queryType` INTEGER NOT NULL, `result` TEXT NOT NULL, `message` TEXT, `cached` INTEGER NOT NULL, `blockSubscriptionId` INTEGER, `packageName` TEXT)''';

  static const _raceLog = '''
CREATE TABLE `dns_race_log` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `timestamp` INTEGER NOT NULL, `queryName` TEXT NOT NULL, `queryType` INTEGER NOT NULL, `strategy` TEXT NOT NULL, `providerCount` INTEGER NOT NULL, `success` INTEGER NOT NULL, `elapsedMs` INTEGER NOT NULL, `selectedProviderId` TEXT, `selectedProviderName` TEXT, `selectedElapsedMs` INTEGER, `winnerProviderId` TEXT, `winnerProviderName` TEXT, `winnerElapsedMs` INTEGER, `fallbackUsed` INTEGER NOT NULL, `fallbackSuccess` INTEGER NOT NULL, `message` TEXT)''';

  static const _bootstrapLog = '''
CREATE TABLE `bootstrap_log` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `timestamp` INTEGER NOT NULL, `ipId` TEXT NOT NULL, `ipName` TEXT NOT NULL, `ip` TEXT NOT NULL, `host` TEXT NOT NULL, `success` INTEGER NOT NULL, `elapsedMs` INTEGER NOT NULL, `fallbackUsed` INTEGER NOT NULL, `message` TEXT)''';

  static const _logTables = <String>[
    _dnsCache,
    _dnsLog,
    _raceLog,
    _bootstrapLog,
  ];

  static const _httpRequestLog = '''
CREATE TABLE `http_request_log` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `timestamp` INTEGER NOT NULL, `packageName` TEXT NOT NULL, `authority` TEXT, `protocol` TEXT NOT NULL, `outcome` TEXT NOT NULL, `matchedRule` TEXT, `blockSubscriptionId` INTEGER)''';

  static const _appTrafficDaily = '''
CREATE TABLE `app_traffic_daily` (`date` TEXT NOT NULL, `package_name` TEXT NOT NULL, `app_name` TEXT NOT NULL, `tx_bytes` INTEGER NOT NULL, `rx_bytes` INTEGER NOT NULL, `updated_at` INTEGER NOT NULL, PRIMARY KEY(`date`, `package_name`))''';

  // The UNIQUE indexes are the only guard against duplicate rules; imports can still race.

  static const _ruleIndexes = <String>[
    'CREATE INDEX `index_block_rule_appScope` ON `block_rule` (`appScope`)',
    'CREATE UNIQUE INDEX `index_block_rule_pattern_important_appScope_appInverted_dnsType_isRegex` ON `block_rule` (`pattern`, `important`, `appScope`, `appInverted`, `dnsType`, `isRegex`)',
    'CREATE INDEX `index_block_rule_source_source` ON `block_rule_source` (`source`)',
    'CREATE INDEX `index_allow_rule_appScope` ON `allow_rule` (`appScope`)',
    'CREATE UNIQUE INDEX `index_allow_rule_pattern_important_appScope_appInverted_dnsType_isRegex` ON `allow_rule` (`pattern`, `important`, `appScope`, `appInverted`, `dnsType`, `isRegex`)',
    'CREATE INDEX `index_allow_rule_source_source` ON `allow_rule_source` (`source`)',
    'CREATE UNIQUE INDEX `index_rewrite_rule_pattern_targetType_targetValue` ON `rewrite_rule` (`pattern`, `targetType`, `targetValue`)',
    'CREATE INDEX `index_rewrite_rule_source_source` ON `rewrite_rule_source` (`source`)',
    'CREATE UNIQUE INDEX `index_go_url_rule_pattern_kind` ON `go_url_rule` (`pattern`, `kind`)',
    'CREATE INDEX `index_go_url_rule_source_source` ON `go_url_rule_source` (`source`)',
    'CREATE UNIQUE INDEX `index_cosmetic_rule_domain_selector_isException` ON `cosmetic_rule` (`domain`, `selector`, `isException`)',
    'CREATE INDEX `index_cosmetic_rule_source_source` ON `cosmetic_rule_source` (`source`)',
    'CREATE UNIQUE INDEX `index_mirror_template_name` ON `mirror_template` (`name`)',
  ];

  static const _subscriptionIndexes = <String>[
    'CREATE UNIQUE INDEX `index_subscription_url_kind` ON `subscription` (`url`, `kind`)',
    'CREATE INDEX `index_subscription_groupId` ON `subscription` (`groupId`)',
    'CREATE UNIQUE INDEX `index_subscription_group_name` ON `subscription_group` (`name`)',
    'CREATE INDEX `index_subscription_auto_update_item_batchId_status` ON `subscription_auto_update_item` (`batchId`, `status`)',
    'CREATE INDEX `index_subscription_auto_update_item_subscriptionId` ON `subscription_auto_update_item` (`subscriptionId`)',
  ];

  static const _logIndexes = <String>[
    'CREATE INDEX `index_dns_cache_expiresAt` ON `dns_cache` (`expiresAt`)',
    'CREATE INDEX `index_dns_cache_lastHitAt` ON `dns_cache` (`lastHitAt`)',
    'CREATE INDEX `index_dns_cache_queryName` ON `dns_cache` (`queryName`)',
    'CREATE INDEX `index_dns_cache_queryType_expiresAt` ON `dns_cache` (`queryType`, `expiresAt`)',
    'CREATE INDEX `index_dns_log_timestamp` ON `dns_log` (`timestamp`)',
    'CREATE INDEX `index_dns_log_queryName` ON `dns_log` (`queryName`)',
    'CREATE INDEX `index_dns_log_packageName` ON `dns_log` (`packageName`)',
    'CREATE INDEX `index_dns_log_result_timestamp` ON `dns_log` (`result`, `timestamp`)',
    'CREATE INDEX `index_dns_log_result_cached_timestamp` ON `dns_log` (`result`, `cached`, `timestamp`)',
    'CREATE INDEX `index_dns_log_block_subscription_timestamp` ON `dns_log` (`blockSubscriptionId`, `timestamp`)',
    'CREATE INDEX `index_dns_race_log_timestamp` ON `dns_race_log` (`timestamp`)',
    'CREATE INDEX `index_dns_race_log_strategy_timestamp` ON `dns_race_log` (`strategy`, `timestamp`)',
    'CREATE INDEX `index_dns_race_log_selected_timestamp` ON `dns_race_log` (`selectedProviderId`, `timestamp`)',
    'CREATE INDEX `index_dns_race_log_winner_timestamp` ON `dns_race_log` (`winnerProviderId`, `timestamp`)',
    'CREATE INDEX `index_bootstrap_log_timestamp` ON `bootstrap_log` (`timestamp`)',
    'CREATE INDEX `index_bootstrap_log_ip_timestamp` ON `bootstrap_log` (`ipId`, `timestamp`)',
    'CREATE INDEX `index_bootstrap_log_success_timestamp` ON `bootstrap_log` (`success`, `timestamp`)',
  ];

  static const _httpRequestLogIndexes = <String>[
    'CREATE INDEX `index_http_request_log_timestamp` ON `http_request_log` (`timestamp`)',
    'CREATE INDEX `index_http_request_log_authority` ON `http_request_log` (`authority`)',
    'CREATE INDEX `index_http_request_log_outcome_timestamp` ON `http_request_log` (`outcome`, `timestamp`)',
    'CREATE INDEX `index_http_request_log_block_subscription_timestamp` ON `http_request_log` (`blockSubscriptionId`, `timestamp`)',
  ];

  static const _appTrafficDailyIndexes = <String>[
    'CREATE INDEX `index_app_traffic_daily_date` ON `app_traffic_daily` (`date`)',
    'CREATE INDEX `index_app_traffic_daily_package_name` ON `app_traffic_daily` (`package_name`)',
  ];
}
