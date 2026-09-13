package com.haoze.dnssr.vpn

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow

class ProviderHealthEngine(
    private val context: Context,
    private val scope: CoroutineScope
) : ProviderHealthStoreListener {
    private val healthByProvider = ProviderHealthStore.loadAll(context).toMutableMap()
    private var dirty = false
    private var closed = false
    private var scheduledFlushJob: Job? = null

    init {
        activeEngine = this
        ProviderHealthStore.registerListener(this)
    }

    @Synchronized
    fun loadAll(): Map<String, ProviderHealthSnapshot> {
        val now = System.currentTimeMillis()
        return healthByProvider.mapValues { (_, snapshot) -> snapshot.decayed(now) }
    }

    @Synchronized
    fun recordResult(providerId: String, success: Boolean, elapsedMs: Long) {
        if (closed) return
        val now = System.currentTimeMillis()
        val current = healthByProvider[providerId]?.decayed(now)
            ?: ProviderHealthSnapshot(
                providerId = providerId,
                successes = 0,
                failures = 0,
                ewmaMs = DEFAULT_LATENCY_MS,
                lastUpdatedAt = now,
                decayedSuccesses = 0.0,
                decayedFailures = 0.0
            )

        val safeElapsed = elapsedMs.coerceAtLeast(1L).toDouble()
        val nextSuccesses = current.successes + if (success) 1 else 0
        val nextFailures = current.failures + if (success) 0 else 1
        val nextEwma = if (success) {
            current.ewmaMs * (1.0 - EWMA_ALPHA) + safeElapsed * EWMA_ALPHA
        } else {
            current.ewmaMs
        }
        val nextJitter = if (success) {
            current.jitterMs * (1.0 - JITTER_ALPHA) + abs(safeElapsed - current.ewmaMs) * JITTER_ALPHA
        } else {
            current.jitterMs
        }
        val nextConsecutiveFailures = if (success) 0 else current.consecutiveFailures + 1
        val cooldownUntil = if (nextConsecutiveFailures >= COOLDOWN_FAILURE_THRESHOLD) {
            now + COOLDOWN_MS
        } else {
            0L
        }

        healthByProvider[providerId] = current.copy(
            successes = nextSuccesses,
            failures = nextFailures,
            ewmaMs = nextEwma,
            jitterMs = nextJitter,
            consecutiveFailures = nextConsecutiveFailures,
            cooldownUntil = cooldownUntil,
            decayedSuccesses = current.decayedSuccesses + if (success) 1.0 else 0.0,
            decayedFailures = current.decayedFailures + if (success) 0.0 else 1.0,
            lastUpdatedAt = now
        )
        markDirty()
    }

    @Synchronized
    fun flush(commit: Boolean = false) {
        if (!dirty && !commit) return
        cancelScheduledFlush()
        ProviderHealthStore.saveAll(context, loadAll(), commit = commit)
        dirty = false
    }

    fun close() {
        val shouldClose = synchronized(this) {
            if (closed) {
                false
            } else {
                closed = true
                true
            }
        }
        if (!shouldClose) return
        synchronized(this) {
            cancelScheduledFlush()
        }
        ProviderHealthStore.unregisterListener(this)
        if (activeEngine === this) {
            activeEngine = null
        }
        flush(commit = true)
    }

    @Synchronized
    override fun onProviderHealthReset(providerIds: Set<String>) {
        providerIds.forEach { healthByProvider.remove(it) }
        flush(commit = true)
    }

    private fun markDirty() {
        dirty = true
        if (scheduledFlushJob?.isActive == true) return
        scheduledFlushJob = scope.launch {
            delay(FLUSH_DELAY_MS)
            flush()
        }
    }

    private fun cancelScheduledFlush() {
        scheduledFlushJob?.cancel()
        scheduledFlushJob = null
    }

    private fun ProviderHealthSnapshot.decayed(now: Long): ProviderHealthSnapshot {
        val elapsed = max(0L, now - lastUpdatedAt)
        if (elapsed == 0L) return this
        val factor = 0.5.pow(elapsed.toDouble() / HEALTH_HALF_LIFE_MS)
        return copy(
            decayedSuccesses = decayedSuccesses * factor,
            decayedFailures = decayedFailures * factor,
            decayedHedgeMisses = decayedHedgeMisses * factor,
            lastUpdatedAt = now
        )
    }

    companion object {
        @Volatile
        private var activeEngine: ProviderHealthEngine? = null

        fun flushActive(commit: Boolean = true): Boolean {
            val engine = activeEngine ?: return false
            engine.flush(commit = commit)
            return true
        }

        private const val FLUSH_DELAY_MS = 15_000L
        private const val HEALTH_HALF_LIFE_MS = 30 * 60 * 1000.0
        private const val DEFAULT_LATENCY_MS = 250.0
        private const val EWMA_ALPHA = 0.25
        private const val JITTER_ALPHA = 0.2
        private const val COOLDOWN_FAILURE_THRESHOLD = 3
        private const val COOLDOWN_MS = 30_000L
    }
}
