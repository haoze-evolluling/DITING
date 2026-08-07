package com.haoze.dnssr.vpn

import android.content.Context
import org.json.JSONObject

data class ProviderHealthSnapshot(
    val providerId: String,
    val successes: Int,
    val failures: Int,
    val ewmaMs: Double,
    val lastUpdatedAt: Long,
    val jitterMs: Double = 0.0,
    val consecutiveFailures: Int = 0,
    val cooldownUntil: Long = 0L,
    val decayedSuccesses: Double = successes.toDouble(),
    val decayedFailures: Double = failures.toDouble(),
    val hedgeMisses: Int = 0,
    val decayedHedgeMisses: Double = hedgeMisses.toDouble()
) {
    val attempts: Int = successes + failures
    val accuracy: Double
        get() {
            val decayedAttempts = decayedSuccesses + decayedFailures
            return if (decayedAttempts <= 0.0) 0.0 else decayedSuccesses / decayedAttempts
        }
    val predictionWeight: Double
        get() {
            val decayedAttempts = decayedSuccesses + decayedFailures
            if (decayedAttempts <= 0.0) return 1.0
            val correctness = (decayedSuccesses + 2.0) / (decayedAttempts + 3.0)
            val speed = if (successes > 0) {
                DEFAULT_LATENCY_MS / (ewmaMs + jitterMs * JITTER_WEIGHT).coerceIn(MIN_LATENCY_MS, MAX_LATENCY_MS)
            } else {
                1.0
            }
            val cooldownPenalty = if (System.currentTimeMillis() < cooldownUntil) COOLDOWN_PENALTY else 1.0
            val failurePenalty = 1.0 / (1.0 + consecutiveFailures * CONSECUTIVE_FAILURE_PENALTY)
            val hedgeMissShare = decayedHedgeMisses / (decayedAttempts + decayedHedgeMisses).coerceAtLeast(1.0)
            val hedgeMissPenalty = 1.0 / (1.0 + hedgeMissShare * HEDGE_MISS_PENALTY)
            return (correctness * speed * cooldownPenalty * failurePenalty * hedgeMissPenalty)
                .coerceIn(MIN_WEIGHT, MAX_WEIGHT)
        }

    companion object {
        private const val DEFAULT_LATENCY_MS = 250.0
        private const val MIN_LATENCY_MS = 20.0
        private const val MAX_LATENCY_MS = 5_000.0
        private const val MIN_WEIGHT = 0.05
        private const val MAX_WEIGHT = 3.0
        private const val JITTER_WEIGHT = 0.5
        private const val COOLDOWN_PENALTY = 0.1
        private const val CONSECUTIVE_FAILURE_PENALTY = 0.2
        private const val HEDGE_MISS_PENALTY = 1.5
    }
}

object ProviderHealthStore {
    private const val PREFS_NAME = "dns_vpn_prefs"
    private const val KEY_PROVIDER_HEALTH_JSON = "provider_health_json"
    private const val DEFAULT_LATENCY_MS = 250.0
    private val listeners = mutableSetOf<ProviderHealthStoreListener>()

    @Synchronized
    fun loadAll(context: Context): Map<String, ProviderHealthSnapshot> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val root = parseRoot(prefs.getString(KEY_PROVIDER_HEALTH_JSON, null))
        val result = mutableMapOf<String, ProviderHealthSnapshot>()
        val keys = root.keys()
        while (keys.hasNext()) {
            val providerId = keys.next()
            val obj = root.optJSONObject(providerId) ?: continue
            result[providerId] = ProviderHealthSnapshot(
                providerId = providerId,
                successes = obj.optInt("successes", 0),
                failures = obj.optInt("failures", 0),
                ewmaMs = obj.optDouble("ewmaMs", DEFAULT_LATENCY_MS),
                lastUpdatedAt = obj.optLong("lastUpdatedAt", 0L),
                jitterMs = obj.optDouble("jitterMs", 0.0),
                consecutiveFailures = obj.optInt("consecutiveFailures", 0),
                cooldownUntil = obj.optLong("cooldownUntil", 0L),
                decayedSuccesses = obj.optDouble("decayedSuccesses", obj.optInt("successes", 0).toDouble()),
                decayedFailures = obj.optDouble("decayedFailures", obj.optInt("failures", 0).toDouble()),
                hedgeMisses = obj.optInt("hedgeMisses", 0),
                decayedHedgeMisses = obj.optDouble("decayedHedgeMisses", obj.optInt("hedgeMisses", 0).toDouble())
            )
        }
        return result
    }

    @Synchronized
    fun saveAll(
        context: Context,
        snapshots: Map<String, ProviderHealthSnapshot>,
        commit: Boolean = false
    ): Boolean {
        val root = JSONObject()
        snapshots.forEach { (providerId, snapshot) ->
            root.put(
                providerId,
                JSONObject().apply {
                    put("successes", snapshot.successes)
                    put("failures", snapshot.failures)
                    put("ewmaMs", snapshot.ewmaMs)
                    put("jitterMs", snapshot.jitterMs)
                    put("consecutiveFailures", snapshot.consecutiveFailures)
                    put("cooldownUntil", snapshot.cooldownUntil)
                    put("decayedSuccesses", snapshot.decayedSuccesses)
                    put("decayedFailures", snapshot.decayedFailures)
                    put("hedgeMisses", snapshot.hedgeMisses)
                    put("decayedHedgeMisses", snapshot.decayedHedgeMisses)
                    put("lastUpdatedAt", snapshot.lastUpdatedAt)
                }
            )
        }
        val editor = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PROVIDER_HEALTH_JSON, root.toString())
        return if (commit) editor.commit() else {
            editor.apply()
            true
        }
    }

    fun normalizeWeightsToPercent(weights: List<Pair<String, Double>>): Map<String, Int> {
        val total = weights.sumOf { it.second }.takeIf { it > 0.0 } ?: return emptyMap()
        val shares = weights.map { (providerId, weight) ->
            val exact = weight / total * 100.0
            ProviderWeightShare(
                providerId = providerId,
                floor = exact.toInt(),
                remainder = exact - exact.toInt()
            )
        }
        val remaining = 100 - shares.sumOf { it.floor }
        val bonusIds = shares
            .sortedByDescending { it.remainder }
            .take(remaining.coerceAtLeast(0))
            .map { it.providerId }
            .toSet()
        return shares.associate { share ->
            share.providerId to (share.floor + if (share.providerId in bonusIds) 1 else 0)
        }
    }

    fun reset(context: Context, providerIds: Set<String>) {
        val notifyListeners = synchronized(this) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val root = parseRoot(prefs.getString(KEY_PROVIDER_HEALTH_JSON, null))
            providerIds.forEach { root.remove(it) }
            prefs.edit().putString(KEY_PROVIDER_HEALTH_JSON, root.toString()).apply()
            listeners.toList()
        }
        notifyListeners.forEach { it.onProviderHealthReset(providerIds) }
    }

    fun remove(context: Context, providerId: String) {
        val providerIds = setOf(providerId)
        val notifyListeners = synchronized(this) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val root = parseRoot(prefs.getString(KEY_PROVIDER_HEALTH_JSON, null))
            root.remove(providerId)
            prefs.edit().putString(KEY_PROVIDER_HEALTH_JSON, root.toString()).apply()
            listeners.toList()
        }
        notifyListeners.forEach { it.onProviderHealthReset(providerIds) }
    }

    @Synchronized
    fun registerListener(listener: ProviderHealthStoreListener) {
        listeners.add(listener)
    }

    @Synchronized
    fun unregisterListener(listener: ProviderHealthStoreListener) {
        listeners.remove(listener)
    }

    private fun parseRoot(json: String?): JSONObject {
        return try {
            if (json.isNullOrBlank()) JSONObject() else JSONObject(json)
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private data class ProviderWeightShare(
        val providerId: String,
        val floor: Int,
        val remainder: Double
    )

}

interface ProviderHealthStoreListener {
    fun onProviderHealthReset(providerIds: Set<String>)
}
