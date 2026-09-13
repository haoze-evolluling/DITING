package com.haoze.dnssr.data

import android.content.Context
import androidx.room.Database
import androidx.room.migration.Migration
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import com.haoze.dnssr.data.dao.AllowRuleDao
import com.haoze.dnssr.data.dao.BlockRuleDao
import com.haoze.dnssr.data.dao.BootstrapLogDao
import com.haoze.dnssr.data.dao.DnsCacheDao
import com.haoze.dnssr.data.dao.DnsLogDao
import com.haoze.dnssr.data.dao.HttpRequestLogDao
import com.haoze.dnssr.data.dao.RaceLogDao
import com.haoze.dnssr.data.dao.SubscriptionDao
import com.haoze.dnssr.data.dao.SubscriptionGroupDao
import com.haoze.dnssr.data.dao.SubscriptionAutoUpdateDao
import com.haoze.dnssr.data.entity.AllowRuleEntity
import com.haoze.dnssr.data.entity.AllowRuleSourceEntity
import com.haoze.dnssr.data.entity.BlockRuleEntity
import com.haoze.dnssr.data.entity.BlockRuleSourceEntity
import com.haoze.dnssr.data.entity.BootstrapLogEntity
import com.haoze.dnssr.data.entity.DnsCacheEntity
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import com.haoze.dnssr.data.entity.RaceLogEntity
import com.haoze.dnssr.data.entity.RewriteRuleEntity
import com.haoze.dnssr.data.entity.RewriteRuleSourceEntity
import com.haoze.dnssr.data.dao.RewriteRuleDao
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.data.entity.GoUrlRuleEntity
import com.haoze.dnssr.data.entity.GoUrlRuleSourceEntity
import com.haoze.dnssr.data.dao.MirrorTemplateDao
import com.haoze.dnssr.data.dao.GoUrlRuleDao
import com.haoze.dnssr.data.entity.AppTrafficDailyEntity
import com.haoze.dnssr.data.dao.AppTrafficDao

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
        HttpRequestLogEntity::class
        ,RewriteRuleEntity::class, RewriteRuleSourceEntity::class, MirrorTemplateEntity::class,
        GoUrlRuleEntity::class, GoUrlRuleSourceEntity::class,
        AppTrafficDailyEntity::class
    ],
    version = 35,
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
                    "dnssr_database"
                )
                    .addMigrations(
                        MIGRATION_29_30,
                        MIGRATION_30_31,
                        MIGRATION_31_32,
                        MIGRATION_32_33,
                        MIGRATION_33_34,
                        MIGRATION_34_35
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
                            com.haoze.dnssr.ui.AppSettings.setDataResetNoticePending(context.applicationContext, true)
                        }
                    })
                    .build().also { INSTANCE = it }
            }
        }

        private val MIGRATION_29_30 = object : Migration(29, 30) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `block_rule` ADD COLUMN `appScope` TEXT DEFAULT NULL")
                db.execSQL("ALTER TABLE `block_rule` ADD COLUMN `appInverted` INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE `block_rule` ADD COLUMN `isWildcard` INTEGER NOT NULL DEFAULT 0")
                db.execSQL("UPDATE `block_rule` SET `isWildcard` = 1 WHERE `pattern` GLOB '*[*]*' OR `pattern` = '*'")
                db.execSQL("DROP INDEX IF EXISTS `index_block_rule_pattern_important_scope`")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_block_rule_pattern_important_scope_appScope_appInverted` " +
                        "ON `block_rule` (`pattern`, `important`, `scope`, `appScope`, `appInverted`)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_block_rule_appScope` ON `block_rule` (`appScope`)")

                db.execSQL("ALTER TABLE `allow_rule` ADD COLUMN `appScope` TEXT DEFAULT NULL")
                db.execSQL("ALTER TABLE `allow_rule` ADD COLUMN `appInverted` INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE `allow_rule` ADD COLUMN `isWildcard` INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE `allow_rule` ADD COLUMN `important` INTEGER NOT NULL DEFAULT 0")
                db.execSQL("UPDATE `allow_rule` SET `isWildcard` = 1 WHERE `pattern` GLOB '*[*]*' OR `pattern` = '*'")
                db.execSQL("DROP INDEX IF EXISTS `index_allow_rule_pattern_scope`")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_allow_rule_pattern_important_scope_appScope_appInverted` " +
                        "ON `allow_rule` (`pattern`, `important`, `scope`, `appScope`, `appInverted`)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_allow_rule_appScope` ON `allow_rule` (`appScope`)")
            }
        }

        private val MIGRATION_30_31 = object : Migration(30, 31) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `dns_log` ADD COLUMN `packageName` TEXT DEFAULT NULL")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_dns_log_packageName` ON `dns_log` (`packageName`)")
            }
        }

        private val MIGRATION_31_32 = object : Migration(31, 32) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // Recreate block_rule and block_rule_source without scope column
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `block_rule_new` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `pattern` TEXT NOT NULL,
                        `rawLine` TEXT NOT NULL,
                        `addedAt` INTEGER NOT NULL,
                        `enabled` INTEGER NOT NULL,
                        `groupName` TEXT,
                        `important` INTEGER NOT NULL,
                        `appScope` TEXT,
                        `appInverted` INTEGER NOT NULL,
                        `isWildcard` INTEGER NOT NULL
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT INTO `block_rule_new` (`id`, `pattern`, `rawLine`, `addedAt`, `enabled`, `groupName`, `important`, `appScope`, `appInverted`, `isWildcard`)
                    SELECT `id`, `pattern`, `rawLine`, `addedAt`, `enabled`, `groupName`, `important`, `appScope`, `appInverted`, `isWildcard` FROM `block_rule`
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `block_rule_source_new` (
                        `ruleId` INTEGER NOT NULL,
                        `source` TEXT NOT NULL,
                        `enabled` INTEGER NOT NULL,
                        PRIMARY KEY(`ruleId`, `source`),
                        FOREIGN KEY(`ruleId`) REFERENCES `block_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT INTO `block_rule_source_new` (`ruleId`, `source`, `enabled`)
                    SELECT `ruleId`, `source`, `enabled` FROM `block_rule_source`
                    """.trimIndent()
                )
                db.execSQL("DROP TABLE IF EXISTS `block_rule_source`")
                db.execSQL("DROP TABLE IF EXISTS `block_rule`")
                db.execSQL("ALTER TABLE `block_rule_new` RENAME TO `block_rule`")
                db.execSQL("ALTER TABLE `block_rule_source_new` RENAME TO `block_rule_source`")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_block_rule_pattern_important_appScope_appInverted` " +
                        "ON `block_rule` (`pattern`, `important`, `appScope`, `appInverted`)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_block_rule_appScope` ON `block_rule` (`appScope`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_block_rule_source_source` ON `block_rule_source` (`source`)")

                // Recreate allow_rule and allow_rule_source without scope column
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `allow_rule_new` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `pattern` TEXT NOT NULL,
                        `rawLine` TEXT NOT NULL,
                        `addedAt` INTEGER NOT NULL,
                        `enabled` INTEGER NOT NULL,
                        `groupName` TEXT,
                        `appScope` TEXT,
                        `appInverted` INTEGER NOT NULL,
                        `isWildcard` INTEGER NOT NULL,
                        `important` INTEGER NOT NULL
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT INTO `allow_rule_new` (`id`, `pattern`, `rawLine`, `addedAt`, `enabled`, `groupName`, `appScope`, `appInverted`, `isWildcard`, `important`)
                    SELECT `id`, `pattern`, `rawLine`, `addedAt`, `enabled`, `groupName`, `appScope`, `appInverted`, `isWildcard`, `important` FROM `allow_rule`
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `allow_rule_source_new` (
                        `ruleId` INTEGER NOT NULL,
                        `source` TEXT NOT NULL,
                        `enabled` INTEGER NOT NULL,
                        PRIMARY KEY(`ruleId`, `source`),
                        FOREIGN KEY(`ruleId`) REFERENCES `allow_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT INTO `allow_rule_source_new` (`ruleId`, `source`, `enabled`)
                    SELECT `ruleId`, `source`, `enabled` FROM `allow_rule_source`
                    """.trimIndent()
                )
                db.execSQL("DROP TABLE IF EXISTS `allow_rule_source`")
                db.execSQL("DROP TABLE IF EXISTS `allow_rule`")
                db.execSQL("ALTER TABLE `allow_rule_new` RENAME TO `allow_rule`")
                db.execSQL("ALTER TABLE `allow_rule_source_new` RENAME TO `allow_rule_source`")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_allow_rule_pattern_important_appScope_appInverted` " +
                        "ON `allow_rule` (`pattern`, `important`, `appScope`, `appInverted`)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_allow_rule_appScope` ON `allow_rule` (`appScope`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_allow_rule_source_source` ON `allow_rule_source` (`source`)")

                // Recreate rewrite_rule and rewrite_rule_source without scope column
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `rewrite_rule_new` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `pattern` TEXT NOT NULL,
                        `targetType` TEXT NOT NULL,
                        `targetValue` TEXT NOT NULL,
                        `rawLine` TEXT NOT NULL,
                        `addedAt` INTEGER NOT NULL,
                        `enabled` INTEGER NOT NULL
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT INTO `rewrite_rule_new` (`id`, `pattern`, `targetType`, `targetValue`, `rawLine`, `addedAt`, `enabled`)
                    SELECT `id`, `pattern`, `targetType`, `targetValue`, `rawLine`, `addedAt`, `enabled` FROM `rewrite_rule`
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `rewrite_rule_source_new` (
                        `ruleId` INTEGER NOT NULL,
                        `source` TEXT NOT NULL,
                        `enabled` INTEGER NOT NULL,
                        PRIMARY KEY(`ruleId`, `source`),
                        FOREIGN KEY(`ruleId`) REFERENCES `rewrite_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT INTO `rewrite_rule_source_new` (`ruleId`, `source`, `enabled`)
                    SELECT `ruleId`, `source`, `enabled` FROM `rewrite_rule_source`
                    """.trimIndent()
                )
                db.execSQL("DROP TABLE IF EXISTS `rewrite_rule_source`")
                db.execSQL("DROP TABLE IF EXISTS `rewrite_rule`")
                db.execSQL("ALTER TABLE `rewrite_rule_new` RENAME TO `rewrite_rule`")
                db.execSQL("ALTER TABLE `rewrite_rule_source_new` RENAME TO `rewrite_rule_source`")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_rewrite_rule_pattern_targetType_targetValue` " +
                        "ON `rewrite_rule` (`pattern`, `targetType`, `targetValue`)"
                )

                // Recreate subscription without scope column
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `subscription_new` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `url` TEXT NOT NULL,
                        `name` TEXT NOT NULL,
                        `sourceType` TEXT NOT NULL,
                        `kind` TEXT NOT NULL,
                        `enabled` INTEGER NOT NULL,
                        `ruleCount` INTEGER NOT NULL,
                        `lastUpdated` INTEGER NOT NULL,
                        `addedAt` INTEGER NOT NULL,
                        `importState` TEXT NOT NULL,
                        `importError` TEXT,
                        `httpEtag` TEXT,
                        `httpLastModified` TEXT,
                        `ruleSetHash` TEXT,
                        `lastAttemptAt` INTEGER NOT NULL,
                        `consecutiveFailureCount` INTEGER NOT NULL,
                        `mirrorTemplate` TEXT,
                        `mirrorFallback` INTEGER NOT NULL,
                        `groupId` INTEGER
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT INTO `subscription_new` (`id`, `url`, `name`, `sourceType`, `kind`, `enabled`, `ruleCount`, `lastUpdated`, `addedAt`, `importState`, `importError`, `httpEtag`, `httpLastModified`, `ruleSetHash`, `lastAttemptAt`, `consecutiveFailureCount`, `mirrorTemplate`, `mirrorFallback`, `groupId`)
                    SELECT `id`, `url`, `name`, `sourceType`, `kind`, `enabled`, `ruleCount`, `lastUpdated`, `addedAt`, `importState`, `importError`, `httpEtag`, `httpLastModified`, `ruleSetHash`, `lastAttemptAt`, `consecutiveFailureCount`, `mirrorTemplate`, `mirrorFallback`, `groupId` FROM `subscription`
                    """.trimIndent()
                )
                db.execSQL("DROP TABLE IF EXISTS `subscription`")
                db.execSQL("ALTER TABLE `subscription_new` RENAME TO `subscription`")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_subscription_url` ON `subscription` (`url`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_subscription_groupId` ON `subscription` (`groupId`)")
            }
        }

        private val MIGRATION_32_33 = object : Migration(32, 33) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_block_rule_source_source` ON `block_rule_source` (`source`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_allow_rule_source_source` ON `allow_rule_source` (`source`)")
            }
        }

        private val MIGRATION_33_34 = object : Migration(33, 34) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `app_traffic_daily` (
                        `date` TEXT NOT NULL,
                        `package_name` TEXT NOT NULL,
                        `app_name` TEXT NOT NULL,
                        `tx_bytes` INTEGER NOT NULL,
                        `rx_bytes` INTEGER NOT NULL,
                        `updated_at` INTEGER NOT NULL,
                        PRIMARY KEY(`date`, `package_name`)
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_app_traffic_daily_date` ON `app_traffic_daily` (`date`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_app_traffic_daily_package_name` ON `app_traffic_daily` (`package_name`)")
            }
        }

        private val MIGRATION_34_35 = object : Migration(34, 35) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_rewrite_rule_source_source` ON `rewrite_rule_source` (`source`)")
            }
        }
    }
}
