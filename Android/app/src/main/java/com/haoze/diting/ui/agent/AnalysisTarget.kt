package com.haoze.diting.ui.agent

import com.haoze.diting.data.RequestSource

/**
 * Represents the target entity for agent intelligence analysis.
 */
sealed interface AnalysisTarget {
    data class Domain(
        val domain: String,
        val contextLogs: List<String> = emptyList()
    ) : AnalysisTarget

    data class RecentTraffic(
        val source: RequestSource = RequestSource.ALL
    ) : AnalysisTarget
}
