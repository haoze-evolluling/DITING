package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

object RewriteTargetType {
    const val IPV4 = "IPv4"
    const val IPV6 = "IPv6"
    const val CNAME = "CNAME"
}

@Entity(tableName = "rewrite_rule", indices = [Index(value = ["pattern", "targetType", "targetValue", "scope"], unique = true)])
data class RewriteRuleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val pattern: String,
    val targetType: String,
    val targetValue: String,
    val rawLine: String,
    val addedAt: Long,
    val enabled: Boolean = true,
    val scope: String = RuleScope.DNS.storageValue
)

@Entity(
    tableName = "rewrite_rule_source",
    primaryKeys = ["ruleId", "source"],
    foreignKeys = [
        ForeignKey(
            entity = RewriteRuleEntity::class,
            parentColumns = ["id"],
            childColumns = ["ruleId"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class RewriteRuleSourceEntity(
    val ruleId: Long,
    val source: String,
    val enabled: Boolean,
    val scope: String = RuleScope.DNS.storageValue
)
