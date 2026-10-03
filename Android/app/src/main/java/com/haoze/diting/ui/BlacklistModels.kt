package com.haoze.diting.ui

enum class BlacklistType {
    DOMAIN,
    URL,
    COSMETIC
}

enum class BlacklistFilter(val labelResName: String) {
    ALL("全部"),
    USER_ADDED("用户自定义"),
    SUBSCRIPTION("规则订阅"),
    DOMAIN("域名屏蔽"),
    URL("URL 屏蔽"),
    COSMETIC("元素隐藏")
}

data class BlacklistItem(
    val id: Long,
    val pattern: String,
    val rawLine: String,
    val type: BlacklistType,
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

data class BlacklistStats(
    val totalDomains: Int = 0,
    val userTotal: Int = 0,
    val userEnabled: Int = 0,
    val urlBlockCount: Int = 0,
    val cosmeticCount: Int = 0,
    val totalActive: Int = 0
)
