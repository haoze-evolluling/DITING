package com.haoze.diting.core.rule

import android.content.Context
import com.haoze.diting.control.DataPlaneControl

enum class RuleDataset {
    NORMAL,
    EXPRESS;

    fun prefsName(): String = when (this) {
        NORMAL -> "dns_vpn_prefs"
        EXPRESS -> "diting_express_prefs"
    }

    fun rulesDatabase(): String = when (this) {
        NORMAL -> StorageContract.NORMAL_RULES
        EXPRESS -> StorageContract.EXPRESS_RULES
    }

    fun logsDatabase(): String = when (this) {
        NORMAL -> StorageContract.NORMAL_LOGS
        EXPRESS -> StorageContract.EXPRESS_LOGS
    }

    companion object {
        fun active(context: Context): RuleDataset =
            when (DataPlaneControl.workMode(context)) {
                DataPlaneControl.WORK_MODE_EXPRESS -> EXPRESS
                else -> NORMAL
            }
    }
}
