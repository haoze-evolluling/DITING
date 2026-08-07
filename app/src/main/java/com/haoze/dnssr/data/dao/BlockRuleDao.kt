package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.haoze.dnssr.data.entity.BlockRuleEntity
import com.haoze.dnssr.data.entity.BlockRuleSourceEntity

data class EnabledBlockRule(val pattern: String, val source: String, val important: Boolean = false)

@Dao
interface BlockRuleDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertRule(entity: BlockRuleEntity): Long

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertSource(entity: BlockRuleSourceEntity): Long

    @Query("SELECT id FROM block_rule WHERE pattern = :pattern AND important = :important AND scope = :scope")
    suspend fun idByPattern(pattern: String, important: Boolean, scope: String): Long

    @Transaction
    suspend fun insertForSource(entity: BlockRuleEntity, source: String, sourceEnabled: Boolean): Boolean {
        val insertedId = insertRule(entity)
        val ruleId = if (insertedId == -1L) idByPattern(entity.pattern, entity.important, entity.scope) else insertedId
        return insertSource(BlockRuleSourceEntity(ruleId, source, sourceEnabled, entity.scope)) != -1L
    }

    @Transaction
    suspend fun insertAllForSource(
        entities: List<BlockRuleEntity>,
        source: String,
        sourceEnabled: Boolean
    ): Int = entities.count { insertForSource(it, source, sourceEnabled) }

    suspend fun replaceBySource(
        source: String,
        entities: List<BlockRuleEntity>,
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

    @Query("SELECT * FROM block_rule ORDER BY addedAt DESC")
    suspend fun all(): List<BlockRuleEntity>

    @Query(
        "SELECT r.pattern, MIN(s.source) AS source, r.important AS important FROM block_rule r " +
            "JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1 AND r.scope = :scope GROUP BY r.id, r.pattern, r.important"
    )
    suspend fun enabledRules(scope: String): List<EnabledBlockRule>

    @Query(
        "SELECT r.pattern, MIN(s.source) AS source, r.important AS important FROM block_rule r " +
            "JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1 AND r.scope = :scope AND s.source LIKE 'sub_%' GROUP BY r.pattern, r.important"
    )
    suspend fun enabledSubscriptionRules(scope: String): List<EnabledBlockRule>

    @Query(
        "SELECT r.pattern, MIN(s.source) AS source, r.important AS important FROM block_rule r " +
            "JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1 AND r.scope = :scope AND s.source LIKE 'sub_%' " +
            "AND r.important = :important GROUP BY r.id, r.pattern, r.important ORDER BY r.id LIMIT :limit OFFSET :offset"
    )
    suspend fun enabledSubscriptionRulesPage(
        scope: String,
        important: Boolean,
        limit: Int,
        offset: Int
    ): List<EnabledBlockRule>

    @Query(
        "SELECT r.pattern, 'useradd' AS source, r.important AS important FROM block_rule r " +
            "JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1 AND r.scope = :scope AND s.source = 'useradd' GROUP BY r.pattern, r.important"
    )
    suspend fun enabledCustomRules(scope: String): List<EnabledBlockRule>

    @Query(
        "SELECT DISTINCT r.pattern FROM block_rule r JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE r.enabled = 1 AND s.enabled = 1"
    )
    suspend fun enabledPatterns(): List<String>

    @Query("SELECT COUNT(*) FROM block_rule WHERE scope=:scope")
    suspend fun count(scope: String): Int

    @Query("SELECT pattern FROM block_rule WHERE id = :id")
    suspend fun patternById(id: Long): String?

    @Query("SELECT EXISTS(SELECT 1 FROM block_rule_source WHERE ruleId = :id AND source GLOB 'sub_*')")
    suspend fun hasSubscriptionSource(id: Long): Boolean

    @Query(
        "SELECT r.pattern, MIN(s.source) AS source, r.important AS important FROM block_rule r " +
            "JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE r.pattern = :pattern AND r.important = :important AND r.scope = :scope AND r.enabled = 1 AND s.enabled = 1 GROUP BY r.pattern, r.important"
    )
    suspend fun enabledRuleByPattern(pattern: String, important: Boolean, scope: String): EnabledBlockRule?

    @Query("DELETE FROM block_rule WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("UPDATE block_rule SET enabled = :enabled WHERE id = :id")
    suspend fun setEnabled(id: Long, enabled: Boolean)

    @Query("UPDATE block_rule_source SET enabled = :enabled WHERE source = :source")
    suspend fun setEnabledBySource(source: String, enabled: Boolean)

    @Query("DELETE FROM block_rule WHERE scope=:scope")
    suspend fun clearAll(scope: String)

    @Query(
        "SELECT r.* FROM block_rule r JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source ORDER BY r.addedAt DESC"
    )
    suspend fun bySource(source: String): List<BlockRuleEntity>

    @Query("DELETE FROM block_rule_source WHERE source = :source")
    suspend fun deleteSource(source: String)

    @Query("UPDATE block_rule_source SET source = :targetSource WHERE source = :source")
    suspend fun moveSource(source: String, targetSource: String)

    @Query("DELETE FROM block_rule WHERE NOT EXISTS (SELECT 1 FROM block_rule_source s WHERE s.ruleId = block_rule.id)")
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

    @Query("SELECT COUNT(*) FROM block_rule_source WHERE source = :source")
    suspend fun countBySource(source: String): Int

    @Query("SELECT * FROM block_rule WHERE scope=:scope AND (pattern LIKE :query OR rawLine LIKE :query) ORDER BY addedAt DESC LIMIT :limit OFFSET :offset")
    suspend fun searchPaged(scope: String, query: String, limit: Int, offset: Int): List<BlockRuleEntity>

    @Query("SELECT COUNT(*) FROM block_rule WHERE scope=:scope AND (pattern LIKE :query OR rawLine LIKE :query)")
    suspend fun searchCount(scope: String, query: String): Int

    @Query("SELECT * FROM block_rule WHERE scope=:scope ORDER BY addedAt DESC LIMIT :limit OFFSET :offset")
    suspend fun paged(scope: String, limit: Int, offset: Int): List<BlockRuleEntity>

    @Query(
        "SELECT DISTINCT r.* FROM block_rule r JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source ORDER BY r.addedAt DESC LIMIT :limit OFFSET :offset"
    )
    suspend fun pagedBySource(source: String, limit: Int, offset: Int): List<BlockRuleEntity>

    @Query(
        "SELECT DISTINCT r.* FROM block_rule r JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source AND (r.pattern LIKE :query OR r.rawLine LIKE :query) " +
            "ORDER BY r.addedAt DESC LIMIT :limit OFFSET :offset"
    )
    suspend fun searchPagedBySource(
        source: String,
        query: String,
        limit: Int,
        offset: Int
    ): List<BlockRuleEntity>

    @Query("SELECT COUNT(DISTINCT r.id) FROM block_rule r JOIN block_rule_source s ON s.ruleId = r.id WHERE s.source = :source")
    suspend fun countBySourceForList(source: String): Int

    @Query(
        "SELECT COUNT(DISTINCT r.id) FROM block_rule r JOIN block_rule_source s ON s.ruleId = r.id " +
            "WHERE s.source = :source AND (r.pattern LIKE :query OR r.rawLine LIKE :query)"
    )
    suspend fun searchCountBySource(source: String, query: String): Int
}
