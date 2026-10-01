package com.haoze.diting.dnsmode.backend

import android.util.Log
import com.haoze.diting.dnsmode.model.DnsModeConfig
import com.haoze.diting.dnsmode.model.DnsModeProtocol
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import com.haoze.diting.vpn.BlockResponseMode
import com.haoze.diting.vpn.DnsMessageUtils
import com.haoze.diting.vpn.DnsRewriteMessage
import com.haoze.diting.vpn.PlainDnsTransport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.TimeUnit
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Lightweight pure-Kotlin coroutine DNS server.
 * Binds on 0.0.0.0 (UDP/TCP) to accept LAN queries and forwards to upstream resolvers.
 */
class DnsServerEngine(
    @Volatile private var config: DnsModeConfig,
    @Volatile private var upstream: DnsUpstreamServer,
    private val onQueryProcessed: ((cacheHit: Boolean, blocked: Boolean, failed: Boolean, latencyMs: Long) -> Unit)? = null,
    private val queryFilter: DnsQueryFilter? = null
) {
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var udpChannel: java.nio.channels.DatagramChannel? = null
    private var tcpServerSocket: ServerSocket? = null

    @Volatile
    private var isRunning: Boolean = false

    val isEngineRunning: Boolean get() = isRunning

    // Access-ordered LRU: hits reinsert the entry, evicting the least recently
    // used one once MAX_CACHE_ENTRIES is reached. All access must hold the lock.
    private val cache = object : LinkedHashMap<String, CacheEntry>(CACHE_INITIAL_CAPACITY, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, CacheEntry>): Boolean {
            return size > MAX_CACHE_ENTRIES
        }
    }

    private val dohClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .build()

    private data class CacheEntry(
        val response: ByteArray,
        val insertedAtEpochMs: Long,
        val ttlSeconds: Long
    )

    @Synchronized
    fun start(): Boolean {
        if (isRunning) return true
        val port = config.localListenPort
        return try {
            val udp = java.nio.channels.DatagramChannel.open(java.net.StandardProtocolFamily.INET).apply {
                configureBlocking(true)
                socket().reuseAddress = true
                bind(InetSocketAddress(InetAddress.getByName("0.0.0.0"), port))
            }
            udpChannel = udp

            val tcp = java.nio.channels.ServerSocketChannel.open().socket().apply {
                reuseAddress = true
                bind(InetSocketAddress(InetAddress.getByName("0.0.0.0"), port))
            }
            tcpServerSocket = tcp

            scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            isRunning = true

            startUdpListener(udp)
            startTcpListener(tcp)
            safeLogI(TAG, "DNS server successfully listening on 0.0.0.0:$port (UDP & TCP)")
            true
        } catch (e: Exception) {
            safeLogE(TAG, "Failed to bind DNS server socket on port $port", e)
            stop()
            false
        }
    }

    @Synchronized
    fun stop() {
        isRunning = false
        runCatching { udpChannel?.close() }
        udpChannel = null
        runCatching { tcpServerSocket?.close() }
        tcpServerSocket = null
        scope.cancel()
        synchronized(cache) { cache.clear() }
        safeLogI(TAG, "DNS server stopped")
    }

    /**
     * Applies a config/upstream change. Returns whether the engine is running
     * afterwards; a failed port-change restart surfaces as false so the caller
     * can stop the service instead of reporting RUNNING with a dead engine.
     */
    @Synchronized
    fun updateConfig(newConfig: DnsModeConfig, newUpstream: DnsUpstreamServer): Boolean {
        val portChanged = newConfig.localListenPort != config.localListenPort
        config = newConfig
        upstream = newUpstream
        if (portChanged && isRunning) {
            safeLogI(TAG, "Port changed to ${newConfig.localListenPort}, restarting DNS server")
            stop()
            return start()
        }
        return isRunning
    }

    private fun startUdpListener(channel: java.nio.channels.DatagramChannel) {
        scope.launch {
            safeLogI(TAG, "UDP listener loop active on port ${config.localListenPort}")
            val buffer = java.nio.ByteBuffer.allocate(4096)
            while (isActive && isRunning && channel.isOpen) {
                try {
                    buffer.clear()
                    val clientAddress = channel.receive(buffer) ?: continue
                    buffer.flip()
                    val queryBytes = ByteArray(buffer.remaining())
                    buffer.get(queryBytes)

                    if (config.logQueries) {
                        safeLogI(TAG, "Received UDP query (${queryBytes.size} bytes) from $clientAddress")
                    }

                    launch {
                        val responseBytes = processQuery(queryBytes)
                        if (responseBytes != null && channel.isOpen) {
                            runCatching {
                                channel.send(java.nio.ByteBuffer.wrap(responseBytes), clientAddress)
                                if (config.logQueries) {
                                    safeLogI(TAG, "Sent UDP reply (${responseBytes.size} bytes) to $clientAddress")
                                }
                            }.onFailure { safeLogW(TAG, "Failed to send UDP reply to $clientAddress", it) }
                        }
                    }
                } catch (e: Exception) {
                    if (isRunning && channel.isOpen) {
                        safeLogW(TAG, "UDP receive error: ${e.message}")
                    }
                }
            }
        }
    }

    private fun startTcpListener(serverSocket: ServerSocket) {
        scope.launch {
            while (isActive && isRunning && !serverSocket.isClosed) {
                try {
                    val client = serverSocket.accept()
                    launch {
                        handleTcpClient(client)
                    }
                } catch (e: Exception) {
                    if (isRunning && !serverSocket.isClosed) {
                        safeLogW(TAG, "TCP accept error: ${e.message}")
                    }
                }
            }
        }
    }

    private fun handleTcpClient(socket: Socket) {
        socket.use { s ->
            s.soTimeout = 5000
            val input = BufferedInputStream(s.getInputStream())
            val output = BufferedOutputStream(s.getOutputStream())
            while (isRunning && !s.isClosed) {
                val high = input.read()
                if (high < 0) break
                val low = input.read()
                if (low < 0) break
                val length = (high shl 8) or low
                if (length <= 0 || length > 65535) break
                val queryBytes = ByteArray(length)
                var readBytes = 0
                while (readBytes < length) {
                    val r = input.read(queryBytes, readBytes, length - readBytes)
                    if (r < 0) break
                    readBytes += r
                }
                if (readBytes != length) break

                val response = processQuery(queryBytes)
                if (response != null) {
                    output.write((response.size ushr 8) and 0xFF)
                    output.write(response.size and 0xFF)
                    output.write(response)
                    output.flush()
                }
            }
        }
    }

    internal fun processQuery(query: ByteArray): ByteArray? {
        val startTime = System.currentTimeMillis()
        val question = DnsMessageUtils.extractQuestion(query)
            ?: return DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.REFUSED)

        val currentConfig = config

        // Malicious-domain filtering uses the DNS mode's isolated rule database;
        // blocked answers are policy decisions, so they are never cached.
        val filter = queryFilter
        if (currentConfig.adBlockEnabled && filter != null && filter.isBlocked(question.name)) {
            val elapsed = (System.currentTimeMillis() - startTime).coerceAtLeast(1L)
            if (currentConfig.logQueries) {
                safeLogI(TAG, "Blocked: ${question.name} (type ${question.type})")
            }
            onQueryProcessed?.invoke(false, true, false, elapsed)
            return DnsMessageUtils.buildBlockedResponse(query, filter.blockResponseMode)
        }

        // Hosts / rewrite answers are resolution features and stay active
        // regardless of the filtering master switch; like block responses they
        // are computed per query and never cached.
        if (filter != null) {
            val rewriteAnswers = filter.rewriteAnswersFor(question.name)
            val rewriteResponse = if (rewriteAnswers.isEmpty()) null else {
                DnsRewriteMessage.buildResponse(query, rewriteAnswers)
            }
            if (rewriteResponse != null) {
                val elapsed = (System.currentTimeMillis() - startTime).coerceAtLeast(1L)
                if (currentConfig.logQueries) {
                    safeLogI(TAG, "Rewrite: ${question.name} (type ${question.type})")
                }
                onQueryProcessed?.invoke(false, false, false, elapsed)
                return rewriteResponse
            }
        }

        // QCLASS and the DNSSEC OK bit are part of the answer's identity; a
        // cached entry for one combination must not be served to another.
        val cacheKey = "${question.name}|${question.type}|${question.qclass}|${question.dnssecOk}"

        if (currentConfig.cacheEnabled) {
            val cached: CacheEntry? = synchronized(cache) { cache[cacheKey] }
            if (cached != null) {
                val now = System.currentTimeMillis()
                val cachedSeconds = ((now - cached.insertedAtEpochMs) / 1000L).toInt()
                if (cachedSeconds < cached.ttlSeconds) {
                    val patched = DnsMessageUtils.patchResponseTtl(cached.response, cachedSeconds)
                    if (patched != null) {
                        val finalResponse = DnsMessageUtils.withTransactionId(patched, query)
                        val elapsed = (System.currentTimeMillis() - startTime).coerceAtLeast(1L)
                        if (currentConfig.logQueries) {
                            safeLogI(TAG, "Cache HIT: ${question.name} (type ${question.type}) in ${elapsed}ms")
                        }
                        onQueryProcessed?.invoke(true, false, false, elapsed)
                        return finalResponse
                    }
                }
                synchronized(cache) { cache.remove(cacheKey) }
            }
        }

        if (currentConfig.logQueries) {
            safeLogI(TAG, "Resolving: ${question.name} (type ${question.type}) via ${upstream.name} (${upstream.address})")
        }
        return try {
            val upstreamResponse = queryUpstream(query)
            val finalResponse = DnsMessageUtils.withTransactionId(upstreamResponse, query)
            val elapsed = (System.currentTimeMillis() - startTime).coerceAtLeast(1L)

            if (currentConfig.cacheEnabled && DnsMessageUtils.isSuccessResponse(finalResponse)) {
                val minTtl = DnsMessageUtils.cacheLifetimeSeconds(finalResponse)
                val effectiveTtl = if (minTtl > 0) {
                    minTtl.coerceIn(10L, currentConfig.cacheTtlSeconds.toLong())
                } else {
                    currentConfig.cacheTtlSeconds.toLong()
                }
                synchronized(cache) {
                    cache[cacheKey] = CacheEntry(finalResponse, System.currentTimeMillis(), effectiveTtl)
                }
            }

            if (currentConfig.logQueries) {
                safeLogI(TAG, "Resolved: ${question.name} via ${upstream.name} in ${elapsed}ms")
            }
            onQueryProcessed?.invoke(false, false, false, elapsed)
            finalResponse
        } catch (e: Exception) {
            safeLogW(TAG, "Upstream DNS query failed for ${question.name}: ${e.message}")
            val elapsed = (System.currentTimeMillis() - startTime).coerceAtLeast(1L)
            onQueryProcessed?.invoke(false, false, true, elapsed)
            // SERVFAIL tells the client the failure is transient; REFUSED would
            // be read as a definitive policy answer and suppress retries.
            DnsMessageUtils.buildServfailResponse(query)
        }
    }

    private fun queryUpstream(query: ByteArray): ByteArray {
        val currentUpstream = upstream
        return when (currentUpstream.protocol) {
            DnsModeProtocol.UDP -> queryPlainDns(currentUpstream, query)
            DnsModeProtocol.TCP -> queryTcpOrDot(currentUpstream.address, currentUpstream.port, isTls = false, query = query)
            DnsModeProtocol.DOT -> queryTcpOrDot(currentUpstream.address, currentUpstream.port, isTls = true, query = query)
            DnsModeProtocol.DOH -> queryDoh(currentUpstream.address, query)
        }
    }

    private fun queryPlainDns(upstreamServer: DnsUpstreamServer, query: ByteArray): ByteArray {
        val addresses = InetAddress.getAllByName(upstreamServer.address).toList()
        return PlainDnsTransport.query(
            addresses = addresses,
            port = upstreamServer.port,
            protectDatagramSocket = null,
            protectTcpSocket = null,
            query = query
        )
    }

    private fun queryTcpOrDot(address: String, port: Int, isTls: Boolean, query: ByteArray): ByteArray {
        // Created unconnected so the connect below has an explicit timeout; a
        // bare createSocket(address, port) blocks until the system default
        // connect timeout elapses.
        val socket = if (isTls) {
            (SSLSocketFactory.getDefault().createSocket() as SSLSocket).apply {
                val params = sslParameters
                params.endpointIdentificationAlgorithm = "HTTPS"
                params.serverNames = listOf(SNIHostName(address))
                sslParameters = params
            }
        } else {
            Socket()
        }
        socket.use { s ->
            s.tcpNoDelay = true
            s.connect(InetSocketAddress(address, port), CONNECT_TIMEOUT_MS)
            if (isTls) (s as SSLSocket).startHandshake()
            s.soTimeout = 5000
            val output = BufferedOutputStream(s.outputStream)
            output.write((query.size ushr 8) and 0xFF)
            output.write(query.size and 0xFF)
            output.write(query)
            output.flush()

            val input = BufferedInputStream(s.inputStream)
            val high = input.read()
            val low = input.read()
            if (high < 0 || low < 0) throw EOFException("Incomplete upstream response")
            val length = (high shl 8) or low
            if (length == 0) throw IOException("Empty upstream response")
            val response = ByteArray(length)
            var offset = 0
            while (offset < length) {
                val read = input.read(response, offset, length - offset)
                if (read < 0) throw EOFException("Incomplete upstream response")
                offset += read
            }
            return response
        }
    }

    private fun queryDoh(url: String, query: ByteArray): ByteArray {
        val mediaType = "application/dns-message".toMediaType()
        val request = Request.Builder()
            .url(url)
            .header("Content-Type", "application/dns-message")
            .header("Accept", "application/dns-message")
            .post(query.toRequestBody(mediaType))
            .build()

        dohClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("DoH request failed with HTTP ${response.code}")
            }
            val body = response.body ?: throw IOException("Empty DoH response")
            return body.bytes()
        }
    }

    companion object {
        private const val TAG = "DnsServerEngine"
        private const val CONNECT_TIMEOUT_MS = 5000
        private const val CACHE_INITIAL_CAPACITY = 256
        private const val MAX_CACHE_ENTRIES = 4096

        private fun safeLogI(tag: String, msg: String) {
            runCatching { Log.i(tag, msg) }
        }

        private fun safeLogW(tag: String, msg: String, tr: Throwable? = null) {
            runCatching {
                if (tr != null) Log.w(tag, msg, tr) else Log.w(tag, msg)
            }
        }

        private fun safeLogE(tag: String, msg: String, tr: Throwable? = null) {
            runCatching {
                if (tr != null) Log.e(tag, msg, tr) else Log.e(tag, msg)
            }
        }
    }
}
