package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.haoze.dnssr.data.entity.SubscriptionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SubscriptionDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(subscription: SubscriptionEntity): Long

    @Update
    suspend fun update(subscription: SubscriptionEntity)

    @Query("SELECT * FROM subscription ORDER BY addedAt DESC")
    suspend fun all(): List<SubscriptionEntity>

    @Query("SELECT * FROM subscription ORDER BY addedAt DESC")
    fun observeAll(): Flow<List<SubscriptionEntity>>

    @Query("SELECT * FROM subscription WHERE scope = :scope ORDER BY addedAt DESC")
    fun observeByScope(scope: String): Flow<List<SubscriptionEntity>>

    @Query("SELECT * FROM subscription WHERE scope = :scope ORDER BY addedAt DESC")
    suspend fun allByScope(scope: String): List<SubscriptionEntity>

    @Query("SELECT * FROM subscription WHERE sourceType = 'remote' ORDER BY addedAt DESC")
    suspend fun allRemote(): List<SubscriptionEntity>

    @Query("SELECT * FROM subscription WHERE sourceType = 'remote' AND scope = :scope ORDER BY addedAt DESC")
    suspend fun allRemoteByScope(scope: String): List<SubscriptionEntity>

    @Query("SELECT * FROM subscription WHERE sourceType = 'remote' AND enabled = 1 ORDER BY addedAt DESC")
    suspend fun allEnabledRemote(): List<SubscriptionEntity>

    @Query(
        "SELECT sub.* FROM subscription sub JOIN subscription_group grp ON grp.id = sub.groupId " +
            "WHERE sub.sourceType = 'remote' AND sub.enabled = 1 AND grp.autoUpdateEnabled = 1 ORDER BY sub.addedAt DESC"
    )
    suspend fun allAutoUpdatableRemote(): List<SubscriptionEntity>

    @Query("SELECT * FROM subscription WHERE kind = :kind ORDER BY addedAt DESC")
    suspend fun allByKind(kind: String): List<SubscriptionEntity>

    @Query(
        "SELECT DISTINCT sub.* FROM subscription sub " +
            "JOIN block_rule_source source ON source.source = 'sub_' || sub.id " +
            "ORDER BY sub.addedAt DESC"
    )
    suspend fun withBlockRules(): List<SubscriptionEntity>

    @Query(
        "SELECT DISTINCT sub.* FROM subscription sub " +
            "JOIN allow_rule_source source ON source.source = 'sub_' || sub.id " +
            "ORDER BY sub.addedAt DESC"
    )
    suspend fun withAllowRules(): List<SubscriptionEntity>

    @Query("SELECT * FROM subscription WHERE id = :id")
    suspend fun byId(id: Long): SubscriptionEntity?

    @Query("UPDATE subscription SET enabled = :enabled WHERE id = :id")
    suspend fun setEnabled(id: Long, enabled: Boolean)

    @Query("UPDATE subscription SET name = :name WHERE id = :id")
    suspend fun setName(id: Long, name: String)

    @Query("UPDATE subscription SET groupId = :groupId WHERE id = :id")
    suspend fun setGroup(id: Long, groupId: Long?)

    @Query("UPDATE subscription SET groupId = NULL WHERE groupId = :groupId")
    suspend fun clearGroup(groupId: Long)

    @Query("SELECT * FROM subscription WHERE groupId = :groupId ORDER BY addedAt DESC")
    suspend fun byGroupId(groupId: Long): List<SubscriptionEntity>

    @Query("UPDATE subscription SET name = :name, url = :url, ruleCount = :ruleCount, lastUpdated = :lastUpdated WHERE id = :id")
    suspend fun setDetails(id: Long, name: String, url: String, ruleCount: Int, lastUpdated: Long)

    @Query("UPDATE subscription SET importState = :state, importError = :error WHERE id = :id")
    suspend fun setImportState(id: Long, state: String, error: String?)

    @Query("SELECT * FROM subscription WHERE importState = 'importing'")
    suspend fun importing(): List<SubscriptionEntity>

    @Query(
        "UPDATE subscription SET importState = :state, importError = :error, " +
            "ruleCount = 0, lastUpdated = 0, httpEtag = NULL, httpLastModified = NULL, ruleSetHash = NULL " +
            "WHERE id = :id"
    )
    suspend fun markInterruptedImportFailed(id: Long, state: String, error: String)

    @Query(
        "UPDATE subscription SET ruleCount = 0, lastUpdated = 0, " +
            "httpEtag = NULL, httpLastModified = NULL, ruleSetHash = NULL " +
            "WHERE scope = :scope"
    )
    suspend fun resetAfterRuleCleanup(scope: String)

    @Query(
        "UPDATE subscription SET importState = :state, importError = NULL, " +
            "lastAttemptAt = :attemptedAt, consecutiveFailureCount = 0, " +
            "httpEtag = :etag, httpLastModified = :lastModified WHERE id = :id"
    )
    suspend fun markNotModified(
        id: Long,
        state: String,
        attemptedAt: Long,
        etag: String?,
        lastModified: String?
    )

    @Query(
        "UPDATE subscription SET importState = :state, importError = :error, " +
            "lastAttemptAt = :attemptedAt, consecutiveFailureCount = consecutiveFailureCount + 1 WHERE id = :id"
    )
    suspend fun markUpdateFailed(id: Long, state: String, error: String, attemptedAt: Long)

    @Query("SELECT * FROM subscription WHERE url = :url AND kind = :kind AND scope = :scope")
    suspend fun byUrlAndKind(url: String, kind: String, scope: String): SubscriptionEntity?

    @Query("SELECT * FROM subscription WHERE url = :url AND scope = :scope LIMIT 1")
    suspend fun byUrlAndScope(url: String, scope: String): SubscriptionEntity?

    @Query("DELETE FROM subscription WHERE id = :id")
    suspend fun deleteById(id: Long)
}
