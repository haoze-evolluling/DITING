package com.haoze.dnssr.vpn

import android.net.VpnService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * DNS-over-TLS resolver using strict TLS hostname validation.
 */
class DotResolver(
    private val vpnService: VpnService,
    private val host: String,
    private val port: Int = DnsProvider.DEFAULT_DOT_PORT,
    private val bootstrapSelector: BootstrapSelector? = null
) : DnsResolver {
    private val nextConnection = AtomicInteger(0)
    private val connections = List(CONNECTION_POOL_SIZE) {
        DotPersistentConnection(host = host, port = port)
    }

    override suspend fun resolve(query: ByteArray): ByteArray = withContext(Dispatchers.IO) {
        val selector = bootstrapSelector
        if (selector == null) {
            queryWithBootstrap(query, bootstrapAddresses = null)
        } else {
            val addresses = selector.resolveHost(host)
            queryWithBootstrap(query, bootstrapAddresses = addresses.takeIf { it.isNotEmpty() })
        }
    }

    override fun close() {
        connections.forEach { it.close() }
    }

    private fun queryWithBootstrap(query: ByteArray, bootstrapAddresses: List<InetAddress>?): ByteArray {
        val index = Math.floorMod(nextConnection.getAndIncrement(), connections.size)
        return connections[index].query(
            bootstrapAddresses = bootstrapAddresses,
            protectSocket = { socket -> vpnService.protect(socket) },
            query = query
        )
    }

    companion object {
        private const val CONNECTION_POOL_SIZE = 2
    }
}

private class DotPersistentConnection(
    private val host: String,
    private val port: Int
) {
    private var socket: SSLSocket? = null
    private var input: BufferedInputStream? = null
    private var output: BufferedOutputStream? = null
    private var targetKey: String? = null

    fun query(
        bootstrapAddresses: List<InetAddress>?,
        protectSocket: ((Socket) -> Boolean)?,
        query: ByteArray
    ): ByteArray = synchronized(this) {
        DotTlsIo.validateQuery(query)
        val key = targetKey(bootstrapAddresses)
        try {
            ensureConnected(bootstrapAddresses, protectSocket, key)
            writeDnsQuery(query)
            readDnsResponse()
        } catch (e: IOException) {
            closeLocked()
            ensureConnected(bootstrapAddresses, protectSocket, key)
            writeDnsQuery(query)
            readDnsResponse()
        }
    }

    fun close() = synchronized(this) {
        closeLocked()
    }

    private fun ensureConnected(
        bootstrapAddresses: List<InetAddress>?,
        protectSocket: ((Socket) -> Boolean)?,
        key: String
    ) {
        val current = socket
        if (current != null && current.isConnected && !current.isClosed && targetKey == key) {
            return
        }
        closeLocked()

        val addresses = bootstrapAddresses?.takeIf { it.isNotEmpty() }
        if (addresses.isNullOrEmpty()) {
            connect(connectAddress = null, protectSocket = protectSocket, key = key)
            return
        }

        var lastError: IOException? = null
        addresses.forEach { address ->
            try {
                connect(connectAddress = address, protectSocket = protectSocket, key = key)
                return
            } catch (e: IOException) {
                lastError = e
                closeLocked()
            }
        }
        throw lastError ?: IOException("All Bootstrap DNS addresses failed")
    }

    private fun connect(
        connectAddress: InetAddress?,
        protectSocket: ((Socket) -> Boolean)?,
        key: String
    ) {
        val sslSocket = DotTlsIo.connectSocket(host, port, connectAddress, protectSocket)
        socket = sslSocket
        input = BufferedInputStream(sslSocket.inputStream)
        output = BufferedOutputStream(sslSocket.outputStream)
        targetKey = key
    }

    private fun writeDnsQuery(query: ByteArray) {
        val out = output ?: throw IOException("DoT connection is not open")
        DotTlsIo.writeDnsQuery(out, query)
    }

    private fun readDnsResponse(): ByteArray {
        val input = input ?: throw IOException("DoT connection is not open")
        return DotTlsIo.readDnsResponse(input)
    }

    private fun closeLocked() {
        runCatching { socket?.close() }
        socket = null
        input = null
        output = null
        targetKey = null
    }

    private fun targetKey(bootstrapAddresses: List<InetAddress>?): String {
        val addresses = bootstrapAddresses?.takeIf { it.isNotEmpty() }
            ?: return "host:$host:$port"
        return addresses.joinToString(separator = ",", prefix = "bootstrap:") { it.hostAddress ?: it.hostName }
    }

}

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
