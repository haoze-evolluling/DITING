package com.haoze.diting.ui

import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity

enum class WhitelistType {
    DOMAIN,
    URL,
    COSMETIC
}

enum class WhitelistFilter(val labelResName: String) {
    ALL("全部"),
    USER_ADDED("用户自定义"),
    PRESET("默认预设"),
    SUBSCRIPTION("规则订阅"),
    DOMAIN("域名放行"),
    URL("URL 放行"),
    COSMETIC("元素放行")
}

data class WhitelistItem(
    val id: Long,
    val pattern: String,
    val rawLine: String,
    val type: WhitelistType,
    val isPreset: Boolean,
    val groupName: String?,
    val appScope: String?,
    val appInverted: Boolean,
    val isWildcard: Boolean,
    val important: Boolean,
    val enabled: Boolean,
    val masterEnabled: Boolean = true,
    val effectiveEnabled: Boolean = enabled && masterEnabled,
    val addedAt: Long,
    val isUserRule: Boolean = true,
    val isSubscription: Boolean = false,
    val subscriptionName: String? = null
)

data class WhitelistStats(
    val totalDomains: Int = 0,
    val presetTotal: Int = 0,
    val presetEnabled: Int = 0,
    val userTotal: Int = 0,
    val userEnabled: Int = 0,
    val subscriptionTotal: Int = 0,
    val subscriptionEnabled: Int = 0,
    val urlAllowCount: Int = 0,
    val cosmeticCount: Int = 0,
    val totalActive: Int = 0
)

internal fun AllowRuleEntity.toItem(
    isPreset: Boolean,
    isUserRule: Boolean = true,
    isSubscription: Boolean = false,
    subscriptionName: String? = null,
    masterEnabled: Boolean = true
): WhitelistItem = WhitelistItem(
    id = id,
    pattern = pattern,
    rawLine = rawLine,
    type = WhitelistType.DOMAIN,
    isPreset = isPreset,
    groupName = groupName,
    appScope = appScope,
    appInverted = appInverted,
    isWildcard = isWildcard,
    important = important,
    enabled = enabled,
    masterEnabled = masterEnabled,
    effectiveEnabled = enabled && masterEnabled,
    addedAt = addedAt,
    isUserRule = isUserRule,
    isSubscription = isSubscription,
    subscriptionName = subscriptionName
)

internal fun GoUrlRuleEntity.toItem(
    isUserRule: Boolean = true,
    isSubscription: Boolean = false,
    subscriptionName: String? = null,
    masterEnabled: Boolean = true
): WhitelistItem = WhitelistItem(
    id = id,
    pattern = pattern,
    rawLine = rawLine,
    type = WhitelistType.URL,
    isPreset = false,
    groupName = null,
    appScope = null,
    appInverted = false,
    isWildcard = false,
    important = false,
    enabled = enabled,
    masterEnabled = masterEnabled,
    effectiveEnabled = enabled && masterEnabled,
    addedAt = addedAt,
    isUserRule = isUserRule,
    isSubscription = isSubscription,
    subscriptionName = subscriptionName
)

internal fun CosmeticRuleEntity.toItem(
    isUserRule: Boolean = true,
    isSubscription: Boolean = false,
    subscriptionName: String? = null,
    masterEnabled: Boolean = true
): WhitelistItem = WhitelistItem(
    id = id,
    pattern = rawLine.ifBlank { if (domain.isNotEmpty()) "$domain#@#$selector" else "#@#$selector" },
    rawLine = rawLine,
    type = WhitelistType.COSMETIC,
    isPreset = false,
    groupName = null,
    appScope = domain.takeIf { it.isNotBlank() },
    appInverted = false,
    isWildcard = false,
    important = false,
    enabled = enabled,
    masterEnabled = masterEnabled,
    effectiveEnabled = enabled && masterEnabled,
    addedAt = addedAt,
    isUserRule = isUserRule,
    isSubscription = isSubscription,
    subscriptionName = subscriptionName
)
