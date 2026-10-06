package com.haoze.diting.express.transport

import com.haoze.diting.core.dns.PlainDnsTransport
import com.haoze.diting.express.dns.ExpressDnsMessageUtils
import com.haoze.diting.core.dns.DNS_UPSTREAM_TIMEOUT_MS
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.EOFException
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Isolated Plain DNS (UDP/TCP 53) transport for Express Mode.
 *
 * Direct source-level copy of PlainDnsTransport adapted with EDNS0 negotiation,
 * configurable timeouts, and active socket cancellation hooks.
 */
object ExpressPlainDnsTransport {

    private const val DEFAULT_EDNS0_BUFFER_SIZE = 1232
    private const val MAX_DNS_PACKET_SIZE = 65_535

    fun query(
        addresses: List<InetAddress>,
        port: Int = 53,
        protectDatagramSocket: ((DatagramSocket) -> Boolean)? = null,
        protectTcpSocket: ((Socket) -> Boolean)? = null,
        query: ByteArray,
        timeoutMs: Int = DNS_UPSTREAM_TIMEOUT_MS,
        edns0BufferSize: Int = DEFAULT_EDNS0_BUFFER_SIZE,
        onSocketActive: ((Closeable) -> Unit)? = null
    ): ByteArray {
        require(addresses.isNotEmpty()) { "DNS server address is unavailable" }
        val outgoingQuery = if (edns0BufferSize > 0) {
            ExpressDnsMessageUtils.ensureEdns0(query, edns0BufferSize)
        } else {
            query
        }

        var lastError: IOException? = null
        addresses.forEach { address ->
            try {
                val response = queryUdp(address, port, protectDatagramSocket, outgoingQuery, timeoutMs, onSocketActive)
                val resolved = if (ExpressDnsMessageUtils.isTruncatedResponse(response)) {
                    queryTcp(address, port, protectTcpSocket, outgoingQuery, timeoutMs, onSocketActive)
                } else {
                    response
                }
                if (!ExpressDnsMessageUtils.isUsableUpstreamResponse(resolved, outgoingQuery)) {
                    throw IOException("DNS server returned an invalid response")
                }
                return resolved
            } catch (e: IOException) {
                lastError = e
            }
        }
        throw lastError ?: IOException("All DNS server addresses failed")
    }

    private fun queryUdp(
        address: InetAddress,
        port: Int,
        protectSocket: ((DatagramSocket) -> Boolean)?,
        query: ByteArray,
        timeoutMs: Int,
        onSocketActive: ((Closeable) -> Unit)?
    ): ByteArray {
        val socket = DatagramSocket()
        onSocketActive?.invoke(socket)
        socket.use { s ->
            if (protectSocket != null && !protectSocket(s)) {
                throw IOException("Failed to protect DNS UDP socket")
            }
            s.soTimeout = timeoutMs
            s.connect(InetSocketAddress(address, port))
            s.send(DatagramPacket(query, query.size))
            val buffer = ByteArray(MAX_DNS_PACKET_SIZE)
            val response = DatagramPacket(buffer, buffer.size)
            s.receive(response)
            return buffer.copyOf(response.length)
        }
    }

    private fun queryTcp(
        address: InetAddress,
        port: Int,
        protectSocket: ((Socket) -> Boolean)?,
        query: ByteArray,
        timeoutMs: Int,
        onSocketActive: ((Closeable) -> Unit)?
    ): ByteArray {
        val socket = Socket()
        onSocketActive?.invoke(socket)
        socket.use { s ->
            if (protectSocket != null && !protectSocket(s)) {
                throw IOException("Failed to protect DNS TCP socket")
            }
            s.soTimeout = timeoutMs
            s.connect(InetSocketAddress(address, port), timeoutMs)
            val output = BufferedOutputStream(s.outputStream)
            output.write(query.size ushr 8)
            output.write(query.size and 0xFF)
            output.write(query)
            output.flush()

            val input = BufferedInputStream(s.inputStream)
            val high = input.read()
            val low = input.read()
            if (high < 0 || low < 0) throw EOFException("Incomplete DNS TCP response length")
            val length = (high shl 8) or low
            if (length == 0) throw IOException("Empty DNS TCP response")
            val response = ByteArray(length)
            var offset = 0
            while (offset < length) {
                val read = input.read(response, offset, length - offset)
                if (read < 0) throw EOFException("Incomplete DNS TCP response")
                offset += read
            }
            return response
        }
    }
}
