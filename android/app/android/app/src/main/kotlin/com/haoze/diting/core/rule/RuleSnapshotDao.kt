package com.haoze.diting.core.rule

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import com.haoze.diting.log.LegacyDb

/** A rule row projected exactly as the legacy Room `EnabledRule`/`EnabledRuleKeyset`. */
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

/**
 * Raw-SQLite port of the legacy Room rule DAO surface the snapshot builder needs. The rule tables
 * live in the sqflite-created database; this reader only reads, and the connection it borrows is
 * the process-wide one from [LegacyDb], so a snapshot build never competes with the log writers
 * for the file lock.
 */
class RuleSnapshotDao private constructor(private val db: SQLiteDatabase) {

    /** Keyset-paged enabled subscription rules, mirroring `enabledSubscriptionRulesPageKeyset`. */
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

    /** Enabled custom (non-subscription) rules, mirroring `enabledCustomRules`. */
    fun enabledCustomRules(kind: RuleKind): List<EnabledRule> =
        queryRules(
            "SELECT r.pattern, MIN(s.source) AS source, r.important AS important, " +
                "r.appScope AS appScope, r.appInverted AS appInverted, r.isWildcard AS isWildcard, " +
                "r.denyallow AS denyallow, r.isRegex AS isRegex, r.dnsType AS dnsType FROM ${kind.ruleTable} r " +
                "JOIN ${kind.sourceTable} s ON s.ruleId = r.id " +
                "WHERE r.enabled = 1 AND s.enabled = 1 AND s.source NOT LIKE 'sub_%' AND s.source NOT LIKE 'staging_sub_%' " +
                "GROUP BY r.id, r.pattern, r.important, r.appScope, r.appInverted, r.isWildcard, r.denyallow, r.isRegex, r.dnsType"
        )

    /** Enabled subscription rules needing per-rule snapshot entries, mirroring the special query. */
    fun enabledSpecialSubscriptionRules(kind: RuleKind): List<EnabledRule> =
        queryRules(
            "SELECT r.pattern, MIN(s.source) AS source, r.important AS important, " +
                "r.appScope AS appScope, r.appInverted AS appInverted, r.isWildcard AS isWildcard, " +
                "r.denyallow AS denyallow, r.isRegex AS isRegex, r.dnsType AS dnsType FROM ${kind.ruleTable} r " +
                "JOIN ${kind.sourceTable} s ON s.ruleId = r.id " +
                "WHERE r.enabled = 1 AND s.enabled = 1 AND s.source LIKE 'sub_%' " +
                "AND (r.isWildcard = 1 OR r.pattern LIKE '%*%' OR r.appScope IS NOT NULL OR r.appInverted = 1 OR r.isRegex = 1 OR r.denyallow IS NOT NULL OR r.dnsType IS NOT NULL) " +
                "GROUP BY r.id, r.pattern, r.important, r.appScope, r.appInverted, r.isWildcard, r.denyallow, r.isRegex, r.dnsType"
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

    /** Enabled rewrite rules as (pattern, targetValue); duplicate patterns keep the oldest row,
     *  matching the Dart encoder that walked a newest-first list and let older rows win. */
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

    /// The connection belongs to [LegacyDb] and is shared with the log writers; closing it here
    /// would pull the file out from under them, so this only drops the reference.
    fun close() = Unit

    /**
     * Cheap fingerprint of the rule tables only. The database file also holds the request-log and
     * traffic tables, which the tunnel keeps writing while it runs, so file size and mtime can never
     * tell whether the *rules* changed: they change on every logged query and would force a trie
     * recompile on every start.
     */
    fun ruleFingerprint(): String {
        val parts = ArrayList<String>(8)
        for (kind in RuleKind.entries) {
            parts += countFingerprint(kind.ruleTable)
            parts += countFingerprint(kind.sourceTable)
        }
        parts += countFingerprint("rewrite_rule")
        parts += countFingerprint("rewrite_rule_source")
        return parts.joinToString("|")
    }

    /** Rows plus the id/source sums catch edits and toggles, not only inserts and deletes. */
    private fun countFingerprint(table: String): String {
        if (!LegacyDb.hasTable(db, table)) return "$table:-"
        val columns = if (table.endsWith("_source")) "SUM(ruleId), SUM(enabled)" else "SUM(id), SUM(enabled)"
        return db.rawQuery("SELECT COUNT(*), $columns FROM $table", null).use { cursor ->
            if (!cursor.moveToFirst()) {
                "$table:0"
            } else {
                "$table:${cursor.getLong(0)}:${cursor.getLong(1)}:${cursor.getLong(2)}"
            }
        }
    }

    enum class RuleKind(val ruleTable: String, val sourceTable: String) {
        BLOCK("block_rule", "block_rule_source"),
        ALLOW("allow_rule", "allow_rule_source"),
    }

    companion object {
        private const val PAGE_SIZE = 2000

        /** Opens the legacy database through the shared connection; null when it has no rule tables. */
        fun open(context: Context, databaseName: String): RuleSnapshotDao? {
            val db = LegacyDb.writable(context, databaseName) ?: return null
            if (!LegacyDb.hasTable(db, "block_rule") || !LegacyDb.hasTable(db, "allow_rule")) {
                return null
            }
            return RuleSnapshotDao(db)
        }
    }
}
