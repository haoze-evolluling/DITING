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

enum class RequestSource(val label: String) {
    ALL("全部"),
    DNS("DNS"),
    HTTPS("HTTPS")
}

enum class RequestStatus(val label: String, val explanation: String) {
    ALL("全部", "显示所有请求记录"),
    PASSED("通过", "请求正常放行，未命中拦截规则"),
    REWRITTEN("覆写", "请求命中了覆写规则，并返回覆写后的结果"),
    BLOCKED("过滤", "请求命中了过滤规则并被拦截"),
    ERROR("失败", "请求解析或处理失败"),
    BYPASSED("旁路", "请求未被读取或过滤，直接建立连接")
}
