package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.haoze.dnssr.data.entity.RewriteRuleEntity
import com.haoze.dnssr.data.entity.RewriteRuleSourceEntity

data class EnabledRewriteRule(val pattern: String, val targetType: String, val targetValue: String)

data class EnabledRewriteRuleKeyset(val id: Long, val pattern: String, val targetType: String, val targetValue: String) {
    fun toEnabledRewriteRule(): EnabledRewriteRule = EnabledRewriteRule(pattern, targetType, targetValue)
}

@Dao
interface RewriteRuleDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insertRule(rule: RewriteRuleEntity): Long
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insertSource(source: RewriteRuleSourceEntity): Long
    @Query("SELECT id FROM rewrite_rule WHERE pattern=:pattern AND targetType=:targetType AND targetValue=:targetValue") suspend fun idByKey(pattern: String, targetType: String, targetValue: String): Long
    @Transaction suspend fun insertForSource(rule: RewriteRuleEntity, source: String, enabled: Boolean): Boolean {
        val id = insertRule(rule).let { if (it == -1L) idByKey(rule.pattern, rule.targetType, rule.targetValue) else it }
        return insertSource(RewriteRuleSourceEntity(id, source, enabled)) != -1L
    }
    @Transaction suspend fun insertAllForSource(
        rules: List<RewriteRuleEntity>,
        source: String,
        enabled: Boolean
    ): Int = rules.count { insertForSource(it, source, enabled) }
    @Query("SELECT r.pattern, r.targetType, r.targetValue FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 GROUP BY r.id") suspend fun enabledRules(): List<EnabledRewriteRule>
    @Query("SELECT r.pattern, r.targetType, r.targetValue FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 AND s.source GLOB 'sub_*' GROUP BY r.id") suspend fun enabledSubscriptionRules(): List<EnabledRewriteRule>
    @Query("SELECT r.id AS id, r.pattern, r.targetType, r.targetValue FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE r.id > :lastId AND r.enabled=1 AND s.enabled=1 AND s.source GLOB 'sub_*' GROUP BY r.id ORDER BY r.id LIMIT :limit") suspend fun enabledSubscriptionRulesPageKeyset(limit: Int, lastId: Long): List<EnabledRewriteRuleKeyset>
    @Query("SELECT r.pattern, r.targetType, r.targetValue FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 AND s.source GLOB 'sub_*' GROUP BY r.id ORDER BY r.id LIMIT :limit OFFSET :offset") suspend fun enabledSubscriptionRulesPage(limit: Int, offset: Int): List<EnabledRewriteRule>
    @Query("SELECT r.pattern, r.targetType, r.targetValue FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 AND s.source NOT GLOB 'sub_*' GROUP BY r.id") suspend fun enabledNonSubscriptionRules(): List<EnabledRewriteRule>
    @Query("SELECT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.enabled=1)) AS enabled FROM rewrite_rule r ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun paged(limit: Int, offset: Int): List<RewriteRuleEntity>
    @Query("SELECT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.enabled=1)) AS enabled FROM rewrite_rule r WHERE (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query) ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun searchPaged(query: String, limit: Int, offset: Int): List<RewriteRuleEntity>
    @Query("SELECT DISTINCT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND s.enabled=1) AS enabled FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source=:source AND (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query) ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun searchPagedBySource(source: String, query: String, limit: Int, offset: Int): List<RewriteRuleEntity>
    @Query("SELECT DISTINCT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND s.enabled=1) AS enabled FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source=:source ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun pagedBySource(source: String, limit: Int, offset: Int): List<RewriteRuleEntity>
    @Query("SELECT COUNT(*) FROM rewrite_rule") suspend fun count(): Int
    @Query("SELECT COUNT(*) FROM rewrite_rule WHERE (pattern LIKE :query OR targetValue LIKE :query OR rawLine LIKE :query)") suspend fun searchCount(query: String): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source=:source") suspend fun countBySourceForList(source: String): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source=:source AND (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query)") suspend fun searchCountBySource(source: String, query: String): Int
    @Query("SELECT DISTINCT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND s.enabled=1) AS enabled FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source=:source") suspend fun rulesBySource(source: String): List<RewriteRuleEntity>
    @Query("SELECT COUNT(*) FROM rewrite_rule WHERE pattern=:pattern AND targetType=:targetType") suspend fun countType(pattern: String, targetType: String): Int
    @Query("SELECT COUNT(*) FROM rewrite_rule WHERE pattern=:pattern AND targetType!=:targetType") suspend fun countOtherTypes(pattern: String, targetType: String): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source NOT GLOB 'sub_*'") suspend fun userRulesCount(): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source NOT GLOB 'sub_*' AND r.enabled=1 AND s.enabled=1") suspend fun enabledUserRulesCount(): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source NOT GLOB 'sub_*' AND (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query)") suspend fun searchUserRulesCount(query: String): Int
    @Query("SELECT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.enabled=1 AND s.source NOT GLOB 'sub_*')) AS enabled FROM rewrite_rule r WHERE EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.source NOT GLOB 'sub_*') ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun userRulesPaged(limit: Int, offset: Int): List<RewriteRuleEntity>
    @Query("SELECT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.enabled=1 AND s.source NOT GLOB 'sub_*')) AS enabled FROM rewrite_rule r WHERE EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.source NOT GLOB 'sub_*') AND (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query) ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun searchUserRulesPaged(query: String, limit: Int, offset: Int): List<RewriteRuleEntity>

    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source GLOB 'sub_*'") suspend fun subscriptionRulesCount(): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source GLOB 'sub_*' AND r.enabled=1 AND s.enabled=1") suspend fun enabledSubscriptionRulesCount(): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE s.source GLOB 'sub_*' AND (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query)") suspend fun searchSubscriptionRulesCount(query: String): Int
    @Query("SELECT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.enabled=1 AND s.source GLOB 'sub_*')) AS enabled FROM rewrite_rule r WHERE EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.source GLOB 'sub_*') ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun subscriptionRulesPaged(limit: Int, offset: Int): List<RewriteRuleEntity>
    @Query("SELECT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.enabled=1 AND s.source GLOB 'sub_*')) AS enabled FROM rewrite_rule r WHERE EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.source GLOB 'sub_*') AND (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query) ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun searchSubscriptionRulesPaged(query: String, limit: Int, offset: Int): List<RewriteRuleEntity>

    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r WHERE r.targetType=:targetType") suspend fun countByTargetType(targetType: String): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r JOIN rewrite_rule_source s ON s.ruleId=r.id WHERE r.targetType=:targetType AND r.enabled=1 AND s.enabled=1") suspend fun enabledCountByTargetType(targetType: String): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM rewrite_rule r WHERE r.targetType=:targetType AND (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query)") suspend fun searchCountByTargetType(targetType: String, query: String): Int
    @Query("SELECT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.enabled=1)) AS enabled FROM rewrite_rule r WHERE r.targetType=:targetType ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun pagedByTargetType(targetType: String, limit: Int, offset: Int): List<RewriteRuleEntity>
    @Query("SELECT r.id, r.pattern, r.targetType, r.targetValue, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=r.id AND s.enabled=1)) AS enabled FROM rewrite_rule r WHERE r.targetType=:targetType AND (r.pattern LIKE :query OR r.targetValue LIKE :query OR r.rawLine LIKE :query) ORDER BY r.id DESC LIMIT :limit OFFSET :offset") suspend fun searchPagedByTargetType(targetType: String, query: String, limit: Int, offset: Int): List<RewriteRuleEntity>

    @Query("SELECT ruleId, source, enabled FROM rewrite_rule_source WHERE ruleId IN (:ruleIds)") suspend fun sourcesForRuleIds(ruleIds: List<Long>): List<RewriteRuleSourceEntity>
    @Query("SELECT * FROM rewrite_rule WHERE id=:id") suspend fun ruleById(id: Long): RewriteRuleEntity?
    @Query("UPDATE rewrite_rule SET pattern=:pattern, targetType=:targetType, targetValue=:targetValue, rawLine=:rawLine WHERE id=:id") suspend fun updateRule(id: Long, pattern: String, targetType: String, targetValue: String, rawLine: String)

    @Query("DELETE FROM rewrite_rule_source WHERE source NOT GLOB 'sub_*'") suspend fun deleteUserSources()
    @Transaction suspend fun deleteUserRules() {
        deleteUserSources()
        deleteOrphans()
    }

    @Query("UPDATE rewrite_rule SET enabled=:enabled WHERE id=:id") suspend fun setEnabled(id: Long, enabled: Boolean)
    @Query("UPDATE rewrite_rule_source SET enabled=:enabled WHERE ruleId=:ruleId") suspend fun setSourceEnabledByRuleId(ruleId: Long, enabled: Boolean)
    @Query("SELECT EXISTS(SELECT 1 FROM rewrite_rule_source WHERE ruleId=:id AND source GLOB 'sub_*')") suspend fun hasSubscriptionSource(id: Long): Boolean
    @Query("DELETE FROM rewrite_rule WHERE id=:id") suspend fun deleteById(id: Long)
    @Query("DELETE FROM rewrite_rule") suspend fun clearAll()
    @Query("DELETE FROM rewrite_rule_source WHERE source=:source") suspend fun deleteSource(source: String)
    @Query("UPDATE rewrite_rule_source SET source=:targetSource WHERE source=:source") suspend fun moveSource(source: String, targetSource: String)
    @Query("DELETE FROM rewrite_rule WHERE NOT EXISTS (SELECT 1 FROM rewrite_rule_source s WHERE s.ruleId=rewrite_rule.id)") suspend fun deleteOrphans()
    @Transaction suspend fun deleteBySource(source: String) { deleteSource(source); deleteOrphans() }
    @Transaction suspend fun replaceSource(stagingSource: String, targetSource: String) { deleteSource(targetSource); moveSource(stagingSource, targetSource); deleteOrphans() }
    suspend fun replaceBySource(
        source: String,
        rules: List<RewriteRuleEntity>,
        enabled: Boolean,
        chunkSize: Int = 500,
        onProgress: ((Int) -> Unit)? = null
    ) {
        deleteBySource(source)
        var imported = 0
        rules.chunked(chunkSize).forEach { chunk ->
            insertAllForSource(chunk, source, enabled)
            imported += chunk.size
            onProgress?.invoke(imported)
        }
    }
    @Query("UPDATE rewrite_rule_source SET enabled=:enabled WHERE source=:source") suspend fun setEnabledBySource(source: String, enabled: Boolean)
}
