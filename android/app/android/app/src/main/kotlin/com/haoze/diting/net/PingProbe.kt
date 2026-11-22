package com.haoze.diting.net

import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

internal object PingProbe {

    const val DEFAULT_COUNT = 4
    const val DEFAULT_TIMEOUT_SECONDS = 3
    private const val MIN_COUNT = 1
    private const val MAX_COUNT = 20

    fun ping(target: String, count: Int, timeoutSeconds: Int): Map<String, Any?> {
        val host = NetHost.sanitize(target)
        if (host.isEmpty()) return failedSummary("", "请输入 Ping 目标")

        val clampedCount = count.coerceIn(MIN_COUNT, MAX_COUNT)
        val timeout = timeoutSeconds.coerceIn(1, MAX_TIMEOUT_SECONDS)

        val address = runCatching { InetAddress.getByName(host) }.getOrNull()
            ?: return failedSummary(host, "无法解析目标地址")
        val resolved = address.hostAddress
        val family = if (address is Inet6Address) "IPv6" else "IPv4"

        val output = runBinaryPing(address, clampedCount, timeout)
        if (output != null) {
            parseSummary(output, host, resolved, family)?.let { return it }
        }
        return reachableFallback(address, host, family, clampedCount)
    }

    private fun runBinaryPing(address: InetAddress, count: Int, timeoutSeconds: Int): String? {
        val host = address.hostAddress ?: return null
        val capMs = count * (timeoutSeconds + 2) * 1000L + 5_000L
        return if (address is Inet6Address) {
            ProcessProbe.runFirst(
                listOf(
                    listOf("ping6", "-c", "$count", "-W", "$timeoutSeconds", host),
                    listOf("ping", "-6", "-c", "$count", "-W", "$timeoutSeconds", host),
                ),
                capMs = capMs,
            )
        } else {
            ProcessProbe.run(
                listOf("ping", "-c", "$count", "-W", "$timeoutSeconds", host),
                capMs = capMs,
            )
        }
    }

    private fun parseSummary(
        output: String,
        target: String,
        resolved: String?,
        family: String,
    ): Map<String, Any?>? {
        val summary = ProbeNative.pingSummary(output) ?: return null
        return mapOf(
            "target" to target,
            "resolvedAddress" to resolved,
            "addressFamily" to family,
            "transmitted" to summary.transmitted,
            "received" to summary.received,
            "lossPercent" to summary.lossPercent,
            "minMs" to summary.minMs,
            "avgMs" to summary.avgMs,
            "maxMs" to summary.maxMs,
            "jitterMs" to summary.jitterMs,
            "replies" to summary.replies.map { reply ->
                mapOf(
                    "sequence" to reply.sequence,
                    "elapsedMs" to reply.elapsedMs,
                    "ttl" to reply.ttl,
                    "error" to if (reply.timeout) TIMEOUT_ERROR else null,
                )
            },
            "success" to (summary.received > 0),
            "message" to if (summary.received == 0) "未收到任何回复" else null,
            "measuredWithFallback" to false,
        )
    }

    private fun reachableFallback(
        address: InetAddress,
        target: String,
        family: String,
        count: Int,
    ): Map<String, Any?> {
        val replies = mutableListOf<Map<String, Any?>>()
        val samples = mutableListOf<Double>()
        val ports = intArrayOf(53, 443, 80)
        repeat(count) { index ->
            val start = System.nanoTime()
            val ok = runCatching { address.isReachable(REACHABLE_TIMEOUT_MS) }
                .getOrDefault(false) ||
                ports.any { port ->
                    runCatching {
                        Socket().use { socket ->
                            socket.connect(InetSocketAddress(address, port), TCP_TIMEOUT_MS)
                        }
                        true
                    }.getOrDefault(false)
                }
            val elapsed = (System.nanoTime() - start) / 1_000_000.0
            if (ok) {
                samples.add(elapsed)
                replies.add(
                    mapOf(
                        "sequence" to index + 1,
                        "elapsedMs" to elapsed,
                        "ttl" to null,
                        "error" to null,
                    ),
                )
            } else {
                replies.add(
                    mapOf(
                        "sequence" to index + 1,
                        "elapsedMs" to null,
                        "ttl" to null,
                        "error" to TIMEOUT_ERROR,
                    ),
                )
            }
            if (index != count - 1) runCatching { Thread.sleep(PROBE_GAP_MS) }
        }
        val stats = ProbeNative.latencyStats(samples)
        val received = samples.size
        return mapOf(
            "target" to target,
            "resolvedAddress" to address.hostAddress,
            "addressFamily" to family,
            "transmitted" to count,
            "received" to received,
            "lossPercent" to (count - received) * 100.0 / count,
            "minMs" to stats.minMs,
            "avgMs" to stats.avgMs,
            "maxMs" to stats.maxMs,
            "jitterMs" to stats.jitterMs,
            "replies" to replies,
            "success" to (received > 0),
            "message" to if (received > 0) {
                "系统 ICMP 受限，已用 TCP/Reachable 回退测量时延"
            } else {
                "目标超时或网络不可达"
            },
            "measuredWithFallback" to true,
        )
    }

    private fun failedSummary(target: String, message: String): Map<String, Any?> = mapOf(
        "target" to target,
        "resolvedAddress" to null,
        "addressFamily" to null,
        "transmitted" to 0,
        "received" to 0,
        "lossPercent" to 100.0,
        "minMs" to null,
        "avgMs" to null,
        "maxMs" to null,
        "jitterMs" to null,
        "replies" to emptyList<Map<String, Any?>>(),
        "success" to false,
        "message" to message,
        "measuredWithFallback" to false,
    )

    private const val TIMEOUT_ERROR = "超时或无响应"
    private const val MAX_TIMEOUT_SECONDS = 10
    private const val REACHABLE_TIMEOUT_MS = 1000
    private const val TCP_TIMEOUT_MS = 1000
    private const val PROBE_GAP_MS = 200L
}
