package com.haoze.diting.net

import java.net.Inet6Address
import java.net.InetAddress

/// Hop-by-hop traceroute via `ping`'s TTL flag: no root, no `traceroute` binary.
///
/// One hop is one process run; the command, the streaming reader and the first-response stamp stay
/// here, while the pattern work (which hop answered, was it unreachable, does this `ping` even
/// support `-t`) lives in `rust/diting-probe-core` (`trace.rs`) behind [ProbeNative].
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

            when (val step = ProbeNative.traceHop(resolved ?: "", probe.text)) {
                ProbeHop.Unsupported -> return result(
                    host,
                    resolved,
                    hops,
                    false,
                    "系统 Ping 不支持 TTL 探测，无法进行路由追踪",
                )
                is ProbeHop.Reached -> {
                    hops.add(
                        hop(
                            index = ttl,
                            address = step.address,
                            elapsedMs = step.elapsedMs,
                            reachedTarget = true,
                        ),
                    )
                    return result(host, resolved, hops, true, "到达目标，共 ${hops.size} 跳")
                }
                is ProbeHop.Answered -> {
                    hops.add(
                        hop(
                            index = ttl,
                            address = step.address,
                            elapsedMs = probe.firstResponseMs,
                            reachedTarget = false,
                        ),
                    )
                    if (step.unreachable) {
                        return result(host, resolved, hops, false, "目标在第 $ttl 跳不可达")
                    }
                }
                ProbeHop.NetUnreachable -> {
                    return result(host, resolved, hops, false, "网络不可达，无法发送探测")
                }
                ProbeHop.NoMatch -> hops.add(hop(ttl, null, null, false))
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
                    if (responseNs == null && ProbeNative.isResponseLine(line)) {
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

    /// Hard cap per hop: `-W` covers the reply wait, the rest spawn plus a slow readLine
    private const val SELF_CAP_MS = (PROBE_TIMEOUT_SECONDS + 3) * 1000L
}
