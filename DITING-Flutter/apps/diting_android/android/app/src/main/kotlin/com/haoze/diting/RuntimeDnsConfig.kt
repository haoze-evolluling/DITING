package com.haoze.diting

import android.content.Context
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import tunnel.Engine

/// Hot-applies a rebuilt DNS config to a running tunnel (legacy `RuntimeDnsSettingsRefresher`),
/// so provider and protocol changes take effect without a restart.
object RuntimeDnsConfig {
    /// Null on success, otherwise the reason shown to the user.
    fun applyNormal(context: Context, dnsConfig: String): String? = apply(
        context = context,
        engine = DitingVpnService.engineForDiagnostics(),
        dnsConfig = dnsConfig,
        prefsName = DitingVpnService.PREFS_NAME,
        configKey = DitingVpnService.KEY_LAST_DNS_CONFIG,
        refreshNotification = DitingVpnService::refreshNotification,
    )

    fun applyExpress(context: Context, dnsConfig: String): String? = apply(
        context = context,
        engine = ExpressVpnService.engineForDiagnostics(),
        dnsConfig = dnsConfig,
        prefsName = ExpressVpnService.PREFS_NAME,
        configKey = ExpressVpnService.KEY_LAST_DNS_CONFIG,
        refreshNotification = ExpressVpnService::refreshNotification,
    )

    private fun apply(
        context: Context,
        engine: Engine?,
        dnsConfig: String,
        prefsName: String,
        configKey: String,
        refreshNotification: (Context) -> Boolean,
    ): String? {
        if (dnsConfig.isBlank()) return "缺少 DNS 配置"
        val current = engine ?: return "服务未运行"
        return runCatching {
            current.applyDNSConfig(dnsConfig)
            // The tile replays this config, so it has to follow the live one.
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                .putString(configKey, dnsConfig)
                .apply()
            refreshNotification(context)
            null
        }.getOrElse { it.message ?: it.javaClass.simpleName }
    }
}
