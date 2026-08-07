package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.RaceLogDao
import com.haoze.dnssr.data.entity.RaceLogEntity
import com.haoze.dnssr.ui.RaceModeStrategy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class RaceLogger(
    private val dao: RaceLogDao,
    private val retentionDays: Int,
    private val flushScope: CoroutineScope? = null
) {

    private val pruneIntervalMs = 60 * 60 * 1000L
    private var lastPruneTime = 0L
    private val mutex = Mutex()
    private val pending = ArrayList<RaceLogEntity>(BATCH_SIZE)
    private var scheduledFlush: Job? = null

    suspend fun log(
        queryName: String,
        queryType: Int,
        strategy: RaceModeStrategy,
        providerCount: Int,
        success: Boolean,
        elapsedMs: Long,
        selectedProvider: DnsProvider? = null,
        selectedElapsedMs: Long? = null,
        winnerProvider: DnsProvider? = null,
        winnerElapsedMs: Long? = null,
        fallbackUsed: Boolean = false,
        fallbackSuccess: Boolean = false,
        message: String? = null
    ) {
        enqueue(
            RaceLogEntity(
                timestamp = System.currentTimeMillis(),
                queryName = queryName.lowercase(),
                queryType = queryType,
                strategy = strategy.storageValue,
                providerCount = providerCount,
                success = success,
                elapsedMs = elapsedMs,
                selectedProviderId = selectedProvider?.id,
                selectedProviderName = selectedProvider?.name,
                selectedElapsedMs = selectedElapsedMs,
                winnerProviderId = winnerProvider?.id,
                winnerProviderName = winnerProvider?.name,
                winnerElapsedMs = winnerElapsedMs,
                fallbackUsed = fallbackUsed,
                fallbackSuccess = fallbackSuccess,
                message = message
            )
        )
    }

    private suspend fun enqueue(entity: RaceLogEntity) {
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
