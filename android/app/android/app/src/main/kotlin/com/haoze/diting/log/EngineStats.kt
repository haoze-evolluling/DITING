package com.haoze.diting.log

import com.haoze.diting.engine.TunnelEngine
import java.nio.ByteBuffer
import java.nio.ByteOrder

/// Reads the engine's counters in the shape the Dart layer expects; both engines answer.
///
/// The engine packs six big-endian `u64`s (`statsSnapshot`), so a poll is one JNI crossing and no
/// JSON document: the status channel used to build and parse two separate JSON objects here every
/// few seconds for the whole life of the tunnel.
object EngineStats {
    private const val FIELDS = 6

    fun snapshot(engine: TunnelEngine?): Map<String, Any?> {
        val source = engine ?: return emptyMap()
        return runCatching {
            val buffer = ByteBuffer.wrap(source.statsSnapshot()).order(ByteOrder.BIG_ENDIAN)
            val values = LongArray(FIELDS) {
                if (buffer.remaining() < Long.SIZE_BYTES) 0L else buffer.long
            }
            val hits = values[3]
            val misses = values[4]
            val lookups = hits + misses
            mapOf(
                "queries" to values[0],
                "blocked" to values[1],
                "droppedLogs" to values[2],
                "cacheHits" to hits,
                "cacheMisses" to misses,
                "cacheEntries" to values[5].toInt(),
                "cacheHitRatio" to if (lookups > 0) hits.toDouble() / lookups else 0.0,
            )
        }.getOrDefault(emptyMap())
    }
}
