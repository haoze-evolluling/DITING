/// Names and table lists of the pre-V2 stores.
///
/// This is the only production file allowed to mention the old database names. Runtime code never
/// reads them; the V2 migrator uses them once and the cleanup pass deletes the files.
library;

abstract final class LegacyStorageSource {
  static const normalDatabase = 'diting_database';
  static const expressDatabase = 'diting_express';

  /// Unreleased split layout. It was never shipped, so its data is discarded, not migrated.
  static const unreleasedSplitDatabases = <String>[
    'diting_normal_rules',
    'diting_normal_logs',
    'diting_express_rules',
    'diting_express_logs',
    'diting_app',
  ];

  static const allOldDatabases = <String>[
    normalDatabase,
    expressDatabase,
    ...unreleasedSplitDatabases,
  ];

  static const oldPreferenceKeys = <String>[
    'storage_layout_version',
    'storage_split_completed_at',
    'storage_migration_error',
  ];

  static const ruleTables = <String>[
    'block_rule',
    'block_rule_source',
    'allow_rule',
    'allow_rule_source',
    'rewrite_rule',
    'rewrite_rule_source',
    'go_url_rule',
    'go_url_rule_source',
    'cosmetic_rule',
    'cosmetic_rule_source',
    'mirror_template',
  ];

  static const ruleVersionTable = 'rule_version';

  static const subscriptionTables = <String>[
    'subscription',
    'subscription_group',
    'subscription_auto_update_item',
  ];

  static const logTables = <String>[
    'dns_log',
    'dns_race_log',
    'bootstrap_log',
  ];

  static const normalExtraTables = <String>[
    'http_request_log',
    'app_traffic_daily',
  ];

  static const automationTables = <String>[
    'automation_rule',
    'automation_profile',
    'automation_event',
  ];
}
