package com.haoze.diting.vpn

import android.content.Context
import android.util.Log
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.ui.OutboundProxyConfig
import com.haoze.diting.ui.RaceModeStrategy
import com.haoze.diting.vpn.cache.DnsCachePolicy
import com.haoze.diting.vpn.cache.DnsResponseCache
import com.haoze.diting.vpn.traffic.TrafficStatsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import tunnel.BatchLogCallback
import tunnel.BootstrapLogCallback
import tunnel.DomainChecker
import tunnel.Engine
import tunnel.HttpLogCallback
import tunnel.OutboundProxyStatusCallback
import tunnel.RaceLogCallback
import tunnel.SocketProtector
import tunnel.TrafficCallback
import java.io.File

/**
 * Owns the GPL-3.0 Go full-TUN data plane.
 * The Go stack owns TUN reads and native DNS resolution engine.
 */
class GoInspectionTunnel(
    private val context: Context,
    private val vpnService: DnsVpnService,
    private val scope: CoroutineScope,
    private var dnsConfig: HttpsDnsConfigSnapshot,
    private val inspectionEnabled: Boolean,
    private val selectedPackages: Set<String>,
    private val blockedPackages: Set<String>,
    private val appAllowlistRules: Map<String, Set<String>>,
    private val dnsPolicy: DomainPolicy,
    private val allowListManager: AllowListManager,
    private val cnameRewriteRuleManager: RewriteRuleManager,
    private val goUrlRuleManager: GoUrlRuleManager,
    private val dnsLogger: DnsLogger,
    private val httpRequestLogger: HttpRequestLogger,
    private val raceLogger: RaceLogger,
    private val bootstrapLogger: BootstrapLogger,
    private val bootstrapHealthEngine: BootstrapHealthEngine,
    private val dnsCache: DnsResponseCache,
    private val filterHttp3: Boolean,
    private val blockEncryptedDns: Boolean,
    private val outboundProxyConfig: OutboundProxyConfig,
    private val ruleIndexDirectory: File? = File(context.filesDir, "rule-index")
) {
    private val engine = Engine()
    private val uidPackageCache = UidPackageCache(context)
    private val ruleManager = GoTunnelRuleManager(
        context = context,
        vpnService = vpnService,
        engine = engine,
        dnsPolicy = dnsPolicy,
        cnameRewriteRuleManager = cnameRewriteRuleManager,
        goUrlRuleManager = goUrlRuleManager,
        inspectionEnabled = inspectionEnabled,
        ruleIndexDirectory = ruleIndexDirectory,
        packageUidProvider = ::packageUid
    )
    private val logProcessor = GoTunnelLogProcessor(
        dnsPolicy = dnsPolicy,
        dnsLogger = dnsLogger,
        dnsCache = dnsCache
    )
    private var startJob: Job? = null

    fun start(tunFileDescriptor: Int): Boolean = runCatching {
        configureEngine(selectedPackages)
        startJob = scope.launch(Dispatchers.IO) {
            engine.startFull(tunFileDescriptor.toLong(), SocketProtector { fd ->
                vpnService.protect(fd.toInt())
            })
        }
        true
    }.onFailure { Log.e(TAG, "Unable to start Go inspection tunnel", it) }.getOrDefault(false)

    fun stop() {
        startJob?.cancel()
        startJob = null
        uidPackageCache.clear()
        runCatching { engine.stop() }.onFailure { Log.w(TAG, "Unable to stop Go inspection tunnel", it) }
        runCatching { engine.stopStackMitm() }
    }

    fun releaseTun() {
        runCatching { engine.releaseTun() }
            .onFailure { Log.w(TAG, "Unable to release Go inspection TUN", it) }
    }

    fun clearDnsCache() {
        runCatching { engine.clearDNSCache() }
    }

    fun getDnsCacheStats(): String = runCatching {
        engine.javaClass.getMethod("getDNSCacheStats").invoke(engine) as String
    }.getOrDefault("{}")

    fun resetBootstrapStats() {

        runCatching { engine.resetBootstrapStats() }
            .onFailure { Log.w(TAG, "Unable to reset Go bootstrap stats", it) }
    }

    /**
     * Adjusts the Go-side traffic-stats tick period (ms), driven by screen
     * state: 1000ms with the screen on / 10000ms with the screen off. During
     * off-screen aggregation RecordTx/Rx keep accumulating, so totals are
     * never lost (same mechanism as the final tick in Stop()).
     */
    fun setTrafficTickIntervalMs(intervalMs: Long) {
        runCatching { engine.setTickIntervalMs(intervalMs) }
            .onFailure { Log.w(TAG, "Unable to set traffic tick interval", it) }
    }

    /**
     * Pushes a rule snapshot one-way to the Go-side local rule decision
     * engine (includes static subscription paths and small rule sets).
     */
    fun pushRuleSnapshot() {
        ruleManager.pushRuleSnapshot()
    }

    fun updateRewriteRules() {
        ruleManager.updateRewriteRules()
    }

    /**
     * Resolves a domain through the Go engine's DNS decision path (rewrites,
     * policy rules, upstream) for the diagnostics tools. Returns null when
     * the engine call fails.
     */
    fun resolveDomain(domain: String, ipv4: Boolean): String? =
        runCatching { engine.resolveDomain(domain, ipv4) }.getOrNull()

    fun updatePassthroughRules() {
        ruleManager.updatePassthroughRules()
    }

    fun updateRequestRules() {
        ruleManager.updateRequestRules()
    }

    @Synchronized
    fun syncDnsConfig(
        providers: List<DnsProvider>,
        resolutionMode: DnsResolutionMode,
        blockResponseMode: BlockResponseMode,
        dynamicBlockResponseConfig: DynamicBlockResponseConfig,
        cachePolicy: DnsCachePolicy,
        bootstrapEnabled: Boolean,
        bootstrapIps: List<BootstrapIpEntry>
    ) {
        val next = HttpsDnsConfigSnapshot.create(
            providers,
            resolutionMode,
            blockResponseMode,
            dynamicBlockResponseConfig,
            cachePolicy,
            bootstrapEnabled,
            bootstrapIps
        )
        engine.applyDNSConfig(next.toJson())
        dnsConfig = next
    }

    @Synchronized
    fun syncAppAllowlist(rules: Map<String, Set<String>>) {
        ruleManager.syncAppAllowlist(rules)
    }

    private fun configureEngine(selectedPackages: Set<String>) {
        val outboundError = engine.configureOutboundProxy(outboundProxyConfig.toNativeJson())
        require(outboundError.isBlank()) { outboundError }
        engine.setOutboundProxyStatusCallback(object : OutboundProxyStatusCallback {
            override fun onOutboundProxyStatus(state: String, message: String) {
                vpnService.onOutboundProxyStatus(state, message)
            }
        })
        syncDnsConfig(
            dnsConfig.providers,
            dnsConfig.mode,
            dnsConfig.blockResponseMode,
            dnsConfig.dynamicBlockResponseConfig,
            dnsConfig.cachePolicy,
            dnsConfig.bootstrapEnabled,
            dnsConfig.bootstrapIps
        )
        if (inspectionEnabled) {
            updateRewriteRules()
        } else {
            // DNS-stage IPv4/IPv6 rewrites must still reach the engine; only
            // the inspection-dependent CNAME redirects stay empty here.
            ruleManager.updateRewriteMap()
            engine.setRequestRules("")
        }
        engine.setDomainChecker(object : DomainChecker {
            override fun checkDomain(domain: String, appName: String): String =
                when (val decision = dnsPolicy.evaluate(domain, appName.ifBlank { null })) {
                    is DomainDecision.Block -> decision.matchedRule.ifEmpty { "custom" }
                    is DomainDecision.Allow -> if (decision.matchedRule != null) "__ALLOW__" else ""
                }

            override fun isBlocked(domain: String): Boolean = dnsPolicy.evaluate(domain) is DomainDecision.Block

            override fun getBlockReason(domain: String): String =
                (dnsPolicy.evaluate(domain) as? DomainDecision.Block)?.matchedRule.orEmpty()

            override fun hasCustomRule(domain: String): Long = when (val decision = dnsPolicy.evaluate(domain)) {
                is DomainDecision.Block -> 1L
                is DomainDecision.Allow -> if (decision.matchedRule != null) 0L else -1L
            }

            override fun isBlockedForApp(domain: String, appName: String): Boolean =
                dnsPolicy.evaluate(domain, appName.ifBlank { null }) is DomainDecision.Block

            override fun getBlockReasonForApp(domain: String, appName: String): String =
                (dnsPolicy.evaluate(domain, appName.ifBlank { null }) as? DomainDecision.Block)?.matchedRule.orEmpty()

            override fun hasCustomRuleForApp(domain: String, appName: String): Long =
                when (val decision = dnsPolicy.evaluate(domain, appName.ifBlank { null })) {
                    is DomainDecision.Block -> 1L
                    is DomainDecision.Allow -> if (decision.matchedRule != null) 0L else -1L
                }
        })
        // DNS filtering and HTTPS inspection are forcibly coupled: while
        // inspection runs, domain-level rules (subscription/custom block and
        // allowlists) must stay active — HTTPS inspection must never run
        // with DNS filtering disabled; decrypted HTTP traffic is additionally
        // matched against URL-level rules on top of the DNS filtering result.
        engine.setFilterDNS(true)
        pushRuleSnapshot()
        engine.setBatchLogCallback(object : BatchLogCallback {
            override fun onDNSQueryBatch(jsonLogs: String) {
                if (jsonLogs.isBlank()) return
                scope.launch {
                    logProcessor.processLogBatch(jsonLogs)
                }
            }
        })
        engine.setRaceLogCallback(object : RaceLogCallback {
            override fun onRaceResult(
                queryName: String,
                queryType: Long,
                strategy: String,
                providerCount: Long,
                success: Boolean,
                elapsedMs: Long,
                selectedProviderID: String,
                selectedElapsedMs: Long,
                winnerProviderID: String,
                winnerElapsedMs: Long,
                fallbackUsed: Boolean,
                fallbackSuccess: Boolean,
                errorMessage: String
            ) {
                scope.launch {
                    val strat = RaceModeStrategy.fromStorageValue(strategy)
                    val providersById = dnsConfig.providers.associateBy { it.id }
                    val selected = providersById[selectedProviderID]
                    val winner = providersById[winnerProviderID]
                    raceLogger.log(
                        queryName = queryName,
                        queryType = queryType.toInt(),
                        strategy = strat,
                        providerCount = providerCount.toInt(),
                        success = success,
                        elapsedMs = elapsedMs,
                        selectedProviderId = selected?.id ?: selectedProviderID.takeIf { it.isNotBlank() },
                        selectedProviderName = selected?.name ?: selectedProviderID.takeIf { it.isNotBlank() },
                        selectedElapsedMs = if (selectedElapsedMs > 0) selectedElapsedMs else null,
                        winnerProviderId = winner?.id ?: winnerProviderID.takeIf { it.isNotBlank() },
                        winnerProviderName = winner?.name ?: winnerProviderID.takeIf { it.isNotBlank() },
                        winnerElapsedMs = if (winnerElapsedMs > 0) winnerElapsedMs else null,
                        fallbackUsed = fallbackUsed,
                        fallbackSuccess = fallbackSuccess,
                        message = errorMessage.ifBlank { null }
                    )
                }
            }
        })
        engine.setBootstrapLogCallback(object : BootstrapLogCallback {
            override fun onBootstrapResult(
                ipId: String,
                ipName: String,
                ip: String,
                host: String,
                success: Boolean,
                elapsedMs: Long,
                fallbackUsed: Boolean,
                errorMessage: String
            ) {
                scope.launch {
                    bootstrapHealthEngine.recordResult(ipId, success, elapsedMs)
                    bootstrapLogger.log(
                        ipId = ipId,
                        ipName = ipName,
                        ip = ip,
                        host = host,
                        success = success,
                        elapsedMs = elapsedMs,
                        fallbackUsed = fallbackUsed,
                        message = errorMessage.ifBlank { null }
                    )
                }
            }
        })
        engine.setHttpLogCallback(object : HttpLogCallback {
            override fun onHttpEvent(
                packageName: String,
                authority: String,
                protocol: String,
                outcome: String,
                matchedRule: String
            ) {
                scope.launch {
                    val httpOutcome = outcome.toHttpRequestOutcome()
                    val blockSubscriptionId = logProcessor.resolveHttpBlockSubscriptionId(authority, httpOutcome, packageName.ifBlank { null })
                    httpRequestLogger.log(
                        packageName = packageName,
                        authority = authority.ifBlank { null },
                        protocol = protocol,
                        outcome = httpOutcome,
                        matchedRule = matchedRule.ifBlank { null },
                        blockSubscriptionId = blockSubscriptionId
                    )
                }
            }
        })
        engine.setUIDResolver(CachedConnectionOwnerUidResolver(uidPackageCache))
        engine.setAppUidResolver(CachedAppPackageResolver(uidPackageCache))
        engine.setUseTcpStack(true)
        engine.setBlockedUIDs(blockedPackages.mapNotNull(::packageUid).joinToString(","))
        syncAppAllowlist(appAllowlistRules)
        if (inspectionEnabled) {
            engine.startStackMitm(GoInspectionCaManager.certificateDirectory(context).absolutePath)
            engine.setMitmAllowedUIDs(selectedPackages.mapNotNull(::packageUid).joinToString(","))
        }
        engine.setFilterHttp3(filterHttp3)
        engine.setBlockEncryptedDns(blockEncryptedDns)
        engine.setTrafficCallback(object : TrafficCallback {
            override fun onTrafficStatsTick(jsonDeltas: String) {
                TrafficStatsManager.onGoTrafficTick(jsonDeltas)
            }
        })
        updatePassthroughRules()
    }

    private fun packageUid(packageName: String): Int? =
        runCatching { context.packageManager.getPackageUid(packageName, 0) }.getOrNull()

    private companion object {
        const val TAG = "GoInspectionTunnel"
    }
}
