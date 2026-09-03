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
            return create(
                name = question.name,
                type = question.type,
                qclass = question.qclass,
                dnssecOk = question.dnssecOk,
                checkingDisabled = question.checkingDisabled
            )
        }

        fun create(
            name: String,
            type: Int,
            qclass: Int = 1,
            dnssecOk: Boolean = false,
            checkingDisabled: Boolean = false
        ): DnsCacheKey {
            val normalizedName = name.trim().trimEnd('.').lowercase()
            val storageKey = buildString {
                append(normalizedName)
                append('|')
                append(type)
                append('|')
                append(qclass)
                append('|')
                append(if (dnssecOk) 1 else 0)
                append('|')
                append(if (checkingDisabled) 1 else 0)
            }
            return DnsCacheKey(
                name = normalizedName,
                type = type,
                qclass = qclass,
                dnssecOk = dnssecOk,
                checkingDisabled = checkingDisabled,
                storageKey = storageKey
            )
        }
    }
}
