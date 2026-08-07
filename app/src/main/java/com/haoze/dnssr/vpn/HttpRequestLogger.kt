package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.HttpRequestLogDao
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import com.haoze.dnssr.ui.DnsLogMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.Locale

enum class HttpRequestOutcome(val storageValue: String) {
    ALLOWED("allowed"),
    REWRITTEN("rewritten"),
    BLOCKED("blocked"),
    INVALID("invalid"),
    DECRYPTION_FAILED("decryption_failed")
}

class HttpRequestLogger(
    private val dao: HttpRequestLogDao,
    private val retentionDays: Int,
    private val flushScope: CoroutineScope? = null,
    private val modeProvider: () -> DnsLogMode = { DnsLogMode.ALL }
) {
    private val mutex = Mutex()
    private val pending = ArrayList<HttpRequestLogEntity>(BATCH_SIZE)
    private var scheduledFlush: Job? = null
    private var lastPruneTime = 0L

    suspend fun log(
        packageName: String,
        authority: String?,
        protocol: String,
        outcome: HttpRequestOutcome,
        matchedRule: String? = null,
        blockSubscriptionId: Long? = null
    ) {
        val mode = modeProvider()
        if (mode == DnsLogMode.OFF) return
        if (mode == DnsLogMode.BLOCKED_AND_ERRORS && outcome == HttpRequestOutcome.ALLOWED) return
        mutex.withLock {
            if (pending.isEmpty()) scheduleFlush()
            pending += HttpRequestLogEntity(
                timestamp = System.currentTimeMillis(),
                packageName = packageName,
                authority = authority?.lowercase(Locale.ROOT),
                protocol = protocol,
                outcome = outcome.storageValue,
                matchedRule = matchedRule,
                blockSubscriptionId = blockSubscriptionId
            )
            if (pending.size >= BATCH_SIZE) flushLocked()
        }
    }

    suspend fun flush() = mutex.withLock { flushLocked() }

    suspend fun clearAll() {
        mutex.withLock {
            scheduledFlush?.cancel()
            scheduledFlush = null
            pending.clear()
            dao.clearAll()
        }
    }

    private fun scheduleFlush() {
        scheduledFlush = flushScope?.launch {
            delay(FLUSH_INTERVAL_MS)
            mutex.withLock {
                scheduledFlush = null
                flushLocked()
            }
        }
    }

    private suspend fun flushLocked() {
        if (pending.isEmpty()) return
        scheduledFlush?.cancel()
        scheduledFlush = null
        dao.insertAll(pending.toList())
        pending.clear()
        val now = System.currentTimeMillis()
        if (now - lastPruneTime >= PRUNE_INTERVAL_MS) {
            lastPruneTime = now
            dao.deleteBefore(now - retentionDays * DAY_MS)
        }
    }

    private companion object {
        const val BATCH_SIZE = 20
        const val FLUSH_INTERVAL_MS = 2_000L
        const val PRUNE_INTERVAL_MS = 60 * 60 * 1_000L
        const val DAY_MS = 24 * 60 * 60 * 1_000L
    }
}
