package com.haoze.dnssr.data.dao

/** Projection of an enabled rule (rule + source + modifier fields) shared by the allow/block rule caches. */
data class EnabledRule(
    val pattern: String,
    val source: String,
    val important: Boolean = false,
    val appScope: String? = null,
    val appInverted: Boolean = false,
    val isWildcard: Boolean = false
)

data class EnabledRuleKeyset(
    val id: Long,
    val pattern: String,
    val source: String,
    val important: Boolean = false,
    val appScope: String? = null,
    val appInverted: Boolean = false,
    val isWildcard: Boolean = false
) {
    fun toEnabledRule(): EnabledRule = EnabledRule(
        pattern = pattern,
        source = source,
        important = important,
        appScope = appScope,
        appInverted = appInverted,
        isWildcard = isWildcard
    )
}
