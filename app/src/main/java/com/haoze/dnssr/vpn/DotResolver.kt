package com.haoze.dnssr.vpn

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

object DotTransport {
    fun query(
        host: String,
        port: Int,
        bootstrapAddresses: List<InetAddress>?,
        protectSocket: ((Socket) -> Boolean)?,
        query: ByteArray
    ): ByteArray {
        DotTlsIo.validateQuery(query)

        val addresses = bootstrapAddresses?.takeIf { it.isNotEmpty() }
        if (addresses.isNullOrEmpty()) {
            return querySingle(host, port, connectAddress = null, protectSocket, query)
        }

        var lastError: IOException? = null
        addresses.forEach { address ->
            try {
                return querySingle(host, port, connectAddress = address, protectSocket, query)
            } catch (e: IOException) {
                lastError = e
            }
        }
        throw lastError ?: IOException("All Bootstrap DNS addresses failed")
    }

    private fun querySingle(
        host: String,
        port: Int,
        connectAddress: InetAddress?,
        protectSocket: ((Socket) -> Boolean)?,
        query: ByteArray
    ): ByteArray {
        val sslSocket = DotTlsIo.connectSocket(host, port, connectAddress, protectSocket)
        sslSocket.use { socket ->
            DotTlsIo.writeDnsQuery(BufferedOutputStream(socket.outputStream), query)
            return DotTlsIo.readDnsResponse(BufferedInputStream(socket.inputStream))
        }
    }
}

private object DotTlsIo {
    private const val TIMEOUT_MS = DNS_UPSTREAM_TIMEOUT_MS
    private const val MAX_DNS_MESSAGE_SIZE = 65_535

    fun validateQuery(query: ByteArray) {
        if (query.isEmpty()) throw IOException("Empty DNS query")
        if (query.size > MAX_DNS_MESSAGE_SIZE) throw IOException("DNS query too large")
    }

    fun connectSocket(
        host: String,
        port: Int,
        connectAddress: InetAddress?,
        protectSocket: ((Socket) -> Boolean)?
    ): SSLSocket {
        val rawSocket = Socket()
        protectSocket?.invoke(rawSocket)
        rawSocket.soTimeout = TIMEOUT_MS

        try {
            val socketAddress = connectAddress?.let { InetSocketAddress(it, port) } ?: InetSocketAddress(host, port)
            rawSocket.connect(socketAddress, TIMEOUT_MS)
            val sslSocket = (SSLSocketFactory.getDefault() as SSLSocketFactory)
                .createSocket(rawSocket, host, port, true) as SSLSocket
            sslSocket.soTimeout = TIMEOUT_MS
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

    fun writeDnsQuery(output: BufferedOutputStream, query: ByteArray) {
        output.write((query.size ushr 8) and 0xff)
        output.write(query.size and 0xff)
        output.write(query)
        output.flush()
    }

    fun readDnsResponse(input: BufferedInputStream): ByteArray {
        val hi = input.read()
        val lo = input.read()
        if (hi < 0 || lo < 0) throw EOFException("DNS upstream closed before response length")
        val length = (hi shl 8) or lo
        if (length <= 0 || length > MAX_DNS_MESSAGE_SIZE) {
            throw IOException("Invalid DNS response length $length")
        }
        return input.readExact(length)
    }

    private fun BufferedInputStream.readExact(length: Int): ByteArray {
        val buffer = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val read = read(buffer, offset, length - offset)
            if (read < 0) throw EOFException("DNS upstream closed during response")
            offset += read
        }
        return buffer
    }
}
