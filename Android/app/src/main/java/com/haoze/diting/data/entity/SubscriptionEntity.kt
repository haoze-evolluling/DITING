package com.haoze.diting.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "subscription",
    indices = [
        Index(value = ["url", "kind"], unique = true),
        Index(value = ["groupId"])
    ]
)
data class SubscriptionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val url: String,
    val name: String,
    val sourceType: String = SubscriptionSourceType.REMOTE,
    val kind: String = SubscriptionKind.DOMAIN,
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
    val groupId: Long? = null
)

object SubscriptionSourceType {
    const val REMOTE = "remote"
    const val LOCAL = "local"
}

/**
 * Subscription rule type. A subscription carries exactly one type of rule:
 *
 * - [DOMAIN]: block / allow domain rules (`||example.com^`, `@@||example.com^`,
 *   plain domains, dnsmasq sinkhole lines).
 * - [HOSTS]: rewriting rules that map a domain to a literal address or CNAME
 *   (hosts `IP domain` lines, `address=/domain/ip`, `$dnsrewrite=`).
 *
 * Rules whose target is a sinkhole address (`0.0.0.0`, `::`, ...) are counted
 * as [DOMAIN] rules, matching the parser's own classification.
 */
object SubscriptionKind {
    const val DOMAIN = "domain"
    const val HOSTS = "hosts"

    val ALL: List<String> = listOf(DOMAIN, HOSTS)

    /** Normalizes kind to [DOMAIN] or [HOSTS]. */
    fun normalize(kind: String?): String = when (kind?.trim()?.lowercase()) {
        HOSTS -> HOSTS
        else -> DOMAIN
    }

    fun isHosts(kind: String?): Boolean = normalize(kind) == HOSTS

    fun isDomain(kind: String?): Boolean = normalize(kind) == DOMAIN

    /** True when [kind] is a valid subscription kind. */
    fun isCanonical(kind: String?): Boolean = kind?.trim()?.lowercase() in ALL

    /** Display name used in user-facing diagnostics. */
    fun displayName(kind: String?): String =
        if (isHosts(kind)) "hosts 规则" else "黑白名单规则"
}

object SubscriptionImportState {
    const val READY = "ready"
    const val IMPORTING = "importing"
    const val FAILED = "failed"
}
