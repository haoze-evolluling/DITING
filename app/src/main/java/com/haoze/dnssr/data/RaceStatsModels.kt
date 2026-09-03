package com.haoze.dnssr.data

enum class RaceStatsRange(val displayName: String) {
    TODAY("今日"),
    SEVEN_DAYS("7 天"),
    ALL("全部")
}

data class RaceStats(
    val strategyStats: List<RaceStrategyStats>,
    val winnerStats: List<RaceWinnerStats>,
    val smartSelectionStats: List<SmartSelectionStats>
)

data class RaceStrategyStats(
    val strategy: String,
    val displayName: String,
    val requests: Int,
    val successes: Int,
    val failures: Int,
    val avgElapsedMs: Double,
    val fallbackUses: Int,
    val fallbackSuccesses: Int,
    val primaryWins: Int
) {
    val successRate: Double = ratio(successes, requests)
    val fallbackRate: Double = ratio(fallbackUses, requests)
    val primaryWinRate: Double = ratio(primaryWins, requests)
}

data class RaceWinnerStats(
    val strategy: String,
    val providerId: String,
    val providerName: String,
    val wins: Int,
    val avgWinnerElapsedMs: Double
)

data class SmartSelectionStats(
    val providerId: String,
    val providerName: String,
    val selectedCount: Int,
    val selectedSuccesses: Int,
    val avgSelectedElapsedMs: Double
) {
    val selectedSuccessRate: Double = ratio(selectedSuccesses, selectedCount)
}

private fun ratio(numerator: Int, denominator: Int): Double {
    return if (denominator <= 0) 0.0 else numerator.toDouble() / denominator
}
