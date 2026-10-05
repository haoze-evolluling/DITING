package com.haoze.diting.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.BootstrapLogDao
import com.haoze.diting.data.dao.DnsCacheDao
import com.haoze.diting.data.dao.DnsLogDao
import com.haoze.diting.data.dao.HttpRequestLogDao
import com.haoze.diting.data.dao.RaceLogDao
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.dao.SubscriptionGroupDao
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.AllowRuleSourceEntity
import com.haoze.diting.data.entity.BlockRuleEntity
import com.haoze.diting.data.entity.BlockRuleSourceEntity
import com.haoze.diting.data.entity.BootstrapLogEntity
import com.haoze.diting.data.entity.DnsCacheEntity
import com.haoze.diting.data.entity.DnsLogEntity
import com.haoze.diting.data.entity.HttpRequestLogEntity
import com.haoze.diting.data.entity.RaceLogEntity
import com.haoze.diting.data.entity.RewriteRuleEntity
import com.haoze.diting.data.entity.RewriteRuleSourceEntity
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.entity.SubscriptionEntity
import com.haoze.diting.data.entity.SubscriptionGroupEntity
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.diting.data.entity.MirrorTemplateEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleSourceEntity
import com.haoze.diting.data.dao.MirrorTemplateDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.entity.AppTrafficDailyEntity
import com.haoze.diting.data.dao.AppTrafficDao
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleSourceEntity
import com.haoze.diting.data.dao.CosmeticRuleDao
import androidx.room.migration.Migration
import com.haoze.diting.ui.settings.SystemSettingsStore

val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS cosmetic_rule (
                id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                domain TEXT NOT NULL,
                selector TEXT NOT NULL,
                rawLine TEXT NOT NULL,
                addedAt INTEGER NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1
            )
            """.trimIndent()
        )
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS index_cosmetic_rule_domain_selector ON cosmetic_rule (domain, selector)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS cosmetic_rule_source (
                ruleId INTEGER NOT NULL,
                source TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                PRIMARY KEY(ruleId, source)
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS index_cosmetic_rule_source_source ON cosmetic_rule_source (source)")
    }
}

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
        HttpRequestLogEntity::class,
        RewriteRuleEntity::class,
        RewriteRuleSourceEntity::class,
        MirrorTemplateEntity::class,
        GoUrlRuleEntity::class,
        GoUrlRuleSourceEntity::class,
        AppTrafficDailyEntity::class,
        CosmeticRuleEntity::class,
        CosmeticRuleSourceEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase(), RuleDataSources, DnsRuntimeDataSources {
    abstract override fun dnsCacheDao(): DnsCacheDao
    abstract override fun dnsLogDao(): DnsLogDao
    abstract fun httpRequestLogDao(): HttpRequestLogDao
    abstract override fun raceLogDao(): RaceLogDao
    abstract override fun bootstrapLogDao(): BootstrapLogDao
    abstract override fun blockRuleDao(): BlockRuleDao
    abstract override fun allowRuleDao(): AllowRuleDao
    abstract override fun subscriptionDao(): SubscriptionDao
    abstract override fun subscriptionGroupDao(): SubscriptionGroupDao
    abstract override fun subscriptionAutoUpdateDao(): SubscriptionAutoUpdateDao
    abstract override fun mirrorTemplateDao(): MirrorTemplateDao
    abstract override fun rewriteRuleDao(): RewriteRuleDao
    abstract override fun goUrlRuleDao(): GoUrlRuleDao
    abstract override fun cosmeticRuleDao(): CosmeticRuleDao
    abstract fun appTrafficDao(): AppTrafficDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "diting_database"
                )
                    .setJournalMode(RoomDatabase.JournalMode.WRITE_AHEAD_LOGGING)
                    .addMigrations(MIGRATION_1_2)
                    .fallbackToDestructiveMigration(true)
                    .addCallback(object : RoomDatabase.Callback() {
                        override fun onOpen(db: SupportSQLiteDatabase) {
                            super.onOpen(db)
                            db.execSQL("PRAGMA synchronous = NORMAL")
                        }

                        override fun onDestructiveMigration(db: SupportSQLiteDatabase) {
                            super.onDestructiveMigration(db)
                            SystemSettingsStore.setDataResetNoticePending(context.applicationContext, true)
                        }
                    })
                    .build().also { INSTANCE = it }
            }
        }
    }
}
