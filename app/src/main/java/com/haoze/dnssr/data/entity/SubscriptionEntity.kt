package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 规则订阅源实体。
 */
@Entity(
    tableName = "subscription",
    indices = [Index(value = ["url", "scope"], unique = true), Index(value = ["groupId"])]
)
data class SubscriptionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val url: String,
    val name: String,
    val sourceType: String = SubscriptionSourceType.REMOTE,
    val kind: String = SubscriptionKind.BLOCK,
    val enabled: Boolean = true,
    val ruleCount: Int = 0,
    val lastUpdated: Long = 0,
    val addedAt: Long = System.currentTimeMillis(),
    val importState: String = SubscriptionImportState.READY,
    val importError: String? = null,
    val httpEtag: String? = null,
    val httpLastModified: String? = null,
    val ruleSetHash: String? = null,
    val lastAttemptAt: Long = 0,
    val consecutiveFailureCount: Int = 0,
    val mirrorTemplate: String? = null,
    val mirrorFallback: Boolean = true,
    val scope: String = RuleScope.DNS.storageValue,
    val groupId: Long? = null
)

object SubscriptionSourceType {
    const val REMOTE = "remote"
    const val LOCAL = "local"
}

object SubscriptionKind {
    const val BLOCK = "block"
    const val ALLOW = "allow"
    const val REWRITE = "rewrite"
}

object SubscriptionImportState {
    const val READY = "ready"
    const val IMPORTING = "importing"
    const val FAILED = "failed"
}
