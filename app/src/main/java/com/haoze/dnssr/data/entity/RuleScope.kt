package com.haoze.dnssr.data.entity

/** DNS is the canonical domain-rule scope; HTTPS remains only for database/route compatibility. */
enum class RuleScope(val storageValue: String) {
    DNS("dns"),
    HTTPS("https");

    companion object {
        fun fromStorage(value: String) = entries.firstOrNull { it.storageValue == value } ?: DNS
    }
}
