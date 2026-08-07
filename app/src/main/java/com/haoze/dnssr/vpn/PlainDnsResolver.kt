package com.haoze.dnssr.vpn

import android.net.VpnService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/** Traditional DNS resolver: UDP first, with TCP retry for truncated responses. */
class PlainDnsResolver(
    private val vpnService: VpnService,
    private val host: String,
    private val port: Int = DnsProvider.DEFAULT_DNS_PORT,
    private val bootstrapSelector: BootstrapSelector? = null
) : DnsResolver {
    override suspend fun resolve(query: ByteArray): ByteArray = withContext(Dispatchers.IO) {
        val addresses = if (DnsProvider.isIpLiteral(host)) {
            listOf(InetAddress.getByName(host))
        } else {
            bootstrapSelector?.resolveHost(host)?.takeIf { it.isNotEmpty() }
                ?: InetAddress.getAllByName(host).toList()
        }
        PlainDnsTransport.query(
            addresses = addresses,
            port = port,
            protectDatagramSocket = { vpnService.protect(it) },
            protectTcpSocket = { vpnService.protect(it) },
            query = query
        )
    }
}

object PlainDnsTransport {
    fun query(
        addresses: List<InetAddress>,
        port: Int,
        protectDatagramSocket: ((DatagramSocket) -> Boolean)?,
        protectTcpSocket: ((Socket) -> Boolean)?,
        query: ByteArray
    ): ByteArray {
        require(addresses.isNotEmpty()) { "DNS server address is unavailable" }
        var lastError: IOException? = null
        addresses.forEach { address ->
            try {
                val response = queryUdp(address, port, protectDatagramSocket, query)
                val resolved = if (DnsMessageUtils.isTruncatedResponse(response)) {
                    queryTcp(address, port, protectTcpSocket, query)
                } else {
                    response
                }
                if (!DnsMessageUtils.isUsableUpstreamResponse(resolved, query)) {
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
        query: ByteArray
    ): ByteArray {
        DatagramSocket().use { socket ->
            if (protectSocket != null && !protectSocket(socket)) {
                throw IOException("Failed to protect DNS UDP socket")
            }
            socket.soTimeout = DNS_UPSTREAM_TIMEOUT_MS
            socket.connect(InetSocketAddress(address, port))
            socket.send(DatagramPacket(query, query.size))
            val buffer = ByteArray(MAX_DNS_PACKET_SIZE)
            val response = DatagramPacket(buffer, buffer.size)
            socket.receive(response)
            return buffer.copyOf(response.length)
        }
    }

    private fun queryTcp(
        address: InetAddress,
        port: Int,
        protectSocket: ((Socket) -> Boolean)?,
        query: ByteArray
    ): ByteArray {
        Socket().use { socket ->
            if (protectSocket != null && !protectSocket(socket)) {
                throw IOException("Failed to protect DNS TCP socket")
            }
            socket.soTimeout = DNS_UPSTREAM_TIMEOUT_MS
            socket.connect(InetSocketAddress(address, port), DNS_UPSTREAM_TIMEOUT_MS)
            val output = BufferedOutputStream(socket.outputStream)
            output.write(query.size ushr 8)
            output.write(query.size and 0xFF)
            output.write(query)
            output.flush()

            val input = BufferedInputStream(socket.inputStream)
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

    private const val MAX_DNS_PACKET_SIZE = 65_535
}
