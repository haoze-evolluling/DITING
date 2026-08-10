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
        GoUrlRuleEntity::class, GoUrlRuleSourceEntity::class
    ],
    version = 29,
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
                        MIGRATION_10_11,
                        MIGRATION_11_12,
                        MIGRATION_12_13,
                        MIGRATION_13_14,
                        MIGRATION_14_15,
                        MIGRATION_15_16,
                        MIGRATION_16_17,
                        MIGRATION_17_18,
                        MIGRATION_18_19,
                        MIGRATION_19_20,
                        MIGRATION_20_21,
                        MIGRATION_21_22,
                        MIGRATION_22_23,
                        MIGRATION_23_24,
                        MIGRATION_24_25,
                        MIGRATION_25_26,
                        MIGRATION_26_27,
                        MIGRATION_27_28,
                        MIGRATION_28_29
                    )
                    .build().also { INSTANCE = it }
            }
        }

        private val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `allow_rule` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `pattern` TEXT NOT NULL,
                        `rawLine` TEXT NOT NULL,
                        `addedAt` INTEGER NOT NULL,
                        `enabled` INTEGER NOT NULL,
                        `source` TEXT NOT NULL,
                        `groupName` TEXT
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_allow_rule_pattern` ON `allow_rule` (`pattern`)")
                db.execSQL("ALTER TABLE `subscription` ADD COLUMN `kind` TEXT NOT NULL DEFAULT 'block'")
                db.execSQL("DROP INDEX IF EXISTS `index_subscription_url`")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_subscription_url_kind` ON `subscription` (`url`, `kind`)")
            }
        }

        private val MIGRATION_11_12 = object : Migration(11, 12) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `dns_log` ADD COLUMN `blockSubscriptionId` INTEGER")
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_dns_log_block_subscription_timestamp` " +
                        "ON `dns_log` (`blockSubscriptionId`, `timestamp`)"
                )
            }
        }

        private val MIGRATION_12_13 = object : Migration(12, 13) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "ALTER TABLE `subscription` ADD COLUMN `sourceType` TEXT NOT NULL DEFAULT 'remote'"
                )
            }
        }

        private val MIGRATION_13_14 = object : Migration(13, 14) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TEMP TABLE subscription_merge AS " +
                        "SELECT s.id AS oldId, (SELECT MIN(k.id) FROM subscription k " +
                        "WHERE LOWER(k.url) = LOWER(s.url)) AS keepId FROM subscription s"
                )
                db.execSQL(
                    "UPDATE block_rule SET source = 'sub_' || " +
                        "(SELECT keepId FROM subscription_merge WHERE oldId = " +
                        "CAST(SUBSTR(block_rule.source, 5) AS INTEGER)) " +
                        "WHERE source LIKE 'sub_%' AND EXISTS " +
                        "(SELECT 1 FROM subscription_merge WHERE oldId = CAST(SUBSTR(block_rule.source, 5) AS INTEGER))"
                )
                db.execSQL(
                    "UPDATE allow_rule SET source = 'sub_' || " +
                        "(SELECT keepId FROM subscription_merge WHERE oldId = " +
                        "CAST(SUBSTR(allow_rule.source, 5) AS INTEGER)) " +
                        "WHERE source LIKE 'sub_%' AND EXISTS " +
                        "(SELECT 1 FROM subscription_merge WHERE oldId = CAST(SUBSTR(allow_rule.source, 5) AS INTEGER))"
                )
                db.execSQL("DELETE FROM subscription WHERE id NOT IN (SELECT keepId FROM subscription_merge)")
                db.execSQL("UPDATE subscription SET kind = 'block'")
                db.execSQL("DROP TABLE subscription_merge")

                db.execSQL("DROP INDEX IF EXISTS index_block_rule_pattern")
                db.execSQL("DROP INDEX IF EXISTS index_allow_rule_pattern")
                db.execSQL("DROP INDEX IF EXISTS index_subscription_url_kind")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS index_block_rule_pattern_source " +
                        "ON block_rule (pattern, source)"
                )
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS index_allow_rule_pattern_source " +
                        "ON allow_rule (pattern, source)"
                )
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS index_subscription_url ON subscription (url)"
                )
            }
        }

        private val MIGRATION_14_15 = object : Migration(14, 15) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "ALTER TABLE `subscription` ADD COLUMN `importState` TEXT NOT NULL DEFAULT 'ready'"
                )
                db.execSQL("ALTER TABLE `subscription` ADD COLUMN `importError` TEXT")
            }
        }

        private val MIGRATION_15_16 = object : Migration(15, 16) {
            override fun migrate(db: SupportSQLiteDatabase) {
                migrateRuleTable(db, "block_rule")
                migrateRuleTable(db, "allow_rule")
            }

            private fun migrateRuleTable(db: SupportSQLiteDatabase, table: String) {
                val newTable = "${table}_new"
                val sourceData = "${table}_source_data"
                val sourceTable = "${table}_source"

                db.execSQL(
                    "CREATE TABLE `$newTable` (" +
                        "`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`pattern` TEXT NOT NULL, `rawLine` TEXT NOT NULL, " +
                        "`addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL, `groupName` TEXT)"
                )
                db.execSQL(
                    "INSERT INTO `$newTable` (`id`, `pattern`, `rawLine`, `addedAt`, `enabled`, `groupName`) " +
                        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
                        "(SELECT MAX(e.enabled) FROM `$table` e WHERE e.pattern = r.pattern), r.groupName " +
                        "FROM `$table` r WHERE r.id = " +
                        "(SELECT MIN(k.id) FROM `$table` k WHERE k.pattern = r.pattern)"
                )
                db.execSQL(
                    "CREATE TEMP TABLE `$sourceData` AS " +
                        "SELECT n.id AS ruleId, o.source AS source, MAX(o.enabled) AS enabled " +
                        "FROM `$table` o JOIN `$newTable` n ON n.pattern = o.pattern " +
                        "GROUP BY n.id, o.source"
                )
                db.execSQL("DROP TABLE `$table`")
                db.execSQL("ALTER TABLE `$newTable` RENAME TO `$table`")
                db.execSQL("CREATE UNIQUE INDEX `index_${table}_pattern` ON `$table` (`pattern`)")
                db.execSQL(
                    "CREATE TABLE `$sourceTable` (" +
                        "`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, " +
                        "PRIMARY KEY(`ruleId`, `source`), " +
                        "FOREIGN KEY(`ruleId`) REFERENCES `$table`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE)"
                )
                db.execSQL(
                    "INSERT INTO `$sourceTable` (`ruleId`, `source`, `enabled`) " +
                        "SELECT ruleId, source, enabled FROM `$sourceData`"
                )
                db.execSQL("CREATE INDEX `index_${sourceTable}_source` ON `$sourceTable` (`source`)")
                db.execSQL("DROP TABLE `$sourceData`")
            }
        }

        private val MIGRATION_16_17 = object : Migration(16, 17) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `subscription` ADD COLUMN `httpEtag` TEXT")
                db.execSQL("ALTER TABLE `subscription` ADD COLUMN `httpLastModified` TEXT")
                db.execSQL("ALTER TABLE `subscription` ADD COLUMN `ruleSetHash` TEXT")
                db.execSQL("ALTER TABLE `subscription` ADD COLUMN `lastAttemptAt` INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE `subscription` ADD COLUMN `consecutiveFailureCount` INTEGER NOT NULL DEFAULT 0")
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `subscription_auto_update_item` (" +
                        "`batchId` TEXT NOT NULL, `subscriptionId` INTEGER NOT NULL, " +
                        "`status` TEXT NOT NULL, `changed` INTEGER NOT NULL, `ruleCount` INTEGER NOT NULL, " +
                        "PRIMARY KEY(`batchId`, `subscriptionId`), " +
                        "FOREIGN KEY(`subscriptionId`) REFERENCES `subscription`(`id`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE)"
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_subscription_auto_update_item_subscriptionId` " +
                        "ON `subscription_auto_update_item` (`subscriptionId`)"
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_subscription_auto_update_item_batchId_status` " +
                        "ON `subscription_auto_update_item` (`batchId`, `status`)"
                )
            }
        }

        private val MIGRATION_17_18 = object : Migration(17, 18) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `http_request_log` (" +
                        "`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`timestamp` INTEGER NOT NULL, `packageName` TEXT NOT NULL, " +
                        "`authority` TEXT, `protocol` TEXT NOT NULL, `outcome` TEXT NOT NULL, " +
                        "`matchedRule` TEXT)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_http_request_log_timestamp` ON `http_request_log` (`timestamp`)")
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_http_request_log_outcome_timestamp` " +
                        "ON `http_request_log` (`outcome`, `timestamp`)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_http_request_log_authority` ON `http_request_log` (`authority`)")
            }
        }
        private val MIGRATION_18_19 = object : Migration(18, 19) { override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("CREATE TABLE IF NOT EXISTS `rewrite_rule` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `pattern` TEXT NOT NULL, `address` TEXT NOT NULL, `rawLine` TEXT NOT NULL, `addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL)")
            db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_rewrite_rule_pattern_address` ON `rewrite_rule` (`pattern`, `address`)")
            db.execSQL("CREATE TABLE IF NOT EXISTS `rewrite_rule_source` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, PRIMARY KEY(`ruleId`, `source`), FOREIGN KEY(`ruleId`) REFERENCES `rewrite_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE)")
        }}
        private val MIGRATION_19_20 = object : Migration(19, 20) { override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("CREATE TABLE `rewrite_rule_source_backup` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL)")
            db.execSQL("CREATE TABLE `rewrite_rule_new` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `pattern` TEXT NOT NULL, `targetType` TEXT NOT NULL, `targetValue` TEXT NOT NULL, `rawLine` TEXT NOT NULL, `addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL)")
            db.execSQL("INSERT INTO rewrite_rule_new (id,pattern,targetType,targetValue,rawLine,addedAt,enabled) SELECT id,pattern,CASE WHEN instr(address, ':') > 0 THEN 'IPv6' ELSE 'IPv4' END,address,rawLine,addedAt,enabled FROM rewrite_rule")
            db.execSQL("INSERT INTO rewrite_rule_source_backup SELECT ruleId,source,enabled FROM rewrite_rule_source")
            db.execSQL("DROP TABLE rewrite_rule_source")
            db.execSQL("DROP TABLE rewrite_rule")
            db.execSQL("ALTER TABLE rewrite_rule_new RENAME TO rewrite_rule")
            db.execSQL("CREATE TABLE `rewrite_rule_source` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, PRIMARY KEY(`ruleId`,`source`), FOREIGN KEY(`ruleId`) REFERENCES `rewrite_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE)")
            db.execSQL("INSERT INTO rewrite_rule_source SELECT ruleId,source,enabled FROM rewrite_rule_source_backup")
            db.execSQL("DROP TABLE rewrite_rule_source_backup")
            db.execSQL("CREATE UNIQUE INDEX `index_rewrite_rule_pattern_targetType_targetValue` ON `rewrite_rule` (`pattern`,`targetType`,`targetValue`)")
        }}
        private val MIGRATION_20_21 = object : Migration(20, 21) { override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE `subscription` ADD COLUMN `mirrorTemplate` TEXT")
            db.execSQL("ALTER TABLE `subscription` ADD COLUMN `mirrorFallback` INTEGER NOT NULL DEFAULT 1")
        }}
        private val MIGRATION_21_22 = object : Migration(21, 22) { override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("CREATE TABLE IF NOT EXISTS `mirror_template` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `name` TEXT NOT NULL, `template` TEXT NOT NULL, `addedAt` INTEGER NOT NULL)")
            db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_mirror_template_name` ON `mirror_template` (`name`)")
        }}
        private val MIGRATION_22_23 = object : Migration(22, 23) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `http_request_log` ADD COLUMN `blockSubscriptionId` INTEGER")
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_http_request_log_block_subscription_timestamp` " +
                        "ON `http_request_log` (`blockSubscriptionId`, `timestamp`)"
                )
            }
        }
        private val MIGRATION_23_24 = object : Migration(23, 24) {
            override fun migrate(db: SupportSQLiteDatabase) {
                listOf("block_rule", "allow_rule", "block_rule_source", "allow_rule_source", "subscription", "rewrite_rule", "rewrite_rule_source")
                    .forEach { db.execSQL("ALTER TABLE `$it` ADD COLUMN `scope` TEXT NOT NULL DEFAULT 'dns'") }
                // CNAME rewriting only exists in the Go full-tunnel path.
                db.execSQL("UPDATE rewrite_rule SET scope = 'https' WHERE targetType = 'CNAME'")
                db.execSQL("UPDATE rewrite_rule_source SET scope = 'https' WHERE ruleId IN (SELECT id FROM rewrite_rule WHERE scope = 'https')")
                db.execSQL("DROP INDEX IF EXISTS `index_block_rule_pattern`")
                db.execSQL("DROP INDEX IF EXISTS `index_allow_rule_pattern`")
                db.execSQL("DROP INDEX IF EXISTS `index_rewrite_rule_pattern_targetType_targetValue`")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_block_rule_pattern_scope` ON `block_rule` (`pattern`, `scope`)")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_allow_rule_pattern_scope` ON `allow_rule` (`pattern`, `scope`)")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_rewrite_rule_pattern_targetType_targetValue_scope` ON `rewrite_rule` (`pattern`, `targetType`, `targetValue`, `scope`)")
            }
        }
        private val MIGRATION_24_25 = object : Migration(24, 25) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS `go_url_rule` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `pattern` TEXT NOT NULL, `kind` TEXT NOT NULL, `rawLine` TEXT NOT NULL, `addedAt` INTEGER NOT NULL, `enabled` INTEGER NOT NULL)")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_go_url_rule_pattern_kind` ON `go_url_rule` (`pattern`, `kind`)")
                db.execSQL("CREATE TABLE IF NOT EXISTS `go_url_rule_source` (`ruleId` INTEGER NOT NULL, `source` TEXT NOT NULL, `enabled` INTEGER NOT NULL, PRIMARY KEY(`ruleId`, `source`), FOREIGN KEY(`ruleId`) REFERENCES `go_url_rule`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_go_url_rule_source_source` ON `go_url_rule_source` (`source`)")
            }
        }
        private val MIGRATION_25_26 = object : Migration(25, 26) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `block_rule` ADD COLUMN `important` INTEGER NOT NULL DEFAULT 0")
                // Existing raw lines retain their effective important modifier after the schema upgrade.
                db.execSQL(
                    "UPDATE `block_rule` SET `important` = 1 WHERE lower(`rawLine`) NOT LIKE '@@%' " +
                        "AND (lower(`rawLine`) GLOB '*${'$'}important' OR lower(`rawLine`) GLOB '*${'$'}important#*' OR lower(`rawLine`) GLOB '*${'$'}important #*')"
                )
                db.execSQL("DROP INDEX IF EXISTS `index_block_rule_pattern_scope`")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_block_rule_pattern_important_scope` ON `block_rule` (`pattern`, `important`, `scope`)")
            }
        }
        private val MIGRATION_26_27 = object : Migration(26, 27) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("DROP INDEX IF EXISTS `index_subscription_url`")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_subscription_url_scope` " +
                        "ON `subscription` (`url`, `scope`)"
                )
            }
        }
        private val MIGRATION_27_28 = object : Migration(27, 28) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `subscription_group` (" +
                        "`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`name` TEXT NOT NULL, `autoUpdateEnabled` INTEGER NOT NULL, `addedAt` INTEGER NOT NULL)"
                )
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_subscription_group_name` ON `subscription_group` (`name`)")
                db.execSQL("ALTER TABLE `subscription` ADD COLUMN `groupId` INTEGER")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_subscription_groupId` ON `subscription` (`groupId`)")
            }
        }
        private val MIGRATION_28_29 = object : Migration(28, 29) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // DNS is the canonical domain-rule scope. Discard the old HTTPS
                // domain rules and subscriptions; URL rules live in their own table.
                listOf("block_rule_source", "allow_rule_source", "rewrite_rule_source").forEach {
                    db.execSQL("DELETE FROM `$it` WHERE scope = 'https'")
                }
                listOf("block_rule", "allow_rule", "rewrite_rule").forEach {
                    db.execSQL("DELETE FROM `$it` WHERE scope = 'https'")
                }
                db.execSQL("DELETE FROM `subscription` WHERE scope = 'https'")
                db.execSQL(
                    "CREATE TABLE `subscription_new` (" +
                        "`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`url` TEXT NOT NULL, `name` TEXT NOT NULL, " +
                        "`sourceType` TEXT NOT NULL, `kind` TEXT NOT NULL, " +
                        "`enabled` INTEGER NOT NULL, `ruleCount` INTEGER NOT NULL, " +
                        "`lastUpdated` INTEGER NOT NULL, `addedAt` INTEGER NOT NULL, " +
                        "`importState` TEXT NOT NULL, `importError` TEXT, " +
                        "`httpEtag` TEXT, `httpLastModified` TEXT, `ruleSetHash` TEXT, " +
                        "`lastAttemptAt` INTEGER NOT NULL, `consecutiveFailureCount` INTEGER NOT NULL, " +
                        "`mirrorTemplate` TEXT, `mirrorFallback` INTEGER NOT NULL, " +
                        "`scope` TEXT NOT NULL, `groupId` INTEGER, " +
                        "FOREIGN KEY(`groupId`) REFERENCES `subscription_group`(`id`) " +
                        "ON UPDATE NO ACTION ON DELETE SET NULL)"
                )
                db.execSQL(
                    "INSERT INTO `subscription_new` (" +
                        "`id`, `url`, `name`, `sourceType`, `kind`, `enabled`, `ruleCount`, " +
                        "`lastUpdated`, `addedAt`, `importState`, `importError`, `httpEtag`, " +
                        "`httpLastModified`, `ruleSetHash`, `lastAttemptAt`, `consecutiveFailureCount`, " +
                        "`mirrorTemplate`, `mirrorFallback`, `scope`, `groupId`) " +
                        "SELECT `id`, `url`, `name`, `sourceType`, `kind`, `enabled`, `ruleCount`, " +
                        "`lastUpdated`, `addedAt`, `importState`, `importError`, `httpEtag`, " +
                        "`httpLastModified`, `ruleSetHash`, `lastAttemptAt`, `consecutiveFailureCount`, " +
                        "`mirrorTemplate`, `mirrorFallback`, `scope`, " +
                        "CASE WHEN `groupId` IN (SELECT `id` FROM `subscription_group`) " +
                        "THEN `groupId` ELSE NULL END FROM `subscription`"
                )
                db.execSQL("DROP TABLE `subscription`")
                db.execSQL("ALTER TABLE `subscription_new` RENAME TO `subscription`")
                db.execSQL(
                    "CREATE UNIQUE INDEX `index_subscription_url_scope` " +
                        "ON `subscription` (`url`, `scope`)"
                )
                db.execSQL("CREATE INDEX `index_subscription_groupId` ON `subscription` (`groupId`)")
            }
        }
    }
}
