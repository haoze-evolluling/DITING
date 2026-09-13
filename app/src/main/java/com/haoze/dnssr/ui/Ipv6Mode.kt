package com.haoze.dnssr.ui

enum class Ipv6Mode(
    val storageValue: String,
    val displayName: String
) {
    AUTO("auto", "自动探测（推荐）"),
    ENABLED("enabled", "始终开启"),
    DISABLED("disabled", "始终禁用");

    companion object {
        fun fromStorageValue(value: String?): Ipv6Mode =
            entries.firstOrNull { it.storageValue == value } ?: AUTO
    }
}
