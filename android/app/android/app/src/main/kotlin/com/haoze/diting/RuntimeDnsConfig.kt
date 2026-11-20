package com.haoze.diting

import android.content.Context
import com.haoze.diting.engine.TunnelEngine
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService

object RuntimeDnsConfig {
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
        engine: TunnelEngine?,
        dnsConfig: String,
        prefsName: String,
        configKey: String,
        refreshNotification: (Context) -> Boolean,
    ): String? {
        if (dnsConfig.isBlank()) return "缺少 DNS 配置"
        val current = engine ?: return "服务未运行"
        return runCatching {
            current.applyDNSConfig(dnsConfig)
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                .putString(configKey, dnsConfig)
                .apply()
            refreshNotification(context)
            null
        }.getOrElse { it.message ?: it.javaClass.simpleName }
    }
}
