package com.haoze.diting.core.log

import com.haoze.diting.data.dao.DnsLogDao
import com.haoze.diting.data.entity.DnsLogEntity
import com.haoze.diting.ui.DnsLogMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * DNS request logger with batch buffering, serialized asynchronous writes,
 * and backpressure protection. Expiry cleanup is scheduled centrally by [LogMaintenance].
 */
class DnsLogger(
    private val dao: DnsLogDao,
    private val flushScope: CoroutineScope? = null,
    private val modeProvider: () -> DnsLogMode = { DnsLogMode.ALL }
) {

    private val mutex = Mutex()
    private val writeMutex = Mutex()
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
                if (entities.size > MAX_PENDING_QUEUE) {
                    entities.takeLast(MAX_PENDING_QUEUE)
                } else {
                    entities
                }
            } else {
                val combined = ArrayList<DnsLogEntity>(pending.size + entities.size)
                combined.addAll(pending)
                combined.addAll(entities)
                pending.clear()
                if (combined.size > MAX_PENDING_QUEUE) {
                    combined.takeLast(MAX_PENDING_QUEUE)
                } else {
                    combined
                }
            }
        }
        if (batch.isNotEmpty()) {
            flushBatch(batch)
        }
    }

    private suspend fun enqueue(entity: DnsLogEntity) {
        val batch = mutex.withLock {
            if (pending.size >= MAX_PENDING_QUEUE) {
                pending.removeAt(0)
            }
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
            flushBatch(batch)
        }
    }

    private suspend fun flushBatch(batch: List<DnsLogEntity>) {
        val scope = flushScope
        if (scope != null) {
            scope.launch(Dispatchers.IO) {
                writeMutex.withLock {
                    runCatching {
                        batch.chunked(100).forEach { dao.insertAll(it) }
                    }
                }
            }
        } else {
            withContext(Dispatchers.IO) {
                writeMutex.withLock {
                    runCatching {
                        batch.chunked(100).forEach { dao.insertAll(it) }
                    }
                }
            }
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
            withContext(Dispatchers.IO) {
                writeMutex.withLock {
                    runCatching {
                        batch.chunked(100).forEach { dao.insertAll(it) }
                    }
                }
            }
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
            flushBatch(batch)
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
        }
        withContext(Dispatchers.IO) {
            writeMutex.withLock {
                dao.clearAll()
            }
        }
    }

    companion object {
        private const val BATCH_SIZE = 50
        private const val FLUSH_INTERVAL_MS = 500L
        private const val MAX_PENDING_QUEUE = 2_000
    }
}
