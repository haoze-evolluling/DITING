package com.haoze.diting.express.transport

import com.haoze.diting.core.dns.DnsLatencyTester
import com.haoze.diting.express.engine.ExpressDnsMessageUtils
import com.haoze.diting.core.dns.DNS_UPSTREAM_TIMEOUT_MS
import kotlinx.coroutines.suspendCancellableCoroutine
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
import javax.net.SocketFactory
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Isolated DNS-over-HTTPS (DoH) transport for Express Mode.
 *
 * Source-level adaptation of DoH POST implementation from DnsLatencyTester.kt
 * with OkHttp, bootstrap DNS binding, socket protection, and coroutine cancellation.
 */
object ExpressDohTransport {

    private val DNS_MEDIA_TYPE = "application/dns-message".toMediaType()

    suspend fun query(
        url: String,
        bootstrapAddresses: List<InetAddress>? = null,
        protectSocket: ((Socket) -> Boolean)? = null,
        query: ByteArray,
        timeoutMs: Long = DNS_UPSTREAM_TIMEOUT_MS.toLong()
    ): ByteArray {
        val httpUrl = url.toHttpUrl()
        val builder = OkHttpClient.Builder()
            .connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .readTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .connectionSpecs(listOf(ConnectionSpec.MODERN_TLS))

        if (protectSocket != null) {
            builder.socketFactory(ExpressProtectingSocketFactory(protectSocket))
        }

        val addresses = bootstrapAddresses?.takeIf { it.isNotEmpty() }
        if (!addresses.isNullOrEmpty()) {
            builder.dns(object : Dns {
                override fun lookup(hostname: String): List<InetAddress> {
                    return if (hostname.equals(httpUrl.host, ignoreCase = true)) {
                        addresses
                    } else {
                        Dns.SYSTEM.lookup(hostname)
                    }
                }
            })
        }

        val client = builder.build()
        val request = Request.Builder()
            .url(httpUrl)
            .post(query.toRequestBody(DNS_MEDIA_TYPE))
            .header("Accept", DNS_MEDIA_TYPE.toString())
            .header("Content-Type", DNS_MEDIA_TYPE.toString())
            .build()

        val call = client.newCall(request)
        val response = call.await()
        return response.use { r ->
            if (!r.isSuccessful) {
                throw IOException("DoH HTTP error ${r.code}")
            }
            val body = r.body?.bytes() ?: throw IOException("Empty DoH response body")
            if (!ExpressDnsMessageUtils.isUsableUpstreamResponse(body, query)) {
                throw IOException("DoH server returned invalid DNS response")
            }
            body
        }
    }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation {
            cancel()
        }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) {
                    continuation.resumeWithException(e)
                }
            }

            override fun onResponse(call: Call, response: Response) {
                if (continuation.isActive) {
                    continuation.resume(response)
                }
            }
        })
    }

    private class ExpressProtectingSocketFactory(
        private val protectSocket: (Socket) -> Boolean,
        private val delegate: SocketFactory = SocketFactory.getDefault()
    ) : SocketFactory() {
        private fun protect(socket: Socket): Socket {
            protectSocket(socket)
            return socket
        }

        override fun createSocket(): Socket = protect(delegate.createSocket())

        override fun createSocket(host: String?, port: Int): Socket =
            protect(delegate.createSocket(host, port))

        override fun createSocket(host: String?, port: Int, localHost: InetAddress?, localPort: Int): Socket =
            protect(delegate.createSocket(host, port, localHost, localPort))

        override fun createSocket(host: InetAddress?, port: Int): Socket =
            protect(delegate.createSocket(host, port))

        override fun createSocket(address: InetAddress?, port: Int, localAddress: InetAddress?, localPort: Int): Socket =
            protect(delegate.createSocket(address, port, localAddress, localPort))
    }
}
