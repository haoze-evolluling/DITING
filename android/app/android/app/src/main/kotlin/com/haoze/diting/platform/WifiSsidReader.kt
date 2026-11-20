package com.haoze.diting.platform

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import androidx.core.content.ContextCompat

internal class WifiSsidReader(private val context: Context) {

    fun currentSsid(): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !hasPermission(Manifest.permission.NEARBY_WIFI_DEVICES) &&
            !hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        ) {
            return null
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            !hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        ) {
            return null
        }
        if (!isLocationEnabled()) {
            return null
        }
        val wifi = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager
        @Suppress("DEPRECATION")
        val info = runCatching { wifi?.connectionInfo }.getOrNull() ?: return null
        @Suppress("DEPRECATION")
        val ssid = info.ssid
        if (ssid.isNullOrBlank()) return ""
        val unquoted = ssid.trim().trim('"').trim()
        if (unquoted == WifiManager.UNKNOWN_SSID) return ""
        return unquoted
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED

    private fun isLocationEnabled(): Boolean = runCatching {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return false
        manager.isLocationEnabled
    }.getOrDefault(false)
}
