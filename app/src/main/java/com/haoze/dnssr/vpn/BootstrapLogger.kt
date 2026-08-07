package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.BootstrapLogDao
import com.haoze.dnssr.data.entity.BootstrapLogEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class BootstrapLogger(
    private val dao: BootstrapLogDao,
    private val retentionDays: Int,
    private val flushScope: CoroutineScope? = null
) {
    private val pruneIntervalMs = 60 * 60 * 1000L
    private var lastPruneTime = 0L
    private val mutex = Mutex()
    private val pending = ArrayList<BootstrapLogEntity>(BATCH_SIZE)
    private var scheduledFlush: Job? = null

    suspend fun log(
        ipId: String,
        ipName: String,
        ip: String,
        host: String,
        success: Boolean,
        elapsedMs: Long,
        fallbackUsed: Boolean = false,
        message: String? = null
    ) {
        enqueue(
            BootstrapLogEntity(
                timestamp = System.currentTimeMillis(),
                ipId = ipId,
                ipName = ipName,
                ip = ip,
                host = host,
                success = success,
                elapsedMs = elapsedMs,
                fallbackUsed = fallbackUsed,
                message = message
            )
        )
    }

    private suspend fun enqueue(entity: BootstrapLogEntity) {
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

    private suspend fun maybePrune() {
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
