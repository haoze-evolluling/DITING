package com.haoze.diting.net

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/// Manual A/AAAA UDP query to a user resolver over the physical network; TC reported, not retried.
internal object DnsServerProbe {

    private const val TIMEOUT_MS = 5000

    private const val TYPE_A = 1
    private const val TYPE_CNAME = 5
    private const val TYPE_AAAA = 28
    private const val CLASS_IN = 1

    data class Record(val type: String, val value: String, val ttl: Long)

    /// Queries `server` (an IP literal); failures throw and surface as `source=error`
    fun lookup(domain: String, server: String, ipv4: Boolean): Result {
        val port = 53
        val address = InetAddress.getByName(server)
        val query = buildQuery(domain, if (ipv4) TYPE_A else TYPE_AAAA)
        val startedAt = System.nanoTime()
        val response = send(address, port, query)
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000.0

        if (response.size < 12 || (response[0].toInt() and 0x80) == 0) {
            throw IllegalStateException("响应不完整，不是有效的 DNS 应答")
        }
        // `TC` bit: the answer did not fit in one datagram; report it, not a partial list.
        if ((response[2].toInt() and 0x02) != 0) {
            throw IllegalStateException("应答被截断（TC=1），请改用支持 TCP 的查询工具")
        }

        val rcode = response[3].toInt() and 0x0F
        if (rcode != 0) {
            throw IllegalStateException(rcodeMessage(rcode))
        }

        return Result(
            records = parseAnswers(response, ipv4),
            elapsedMs = elapsedMs,
            server = server,
        )
    }

    data class Result(
        val records: List<Record>,
        val elapsedMs: Double,
        val server: String,
    )

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

    /// Builds a single-question query with `RD = 1`, so the server resolves on our behalf
    private fun buildQuery(domain: String, qtype: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val data = DataOutputStream(out)
        data.writeShort((System.nanoTime() and 0xFFFF).toInt()) // ID
        data.writeShort(0x0100) // RD = 1, recursion desired
        data.writeShort(1) // QDCOUNT
        data.writeShort(0) // ANCOUNT
        data.writeShort(0) // NSCOUNT
        data.writeShort(0) // ARCOUNT
        for (label in domain.trim('.').split('.')) {
            val bytes = label.toByteArray(Charsets.US_ASCII)
            if (bytes.isEmpty() || bytes.size > 63) {
                throw IllegalArgumentException("域名标签非法: $domain")
            }
            data.writeByte(bytes.size)
            data.write(bytes)
        }
        data.writeByte(0) // end of QNAME
        data.writeShort(qtype)
        data.writeShort(CLASS_IN)
        data.flush()
        return out.toByteArray()
    }

    /// Names may use compression pointers, hence skipName over a length-prefixed read
    private fun parseAnswers(response: ByteArray, ipv4: Boolean): List<Record> {
        val input = DataInputStream(response.inputStream())
        input.skipBytes(4) // ID + flags
        val questionCount = input.readUnsignedShort()
        val answerCount = input.readUnsignedShort()
        input.skipBytes(4) // NSCOUNT + ARCOUNT

        repeat(questionCount) {
            skipName(input)
            input.skipBytes(4) // QTYPE + QCLASS
        }

        val records = mutableListOf<Record>()
        repeat(answerCount) {
            skipName(input)
            val type = input.readUnsignedShort()
            val klass = input.readUnsignedShort()
            val ttl = input.readInt().toLong() and 0xFFFFFFFFL
            val length = input.readUnsignedShort()
            val payload = ByteArray(length)
            input.readFully(payload)
            if (klass != CLASS_IN) return@repeat
            when (type) {
                TYPE_A -> if (ipv4 && length == 4) {
                    records.add(
                        Record("A", payload.joinToString(".") { (it.toInt() and 0xFF).toString() }, ttl),
                    )
                }
                TYPE_AAAA -> if (!ipv4 && length == 16) {
                    records.add(Record("AAAA", formatIpv6(payload), ttl))
                }
                // CNAME is not rendered but still walked, so a malformed one surfaces.
                TYPE_CNAME -> Unit
            }
        }
        return records
    }

    /// A pointer ends the name and its target is not consumed, or the next fields drift
    
    private fun skipName(input: DataInputStream) {
        while (true) {
            val length = input.readUnsignedByte()
            if (length == 0) return
            if (length and 0xC0 == 0xC0) {
                input.skipBytes(1) // pointer low byte
                return
            }
            input.skipBytes(length)
        }
    }

    /// RFC 5952-ish formatting: compress the longest run of zero groups
    private fun formatIpv6(bytes: ByteArray): String {
        val groups = IntArray(8) {
            ((bytes[it * 2].toInt() and 0xFF) shl 8) or (bytes[it * 2 + 1].toInt() and 0xFF)
        }
        var bestStart = -1
        var bestLength = 0
        var index = 0
        while (index < 8) {
            if (groups[index] != 0) {
                index++
                continue
            }
            var end = index
            while (end < 8 && groups[end] == 0) end++
            if (end - index > bestLength) {
                bestStart = index
                bestLength = end - index
            }
            index = end
        }
        if (bestLength < 2) return groups.joinToString(":") { it.toString(16) }
        val head = (0 until bestStart).joinToString(":") { groups[it].toString(16) }
        val tail = (bestStart + bestLength until 8).joinToString(":") { groups[it].toString(16) }
        return "$head::$tail"
    }
}
