package com.haoze.dnssr.ui

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
