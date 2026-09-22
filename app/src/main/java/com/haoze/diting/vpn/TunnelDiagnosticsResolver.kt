package com.haoze.diting.vpn

import org.json.JSONObject

/**
 * Resolves domains through the running Go tunnel for the diagnostics tools,
 * mirroring the engine's ResolveDomain JSON contract. A null return means
 * the VPN (and therefore the tunnel) is not running.
 */
object TunnelDiagnosticsResolver {

    enum class Source { REWRITE, UPSTREAM, BLOCKED, NODATA, ERROR }

    data class Result(
        val ips: List<String>,
        val ttls: List<Int>,
        val source: Source,
        val reason: String?,
        val error: String?
    ) {
        /** Human-readable decision source; empty for non-answer outcomes. */
        fun sourceLabel(): String = when (source) {
            Source.REWRITE -> "覆写规则"
            Source.UPSTREAM -> "上游 DNS"
            else -> ""
        }

        /** Translates the engine's technical error tokens into user-facing text. */
        fun errorLabel(): String = when (error) {
            "tunnel resolver not active" -> "Go 隧道未运行"
            null -> "隧道解析失败"
            else -> error
        }
    }

    fun resolve(domain: String, preferIpv4: Boolean): Result? {
        val json = DnsVpnService.resolveThroughTunnel(domain, preferIpv4) ?: return null
        return runCatching { parse(json) }.getOrNull()
            ?: Result(emptyList(), emptyList(), Source.ERROR, null, "解析结果无效")
    }

    /** Resolves IPv4 first and falls back to IPv6 only when the family yields no answer records. */
    fun resolveAutoFamily(domain: String): Result? {
        resolve(domain, preferIpv4 = true)?.let { result ->
            if (result.ips.isNotEmpty() || result.source != Source.NODATA) return result
        }
        return resolve(domain, preferIpv4 = false)
    }

    private fun parse(json: String): Result {
        val obj = JSONObject(json)
        obj.optString("error").takeIf { it.isNotEmpty() }?.let { error ->
            return Result(emptyList(), emptyList(), Source.ERROR, null, error)
        }
        val ips = obj.optJSONArray("ips")?.let { array ->
            (0 until array.length()).mapNotNull { index ->
                array.optString(index).takeIf { it.isNotEmpty() }
            }
        }.orEmpty()
        val ttls = obj.optJSONArray("ttls")?.let { array ->
            (0 until array.length()).map { index -> array.optInt(index) }
        }.orEmpty()
        val source = when (obj.optString("source")) {
            "rewrite" -> Source.REWRITE
            "upstream" -> Source.UPSTREAM
            "blocked" -> Source.BLOCKED
            else -> Source.NODATA
        }
        return Result(ips, ttls, source, obj.optString("reason").takeIf { it.isNotEmpty() }, null)
    }
}
