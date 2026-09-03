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
 * DNS 请求日志记录器，支持批量缓冲与异步写入。
 * 过期日志清理统一由 [LogMaintenance] 调度管理。
 */
class DnsLogger(
    private val dao: DnsLogDao,
    private val flushScope: CoroutineScope? = null,
    private val modeProvider: () -> DnsLogMode = { DnsLogMode.ALL }
) {

    private val mutex = Mutex()
    private val pending = ArrayList<DnsLogEntity>(BATCH_SIZE)
    private var scheduledFlush: Job? = null

    fun isLoggable(result: LogResult): Boolean {
        val mode = modeProvider()
        if (mode == DnsLogMode.OFF) return false
        if (mode == DnsLogMode.BLOCKED_AND_ERRORS && result == LogResult.PASSED) return false
        return true
    }

    suspend fun log(
        queryName: String,
        queryType: Int,
        result: LogResult,
        message: String? = null,
        cached: Boolean = false,
        blockSubscriptionId: Long? = null,
        packageName: String? = null
    ) {
        if (!isLoggable(result)) return
        enqueue(
            DnsLogEntity(
                timestamp = System.currentTimeMillis(),
                queryName = queryName.lowercase(),
                queryType = queryType,
                result = result.value,
                message = message,
                cached = cached,
                blockSubscriptionId = blockSubscriptionId,
                packageName = packageName
            )
        )
    }

    suspend fun logBatch(entities: List<DnsLogEntity>) {
        if (entities.isEmpty()) return
        val batch = mutex.withLock {
            scheduledFlush?.cancel()
            scheduledFlush = null
            if (pending.isEmpty()) {
                entities
            } else {
                val combined = ArrayList<DnsLogEntity>(pending.size + entities.size)
                combined.addAll(pending)
                combined.addAll(entities)
                pending.clear()
                combined
            }
        }
        if (batch.isNotEmpty()) {
            runCatching {
                batch.chunked(100).forEach { dao.insertAll(it) }
            }
        }
    }

    private suspend fun enqueue(entity: DnsLogEntity) {
        val batch = mutex.withLock {
            if (pending.isEmpty()) {
                scheduleFlush()
            }
            pending.add(entity)
            if (pending.size >= BATCH_SIZE) {
                scheduledFlush?.cancel()
                scheduledFlush = null
                val snapshot = pending.toList()
                pending.clear()
                snapshot
            } else {
                null
            }
        }
        if (batch != null && batch.isNotEmpty()) {
            runCatching { dao.insertAll(batch) }
        }
    }

    suspend fun flush() {
        val batch = mutex.withLock {
            scheduledFlush?.cancel()
            scheduledFlush = null
            val snapshot = pending.toList()
            pending.clear()
            snapshot
        }
        if (batch.isNotEmpty()) {
            runCatching { dao.insertAll(batch) }
        }
    }

    private suspend fun flushFromTimer() {
        val batch = mutex.withLock {
            scheduledFlush = null
            val snapshot = pending.toList()
            pending.clear()
            snapshot
        }
        if (batch.isNotEmpty()) {
            runCatching { dao.insertAll(batch) }
        }
    }

    private fun scheduleFlush() {
        scheduledFlush = flushScope?.launch {
            delay(FLUSH_INTERVAL_MS)
            flushFromTimer()
        }
    }

    suspend fun clearAll() {
        mutex.withLock {
            scheduledFlush?.cancel()
            scheduledFlush = null
            pending.clear()
            dao.clearAll()
        }
    }

    companion object {
        private const val BATCH_SIZE = 50
        private const val FLUSH_INTERVAL_MS = 3_000L
    }
}
