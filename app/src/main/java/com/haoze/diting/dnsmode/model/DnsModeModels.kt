package com.haoze.diting.dnsmode.model

enum class DnsModeProtocol(val label: String, val defaultPort: Int) {
    UDP("UDP", 53),
    TCP("TCP", 53),
    DOH("DoH", 443),
    DOT("DoT", 853);
}

enum class DnsServiceStatus {
    STOPPED,
    STARTING,
    RUNNING,
    STOPPING,
    ERROR;

    val isRunning: Boolean get() = this == RUNNING
}

data class DnsUpstreamServer(
    val id: String,
    val name: String,
    val address: String,
    val port: Int = 53,
    val protocol: DnsModeProtocol = DnsModeProtocol.UDP,
    val description: String = "",
    val isCustom: Boolean = false
) {
    fun endpointLabel(): String {
        return when (protocol) {
            DnsModeProtocol.DOH -> "[${protocol.label}] $address"
            else -> "[${protocol.label}] $address:$port"
        }
    }

    companion object {
        val PRESETS = listOf(
            DnsUpstreamServer(
                id = "alidns",
                name = "阿里 DNS",
                address = "223.5.5.5",
                port = 53,
                protocol = DnsModeProtocol.UDP,
                description = "阿里巴巴公共 DNS，国内解析低时延"
            ),
            DnsUpstreamServer(
                id = "dnspod",
                name = "腾讯 DNSPod",
                address = "119.29.29.29",
                port = 53,
                protocol = DnsModeProtocol.UDP,
                description = "腾讯云公共解析，节点覆盖广"
            ),
            DnsUpstreamServer(
                id = "cloudflare",
                name = "Cloudflare DNS",
                address = "1.1.1.1",
                port = 53,
                protocol = DnsModeProtocol.UDP,
                description = "全球快速且隐私友好的 DNS 服务"
            ),
            DnsUpstreamServer(
                id = "google",
                name = "Google Public DNS",
                address = "8.8.8.8",
                port = 53,
                protocol = DnsModeProtocol.UDP,
                description = "Google 全球公共 DNS 解析服务"
            ),
            DnsUpstreamServer(
                id = "quad9",
                name = "Quad9 DNS",
                address = "9.9.9.9",
                port = 53,
                protocol = DnsModeProtocol.UDP,
                description = "内置恶意域名安全拦截与隐私保护"
            ),
            DnsUpstreamServer(
                id = "alidns_doh",
                name = "阿里 DNS (DoH)",
                address = "https://dns.alidns.com/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                description = "基于 HTTPS 的加密 DNS 解析"
            ),
            DnsUpstreamServer(
                id = "cloudflare_doh",
                name = "Cloudflare (DoH)",
                address = "https://cloudflare-dns.com/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                description = "Cloudflare 1.1.1.1 加密 DNS 查询"
            )
        )
    }
}

data class DnsModeConfig(
    val selectedUpstreamId: String = "alidns",
    val localListenPort: Int = 1053,
    val cacheEnabled: Boolean = true,
    val cacheTtlSeconds: Int = 300,
    val adBlockEnabled: Boolean = false,
    val logQueries: Boolean = false
)

data class DnsModeStats(
    val queryCount: Long = 0L,
    val cacheHitCount: Long = 0L,
    val blockedCount: Long = 0L,
    val latencyMs: Long = 0L,
    val latencyTotalMs: Long = 0L,
    val uptimeSeconds: Long = 0L
)
