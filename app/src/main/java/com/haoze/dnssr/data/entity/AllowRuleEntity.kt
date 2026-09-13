package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Room entity for an allowlist (whitelist) DNS rule.
 *
 * @param pattern normalized domain pattern, e.g. "example.com" or a wildcard
 *   pattern like "*-analytics.google.com" / "*".
 * @param rawLine original rule line, kept for display to the user.
 * @param appScope target package names (a single package or |-separated list);
 *   null means the rule applies globally.
 * @param appInverted whether this is an inverted-exclusion rule (~).
 * @param important whether this is a $important allowlist rule.
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
