package com.haoze.dnssr.data

enum class BootstrapStatsRange(val displayName: String) {
    TODAY("今日"),
    SEVEN_DAYS("7 天"),
    ALL("全部")
}

data class BootstrapStats(
    val overall: BootstrapOverallStats,
    val ipStats: List<BootstrapIpStats>
)

data class BootstrapOverallStats(
    val attempts: Int,
    val successes: Int,
    val failures: Int,
    val avgElapsedMs: Double,
    val fallbackUses: Int
) {
    val successRate: Double = ratio(successes, attempts)
    val fallbackRate: Double = ratio(fallbackUses, attempts)
}

data class BootstrapIpStats(
    val ipId: String,
    val ipName: String,
    val ip: String,
    val attempts: Int,
    val successes: Int,
    val failures: Int,
    val avgElapsedMs: Double,
    val fallbackUses: Int,
    val predictionWeight: Double,
    val ewmaMs: Double,
    val consecutiveFailures: Int,
    val cooldownUntil: Long
) {
    val successRate: Double = ratio(successes, attempts)
}

private fun ratio(numerator: Int, denominator: Int): Double {
    return if (denominator <= 0) 0.0 else numerator.toDouble() / denominator
}
