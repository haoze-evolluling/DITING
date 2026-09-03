package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.SubscriptionImportState
import androidx.room.withTransaction

/** Restores a consistent state after the process dies during an import. */
object SubscriptionImportRecovery {
    private const val INITIAL_IMPORT_INTERRUPTION_ERROR = "首次导入因应用意外终止而中断，残留规则已清理，请重新导入"
    private const val UPDATE_INTERRUPTION_ERROR = "更新因应用意外终止而中断，已保留原有规则，请重新更新"

    suspend fun recoverInterruptedImports(database: AppDatabase) {
        database.subscriptionDao().importing().forEach { subscription ->
            database.withTransaction {
                val stagingSource = "staging_sub_${subscription.id}"
                database.blockRuleDao().deleteBySource(stagingSource)
                database.allowRuleDao().deleteBySource(stagingSource)
                database.rewriteRuleDao().deleteBySource(stagingSource)
                if (subscription.ruleCount == 0 && subscription.lastUpdated == 0L) {
                    val source = "sub_${subscription.id}"
                    database.blockRuleDao().deleteBySource(source)
                    database.allowRuleDao().deleteBySource(source)
                    database.rewriteRuleDao().deleteBySource(source)
                    database.subscriptionDao().markInterruptedImportFailed(
                        subscription.id,
                        SubscriptionImportState.FAILED,
                        INITIAL_IMPORT_INTERRUPTION_ERROR
                    )
                } else {
                    database.subscriptionDao().setImportState(
                        subscription.id,
                        SubscriptionImportState.FAILED,
                        UPDATE_INTERRUPTION_ERROR
                    )
                }
            }
        }
    }
}
