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
import com.haoze.diting.ui.settings.SystemSettingsStore

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
        AppTrafficDailyEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun dnsCacheDao(): DnsCacheDao
    abstract fun dnsLogDao(): DnsLogDao
    abstract fun httpRequestLogDao(): HttpRequestLogDao
    abstract fun raceLogDao(): RaceLogDao
    abstract fun bootstrapLogDao(): BootstrapLogDao
    abstract fun blockRuleDao(): BlockRuleDao
    abstract fun allowRuleDao(): AllowRuleDao
    abstract fun subscriptionDao(): SubscriptionDao
    abstract fun subscriptionGroupDao(): SubscriptionGroupDao
    abstract fun subscriptionAutoUpdateDao(): SubscriptionAutoUpdateDao
    abstract fun mirrorTemplateDao(): MirrorTemplateDao
    abstract fun rewriteRuleDao(): RewriteRuleDao
    abstract fun goUrlRuleDao(): GoUrlRuleDao
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
