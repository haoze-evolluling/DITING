package com.haoze.dnssr.vpn

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.Inet6Address
import java.net.InetAddress

/**
 * DNS 解析查询工具（网络调试工具）。
 *
 * 向指定 DNS 服务器发送一次标准 A/AAAA 查询并完整解析应答记录，
 * 展示解析 IP、CNAME/NS 等记录、TTL 与响应状态。不依赖 VpnService，
 * 复用 DnsMessageUtils 构造报文与 PlainDnsTransport 传输（UDP + TCP 截断重试）。
 */
object DnsLookupTool {

    enum class RecordType(val label: String, val code: Int) {
        A("A", 1),
        AAAA("AAAA", 28)
    }

    data class Record(
        val name: String,
        val typeLabel: String,
        val ttlSeconds: Long,
        val value: String
    )

    data class Result(
        val queryName: String,
        val recordTypeLabel: String,
        val server: String,
        val records: List<Record>,
        val resolvedAddresses: List<String>,
        val elapsedMs: Long,
        val rcodeLabel: String?,
        val success: Boolean,
        val message: String? = null
    )

    suspend fun lookup(
        host: String,
        recordType: RecordType,
        servers: List<InetAddress>,
        port: Int = 53
    ): Result = withContext(Dispatchers.IO) {
        val name = host.trim()
        if (name.isEmpty()) {
            return@withContext failed("", recordType, "", "请输入要解析的域名")
        }
        if (servers.isEmpty()) {
            return@withContext failed(name, recordType, "", "没有可用的 DNS 服务器")
        }

        if (DnsProvider.isIpLiteral(name)) {
            val address = runCatching { InetAddress.getByName(name) }.getOrNull()
            val hostAddress = address?.hostAddress ?: name
            val typeLabel = if (address is Inet6Address) RecordType.AAAA.label else RecordType.A.label
            return@withContext Result(
                queryName = name,
                recordTypeLabel = typeLabel,
                server = "",
                records = listOf(Record(name, typeLabel, 0, hostAddress)),
                resolvedAddresses = listOf(hostAddress),
                elapsedMs = 0,
                rcodeLabel = null,
                success = true,
                message = null
            )
        }

        val serverLabel = servers.joinToString(" / ") { it.hostAddress ?: it.toString() }
            .let { if (port != 53) "$it:$port" else it }
        val start = System.currentTimeMillis()
        try {
            val query = DnsMessageUtils.buildQuery(name, recordType.code)
            val response = PlainDnsTransport.query(servers, port, null, null, query)
            val elapsed = System.currentTimeMillis() - start
            val records = DnsRecordParser.parse(response)
            val rcode = DnsMessageUtils.responseCodeLabel(response)
            val success = DnsMessageUtils.isSuccessResponse(response)
            val resolvedAddresses = records
                .filter { it.typeLabel == RecordType.A.label || it.typeLabel == RecordType.AAAA.label }
                .map { it.value }
                .distinct()
            Result(
                queryName = name,
                recordTypeLabel = recordType.label,
                server = serverLabel,
                records = records,
                resolvedAddresses = resolvedAddresses,
                elapsedMs = elapsed,
                rcodeLabel = rcode,
                success = success,
                message = when {
                    !success -> "查询失败"
                    records.none { it.typeLabel == recordType.label } -> "该域名没有 ${recordType.label} 记录"
                    else -> null
                }
            )
        } catch (e: Exception) {
            failed(name, recordType, serverLabel, "查询失败", System.currentTimeMillis() - start, e.message)
        }
    }

    private fun failed(
        name: String,
        recordType: RecordType,
        server: String,
        message: String,
        elapsedMs: Long = 0,
        detail: String? = null
    ) = Result(
        queryName = name,
        recordTypeLabel = recordType.label,
        server = server,
        records = emptyList(),
        resolvedAddresses = emptyList(),
        elapsedMs = elapsedMs,
        rcodeLabel = null,
        success = false,
        message = listOfNotNull(message, detail).joinToString("：").takeIf { it.isNotEmpty() }
    )
}

/**
 * 轻量 DNS 应答记录解析器，覆盖 Answer / Authority / Additional 三个区域，
 * 支持名称压缩指针。仅解析调试工具需要展示的常见记录类型，异常报文返回已解析部分。
 */
private object DnsRecordParser {

    private const val HEADER_LEN = 12
    private const val TYPE_A = 1
    private const val TYPE_NS = 2
    private const val TYPE_CNAME = 5
    private const val TYPE_SOA = 6
    private const val TYPE_PTR = 12
    private const val TYPE_MX = 15
    private const val TYPE_TXT = 16
    private const val TYPE_AAAA = 28
    private const val TYPE_SRV = 33
    private const val TYPE_OPT = 41

    fun parse(message: ByteArray): List<DnsLookupTool.Record> {
        if (message.size < HEADER_LEN) return emptyList()
        val records = mutableListOf<DnsLookupTool.Record>()
        var offset = HEADER_LEN

        val questionCount = readShort(message, 4)
        repeat(questionCount) {
            val name = readName(message, offset) ?: return records
            offset = name.second + 4
            if (offset > message.size) return records
        }

        listOf(readShort(message, 6), readShort(message, 8), readShort(message, 10)).forEach { count ->
            repeat(count) {
                if (offset >= message.size) return records
                val name = readName(message, offset) ?: return records
                if (name.second + 10 > message.size) return records
                val type = readShort(message, name.second)
                val ttl = readInt(message, name.second + 4)
                val rdLength = readShort(message, name.second + 8)
                val rdataStart = name.second + 10
                val rdataEnd = rdataStart + rdLength
                if (rdataEnd > message.size) return records
                if (type != TYPE_OPT) {
                    parseRdata(message, rdataStart, rdataEnd, type)?.let { value ->
                        records.add(DnsLookupTool.Record(name.first, typeLabel(type), ttl, value))
                    }
                }
                offset = rdataEnd
            }
        }
        return records
    }

    private fun parseRdata(message: ByteArray, start: Int, end: Int, type: Int): String? {
        val length = end - start
        return when (type) {
            TYPE_A -> if (length == 4) addressLabel(message.copyOfRange(start, end)) else null
            TYPE_AAAA -> if (length == 16) addressLabel(message.copyOfRange(start, end)) else null
            TYPE_CNAME, TYPE_NS, TYPE_PTR -> readName(message, start)?.first
            TYPE_MX -> if (length >= 3) {
                val preference = readShort(message, start)
                readName(message, start + 2)?.first?.let { "$it ($preference)" }
            } else {
                null
            }
            TYPE_SRV -> if (length >= 7) {
                val priority = readShort(message, start)
                val weight = readShort(message, start + 2)
                val port = readShort(message, start + 4)
                readName(message, start + 6)?.first?.let { "$it ($port · 优先级 $priority · 权重 $weight)" }
            } else {
                null
            }
            TYPE_TXT -> {
                var offset = start
                val parts = mutableListOf<String>()
                while (offset < end) {
                    val partLength = message[offset].toInt() and 0xFF
                    if (offset + 1 + partLength > end) break
                    parts.add(String(message, offset + 1, partLength, Charsets.UTF_8))
                    offset += 1 + partLength
                }
                parts.joinToString(" ").takeIf { it.isNotEmpty() }
            }
            TYPE_SOA -> {
                val primary = readName(message, start) ?: return null
                val responsible = readName(message, primary.second) ?: return null
                "${primary.first} ${responsible.first}"
            }
            else -> null
        }
    }

    private fun addressLabel(bytes: ByteArray): String =
        runCatching { InetAddress.getByAddress(bytes).hostAddress }.getOrNull()
            ?: bytes.joinToString(".") { (it.toInt() and 0xFF).toString() }

    /** 返回 (名称, 名称字段之后的偏移)；解析失败返回 null。 */
    private fun readName(message: ByteArray, start: Int): Pair<String, Int>? {
        val labels = mutableListOf<String>()
        var offset = start
        var nextOffset = -1
        var jumps = 0
        while (jumps < 64) {
            if (offset < 0 || offset >= message.size) return null
            val length = message[offset].toInt() and 0xFF
            when {
                length == 0 -> {
                    if (nextOffset < 0) nextOffset = offset + 1
                    return Pair(labels.joinToString("."), nextOffset)
                }
                length and 0xC0 == 0xC0 -> {
                    if (offset + 1 >= message.size) return null
                    if (nextOffset < 0) nextOffset = offset + 2
                    offset = ((length and 0x3F) shl 8) or (message[offset + 1].toInt() and 0xFF)
                    jumps++
                }
                else -> {
                    if (offset + 1 + length > message.size) return null
                    labels.add(String(message, offset + 1, length, Charsets.US_ASCII))
                    offset += 1 + length
                    jumps++
                }
            }
        }
        return null
    }

    private fun readShort(message: ByteArray, offset: Int): Int {
        return ((message[offset].toInt() and 0xFF) shl 8) or (message[offset + 1].toInt() and 0xFF)
    }

    private fun readInt(message: ByteArray, offset: Int): Long {
        return ((message[offset].toLong() and 0xFF) shl 24) or
            ((message[offset + 1].toLong() and 0xFF) shl 16) or
            ((message[offset + 2].toLong() and 0xFF) shl 8) or
            (message[offset + 3].toLong() and 0xFF)
    }

    private fun typeLabel(type: Int): String = when (type) {
        TYPE_A -> "A"
        TYPE_NS -> "NS"
        TYPE_CNAME -> "CNAME"
        TYPE_SOA -> "SOA"
        TYPE_PTR -> "PTR"
        TYPE_MX -> "MX"
        TYPE_TXT -> "TXT"
        TYPE_AAAA -> "AAAA"
        TYPE_SRV -> "SRV"
        else -> "TYPE$type"
    }
}
