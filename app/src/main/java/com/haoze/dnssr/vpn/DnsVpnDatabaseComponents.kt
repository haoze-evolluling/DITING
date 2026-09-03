package com.haoze.dnssr.vpn

import android.content.Context
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.ui.DnsLogMode
import com.haoze.dnssr.vpn.cache.DnsCacheController
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import com.haoze.dnssr.vpn.cache.DnsResponseCache
import com.haoze.dnssr.vpn.traffic.TrafficStatsManager
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * 集中管理 VPN 运行时所依赖的数据库、规则管理器、日志记录器及缓存组件。
 */
class DnsVpnDatabaseComponents {

    lateinit var dnsCache: DnsResponseCache
        private set
    lateinit var uidPackageCache: UidPackageCache
        private set
    lateinit var blockListManager: BlockListManager
        private set
    lateinit var allowListManager: AllowListManager
        private set
    lateinit var rewriteRuleManager: RewriteRuleManager
        private set
    lateinit var domainPolicy: DomainPolicy
        private set
    lateinit var goUrlRuleManager: GoUrlRuleManager
        private set
    lateinit var dnsLogger: DnsLogger
        private set
    lateinit var httpRequestLogger: HttpRequestLogger
        private set
    lateinit var raceLogger: RaceLogger
        private set
    lateinit var bootstrapLogger: BootstrapLogger
        private set
    lateinit var bootstrapHealthEngine: BootstrapHealthEngine
        private set

    private lateinit var bootstrapHealthListener: BootstrapHealthStoreListener

    /**
     * 初始化各组件并注册监听器。
     */
    fun initialize(
        context: Context,
        scope: CoroutineScope,
        activeDnsCachePolicy: DnsCachePolicy,
        activeDnsLogMode: () -> DnsLogMode,
        activeLogRetentionDays: () -> Int,
        isDomainRulesEnabled: () -> Boolean,
        onBootstrapHealthReset: () -> Unit,
        onClearGoDnsCache: () -> Unit
    ) {
        val db = AppDatabase.getInstance(context)
        uidPackageCache = UidPackageCache(context)
        dnsCache = DnsResponseCache(db.dnsCacheDao(), activeDnsCachePolicy, scope)
        val ruleIndexDirectory = File(context.filesDir, "rule-index")
        blockListManager = BlockListManager(db.blockRuleDao(), ruleIndexDirectory)
        allowListManager = AllowListManager(db.allowRuleDao(), ruleIndexDirectory)
        rewriteRuleManager = RewriteRuleManager(db.rewriteRuleDao(), ruleIndexDirectory)
        domainPolicy = DomainPolicy(allowListManager, blockListManager) { isDomainRulesEnabled() }
        blockListManager.onCacheChanged = { domainPolicy.invalidateCache() }
        allowListManager.onCacheChanged = { domainPolicy.invalidateCache() }
        goUrlRuleManager = GoUrlRuleManager(db.goUrlRuleDao())
        dnsLogger = DnsLogger(db.dnsLogDao(), flushScope = scope) { activeDnsLogMode() }
        httpRequestLogger = HttpRequestLogger(db.httpRequestLogDao(), flushScope = scope) { activeDnsLogMode() }
        raceLogger = RaceLogger(db.raceLogDao(), flushScope = scope)
        bootstrapHealthEngine = BootstrapHealthEngine(context, scope)
        bootstrapLogger = BootstrapLogger(db.bootstrapLogDao(), flushScope = scope)

        bootstrapHealthListener = object : BootstrapHealthStoreListener {
            override fun onBootstrapHealthReset(ipIds: Set<String>) {
                onBootstrapHealthReset()
            }
        }
        BootstrapHealthStore.registerListener(bootstrapHealthListener)
        LogMaintenance.start(scope, db) { activeLogRetentionDays() }

        // 启动时全量加载规则到内存缓存与预热 DNS 缓存
        scope.launch { blockListManager.refreshCache() }
        scope.launch { allowListManager.refreshCache() }
        scope.launch { rewriteRuleManager.refreshCache() }
        scope.launch {
            DnsCacheController.register(dnsCache) { onClearGoDnsCache() }
            dnsCache.warmUp()
        }
    }

    /**
     * 异步刷盘所有日志、缓存和统计数据。
     */
    suspend fun flushLoggers(context: Context) {
        if (::dnsCache.isInitialized) {
            dnsCache.flushPendingWrites()
            dnsCache.flushPendingHits()
        }
        if (::dnsLogger.isInitialized) {
            dnsLogger.flush()
        }
        if (::httpRequestLogger.isInitialized) {
            httpRequestLogger.flush()
        }
        if (::raceLogger.isInitialized) {
            raceLogger.flush()
        }
        if (::bootstrapLogger.isInitialized) {
            bootstrapLogger.flush()
        }
        if (::bootstrapHealthEngine.isInitialized) {
            bootstrapHealthEngine.flush(commit = true)
        }
        TrafficStatsManager.flush(context)
    }

    /**
     * 同步阻塞刷盘所有日志、缓存和统计数据。
     */
    fun flushLoggersBlocking(context: Context) {
        runBlocking {
            flushLoggers(context)
        }
    }

    /**
     * 关闭资源与注销监听。
     */
    fun close() {
        if (::rewriteRuleManager.isInitialized) {
            rewriteRuleManager.close()
        }
        if (::dnsCache.isInitialized) {
            runBlocking { DnsCacheController.unregister(dnsCache) }
        }
        if (::bootstrapHealthEngine.isInitialized) {
            bootstrapHealthEngine.close()
        }
        if (::bootstrapHealthListener.isInitialized) {
            BootstrapHealthStore.unregisterListener(bootstrapHealthListener)
        }
    }
}
