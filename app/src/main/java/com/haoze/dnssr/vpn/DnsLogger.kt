package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.DnsLogDao
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.ui.DnsLogMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * DNS 请求日志记录器，支持按保留天数自动清理。
 */
class DnsLogger(
    private val dao: DnsLogDao,
    private val retentionDays: Int,
    private val flushScope: CoroutineScope? = null,
    private val modeProvider: () -> DnsLogMode = { DnsLogMode.ALL }
) {

    private val pruneIntervalMs = 60 * 60 * 1000L // 1 小时
    private var lastPruneTime = 0L
    private val mutex = Mutex()
    private val pending = ArrayList<DnsLogEntity>(BATCH_SIZE)
    private var scheduledFlush: Job? = null

    suspend fun log(
        queryName: String,
        queryType: Int,
        result: LogResult,
        message: String? = null,
        cached: Boolean = false,
        blockSubscriptionId: Long? = null
    ) {
        val mode = modeProvider()
        if (mode == DnsLogMode.OFF) return
        if (mode == DnsLogMode.BLOCKED_AND_ERRORS && result == LogResult.PASSED) return
        enqueue(
            DnsLogEntity(
                timestamp = System.currentTimeMillis(),
                queryName = queryName.lowercase(),
                queryType = queryType,
                result = result.value,
                message = message,
                cached = cached,
                blockSubscriptionId = blockSubscriptionId
            )
        )
    }

    private suspend fun enqueue(entity: DnsLogEntity) {
        mutex.withLock {
            if (pending.isEmpty()) {
                scheduleFlush()
            }
            pending.add(entity)
            if (pending.size >= BATCH_SIZE) {
                scheduledFlush?.cancel()
                scheduledFlush = null
                flushLocked()
            }
        }
    }

    suspend fun flush() {
        mutex.withLock {
            scheduledFlush?.cancel()
            scheduledFlush = null
            flushLocked()
        }
    }

    private suspend fun flushFromTimer() {
        mutex.withLock {
            scheduledFlush = null
            flushLocked()
        }
    }

    private fun scheduleFlush() {
        scheduledFlush = flushScope?.launch {
            delay(FLUSH_INTERVAL_MS)
            flushFromTimer()
        }
    }

    private suspend fun flushLocked() {
        if (pending.isEmpty()) return
        val batch = pending.toList()
        pending.clear()
        dao.insertAll(batch)
        maybePrune()
    }

    suspend fun maybePrune() {
        val now = System.currentTimeMillis()
        if (now - lastPruneTime >= pruneIntervalMs) {
            lastPruneTime = now
            prune()
        }
    }

    suspend fun prune() {
        val cutoff = System.currentTimeMillis() - retentionDays * 24 * 60 * 60 * 1000L
        dao.deleteBefore(cutoff)
    }

    suspend fun clearAll() {
        flush()
        dao.clearAll()
    }

    companion object {
        private const val BATCH_SIZE = 20
        private const val FLUSH_INTERVAL_MS = 2_000L
    }
}
