package com.haoze.diting.express.transport

import com.haoze.diting.core.dns.DotTransport
import com.haoze.diting.express.engine.ExpressDnsMessageUtils
import com.haoze.diting.core.dns.DNS_UPSTREAM_TIMEOUT_MS
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.EOFException
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Isolated DNS-over-TLS (DoT) transport for Express Mode.
 *
 * Direct source-level copy of DotTransport adapted with EDNS0 negotiation,
 * configurable timeouts, and active socket cancellation hooks.
 */
object ExpressDotTransport {

    private const val DEFAULT_EDNS0_BUFFER_SIZE = 1232
    private const val MAX_DNS_MESSAGE_SIZE = 65_535

    fun query(
        host: String,
        port: Int = 853,
        bootstrapAddresses: List<InetAddress>? = null,
        protectSocket: ((Socket) -> Boolean)? = null,
        query: ByteArray,
        timeoutMs: Int = DNS_UPSTREAM_TIMEOUT_MS,
        edns0BufferSize: Int = DEFAULT_EDNS0_BUFFER_SIZE,
        onSocketActive: ((Closeable) -> Unit)? = null
    ): ByteArray {
        val outgoingQuery = if (edns0BufferSize > 0) {
            ExpressDnsMessageUtils.ensureEdns0(query, edns0BufferSize)
        } else {
            query
        }
        validateQuery(outgoingQuery)

        val addresses = bootstrapAddresses?.takeIf { it.isNotEmpty() }
        if (addresses.isNullOrEmpty()) {
            return querySingle(host, port, connectAddress = null, protectSocket, outgoingQuery, timeoutMs, onSocketActive)
        }

        var lastError: IOException? = null
        addresses.forEach { address ->
            try {
                return querySingle(host, port, connectAddress = address, protectSocket, outgoingQuery, timeoutMs, onSocketActive)
            } catch (e: IOException) {
                lastError = e
            }
        }
        throw lastError ?: IOException("All Bootstrap DNS addresses failed for DoT host $host")
    }

    private fun querySingle(
        host: String,
        port: Int,
        connectAddress: InetAddress?,
        protectSocket: ((Socket) -> Boolean)?,
        query: ByteArray,
        timeoutMs: Int,
        onSocketActive: ((Closeable) -> Unit)?
    ): ByteArray {
        val sslSocket = connectSocket(host, port, connectAddress, protectSocket, timeoutMs, onSocketActive)
        sslSocket.use { socket ->
            val out = BufferedOutputStream(socket.outputStream)
            out.write((query.size ushr 8) and 0xff)
            out.write(query.size and 0xff)
            out.write(query)
            out.flush()

            val input = BufferedInputStream(socket.inputStream)
            val hi = input.read()
            val lo = input.read()
            if (hi < 0 || lo < 0) throw EOFException("DoT upstream closed before response length")
            val length = (hi shl 8) or lo
            if (length <= 0 || length > MAX_DNS_MESSAGE_SIZE) {
                throw IOException("Invalid DoT response length $length")
            }
            val buffer = ByteArray(length)
            var offset = 0
            while (offset < length) {
                val read = input.read(buffer, offset, length - offset)
                if (read < 0) throw EOFException("DoT upstream closed during response")
                offset += read
            }
            if (!ExpressDnsMessageUtils.isUsableUpstreamResponse(buffer, query)) {
                throw IOException("DoT server returned invalid DNS response")
            }
            return buffer
        }
    }

    private fun validateQuery(query: ByteArray) {
        if (query.isEmpty()) throw IOException("Empty DNS query")
        if (query.size > MAX_DNS_MESSAGE_SIZE) throw IOException("DNS query too large")
    }

    private fun connectSocket(
        host: String,
        port: Int,
        connectAddress: InetAddress?,
        protectSocket: ((Socket) -> Boolean)?,
        timeoutMs: Int,
        onSocketActive: ((Closeable) -> Unit)?
    ): SSLSocket {
        val rawSocket = Socket()
        onSocketActive?.invoke(rawSocket)
        protectSocket?.invoke(rawSocket)
        rawSocket.soTimeout = timeoutMs

        try {
            val socketAddress = connectAddress?.let { InetSocketAddress(it, port) } ?: InetSocketAddress(host, port)
            rawSocket.connect(socketAddress, timeoutMs)
            val sslSocket = (SSLSocketFactory.getDefault() as SSLSocketFactory)
                .createSocket(rawSocket, host, port, true) as SSLSocket
            onSocketActive?.invoke(sslSocket)
            sslSocket.soTimeout = timeoutMs
            sslSocket.sslParameters = sslSocket.sslParameters.apply {
                endpointIdentificationAlgorithm = "HTTPS"
                serverNames = listOf(SNIHostName(host))
            }
            sslSocket.startHandshake()
            return sslSocket
        } catch (e: Exception) {
            runCatching { rawSocket.close() }
            if (e is IOException) throw e
            throw IOException(e)
        }
    }
}
