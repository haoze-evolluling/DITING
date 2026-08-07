package com.haoze.dnssr.vpn

import android.net.VpnService
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
import java.net.Socket
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * 使用 RFC 8484 DNS-over-HTTPS（DoH）解析 DNS 查询。
 *
 * @param dohUrl DoH 服务器地址，例如 https://cloudflare-dns.com/dns-query
 * @param bootstrapSelector 可选的全局 Bootstrap 选择器。若启用，会使用 Bootstrap DNS
 *                          解析 DoH 域名，避免在 VPN 运行期间解析 DoH 域名造成循环。
 */
class DohResolver(
    private val vpnService: VpnService,
    dohUrl: String,
    private val bootstrapSelector: BootstrapSelector? = null
) : DnsResolver {
    private val dohHttpUrl = dohUrl.toHttpUrl()
    private val baseClient: OkHttpClient
    private val clientCacheLock = Any()
    private val bootstrapClientCache = LinkedHashMap<String, OkHttpClient>()

    init {
        val builder = OkHttpClient.Builder()
            .connectTimeout(DNS_UPSTREAM_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
            .readTimeout(DNS_UPSTREAM_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
            .callTimeout(DNS_UPSTREAM_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
            .connectionSpecs(listOf(ConnectionSpec.MODERN_TLS))

        // 让 OkHttp 的 socket 绕过 VPN，避免 DoH 请求被本应用再次拦截。
        builder.socketFactory(object : javax.net.SocketFactory() {
            private val delegate = javax.net.SocketFactory.getDefault()
            override fun createSocket(): Socket {
                return delegate.createSocket().also { vpnService.protect(it) }
            }

            override fun createSocket(host: String?, port: Int): Socket {
                return delegate.createSocket(host, port).also { vpnService.protect(it) }
            }

            override fun createSocket(host: String?, port: Int, localHost: InetAddress?, localPort: Int): Socket {
                return delegate.createSocket(host, port, localHost, localPort).also { vpnService.protect(it) }
            }

            override fun createSocket(host: InetAddress?, port: Int): Socket {
                return delegate.createSocket(host, port).also { vpnService.protect(it) }
            }

            override fun createSocket(address: InetAddress?, port: Int, localAddress: InetAddress?, localPort: Int): Socket {
                return delegate.createSocket(address, port, localAddress, localPort).also { vpnService.protect(it) }
            }
        })

        baseClient = builder.build()
    }

    /**
     * 同步解析 DNS 查询，返回 wire-format 的 DNS 响应。
     */
    override suspend fun resolve(query: ByteArray): ByteArray {
        val selector = bootstrapSelector
        return if (selector == null) {
            resolveOnce(query, bootstrapAddresses = null)
        } else {
            val addresses = selector.resolveHost(dohHttpUrl.host)
            resolveOnce(query, bootstrapAddresses = addresses.takeIf { it.isNotEmpty() })
        }
    }

    private suspend fun resolveOnce(query: ByteArray, bootstrapAddresses: List<InetAddress>?): ByteArray = suspendCancellableCoroutine { continuation ->
        val request = Request.Builder()
            .url(dohHttpUrl)
            .post(query.toRequestBody(DNS_MEDIA_TYPE))
            .header("Accept", DNS_MEDIA_TYPE.toString())
            .header("Content-Type", DNS_MEDIA_TYPE.toString())
            .build()

        val call = clientForBootstrap(bootstrapAddresses).newCall(request)
        continuation.invokeOnCancellation { call.cancel() }

        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) {
                    runCatching { continuation.resumeWithException(e) }
                }
            }

            override fun onResponse(call: Call, response: Response) {
                response.use { r ->
                    if (!continuation.isActive) return

                    val body = r.body
                    if (!r.isSuccessful || body == null) {
                        if (continuation.isActive) {
                            runCatching { continuation.resumeWithException(IOException("DNS upstream HTTP ${r.code}")) }
                        }
                        return
                    }

                    try {
                        val bytes = body.bytes()
                        if (continuation.isActive) {
                            runCatching { continuation.resume(bytes) }
                        }
                    } catch (e: IOException) {
                        if (continuation.isActive) {
                            runCatching { continuation.resumeWithException(e) }
                        }
                    }
                }
            }
        })
    }

    private fun clientForBootstrap(bootstrapAddresses: List<InetAddress>?): OkHttpClient {
        val addresses = bootstrapAddresses?.takeIf { it.isNotEmpty() } ?: return baseClient
        val cacheKey = addresses.joinToString(separator = ",") { it.hostAddress ?: it.hostName }
        synchronized(clientCacheLock) {
            bootstrapClientCache[cacheKey]?.let { return it }
            val client = baseClient.newBuilder()
                .dns(object : Dns {
                    override fun lookup(hostname: String): List<InetAddress> {
                        return if (hostname.equals(dohHttpUrl.host, ignoreCase = true)) {
                            addresses
                        } else {
                            Dns.SYSTEM.lookup(hostname)
                        }
                    }
                })
                .build()
            if (bootstrapClientCache.size >= MAX_BOOTSTRAP_CLIENTS) {
                val firstKey = bootstrapClientCache.keys.firstOrNull()
                if (firstKey != null) {
                    bootstrapClientCache.remove(firstKey)
                }
            }
            bootstrapClientCache[cacheKey] = client
            return client
        }
    }

    companion object {
        private val DNS_MEDIA_TYPE = "application/dns-message".toMediaType()
        private const val MAX_BOOTSTRAP_CLIENTS = 4
    }
}
