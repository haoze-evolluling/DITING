package com.haoze.diting.net

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

internal object DnsServerProbe {

    private const val TIMEOUT_MS = 5000

    data class Record(val type: String, val value: String, val ttl: Long)

    fun lookup(domain: String, server: String, ipv4: Boolean): Result {
        val port = 53
        val address = InetAddress.getByName(server)
        val query = ProbeNative.buildDnsQueryOrNull(queryId(), ipv4, domain)
            ?: throw IllegalArgumentException("域名标签非法: $domain")
        val startedAt = System.nanoTime()
        val response = send(address, port, query)
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000.0

        val reply = ProbeNative.parseDnsServerReply(response, ipv4)
        val records = when (reply) {
            is ProbeDnsReply.Ok -> reply.answers.map {
                Record(if (it.ipv4) "A" else "AAAA", it.value, it.ttl)
            }
            ProbeDnsReply.Invalid -> throw IllegalStateException("响应不完整，不是有效的 DNS 应答")
            ProbeDnsReply.Truncated ->
                throw IllegalStateException("应答被截断（TC=1），请改用支持 TCP 的查询工具")
            is ProbeDnsReply.Rcode -> throw IllegalStateException(rcodeMessage(reply.code))
            ProbeDnsReply.Incomplete -> throw IllegalStateException()
        }

        return Result(records = records, elapsedMs = elapsedMs, server = server)
    }

    data class Result(
        val records: List<Record>,
        val elapsedMs: Double,
        val server: String,
    )

    private fun queryId(): Int = (System.nanoTime() and 0xFFFF).toInt()

    private fun rcodeMessage(rcode: Int): String = when (rcode) {
        1 -> "查询格式错误（FORMERR）"
        2 -> "服务器内部失败（SERVFAIL）"
        3 -> "域名不存在（NXDOMAIN）"
        4 -> "服务器不支持该查询（NOTIMP）"
        5 -> "服务器拒绝该查询（REFUSED）"
        else -> "查询失败（RCODE=$rcode）"
    }

    private fun send(address: InetAddress, port: Int, query: ByteArray): ByteArray {
        DatagramSocket().use { socket ->
            socket.soTimeout = TIMEOUT_MS
            socket.send(DatagramPacket(query, query.size, address, port))
            val buffer = ByteArray(4096)
            val packet = DatagramPacket(buffer, buffer.size)
            socket.receive(packet)
            return packet.data.copyOf(packet.length)
        }
    }
}
