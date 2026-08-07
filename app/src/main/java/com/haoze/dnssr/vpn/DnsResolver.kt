package com.haoze.dnssr.vpn

interface DnsResolver {
    suspend fun resolve(query: ByteArray): ByteArray

    fun close() = Unit
}
