package com.haoze.diting.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.BootstrapLogDao
import com.haoze.diting.data.dao.CosmeticRuleDao
import com.haoze.diting.data.dao.DnsCacheDao
import com.haoze.diting.data.dao.DnsLogDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.dao.MirrorTemplateDao
import com.haoze.diting.data.dao.RaceLogDao
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.dao.SubscriptionGroupDao
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.AllowRuleSourceEntity
import com.haoze.diting.data.entity.BlockRuleEntity
import com.haoze.diting.data.entity.BlockRuleSourceEntity
import com.haoze.diting.data.entity.BootstrapLogEntity
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleSourceEntity
import com.haoze.diting.data.entity.DnsCacheEntity
import com.haoze.diting.data.entity.DnsLogEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleSourceEntity
import com.haoze.diting.data.entity.MirrorTemplateEntity
import com.haoze.diting.data.entity.RaceLogEntity
import com.haoze.diting.data.entity.RewriteRuleEntity
import com.haoze.diting.data.entity.RewriteRuleSourceEntity
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.diting.data.entity.SubscriptionEntity
import com.haoze.diting.data.entity.SubscriptionGroupEntity

/**
 * Dedicated database for Express Mode (EXPRESS).
 *
 * Fully physically isolated from AppDatabase (NORMAL) and DnsRulesDatabase (DNS_MODE).
 * Contains domain rule tables, subscriptions, and 4 runtime tables (dns_cache,
 * dns_log, race_log, bootstrap_log). Explicitly excludes HttpRequestLogEntity and
 * AppTrafficDailyEntity.
 */
@Database(
    entities = [
        DnsCacheEntity::class,
        DnsLogEntity::class,
        RaceLogEntity::class,
        BootstrapLogEntity::class,
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
        GoUrlRuleSourceEntity::class,
        CosmeticRuleEntity::class,
        CosmeticRuleSourceEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class ExpressRulesDatabase : RoomDatabase(), RuleDataSources, DnsRuntimeDataSources {
    abstract override fun dnsCacheDao(): DnsCacheDao
    abstract override fun dnsLogDao(): DnsLogDao
    abstract override fun raceLogDao(): RaceLogDao
    abstract override fun bootstrapLogDao(): BootstrapLogDao
    abstract override fun blockRuleDao(): BlockRuleDao
    abstract override fun allowRuleDao(): AllowRuleDao
    abstract override fun rewriteRuleDao(): RewriteRuleDao
    abstract override fun subscriptionDao(): SubscriptionDao
    abstract override fun subscriptionGroupDao(): SubscriptionGroupDao
    abstract override fun subscriptionAutoUpdateDao(): SubscriptionAutoUpdateDao
    abstract override fun mirrorTemplateDao(): MirrorTemplateDao
    abstract override fun goUrlRuleDao(): GoUrlRuleDao
    abstract override fun cosmeticRuleDao(): CosmeticRuleDao

    companion object {
        private const val DATABASE_NAME = "diting_express"

        @Volatile
        private var INSTANCE: ExpressRulesDatabase? = null

        fun getInstance(context: Context): ExpressRulesDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    ExpressRulesDatabase::class.java,
                    DATABASE_NAME
                )
                    .setJournalMode(RoomDatabase.JournalMode.WRITE_AHEAD_LOGGING)
                    .fallbackToDestructiveMigration(true)
                    .build().also { INSTANCE = it }
            }
        }
    }
}
