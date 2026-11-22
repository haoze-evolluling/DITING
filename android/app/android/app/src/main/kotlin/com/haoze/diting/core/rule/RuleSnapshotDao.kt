package com.haoze.diting.core.rule

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import com.haoze.diting.log.AppDatabase

data class EnabledRule(
    val pattern: String,
    val source: String,
    val important: Boolean = false,
    val appScope: String? = null,
    val appInverted: Boolean = false,
    val isWildcard: Boolean = false,
    val denyallow: String? = null,
    val isRegex: Boolean = false,
    val dnsType: String? = null,
)

data class EnabledRuleKeyset(
    val id: Long,
    val pattern: String,
    val source: String,
    val important: Boolean,
    val appScope: String?,
    val appInverted: Boolean,
    val isWildcard: Boolean,
    val denyallow: String?,
    val isRegex: Boolean,
    val dnsType: String?,
) {
    fun toEnabledRule() = EnabledRule(
        pattern, source, important, appScope, appInverted, isWildcard, denyallow, isRegex, dnsType
    )
}

class RuleSnapshotDao private constructor(private val db: SQLiteDatabase) {

    fun forEachSubscriptionRulePage(kind: RuleKind, important: Boolean? = null, action: (EnabledRule) -> Unit) {
        val ruleTable = kind.ruleTable
        val sourceTable = kind.sourceTable
        val importantClause = if (kind == RuleKind.BLOCK && important != null) " AND r.important = ${if (important) 1 else 0}" else ""
        var lastId = 0L
        while (true) {
            val page = mutableListOf<EnabledRuleKeyset>()
            db.rawQuery(
                "SELECT r.id AS id, r.pattern, MIN(s.source) AS source, r.important AS important, " +
                    "r.appScope AS appScope, r.appInverted AS appInverted, r.isWildcard AS isWildcard, " +
                    "r.denyallow AS denyallow, r.isRegex AS isRegex, r.dnsType AS dnsType FROM $ruleTable r " +
                    "JOIN $sourceTable s ON s.ruleId = r.id " +
                    "WHERE r.id > ? AND r.enabled = 1 AND s.enabled = 1 AND s.source LIKE 'sub_%'$importantClause " +
                    "GROUP BY r.id, r.pattern, r.important, r.appScope, r.appInverted, r.isWildcard, r.denyallow, r.isRegex, r.dnsType " +
                    "ORDER BY r.id LIMIT $PAGE_SIZE",
                arrayOf(lastId.toString()),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    page += EnabledRuleKeyset(
                        id = cursor.getLong(0),
                        pattern = cursor.getString(1),
                        source = cursor.getString(2),
                        important = cursor.getInt(3) != 0,
                        appScope = cursor.getString(4),
                        appInverted = cursor.getInt(5) != 0,
                        isWildcard = cursor.getInt(6) != 0,
                        denyallow = cursor.getString(7),
                        isRegex = cursor.getInt(8) != 0,
                        dnsType = cursor.getString(9),
                    )
                }
            }
            if (page.isEmpty()) return
            page.forEach { action(it.toEnabledRule()) }
            lastId = page.last().id
        }
    }

    fun enabledCustomRules(kind: RuleKind): List<EnabledRule> =
        queryRules(
            RULE_COLUMNS + "${kind.ruleTable} r " +
                "JOIN ${kind.sourceTable} s ON s.ruleId = r.id " +
                "WHERE r.enabled = 1 AND s.enabled = 1 AND s.source NOT LIKE 'sub_%' AND s.source NOT LIKE 'staging_sub_%'" +
                GROUP_BY_RULE
        )

    fun enabledSpecialSubscriptionRules(kind: RuleKind): List<EnabledRule> =
        queryRules(
            RULE_COLUMNS + "${kind.ruleTable} r " +
                "JOIN ${kind.sourceTable} s ON s.ruleId = r.id " +
                "WHERE r.enabled = 1 AND s.enabled = 1 AND s.source LIKE 'sub_%' " +
                "AND (r.isWildcard = 1 OR r.pattern LIKE '%*%' OR r.appScope IS NOT NULL OR r.appInverted = 1 OR r.isRegex = 1 OR r.denyallow IS NOT NULL OR r.dnsType IS NOT NULL)" +
                GROUP_BY_RULE
        )

    private fun queryRules(sql: String): List<EnabledRule> = db.rawQuery(sql, null).use { cursor ->
        val result = ArrayList<EnabledRule>()
        while (cursor.moveToNext()) {
            result += EnabledRule(
                pattern = cursor.getString(0),
                source = cursor.getString(1),
                important = cursor.getInt(2) != 0,
                appScope = cursor.getString(3),
                appInverted = cursor.getInt(4) != 0,
                isWildcard = cursor.getInt(5) != 0,
                denyallow = cursor.getString(6),
                isRegex = cursor.getInt(7) != 0,
                dnsType = cursor.getString(8),
            )
        }
        result
    }

    fun rewriteRules(): List<Pair<String, String>> = db.rawQuery(
        "SELECT pattern, targetValue FROM rewrite_rule " +
            "WHERE enabled = 1 AND EXISTS (SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId = rewrite_rule.id AND s.enabled = 1) " +
            "ORDER BY id",
        null,
    ).use { cursor ->
        val result = LinkedHashMap<String, String>()
        while (cursor.moveToNext()) {
            val pattern = cursor.getString(0)?.trim().orEmpty()
            val target = cursor.getString(1)?.trim().orEmpty()
            if (pattern.isNotEmpty() && target.isNotEmpty()) result.putIfAbsent(pattern, target)
        }
        result.map { (pattern, target) -> pattern to target }
    }

    fun close() = Unit

    fun ruleFingerprint(): String {
        val parts = ArrayList<Pair<String, Triple<Long, Long, Long>?>>(8)
        for (kind in RuleKind.entries) {
            parts += kind.ruleTable to countFingerprint(kind.ruleTable)
            parts += kind.sourceTable to countFingerprint(kind.sourceTable)
        }
        parts += "rewrite_rule" to countFingerprint("rewrite_rule")
        parts += "rewrite_rule_source" to countFingerprint("rewrite_rule_source")
        return RuleIndexNative.ruleFingerprint(parts)
    }

    private fun countFingerprint(table: String): Triple<Long, Long, Long>? {
        if (!AppDatabase.hasTable(db, table)) return null
        val columns = if (table.endsWith("_source")) "SUM(ruleId), SUM(enabled)" else "SUM(id), SUM(enabled)"
        return db.rawQuery("SELECT COUNT(*), $columns FROM $table", null).use { cursor ->
            if (!cursor.moveToFirst()) Triple(0L, 0L, 0L)
            else Triple(cursor.getLong(0), cursor.getLong(1), cursor.getLong(2))
        }
    }

    enum class RuleKind(val ruleTable: String, val sourceTable: String) {
        BLOCK("block_rule", "block_rule_source"),
        ALLOW("allow_rule", "allow_rule_source"),
    }

    companion object {
        private const val PAGE_SIZE = 2000

        private const val RULE_COLUMNS =
            "SELECT r.pattern, MIN(s.source) AS source, r.important AS important, " +
                "r.appScope AS appScope, r.appInverted AS appInverted, r.isWildcard AS isWildcard, " +
                "r.denyallow AS denyallow, r.isRegex AS isRegex, r.dnsType AS dnsType FROM "

        private const val GROUP_BY_RULE =
            " GROUP BY r.id, r.pattern, r.important, r.appScope, r.appInverted, r.isWildcard, " +
                "r.denyallow, r.isRegex, r.dnsType"

        fun open(context: Context, databaseName: String): RuleSnapshotDao? {
            val db = AppDatabase.writable(context, databaseName) ?: return null
            if (!AppDatabase.hasTable(db, "block_rule") || !AppDatabase.hasTable(db, "allow_rule")) {
                return null
            }
            return RuleSnapshotDao(db)
        }
    }
}
