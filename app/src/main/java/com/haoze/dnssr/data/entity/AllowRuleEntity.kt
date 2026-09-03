package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * DNS 白名单规则实体。
 *
 * @param pattern 规范化后的域名模式，如 "example.com" 或通配符模式 "*-analytics.google.com" / "*"。
 * @param rawLine 原始规则行，用于展示给用户。
 * @param appScope 目标包名列表（单包名或 | 分隔），null 表示全局生效。
 * @param appInverted 是否为反向排除规则（~）。
 * @param important 是否为 $important 白名单规则。
 */
@Entity(
    tableName = "allow_rule",
    indices = [
        Index(value = ["pattern", "important", "appScope", "appInverted"], unique = true),
        Index(value = ["appScope"])
    ]
)
data class AllowRuleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val pattern: String,
    val rawLine: String,
    val addedAt: Long,
    val enabled: Boolean = true,
    val groupName: String? = null,
    val appScope: String? = null,
    val appInverted: Boolean = false,
    val isWildcard: Boolean = false,
    val important: Boolean = false
)
