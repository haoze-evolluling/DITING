package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "subscription_group",
    indices = [Index(value = ["name"], unique = true)]
)
data class SubscriptionGroupEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val autoUpdateEnabled: Boolean = true,
    val addedAt: Long = System.currentTimeMillis()
)
