package com.haoze.diting.log

import org.json.JSONObject
import java.util.concurrent.atomic.AtomicLong

/// Request counts for the notification, since the running service started. Kept in memory and
/// fed from the engine callbacks, so the notification never queries the log database and the
/// numbers do not depend on the log mode. The three data planes are mutually exclusive, hence one
/// process-wide set reset on every start.
///
/// Buckets follow the log dashboard: rewritten answers also count as passed, cached counts only
/// passed answers, and bypassed HTTPS flows count toward the total only.
object RequestStats {
    private val total = AtomicLong()
    private val passed = AtomicLong()
    private val filtered = AtomicLong()
    private val cached = AtomicLong()
    private val rewritten = AtomicLong()
    private val failed = AtomicLong()

    data class Snapshot(
        val total: Long,
        val passed: Long,
        val filtered: Long,
        val cached: Long,
        val rewritten: Long,
        val failed: Long,
    )

    fun reset() {
        for (counter in listOf(total, passed, filtered, cached, rewritten, failed)) counter.set(0)
    }

    fun snapshot() = Snapshot(
        total = total.get(),
        passed = passed.get(),
        filtered = filtered.get(),
        cached = cached.get(),
        rewritten = rewritten.get(),
        failed = failed.get(),
    )

    /// One entry of the engine's batch DNS log. Connection and firewall lines are flows, not
    /// queries, so they stay out like they do on the dashboard's request overview.
    fun onDns(obj: JSONObject) {
        if (obj.optString("d").isBlank()) return
        val blockedBy = obj.optString("k")
        if (obj.optInt("t") == 0 || blockedBy == "connection" || blockedBy.startsWith("firewall:")) {
            return
        }
        total.incrementAndGet()
        when {
            obj.optString("e").isNotBlank() -> failed.incrementAndGet()
            blockedBy.startsWith("rewrite=") -> {
                rewritten.incrementAndGet()
                passed.incrementAndGet()
            }
            obj.optBoolean("b") -> filtered.incrementAndGet()
            else -> {
                passed.incrementAndGet()
                if (obj.optBoolean("c")) cached.incrementAndGet()
            }
        }
    }

    /// HTTPS outcome, mapped like `httpRowStatusOf` on the Dart side.
    fun onHttp(outcome: String) {
        total.incrementAndGet()
        when (outcome) {
            "allowed" -> passed.incrementAndGet()
            "rewritten" -> {
                rewritten.incrementAndGet()
                passed.incrementAndGet()
            }
            "blocked", "invalid" -> filtered.incrementAndGet()
            "passthrough", "bypassed", "unsupported_protocol", "resource_bypass" -> Unit
            else -> failed.incrementAndGet()
        }
    }
}
