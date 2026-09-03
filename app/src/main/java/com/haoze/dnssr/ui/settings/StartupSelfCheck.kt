package com.haoze.dnssr.ui.settings

import android.content.Context
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.PresetDnsService
import org.json.JSONArray

object StartupSelfCheck {
    private const val KEY_DNS_RESOLUTION_MODE = "dns_resolution_mode"
    private const val KEY_PRESET_DNS_SERVICE = "preset_dns_service"
    private const val KEY_BOOTSTRAP_CUSTOM_JSON = "bootstrap_custom_json"
    private const val KEY_CUSTOM_BACKGROUND_URI = "custom_background_uri"
    private const val KEY_CUSTOM_BACKGROUND_URIS = "custom_background_uris"
    private const val KEY_CUSTOM_BACKGROUND_ENABLED = "custom_background_enabled"
    private const val KEY_OUTBOUND_PROXY_PORT = "outbound_proxy_port"
    private const val KEY_HTTP_INSPECTION_RESET_OPT_IN_V1 = "http_inspection_reset_opt_in_v1"
    private const val KEY_HTTP_INSPECTION_APP_PACKAGES = "http_inspection_app_packages"
    private const val KEY_HTTP_INSPECTION_ENABLED = "http_inspection_enabled"

    /**
     * 应用启动时执行轻量级配置自检与异常兜底，清理废弃键与损坏配置，防止闪退。
     */
    fun performStartupSelfCheck(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        var hasChanges = false

        // 1. 校验并纠正解析模式
        val rawResolutionMode = prefs.getString(KEY_DNS_RESOLUTION_MODE, null)
        if (rawResolutionMode != null && DnsResolutionMode.fromStorageValue(rawResolutionMode) == null) {
            editor.putString(KEY_DNS_RESOLUTION_MODE, DnsResolutionMode.SINGLE.storageValue)
            hasChanges = true
        }

        // 2. 校验并纠正服务商协议类型
        val rawPresetService = prefs.getString(KEY_PRESET_DNS_SERVICE, null)
        if (rawPresetService != null && runCatching { PresetDnsService.valueOf(rawPresetService) }.isFailure) {
            editor.putString(KEY_PRESET_DNS_SERVICE, PresetDnsService.DNS.name)
            hasChanges = true
        }

        // 3. 校验并清理可能损坏的 Bootstrap 自定义 JSON
        val customBootstrapJson = prefs.getString(KEY_BOOTSTRAP_CUSTOM_JSON, null)
        if (!customBootstrapJson.isNullOrBlank()) {
            try {
                JSONArray(customBootstrapJson)
            } catch (_: Exception) {
                editor.remove(KEY_BOOTSTRAP_CUSTOM_JSON)
                hasChanges = true
            }
        }

        // 4. 校验并清理可能损坏的自定义背景 JSON
        val customBackgroundUris = prefs.getString(KEY_CUSTOM_BACKGROUND_URIS, null)
        if (!customBackgroundUris.isNullOrBlank()) {
            try {
                JSONArray(customBackgroundUris)
            } catch (_: Exception) {
                editor.remove(KEY_CUSTOM_BACKGROUND_URIS)
                editor.remove(KEY_CUSTOM_BACKGROUND_URI)
                editor.putBoolean(KEY_CUSTOM_BACKGROUND_ENABLED, false)
                hasChanges = true
            }
        }

        // 5. 校验并纠正出站代理端口
        val proxyPort = prefs.getInt(KEY_OUTBOUND_PROXY_PORT, 7890)
        if (proxyPort !in 1..65535) {
            editor.putInt(KEY_OUTBOUND_PROXY_PORT, 7890)
            hasChanges = true
        }

        // 6. 清理可能残留的历史废弃 Key
        val legacyKeys = listOf(
            "legacy_icon_enabled",
            "legacy_log_page_enabled",
            "race_mode_enabled",
            "race_mode_strategy",
            "http_inspection_apps_initialized"
        )
        for (legacyKey in legacyKeys) {
            if (prefs.contains(legacyKey)) {
                editor.remove(legacyKey)
                hasChanges = true
            }
        }

        // 7. 历史版本升级迁移：将已选应用一次性重置为“一个都不选”，同时将 HTTPS 流量检查开关关闭
        if (!prefs.getBoolean(KEY_HTTP_INSPECTION_RESET_OPT_IN_V1, false)) {
            editor.putStringSet(KEY_HTTP_INSPECTION_APP_PACKAGES, emptySet())
            editor.putBoolean(KEY_HTTP_INSPECTION_ENABLED, false)
            editor.putBoolean(KEY_HTTP_INSPECTION_RESET_OPT_IN_V1, true)
            hasChanges = true
        }

        if (hasChanges) {
            editor.apply()
        }
    }
}
