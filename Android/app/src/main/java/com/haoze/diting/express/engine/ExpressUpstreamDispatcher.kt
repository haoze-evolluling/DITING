package com.haoze.diting.express.engine

import com.haoze.diting.express.transport.ExpressDohTransport
import com.haoze.diting.express.transport.ExpressDotTransport
import com.haoze.diting.express.transport.ExpressPlainDnsTransport
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.ui.RaceModeStrategy
import com.haoze.diting.vpn.DNS_UPSTREAM_TIMEOUT_MS
import com.haoze.diting.vpn.DnsProtocol
import com.haoze.diting.vpn.DnsProvider
import com.haoze.diting.vpn.RaceLogger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import java.io.Closeable
import java.io.IOException
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger

/**
 * Dispatches DNS queries across upstreams according to [DnsResolutionMode].
 *
 * Supports SINGLE, PRIMARY_BACKUP failover, PARALLEL_RACE, and SMART_PREDICTION.
 * On race victory, losing jobs and their underlying sockets are cancelled and closed immediately.
 */
class ExpressUpstreamDispatcher(
    private val transportInvoker: ExpressTransportInvoker = DefaultExpressTransportInvoker(),
    private val raceLogger: RaceLogger? = null,
    private val bootstrapResolver: ((String) -> List<InetAddress>)? = null
) {

    fun interface ExpressTransportInvoker {
        suspend fun query(
            provider: DnsProvider,
            query: ByteArray,
            bootstrapAddresses: List<InetAddress>?,
            onSocketActive: ((Closeable) -> Unit)?
        ): ByteArray
    }

    class DefaultExpressTransportInvoker(
        private val protectDatagramSocket: ((DatagramSocket) -> Boolean)? = null,
        private val protectSocket: ((Socket) -> Boolean)? = null,
        private val timeoutMs: Int = DNS_UPSTREAM_TIMEOUT_MS
    ) : ExpressTransportInvoker {
        override suspend fun query(
            provider: DnsProvider,
            query: ByteArray,
            bootstrapAddresses: List<InetAddress>?,
            onSocketActive: ((Closeable) -> Unit)?
        ): ByteArray {
            return when (provider.protocol) {
                DnsProtocol.DNS -> {
                    val addresses = if (bootstrapAddresses.isNullOrEmpty()) {
                        listOf(InetAddress.getByName(provider.host))
                    } else {
                        bootstrapAddresses
                    }
                    ExpressPlainDnsTransport.query(
                        addresses = addresses,
                        port = provider.port,
                        protectDatagramSocket = protectDatagramSocket,
                        protectTcpSocket = protectSocket,
                        query = query,
                        timeoutMs = timeoutMs,
                        onSocketActive = onSocketActive
                    )
                }
                DnsProtocol.DOT -> {
                    ExpressDotTransport.query(
                        host = provider.host,
                        port = provider.port,
                        bootstrapAddresses = bootstrapAddresses,
                        protectSocket = protectSocket,
                        query = query,
                        timeoutMs = timeoutMs,
                        onSocketActive = onSocketActive
                    )
                }
                DnsProtocol.DOH -> {
                    ExpressDohTransport.query(
                        url = provider.url,
                        bootstrapAddresses = bootstrapAddresses,
                        protectSocket = protectSocket,
                        query = query,
                        timeoutMs = timeoutMs.toLong()
                    )
                }
            }
        }
    }

    suspend fun dispatch(
        mode: DnsResolutionMode,
        providers: List<DnsProvider>,
        query: ByteArray,
        question: ExpressDnsMessageUtils.DnsQuestion? = null
    ): ByteArray {
        require(providers.isNotEmpty()) { "No upstream DNS providers configured" }

        return when (mode) {
            DnsResolutionMode.SINGLE -> dispatchSingle(providers.first(), query)
            DnsResolutionMode.PRIMARY_BACKUP -> dispatchPrimaryBackup(providers, query)
            DnsResolutionMode.PARALLEL_RACE -> dispatchRace(providers, query, question, RaceModeStrategy.BRUTE_FORCE_PARALLEL)
            DnsResolutionMode.SMART_PREDICTION -> dispatchRace(providers, query, question, RaceModeStrategy.SMART_PREDICTION)
        }
    }

    private suspend fun dispatchSingle(provider: DnsProvider, query: ByteArray): ByteArray {
        val bootstrap = resolveBootstrap(provider)
        val response = transportInvoker.query(provider, query, bootstrap, null)
        if (!ExpressDnsMessageUtils.isUsableUpstreamResponse(response, query)) {
            throw IOException("Provider ${provider.name} returned invalid response")
        }
        return response
    }

    private suspend fun dispatchPrimaryBackup(providers: List<DnsProvider>, query: ByteArray): ByteArray {
        var lastError: Exception? = null
        for (provider in providers) {
            try {
                val bootstrap = resolveBootstrap(provider)
                val response = transportInvoker.query(provider, query, bootstrap, null)
                if (ExpressDnsMessageUtils.isUsableUpstreamResponse(response, query)) {
                    return response
                }
            } catch (e: Exception) {
                lastError = e
            }
        }
        throw lastError ?: IOException("All upstream DNS providers in failover chain failed")
    }

    private suspend fun dispatchRace(
        providers: List<DnsProvider>,
        query: ByteArray,
        question: ExpressDnsMessageUtils.DnsQuestion?,
        strategy: RaceModeStrategy
    ): ByteArray = coroutineScope {
        val winnerResult = CompletableDeferred<Pair<DnsProvider, ByteArray>>()
        val failureCount = AtomicInteger(0)
        val jobs = mutableListOf<Job>()
        val startNs = System.nanoTime()

        providers.forEach { provider ->
            val job = launch(Dispatchers.IO) {
                var activeSocket: Closeable? = null
                currentCoroutineContext().job.invokeOnCompletion { cause ->
                    if (cause is CancellationException) {
                        try {
                            activeSocket?.close()
                        } catch (_: Throwable) {}
                    }
                }

                try {
                    val bootstrap = resolveBootstrap(provider)
                    val response = transportInvoker.query(provider, query, bootstrap) { socket ->
                        activeSocket = socket
                    }
                    if (ExpressDnsMessageUtils.isUsableUpstreamResponse(response, query)) {
                        if (winnerResult.complete(provider to response)) {
                            // Cancel siblings immediately
                            jobs.forEach { sibling ->
                                if (sibling !== currentCoroutineContext().job) {
                                    sibling.cancel()
                                }
                            }
                        }
                    } else {
                        if (failureCount.incrementAndGet() == providers.size) {
                            winnerResult.completeExceptionally(IOException("All racing upstreams returned invalid responses"))
                        }
                    }
                } catch (e: Exception) {
                    if (failureCount.incrementAndGet() == providers.size) {
                        winnerResult.completeExceptionally(e)
                    }
                }
            }
            jobs.add(job)
        }

        try {
            val (winner, response) = winnerResult.await()
            val elapsedMs = (System.nanoTime() - startNs) / 1_000_000
            if (question != null && raceLogger != null) {
                raceLogger.log(
                    queryName = question.name,
                    queryType = question.type,
                    strategy = strategy,
                    providerCount = providers.size,
                    success = true,
                    elapsedMs = elapsedMs,
                    winnerProviderId = winner.id,
                    winnerProviderName = winner.name,
                    winnerElapsedMs = elapsedMs
                )
            }
            response
        } catch (e: Exception) {
            val elapsedMs = (System.nanoTime() - startNs) / 1_000_000
            if (question != null && raceLogger != null) {
                raceLogger.log(
                    queryName = question.name,
                    queryType = question.type,
                    strategy = strategy,
                    providerCount = providers.size,
                    success = false,
                    elapsedMs = elapsedMs,
                    message = e.message
                )
            }
            throw e
        }
    }

    private fun resolveBootstrap(provider: DnsProvider): List<InetAddress>? {
        if (bootstrapResolver == null) return null
        return when (provider.protocol) {
            DnsProtocol.DOH -> {
                val host = provider.url.substringAfter("://").substringBefore("/").substringBefore(":")
                bootstrapResolver.invoke(host)
            }
            DnsProtocol.DOT, DnsProtocol.DNS -> {
                if (provider.host.isNotEmpty()) bootstrapResolver.invoke(provider.host) else null
            }
        }
    }
}
