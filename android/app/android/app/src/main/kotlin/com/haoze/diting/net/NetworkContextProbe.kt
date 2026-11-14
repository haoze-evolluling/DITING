package com.haoze.diting.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build

/// 把 `ConnectivityManager` 归一化成 `diting-netprofile-core` 消费的网络上下文（N1）。
///
/// 只读物理链路（VPN 传输单独标记为 vpn），字段与 Rust 侧 `NetworkContext` 一一对应。SSID/BSSID
/// 需要定位权限，取不到时返回空串而不是抛异常——匹配逻辑把空串视为“不关心”。
internal object NetworkContextProbe {

    fun snapshot(context: Context): Map<String, Any?> {
        val manager = runCatching {
            context.getSystemService(ConnectivityManager::class.java)
        }.getOrNull() ?: return neutral()

        val active = manager.activeNetwork ?: return neutral()
        val caps = manager.getNetworkCapabilities(active) ?: return neutral()

        val type = when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        val metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        val roaming = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING)
        val validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)

        var ssid = ""
        var bssid = ""
        if (type == "wifi") {
            runCatching {
                val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
                @Suppress("DEPRECATION")
                val info = wifi?.connectionInfo
                ssid = info?.ssid?.trim('"') ?: ""
                bssid = info?.bssid ?: ""
            }
        }
        return mapOf(
            "type" to type,
            "metered" to metered,
            "roaming" to roaming,
            "validated" to validated,
            "ssid" to ssid,
            "bssid" to bssid,
        )
    }

    private fun neutral(): Map<String, Any?> = mapOf(
        "type" to "unknown",
        "metered" to false,
        "roaming" to false,
        "validated" to false,
        "ssid" to "",
        "bssid" to "",
    )

    /// Kept for callers that need to branch on the platform level; unused by matching itself.
    fun supportsSsid(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
}
