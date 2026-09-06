package com.haoze.dnssr.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.os.Process
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.OutboundProxyConfig
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import com.haoze.dnssr.vpn.cache.DnsResponseCache
import com.haoze.dnssr.data.entity.DnsLogEntity
import tunnel.AppUidResolver
import tunnel.BatchLogCallback
import tunnel.BootstrapLogCallback
import tunnel.DomainChecker
import tunnel.Engine
import tunnel.HttpLogCallback
import tunnel.LogCallback
import tunnel.OutboundProxyStatusCallback
import tunnel.RaceLogCallback
import tunnel.SocketProtector
import tunnel.TrafficCallback
import tunnel.UIDResolver
import com.haoze.dnssr.ui.RaceModeStrategy
import com.haoze.dnssr.vpn.traffic.TrafficStatsManager
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import org.json.JSONObject
import org.json.JSONArray

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

    fun resetBootstrapStats() {
        runCatching { engine.resetBootstrapStats() }
            .onFailure { Log.w(TAG, "Unable to reset Go bootstrap stats", it) }
    }

    /**
     * 调整 Go 侧流量统计 tick 周期（ms）。屏幕状态驱动：亮屏 1000ms / 灭屏 10000ms，
     * 灭屏聚合期间 RecordTx/Rx 照常累计，总量不丢（与 Stop() 最终 tick 同一机制）。
     */
    fun setTrafficTickIntervalMs(intervalMs: Long) {
        runCatching { engine.setTickIntervalMs(intervalMs) }
            .onFailure { Log.w(TAG, "Unable to set traffic tick interval", it) }
    }

    /**
     * 单向向 Go 侧本地规则决策引擎推送规则快照（包含静态订阅路径与小规则集）。
     */
    fun pushRuleSnapshot() {
        val snapshotJson = dnsPolicy.buildRuleSnapshotJson(ruleIndexDirectory)
        runCatching {
            val err = engine.applyRuleSnapshot(snapshotJson)
            if (!err.isNullOrBlank()) {
                Log.w(TAG, "applyRuleSnapshot error: $err")
            } else {
                Log.d(TAG, "applyRuleSnapshot succeeded")
            }
        }.onFailure { Log.w(TAG, "Failed to push rule snapshot to Go engine", it) }
    }

    fun updateRewriteRules() {
        dnsPolicy.invalidateCache()
        updateCnameRewriteRules()
        updateRequestRules()
        updatePassthroughRules()
        pushRuleSnapshot()
    }

    fun updatePassthroughRules() {
        runCatching {
            val patterns = runBlocking { allowListManager.enabledPatterns() }
            engine.setExtraPassthroughSuffixes(patterns.joinToString("\n"))
        }
    }

    fun updateCnameRewriteRules() {
        if (!inspectionEnabled || !AppSettings.isAddressRulesEnabled(vpnService)) {
            engine.setRewriteRules("")
            return
        }
        engine.setRewriteRules(JSONObject(cnameRewriteRuleManager.cnameRedirects()).toString())
    }

    fun updateRequestRules() {
        if (!inspectionEnabled || !AppSettings.isAddressRulesEnabled(vpnService)) {
            engine.setRequestRules("")
            return
        }
        engine.setRequestRules(runBlocking { goUrlRuleManager.jsonSnapshot() })
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
        val root = JSONObject()
        for ((pkg, domains) in rules) {
            val uid = packageUid(pkg) ?: continue
            val validDomains = domains.filter { it.isNotBlank() }
            if (validDomains.isEmpty()) continue
            val arr = JSONArray()
            validDomains.forEach { arr.put(it) }
            root.put(uid.toString(), arr)
        }
        engine.setAppAllowlist(root.toString())
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
            engine.setRewriteRules("")
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
        // DNS 过滤与 HTTPS 检测强制联动：检测运行期间域名级规则（订阅/自定义屏蔽与白名单）
        // 必须保持生效，HTTPS 检测不得在 DNS 过滤关闭的情况下单独运行；
        // 解密后的 HTTP 流量在 DNS 过滤结果之上再做 URL 级规则匹配。
        engine.setFilterDNS(true)
        pushRuleSnapshot()
        engine.setBatchLogCallback(object : BatchLogCallback {
            override fun onDNSQueryBatch(jsonLogs: String) {
                if (jsonLogs.isBlank()) return
                scope.launch {
                    processLogBatch(jsonLogs)
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
                    val blockSubscriptionId = resolveHttpBlockSubscriptionId(authority, httpOutcome, packageName.ifBlank { null })
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

    private suspend fun processLogBatch(jsonLogs: String) {
        val array = runCatching { JSONArray(jsonLogs) }.getOrNull() ?: return
        val len = array.length()
        if (len == 0) return

        val entities = ArrayList<DnsLogEntity>(len)
        for (i in 0 until len) {
            val obj = array.optJSONObject(i) ?: continue
            val domain = obj.optString("d")
            val blocked = obj.optBoolean("b")
            val queryType = obj.optInt("t")
            val responseTimeMs = obj.optLong("r")
            val appName = obj.optString("a")
            val resolvedIPs = obj.optString("i")
            val blockedBy = obj.optString("k")
            val errorMessage = obj.optString("e")
            val cached = obj.optBoolean("c")
            val timestamp = obj.optLong("ts").takeIf { it > 0 } ?: System.currentTimeMillis()

            val result = when {
                errorMessage.isNotBlank() -> LogResult.ERROR
                blockedBy.startsWith("rewrite=") -> LogResult.REWRITTEN
                blocked -> LogResult.BLOCKED
                else -> LogResult.PASSED
            }
            val effectivePackage = appName.ifBlank { null }
            val effectiveBlockedBy: String
            val blockSubId: Long?
            val isConnectionLog = blockedBy == "connection"

            if (result == LogResult.BLOCKED) {
                val decision = dnsPolicy.evaluate(domain, effectivePackage)
                val ruleTypeTag = if (decision.isAppSpecific) "app rule" else if (decision.matchedRule != null) "global rule" else null
                effectiveBlockedBy = if (ruleTypeTag != null && blockedBy.isNotBlank()) "$blockedBy ($ruleTypeTag)" else (ruleTypeTag ?: blockedBy)
                blockSubId = (decision as? DomainDecision.Block)?.source?.subscriptionIdOrNull()
                    ?: parseBlockSubscriptionIdFromToken(blockedBy)
            } else if (blockedBy.startsWith("rewrite=")) {
                effectiveBlockedBy = blockedBy
                blockSubId = null
            } else if (isConnectionLog) {
                effectiveBlockedBy = "connection"
                blockSubId = null
            } else {
                effectiveBlockedBy = ""
                blockSubId = null
            }

            if (dnsLogger.isLoggable(result)) {
                entities.add(
                    DnsLogEntity(
                        timestamp = timestamp,
                        queryName = domain.lowercase(),
                        queryType = queryType,
                        result = result.value,
                        message = buildDnsLogMessage(appName, resolvedIPs, effectiveBlockedBy, errorMessage, responseTimeMs),
                        cached = cached,
                        blockSubscriptionId = blockSubId,
                        packageName = effectivePackage
                    )
                )
            }

            if (result == LogResult.PASSED && !isConnectionLog) {
                if (cached) {
                    dnsCache.recordCacheHit(domain, queryType)
                } else if (resolvedIPs.isNotBlank()) {
                    dnsCache.recordResolved(domain, queryType, resolvedIPs)
                }
            }
        }

        if (entities.isNotEmpty()) {
            dnsLogger.logBatch(entities)
        }
    }

    private fun resolveHttpBlockSubscriptionId(
        authority: String,
        outcome: HttpRequestOutcome,
        packageName: String? = null
    ): Long? {
        if (outcome != HttpRequestOutcome.BLOCKED) return null
        return resolveBlockSubscriptionId(authority, packageName)
    }

    private fun resolveDnsBlockSubscriptionId(
        domain: String,
        result: LogResult,
        blockedBy: String,
        packageName: String? = null
    ): Long? {
        if (result != LogResult.BLOCKED) return null
        resolveBlockSubscriptionId(domain, packageName)?.let { return it }
        // Go may pass comma-joined filter ids; accept a direct sub_<id> token.
        return blockedBy
            .split(',')
            .map { it.trim() }
            .firstNotNullOfOrNull { token ->
                if (token.startsWith("sub_")) token.removePrefix("sub_").toLongOrNull() else null
            }
    }

    private fun resolveBlockSubscriptionId(authority: String, packageName: String? = null): Long? {
        if (authority.isBlank()) return null
        val source = (dnsPolicy.evaluate(authority, packageName) as? DomainDecision.Block)?.source ?: return null
        return source.subscriptionIdOrNull()
    }

    private fun parseBlockSubscriptionIdFromToken(blockedBy: String): Long? {
        return blockedBy
            .split(',')
            .map { it.trim() }
            .firstNotNullOfOrNull { token ->
                if (token.startsWith("sub_")) token.removePrefix("sub_").toLongOrNull() else null
            }
    }
    private fun HttpsDnsConfigSnapshot.toJson(): String = JSONObject()
            .put("mode", mode.storageValue)
            .put("blockResponse", blockResponseMode.goValue)
            .put("dynamicResponse", JSONObject()
                .put("enabled", dynamicBlockResponseConfig.enabled)
                .put("requestThreshold", dynamicBlockResponseConfig.requestThreshold)
                .put("windowSeconds", dynamicBlockResponseConfig.windowSeconds)
                .put("nxDomainDurationSeconds", dynamicBlockResponseConfig.nxDomainDurationSeconds))
            .put("cache", JSONObject()
                .put("enabled", cachePolicy.enabled)
                .put("mode", cachePolicy.mode.storageValue)
                .put("maxTtlSeconds", cachePolicy.maxTtlSeconds)
                .put("fixedTtlSeconds", cachePolicy.fixedTtlSeconds)
                .put("minTtlEnabled", cachePolicy.minTtlEnabled)
                .put("minTtlSeconds", cachePolicy.minTtlSeconds)
                .put("staleFallbackEnabled", cachePolicy.staleFallbackEnabled)
                .put("staleFallbackSeconds", cachePolicy.staleFallbackSeconds))
            .put("providers", JSONArray().apply {
                providers.forEach { provider ->
                    put(JSONObject()
                        .put("id", provider.id)
                        .put("protocol", provider.protocol.goProtocol)
                        .put("server", when (provider.protocol) {
                            DnsProtocol.DNS, DnsProtocol.DOT -> provider.hostPort()
                            DnsProtocol.DOH -> ""
                        })
                        .put("url", provider.url))
                }
            })
            .put("bootstrap", JSONObject()
                .put("enabled", bootstrapEnabled)
                .put("ips", JSONArray().apply {
                    bootstrapIps.forEach { entry ->
                        put(JSONObject()
                            .put("id", entry.id)
                            .put("name", entry.name)
                            .put("ip", entry.ip))
                    }
                }))
            .toString()

    private val DnsProtocol.goProtocol: String
        get() = when (this) {
            DnsProtocol.DNS -> "PLAIN"
            DnsProtocol.DOH -> "DOH"
            DnsProtocol.DOT -> "DOT"
        }

    private fun DnsProvider.hostPort(): String =
        if (host.contains(':') && !host.startsWith('[')) "[$host]:$port" else "$host:$port"

    private val BlockResponseMode.goValue: String
        get() = when (this) {
            BlockResponseMode.NXDOMAIN -> "NXDOMAIN"
            BlockResponseMode.NODATA -> "NODATA"
            BlockResponseMode.REFUSED -> "REFUSED"
            BlockResponseMode.ZERO_ADDRESS -> "CUSTOM_IP"
        }

    private fun packageUid(packageName: String): Int? =
        runCatching { context.packageManager.getPackageUid(packageName, 0) }.getOrNull()

    private companion object {
        const val TAG = "GoInspectionTunnel"
    }
}

@ConsistentCopyVisibility
data class HttpsDnsConfigSnapshot private constructor(
    val providers: List<DnsProvider>,
    val mode: DnsResolutionMode,
    val blockResponseMode: BlockResponseMode,
    val dynamicBlockResponseConfig: DynamicBlockResponseConfig,
    val cachePolicy: DnsCachePolicy,
    val bootstrapEnabled: Boolean = false,
    val bootstrapIps: List<BootstrapIpEntry> = emptyList()
) {
    companion object {
        fun create(
            providers: List<DnsProvider>,
            mode: DnsResolutionMode,
            blockResponseMode: BlockResponseMode,
            dynamicBlockResponseConfig: DynamicBlockResponseConfig,
            cachePolicy: DnsCachePolicy,
            bootstrapEnabled: Boolean = false,
            bootstrapIps: List<BootstrapIpEntry> = emptyList()
        ): HttpsDnsConfigSnapshot {
            require(providers.isNotEmpty()) { "DNS provider list must not be empty" }
            val selected = if (mode == DnsResolutionMode.SINGLE) listOf(providers.first()) else providers
            return HttpsDnsConfigSnapshot(
                selected,
                mode,
                blockResponseMode,
                dynamicBlockResponseConfig,
                cachePolicy,
                bootstrapEnabled,
                bootstrapIps
            )
        }
    }
}

private fun buildDnsLogMessage(
    appName: String,
    resolvedIPs: String,
    blockedBy: String,
    errorMessage: String,
    responseTimeMs: Long
): String? = listOfNotNull(
    appName.takeIf { it.isNotBlank() }?.let { "app=$it" },
    resolvedIPs.takeIf { it.isNotBlank() }?.let { "resolved=$it" },
    blockedBy.takeIf { it.isNotBlank() }?.let { "blocked_by=$it" },
    errorMessage.takeIf { it.isNotBlank() }?.let { "error=$it" },
    responseTimeMs.takeIf { it > 0 }?.let { "elapsed=${it}ms" }
).joinToString(", ").takeIf { it.isNotEmpty() }


private fun String.subscriptionIdOrNull(): Long? =
    if (startsWith("sub_")) removePrefix("sub_").toLongOrNull() else null

private fun String.toHttpRequestOutcome(): HttpRequestOutcome = when (this) {
    "blocked" -> HttpRequestOutcome.BLOCKED
    "rewritten" -> HttpRequestOutcome.REWRITTEN
    "decryption_failed" -> HttpRequestOutcome.DECRYPTION_FAILED
    "invalid" -> HttpRequestOutcome.INVALID
    else -> HttpRequestOutcome.ALLOWED
}

private class CachedConnectionOwnerUidResolver(private val cache: UidPackageCache) : UIDResolver {
    override fun resolveUID(
        protocol: Long,
        localIP: String,
        localPort: Long,
        remoteIP: String,
        remotePort: Long
    ): Long {
        return cache.resolveUid(
            protocol.toInt(),
            localIP,
            localPort.toInt(),
            remoteIP,
            remotePort.toInt()
        ).toLong()
    }
}

private class CachedAppPackageResolver(private val cache: UidPackageCache) : AppUidResolver {
    override fun packageForUid(uid: Long): String =
        cache.resolvePackageForUid(uid.toInt()).orEmpty()
}
