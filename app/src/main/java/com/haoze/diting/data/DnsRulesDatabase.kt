package com.haoze.diting.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.dao.MirrorTemplateDao
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.dao.SubscriptionGroupDao
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.AllowRuleSourceEntity
import com.haoze.diting.data.entity.BlockRuleEntity
import com.haoze.diting.data.entity.BlockRuleSourceEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleSourceEntity
import com.haoze.diting.data.entity.MirrorTemplateEntity
import com.haoze.diting.data.entity.RewriteRuleEntity
import com.haoze.diting.data.entity.RewriteRuleSourceEntity
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.diting.data.entity.SubscriptionEntity
import com.haoze.diting.data.entity.SubscriptionGroupEntity

/**
 * Dedicated rule database for DNS mode. It reuses the same entity and DAO
 * classes as AppDatabase but stores everything in a separate SQLite file, so
 * the DNS mode malicious-domain filtering has fully independent rule data:
 * nothing written here is visible to VPN mode and vice versa. Starts empty —
 * no data is ever migrated from the normal mode database.
 */
@Database(
    entities = [
        BlockRuleEntity::class,
        BlockRuleSourceEntity::class,
        AllowRuleEntity::class,
        AllowRuleSourceEntity::class,
        SubscriptionEntity::class,
        SubscriptionGroupEntity::class,
        SubscriptionAutoUpdateItemEntity::class,
        RewriteRuleEntity::class,
        RewriteRuleSourceEntity::class,
        MirrorTemplateEntity::class,
        GoUrlRuleEntity::class,
        GoUrlRuleSourceEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class DnsRulesDatabase : RoomDatabase(), RuleDataSources {
    abstract override fun blockRuleDao(): BlockRuleDao
    abstract override fun allowRuleDao(): AllowRuleDao
    abstract override fun rewriteRuleDao(): RewriteRuleDao
    abstract override fun subscriptionDao(): SubscriptionDao
    abstract override fun subscriptionGroupDao(): SubscriptionGroupDao
    abstract override fun subscriptionAutoUpdateDao(): SubscriptionAutoUpdateDao
    abstract override fun mirrorTemplateDao(): MirrorTemplateDao
    abstract override fun goUrlRuleDao(): GoUrlRuleDao

    companion object {
        private const val DATABASE_NAME = "diting_dns_rules"

        @Volatile
        private var INSTANCE: DnsRulesDatabase? = null

        fun getInstance(context: Context): DnsRulesDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    DnsRulesDatabase::class.java,
                    DATABASE_NAME
                )
                    .setJournalMode(RoomDatabase.JournalMode.WRITE_AHEAD_LOGGING)
                    .fallbackToDestructiveMigration(true)
                    .build().also { INSTANCE = it }
            }
        }
    }
}

/** Resolves the rule data sources for a dataset; both instances are singletons. */
object RuleDatabases {
    fun forDataset(context: Context, dataset: RuleDataset): RuleDataSources = when (dataset) {
        RuleDataset.NORMAL -> AppDatabase.getInstance(context)
        RuleDataset.DNS_MODE -> DnsRulesDatabase.getInstance(context)
    }

    /** Same singleton as [forDataset], typed for Room transactions. */
    fun forDatasetDb(context: Context, dataset: RuleDataset): RoomDatabase = when (dataset) {
        RuleDataset.NORMAL -> AppDatabase.getInstance(context)
        RuleDataset.DNS_MODE -> DnsRulesDatabase.getInstance(context)
    }
}
