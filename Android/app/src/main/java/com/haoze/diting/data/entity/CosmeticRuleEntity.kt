package com.haoze.diting.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * An element-hiding CSS cosmetic rule evaluated during HTTP(S) inspection.
 *
 * @param domain target package name or domain (e.g. "com.generalcomp.batian"), empty for global rules
 * @param selector CSS selector (e.g. ".ad-container", "[class*=\"ad-\"]")
 * @param rawLine original rule line, kept for display and diagnostics
 * @param addedAt timestamp when rule was added
 * @param enabled whether the rule is active
 */
@Entity(
    tableName = "cosmetic_rule",
    indices = [Index(value = ["domain", "selector"], unique = true)]
)
data class CosmeticRuleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val domain: String,
    val selector: String,
    val rawLine: String,
    val addedAt: Long,
    val enabled: Boolean = true
)
