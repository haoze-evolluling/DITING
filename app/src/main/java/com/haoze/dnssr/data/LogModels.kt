package com.haoze.dnssr.data

enum class LogFilter { ALL, PASSED, BLOCKED, ERROR, CACHED }

data class LogQueryParams(val filter: LogFilter, val query: String)

data class LogDailyStats(
    val passed: Int,
    val blocked: Int,
    val error: Int,
    val cached: Int
)

enum class SubscriptionInterceptionStatsRange(val displayName: String) {
    TODAY("今日"),
    SEVEN_DAYS("近 7 天"),
    ALL("全部")
}

data class SubscriptionInterceptionStats(
    val totalRequests: Int,
    val hitsBySubscriptionId: Map<Long, Int>
)
