package com.haoze.dnssr.data.entity

/** Rules are deliberately isolated between the ordinary DNS and Go tunnel paths. */
enum class RuleScope(val storageValue: String) {
    DNS("dns"),
    HTTPS("https");

    companion object {
        fun fromStorage(value: String) = entries.firstOrNull { it.storageValue == value } ?: DNS
    }
}
