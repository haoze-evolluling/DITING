package com.haoze.diting.core.rule

import android.content.Context
import com.haoze.diting.control.DataPlaneControl

/**
 * Identifies which isolated data set a caller operates on.
 *
 * Every mode owns a rules database and a logs database. The declaration order is the kernel's
 * dataset tag (`rust/diting-rule-core/src/index_layout.rs`), so [RuleIndexNative] can pass
 * [ordinal] straight through; do not reorder the entries.
 */
enum class RuleDataset {
    NORMAL,
    EXPRESS,
    DNS_MODE;

    /** The SharedPreferences file holding per-dataset rule settings. */
    fun prefsName(): String = when (this) {
        NORMAL -> "dns_vpn_prefs"
        EXPRESS -> "diting_express_prefs"
        DNS_MODE -> "diting_dns_mode_prefs"
    }

    /** Rules and subscriptions of this data set. */
    fun rulesDatabase(): String = when (this) {
        NORMAL -> StorageContract.NORMAL_RULES
        EXPRESS -> StorageContract.EXPRESS_RULES
        DNS_MODE -> StorageContract.DNS_RULES
    }

    /** Runtime tables (logs, cache) of this data set. */
    fun logsDatabase(): String = when (this) {
        NORMAL -> StorageContract.NORMAL_LOGS
        EXPRESS -> StorageContract.EXPRESS_LOGS
        DNS_MODE -> StorageContract.DNS_LOGS
    }

    companion object {
        /** Dataset of the persisted work mode. */
        fun active(context: Context): RuleDataset =
            when (DataPlaneControl.workMode(context)) {
                DataPlaneControl.WORK_MODE_DNS -> DNS_MODE
                DataPlaneControl.WORK_MODE_EXPRESS -> EXPRESS
                else -> NORMAL
            }
    }
}
