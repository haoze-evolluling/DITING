package com.haoze.diting.platform

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import androidx.core.content.ContextCompat

/// Reads the SSID of the joined Wi-Fi for on-demand connection rules.
internal class WifiSsidReader(private val context: Context) {

    /// The SSID of the joined Wi-Fi. Null means the answer is unknowable (permission denied or
    /// location services off) and the page must say so rather than show a made-up name; an empty
    /// string means "not on Wi-Fi". Android 10+ needs a location permission for `getConnectionInfo`
    /// to return a real SSID, and Android 13+ additionally gates it behind NEARBY_WIFI_DEVICES.
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
        // Location services off also blanks the SSID, so report "unknown" instead of "".
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
        // Android quotes SSIDs, and some builds (emulators) escape them a second time, so strip
        // every surrounding quote instead of exactly one pair; an unassociated network reports the
        // sentinel `<unknown ssid>`.
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
