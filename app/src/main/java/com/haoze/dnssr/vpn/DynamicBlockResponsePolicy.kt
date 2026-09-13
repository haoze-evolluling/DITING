package com.haoze.dnssr.vpn

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class DynamicBlockResponseConfig(
    val enabled: Boolean = false,
    val requestThreshold: Int = DEFAULT_REQUEST_THRESHOLD,
    val windowSeconds: Int = DEFAULT_WINDOW_SECONDS,
    val nxDomainDurationSeconds: Int = DEFAULT_NXDOMAIN_DURATION_SECONDS
) {
    companion object {
        const val DEFAULT_REQUEST_THRESHOLD = 5
        const val DEFAULT_WINDOW_SECONDS = 60
        const val DEFAULT_NXDOMAIN_DURATION_SECONDS = 300
        const val MIN_REQUEST_THRESHOLD = 2
        const val MAX_REQUEST_THRESHOLD = 100
        const val MIN_WINDOW_SECONDS = 10
        const val MAX_WINDOW_SECONDS = 300
        const val MIN_NXDOMAIN_DURATION_SECONDS = 60
        const val MAX_NXDOMAIN_DURATION_SECONDS = 3_600
    }
}

/** Tracks short-lived dynamic blocking decisions for the running VPN session only. */
class DynamicBlockResponseTracker {
    private data class Entry(
        var windowStartedAt: Long,
        var requestCount: Int,
        var nxDomainUntil: Long = 0L
    )

    private val mutex = Mutex()
    private val entries = LinkedHashMap<String, Entry>()

    suspend fun clear() = mutex.withLock { entries.clear() }
}
