package com.haoze.dnssr.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Speed
import androidx.compose.ui.graphics.vector.ImageVector

enum class DnsResolutionMode(
    val storageValue: String,
    val displayName: String
) {
    SINGLE("single", "单一服务"),
    SMART_PREDICTION("smart_prediction", "智能选择"),
    PARALLEL_RACE("parallel_race", "最快响应"),
    PRIMARY_BACKUP("primary_backup", "依次尝试");

    companion object {
        fun fromStorageValue(value: String?): DnsResolutionMode? =
            entries.firstOrNull { it.storageValue == value }
    }
}

/** 模式对应的表达性图标，用于 Hero 卡片、模式卡片与选择对话框。 */
internal fun DnsResolutionMode.iconVector(): ImageVector = when (this) {
    DnsResolutionMode.SINGLE -> Icons.Filled.Dns
    DnsResolutionMode.SMART_PREDICTION -> Icons.Filled.Lightbulb
    DnsResolutionMode.PARALLEL_RACE -> Icons.Filled.Speed
    DnsResolutionMode.PRIMARY_BACKUP -> Icons.AutoMirrored.Filled.AltRoute
}
