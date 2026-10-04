package com.haoze.diting.express.engine

/**
 * Common public DNS IP addresses hijacked into TUN for local resolution.
 *
 * Route table in Phase 3 registers these addresses (/32 for IPv4, /128 for IPv6)
 * to intercept hard-coded public DNS queries from applications.
 */
object PublicDnsHijackList {

    data class HijackEntry(
        val ip: String,
        val isIpv6: Boolean,
        val provider: String,
        val description: String
    )

    /**
     * Common public DNS IPv4 addresses (approx 22 items).
     */
    val IPV4_HIJACK_ENTRIES: List<HijackEntry> = listOf(
        // Google Public DNS
        HijackEntry("8.8.8.8", false, "Google", "Google Public DNS Primary"),
        HijackEntry("8.8.4.4", false, "Google", "Google Public DNS Secondary"),
        // Cloudflare DNS
        HijackEntry("1.1.1.1", false, "Cloudflare", "Cloudflare DNS Primary"),
        HijackEntry("1.0.0.1", false, "Cloudflare", "Cloudflare DNS Secondary"),
        // Quad9
        HijackEntry("9.9.9.9", false, "Quad9", "Quad9 Recommended Primary"),
        HijackEntry("149.112.112.112", false, "Quad9", "Quad9 Recommended Secondary"),
        // OpenDNS (Cisco)
        HijackEntry("208.67.222.222", false, "OpenDNS", "OpenDNS Home Primary"),
        HijackEntry("208.67.220.220", false, "OpenDNS", "OpenDNS Home Secondary"),
        // AliDNS (Alibaba Cloud)
        HijackEntry("223.5.5.5", false, "AliDNS", "Aliyun Public DNS Primary"),
        HijackEntry("223.6.6.6", false, "AliDNS", "Aliyun Public DNS Secondary"),
        // DNSPod (Tencent Cloud)
        HijackEntry("119.29.29.29", false, "DNSPod", "Tencent Public DNS"),
        // 114DNS
        HijackEntry("114.114.114.114", false, "114DNS", "114DNS Primary"),
        HijackEntry("114.114.115.115", false, "114DNS", "114DNS Secondary"),
        // Baidu DNS
        HijackEntry("180.76.76.76", false, "Baidu DNS", "Baidu Public DNS"),
        // Yandex DNS
        HijackEntry("77.88.8.8", false, "Yandex", "Yandex.DNS Basic Primary"),
        HijackEntry("77.88.8.1", false, "Yandex", "Yandex.DNS Basic Secondary"),
        // AdGuard DNS
        HijackEntry("94.140.14.14", false, "AdGuard", "AdGuard Default Primary"),
        HijackEntry("94.140.14.15", false, "AdGuard", "AdGuard Default Secondary"),
        // CleanBrowsing
        HijackEntry("185.228.168.9", false, "CleanBrowsing", "CleanBrowsing Security Primary"),
        HijackEntry("185.228.169.9", false, "CleanBrowsing", "CleanBrowsing Security Secondary"),
        // Neustar / UltraDNS
        HijackEntry("64.6.64.6", false, "Neustar", "UltraDNS Public Primary"),
        HijackEntry("64.6.65.6", false, "Neustar", "UltraDNS Public Secondary")
    )

    /**
     * Common public DNS IPv6 addresses (approx 8 items).
     */
    val IPV6_HIJACK_ENTRIES: List<HijackEntry> = listOf(
        // Google IPv6
        HijackEntry("2001:4860:4860::8888", true, "Google", "Google IPv6 Primary"),
        HijackEntry("2001:4860:4860::8844", true, "Google", "Google IPv6 Secondary"),
        // Cloudflare IPv6
        HijackEntry("2606:4700:4700::1111", true, "Cloudflare", "Cloudflare IPv6 Primary"),
        HijackEntry("2606:4700:4700::1001", true, "Cloudflare", "Cloudflare IPv6 Secondary"),
        // Quad9 IPv6
        HijackEntry("2620:fe::fe", true, "Quad9", "Quad9 IPv6 Primary"),
        HijackEntry("2620:fe::9", true, "Quad9", "Quad9 IPv6 Secondary"),
        // AliDNS IPv6
        HijackEntry("2400:3200::1", true, "AliDNS", "Aliyun IPv6 Primary"),
        HijackEntry("2400:3200:baba::1", true, "AliDNS", "Aliyun IPv6 Secondary")
    )

    val IPV4_HIJACK_IPS: List<String> = IPV4_HIJACK_ENTRIES.map { it.ip }
    val IPV6_HIJACK_IPS: List<String> = IPV6_HIJACK_ENTRIES.map { it.ip }
    val ALL_HIJACK_IPS: Set<String> = (IPV4_HIJACK_IPS + IPV6_HIJACK_IPS).toSet()

    fun isHijacked(ip: String): Boolean = ALL_HIJACK_IPS.contains(ip.trim())
}
