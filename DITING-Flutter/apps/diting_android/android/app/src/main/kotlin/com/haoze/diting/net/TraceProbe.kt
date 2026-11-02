package com.haoze.diting.net

import java.net.Inet6Address
import java.net.InetAddress

/// Hop-by-hop traceroute via `ping`'s TTL flag: no root, no `traceroute` binary
internal object TraceProbe {

    const val DEFAULT_MAX_HOPS = 30
    private const val MIN_HOPS = 1
    private const val MAX_HOPS = 30
    private const val PROBE_TIMEOUT_SECONDS = 2

    fun trace(target: String, maxHops: Int): Map<String, Any?> {
        val host = NetHost.sanitize(target)
        if (host.isEmpty()) return failed("", maxHops, "请输入追踪目标")
        val limit = maxHops.coerceIn(MIN_HOPS, MAX_HOPS)

        val address = runCatching { InetAddress.getByName(host) }.getOrNull()
            ?: return failed(host, limit, "无法解析目标地址")
        val resolved = address.hostAddress
        val hops = mutableListOf<Map<String, Any?>>()

        for (ttl in 1..limit) {
            val probe = execProbe(address, ttl)
                ?: return result(host, resolved, hops, false, "无法执行系统 Ping，无法进行路由追踪")

            if (probe.text.contains("Usage:") || probe.text.contains("invalid option")) {
                return result(
                    host,
                    resolved,
                    hops,
                    false,
                    "系统 Ping 不支持 TTL 探测，无法进行路由追踪",
                )
            }

            val reply = REPLY_REGEX.find(probe.text)
            val from = FROM_REGEX.find(probe.text)
            when {
                reply != null -> {
                    hops.add(
                        hop(
                            index = ttl,
                            address = reply.groupValues[1].takeIf { it.isNotEmpty() } ?: resolved,
                            elapsedMs = reply.groupValues[2].toDoubleOrNull(),
                            reachedTarget = true,
                        ),
                    )
                    return result(host, resolved, hops, true, "到达目标，共 ${hops.size} 跳")
                }
                from != null -> {
                    val unreachable = from.groupValues[2].contains("unreach", ignoreCase = true)
                    hops.add(
                        hop(
                            index = ttl,
                            address = from.groupValues[1],
                            elapsedMs = probe.firstResponseMs,
                            reachedTarget = false,
                        ),
                    )
                    if (unreachable) {
                        return result(host, resolved, hops, false, "目标在第 $ttl 跳不可达")
                    }
                }
                probe.text.contains("unreach", ignoreCase = true) -> {
                    return result(host, resolved, hops, false, "网络不可达，无法发送探测")
                }
                else -> hops.add(hop(ttl, null, null, false))
            }
        }
        return result(host, resolved, hops, false, "经 $limit 跳仍未到达目标")
    }

    private class ProbeOutput(val text: String, val firstResponseMs: Double?)

    private fun execProbe(address: InetAddress, ttl: Int): ProbeOutput? {
        val host = address.hostAddress ?: return null
        val candidates = if (address is Inet6Address) {
            listOf(
                listOf("ping6", "-c", "1", "-W", "$PROBE_TIMEOUT_SECONDS", "-t", "$ttl", host),
                listOf("ping", "-6", "-c", "1", "-W", "$PROBE_TIMEOUT_SECONDS", "-t", "$ttl", host),
            )
        } else {
            listOf(
                listOf("ping", "-c", "1", "-W", "$PROBE_TIMEOUT_SECONDS", "-t", "$ttl", host),
            )
        }
        // The first-response stamp needs the streaming output, so ProcessProbe.run is not reused.
        for (command in candidates) {
            val output = streamingProbe(command) ?: continue
            return output
        }
        return null
    }

    private fun streamingProbe(command: List<String>): ProbeOutput? {
        val process = try {
            ProcessBuilder(command).redirectErrorStream(true).start()
        } catch (_: Exception) {
            return null
        }
        val text = StringBuilder()
        val startNs = System.nanoTime()
        var responseNs: Long? = null
        try {
            process.inputStream.bufferedReader().use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    if (responseNs == null &&
                        (line.contains("time=") || line.startsWith("From "))
                    ) {
                        responseNs = System.nanoTime()
                    }
                    synchronized(text) { text.appendLine(line) }
                }
            }
            ProcessSupport.waitOrKill(process, SELF_CAP_MS)
        } catch (_: Exception) {
            // A mid-read crash still leaves usable output on some devices; let the parser decide.
        } finally {
            runCatching { process.destroy() }
        }
        return ProbeOutput(
            text = synchronized(text) { text.toString() },
            firstResponseMs = responseNs?.let { (it - startNs) / 1_000_000.0 },
        )
    }

    private fun hop(
        index: Int,
        address: String?,
        elapsedMs: Double?,
        reachedTarget: Boolean,
    ): Map<String, Any?> = mapOf(
        "hop" to index,
        "address" to address,
        "elapsedMs" to elapsedMs,
        "reachedTarget" to reachedTarget,
    )

    private fun failed(target: String, maxHops: Int, message: String): Map<String, Any?> =
        result(target, null, emptyList(), false, message)

    private fun result(
        target: String,
        resolved: String?,
        hops: List<Map<String, Any?>>,
        success: Boolean,
        message: String,
    ): Map<String, Any?> = mapOf(
        "target" to target,
        "resolvedAddress" to resolved,
        "hops" to hops,
        "success" to success,
        "message" to message,
        // Always false: a MethodChannel call has no cancel path, but `fromMap` reads the key.
        "cancelled" to false,
    )

    // Matches "64 bytes from 1.2.3.4: icmp_seq=1 ttl=57 time=12.3 ms".
    private val REPLY_REGEX = Regex("from\\s+(\\S+):\\s+(?:icmp_seq|seq)=\\d+.*?time=([0-9.]+)\\s*ms")

    // IPv4 "From 1.2.3.4: icmp_seq=1 Time to live exceeded", IPv6 "... Time exceeded: Hop limit".
    private val FROM_REGEX = Regex("From\\s+(.+?)\\s*:??\\s*icmp_seq=\\d+\\s+(.*)")

    /// Hard cap per hop: `-W` covers the reply wait, the rest spawn plus a slow readLine
    private const val SELF_CAP_MS = (PROBE_TIMEOUT_SECONDS + 3) * 1000L
}
