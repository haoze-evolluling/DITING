package com.haoze.dnssr.vpn

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.TimeUnit

/**
 * 路由追踪工具（网络诊断）。
 *
 * 通过系统 ping / ping6 的 -t TTL 参数逐跳递增探测，利用中间路由返回的
 * "Time to live exceeded" 应答发现路径上的每一跳，记录其地址与响应时延，
 * 无需 root 或独立的 traceroute 二进制。
 * 与 DnsLatencyTester 一致，应用自身流量已被 VPN 排除，探测直接走物理网络。
 */
object NetworkTraceRouteTool {

    data class Hop(
        val index: Int,
        val address: String?,
        val elapsedMs: Double?,
        val isDestination: Boolean,
        val responded: Boolean,
        val error: String? = null
    )

    data class Progress(
        val target: String,
        val resolvedAddress: String?,
        val addressFamily: String?,
        val maxHops: Int,
        val hops: List<Hop>,
        val complete: Boolean,
        val success: Boolean,
        val message: String? = null
    )

    suspend fun trace(
        target: String,
        maxHops: Int = DEFAULT_MAX_HOPS,
        timeoutSeconds: Int = PROBE_TIMEOUT_SECONDS,
        onHop: suspend (Hop) -> Unit = {}
    ): Progress {
        val sanitized = NetworkPingTool.sanitizeHost(target)
        if (sanitized.isEmpty()) {
            return failed("", null, maxHops, "请输入追踪目标")
        }
        return withContext(Dispatchers.IO) {
            try {
                withTimeout((maxHops.coerceIn(1, MAX_HOPS_LIMIT) * (timeoutSeconds + 2) + 15) * 1000L) {
                    runTrace(sanitized, maxHops.coerceIn(1, MAX_HOPS_LIMIT), timeoutSeconds, onHop)
                }
            } catch (_: TimeoutCancellationException) {
                failed(sanitized, null, maxHops, "追踪执行超时")
            }
        }
    }

    private suspend fun runTrace(
        target: String,
        maxHops: Int,
        timeoutSeconds: Int,
        onHop: suspend (Hop) -> Unit
    ): Progress {
        val address = runCatching { InetAddress.getByName(target) }.getOrNull()
            ?: return failed(target, null, maxHops, "无法解析目标地址")
        val resolved = address.hostAddress
        val family = if (address is Inet6Address) "IPv6" else "IPv4"

        val hops = mutableListOf<Hop>()
        val failure = tracePath(address, resolved, maxHops, timeoutSeconds, hops, onHop)
        return Progress(
            target = target,
            resolvedAddress = resolved,
            addressFamily = family,
            maxHops = maxHops,
            hops = hops.toList(),
            complete = true,
            success = failure == null,
            message = failure ?: "到达目标，共 ${hops.size} 跳"
        )
    }

    /** 逐跳探测；返回 null 表示已到达目标，否则返回失败原因并追加已完成的跳。 */
    private suspend fun tracePath(
        address: InetAddress,
        resolved: String?,
        maxHops: Int,
        timeoutSeconds: Int,
        hops: MutableList<Hop>,
        onHop: suspend (Hop) -> Unit
    ): String? {
        for (ttl in 1..maxHops) {
            val probe = execProbe(address, ttl, timeoutSeconds)
                ?: return "无法执行系统 Ping，无法进行路由追踪"
            if (probe.text.contains("Usage:") || probe.text.contains("invalid option")) {
                return "系统 Ping 不支持 TTL 探测，无法进行路由追踪"
            }

            val reply = REPLY_REGEX.find(probe.text)
            val exceeded = FROM_REGEX.find(probe.text)
            when {
                reply != null -> {
                    val hop = Hop(
                        index = ttl,
                        address = reply.groupValues[1].takeIf { it.isNotEmpty() } ?: resolved,
                        elapsedMs = reply.groupValues[2].toDoubleOrNull(),
                        isDestination = true,
                        responded = true
                    )
                    hops.add(hop)
                    onHop(hop)
                    return null
                }
                exceeded != null -> {
                    val unreachable = exceeded.groupValues[2].contains("unreach", ignoreCase = true)
                    val hop = Hop(
                        index = ttl,
                        address = exceeded.groupValues[1],
                        elapsedMs = probe.firstResponseMs,
                        isDestination = false,
                        responded = true,
                        error = if (unreachable) "目标不可达" else null
                    )
                    hops.add(hop)
                    onHop(hop)
                    if (unreachable) return "目标在第 $ttl 跳不可达"
                }
                probe.text.contains("unreach", ignoreCase = true) -> {
                    return "网络不可达，无法发送探测"
                }
                else -> {
                    val hop = Hop(ttl, null, null, isDestination = false, responded = false, error = "超时或无响应")
                    hops.add(hop)
                    onHop(hop)
                }
            }
        }
        return "经 $maxHops 跳仍未到达目标"
    }


    private class ProbeOutput(
        val text: String,
        val firstResponseMs: Double?
    )

    private fun execProbe(address: InetAddress, ttl: Int, timeoutSeconds: Int): ProbeOutput? {
        val host = address.hostAddress ?: return null
        val binary = if (address is Inet6Address) "ping6" else "ping"
        val command = arrayOf(
            binary, "-c", "1",
            "-W", timeoutSeconds.toString(),
            "-t", ttl.toString(),
            host
        )
        return try {
            val process = ProcessBuilder(*command)
                .redirectErrorStream(true)
                .start()
            try {
                val output = StringBuilder()
                val startNs = System.nanoTime()
                var responseNs: Long? = null
                process.inputStream.bufferedReader().use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        if (responseNs == null &&
                            (line.contains("time=") || line.startsWith("From "))
                        ) {
                            responseNs = System.nanoTime()
                        }
                        output.appendLine(line)
                    }
                }
                val finished = process.waitFor(3, TimeUnit.SECONDS)
                if (!finished) process.destroyForcibly()
                ProbeOutput(
                    text = output.toString(),
                    firstResponseMs = responseNs?.let { (it - startNs) / 1_000_000.0 }
                )
            } finally {
                process.destroy()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun failed(target: String, resolved: String?, maxHops: Int, message: String) = Progress(
        target = target,
        resolvedAddress = resolved,
        addressFamily = null,
        maxHops = maxHops,
        hops = emptyList(),
        complete = true,
        success = false,
        message = message
    )

    // 形如 "64 bytes from 1.2.3.4: icmp_seq=1 ttl=57 time=12.3 ms"（地址可能是 IPv6）
    private val REPLY_REGEX = Regex("from\\s+(\\S+):\\s+(?:icmp_seq|seq)=\\d+.*?time=([0-9.]+)\\s*ms")

    // 形如 "From 1.2.3.4: icmp_seq=1 Time to live exceeded"（IPv4，冒号分隔）
    // 或   "From 2001:db8::1 icmp_seq=1 Time exceeded: Hop limit"（IPv6，无冒号）
    private val FROM_REGEX = Regex("From\\s+(.+?)\\s*:??\\s*icmp_seq=\\d+\\s+(.*)")

    private const val DEFAULT_MAX_HOPS = 15
    private const val MAX_HOPS_LIMIT = 30
    private const val PROBE_TIMEOUT_SECONDS = 2
}
