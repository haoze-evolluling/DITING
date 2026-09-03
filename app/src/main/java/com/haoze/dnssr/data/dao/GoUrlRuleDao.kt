package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.haoze.dnssr.data.entity.GoUrlRuleEntity
import com.haoze.dnssr.data.entity.GoUrlRuleSourceEntity

@Dao
interface GoUrlRuleDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insertRule(rule: GoUrlRuleEntity): Long
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insertSource(source: GoUrlRuleSourceEntity): Long
    @Query("SELECT id FROM go_url_rule WHERE pattern=:pattern AND kind=:kind") suspend fun idByPattern(pattern: String, kind: String): Long

    @Transaction
    suspend fun insertForSource(rule: GoUrlRuleEntity, source: String, sourceEnabled: Boolean): Boolean {
        val inserted = insertRule(rule)
        val id = if (inserted == -1L) idByPattern(rule.pattern, rule.kind) else inserted
        return insertSource(GoUrlRuleSourceEntity(id, source, sourceEnabled)) != -1L
    }

    @Query("SELECT r.* FROM go_url_rule r JOIN go_url_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 GROUP BY r.id")
    suspend fun enabledRules(): List<GoUrlRuleEntity>
    @Query("SELECT r.* FROM go_url_rule r JOIN go_url_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 AND s.source=:source GROUP BY r.id")
    suspend fun enabledRulesBySource(source: String): List<GoUrlRuleEntity>
    @Query("SELECT r.* FROM go_url_rule r JOIN go_url_rule_source s ON s.ruleId=r.id WHERE s.source=:source GROUP BY r.id")
    suspend fun rulesBySource(source: String): List<GoUrlRuleEntity>
    @Query("SELECT r.id, r.pattern, r.kind, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM go_url_rule_source s WHERE s.ruleId=r.id AND s.enabled=1)) AS enabled FROM go_url_rule r WHERE r.kind=:kind ORDER BY r.addedAt DESC") suspend fun byKind(kind: String): List<GoUrlRuleEntity>
    @Query("SELECT COUNT(*) FROM go_url_rule WHERE kind=:kind") suspend fun count(kind: String): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM go_url_rule r JOIN go_url_rule_source s ON s.ruleId=r.id WHERE r.kind=:kind AND r.enabled=1 AND s.enabled=1") suspend fun enabledCount(kind: String): Int
    @Query("SELECT ruleId, source, enabled FROM go_url_rule_source WHERE ruleId IN (:ruleIds)") suspend fun sourcesForRuleIds(ruleIds: List<Long>): List<GoUrlRuleSourceEntity>
    @Query("UPDATE go_url_rule SET enabled=:enabled WHERE id=:id") suspend fun setEnabled(id: Long, enabled: Boolean)
    @Query("UPDATE go_url_rule_source SET enabled=:enabled WHERE ruleId=:ruleId") suspend fun setSourceEnabledByRuleId(ruleId: Long, enabled: Boolean)
    @Query("DELETE FROM go_url_rule WHERE id=:id") suspend fun deleteById(id: Long)
    @Query("DELETE FROM go_url_rule_source WHERE source=:source") suspend fun deleteSourceOnly(source: String)
    @Query("DELETE FROM go_url_rule WHERE NOT EXISTS (SELECT 1 FROM go_url_rule_source s WHERE s.ruleId=go_url_rule.id)") suspend fun deleteOrphans()
    @Transaction suspend fun deleteBySource(source: String) { deleteSourceOnly(source); deleteOrphans() }
    @Query("DELETE FROM go_url_rule_source WHERE source=:source AND ruleId IN (SELECT id FROM go_url_rule WHERE kind=:kind)") suspend fun deleteSourcesByKindAndSource(kind: String, source: String)
    @Transaction suspend fun deleteByKindAndSource(kind: String, source: String) { deleteSourcesByKindAndSource(kind, source); deleteOrphans() }
    @Query("DELETE FROM go_url_rule") suspend fun clearAll()
}
