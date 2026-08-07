package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    tableName = "go_url_rule_source",
    primaryKeys = ["ruleId", "source"],
    foreignKeys = [ForeignKey(
        entity = GoUrlRuleEntity::class,
        parentColumns = ["id"],
        childColumns = ["ruleId"],
        onDelete = ForeignKey.CASCADE
    )],
    indices = [Index(value = ["source"])]
)
data class GoUrlRuleSourceEntity(
    val ruleId: Long,
    val source: String,
    val enabled: Boolean = true
)
