package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    tableName = "allow_rule_source",
    primaryKeys = ["ruleId", "source"],
    foreignKeys = [
        ForeignKey(
            entity = AllowRuleEntity::class,
            parentColumns = ["id"],
            childColumns = ["ruleId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["source"])]
)
data class AllowRuleSourceEntity(
    val ruleId: Long,
    val source: String,
    val enabled: Boolean = true
)
