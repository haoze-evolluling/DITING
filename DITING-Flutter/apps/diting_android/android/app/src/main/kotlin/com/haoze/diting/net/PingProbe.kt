package com.haoze.diting.net

import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.math.abs

/// ICMP ping probe. Preferred path: the system `ping` / `ping6` binary, parsed for
/// per-reply latency, TTL and the summary block. Fallback when it is missing or unparsable:
/// `InetAddress.isReachable` plus a TCP handshake on 53/443/80, sets `measuredWithFallback`.
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
        // Reaching here means no system ping or unknown output shape: measure with the fallback.
        return reachableFallback(address, host, family, clampedCount)
    }

    private fun runBinaryPing(address: InetAddress, count: Int, timeoutSeconds: Int): String? {
        val host = address.hostAddress ?: return null
        return if (address is Inet6Address) {
            ProcessProbe.runFirst(
                listOf(
                    listOf("ping6", "-c", "$count", "-W", "$timeoutSeconds", host),
                    // Newer toybox/iputils merged IPv6 into `ping` itself.
                    listOf("ping", "-6", "-c", "$count", "-W", "$timeoutSeconds", host),
                ),
                capMs = count * (timeoutSeconds + 2) * 1000L + 5_000L,
            )
        } else {
            ProcessProbe.run(
                listOf("ping", "-c", "$count", "-W", "$timeoutSeconds", host),
                capMs = count * (timeoutSeconds + 2) * 1000L + 5_000L,
            )
        }
    }

    /// Null when there is no `N% packet loss` line, which tells the caller to use its fallback
    private fun parseSummary(
        output: String,
        target: String,
        resolved: String?,
        family: String,
    ): Map<String, Any?>? {
        val lossMatch = LOSS_REGEX.find(output) ?: return null
        val replies: List<Map<String, Any?>> = REPLY_REGEX.findAll(output).map { match ->
            buildMap<String, Any?> {
                put("sequence", match.groupValues[2].toIntOrNull())
                put("elapsedMs", match.groupValues[4].toDoubleOrNull())
                put("ttl", match.groupValues[3].toIntOrNull())
                // `fromAddress` is not in the Dart contract; it is reported as `resolvedAddress`
                put("error", null)
            }
        }.toList()

        val transmitted = TRANSMITTED_REGEX.find(output)?.groupValues?.get(1)?.toIntOrNull()
            ?: maxOf(replies.size, 1)
        val received = RECEIVED_REGEX.find(output)?.groupValues?.get(1)?.toIntOrNull()
            ?: replies.count { it["elapsedMs"] != null }
        val loss = lossMatch.groupValues[1].toDoubleOrNull()
            ?: if (transmitted > 0) (transmitted - received) * 100.0 / transmitted else 100.0
        val rtt = RTT_REGEX.find(output)?.groupValues

        // One row per sequence, so a lost packet stays a gap. iputils starts at 1, busybox at 0.
        val bySequence = replies.associateBy { (it["sequence"] as? Int) ?: -1 }
        val base = if (bySequence.containsKey(0)) 0 else 1
        val allReplies: List<Map<String, Any?>> = (base until base + transmitted).map { sequence ->
            bySequence[sequence] ?: buildMap<String, Any?> {
                put("sequence", sequence)
                put("elapsedMs", null)
                put("ttl", null)
                put("error", "超时或无响应")
            }
        }
        val samples = replies.mapNotNull { it["elapsedMs"] as? Double }

        return mapOf(
            "target" to target,
            "resolvedAddress" to resolved,
            "addressFamily" to family,
            "transmitted" to transmitted,
            "received" to received,
            "lossPercent" to loss,
            "minMs" to (rtt?.get(1)?.toDoubleOrNull() ?: samples.minOrNull()),
            "avgMs" to (rtt?.get(2)?.toDoubleOrNull()
                ?: samples.takeIf { it.isNotEmpty() }?.average()),
            "maxMs" to (rtt?.get(3)?.toDoubleOrNull() ?: samples.maxOrNull()),
            "jitterMs" to (rtt?.getOrNull(4)?.toDoubleOrNull() ?: jitterOf(samples)),
            "replies" to allReplies,
            "success" to (received > 0),
            "message" to if (received == 0) "未收到任何回复" else null,
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
        var received = 0
        val ports = intArrayOf(53, 443, 80)
        repeat(count) { index ->
            val start = System.nanoTime()
            var ok = runCatching { address.isReachable(REACHABLE_TIMEOUT_MS) }
                .getOrDefault(false)
            if (!ok) {
                for (port in ports) {
                    ok = runCatching {
                        Socket().use { socket ->
                            socket.connect(InetSocketAddress(address, port), TCP_TIMEOUT_MS)
                        }
                        true
                    }.getOrDefault(false)
                    if (ok) break
                }
            }
            val elapsed = (System.nanoTime() - start) / 1_000_000.0
            if (ok) {
                received++
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
                        "error" to "超时或无响应",
                    ),
                )
            }
            if (index != count - 1) runCatching { Thread.sleep(PROBE_GAP_MS) }
        }
        val samples = replies.mapNotNull { it["elapsedMs"] as Double? }
        return mapOf(
            "target" to target,
            "resolvedAddress" to address.hostAddress,
            "addressFamily" to family,
            "transmitted" to count,
            "received" to received,
            "lossPercent" to (count - received) * 100.0 / count,
            "minMs" to samples.minOrNull(),
            "avgMs" to samples.takeIf { it.isNotEmpty() }?.average(),
            "maxMs" to samples.maxOrNull(),
            "jitterMs" to jitterOf(samples),
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

    private fun jitterOf(samples: List<Double>): Double? {
        if (samples.size < 2) return null
        val mean = samples.average()
        return samples.map { abs(it - mean) }.average()
    }

    private const val MAX_TIMEOUT_SECONDS = 10
    private const val REACHABLE_TIMEOUT_MS = 1000
    private const val TCP_TIMEOUT_MS = 1000
    private const val PROBE_GAP_MS = 200L

    /// `ttl` is optional (`ping6` omits it); lines without `from` and `time=` cannot match
    private val REPLY_REGEX = Regex(
        "from\\s+(\\S+):\\s+(?:icmp_seq|seq)=(\\d+)(?:.*?ttl=(\\d+))?.*?time=([0-9.]+)\\s*ms",
    )
    private val LOSS_REGEX = Regex("([0-9.]+)% packet loss")
    private val TRANSMITTED_REGEX = Regex("(\\d+) packets? transmitted")
    private val RECEIVED_REGEX = Regex("(\\d+) (?:packets? )?received")
    private val RTT_REGEX = Regex("=\\s*([0-9.]+)/([0-9.]+)/([0-9.]+)(?:/([0-9.]+))?\\s*ms")
}
