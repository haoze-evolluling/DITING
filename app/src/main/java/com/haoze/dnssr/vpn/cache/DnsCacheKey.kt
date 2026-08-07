package com.haoze.dnssr.vpn.cache

import com.haoze.dnssr.vpn.DnsMessageUtils

data class DnsCacheKey(
    val name: String,
    val type: Int,
    val qclass: Int,
    val dnssecOk: Boolean,
    val checkingDisabled: Boolean,
    val storageKey: String
) {
    companion object {
        fun fromQuestion(question: DnsMessageUtils.DnsQuestion): DnsCacheKey {
            val normalizedName = question.name.lowercase()
            val storageKey = buildString {
                append(normalizedName)
                append('|')
                append(question.type)
                append('|')
                append(question.qclass)
                append('|')
                append(if (question.dnssecOk) 1 else 0)
                append('|')
                append(if (question.checkingDisabled) 1 else 0)
            }
            return DnsCacheKey(
                name = normalizedName,
                type = question.type,
                qclass = question.qclass,
                dnssecOk = question.dnssecOk,
                checkingDisabled = question.checkingDisabled,
                storageKey = storageKey
            )
        }
    }
}
