package com.haoze.diting.dnsmode.model

import com.haoze.diting.vpn.cache.DnsCachePreset

enum class DnsModeProtocol(val label: String, val defaultPort: Int) {
    DNS("DNS", 53),
    DOH("DoH", 443),
    DOT("DoT", 853);

    companion object {
        val MANAGED_PROTOCOLS = listOf(DNS, DOH, DOT)

        fun fromStorage(value: String?): DnsModeProtocol {
            return entries.firstOrNull { it.name.equals(value, ignoreCase = true) } ?: DNS
        }
    }
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
    val protocol: DnsModeProtocol = DnsModeProtocol.DNS,
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
                id = "preset_alidns_dns",
                name = "阿里云",
                address = "223.5.5.5",
                port = 53,
                protocol = DnsModeProtocol.DNS,
                description = "阿里巴巴公共 DNS，国内解析低时延"
            ),
            DnsUpstreamServer(
                id = "preset_dnspod_dns",
                name = "腾讯云 DNSPod",
                address = "119.29.29.29",
                port = 53,
                protocol = DnsModeProtocol.DNS,
                description = "腾讯云公共解析，节点覆盖广"
            ),
            DnsUpstreamServer(
                id = "preset_360_dns",
                name = "360",
                address = "101.226.4.6",
                port = 53,
                protocol = DnsModeProtocol.DNS,
                description = "360 安全 DNS，提供基础安全防护"
            ),
            DnsUpstreamServer(
                id = "preset_onedns_dns",
                name = "OneDNS",
                address = "117.50.10.10",
                port = 53,
                protocol = DnsModeProtocol.DNS,
                description = "北京联盛 OneDNS，拦截恶意网站"
            ),
            DnsUpstreamServer(
                id = "preset_cloudflare_dns",
                name = "Cloudflare",
                address = "1.1.1.1",
                port = 53,
                protocol = DnsModeProtocol.DNS,
                description = "全球快速且隐私友好的 DNS 服务"
            ),
            DnsUpstreamServer(
                id = "preset_google_dns",
                name = "Google",
                address = "8.8.8.8",
                port = 53,
                protocol = DnsModeProtocol.DNS,
                description = "Google 全球公共 DNS 解析服务"
            ),
            DnsUpstreamServer(
                id = "preset_alidns_doh",
                name = "阿里云",
                address = "https://dns.alidns.com/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                description = "阿里巴巴公共 DNS，基于 HTTPS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_dnspod_doh",
                name = "腾讯云 DNSPod",
                address = "https://doh.pub/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                description = "腾讯云公共解析，基于 HTTPS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_360_doh",
                name = "360",
                address = "https://doh.360.cn/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                description = "360 安全 DNS，基于 HTTPS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_onedns_doh",
                name = "OneDNS",
                address = "https://doh.onedns.net/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                description = "OneDNS 安全解析，基于 HTTPS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_cloudflare_doh",
                name = "Cloudflare",
                address = "https://cloudflare-dns.com/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                description = "Cloudflare 1.1.1.1 加密 DNS 查询"
            ),
            DnsUpstreamServer(
                id = "preset_google_doh",
                name = "Google",
                address = "https://dns.google/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                description = "Google 公共 DNS，基于 HTTPS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_alidns_dot",
                name = "阿里云",
                address = "dns.alidns.com",
                port = 853,
                protocol = DnsModeProtocol.DOT,
                description = "阿里巴巴公共 DNS，基于 TLS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_dnspod_dot",
                name = "腾讯云 DNSPod",
                address = "dot.pub",
                port = 853,
                protocol = DnsModeProtocol.DOT,
                description = "腾讯云公共解析，基于 TLS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_360_dot",
                name = "360",
                address = "dot.360.cn",
                port = 853,
                protocol = DnsModeProtocol.DOT,
                description = "360 安全 DNS，基于 TLS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_onedns_dot",
                name = "OneDNS",
                address = "dot.onedns.net",
                port = 853,
                protocol = DnsModeProtocol.DOT,
                description = "OneDNS 安全解析，基于 TLS 的加密解析"
            ),
            DnsUpstreamServer(
                id = "preset_cloudflare_dot",
                name = "Cloudflare",
                address = "one.one.one.one",
                port = 853,
                protocol = DnsModeProtocol.DOT,
                description = "Cloudflare 1.1.1.1 加密 DNS 查询"
            ),
            DnsUpstreamServer(
                id = "preset_google_dot",
                name = "Google",
                address = "dns.google",
                port = 853,
                protocol = DnsModeProtocol.DOT,
                description = "Google 公共 DNS，基于 TLS 的加密解析"
            )
        )
    }
}

data class DnsModeConfig(
    val selectedUpstreamId: String = "preset_alidns_dns",
    val localListenPort: Int = 1053,
    val cacheEnabled: Boolean = true,
    val cachePreset: DnsCachePreset = DnsCachePreset.BALANCED,
    val cacheTtlSeconds: Int = 300,
    val adBlockEnabled: Boolean = false,
    val logQueries: Boolean = false
)

data class DnsModeStats(
    val queryCount: Long = 0L,
    val cacheHitCount: Long = 0L,
    val blockedCount: Long = 0L,
    val failedCount: Long = 0L,
    val latencyMs: Long = 0L,
    val latencyTotalMs: Long = 0L,
    val uptimeSeconds: Long = 0L
)
