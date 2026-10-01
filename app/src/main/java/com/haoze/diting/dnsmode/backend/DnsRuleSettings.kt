package com.haoze.diting.dnsmode.backend

import android.content.Context
import com.haoze.diting.vpn.BlockResponseMode
import com.haoze.diting.vpn.DynamicBlockResponseConfig

/**
 * Rule-management settings for DNS mode, stored in the DNS mode prefs file so
 * they never touch the normal mode's AppRulesSettingsStore values. Covers the
 * block response policy and subscription auto-update settings of the isolated
 * DNS rule dataset; the filtering master switch is DnsModeConfig.adBlockEnabled.
 */
object DnsRuleSettings {
    private const val PREFS_NAME = "diting_dns_mode_prefs"

    private const val KEY_BLOCK_RESPONSE_MODE = "block_response_mode"
    private const val KEY_DYNAMIC_BLOCK_ENABLED = "block_response_dynamic_enabled"
    private const val KEY_DYNAMIC_BLOCK_THRESHOLD = "block_response_dynamic_threshold"
    private const val KEY_DYNAMIC_BLOCK_WINDOW = "block_response_dynamic_window_seconds"
    private const val KEY_DYNAMIC_BLOCK_NXDOMAIN_DURATION = "block_response_dynamic_nxdomain_duration_seconds"

    private const val KEY_AUTO_UPDATE_ENABLED = "subscription_auto_update_enabled"
    private const val KEY_AUTO_UPDATE_INTERVAL = "subscription_auto_update_interval_hours"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun blockResponseMode(context: Context): BlockResponseMode =
        BlockResponseMode.fromStorageValue(
            prefs(context).getString(KEY_BLOCK_RESPONSE_MODE, BlockResponseMode.NXDOMAIN.storageValue)
        )

    fun setBlockResponseMode(context: Context, mode: BlockResponseMode) {
        prefs(context).edit().putString(KEY_BLOCK_RESPONSE_MODE, mode.storageValue).apply()
    }

    fun dynamicBlockResponseConfig(context: Context): DynamicBlockResponseConfig {
        val stored = prefs(context)
        return DynamicBlockResponseConfig(
            enabled = stored.getBoolean(KEY_DYNAMIC_BLOCK_ENABLED, false),
            requestThreshold = stored.getInt(
                KEY_DYNAMIC_BLOCK_THRESHOLD,
                DynamicBlockResponseConfig.DEFAULT_REQUEST_THRESHOLD
            ).coerceIn(
                DynamicBlockResponseConfig.MIN_REQUEST_THRESHOLD,
                DynamicBlockResponseConfig.MAX_REQUEST_THRESHOLD
            ),
            windowSeconds = stored.getInt(
                KEY_DYNAMIC_BLOCK_WINDOW,
                DynamicBlockResponseConfig.DEFAULT_WINDOW_SECONDS
            ).coerceIn(
                DynamicBlockResponseConfig.MIN_WINDOW_SECONDS,
                DynamicBlockResponseConfig.MAX_WINDOW_SECONDS
            ),
            nxDomainDurationSeconds = stored.getInt(
                KEY_DYNAMIC_BLOCK_NXDOMAIN_DURATION,
                DynamicBlockResponseConfig.DEFAULT_NXDOMAIN_DURATION_SECONDS
            ).coerceIn(
                DynamicBlockResponseConfig.MIN_NXDOMAIN_DURATION_SECONDS,
                DynamicBlockResponseConfig.MAX_NXDOMAIN_DURATION_SECONDS
            )
        )
    }

    fun setDynamicBlockResponseConfig(context: Context, config: DynamicBlockResponseConfig) {
        prefs(context).edit()
            .putBoolean(KEY_DYNAMIC_BLOCK_ENABLED, config.enabled)
            .putInt(
                KEY_DYNAMIC_BLOCK_THRESHOLD,
                config.requestThreshold.coerceIn(
                    DynamicBlockResponseConfig.MIN_REQUEST_THRESHOLD,
                    DynamicBlockResponseConfig.MAX_REQUEST_THRESHOLD
                )
            )
            .putInt(
                KEY_DYNAMIC_BLOCK_WINDOW,
                config.windowSeconds.coerceIn(
                    DynamicBlockResponseConfig.MIN_WINDOW_SECONDS,
                    DynamicBlockResponseConfig.MAX_WINDOW_SECONDS
                )
            )
            .putInt(
                KEY_DYNAMIC_BLOCK_NXDOMAIN_DURATION,
                config.nxDomainDurationSeconds.coerceIn(
                    DynamicBlockResponseConfig.MIN_NXDOMAIN_DURATION_SECONDS,
                    DynamicBlockResponseConfig.MAX_NXDOMAIN_DURATION_SECONDS
                )
            )
            .apply()
    }

    fun autoUpdateEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_AUTO_UPDATE_ENABLED, false)

    fun autoUpdateIntervalHours(context: Context): Int {
        val value = prefs(context).getInt(
            KEY_AUTO_UPDATE_INTERVAL,
            com.haoze.diting.vpn.SubscriptionAutoUpdateSettings.DEFAULT_INTERVAL_HOURS
        )
        return value.takeIf {
            it in com.haoze.diting.vpn.SubscriptionAutoUpdateSettings.MIN_INTERVAL_HOURS..
                com.haoze.diting.vpn.SubscriptionAutoUpdateSettings.MAX_INTERVAL_HOURS
        } ?: com.haoze.diting.vpn.SubscriptionAutoUpdateSettings.DEFAULT_INTERVAL_HOURS
    }

    fun saveAutoUpdate(context: Context, enabled: Boolean, intervalHours: Int) {
        prefs(context).edit()
            .putBoolean(KEY_AUTO_UPDATE_ENABLED, enabled)
            .putInt(KEY_AUTO_UPDATE_INTERVAL, intervalHours)
            .apply()
    }
}
