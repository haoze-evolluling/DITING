package com.haoze.diting.ui.mode

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.ui.graphics.vector.ImageVector

enum class AppWorkMode(
    val storageValue: String,
    val title: String,
    val summary: String,
    val badgeText: String,
    val isAvailable: Boolean,
    val icon: ImageVector
) {
    NORMAL(
        storageValue = "normal",
        title = "普通模式",
        summary = "包含全量域名解析、黑白名单过滤、HTTPS 检查与网络管控能力",
        badgeText = "推荐",
        isAvailable = true,
        icon = Icons.Outlined.Layers
    ),
    DNS(
        storageValue = "dns",
        title = "DNS模式",
        summary = "轻量级纯 DNS 代理与解析加速，专注于低功耗防护",
        badgeText = "施工中",
        isAvailable = false,
        icon = Icons.Outlined.Dns
    );

    companion object {
        fun fromStorageValue(value: String?): AppWorkMode =
            entries.firstOrNull { it.storageValue == value } ?: NORMAL
    }
}
