package com.haoze.diting.vpn

import android.content.Context
import android.net.ConnectivityManager

/** 用户选择的 IPv6 策略；隧道与 DNS 语义由同一枚举决定，避免两者不一致。 */
internal enum class Ipv6Mode(val wire: String) {
    IPV4("ipv4"),
    AUTO("auto"),
    IPV6("ipv6");

    companion object {
        fun fromWire(raw: String?): Ipv6Mode =
            entries.firstOrNull { it.wire == raw?.trim()?.lowercase() } ?: IPV4

        /** 旧版两个布尔开关：只有同时开启才等价于“自动”。 */
        fun fromLegacy(tunnelIpv6: Boolean, dnsAaaa: Boolean): Ipv6Mode =
            if (tunnelIpv6 && dnsAaaa) AUTO else IPV4
    }
}

/** 一次隧道启动实际采用的 IPv6 形态。 */
internal data class Ipv6Plan(
    val tunnelIpv6: Boolean,
    val blockIpv6: Boolean,
    val preferIpv6: Boolean,
)

internal object Ipv6Policy {
    /**
     * CLAT 网络必须启用 IPv6，即使策略是 IPv4；其余情况下没有物理 IPv6 就不注入，
     * 否则 AAAA 解析会得到无法到达的地址。
     */
    fun resolve(mode: Ipv6Mode, hasRoutableIpv6: Boolean, clat: Boolean): Ipv6Plan {
        val tunnel = clat || (mode != Ipv6Mode.IPV4 && hasRoutableIpv6)
        return Ipv6Plan(
            tunnelIpv6 = tunnel,
            blockIpv6 = !tunnel,
            preferIpv6 = tunnel && mode == Ipv6Mode.IPV6,
        )
    }

    fun hasRoutableIpv6(context: Context): Boolean = runCatching {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
        NetworkTopology.physicalLinks(manager).any(NetworkTopology::hasRoutableIpv6)
    }.getOrDefault(false)
}
