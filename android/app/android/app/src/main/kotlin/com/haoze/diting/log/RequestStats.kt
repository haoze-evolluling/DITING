package com.haoze.diting.log

/// Request counts for the notification, since the running service started.
///
/// The counters themselves live in the log kernel (`rust/diting-log-core/src/stats.rs`), because the
/// classification is the same one `dns_log` and the dashboard use: rewritten answers also count as
/// passed, cached counts only passed answers, and bypassed HTTPS flows count toward the total only.
/// The handle is process-wide like the old singleton, and it is never freed: the process ends with it.
object RequestStats {
    /// The kernel's handle, shared with `DnsLogWriter` and `HttpRequestLogWriter`.
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
