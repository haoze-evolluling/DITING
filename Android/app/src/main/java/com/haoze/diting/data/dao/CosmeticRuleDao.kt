package com.haoze.diting.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleSourceEntity

@Dao
interface CosmeticRuleDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insertRule(rule: CosmeticRuleEntity): Long
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insertSource(source: CosmeticRuleSourceEntity): Long
    @Query("SELECT id FROM cosmetic_rule WHERE domain=:domain AND selector=:selector") suspend fun idByDomainAndSelector(domain: String, selector: String): Long

    @Transaction
    suspend fun insertForSource(rule: CosmeticRuleEntity, source: String, sourceEnabled: Boolean): Boolean {
        val inserted = insertRule(rule)
        val id = if (inserted == -1L) idByDomainAndSelector(rule.domain, rule.selector) else inserted
        return insertSource(CosmeticRuleSourceEntity(id, source, sourceEnabled)) != -1L
    }

    @Query("SELECT r.* FROM cosmetic_rule r JOIN cosmetic_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 GROUP BY r.id")
    suspend fun enabledRules(): List<CosmeticRuleEntity>

    @Query("SELECT r.* FROM cosmetic_rule r JOIN cosmetic_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 AND s.source=:source GROUP BY r.id")
    suspend fun enabledRulesBySource(source: String): List<CosmeticRuleEntity>

    @Query("SELECT r.* FROM cosmetic_rule r JOIN cosmetic_rule_source s ON s.ruleId=r.id WHERE s.source=:source GROUP BY r.id")
    suspend fun rulesBySource(source: String): List<CosmeticRuleEntity>

    @Query("SELECT r.id, r.domain, r.selector, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM cosmetic_rule_source s WHERE s.ruleId=r.id AND s.enabled=1)) AS enabled FROM cosmetic_rule r ORDER BY r.addedAt DESC")
    suspend fun allRules(): List<CosmeticRuleEntity>

    @Query("SELECT COUNT(*) FROM cosmetic_rule") suspend fun count(): Int
    @Query("SELECT COUNT(DISTINCT r.id) FROM cosmetic_rule r JOIN cosmetic_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1") suspend fun enabledCount(): Int
    @Query("UPDATE cosmetic_rule SET enabled=:enabled WHERE id=:id") suspend fun setEnabled(id: Long, enabled: Boolean)
    @Query("UPDATE cosmetic_rule_source SET enabled=:enabled WHERE ruleId=:ruleId") suspend fun setSourceEnabledByRuleId(ruleId: Long, enabled: Boolean)
    @Query("DELETE FROM cosmetic_rule WHERE id=:id") suspend fun deleteById(id: Long)
    @Query("DELETE FROM cosmetic_rule_source WHERE ruleId=:ruleId") suspend fun deleteSourcesByRuleId(ruleId: Long)
    @Transaction suspend fun deleteRule(id: Long) { deleteById(id); deleteSourcesByRuleId(id) }
    @Query("DELETE FROM cosmetic_rule_source WHERE source=:source") suspend fun deleteSourceOnly(source: String)
    @Query("DELETE FROM cosmetic_rule WHERE NOT EXISTS (SELECT 1 FROM cosmetic_rule_source s WHERE s.ruleId=cosmetic_rule.id)") suspend fun deleteOrphans()
    @Transaction suspend fun deleteBySource(source: String) { deleteSourceOnly(source); deleteOrphans() }
    @Query("UPDATE cosmetic_rule_source SET source=:newSource WHERE source=:oldSource") suspend fun promoteSource(oldSource: String, newSource: String)
    @Query("UPDATE cosmetic_rule_source SET enabled=:enabled WHERE source=:source") suspend fun setSourceEnabledBySource(source: String, enabled: Boolean)
    @Query("DELETE FROM cosmetic_rule") suspend fun clearAll()

    @Query("SELECT ruleId, source, enabled FROM cosmetic_rule_source WHERE ruleId IN (:ruleIds)")
    suspend fun sourcesForRuleIds(ruleIds: List<Long>): List<CosmeticRuleSourceEntity>

    @Query("SELECT r.id, r.domain, r.selector, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM cosmetic_rule_source s WHERE s.ruleId=r.id AND s.enabled=1)) AS enabled FROM cosmetic_rule r WHERE r.rawLine NOT LIKE '%#@#%' ORDER BY r.addedAt DESC")
    suspend fun blockRules(): List<CosmeticRuleEntity>

    @Query("SELECT r.id, r.domain, r.selector, r.rawLine, r.addedAt, (r.enabled=1 AND EXISTS(SELECT 1 FROM cosmetic_rule_source s WHERE s.ruleId=r.id AND s.enabled=1)) AS enabled FROM cosmetic_rule r WHERE r.rawLine LIKE '%#@#%' ORDER BY r.addedAt DESC")
    suspend fun allowRules(): List<CosmeticRuleEntity>

    @Query("SELECT COUNT(*) FROM cosmetic_rule WHERE rawLine NOT LIKE '%#@#%'")
    suspend fun blockRulesCount(): Int

    @Query("SELECT COUNT(*) FROM cosmetic_rule WHERE rawLine LIKE '%#@#%'")
    suspend fun allowRulesCount(): Int

    @Query("SELECT COUNT(DISTINCT r.id) FROM cosmetic_rule r JOIN cosmetic_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 AND r.rawLine NOT LIKE '%#@#%'")
    suspend fun enabledBlockCount(): Int

    @Query("SELECT COUNT(DISTINCT r.id) FROM cosmetic_rule r JOIN cosmetic_rule_source s ON s.ruleId=r.id WHERE r.enabled=1 AND s.enabled=1 AND r.rawLine LIKE '%#@#%'")
    suspend fun enabledAllowCount(): Int

    @Query("DELETE FROM cosmetic_rule_source WHERE source='useradd' AND ruleId IN (SELECT id FROM cosmetic_rule WHERE rawLine NOT LIKE '%#@#%')")
    suspend fun deleteUserBlockSources()

    @Query("DELETE FROM cosmetic_rule_source WHERE source='useradd' AND ruleId IN (SELECT id FROM cosmetic_rule WHERE rawLine LIKE '%#@#%')")
    suspend fun deleteUserAllowSources()

    @Transaction
    suspend fun deleteUserBlockRules() {
        deleteUserBlockSources()
        deleteOrphans()
    }

    @Transaction
    suspend fun deleteUserAllowRules() {
        deleteUserAllowSources()
        deleteOrphans()
    }
}
