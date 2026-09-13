package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** A request-level rule evaluated by the Go tunnel after HTTP decryption. */
@Entity(
    tableName = "go_url_rule",
    indices = [Index(value = ["pattern", "kind"], unique = true)]
)
data class GoUrlRuleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val pattern: String,
    val kind: String,
    val rawLine: String,
    val addedAt: Long,
    val enabled: Boolean = true
)

object GoUrlRuleKind {
    const val BLOCK = "block"
    const val ALLOW = "allow"
}
