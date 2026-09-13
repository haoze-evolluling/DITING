package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.haoze.dnssr.data.entity.SubscriptionAutoUpdateItemEntity

@Dao
interface SubscriptionAutoUpdateDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(item: SubscriptionAutoUpdateItemEntity)

    @Query("SELECT * FROM subscription_auto_update_item WHERE batchId = :batchId AND status = :status")
    suspend fun byStatus(batchId: String, status: String): List<SubscriptionAutoUpdateItemEntity>

    @Query("SELECT * FROM subscription_auto_update_item WHERE batchId = :batchId")
    suspend fun byBatch(batchId: String): List<SubscriptionAutoUpdateItemEntity>

    @Query("DELETE FROM subscription_auto_update_item WHERE batchId = :batchId")
    suspend fun deleteBatch(batchId: String)

    @Query("DELETE FROM subscription_auto_update_item WHERE batchId = :batchId AND subscriptionId = :subscriptionId")
    suspend fun deleteItem(batchId: String, subscriptionId: Long)

    @Query("DELETE FROM subscription_auto_update_item")
    suspend fun clear()
}
