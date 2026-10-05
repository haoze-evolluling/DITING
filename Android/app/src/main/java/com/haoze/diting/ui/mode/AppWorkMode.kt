package com.haoze.diting.ui.mode

import android.os.Build
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.ui.graphics.vector.ImageVector

enum class AppWorkMode(
    val storageValue: String,
    val title: String,
    val summary: String,
    val badgeText: String,
    val minApiLevel: Int,
    val isAvailable: Boolean,
    val icon: ImageVector
) {
    NORMAL(
        storageValue = "normal",
        title = "普通模式",
        summary = "包含全量域名解析、黑白名单过滤、HTTPS 检查与网络管控能力",
        badgeText = "推荐",
        minApiLevel = 29,
        isAvailable = true,
        icon = Icons.Outlined.Layers
    ),
    DNS(
        storageValue = "dns",
        title = "服务器模式",
        summary = "轻量级纯 DNS 代理与解析加速，专注于低功耗防护",
        badgeText = "轻量",
        minApiLevel = 29,
        isAvailable = true,
        icon = Icons.Outlined.Dns
    ),
    EXPRESS(
        storageValue = "express",
        title = "极速模式",
        summary = "Kotlin 原生轻量实现,DNS 解析加速与规则过滤,支持 Android 7+ (64 位)",
        badgeText = "极速",
        minApiLevel = 24,
        isAvailable = true,
        icon = Icons.Outlined.Bolt
    );

    fun isSupportedOnCurrentDevice(): Boolean =
        Build.VERSION.SDK_INT >= minApiLevel

    companion object {
        fun fromStorageValue(value: String?): AppWorkMode =
            entries.firstOrNull { it.storageValue == value } ?: NORMAL
    }
}
