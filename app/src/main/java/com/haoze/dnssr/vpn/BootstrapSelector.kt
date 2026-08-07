package com.haoze.dnssr.vpn

import android.content.Context
import com.haoze.dnssr.ui.AppSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.max
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

class BootstrapSelector(
    private val context: Context,
    private val healthEngine: BootstrapHealthEngine,
    private val logger: BootstrapLogger? = null,
    private val protectDatagramSocket: ((DatagramSocket) -> Boolean)? = null
) {
    private val cacheLock = Any()
    private val hostCache = HashMap<String, CachedBootstrapResolution>()

    suspend fun resolveHost(host: String): List<InetAddress> = withContext(Dispatchers.IO) {
        val entries = AppSettings.loadEnabledBootstrapIpEntries(context)
        if (!AppSettings.isBootstrapEnabled(context) || entries.isEmpty()) {
            return@withContext emptyList()
        }
        val normalizedHost = host.lowercase()
        val sourceKey = entries.joinToString(separator = "|") { "${it.id}:${it.ip}" }
        getCached(normalizedHost, sourceKey)?.let { return@withContext it }

        val plan = healthEngine.choosePlan(entries)
        val orderedIndices = buildList {
            if (plan.primaryIndex in entries.indices) add(plan.primaryIndex)
            plan.fallbackIndices.forEach { index ->
                if (index in entries.indices && index !in this) add(index)
            }
        }
        if (orderedIndices.isEmpty()) return@withContext emptyList()

        var lastError: Throwable? = null
        orderedIndices.forEachIndexed { attemptIndex, entryIndex ->
            val entry = entries[entryIndex]
            val startedAt = System.nanoTime()
            try {
                val result = resolveWithBootstrapDns(host, entry.ip)
                if (result.isEmpty()) {
                    throw IOException("Bootstrap DNS returned no A/AAAA records")
                }
                val elapsedMs = max(1L, (System.nanoTime() - startedAt) / 1_000_000L)
                healthEngine.recordResult(entry.id, success = true, elapsedMs = elapsedMs)
                logger?.log(
                    ipId = entry.id,
                    ipName = entry.name,
                    ip = entry.ip,
                    host = host,
                    success = true,
                    elapsedMs = elapsedMs,
                    fallbackUsed = attemptIndex > 0,
                    message = "exploration".takeIf { plan.exploration && attemptIndex == 0 }
                )
                putCached(normalizedHost, sourceKey, result)
                return@withContext result
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                removeCached(normalizedHost)
                val elapsedMs = max(1L, (System.nanoTime() - startedAt) / 1_000_000L)
                healthEngine.recordResult(entry.id, success = false, elapsedMs = elapsedMs)
                logger?.log(
                    ipId = entry.id,
                    ipName = entry.name,
                    ip = entry.ip,
                    host = host,
                    success = false,
                    elapsedMs = elapsedMs,
                    fallbackUsed = attemptIndex > 0,
                    message = e.message
                )
                lastError = e
            }
        }
        throw lastError ?: IllegalStateException("All Bootstrap DNS attempts failed")
    }

    private fun getCached(host: String, sourceKey: String): List<InetAddress>? {
        val now = System.currentTimeMillis()
        return synchronized(cacheLock) {
            val cached = hostCache[host] ?: return@synchronized null
            if (cached.sourceKey == sourceKey && now < cached.expiresAt) {
                cached.addresses
            } else {
                hostCache.remove(host)
                null
            }
        }
    }

    private fun putCached(host: String, sourceKey: String, addresses: List<InetAddress>) {
        synchronized(cacheLock) {
            hostCache[host] = CachedBootstrapResolution(
                sourceKey = sourceKey,
                expiresAt = System.currentTimeMillis() + HOST_CACHE_TTL_MS,
                addresses = addresses
            )
        }
    }

    private fun removeCached(host: String) {
        synchronized(cacheLock) {
            hostCache.remove(host)
        }
    }

    private fun resolveWithBootstrapDns(host: String, bootstrapIp: String): List<InetAddress> {
        val addresses = mutableListOf<InetAddress>()
        var lastError: Exception? = null

        listOf(DnsMessageUtils.TYPE_A, DnsMessageUtils.TYPE_AAAA).forEach { qtype ->
            try {
                val query = DnsMessageUtils.buildQuery(host, qtype)
                val response = queryUdp(bootstrapIp, query)
                addresses += DnsMessageUtils.extractAddressRecords(response)
            } catch (e: Exception) {
                lastError = e
            }
        }

        val distinct = addresses.distinctBy { it.hostAddress }
        if (distinct.isEmpty() && lastError != null) {
            throw IOException("Bootstrap DNS lookup failed for $host via $bootstrapIp", lastError)
        }
        return distinct
    }

    private fun queryUdp(bootstrapIp: String, query: ByteArray): ByteArray {
        DatagramSocket().use { socket ->
            protectDatagramSocket?.invoke(socket)
            socket.soTimeout = DNS_TIMEOUT_MS
            val server = InetAddress.getByName(bootstrapIp)
            val request = DatagramPacket(query, query.size, server, DNS_PORT)
            socket.send(request)

            val buffer = ByteArray(DNS_RESPONSE_BUFFER_SIZE)
            val response = DatagramPacket(buffer, buffer.size)
            socket.receive(response)

            val bytes = response.data.copyOf(response.length)
            if (DnsMessageUtils.transactionId(bytes) != DnsMessageUtils.transactionId(query)) {
                throw IOException("Mismatched DNS transaction ID")
            }
            if (DnsMessageUtils.isTruncatedResponse(bytes)) {
                throw IOException("Truncated DNS response")
            }
            return bytes
        }
    }

    companion object {
        private const val DNS_PORT = 53
        private const val DNS_TIMEOUT_MS = 3_000
        private const val DNS_RESPONSE_BUFFER_SIZE = 1500
        private const val HOST_CACHE_TTL_MS = 60_000L
    }
}

private data class CachedBootstrapResolution(
    val sourceKey: String,
    val expiresAt: Long,
    val addresses: List<InetAddress>
)
