package com.haoze.dnssr.vpn.traffic

import android.content.pm.ApplicationInfo

/**
 * 系统应用与特殊系统组件统一分类与识别工具。
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
        // 小米 / HyperOS / MIUI
        "com.miui.",
        "com.xiaomi.",
        // 华为 / 荣耀 / HarmonyOS / MagicOS
        "com.huawei.",
        "com.hihonor.",
        // OPPO / 一加 / Realme / ColorOS
        "com.coloros.",
        "com.heytap.",
        "com.oplus.",
        // vivo / iQOO / OriginOS
        "com.vivo.",
        "com.bbk.",
        // 三星 OneUI
        "com.samsung.",
        "com.sec.",
        // 联想 / MOTO
        "com.lenovo.",
        "com.motorola.",
        // 魅族 Flyme
        "com.meizu.",
        // 芯片驱动与底层硬件服务
        "com.qualcomm.",
        "com.qti.",
        "com.mediatek."
    )

    /**
     * 判断包名是否符合已知系统组件或厂商系统预装服务的前缀规则
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
     * 根据 [ApplicationInfo] 的系统标志位和 UID 判断是否为系统应用
     */
    fun isSystemApplicationInfo(appInfo: ApplicationInfo): Boolean {
        return (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
            (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0 ||
            appInfo.uid < 10000
    }
}
