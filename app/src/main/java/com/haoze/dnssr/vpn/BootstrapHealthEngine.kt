package com.haoze.dnssr.vpn

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow
import kotlin.random.Random

class BootstrapHealthEngine(
    private val context: Context,
    private val scope: CoroutineScope
) : BootstrapHealthStoreListener {
    private val healthByIp = BootstrapHealthStore.loadAll(context).toMutableMap()
    private var dirty = false
    private var closed = false
    private var scheduledFlushJob: Job? = null

    init {
        activeEngine = this
        BootstrapHealthStore.registerListener(this)
    }

    @Synchronized
    fun loadAll(): Map<String, BootstrapHealthSnapshot> {
        val now = System.currentTimeMillis()
        return healthByIp.mapValues { (_, snapshot) -> snapshot.decayed(now) }
    }

    @Synchronized
    fun choosePlan(entries: List<BootstrapIpEntry>): BootstrapIpPlan {
        if (entries.isEmpty()) return BootstrapIpPlan(primaryIndex = -1)
        if (entries.size == 1) {
            return BootstrapIpPlan(primaryIndex = 0, fallbackIndices = emptyList(), exploration = false)
        }

        val now = System.currentTimeMillis()
        val scored = entries.mapIndexed { index, entry ->
            val snapshot = healthByIp[entry.id]?.decayed(now)
            BootstrapScore(
                index = index,
                weight = snapshot?.predictionWeight ?: DEFAULT_WEIGHT,
                coolingDown = snapshot?.let { now < it.cooldownUntil } ?: false,
                sampleCount = snapshot?.let { it.decayedSuccesses + it.decayedFailures } ?: 0.0
            )
        }
        val candidates = scored.filterNot { it.coolingDown }.ifEmpty { scored }
        val explorationRate = when {
            scored.any { it.coolingDown } -> RECOVERY_EXPLORATION_RATE
            scored.any { it.sampleCount < LOW_SAMPLE_THRESHOLD } -> LOW_SAMPLE_EXPLORATION_RATE
            else -> BASE_EXPLORATION_RATE
        }
        val exploration = Random.nextDouble() < explorationRate
        val primary = if (exploration) candidates.random() else chooseWeighted(candidates)
        val fallbackIndices = scored
            .filter { it.index != primary.index }
            .sortedByDescending { it.weight }
            .map { it.index }

        return BootstrapIpPlan(
            primaryIndex = primary.index,
            fallbackIndices = fallbackIndices,
            exploration = exploration
        )
    }

    @Synchronized
    fun recordResult(ipId: String, success: Boolean, elapsedMs: Long) {
        if (closed) return
        val now = System.currentTimeMillis()
        val current = healthByIp[ipId]?.decayed(now)
            ?: BootstrapHealthSnapshot(
                ipId = ipId,
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

        healthByIp[ipId] = current.copy(
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
        BootstrapHealthStore.saveAll(context, loadAll(), commit = commit)
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
        BootstrapHealthStore.unregisterListener(this)
        if (activeEngine === this) {
            activeEngine = null
        }
        flush(commit = true)
    }

    @Synchronized
    override fun onBootstrapHealthReset(ipIds: Set<String>) {
        ipIds.forEach { healthByIp.remove(it) }
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

    private fun chooseWeighted(scores: List<BootstrapScore>): BootstrapScore {
        val total = scores.sumOf { it.weight }.takeIf { it > 0.0 } ?: return scores.first()
        var remaining = Random.nextDouble(total)
        scores.forEach { score ->
            remaining -= score.weight
            if (remaining <= 0.0) return score
        }
        return scores.last()
    }

    private fun BootstrapHealthSnapshot.decayed(now: Long): BootstrapHealthSnapshot {
        val elapsed = max(0L, now - lastUpdatedAt)
        if (elapsed == 0L) return this
        val factor = 0.5.pow(elapsed.toDouble() / HEALTH_HALF_LIFE_MS)
        return copy(
            decayedSuccesses = decayedSuccesses * factor,
            decayedFailures = decayedFailures * factor,
            lastUpdatedAt = now
        )
    }

    private data class BootstrapScore(
        val index: Int,
        val weight: Double,
        val coolingDown: Boolean,
        val sampleCount: Double
    )

    companion object {
        @Volatile
        private var activeEngine: BootstrapHealthEngine? = null

        fun flushActive(commit: Boolean = true): Boolean {
            val engine = activeEngine ?: return false
            engine.flush(commit = commit)
            return true
        }

        private const val FLUSH_DELAY_MS = 15_000L
        private const val HEALTH_HALF_LIFE_MS = 30 * 60 * 1000.0
        private const val DEFAULT_LATENCY_MS = 250.0
        private const val DEFAULT_WEIGHT = 1.0
        private const val EWMA_ALPHA = 0.25
        private const val JITTER_ALPHA = 0.2
        private const val BASE_EXPLORATION_RATE = 0.02
        private const val LOW_SAMPLE_EXPLORATION_RATE = 0.08
        private const val RECOVERY_EXPLORATION_RATE = 0.10
        private const val LOW_SAMPLE_THRESHOLD = 10.0
        private const val COOLDOWN_FAILURE_THRESHOLD = 3
        private const val COOLDOWN_MS = 30_000L
    }
}

data class BootstrapIpPlan(
    val primaryIndex: Int,
    val fallbackIndices: List<Int> = emptyList(),
    val exploration: Boolean = false
)
