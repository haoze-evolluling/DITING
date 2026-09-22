package com.haoze.diting.ui.transfer

import android.content.Context
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.ConfigImportProgress
import com.haoze.diting.ui.ConfigImportResult
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher

/**
 * Orchestrates importing configuration data across providers, networks, rules, app rules, and preferences.
 */
class ConfigImporter(private val context: Context) {
    private val database = AppDatabase.getInstance(context)

    suspend fun import(
        config: TransferConfig,
        onProgress: (ConfigImportProgress) -> Unit = {}
    ): ConfigImportResult {
        val total = config.providers.size + config.bootstrapIps.size + config.subscriptions.size +
            config.mirrorTemplates.size + config.customBlockRules.size + config.customAllowRules.size +
            config.customRewriteDomainRules.size + config.customRewriteCnameRules.size + config.customAddressRules.size +
            config.excludedApps.size + config.blockedApps.size + config.appAllowlistRules.size +
            (if (config.bootstrapPresetIds != null) 1 else 0) +
            (if (config.dnsCache != null) 1 else 0) +
            (if (config.outboundProxy != null) 1 else 0) +
            (if (config.httpInspection != null) 1 else 0) +
            (if (config.appearance != null) 1 else 0) +
            (if (config.systemSettings != null) 1 else 0)

        val session = ImportSessionContext(
            context = context,
            database = database,
            total = total,
            onProgress = onProgress
        )

        session.report("正在读取配置文件", "成功解析配置文件（版本 V${config.formatVersion}）")

        val providerImporter = ProviderConfigImporter(session)
        val networkImporter = NetworkFeatureConfigImporter(session)
        val ruleImporter = RuleConfigImporter(session)
        val appRuleImporter = AppRuleConfigImporter(session)
        val preferenceImporter = PreferenceConfigImporter(session)

        providerImporter.importProvidersAndResolution(config)
        networkImporter.importNetworkFeatures(config)
        ruleImporter.importRules(config)
        appRuleImporter.importAppRules(config)
        preferenceImporter.importPreferences(config)

        if (session.customRulesAdded > 0) {
            RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                context, refreshBlock = true, refreshAllow = true, refreshRewrite = true, scope = RuleScope.DNS
            )
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            session.addLog("已同步更新运行时规则索引")
        }

        session.addLog(
            "导入完成：新增 ${session.added} 项，跳过 ${session.skipped} 项" +
                if (session.failed > 0) "，失败 ${session.failed} 项" else ""
        )

        return session.toResult()
    }
}
