package com.haoze.diting.core.rule

import android.content.Context

/**
 * Mirrors `shared/lib/data/db/storage_contract.dart`.
 *
 * The Dart migrator sets `storage_layout_version` only after every split database verifies, so
 * native readers and writers can resolve the same file names without a second migration. Until
 * that marker exists they keep using the legacy files, which is what makes an interrupted upgrade
 * harmless.
 */
object StorageContract {
    private const val SETTINGS_PREFS = "diting_settings"
    private const val LAYOUT_KEY = "storage_layout_version"
    private const val SPLIT_VERSION = 1

    const val LEGACY_NORMAL = "diting_database"
    const val LEGACY_EXPRESS = "diting_express"
    const val LEGACY_SERVER_RULES = "diting_dns_rules"
    const val LEGACY_SERVER_LOGS = "diting_server_logs"

    const val NORMAL_RULES = "diting_normal_rules"
    const val NORMAL_LOGS = "diting_normal_logs"
    const val EXPRESS_RULES = "diting_express_rules"
    const val EXPRESS_LOGS = "diting_express_logs"
    const val SERVER_RULES = "diting_dns_rules"
    const val SERVER_LOGS = "diting_dns_logs"
    const val APP = "diting_app"

    fun isSplit(context: Context): Boolean =
        context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
            .getInt(LAYOUT_KEY, 0) >= SPLIT_VERSION

    fun rulesDatabase(context: Context, dataset: RuleDataset): String =
        if (isSplit(context)) dataset.splitRulesDatabase() else dataset.legacyDatabaseName()

    fun logsDatabase(context: Context, dataset: RuleDataset): String =
        if (isSplit(context)) dataset.splitLogsDatabase() else dataset.legacyLogsDatabaseName()

    /** Automation is global; before the split it lived in the normal mode's file. */
    fun appDatabase(context: Context): String =
        if (isSplit(context)) APP else LEGACY_NORMAL
}
