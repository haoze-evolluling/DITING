package com.haoze.diting.log

object RequestStats {
    internal val kernel: Long = LogNative.statsNew()

    data class Snapshot(
        val total: Long,
        val passed: Long,
        val filtered: Long,
        val cached: Long,
        val rewritten: Long,
        val failed: Long,
    )

    fun reset() = LogNative.statsRequestReset(kernel)

    fun snapshot(): Snapshot = LogNative.statsSnapshot(kernel).let { counters ->
        Snapshot(
            total = counters.total,
            passed = counters.passed,
            filtered = counters.filtered,
            cached = counters.cached,
            rewritten = counters.rewritten,
            failed = counters.failed,
        )
    }
}
