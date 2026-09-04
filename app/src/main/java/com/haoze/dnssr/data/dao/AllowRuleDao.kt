package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.haoze.dnssr.data.entity.AllowRuleEntity
import com.haoze.dnssr.data.entity.AllowRuleSourceEntity
import com.haoze.dnssr.data.dao.EnabledRule

data class AllowRuleIdentity(
    val id: Long,
    val pattern: String,
    val important: Boolean,
    val appScope: String?,
    val appInverted: Boolean
)

@Dao
interface AllowRuleDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertRule(entity: AllowRuleEntity): Long

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertRules(entities: List<AllowRuleEntity>): List<Long>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertSource(entity: AllowRuleSourceEntity): Long

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertSources(entities: List<AllowRuleSourceEntity>): List<Long>

    @Query(
        "SELECT id FROM allow_rule WHERE pattern = :pattern AND important = :important " +
            "AND ((:appScope IS NULL AND appScope IS NULL) OR appScope = :appScope) AND appInverted = :appInverted"
    )
    suspend fun idByPattern(
        pattern: String,
        important: Boolean = false,
        appScope: String? = null,
        appInverted: Boolean = false
    ): Long

    @Query(
        "SELECT id, pattern, important, appScope, appInverted FROM allow_rule " +
            "WHERE pattern IN (:patterns)"
    )
    suspend fun rulesByPatterns(patterns: List<String>): List<AllowRuleIdentity>

    @Transaction
    suspend fun insertForSource(entity: AllowRuleEntity, source: String, sourceEnabled: Boolean): Boolean {
        val insertedId = insertRule(entity)
        val ruleId = if (insertedId == -1L) {
            idByPattern(entity.pattern, entity.important, entity.appScope, entity.appInverted)
        } else insertedId
        return insertSource(AllowRuleSourceEntity(ruleId, source, sourceEnabled)) != -1L
    }

    @Transaction
    suspend fun insertAllForSource(
        entities: List<AllowRuleEntity>,
        source: String,
        sourceEnabled: Boolean
    ): Int {
        if (entities.isEmpty()) return 0
        val rowIds = insertRules(entities)
        val conflictedIndices = mutableListOf<Int>()
        for (i in rowIds.indices) {
            if (rowIds[i] == -1L) {
                conflictedIndices.add(i)
            }
        }

        val ruleIds = LongArray(entities.size)
        for (i in rowIds.indices) {
            ruleIds[i] = rowIds[i]
        }

        if (conflictedIndices.isNotEmpty()) {
            val conflictedPatterns = conflictedIndices.map { entities[it].pattern }.distinct()
            val existingRules = rulesByPatterns(conflictedPatterns)
            val lookup = existingRules.groupBy { it.pattern }

            for (i in conflictedIndices) {
                val entity = entities[i]
                val candidates = lookup[entity.pattern]
                val matched = candidates?.firstOrNull {
                    it.important == entity.important &&
                        it.appScope == entity.appScope &&
                        it.appInverted == entity.appInverted
                }
                ruleIds[i] = matched?.id ?: idByPattern(
                    entity.pattern,
                    entity.important,
                    entity.appScope,
                    entity.appInverted
                )
            }
        }

        val sourcesToInsert = ArrayList<AllowRuleSourceEntity>(ruleIds.size)
        for (ruleId in ruleIds) {
            if (ruleId > 0L) {
                sourcesToInsert.add(AllowRuleSourceEntity(ruleId, source, sourceEnabled))
            }
        }
        val insertedSources = insertSources(sourcesToInsert)
        return insertedSources.count { it != -1L }
    }

    suspend fun replaceBySource(
        source: String,
        entities: List<AllowRuleEntity>,
        sourceEnabled: Boolean,
        chunkSize: Int = 500,
        onProgress: ((Int) -> Unit)? = null
    ) {
        deleteSource(source)
        deleteOrphans()
        var imported = 0
        entities.chunked(chunkSize).forEach { chunk ->
            insertAllForSource(chunk, source, sourceEnabled)
            imported += chunk.size
            onProgress?.invoke(imported)
        }
    }

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.enabled = 1)) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r ORDER BY r.addedAt DESC"
    )
    suspend fun all(): List<AllowRuleEntity>

    @Query(
        "SELECT r.id AS id, r.pattern, MIN(s.source) AS source, r.important AS important, " +
            "r.appScope AS appScope, r.appInverted AS appInverted, r.isWildcard AS isWildcard FROM allow_rule r " +
            "JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE r.id > :lastId AND r.enabled = 1 AND s.enabled = 1 AND s.source LIKE 'sub_%' " +
            "GROUP BY r.id, r.pattern, r.important, r.appScope, r.appInverted, r.isWildcard " +
            "ORDER BY r.id LIMIT :limit"
    )
    suspend fun enabledSubscriptionRulesPageKeyset(limit: Int, lastId: Long): List<EnabledRuleKeyset>

    @Query(
        "SELECT r.pattern, MIN(s.source) AS source, r.important AS important, " +
            "r.appScope AS appScope, r.appInverted AS appInverted, r.isWildcard AS isWildcard FROM allow_rule r " +
            "JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1 AND s.source LIKE 'sub_%' " +
            "AND (r.isWildcard = 1 OR r.pattern LIKE '%*%' OR r.appScope IS NOT NULL OR r.appInverted = 1) " +
            "GROUP BY r.id, r.pattern, r.important, r.appScope, r.appInverted, r.isWildcard"
    )
    suspend fun enabledSpecialSubscriptionRules(): List<EnabledRule>

    @Query(
        "SELECT r.pattern, MIN(s.source) AS source, r.important AS important, " +
            "r.appScope AS appScope, r.appInverted AS appInverted, r.isWildcard AS isWildcard FROM allow_rule r " +
            "JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1 AND s.source NOT LIKE 'sub_%' " +
            "GROUP BY r.id, r.pattern, r.important, r.appScope, r.appInverted, r.isWildcard"
    )
    suspend fun enabledCustomRules(): List<EnabledRule>

    @Query(
        "SELECT DISTINCT r.pattern FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1"
    )
    suspend fun enabledPatterns(): List<String>

    @Query(
        "SELECT COUNT(DISTINCT r.pattern) FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1"
    )
    suspend fun enabledPatternsCount(): Int

    @Query(
        "SELECT COUNT(DISTINCT r.id) FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source AND r.enabled = 1 AND s.enabled = 1"
    )
    suspend fun enabledCountBySource(source: String): Int

    @Query("SELECT COUNT(*) FROM allow_rule")
    suspend fun count(): Int

    @Query("SELECT pattern FROM allow_rule WHERE id = :id")
    suspend fun patternById(id: Long): String?

    @Query("SELECT EXISTS(SELECT 1 FROM allow_rule_source WHERE ruleId = :id AND source GLOB 'sub_*')")
    suspend fun hasSubscriptionSource(id: Long): Boolean

    @Query(
        "SELECT r.pattern, MIN(s.source) AS source, r.important AS important, " +
            "r.appScope AS appScope, r.appInverted AS appInverted, r.isWildcard AS isWildcard FROM allow_rule r " +
            "JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE r.pattern = :pattern " +
            "AND ((:appScope IS NULL AND r.appScope IS NULL) OR r.appScope = :appScope) AND r.appInverted = :appInverted " +
            "AND r.enabled = 1 AND s.enabled = 1 " +
            "GROUP BY r.id, r.pattern, r.important, r.appScope, r.appInverted, r.isWildcard"
    )
    suspend fun enabledRuleByPattern(
        pattern: String,
        appScope: String? = null,
        appInverted: Boolean = false
    ): EnabledRule?

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.enabled = 1)) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r WHERE r.appScope LIKE '%' || :appScope || '%' " +
            "ORDER BY r.addedAt DESC LIMIT :limit OFFSET :offset"
    )
    suspend fun rulesByAppScopePaged(
        appScope: String,
        limit: Int,
        offset: Int
    ): List<AllowRuleEntity>

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.enabled = 1)) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r WHERE r.appScope LIKE '%' || :appScope || '%' " +
            "AND (r.pattern LIKE :query OR r.rawLine LIKE :query) ORDER BY r.addedAt DESC LIMIT :limit OFFSET :offset"
    )
    suspend fun searchPagedByAppScope(
        appScope: String,
        query: String,
        limit: Int,
        offset: Int
    ): List<AllowRuleEntity>

    @Query("SELECT COUNT(*) FROM allow_rule WHERE appScope LIKE '%' || :appScope || '%'")
    suspend fun countByAppScope(appScope: String): Int

    @Query(
        "SELECT COUNT(*) FROM allow_rule WHERE appScope LIKE '%' || :appScope || '%' " +
            "AND (pattern LIKE :query OR rawLine LIKE :query)"
    )
    suspend fun searchCountByAppScope(appScope: String, query: String): Int

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.enabled = 1)) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r WHERE r.appScope LIKE '%' || :appScope || '%' ORDER BY r.addedAt DESC"
    )
    suspend fun allByAppScope(appScope: String): List<AllowRuleEntity>

    @Query("SELECT DISTINCT appScope FROM allow_rule WHERE appScope IS NOT NULL")
    suspend fun appScopes(): List<String>

    @Query("DELETE FROM allow_rule WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("UPDATE allow_rule SET enabled = :enabled WHERE id = :id")
    suspend fun setEnabled(id: Long, enabled: Boolean)

    @Query("UPDATE allow_rule_source SET enabled = :enabled WHERE ruleId = :ruleId")
    suspend fun setSourceEnabledByRuleId(ruleId: Long, enabled: Boolean)

    @Query("UPDATE allow_rule_source SET enabled = :enabled WHERE source = :source")
    suspend fun setEnabledBySource(source: String, enabled: Boolean)

    @Query("DELETE FROM allow_rule")
    suspend fun clearAll()

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND s.enabled = 1) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source ORDER BY r.addedAt DESC"
    )
    suspend fun bySource(source: String): List<AllowRuleEntity>

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.enabled = 1 AND s.source != 'preset' AND s.source NOT LIKE 'sub_%')) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r " +
            "WHERE EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.source != 'preset' AND s.source NOT LIKE 'sub_%') " +
            "ORDER BY r.addedAt DESC"
    )
    suspend fun userRules(): List<AllowRuleEntity>

    @Query("SELECT COUNT(DISTINCT r.id) FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id WHERE s.source != 'preset' AND s.source NOT LIKE 'sub_%'")
    suspend fun userRulesCount(): Int

    @Query("SELECT COUNT(DISTINCT r.id) FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id WHERE s.source != 'preset' AND s.source NOT LIKE 'sub_%' AND r.enabled = 1 AND s.enabled = 1")
    suspend fun enabledUserRulesCount(): Int

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.enabled = 1 AND s.source LIKE 'sub_%')) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r " +
            "WHERE EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.source LIKE 'sub_%') " +
            "ORDER BY r.addedAt DESC"
    )
    suspend fun subscriptionRules(): List<AllowRuleEntity>

    @Query("SELECT COUNT(DISTINCT r.id) FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id WHERE s.source LIKE 'sub_%'")
    suspend fun subscriptionRulesCount(): Int

    @Query("SELECT COUNT(DISTINCT r.id) FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id WHERE s.source LIKE 'sub_%' AND r.enabled = 1 AND s.enabled = 1")
    suspend fun enabledSubscriptionRulesCount(): Int

    @Query("SELECT ruleId, source, enabled FROM allow_rule_source WHERE ruleId IN (:ruleIds)")
    suspend fun sourcesForRuleIds(ruleIds: List<Long>): List<AllowRuleSourceEntity>

    @Query("DELETE FROM allow_rule_source WHERE source != 'preset' AND source NOT LIKE 'sub_%'")
    suspend fun deleteUserSources()

    @Transaction
    suspend fun deleteUserRules() {
        deleteUserSources()
        deleteOrphans()
    }

    @Query("DELETE FROM allow_rule_source WHERE source = :source")
    suspend fun deleteSource(source: String)

    @Query("UPDATE allow_rule_source SET source = :targetSource WHERE source = :source")
    suspend fun moveSource(source: String, targetSource: String)

    @Query("DELETE FROM allow_rule WHERE NOT EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = allow_rule.id)")
    suspend fun deleteOrphans()

    @Transaction
    suspend fun deleteBySource(source: String) {
        deleteSource(source)
        deleteOrphans()
    }

    @Transaction
    suspend fun replaceSource(stagingSource: String, targetSource: String) {
        deleteSource(targetSource)
        moveSource(stagingSource, targetSource)
        deleteOrphans()
    }

    @Query("SELECT COUNT(*) FROM allow_rule_source WHERE source = :source")
    suspend fun countBySource(source: String): Int

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.enabled = 1)) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r WHERE r.pattern LIKE :query OR r.rawLine LIKE :query ORDER BY r.addedAt DESC LIMIT :limit OFFSET :offset"
    )
    suspend fun searchPaged(query: String, limit: Int, offset: Int): List<AllowRuleEntity>

    @Query("SELECT COUNT(*) FROM allow_rule WHERE pattern LIKE :query OR rawLine LIKE :query")
    suspend fun searchCount(query: String): Int

    @Query(
        "SELECT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND EXISTS (SELECT 1 FROM allow_rule_source s WHERE s.ruleId = r.id AND s.enabled = 1)) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r ORDER BY r.addedAt DESC LIMIT :limit OFFSET :offset"
    )
    suspend fun paged(limit: Int, offset: Int): List<AllowRuleEntity>

    @Query(
        "SELECT DISTINCT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND s.enabled = 1) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source ORDER BY r.addedAt DESC LIMIT :limit OFFSET :offset"
    )
    suspend fun pagedBySource(source: String, limit: Int, offset: Int): List<AllowRuleEntity>

    @Query(
        "SELECT DISTINCT r.id, r.pattern, r.rawLine, r.addedAt, " +
            "(r.enabled = 1 AND s.enabled = 1) AS enabled, " +
            "r.groupName, r.appScope, r.appInverted, r.isWildcard, r.important " +
            "FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source AND (r.pattern LIKE :query OR r.rawLine LIKE :query) " +
            "ORDER BY r.addedAt DESC LIMIT :limit OFFSET :offset"
    )
    suspend fun searchPagedBySource(
        source: String,
        query: String,
        limit: Int,
        offset: Int
    ): List<AllowRuleEntity>

    @Query("SELECT COUNT(DISTINCT r.id) FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id WHERE s.source = :source")
    suspend fun countBySourceForList(source: String): Int

    @Query(
        "SELECT COUNT(DISTINCT r.id) FROM allow_rule r JOIN allow_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source AND (r.pattern LIKE :query OR r.rawLine LIKE :query)"
    )
    suspend fun searchCountBySource(source: String, query: String): Int
}
