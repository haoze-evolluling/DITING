package com.haoze.diting.vpn

import androidx.room.RoomDatabase
import androidx.room.withTransaction
import com.haoze.diting.data.RuleDataSources
import com.haoze.diting.data.entity.SubscriptionImportState

/** Restores a consistent state after the process dies during an import. */
object SubscriptionImportRecovery {
    private const val INITIAL_IMPORT_INTERRUPTION_ERROR = "首次导入因应用意外终止而中断，残留规则已清理，请重新导入"
    private const val UPDATE_INTERRUPTION_ERROR = "更新因应用意外终止而中断，已保留原有规则，请重新更新"

    /**
     * Works on any rule database: the room instance provides transactions and
     * the sources provide the rule DAOs of the same dataset.
     */
    suspend fun recoverInterruptedImports(room: RoomDatabase, sources: RuleDataSources) {
        sources.subscriptionDao().importing().forEach { subscription ->
            room.withTransaction {
                val stagingSource = "staging_sub_${subscription.id}"
                sources.blockRuleDao().deleteBySource(stagingSource)
                sources.allowRuleDao().deleteBySource(stagingSource)
                sources.rewriteRuleDao().deleteBySource(stagingSource)
                if (subscription.ruleCount == 0 && subscription.lastUpdated == 0L) {
                    val source = "sub_${subscription.id}"
                    sources.blockRuleDao().deleteBySource(source)
                    sources.allowRuleDao().deleteBySource(source)
                    sources.rewriteRuleDao().deleteBySource(source)
                    sources.subscriptionDao().markInterruptedImportFailed(
                        subscription.id,
                        SubscriptionImportState.FAILED,
                        INITIAL_IMPORT_INTERRUPTION_ERROR
                    )
                } else {
                    sources.subscriptionDao().setImportState(
                        subscription.id,
                        SubscriptionImportState.FAILED,
                        UPDATE_INTERRUPTION_ERROR
                    )
                }
            }
        }
    }
}
