package com.haoze.dnssr.ui

enum class PresetDnsService(
    val displayName: String
) {
    DNS("DNS"),
    DOT("DoT"),
    DOH("DoH");

    companion object {
        fun fromStorageValue(value: String?): PresetDnsService =
            entries.firstOrNull { it.name == value } ?: DNS
    }
}
