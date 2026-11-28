package com.haoze.diting.core.rule

import android.content.Context
import com.haoze.diting.control.DataPlaneControl

enum class RuleDataset {
    NORMAL,
    EXPRESS,
    SERVER;

    fun prefsName(): String = when (this) {
        NORMAL -> "dns_vpn_prefs"
        EXPRESS -> "diting_express_prefs"
        SERVER -> "diting_server_prefs"
    }

    fun rulesDatabase(): String = when (this) {
        NORMAL -> StorageContract.NORMAL_RULES
        EXPRESS -> StorageContract.EXPRESS_RULES
        SERVER -> StorageContract.SERVER_RULES
    }

    fun logsDatabase(): String = when (this) {
        NORMAL -> StorageContract.NORMAL_LOGS
        EXPRESS -> StorageContract.EXPRESS_LOGS
        SERVER -> StorageContract.SERVER_LOGS
    }

    companion object {
        fun active(context: Context): RuleDataset =
            when (DataPlaneControl.workMode(context)) {
                DataPlaneControl.WORK_MODE_EXPRESS -> EXPRESS
                DataPlaneControl.WORK_MODE_SERVER -> SERVER
                else -> NORMAL
            }
    }
}
