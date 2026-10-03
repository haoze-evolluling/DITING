package com.haoze.diting.data.entity

import androidx.room.Entity
import androidx.room.Index

/**
 * Maps a cosmetic rule to the subscription or origin source that introduced it.
 */
@Entity(
    tableName = "cosmetic_rule_source",
    primaryKeys = ["ruleId", "source"],
    indices = [Index(value = ["source"])]
)
data class CosmeticRuleSourceEntity(
    val ruleId: Long,
    val source: String,
    val enabled: Boolean = true
)
