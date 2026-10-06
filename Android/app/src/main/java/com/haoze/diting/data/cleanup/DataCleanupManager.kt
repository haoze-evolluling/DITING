package com.haoze.diting.data.cleanup
import com.haoze.diting.core.cert.GoInspectionCaManager

import android.content.Context
import com.haoze.diting.crash.CrashLogManager
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.DnsRulesDatabase
import com.haoze.diting.data.ExpressRulesDatabase
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
import com.haoze.diting.core.rule.AllowListManager
import com.haoze.diting.core.rule.BlockListManager
import com.haoze.diting.core.diagnostic.BootstrapHealthStore
import com.haoze.diting.core.rule.DefaultWhitelistSeeder
import com.haoze.diting.core.rule.RuleIndexLayout
import com.haoze.diting.core.log.LogMaintenance
import com.haoze.diting.core.diagnostic.ProviderHealthStore
import com.haoze.diting.core.rule.RewriteRuleManager
import com.haoze.diting.core.cache.DnsCacheController
import com.haoze.diting.core.traffic.TrafficStatsManager
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
        database: AppDatabase = AppDatabase.getInstance(context),
        dataset: RuleDataset = RuleDataset.NORMAL
    ) = withContext(Dispatchers.IO) {
        if (dataset == RuleDataset.EXPRESS) {
            val expressDb = ExpressRulesDatabase.getInstance(context)
            expressDb.dnsLogDao().clearAll()
            expressDb.raceLogDao().clearAll()
            expressDb.bootstrapLogDao().clearAll()
        } else {
            LogMaintenance.clearAllLogs(database)
        }
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
        database: AppDatabase = AppDatabase.getInstance(context),
        dataset: RuleDataset = RuleDataset.NORMAL
    ) = withContext(Dispatchers.IO) {
        if (dataset == RuleDataset.EXPRESS) {
            val expressDb = ExpressRulesDatabase.getInstance(context)
            expressDb.dnsCacheDao().clearAll()
            com.haoze.diting.express.ExpressSettingsRefresher.clearCacheIfRunning(context)
        } else {
            DnsCacheController.clearAll(database.dnsCacheDao())
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, dataset = dataset)
        }
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
    suspend fun clearAllDomainRules(
        context: Context,
        dataset: RuleDataset = RuleDataset.NORMAL
    ) = withContext(Dispatchers.IO) {
        when (dataset) {
            RuleDataset.EXPRESS -> {
                val expressDb = ExpressRulesDatabase.getInstance(context)
                clearDomainRulesData(
                    expressDb.blockRuleDao(),
                    expressDb.allowRuleDao(),
                    expressDb.rewriteRuleDao(),
                    expressDb.cosmeticRuleDao(),
                    expressDb.subscriptionDao(),
                    expressDb.subscriptionAutoUpdateDao()
                )
                com.haoze.diting.express.ExpressDefaultsSeeder.seedDefaults(context, forceReset = true)
                val expressIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.EXPRESS)
                File(expressIndexDir, "domain").deleteRecursively()
                RuleIndexLayout.hostsIndex(expressIndexDir).delete()
                runCatching {
                    AllowListManager(expressDb.allowRuleDao(), expressIndexDir).refreshCache(forceRebuild = true)
                    BlockListManager(expressDb.blockRuleDao(), expressIndexDir).refreshCache(forceRebuild = true)
                    RewriteRuleManager(expressDb.rewriteRuleDao(), expressIndexDir).refreshCache(rebuildSubscriptionIndex = true)
                }
                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = true,
                    refreshAllow = true,
                    refreshRewrite = true,
                    dataset = RuleDataset.EXPRESS
                )
            }
            RuleDataset.DNS_MODE -> {
                val dnsDb = DnsRulesDatabase.getInstance(context)
                clearDomainRulesData(
                    dnsDb.blockRuleDao(),
                    dnsDb.allowRuleDao(),
                    dnsDb.rewriteRuleDao(),
                    dnsDb.cosmeticRuleDao(),
                    dnsDb.subscriptionDao(),
                    dnsDb.subscriptionAutoUpdateDao()
                )
                val dnsIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.DNS_MODE)
                File(dnsIndexDir, "domain").deleteRecursively()
                RuleIndexLayout.hostsIndex(dnsIndexDir).delete()
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, dataset = RuleDataset.DNS_MODE)
            }
            RuleDataset.NORMAL -> {
                val normalDb = AppDatabase.getInstance(context)
                clearDomainRulesData(
                    normalDb.blockRuleDao(),
                    normalDb.allowRuleDao(),
                    normalDb.rewriteRuleDao(),
                    normalDb.cosmeticRuleDao(),
                    normalDb.subscriptionDao(),
                    normalDb.subscriptionAutoUpdateDao()
                )
                DefaultWhitelistSeeder.seed(context, normalDb, forceReset = true)
                val ruleIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.NORMAL)
                File(ruleIndexDir, "domain").deleteRecursively()
                RuleIndexLayout.hostsIndex(ruleIndexDir).delete()
                runCatching {
                    AllowListManager(normalDb.allowRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
                    BlockListManager(normalDb.blockRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
                    RewriteRuleManager(normalDb.rewriteRuleDao(), ruleIndexDir).refreshCache(rebuildSubscriptionIndex = true)
                }
                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = true,
                    refreshAllow = true,
                    refreshRewrite = true,
                    dataset = RuleDataset.NORMAL
                )
            }
        }
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
    suspend fun clearAllAddressRules(
        context: Context,
        dataset: RuleDataset = RuleDataset.NORMAL
    ) = withContext(Dispatchers.IO) {
        when (dataset) {
            RuleDataset.EXPRESS -> {
                val expressDb = ExpressRulesDatabase.getInstance(context)
                clearAddressRulesData(expressDb.goUrlRuleDao(), expressDb.rewriteRuleDao())
                val expressIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.EXPRESS)
                RuleIndexLayout.hostsIndex(expressIndexDir).delete()
                runCatching {
                    RewriteRuleManager(expressDb.rewriteRuleDao(), expressIndexDir).refreshCache(rebuildSubscriptionIndex = true)
                }
                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = false,
                    refreshAllow = false,
                    refreshRewrite = true,
                    dataset = RuleDataset.EXPRESS
                )
            }
            RuleDataset.DNS_MODE -> {
                val dnsDb = DnsRulesDatabase.getInstance(context)
                clearAddressRulesData(dnsDb.goUrlRuleDao(), dnsDb.rewriteRuleDao())
                val dnsIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.DNS_MODE)
                RuleIndexLayout.hostsIndex(dnsIndexDir).delete()
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, dataset = RuleDataset.DNS_MODE)
            }
            RuleDataset.NORMAL -> {
                val normalDb = AppDatabase.getInstance(context)
                clearAddressRulesData(normalDb.goUrlRuleDao(), normalDb.rewriteRuleDao())
                val ruleIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.NORMAL)
                RuleIndexLayout.hostsIndex(ruleIndexDir).delete()
                runCatching {
                    RewriteRuleManager(normalDb.rewriteRuleDao(), ruleIndexDir).refreshCache(rebuildSubscriptionIndex = true)
                }
                RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = false,
                    refreshAllow = false,
                    refreshRewrite = true,
                    dataset = RuleDataset.NORMAL
                )
            }
        }
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
    suspend fun clearAllSubscriptions(
        context: Context,
        dataset: RuleDataset = RuleDataset.NORMAL
    ) = withContext(Dispatchers.IO) {
        when (dataset) {
            RuleDataset.EXPRESS -> {
                val expressDb = ExpressRulesDatabase.getInstance(context)
                clearSubscriptionsData(
                    expressDb.subscriptionDao(),
                    expressDb.subscriptionGroupDao(),
                    expressDb.subscriptionAutoUpdateDao(),
                    expressDb.blockRuleDao(),
                    expressDb.allowRuleDao(),
                    expressDb.rewriteRuleDao(),
                    expressDb.goUrlRuleDao(),
                    expressDb.cosmeticRuleDao()
                )
                val expressIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.EXPRESS)
                RuleIndexLayout.hostsIndex(expressIndexDir).delete()
                runCatching {
                    BlockListManager(expressDb.blockRuleDao(), expressIndexDir).refreshCache(forceRebuild = true)
                    AllowListManager(expressDb.allowRuleDao(), expressIndexDir).refreshCache(forceRebuild = true)
                    RewriteRuleManager(expressDb.rewriteRuleDao(), expressIndexDir).refreshCache(rebuildSubscriptionIndex = true)
                }
                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = true,
                    refreshAllow = true,
                    refreshRewrite = true,
                    dataset = RuleDataset.EXPRESS
                )
            }
            RuleDataset.DNS_MODE -> {
                val dnsDb = DnsRulesDatabase.getInstance(context)
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
                val dnsIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.DNS_MODE)
                RuleIndexLayout.hostsIndex(dnsIndexDir).delete()
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, dataset = RuleDataset.DNS_MODE)
            }
            RuleDataset.NORMAL -> {
                val normalDb = AppDatabase.getInstance(context)
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
                val ruleIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.NORMAL)
                RuleIndexLayout.hostsIndex(ruleIndexDir).delete()
                runCatching {
                    BlockListManager(normalDb.blockRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
                    AllowListManager(normalDb.allowRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
                    RewriteRuleManager(normalDb.rewriteRuleDao(), ruleIndexDir).refreshCache(rebuildSubscriptionIndex = true)
                }
                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    context,
                    refreshBlock = true,
                    refreshAllow = true,
                    refreshRewrite = true,
                    dataset = RuleDataset.NORMAL
                )
                RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            }
        }
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
    suspend fun clearAllLocalData(
        context: Context,
        dataset: RuleDataset = RuleDataset.NORMAL
    ) = withContext(Dispatchers.IO) {
        if (dataset == RuleDataset.EXPRESS) {
            clearRequestLogs(context, dataset = RuleDataset.EXPRESS)
            clearDnsCache(context, dataset = RuleDataset.EXPRESS)
            clearCrashLogs(context)
            resetProviderWeights(context)
            resetBootstrapWeights(context)
            val expressDb = ExpressRulesDatabase.getInstance(context)
            clearDomainRulesData(
                expressDb.blockRuleDao(),
                expressDb.allowRuleDao(),
                expressDb.rewriteRuleDao(),
                expressDb.cosmeticRuleDao(),
                expressDb.subscriptionDao(),
                expressDb.subscriptionAutoUpdateDao()
            )
            clearAddressRulesData(expressDb.goUrlRuleDao(), expressDb.rewriteRuleDao())
            clearSubscriptionsData(
                expressDb.subscriptionDao(),
                expressDb.subscriptionGroupDao(),
                expressDb.subscriptionAutoUpdateDao(),
                expressDb.blockRuleDao(),
                expressDb.allowRuleDao(),
                expressDb.rewriteRuleDao(),
                expressDb.goUrlRuleDao(),
                expressDb.cosmeticRuleDao()
            )
            expressDb.mirrorTemplateDao().clearAll()
            val expressIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.EXPRESS)
            expressIndexDir.deleteRecursively()
            clearDownloadAndTempCache(context)
            clearCustomBackground(context)
            resetSettingsGuides(context)
            context.getSharedPreferences(RuleDataset.EXPRESS.prefsName(), Context.MODE_PRIVATE).edit().clear().apply()
            com.haoze.diting.express.ExpressDefaultsSeeder.seedDefaults(context, forceReset = true)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, reason = "factory_reset", dataset = RuleDataset.EXPRESS)
            return@withContext
        }
        if (dataset == RuleDataset.DNS_MODE) {
            val dnsDb = DnsRulesDatabase.getInstance(context)
            clearDomainRulesData(
                dnsDb.blockRuleDao(),
                dnsDb.allowRuleDao(),
                dnsDb.rewriteRuleDao(),
                dnsDb.cosmeticRuleDao(),
                dnsDb.subscriptionDao(),
                dnsDb.subscriptionAutoUpdateDao()
            )
            clearAddressRulesData(dnsDb.goUrlRuleDao(), dnsDb.rewriteRuleDao())
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
            dnsDb.mirrorTemplateDao().clearAll()
            val dnsIndexDir = RuleIndexLayout.rootDirectory(context.filesDir, RuleDataset.DNS_MODE)
            File(dnsIndexDir, "domain").deleteRecursively()
            RuleIndexLayout.hostsIndex(dnsIndexDir).delete()
            context.getSharedPreferences(RuleDataset.DNS_MODE.prefsName(), Context.MODE_PRIVATE).edit().clear().apply()
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, reason = "factory_reset", dataset = RuleDataset.DNS_MODE)
            return@withContext
        }
        clearRequestLogs(context, dataset = RuleDataset.NORMAL)
        clearTrafficStats(context)
        clearCrashLogs(context)
        clearDnsCache(context, dataset = RuleDataset.NORMAL)
        resetProviderWeights(context)
        resetBootstrapWeights(context)
        clearAllDomainRules(context, dataset = RuleDataset.NORMAL)
        clearAllAddressRules(context, dataset = RuleDataset.NORMAL)
        clearAllSubscriptions(context, dataset = RuleDataset.NORMAL)
        resetAppRules(context)
        resetOutboundProxy(context)
        resetCaCertificate(context)
        clearDownloadAndTempCache(context)
        clearCustomBackground(context)
        resetSettingsGuides(context)

        // 清理镜像模板（仅限 Normal 库）
        val normalDb = AppDatabase.getInstance(context)
        normalDb.mirrorTemplateDao().clearAll()

        // 清理头像与识别库缓存
        deleteDirectoryContents(File(context.filesDir, "avatars"))
        deleteDirectoryContents(File(context.cacheDir, "recognition"))
        context.getSharedPreferences("diting_recognition_members", Context.MODE_PRIVATE).edit().clear().apply()
    }
}
