package com.haoze.diting.log

/// Second-resolution rates for the notification, from the deltas `TrafficIngest` parses.
///
/// The rate arithmetic (elapsed interval, first-tick rule) lives in the log kernel next to the
/// request counters; the `↑ 1.2 MB/s` text is formatted by `rust/diting-notification-core`.
object TrafficRateMonitor {
    fun onTick(tx: Long, rx: Long) = LogNative.rateTick(RequestStats.kernel, tx, rx)

    fun reset() = LogNative.statsRateReset(RequestStats.kernel)

    fun snapshot(): Pair<Long, Long> = LogNative.rateSnapshot(RequestStats.kernel)
}
