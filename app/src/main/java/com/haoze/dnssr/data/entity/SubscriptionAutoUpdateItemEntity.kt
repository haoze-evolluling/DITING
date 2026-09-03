package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    tableName = "subscription_auto_update_item",
    primaryKeys = ["batchId", "subscriptionId"],
    foreignKeys = [
        ForeignKey(
            entity = SubscriptionEntity::class,
            parentColumns = ["id"],
            childColumns = ["subscriptionId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["subscriptionId"]),
        Index(value = ["batchId", "status"])
    ]
)
data class SubscriptionAutoUpdateItemEntity(
    val batchId: String,
    val subscriptionId: Long,
    val status: String,
    val changed: Boolean = false,
    val ruleCount: Int = 0
)

object SubscriptionAutoUpdateItemStatus {
    const val PENDING_RETRY = "pending_retry"
    const val SUCCESS = "success"
    const val FAILED = "failed"
}
