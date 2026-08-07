package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * DNS 白名单规则实体。
 *
 * @param pattern 规范化后的域名模式，如 "example.com"。
 * @param rawLine 原始规则行，用于展示给用户。
 */
@Entity(
    tableName = "allow_rule",
    indices = [Index(value = ["pattern", "scope"], unique = true)]
)
data class AllowRuleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val pattern: String,
    val rawLine: String,
    val addedAt: Long,
    val enabled: Boolean = true,
    val groupName: String? = null,
    val scope: String = RuleScope.DNS.storageValue
)
