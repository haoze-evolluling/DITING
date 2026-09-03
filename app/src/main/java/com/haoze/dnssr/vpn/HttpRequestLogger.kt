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

/**
 * HTTP 请求日志记录器，支持批量缓冲与异步写入。
 * 过期日志清理统一由 [LogMaintenance] 调度管理。
 */
class HttpRequestLogger(
    private val dao: HttpRequestLogDao,
    private val flushScope: CoroutineScope? = null,
    private val modeProvider: () -> DnsLogMode = { DnsLogMode.ALL }
) {
    constructor(
        dao: HttpRequestLogDao,
        retentionDays: Int,
        flushScope: CoroutineScope? = null,
        modeProvider: () -> DnsLogMode = { DnsLogMode.ALL }
    ) : this(dao, flushScope, modeProvider)

    private val mutex = Mutex()
    private val pending = ArrayList<HttpRequestLogEntity>(BATCH_SIZE)
    private var scheduledFlush: Job? = null

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
        val batch = pending.toList()
        pending.clear()
        dao.insertAll(batch)
    }

    private companion object {
        const val BATCH_SIZE = 20
        const val FLUSH_INTERVAL_MS = 2_000L
    }
}
