package com.haoze.diting.data.cleanup

import android.content.Context
import com.haoze.diting.crash.CrashLogManager
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.DnsRulesDatabase
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.CosmeticRuleDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.dao.SubscriptionGroupDao
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.data.entity.SubscriptionKind
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher
import com.haoze.diting.ui.background.CustomBackgroundManager
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.ui.settings.OutboundProxySettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.vpn.AllowListManager
import com.haoze.diting.vpn.BlockListManager
import com.haoze.diting.vpn.BootstrapHealthStore
import com.haoze.diting.vpn.DefaultWhitelistSeeder
import com.haoze.diting.vpn.RuleIndexLayout
import com.haoze.diting.vpn.GoInspectionCaManager
import com.haoze.diting.vpn.LogMaintenance
import com.haoze.diting.vpn.ProviderHealthStore
import com.haoze.diting.vpn.RewriteRuleManager
import com.haoze.diting.vpn.cache.DnsCacheController
import com.haoze.diting.vpn.traffic.TrafficStatsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 集中管理应用各类本地持久化数据、统计记录、规则、日志及缓存的清理控制器。
 */
object DataCleanupManager {

    /**
     * 清理所有 DNS、HTTP 请求日志、竞速统计及 Bootstrap 解析日志。
     */
    suspend fun clearRequestLogs(
        context: Context,
        database: AppDatabase = AppDatabase.getInstance(context)
    ) = withContext(Dispatchers.IO) {
        LogMaintenance.clearAllLogs(database)
    }

    /**
     * 清理所有应用的历史流量统计与实时统计内存状态。
     */
    suspend fun clearTrafficStats(
        context: Context,
        database: AppDatabase = AppDatabase.getInstance(context)
    ) = withContext(Dispatchers.IO) {
        TrafficStatsManager.clearAllTrafficStats(context)
        LogMaintenance.clearAllTrafficStats(database)
    }

    /**
     * 清理本地所有崩溃日志记录及连续崩溃统计状态。
     */
    fun clearCrashLogs(context: Context): Boolean {
        return CrashLogManager.clearCrashLogs(context)
    }

    /**
     * 清理本地 DNS 缓存记录（包括内存缓存、后端引擎缓存与数据库持久化）。
     */
    suspend fun clearDnsCache(
        context: Context,
        database: AppDatabase = AppDatabase.getInstance(context)
    ) = withContext(Dispatchers.IO) {
        DnsCacheController.clearAll(database.dnsCacheDao())
    }

    /**
     * 清除 DNS 服务商健康样本与历史竞速统计，恢复默认分配权重。
     */
    suspend fun resetProviderWeights(context: Context) = withContext(Dispatchers.IO) {
        ProviderHealthStore.clearAll(context)
    }

    /**
     * 清除 Bootstrap DNS 解析健康样本与延迟统计，恢复默认选择权重。
     */
    suspend fun resetBootstrapWeights(context: Context) = withContext(Dispatchers.IO) {
        BootstrapHealthStore.clearAll(context)
    }

    /**
     * 清理全部域名规则（黑名单、白名单、IPv4/IPv6 覆写、修饰规则及对应域名订阅），
     * 重新注入预设默认白名单，并同步刷新磁盘索引与运行中引擎。
     */
    suspend fun clearAllDomainRules(context: Context) = withContext(Dispatchers.IO) {
        val normalDb = AppDatabase.getInstance(context)
        val dnsDb = DnsRulesDatabase.getInstance(context)

        // 1. AppDatabase（VPN 模式）
        clearDomainRulesData(
            normalDb.blockRuleDao(),
            normalDb.allowRuleDao(),
            normalDb.rewriteRuleDao(),
            normalDb.cosmeticRuleDao(),
            normalDb.subscriptionDao(),
            normalDb.subscriptionAutoUpdateDao()
        )
        DefaultWhitelistSeeder.seed(context, normalDb, forceReset = true)

        // 2. DnsRulesDatabase（DNS 模式）
        clearDomainRulesData(
            dnsDb.blockRuleDao(),
            dnsDb.allowRuleDao(),
            dnsDb.rewriteRuleDao(),
            dnsDb.cosmeticRuleDao(),
            dnsDb.subscriptionDao(),
            dnsDb.subscriptionAutoUpdateDao()
        )

        // 3. 磁盘索引重建
        val ruleIndexDir = File(context.filesDir, "rule-index")
        File(ruleIndexDir, "domain").deleteRecursively()
        RuleIndexLayout.hostsIndex(ruleIndexDir).delete()
        runCatching {
            AllowListManager(normalDb.allowRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
            BlockListManager(normalDb.blockRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
            RewriteRuleManager(normalDb.rewriteRuleDao(), ruleIndexDir).refreshCache(rebuildSubscriptionIndex = true)
        }

        // 4. 同步运行时服务
        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
            context,
            refreshBlock = true,
            refreshAllow = true,
            refreshRewrite = true,
            dataset = RuleDataset.NORMAL
        )
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, dataset = RuleDataset.DNS_MODE)
    }

    internal suspend fun clearDomainRulesData(
        blockDao: BlockRuleDao,
        allowDao: AllowRuleDao,
        rewriteDao: RewriteRuleDao,
        cosmeticDao: CosmeticRuleDao,
        subscriptionDao: SubscriptionDao,
        subscriptionAutoUpdateDao: SubscriptionAutoUpdateDao? = null
    ) {
        blockDao.clearAll()
        allowDao.clearAll()
        rewriteDao.clearByTargetTypes(listOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6))
        cosmeticDao.clearAll()
        cosmeticDao.clearAllSources()
        subscriptionDao.deleteByKind(SubscriptionKind.DOMAIN)
        subscriptionAutoUpdateDao?.deleteOrphans()
    }

    /**
     * 清理全部地址规则（URL 屏蔽、URL 放行及 CNAME 覆写规则），不干扰域名黑白名单与域名订阅。
     */
    suspend fun clearAllAddressRules(context: Context) = withContext(Dispatchers.IO) {
        val normalDb = AppDatabase.getInstance(context)
        val dnsDb = DnsRulesDatabase.getInstance(context)

        // 1. AppDatabase
        clearAddressRulesData(normalDb.goUrlRuleDao(), normalDb.rewriteRuleDao())

        // 2. DnsRulesDatabase
        clearAddressRulesData(dnsDb.goUrlRuleDao(), dnsDb.rewriteRuleDao())

        // 3. 刷新 hosts 覆写索引
        val ruleIndexDir = File(context.filesDir, "rule-index")
        RuleIndexLayout.hostsIndex(ruleIndexDir).delete()
        runCatching {
            RewriteRuleManager(normalDb.rewriteRuleDao(), ruleIndexDir).refreshCache(rebuildSubscriptionIndex = true)
        }

        // 4. 同步运行时引擎
        RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
            context,
            refreshBlock = false,
            refreshAllow = false,
            refreshRewrite = true,
            dataset = RuleDataset.NORMAL
        )
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, dataset = RuleDataset.DNS_MODE)
    }

    internal suspend fun clearAddressRulesData(
        goUrlDao: GoUrlRuleDao,
        rewriteDao: RewriteRuleDao
    ) {
        goUrlDao.clearAll()
        rewriteDao.clearByTargetType(RewriteTargetType.CNAME)
    }

    /**
     * 清理所有规则订阅（网络订阅、本地订阅、分组配置、自动更新任务队列以及由订阅引入的所有规则）。
     */
    suspend fun clearAllSubscriptions(context: Context) = withContext(Dispatchers.IO) {
        val normalDb = AppDatabase.getInstance(context)
        val dnsDb = DnsRulesDatabase.getInstance(context)

        // 1. AppDatabase
        clearSubscriptionsData(
            normalDb.subscriptionDao(),
            normalDb.subscriptionGroupDao(),
            normalDb.subscriptionAutoUpdateDao(),
            normalDb.blockRuleDao(),
            normalDb.allowRuleDao(),
            normalDb.rewriteRuleDao(),
            normalDb.goUrlRuleDao(),
            normalDb.cosmeticRuleDao()
        )

        // 2. DnsRulesDatabase
        clearSubscriptionsData(
            dnsDb.subscriptionDao(),
            dnsDb.subscriptionGroupDao(),
            dnsDb.subscriptionAutoUpdateDao(),
            dnsDb.blockRuleDao(),
            dnsDb.allowRuleDao(),
            dnsDb.rewriteRuleDao(),
            dnsDb.goUrlRuleDao(),
            dnsDb.cosmeticRuleDao()
        )

        // 3. 索引刷新与缓存同步
        val ruleIndexDir = File(context.filesDir, "rule-index")
        RuleIndexLayout.hostsIndex(ruleIndexDir).delete()
        runCatching {
            BlockListManager(normalDb.blockRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
            AllowListManager(normalDb.allowRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
            RewriteRuleManager(normalDb.rewriteRuleDao(), ruleIndexDir).refreshCache(rebuildSubscriptionIndex = true)
        }

        // 4. 同步运行时服务
        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
            context,
            refreshBlock = true,
            refreshAllow = true,
            refreshRewrite = true,
            dataset = RuleDataset.NORMAL
        )
        RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, dataset = RuleDataset.DNS_MODE)
    }

    internal suspend fun clearSubscriptionsData(
        subscriptionDao: SubscriptionDao,
        subscriptionGroupDao: SubscriptionGroupDao,
        subscriptionAutoUpdateDao: SubscriptionAutoUpdateDao,
        blockDao: BlockRuleDao,
        allowDao: AllowRuleDao,
        rewriteDao: RewriteRuleDao,
        goUrlDao: GoUrlRuleDao,
        cosmeticDao: CosmeticRuleDao
    ) {
        subscriptionDao.clearAll()
        subscriptionGroupDao.clearAll()
        subscriptionAutoUpdateDao.clear()
        blockDao.clearSubscriptionRules()
        allowDao.clearSubscriptionRules()
        rewriteDao.clearSubscriptionRules()
        goUrlDao.clearSubscriptionRules()
        cosmeticDao.clearSubscriptionRules()
    }

    /**
     * 重置 HTTPS 抓包本地自签名根证书与私钥，并同步抓包就绪状态。
     */
    fun resetCaCertificate(context: Context) {
        GoInspectionCaManager.reset(context)
        AppRulesSettingsStore.setHttpsInspectionReady(context, false)
        val wasEnabled = AppRulesSettingsStore.isHttpInspectionEnabled(context)
        AppRulesSettingsStore.setHttpInspectionEnabled(context, false)
        if (wasEnabled) {
            RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        }
    }

    /**
     * 重置所有应用控制名单（分应用排除、禁止联网应用、应用独立白名单及 HTTP/HTTPS 抓包应用配置）。
     */
    fun resetAppRules(context: Context) {
        AppRulesSettingsStore.resetAppControlRules(context)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        RuntimeDnsSettingsRefresher.refreshAppAllowlistIfRunning(context)
        RuntimeDnsSettingsRefresher.refreshIfRunning(context)
    }

    /**
     * 重置出站代理配置，恢复默认关闭与直接连接。
     */
    fun resetOutboundProxy(context: Context) {
        OutboundProxySettingsStore.resetOutboundProxy(context)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        RuntimeDnsSettingsRefresher.refreshIfRunning(context)
    }

    /**
     * 清理应用更新下载安装包及临时文件缓存目录。
     */
    fun clearDownloadAndTempCache(context: Context) {
        // 1. 更新安装包
        deleteDirectoryContents(File(context.filesDir, "updates"))
        SystemSettingsStore.clearAppUpdateDownload(context)

        // 2. 内部与外部临时缓存
        deleteDirectoryContents(context.cacheDir)
        deleteDirectoryContents(context.externalCacheDir)
    }

    internal fun deleteDirectoryContents(dir: File?) {
        if (dir != null && dir.exists()) {
            dir.listFiles()?.forEach { file ->
                runCatching {
                    if (file.isDirectory) file.deleteRecursively() else file.delete()
                }
            }
        }
    }

    /**
     * 清除自定义背景图片缓存与偏好配置，恢复默认背景。
     */
    fun clearCustomBackground(context: Context) {
        CustomBackgroundManager.clearActiveCache(context)
        val prefs = context.getSharedPreferences("appearance_settings", Context.MODE_PRIVATE)
        prefs.edit()
            .remove("custom_background_enabled")
            .remove("custom_background_uri")
            .remove("custom_background_uris")
            .apply()
        CustomBackgroundManager.onBackgroundSettingsChanged(context, false, null)
    }

    /**
     * 重置所有新手引导说明与首次使用协议同意状态。
     */
    fun resetSettingsGuides(context: Context) {
        SystemSettingsStore.resetAllSettingsGuides(context)
    }

    /**
     * 一键全面清理：按序清理所有运行日志、流量统计、崩溃记录、DNS 缓存、权重、规则、订阅、应用控制、出站代理、证书与缓存。
     */
    suspend fun clearAllLocalData(context: Context) = withContext(Dispatchers.IO) {
        clearRequestLogs(context)
        clearTrafficStats(context)
        clearCrashLogs(context)
        clearDnsCache(context)
        resetProviderWeights(context)
        resetBootstrapWeights(context)
        clearAllDomainRules(context)
        clearAllAddressRules(context)
        clearAllSubscriptions(context)
        resetAppRules(context)
        resetOutboundProxy(context)
        resetCaCertificate(context)
        clearDownloadAndTempCache(context)
        clearCustomBackground(context)
        resetSettingsGuides(context)

        // 清理镜像模板
        val normalDb = AppDatabase.getInstance(context)
        val dnsDb = DnsRulesDatabase.getInstance(context)
        normalDb.mirrorTemplateDao().clearAll()
        dnsDb.mirrorTemplateDao().clearAll()

        // 清理头像与识别库缓存
        deleteDirectoryContents(File(context.filesDir, "avatars"))
        deleteDirectoryContents(File(context.cacheDir, "recognition"))
        context.getSharedPreferences("diting_recognition_members", Context.MODE_PRIVATE).edit().clear().apply()
    }
}
