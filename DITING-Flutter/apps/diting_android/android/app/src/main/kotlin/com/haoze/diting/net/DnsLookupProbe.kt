package com.haoze.diting.net

import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

/// One manual lookup in the shape `DnsLookupResult.fromMap` reads: tunnel or system resolver.
internal object DnsLookupProbe {

    fun lookup(domain: String, viaTunnel: Boolean, ipv4: Boolean): Map<String, Any?> {
        val host = NetHost.sanitize(domain)
        // `domain` names what was actually looked up, so the empty case reports "".
        if (host.isEmpty()) return error("", "请输入要查询的域名")
        return if (viaTunnel) tunnelLookup(host, ipv4) else systemLookup(host, ipv4)
    }

    /// UDP query to a user-specified resolver, same shape as `lookup`; server is an IP
    fun customServerLookup(domain: String, server: String, ipv4: Boolean): Map<String, Any?> {
        val host = NetHost.sanitize(domain)
        if (host.isEmpty()) return error("", "请输入要查询的域名")
        if (!isIpLiteral(server)) {
            return error(host, "自定义 DNS 服务器须为有效 IP 地址")
        }
        val probe = runCatching { DnsServerProbe.lookup(host, server, ipv4) }
            .getOrElse { failure ->
                return error(host, failure.message ?: "向 $server 查询失败")
            }
        if (probe.records.isEmpty()) {
            val type = if (ipv4) "A" else "AAAA"
            return error(host, "$server 未返回 $type 记录", probe.elapsedMs)
        }
        return result(
            host,
            "upstream",
            probe.records.map { mapOf("type" to it.type, "value" to it.value, "ttl" to it.ttl) },
            probe.elapsedMs,
            null,
        )
    }

    /// Hand-rolled: `getByName` also resolves hostnames, so "dns.google" would pass it
    private fun isIpLiteral(value: String): Boolean {
        val text = value.removePrefix("[").removeSuffix("]")
        if (text.isEmpty()) return false
        val parts = text.split(".")
        if (parts.size == 4 && !text.contains(":")) {
            return parts.all { part ->
                part.isNotEmpty() && part.length <= 3 && part.all { it.isDigit() } &&
                    (part.toIntOrNull() ?: return false) in 0..255
            }
        }
        // IPv6: a colon is mandatory, at least two of them, hex digits only.
        if (!text.contains(":")) return false
        if (text.count { it == ':' } < 2) return false
        return text.all {
            it.isDigit() || it in 'a'..'f' || it in 'A'..'F' || it == ':' || it == '.'
        }
    }

    private fun tunnelLookup(host: String, ipv4: Boolean): Map<String, Any?> {
        val engine = EngineAccess.current()
            ?: return error(host, "隧道未运行，无法经内核解析（可用系统解析）")

        val startedAt = System.nanoTime()
        val raw = runCatching { engine.resolveDomain(host, ipv4) }.getOrNull()
        val elapsed = (System.nanoTime() - startedAt) / 1_000_000.0
        if (raw.isNullOrBlank()) return error(host, "隧道解析未返回结果", elapsed)

        val json = runCatching { JSONObject(raw) }.getOrNull()
            ?: return error(host, "隧道解析结果无效", elapsed)

        // Error object wins: with no upstream yet the engine returns a bare error object.
        json.optString("error").takeIf { it.isNotEmpty() }?.let { message ->
            return error(host, translateEngineError(message), elapsed)
        }

        val source = json.optString("source")
        val answers = answersOf(json.optJSONArray("ips"), json.optJSONArray("ttls"), ipv4)
        val reason = json.optString("reason").takeIf { it.isNotEmpty() }

        return when (source) {
            "rewrite", "upstream", "blocked" -> result(host, source, answers, elapsed, null)
            // `nodata`: no address record; the Dart model has no label for it, so report the rcode.
            else -> error(host, noDataMessage(reason), elapsed)
        }
    }

    private fun systemLookup(host: String, ipv4: Boolean): Map<String, Any?> {
        val startedAt = System.nanoTime()
        val addresses = runCatching { InetAddress.getAllByName(host) }.getOrNull()
            ?: return error(
                host,
                "系统解析失败，请检查网络或域名",
                (System.nanoTime() - startedAt) / 1_000_000.0,
            )
        val elapsed = (System.nanoTime() - startedAt) / 1_000_000.0
        val answers = addresses.mapNotNull { address ->
            when {
                ipv4 && address is Inet4Address -> answer("A", address.hostAddress ?: "")
                !ipv4 && address is Inet6Address -> answer("AAAA", address.hostAddress ?: "")
                else -> null
            }
        }
        if (answers.isEmpty()) return error(host, "系统解析未返回对应记录", elapsed)
        // The OS resolver did reach one (possibly the tunnel DNS): that is `upstream`.
        return result(host, "upstream", answers, elapsed, null)
    }

    private fun answersOf(ips: JSONArray?, ttls: JSONArray?, ipv4: Boolean): List<Map<String, Any?>> {
        if (ips == null) return emptyList()
        val type = if (ipv4) "A" else "AAAA"
        val answers = mutableListOf<Map<String, Any?>>()
        for (index in 0 until ips.length()) {
            val value = ips.optString(index).takeIf { it.isNotEmpty() } ?: continue
            answers.add(
                mapOf(
                    "type" to type,
                    "value" to value,
                    // TTLs are optional in the payload; 0 means not reported, never expired.
                    
                    "ttl" to (ttls?.optInt(index, 0) ?: 0),
                ),
            )
        }
        return answers
    }

    private fun answer(type: String, value: String): Map<String, Any?> =
        mapOf("type" to type, "value" to value, "ttl" to 0)

    /// Same wording the legacy app's `errorLabel()` used for the one token users hit
    private fun translateEngineError(raw: String): String = when (raw) {
        "tunnel resolver not active" -> "隧道解析器未就绪（DNS 尚未生效）"
        "empty domain" -> "请输入要查询的域名"
        else -> raw
    }

    private fun noDataMessage(reason: String?): String = when {
        reason == null -> "解析未返回地址记录"
        reason.contains("NXDOMAIN", ignoreCase = true) -> "域名不存在（NXDOMAIN）"
        reason.contains("SERVFAIL", ignoreCase = true) -> "上游解析失败（SERVFAIL）"
        reason == "no answer records" -> "解析未返回地址记录"
        else -> "解析无结果：$reason"
    }

    private fun result(
        domain: String,
        source: String,
        answers: List<Map<String, Any?>>,
        elapsedMs: Double,
        error: String?,
    ): Map<String, Any?> = mapOf(
        "domain" to domain,
        "source" to source,
        "answers" to answers,
        "elapsedMs" to elapsedMs,
        "error" to error,
    )

    private fun error(domain: String, message: String, elapsedMs: Double = 0.0) =
        result(domain, "error", emptyList(), elapsedMs, message)
}
