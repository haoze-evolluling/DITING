package com.haoze.diting.log

import com.haoze.diting.engine.TunnelEngine
import org.json.JSONObject

/// Reads the engine's counters in the shape the Dart layer expects; both engines answer
object EngineStats {
    fun snapshot(engine: TunnelEngine?): Map<String, Any?> {
        if (engine == null) return emptyMap()
        return runCatching {
            val stats = JSONObject(engine.getStats())
            val cache = JSONObject(engine.getDNSCacheStats())
            mapOf(
                "queries" to stats.optLong("total"),
                "blocked" to stats.optLong("blocked"),
                "droppedLogs" to stats.optLong("dropped_logs"),
                "cacheHits" to cache.optLong("totalHits"),
                "cacheMisses" to cache.optLong("totalMisses"),
                "cacheEntries" to cache.optInt("entryCount"),
                "cacheHitRatio" to cache.optDouble("hitRatio", 0.0),
            )
        }.getOrDefault(emptyMap())
    }
}
