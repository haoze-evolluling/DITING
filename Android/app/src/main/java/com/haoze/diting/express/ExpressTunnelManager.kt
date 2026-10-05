package com.haoze.diting.express

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import com.haoze.diting.R
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.dao.DnsCacheDao
import com.haoze.diting.data.entity.DnsCacheEntity
import com.haoze.diting.express.engine.ExpressDnsEngine
import com.haoze.diting.express.engine.ExpressDnsMessageUtils
import com.haoze.diting.express.engine.ExpressPacketCodec
import com.haoze.diting.express.engine.ExpressTcpDnsHandler
import com.haoze.diting.express.engine.ExpressUpstreamDispatcher
import com.haoze.diting.express.engine.PublicDnsHijackList
import com.haoze.diting.ui.DnsLogMode
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.ui.Ipv6Mode
import com.haoze.diting.vpn.AllowListManager
import com.haoze.diting.vpn.BlockListManager
import com.haoze.diting.vpn.BlockResponseMode
import com.haoze.diting.vpn.BootstrapHealthEngine
import com.haoze.diting.vpn.BootstrapLogger
import com.haoze.diting.vpn.BootstrapSelector
import com.haoze.diting.vpn.DnsLogger
import com.haoze.diting.vpn.DnsProvider
import com.haoze.diting.vpn.DomainDecision
import com.haoze.diting.vpn.DomainPolicy
import com.haoze.diting.vpn.LogResult
import com.haoze.diting.vpn.RaceLogger
import com.haoze.diting.vpn.cache.DnsCachePolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.Inet6Address
import java.net.InetAddress

/**
 * Manages the TUN virtual network interface, rules cache pre-warming,
 * and high-performance packet dispatch loop for Express Mode.
 */
class ExpressTunnelManager {

    companion object {
        private const val TAG = "ExpressTunnelManager"
        const val VPN_ADDRESS_V4 = "10.0.0.2"
        const val DNS_SERVER_V4 = "10.0.0.1"
        const val VPN_ADDRESS_V6 = "fd00:abcd::2"
        const val DNS_SERVER_V6 = "fd00:abcd::1"
        const val VPN_MTU = 1400
    }

    var vpnInterface: ParcelFileDescriptor? = null
        private set

    @Volatile
    var isIpv6Active: Boolean = false
        private set

    @Volatile
    var isRunning: Boolean = false
        private set

    private val writeLock = Any()
    private var inputStream: FileInputStream? = null
    private var outputStream: FileOutputStream? = null
    private var tunThread: Thread? = null
    private var retransmitJob: Job? = null

    private lateinit var blockListManager: BlockListManager
    private lateinit var allowListManager: AllowListManager
    private lateinit var domainPolicy: DomainPolicy
    private lateinit var expressCache: ExpressRoomDnsCache
    private lateinit var dnsLogger: DnsLogger
    private lateinit var raceLogger: RaceLogger
    private lateinit var bootstrapLogger: BootstrapLogger
    private lateinit var bootstrapHealthEngine: BootstrapHealthEngine
    private lateinit var bootstrapSelector: BootstrapSelector
    private lateinit var engine: ExpressDnsEngine
    private lateinit var tcpHandler: ExpressTcpDnsHandler

    /**
     * Cache adapter backed by Room DnsCacheDao and in-memory LruCache.
     */
    class ExpressRoomDnsCache(
        private val dao: DnsCacheDao,
        private val cachePolicyProvider: () -> DnsCachePolicy
    ) : ExpressDnsEngine.ExpressDnsCache {
        private class SimpleLruCache<K, V>(private val maxEntries: Int) {
            private val map = object : LinkedHashMap<K, V>(maxEntries, 0.75f, true) {
                override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean {
                    return size > maxEntries
                }
            }

            @Synchronized
            fun get(key: K): V? = map[key]

            @Synchronized
            fun put(key: K, value: V) {
                map[key] = value
            }

            @Synchronized
            fun remove(key: K): V? = map.remove(key)

            @Synchronized
            fun clear() {
                map.clear()
            }
        }

        private val memoryCache = SimpleLruCache<String, Pair<Long, ByteArray>>(500)

        fun clearMemory() {
            memoryCache.clear()
        }

        override suspend fun get(
            question: ExpressDnsMessageUtils.DnsQuestion,
            requestQuery: ByteArray
        ): ByteArray? {
            val policy = cachePolicyProvider()
            if (!policy.enabled) return null
            val normalizedName = question.name.lowercase().trimEnd('.')
            val key = "$normalizedName#${question.type}#${question.qclass}"
            val now = System.currentTimeMillis()

            val mem = memoryCache.get(key)
            if (mem != null) {
                val (expiresAt, response) = mem
                if (expiresAt > now) {
                    val remainingTtl = ((expiresAt - now) / 1000L).coerceAtLeast(1L)
                    val patched = ExpressPacketCodec.overwriteDnsPayloadTtl(response, remainingTtl)
                    if (patched != null) return patched
                } else {
                    memoryCache.remove(key)
                }
            }

            val entity = dao.get(key) ?: return null
            if (entity.expiresAt <= now) {
                dao.delete(key)
                return null
            }
            val remainingTtl = ((entity.expiresAt - now) / 1000L).coerceAtLeast(1L)
            val patched = ExpressPacketCodec.overwriteDnsPayloadTtl(entity.response, remainingTtl)
            if (patched != null) {
                memoryCache.put(key, entity.expiresAt to entity.response)
                dao.recordHit(key, now)
                return patched
            }
            return null
        }

        override suspend fun put(
            question: ExpressDnsMessageUtils.DnsQuestion,
            response: ByteArray
        ) {
            val policy = cachePolicyProvider()
            if (!policy.enabled) return
            val normalizedName = question.name.lowercase().trimEnd('.')
            val key = "$normalizedName#${question.type}#${question.qclass}"
            val minTtl = ExpressPacketCodec.extractMinDnsTtl(response) ?: 300L
            val effectiveTtl = policy.effectiveTtlSeconds(minTtl)
            if (effectiveTtl <= 0L) return

            val now = System.currentTimeMillis()
            val expiresAt = now + effectiveTtl * 1000L
            memoryCache.put(key, expiresAt to response)
            val entity = DnsCacheEntity(
                key = key,
                queryName = normalizedName,
                queryType = question.type,
                queryClass = question.qclass,
                createdAt = now,
                expiresAt = expiresAt,
                lastHitAt = null,
                hitCount = 0,
                originalTtlSeconds = minTtl,
                ttlOffsets = "",
                response = response.copyOf(),
                responseSize = response.size
            )
            dao.insert(entity)
        }
    }

    /**
     * Probes whether the underlying physical network has a valid public IPv6 address and gateway route.
     */
    @Suppress("DEPRECATION")
    fun hasPhysicalIpv6Support(context: Context): Boolean {
        return runCatching {
            val cm = context.getSystemService(ConnectivityManager::class.java) ?: return false
            val activeNetwork = cm.activeNetwork
            val candidateNetworks = mutableListOf<Network>()

            fun isPhysicalNetwork(network: Network): Boolean {
                val caps = cm.getNetworkCapabilities(network) ?: return false
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return false
                return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            }

            if (activeNetwork != null && isPhysicalNetwork(activeNetwork)) {
                candidateNetworks.add(activeNetwork)
            }

            cm.allNetworks.forEach { network ->
                if (network != activeNetwork && isPhysicalNetwork(network)) {
                    val caps = cm.getNetworkCapabilities(network)
                    if (caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                        candidateNetworks.add(network)
                    }
                }
            }

            if (candidateNetworks.isEmpty()) {
                cm.allNetworks.forEach { network ->
                    if (isPhysicalNetwork(network)) {
                        candidateNetworks.add(network)
                    }
                }
            }

            candidateNetworks.any { network ->
                val lp = cm.getLinkProperties(network) ?: return@any false
                val iface = lp.interfaceName.orEmpty().lowercase()
                if (iface.startsWith("tun") || iface.startsWith("vpn")) {
                    return@any false
                }

                val hasGlobalIpv6 = lp.linkAddresses.any { linkAddr ->
                    val addr = linkAddr.address
                    if (addr !is Inet6Address) return@any false
                    val firstByte = addr.address[0].toInt() and 0xff
                    (firstByte in 0x20..0x3f) &&
                        !addr.isAnyLocalAddress &&
                        !addr.isLinkLocalAddress &&
                        !addr.isLoopbackAddress &&
                        !addr.isMulticastAddress
                }
                if (!hasGlobalIpv6) return@any false

                val hasIpv6Route = lp.routes.any { route ->
                    val destAddr = route.destination.address
                    (destAddr is Inet6Address && route.isDefaultRoute) ||
                        (destAddr is Inet6Address && route.hasGateway()) ||
                        (destAddr is Inet6Address && route.destination.prefixLength == 0)
                }
                hasIpv6Route || hasGlobalIpv6
            }
        }.getOrDefault(false)
    }

    /**
     * Establishes the narrow-routing TUN interface for Express Mode.
     */
    fun establishVpnInterface(
        vpnService: VpnService,
        ipv6Mode: Ipv6Mode = Ipv6Mode.AUTO
    ): ParcelFileDescriptor? {
        val enableIpv6 = when (ipv6Mode) {
            Ipv6Mode.ENABLED -> true
            Ipv6Mode.DISABLED -> false
            Ipv6Mode.AUTO -> hasPhysicalIpv6Support(vpnService)
        }
        Log.i(TAG, "establishVpnInterface: ipv6Mode=$ipv6Mode, enableIpv6=$enableIpv6")

        val builder = vpnService.Builder()
            .setSession(vpnService.getString(R.string.app_name))
            .addAddress(VPN_ADDRESS_V4, 30)
            .addDnsServer(DNS_SERVER_V4)
            .allowFamily(OsConstants.AF_INET)
            .setMtu(VPN_MTU)
            .setBlocking(true)

        fun addRouteSafe(ip: String, prefix: Int) {
            try { builder.addRoute(ip, prefix) } catch (e: Exception) { Log.w(TAG, "addRoute failed for $ip/$prefix", e) }
        }
        addRouteSafe("10.0.0.0", 30)
        PublicDnsHijackList.IPV4_HIJACK_IPS.forEach { ip -> addRouteSafe(ip, 32) }

        if (enableIpv6) {
            builder.addAddress(VPN_ADDRESS_V6, 64)
            builder.addDnsServer(DNS_SERVER_V6)
            builder.allowFamily(OsConstants.AF_INET6)
            addRouteSafe("fd00:abcd::1", 128)
            PublicDnsHijackList.IPV6_HIJACK_IPS.forEach { ip -> addRouteSafe(ip, 128) }
        }

        try {
            builder.addDisallowedApplication(vpnService.packageName)
        } catch (e: Exception) {
            Log.w(TAG, "addDisallowedApplication failed for self", e)
        }

        val pfd = builder.establish()
        vpnInterface = pfd
        isIpv6Active = if (pfd != null) enableIpv6 else false
        return pfd
    }

    /**
     * Initializes components, warms up rules, and launches the TUN read/write loop.
     */
    fun start(
        service: VpnService,
        pfd: ParcelFileDescriptor,
        scope: CoroutineScope,
        providersProvider: () -> List<DnsProvider>,
        resolutionModeProvider: () -> DnsResolutionMode,
        blockResponseModeProvider: () -> BlockResponseMode,
        domainRulesEnabledProvider: () -> Boolean,
        cachePolicyProvider: () -> DnsCachePolicy,
        dnsLogModeProvider: () -> DnsLogMode
    ): Boolean {
        val db = AppDatabase.getInstance(service)
        val ruleIndexDirectory = File(service.filesDir, "rule-index")
        blockListManager = BlockListManager(db.blockRuleDao(), ruleIndexDirectory)
        allowListManager = AllowListManager(db.allowRuleDao(), ruleIndexDirectory)
        domainPolicy = DomainPolicy(allowListManager, blockListManager) { domainRulesEnabledProvider() }
        blockListManager.onCacheChanged = { domainPolicy.invalidateCache() }
        allowListManager.onCacheChanged = { domainPolicy.invalidateCache() }

        expressCache = ExpressRoomDnsCache(db.dnsCacheDao(), cachePolicyProvider)
        dnsLogger = DnsLogger(db.dnsLogDao(), flushScope = scope) { dnsLogModeProvider() }
        raceLogger = RaceLogger(db.raceLogDao(), flushScope = scope)
        bootstrapLogger = BootstrapLogger(db.bootstrapLogDao(), flushScope = scope)
        bootstrapHealthEngine = BootstrapHealthEngine(service, scope)
        bootstrapSelector = BootstrapSelector(
            context = service,
            healthEngine = bootstrapHealthEngine,
            logger = bootstrapLogger,
            protectDatagramSocket = { sock -> service.protect(sock) }
        )

        // Pre-warm rule caches
        val ruleJob = scope.launch(Dispatchers.IO) {
            val j1 = launch { runCatching { blockListManager.refreshCache() } }
            val j2 = launch { runCatching { allowListManager.refreshCache() } }
            j1.join()
            j2.join()
            domainPolicy.invalidateCache()
        }
        runCatching {
            runBlocking {
                withTimeoutOrNull(3000) { ruleJob.join() }
            }
        }

        val transportInvoker = ExpressUpstreamDispatcher.DefaultExpressTransportInvoker(
            protectDatagramSocket = { sock -> service.protect(sock) },
            protectSocket = { sock -> service.protect(sock) }
        )
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = transportInvoker,
            raceLogger = raceLogger,
            bootstrapResolver = { host -> resolveBootstrap(host) }
        )

        engine = ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            ruleEvaluator = { domain, _ ->
                val decision = domainPolicy.evaluate(domain, null)
                when (decision) {
                    is DomainDecision.Block -> ExpressDnsEngine.RuleEvaluation(blocked = true, reason = decision.matchedRule)
                    is DomainDecision.Allow -> ExpressDnsEngine.RuleEvaluation(blocked = false, reason = decision.matchedRule)
                }
            },
            cache = expressCache,
            isDomainRulesEnabledProvider = domainRulesEnabledProvider,
            blockResponseModeProvider = blockResponseModeProvider,
            activeProvidersProvider = providersProvider,
            resolutionModeProvider = resolutionModeProvider,
            dnsLogger = { domain, queryType, blocked, reason, cached, latencyMs, providerName ->
                val logResult = when {
                    blocked -> LogResult.BLOCKED
                    reason != null && reason.startsWith("upstream_failure") -> LogResult.ERROR
                    else -> LogResult.PASSED
                }
                val msg = if (providerName != null) "$providerName (${latencyMs}ms)" else reason
                scope.launch {
                    dnsLogger.log(
                        queryName = domain,
                        queryType = queryType,
                        result = logResult,
                        message = msg,
                        cached = cached
                    )
                }
            }
        )

        tcpHandler = ExpressTcpDnsHandler(engine)

        val inStream = FileInputStream(pfd.fileDescriptor)
        val outStream = FileOutputStream(pfd.fileDescriptor)
        inputStream = inStream
        outputStream = outStream
        isRunning = true

        retransmitJob = scope.launch(Dispatchers.IO) {
            while (isActive && isRunning) {
                delay(500)
                val resends = tcpHandler.checkRetransmissions()
                for (pkt in resends) {
                    writePacket(pkt)
                }
                tcpHandler.pruneInactive()
            }
        }

        tunThread = Thread({
            val buffer = ByteArray(VPN_MTU + 64)
            while (isRunning) {
                val len = try {
                    inStream.read(buffer)
                } catch (_: Exception) {
                    break
                }
                if (len <= 0) break

                val parsed = ExpressPacketCodec.parse(buffer, 0, len) ?: continue
                when (parsed) {
                    is ExpressPacketCodec.ParsedPacket.DnsUdpQuery -> {
                        scope.launch(Dispatchers.IO) {
                            try {
                                val dnsResp = engine.resolve(parsed.dnsPayload)
                                val udpResp = ExpressPacketCodec.buildUdpResponse(
                                    isIpv6 = parsed.isIpv6,
                                    srcIp = parsed.dstIp,
                                    dstIp = parsed.srcIp,
                                    srcPort = parsed.dstPort,
                                    dstPort = parsed.srcPort,
                                    dnsPayload = dnsResp
                                )
                                writePacket(udpResp)
                            } catch (e: Exception) {
                                Log.w(TAG, "Error handling DNS UDP query", e)
                            }
                        }
                    }
                    is ExpressPacketCodec.ParsedPacket.DnsTcpPacket -> {
                        scope.launch(Dispatchers.IO) {
                            try {
                                val tcpResponses = tcpHandler.handlePacket(parsed)
                                for (resp in tcpResponses) {
                                    writePacket(resp)
                                }
                            } catch (e: Exception) {
                                Log.w(TAG, "Error handling DNS TCP packet", e)
                            }
                        }
                    }
                    is ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket -> {
                        val rst = ExpressPacketCodec.buildTcpReset(
                            isIpv6 = parsed.isIpv6,
                            srcIp = parsed.srcIp,
                            dstIp = parsed.dstIp,
                            srcPort = parsed.srcPort,
                            dstPort = parsed.dstPort,
                            seqNumber = parsed.seqNumber,
                            ackNumber = parsed.ackNumber,
                            flags = parsed.flags,
                            payloadLength = parsed.payloadLength
                        )
                        if (rst != null) {
                            writePacket(rst)
                        }
                    }
                    is ExpressPacketCodec.ParsedPacket.DiscardPacket -> {
                        // Drop
                    }
                }
            }
        }, "ExpressTunReader").apply {
            isDaemon = true
            start()
        }

        return true
    }

    fun writePacket(packet: ByteArray) {
        synchronized(writeLock) {
            if (!isRunning) return
            try {
                outputStream?.write(packet)
            } catch (_: Exception) {
            }
        }
    }

    fun syncRules(scope: CoroutineScope) {
        scope.launch(Dispatchers.IO) {
            if (::blockListManager.isInitialized) runCatching { blockListManager.refreshCache() }
            if (::allowListManager.isInitialized) runCatching { allowListManager.refreshCache() }
            if (::domainPolicy.isInitialized) domainPolicy.invalidateCache()
        }
    }

    fun clearCache() {
        if (::expressCache.isInitialized) {
            expressCache.clearMemory()
        }
    }

    private fun resolveBootstrap(host: String): List<InetAddress> {
        if (!::bootstrapSelector.isInitialized) return emptyList()
        return runCatching {
            runBlocking(Dispatchers.IO) {
                bootstrapSelector.resolveHost(host)
            }
        }.getOrNull()?.takeIf { it.isNotEmpty() } ?: emptyList()
    }

    /**
     * Stops the read loop, cancels jobs, closes TUN, and flushes loggers.
     */
    fun stop() {
        isRunning = false
        retransmitJob?.cancel()
        retransmitJob = null
        try {
            inputStream?.close()
        } catch (_: Exception) {}
        try {
            outputStream?.close()
        } catch (_: Exception) {}
        try {
            vpnInterface?.close()
        } catch (_: Exception) {}
        vpnInterface = null
        isIpv6Active = false
        tunThread?.interrupt()
        tunThread = null

        runCatching {
            runBlocking {
                if (::dnsLogger.isInitialized) dnsLogger.flush()
                if (::raceLogger.isInitialized) raceLogger.flush()
                if (::bootstrapLogger.isInitialized) bootstrapLogger.flush()
            }
            if (::bootstrapHealthEngine.isInitialized) bootstrapHealthEngine.flush(commit = true)
        }
    }
}
