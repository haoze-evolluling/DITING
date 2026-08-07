package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.RawQuery
import androidx.room.Transaction
import androidx.sqlite.db.SupportSQLiteQuery
import com.haoze.dnssr.data.entity.DnsCacheEntity

data class DnsCacheHitUpdate(
    val key: String,
    val count: Int,
    val lastHitAt: Long
)

@Dao
interface DnsCacheDao {
    @Query("SELECT * FROM dns_cache WHERE `key` = :key LIMIT 1")
    suspend fun get(key: String): DnsCacheEntity?

    @Query("SELECT * FROM dns_cache WHERE expiresAt > :now ORDER BY lastHitAt DESC, createdAt DESC LIMIT :limit")
    suspend fun getUnexpired(now: Long, limit: Int): List<DnsCacheEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: DnsCacheEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(entities: List<DnsCacheEntity>)

    @Query("UPDATE dns_cache SET hitCount = hitCount + 1, lastHitAt = :now WHERE `key` = :key")
    suspend fun recordHit(key: String, now: Long)

    @Query("UPDATE dns_cache SET hitCount = hitCount + :count, lastHitAt = :lastHitAt WHERE `key` = :key")
    suspend fun recordHits(key: String, count: Int, lastHitAt: Long)

    @Transaction
    suspend fun recordHitsBatch(updates: List<DnsCacheHitUpdate>) {
        updates.forEach { update ->
            recordHits(update.key, update.count, update.lastHitAt)
        }
    }

    @Query("DELETE FROM dns_cache WHERE `key` = :key")
    suspend fun delete(key: String)

    @Query("DELETE FROM dns_cache WHERE `key` IN (:keys)")
    suspend fun deleteKeys(keys: List<String>)

    @Query("DELETE FROM dns_cache WHERE expiresAt <= :now")
    suspend fun deleteExpired(now: Long): Int

    @Query("DELETE FROM dns_cache")
    suspend fun clearAll()

    @RawQuery
    suspend fun queryList(query: SupportSQLiteQuery): List<DnsCacheEntity>

    @RawQuery
    suspend fun count(query: SupportSQLiteQuery): Int
}
