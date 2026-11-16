package com.haoze.diting.core.rule

import android.content.Context

/**
 * Identifies which isolated data set a caller operates on, ported from the legacy app.
 * Every mode has its own rules and logs database; [legacyDatabaseName] is the combined pre-split
 * file, used until the Dart-side storage migration writes `storage_layout_version`.
 *
 * The declaration order is the kernel's dataset tag (`rust/diting-rule-core/src/index_layout.rs`),
 * so [RuleIndexNative] can pass [ordinal] straight through; do not reorder the entries.
 */
enum class RuleDataset {
    NORMAL,
    EXPRESS,
    DNS_MODE;

    /** The legacy SharedPreferences file holding per-dataset rule settings. */
    fun prefsName(): String = when (this) {
        NORMAL -> "dns_vpn_prefs"
        EXPRESS -> "diting_express_prefs"
        DNS_MODE -> "diting_dns_mode_prefs"
    }

    /** Pre-split SQLite file: rules, subscriptions and (for the tunnel modes) logs. */
    fun legacyDatabaseName(): String = when (this) {
        NORMAL -> StorageContract.LEGACY_NORMAL
        EXPRESS -> StorageContract.LEGACY_EXPRESS
        DNS_MODE -> StorageContract.LEGACY_SERVER_RULES
    }

    /** Pre-split file the log tables were read from. */
    fun legacyLogsDatabaseName(): String = when (this) {
        NORMAL -> StorageContract.LEGACY_NORMAL
        EXPRESS -> StorageContract.LEGACY_EXPRESS
        DNS_MODE -> StorageContract.LEGACY_SERVER_LOGS
    }

    /** Split layout: rule-only database of this data set. */
    fun splitRulesDatabase(): String = when (this) {
        NORMAL -> StorageContract.NORMAL_RULES
        EXPRESS -> StorageContract.EXPRESS_RULES
        DNS_MODE -> StorageContract.SERVER_RULES
    }

    /** Split layout: log-only database of this data set. */
    fun splitLogsDatabase(): String = when (this) {
        NORMAL -> StorageContract.NORMAL_LOGS
        EXPRESS -> StorageContract.EXPRESS_LOGS
        DNS_MODE -> StorageContract.SERVER_LOGS
    }

    /** Rule database in the layout the migration selected. */
    fun rulesDatabase(context: Context): String =
        StorageContract.rulesDatabase(context, this)

    /** Log database in the layout the migration selected. */
    fun logsDatabase(context: Context): String =
        StorageContract.logsDatabase(context, this)
}
