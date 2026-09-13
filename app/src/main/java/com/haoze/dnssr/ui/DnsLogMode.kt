package com.haoze.dnssr.ui

enum class DnsLogMode(val storageValue: String, val displayName: String) {
    ALL("all", "记录全部"),
    BLOCKED_AND_ERRORS("blocked_and_errors", "仅拦截和错误"),
    OFF("off", "关闭");

    companion object {
        fun fromStorageValue(value: String?): DnsLogMode =
            entries.firstOrNull { it.storageValue == value } ?: OFF
    }
}
