package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SubscriptionGroupDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(group: SubscriptionGroupEntity): Long

    @Update
    suspend fun update(group: SubscriptionGroupEntity)

    @Query("SELECT * FROM subscription_group ORDER BY addedAt ASC, name COLLATE NOCASE ASC")
    fun observeAll(): Flow<List<SubscriptionGroupEntity>>

    @Query("SELECT * FROM subscription_group ORDER BY addedAt ASC, name COLLATE NOCASE ASC")
    suspend fun all(): List<SubscriptionGroupEntity>

    @Query("SELECT * FROM subscription_group WHERE id = :id")
    suspend fun byId(id: Long): SubscriptionGroupEntity?

    @Query("SELECT * FROM subscription_group WHERE name = :name COLLATE NOCASE LIMIT 1")
    suspend fun byName(name: String): SubscriptionGroupEntity?

    @Query("UPDATE subscription_group SET name = :name WHERE id = :id")
    suspend fun setName(id: Long, name: String)

    @Query("UPDATE subscription_group SET autoUpdateEnabled = :enabled WHERE id = :id")
    suspend fun setAutoUpdateEnabled(id: Long, enabled: Boolean)

    @Query("DELETE FROM subscription_group WHERE id = :id")
    suspend fun deleteById(id: Long)
}
