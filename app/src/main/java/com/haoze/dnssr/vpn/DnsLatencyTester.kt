package com.haoze.dnssr.vpn

import okhttp3.Call
import okhttp3.Callback
import okhttp3.ConnectionSpec
import okhttp3.Dns
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import kotlin.math.roundToLong

/**
 * Measures the real-world query latency of encrypted DNS providers.
 *
 * Does not depend on VpnService: it sends a single A-record DNS query directly
 * to the given provider and measures the round-trip time. The app's own
 * traffic is excluded from the VPN (addDisallowedApplication) and uses the
 * Bootstrap DNS, so no request loop can form.
 */
object DnsLatencyTester {

    private val DNS_MEDIA_TYPE = "application/dns-message".toMediaType()

    data class Result(
        val providerId: String,
        val providerName: String,
        val protocol: DnsProtocol,
        val elapsedMs: Long,
        val success: Boolean,
        val message: String? = null,
        val attempts: Int = 1,
        val successCount: Int = if (success) 1 else 0,
        val elapsedSamplesMs: List<Long> = if (success) listOf(elapsedMs) else emptyList()
    )

    /**
     * Tests the actual latency of resolving [domain] on the given provider.
     *
     * @return always a [Result]; [Result.success] is true when a successful
     *   DNS response was received.
     */
    suspend fun test(
        context: android.content.Context,
        provider: DnsProvider,
        domain: String,
        bootstrapSelector: BootstrapSelector? = null
    ): Result {
        val query = DnsMessageUtils.buildQuery(domain, qtype = 1)
        return when (provider.protocol) {
            DnsProtocol.DNS -> testPlainDns(provider, query, bootstrapSelector)
            DnsProtocol.DOH -> testDoh(provider, query, bootstrapSelector)
            DnsProtocol.DOT -> testDot(provider, query, bootstrapSelector)
        }
    }

    /**
     * Runs several real DNS queries against the same provider in a row and
     * returns the average latency of the successful samples.
     *
     * If every attempt fails, the last failure result is returned; if some
     * attempts succeed, the test counts as successful and the message notes
     * how many attempts succeeded.
     */
    suspend fun testAverage(
        context: android.content.Context,
        provider: DnsProvider,
        domain: String,
        attempts: Int = DEFAULT_ATTEMPTS,
        bootstrapSelector: BootstrapSelector? = null
    ): Result {
        val safeAttempts = attempts.coerceAtLeast(1)
        val results = (1..safeAttempts).map {
            test(context, provider, domain, bootstrapSelector)
        }
        val successful = results.filter { it.success }
        if (successful.isNotEmpty()) {
            val samples = successful.map { it.elapsedMs }
            return Result(
                providerId = provider.id,
                providerName = provider.name,
                protocol = provider.protocol,
                elapsedMs = samples.average().roundToLong().coerceAtLeast(1L),
                success = true,
                message = if (successful.size == safeAttempts) {
                    null
                } else {
                    "${successful.size}/$safeAttempts 次成功"
                },
                attempts = safeAttempts,
                successCount = successful.size,
                elapsedSamplesMs = samples
            )
        }

        val last = results.last()
        return last.copy(
            attempts = safeAttempts,
            successCount = 0,
            elapsedSamplesMs = emptyList()
        )
    }

    private suspend fun testDoh(
        provider: DnsProvider,
        query: ByteArray,
        bootstrapSelector: BootstrapSelector?
    ): Result {
        val httpUrl = provider.url.toHttpUrl()

        val builder = OkHttpClient.Builder()
            .connectTimeout(DNS_UPSTREAM_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
            .readTimeout(DNS_UPSTREAM_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
            .callTimeout(DNS_UPSTREAM_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
            .connectionSpecs(listOf(ConnectionSpec.MODERN_TLS))

        fun clientForBootstrap(bootstrapAddresses: List<InetAddress>?): OkHttpClient {
            val addresses = bootstrapAddresses?.takeIf { it.isNotEmpty() } ?: return builder.build()
            return builder
                .dns(object : Dns {
                override fun lookup(hostname: String): List<InetAddress> {
                    return if (hostname.equals(httpUrl.host, ignoreCase = true)) {
                            addresses
                    } else {
                        Dns.SYSTEM.lookup(hostname)
                    }
                }
                })
                .build()
        }

        val request = Request.Builder()
            .url(httpUrl)
            .post(query.toRequestBody(DNS_MEDIA_TYPE))
            .header("Accept", DNS_MEDIA_TYPE.toString())
            .header("Content-Type", DNS_MEDIA_TYPE.toString())
            .build()

        val start = System.currentTimeMillis()
        return try {
            val response = if (bootstrapSelector == null) {
                clientForBootstrap(null).newCall(request).await()
            } else {
                val addresses = bootstrapSelector.resolveHost(httpUrl.host)
                clientForBootstrap(addresses.takeIf { it.isNotEmpty() }).newCall(request).await()
            }
            val elapsed = System.currentTimeMillis() - start
            response.use { r ->
                val body = r.body?.bytes()
                val dnsSuccess = body != null && DnsMessageUtils.isSuccessResponse(body)
                Result(
                    providerId = provider.id,
                    providerName = provider.name,
                    protocol = provider.protocol,
                    elapsedMs = elapsed,
                    success = dnsSuccess && r.isSuccessful,
                    message = if (dnsSuccess && r.isSuccessful) null else "HTTP ${r.code}"
                )
            }
        } catch (e: Exception) {
            Result(
                providerId = provider.id,
                providerName = provider.name,
                protocol = provider.protocol,
                elapsedMs = System.currentTimeMillis() - start,
                success = false,
                message = e.message
            )
        }
    }

    private suspend fun testDot(
        provider: DnsProvider,
        query: ByteArray,
        bootstrapSelector: BootstrapSelector?
    ): Result {
        val start = System.currentTimeMillis()
        return try {
            val response = if (bootstrapSelector == null) {
                queryDot(provider, query, bootstrapAddresses = null)
            } else {
                val addresses = bootstrapSelector.resolveHost(provider.host)
                queryDot(provider, query, addresses.takeIf { it.isNotEmpty() })
            }
            val elapsed = System.currentTimeMillis() - start
            Result(
                providerId = provider.id,
                providerName = provider.name,
                protocol = provider.protocol,
                elapsedMs = elapsed,
                success = DnsMessageUtils.isSuccessResponse(response),
                message = null
            )
        } catch (e: Exception) {
            Result(
                providerId = provider.id,
                providerName = provider.name,
                protocol = provider.protocol,
                elapsedMs = System.currentTimeMillis() - start,
                success = false,
                message = e.message
            )
        }
    }

    private suspend fun testPlainDns(
        provider: DnsProvider,
        query: ByteArray,
        bootstrapSelector: BootstrapSelector?
    ): Result {
        val start = System.currentTimeMillis()
        return try {
            val addresses = if (DnsProvider.isIpLiteral(provider.host)) {
                listOf(InetAddress.getByName(provider.host))
            } else {
                bootstrapSelector?.resolveHost(provider.host)?.takeIf { it.isNotEmpty() }
                    ?: InetAddress.getAllByName(provider.host).toList()
            }
            val response = PlainDnsTransport.query(addresses, provider.port, null, null, query)
            Result(provider.id, provider.name, provider.protocol, System.currentTimeMillis() - start,
                DnsMessageUtils.isSuccessResponse(response))
        } catch (e: Exception) {
            Result(provider.id, provider.name, provider.protocol, System.currentTimeMillis() - start,
                false, e.message)
        }
    }

    private fun queryDot(provider: DnsProvider, query: ByteArray, bootstrapAddresses: List<InetAddress>?): ByteArray {
        return DotTransport.query(
            host = provider.host,
            port = provider.port,
            bootstrapAddresses = bootstrapAddresses,
            protectSocket = null,
            query = query
        )
    }

    private suspend fun Call.await(): Response = suspendCoroutine { continuation ->
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                continuation.resume(response)
            }
        })
    }

    private const val DEFAULT_ATTEMPTS = 3
}
