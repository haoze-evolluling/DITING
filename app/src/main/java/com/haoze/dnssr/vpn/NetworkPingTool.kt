package com.haoze.dnssr.vpn

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * ICMP ping tester (network diagnostics).
 *
 * Prefers the system ping / ping6 binary for standard ICMP measurements
 * (latency, packet loss, TTL), and falls back to an approximation based on
 * InetAddress.isReachable when the system binary is unavailable. Like
 * DnsLatencyTester, the app's own traffic is excluded from the VPN, so
 * probes go directly over the physical network.
 */
object NetworkPingTool {

    data class Reply(
        val sequence: Int,
        val elapsedMs: Double?,
        val ttl: Int?,
        val fromAddress: String?,
        val error: String? = null
    )

    data class Summary(
        val target: String,
        val resolvedAddress: String?,
        val addressFamily: String?,
        val transmitted: Int,
        val received: Int,
        val lossPercent: Double,
        val minMs: Double?,
        val avgMs: Double?,
        val maxMs: Double?,
        val jitterMs: Double?,
        val replies: List<Reply>,
        val success: Boolean,
        val message: String?,
        val measuredWithFallback: Boolean = false
    )

    suspend fun ping(target: String, count: Int = DEFAULT_COUNT, timeoutSeconds: Int = PING_TIMEOUT_SECONDS): Summary {
        val sanitized = sanitizeHost(target)
        if (sanitized.isEmpty()) {
            return failedSummary("", null, "请输入 Ping 目标")
        }
        return withContext(Dispatchers.IO) {
            try {
                withTimeout((count * (timeoutSeconds + 3) + 15) * 1000L) {
                    runPing(sanitized, count.coerceIn(1, 20), timeoutSeconds)
                }
            } catch (_: TimeoutCancellationException) {
                failedSummary(sanitized, null, "Ping 执行超时")
            }
        }
    }

    private fun runPing(target: String, count: Int, timeoutSeconds: Int): Summary {
        val address = runCatching { InetAddress.getByName(target) }.getOrNull()
            ?: return failedSummary(target, null, "无法解析目标地址")
        val resolved = address.hostAddress
        val family = if (address is Inet6Address) "IPv6" else "IPv4"

        val output = runCatching { execPing(address, count, timeoutSeconds) }.getOrNull()
        val parsed = output?.let { parseSummary(output, target, resolved, family) }
        return parsed ?: reachableFallback(address, target, family, count)
    }

    private fun execPing(address: InetAddress, count: Int, timeoutSeconds: Int): String? {
        val host = address.hostAddress ?: return null
        val binary = if (address is Inet6Address) "ping6" else "ping"
        val deadlineSeconds = count * (timeoutSeconds + 2)
        val command = arrayOf(
            binary, "-c", count.toString(),
            "-W", timeoutSeconds.toString(),
            "-w", deadlineSeconds.toString(),
            host
        )
        val process = ProcessBuilder(*command)
            .redirectErrorStream(true)
            .start()
        return try {
            val output = StringBuilder()
            process.inputStream.bufferedReader().use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    output.appendLine(line)
                }
            }
            val finished = process.waitFor(3, TimeUnit.SECONDS)
            if (!finished) process.destroyForcibly()
            output.toString()
        } finally {
            process.destroy()
        }
    }

    private fun parseSummary(output: String, target: String, resolved: String?, family: String): Summary? {
        val replies = REPLY_REGEX.findAll(output).map { match ->
            Reply(
                sequence = match.groupValues[2].toInt(),
                elapsedMs = match.groupValues[4].toDoubleOrNull(),
                ttl = match.groupValues[3].toIntOrNull(),
                fromAddress = match.groupValues[1].takeIf { it.isNotEmpty() } ?: resolved
            )
        }.toList()

        val lossMatch = LOSS_REGEX.find(output) ?: return null
        val transmitted = TRANSMITTED_REGEX.find(output)?.groupValues?.get(1)?.toIntOrNull()
            ?: maxOf(replies.size, 1)
        val received = RECEIVED_REGEX.find(output)?.groupValues?.get(1)?.toIntOrNull()
            ?: replies.count { it.elapsedMs != null }
        val loss = lossMatch.groupValues[1].toDoubleOrNull()
            ?: (transmitted - received) * 100.0 / transmitted
        val rtt = RTT_REGEX.find(output)?.groupValues

        val replyMap = replies.associateBy { it.sequence }
        val allReplies = (1..transmitted).map { sequence ->
            replyMap[sequence] ?: Reply(sequence, null, null, resolved, "超时或无响应")
        }
        val samples = replies.mapNotNull { it.elapsedMs }

        return Summary(
            target = target,
            resolvedAddress = resolved,
            addressFamily = family,
            transmitted = transmitted,
            received = received,
            lossPercent = loss,
            minMs = rtt?.get(1)?.toDoubleOrNull() ?: samples.minOrNull(),
            avgMs = rtt?.get(2)?.toDoubleOrNull() ?: samples.takeIf { it.isNotEmpty() }?.average(),
            maxMs = rtt?.get(3)?.toDoubleOrNull() ?: samples.maxOrNull(),
            jitterMs = rtt?.getOrNull(4)?.toDoubleOrNull() ?: jitterOf(samples),
            replies = allReplies,
            success = received > 0,
            message = if (received == 0) "未收到任何回复" else null
        )
    }

    /** Fallback measurement: prefers InetAddress.isReachable, then tries common network ports (DNS 53, HTTPS 443, HTTP 80) with TCP handshake latency. */
    private fun reachableFallback(address: InetAddress, target: String, family: String, count: Int): Summary {
        val replies = mutableListOf<Reply>()
        var received = 0
        val portsToTry = intArrayOf(53, 443, 80)
        repeat(count) { index ->
            val start = System.nanoTime()
            var ok = runCatching { address.isReachable(1000) }.getOrDefault(false)
            if (!ok) {
                for (port in portsToTry) {
                    ok = runCatching {
                        java.net.Socket().use { socket ->
                            socket.connect(java.net.InetSocketAddress(address, port), 1000)
                            true
                        }
                    }.getOrDefault(false)
                    if (ok) break
                }
            }
            val elapsed = (System.nanoTime() - start) / 1_000_000.0
            if (ok) {
                received++
                replies.add(Reply(index + 1, elapsed, null, address.hostAddress))
            } else {
                replies.add(Reply(index + 1, null, null, address.hostAddress, "超时或无响应"))
            }
            if (index != count - 1) runCatching { Thread.sleep(200) }
        }
        val samples = replies.mapNotNull { it.elapsedMs }
        return Summary(
            target = target,
            resolvedAddress = address.hostAddress,
            addressFamily = family,
            transmitted = count,
            received = received,
            lossPercent = (count - received) * 100.0 / count,
            minMs = samples.minOrNull(),
            avgMs = samples.takeIf { it.isNotEmpty() }?.average(),
            maxMs = samples.maxOrNull(),
            jitterMs = jitterOf(samples),
            replies = replies,
            success = received > 0,
            message = if (received > 0) "系统 ICMP 受阻，已用 TCP/Reachable 回退测量时延" else "目标超时或网络不可达",
            measuredWithFallback = true
        )
    }

    private fun jitterOf(samples: List<Double>): Double? {
        if (samples.size < 2) return null
        val mean = samples.average()
        return samples.map { abs(it - mean) }.average()
    }

    private fun failedSummary(target: String, resolved: String?, message: String) = Summary(
        target = target,
        resolvedAddress = resolved,
        addressFamily = null,
        transmitted = 0,
        received = 0,
        lossPercent = 100.0,
        minMs = null,
        avgMs = null,
        maxMs = null,
        jitterMs = null,
        replies = emptyList(),
        success = false,
        message = message
    )

    /** Strips protocol prefixes, paths, user info, and ports from pasted input, leaving a bare hostname or IP. */
    internal fun sanitizeHost(input: String): String {
        var value = input.trim()
        if (value.isEmpty()) return value
        val schemeIndex = value.indexOf("://")
        if (schemeIndex >= 0) value = value.substring(schemeIndex + 3)
        val cutIndex = value.indexOfAny(charArrayOf('/', '?', '#'))
        if (cutIndex >= 0) value = value.substring(0, cutIndex)
        val atIndex = value.lastIndexOf('@')
        if (atIndex >= 0) value = value.substring(atIndex + 1)
        if (value.startsWith("[")) {
            val endIndex = value.indexOf(']')
            if (endIndex > 0) value = value.substring(1, endIndex)
            return value
        }
        if (!value.contains("::") && value.count { it == ':' } == 1) {
            val afterColon = value.substringAfter(':')
            if (afterColon.isNotEmpty() && afterColon.all { it.isDigit() }) {
                value = value.substringBefore(':')
            }
        }
        return value
    }

    // Matches "64 bytes from 1.2.3.4: icmp_seq=1 ttl=57 time=12.3 ms"
    // (busybox uses seq=, and the address may be IPv6)
    private val REPLY_REGEX = Regex("from\\s+(\\S+):\\s+(?:icmp_seq|seq)=(\\d+).*?ttl=(\\d+).*?time=([0-9.]+)\\s*ms")
    private val LOSS_REGEX = Regex("([0-9.]+)% packet loss")
    private val TRANSMITTED_REGEX = Regex("(\\d+) packets? transmitted")
    private val RECEIVED_REGEX = Regex("(\\d+) (?:packets? )?received")
    private val RTT_REGEX = Regex("=\\s*([0-9.]+)/([0-9.]+)/([0-9.]+)(?:/([0-9.]+))?\\s*ms")

    private const val DEFAULT_COUNT = 4
    private const val PING_TIMEOUT_SECONDS = 3
}
