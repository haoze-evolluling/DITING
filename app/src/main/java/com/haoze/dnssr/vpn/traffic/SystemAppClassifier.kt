package com.haoze.dnssr.vpn.traffic

import android.content.pm.ApplicationInfo

/**
 * Unified classification and identification of system apps and special
 * system components.
 */
object SystemAppClassifier {

    private val KNOWN_SYSTEM_PREFIXES = arrayOf(
        "android",
        "com.android.",
        "android.uid.",
        "com.google.android.gms",
        "com.google.android.gsf",
        "com.google.android.ext.services",
        "com.google.android.networkstack",
        "com.google.android.providers.media.module",
        // Xiaomi / HyperOS / MIUI
        "com.miui.",
        "com.xiaomi.",
        // Huawei / Honor / HarmonyOS / MagicOS
        "com.huawei.",
        "com.hihonor.",
        // OPPO / OnePlus / Realme / ColorOS
        "com.coloros.",
        "com.heytap.",
        "com.oplus.",
        // vivo / iQOO / OriginOS
        "com.vivo.",
        "com.bbk.",
        // Samsung OneUI
        "com.samsung.",
        "com.sec.",
        // Lenovo / Motorola
        "com.lenovo.",
        "com.motorola.",
        // Meizu Flyme
        "com.meizu.",
        // Chipset drivers and low-level hardware services
        "com.qualcomm.",
        "com.qti.",
        "com.mediatek."
    )

    /**
     * Returns whether the package name matches a known system-component or
     * vendor preinstalled-service prefix rule.
     */
    fun isKnownSystemPackagePrefix(packageName: String): Boolean {
        if (packageName.isBlank()) return false
        if (packageName == "android") return true
        for (prefix in KNOWN_SYSTEM_PREFIXES) {
            if (packageName.startsWith(prefix)) {
                return true
            }
        }
        return false
    }

    /**
     * Returns whether the app is a system app based on [ApplicationInfo]
     * system flags and UID.
     */
    fun isSystemApplicationInfo(appInfo: ApplicationInfo): Boolean {
        return (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
            (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0 ||
            appInfo.uid < 10000
    }
}
