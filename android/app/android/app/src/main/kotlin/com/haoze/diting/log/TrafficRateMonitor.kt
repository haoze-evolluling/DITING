package com.haoze.diting.log

object TrafficRateMonitor {
    fun onTick(tx: Long, rx: Long) = LogNative.rateTick(RequestStats.kernel, tx, rx)

    fun reset() = LogNative.statsRateReset(RequestStats.kernel)

    fun snapshot(): Pair<Long, Long> = LogNative.rateSnapshot(RequestStats.kernel)
}
