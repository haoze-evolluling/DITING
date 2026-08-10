package com.haoze.dnssr.ui

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.haoze.dnssr.vpn.BlockResponseMode
import com.haoze.dnssr.vpn.DynamicBlockResponseConfig
import com.haoze.dnssr.vpn.BootstrapIpDefaults
import com.haoze.dnssr.vpn.BootstrapIpEntry
import com.haoze.dnssr.vpn.BootstrapIpValidator
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.cache.DnsCacheMode
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import com.haoze.dnssr.vpn.cache.DnsCachePreset
import com.haoze.dnssr.ui.theme.ThemeColorStyle
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private val DEFAULT_HOME_VISIBLE_PROTOCOLS = DnsProtocol.MANAGED_PROTOCOLS.toSet()

enum class RaceModeStrategy(
    val storageValue: String,
    val displayName: String
) {
    BRUTE_FORCE_PARALLEL("brute_force_parallel", "最快响应"),
    SMART_PREDICTION("smart_prediction", "智能选择"),
    PRIMARY_BACKUP("primary_backup", "依次尝试");

    companion object {
        fun fromStorageValue(value: String?): RaceModeStrategy {
            return values().firstOrNull { it.storageValue == value } ?: SMART_PREDICTION
        }
    }
}

enum class DnsResolutionMode(
    val storageValue: String,
    val displayName: String
) {
    SINGLE("single", "单一服务"),
    SMART_PREDICTION("smart_prediction", "智能选择"),
    PARALLEL_RACE("parallel_race", "最快响应"),
    PRIMARY_BACKUP("primary_backup", "依次尝试");

    companion object {
        fun fromStorageValue(value: String?): DnsResolutionMode? =
            entries.firstOrNull { it.storageValue == value }
    }
}

enum class DnsLogMode(val storageValue: String, val displayName: String) {
    ALL("all", "记录全部"),
    BLOCKED_AND_ERRORS("blocked_and_errors", "仅拦截和错误"),
    OFF("off", "关闭");

    companion object {
        fun fromStorageValue(value: String?): DnsLogMode =
            entries.firstOrNull { it.storageValue == value } ?: OFF
    }
}

enum class PresetDnsService(
    val displayName: String
) {
    DNS("DNS"),
    DOT("DoT"),
    DOH("DoH");

    companion object {
        fun fromStorageValue(value: String?): PresetDnsService =
            entries.firstOrNull { it.name == value } ?: DNS
    }
}

enum class AppThemeMode(
    val storageValue: String,
    val displayName: String
) {
    SYSTEM("system", "跟随系统"),
    LIGHT("light", "浅色模式"),
    DARK("dark", "深色模式");

    companion object {
        fun fromStorageValue(value: String?): AppThemeMode =
            entries.firstOrNull { it.storageValue == value } ?: SYSTEM
    }
}

data class HomeProviderVisibility(
    val visibleProtocols: Set<DnsProtocol> = DEFAULT_HOME_VISIBLE_PROTOCOLS,
    val hiddenProviderIds: Set<String> = emptySet(),
    val visibleProviderIds: Set<String> = emptySet()
) {
    fun isVisible(provider: DnsProvider): Boolean {
        return if (provider.protocol in visibleProtocols) {
            provider.id !in hiddenProviderIds
        } else {
            provider.id in visibleProviderIds
        }
    }

    fun isDefault(): Boolean {
        return visibleProtocols == DEFAULT_HOME_VISIBLE_PROTOCOLS &&
            hiddenProviderIds.isEmpty() && visibleProviderIds.isEmpty()
    }
}

enum class GoTunnelReason(val displayName: String) {
    HTTPS_INSPECTION("HTTPS 流量检查"),
    BLOCKED_APPS("禁止联网应用"),
    APP_ALLOWLIST("应用白名单访问"),
    OUTBOUND_PROXY("出站代理")
}

enum class OutboundProxyProtocol(val storageValue: String, val displayName: String) {
    SOCKS5("socks5", "SOCKS5"),
    HTTP("http", "HTTP CONNECT");

    companion object {
        fun fromStorageValue(value: String?): OutboundProxyProtocol =
            entries.firstOrNull { it.storageValue == value } ?: SOCKS5
    }
}

data class OutboundProxyConfig(
    val enabled: Boolean = false,
    val protocol: OutboundProxyProtocol = OutboundProxyProtocol.SOCKS5,
    val host: String = "127.0.0.1",
    val port: Int = 7890,
    val username: String = "",
    val password: String = "",
    val proxyAppPackage: String = ""
) {
    fun validationError(context: Context): String? {
        if (host != "127.0.0.1" && host != "::1") return "代理地址仅支持 127.0.0.1 或 ::1"
        if (port !in 1..65535) return "代理端口必须在 1 到 65535 之间"
        if (proxyAppPackage.isBlank()) return "请选择提供本地代理端口的应用"
        if (proxyAppPackage == context.packageName) return "不能选择 DNSSR 自身作为代理应用"
        if (runCatching { context.packageManager.getApplicationInfo(proxyAppPackage, 0) }.isFailure) return "所选代理应用未安装"
        if (username.toByteArray().size > 255 || password.toByteArray().size > 255) return "代理账号或密码过长"
        return null
    }

    fun toNativeJson(): String = JSONObject()
        .put("enabled", enabled)
        .put("protocol", protocol.storageValue)
        .put("host", host)
        .put("port", port)
        .put("username", username)
        .put("password", password)
        .toString()
}

/**
 * 应用设置封装，基于 SharedPreferences。
 */
object AppSettings {
    private const val PREFS_NAME = "dns_vpn_prefs"

    private const val KEY_DNS_CACHE_ENABLED = "dns_cache_enabled_v2"
    private const val KEY_DNS_CACHE_MODE = "dns_cache_mode_v2"
    private const val KEY_DNS_CACHE_MAX_TTL_SECONDS = "dns_cache_max_ttl_seconds_v2"
    private const val KEY_DNS_CACHE_FIXED_TTL_SECONDS = "dns_cache_fixed_ttl_seconds_v2"
    private const val KEY_DNS_CACHE_MIN_TTL_ENABLED = "dns_cache_min_ttl_enabled_v2"
    private const val KEY_DNS_CACHE_MIN_TTL_SECONDS = "dns_cache_min_ttl_seconds_v2"
    private const val KEY_DNS_CACHE_STALE_FALLBACK_ENABLED = "dns_cache_stale_fallback_enabled_v2"
    private const val KEY_DNS_CACHE_STALE_FALLBACK_SECONDS = "dns_cache_stale_fallback_seconds_v2"
    private const val KEY_DNS_CACHE_PRESET = "dns_cache_preset_v3"
    private const val KEY_BLOCK_RESPONSE_MODE = "block_response_mode"
    private const val KEY_DYNAMIC_BLOCK_RESPONSE_ENABLED = "dynamic_block_response_enabled"
    private const val KEY_DYNAMIC_BLOCK_REQUEST_THRESHOLD = "dynamic_block_request_threshold"
    private const val KEY_DYNAMIC_BLOCK_WINDOW_SECONDS = "dynamic_block_window_seconds"
    private const val KEY_DYNAMIC_BLOCK_NXDOMAIN_DURATION_SECONDS = "dynamic_block_nxdomain_duration_seconds"
    const val KEY_LOG_RETENTION_DAYS = "log_retention_days"
    private const val KEY_DNS_LOG_MODE = "dns_log_mode"
    private const val KEY_FLOATING_LOG_ENABLED = "floating_log_enabled"
    private const val KEY_FLOATING_LOG_PANEL_SIZE = "floating_log_panel_size"
    private const val KEY_MAIN_ACTIVITY_FOREGROUND = "main_activity_foreground"
    const val KEY_RACE_MODE_ENABLED = "race_mode_enabled"
    const val KEY_RACE_PROVIDER_IDS = "race_provider_ids"
    const val KEY_RACE_TEST_DOMAIN = "race_test_domain"
    const val KEY_LATENCY_TEST_PROVIDER_IDS = "latency_test_provider_ids"
    const val KEY_RACE_MODE_STRATEGY = "race_mode_strategy"
    private const val KEY_DNS_RESOLUTION_MODE = "dns_resolution_mode"
    private const val KEY_PRESET_DNS_SERVICE = "preset_dns_service"
    private const val KEY_SMART_PREDICTION_PROVIDER_IDS = "smart_prediction_provider_ids"
    private const val KEY_PARALLEL_RACE_PROVIDER_IDS = "parallel_race_provider_ids"
    private const val KEY_PRIMARY_BACKUP_PROVIDER_IDS = "primary_backup_provider_ids"
    const val KEY_BOOTSTRAP_ENABLED = "bootstrap_enabled"
    const val KEY_BOOTSTRAP_PRESET_IDS = "bootstrap_preset_ids"
    const val KEY_BOOTSTRAP_CUSTOM_JSON = "bootstrap_custom_json"
    const val KEY_HIDE_FROM_RECENTS_ENABLED = "hide_from_recents_enabled"
    const val KEY_PERSISTENT_NOTIFICATION_ENABLED = "persistent_notification_enabled"
    const val KEY_LEGACY_ICON_ENABLED = "legacy_icon_enabled"
    const val KEY_LEGACY_LOG_PAGE_ENABLED = "legacy_log_page_enabled"
    const val KEY_SERVICE_LIGHT_EFFECT_ENABLED = "service_light_effect_enabled"
    private const val KEY_HIDE_GO_TUNNEL_DISABLE_BUTTON_WHEN_INACTIVE = "hide_go_tunnel_disable_button_when_inactive"
    private const val KEY_HOME_VISIBLE_PROTOCOLS = "home_visible_protocols"
    private const val KEY_HOME_HIDDEN_PROVIDER_IDS = "home_hidden_provider_ids"
    private const val KEY_HOME_VISIBLE_PROVIDER_IDS = "home_visible_provider_ids"
    private const val KEY_APP_THEME_MODE = "app_theme_mode"
    private const val KEY_THEME_COLOR_STYLE = "theme_color_style"
    private const val KEY_HOME_COMPONENT_OPACITY = "home_component_opacity"
    private const val KEY_HOME_POWER_BUTTON_OPACITY = "home_power_button_opacity"
    private const val KEY_HOME_PROVIDER_SELECTOR_OPACITY = "home_provider_selector_opacity"
    private const val KEY_HOME_MODE_BUTTON_OPACITY = "home_mode_button_opacity"
    private const val KEY_HOME_POEM_OPACITY = "home_poem_opacity"
    private const val KEY_HOME_DNS_DETAIL_OPACITY = "home_dns_detail_opacity"
    private const val KEY_HOME_SENTENCE_RUNNING = "home_sentence_running"
    private const val KEY_HOME_SENTENCE_STOPPED = "home_sentence_stopped"
    private const val KEY_NOTIFICATION_TEXT_RUNNING = "notification_text_running"
    private const val KEY_NOTIFICATION_TEXT_STOPPED = "notification_text_stopped"
    private const val KEY_CUSTOM_BACKGROUND_ENABLED = "custom_background_enabled"
    private const val KEY_CUSTOM_BACKGROUND_URI = "custom_background_uri"
    private const val KEY_CUSTOM_BACKGROUND_URIS = "custom_background_uris"
    private const val KEY_EXCLUDED_APP_PACKAGES = "excluded_app_packages"
    private const val KEY_EXCLUDED_APPS_FILTER = "excluded_apps_filter"
    private const val KEY_EXCLUDED_APPS_SORT = "excluded_apps_sort"
    private const val KEY_BLOCKED_APP_PACKAGES = "blocked_app_packages"
    private const val KEY_BLOCKED_APPS_ENABLED = "blocked_apps_enabled"
    private const val KEY_BLOCKED_APPS_FILTER = "blocked_apps_filter"
    private const val KEY_BLOCKED_APPS_SORT = "blocked_apps_sort"
    private const val KEY_APP_ALLOWLIST_PACKAGES = "app_allowlist_packages"
    private const val KEY_APP_ALLOWLIST_ENABLED = "app_allowlist_enabled"
    private const val KEY_APP_ALLOWLIST_DOMAINS = "app_allowlist_domains"
    private const val KEY_APP_ALLOWLIST_FILTER = "app_allowlist_filter"
    private const val KEY_APP_ALLOWLIST_SORT = "app_allowlist_sort"
    private const val KEY_HTTP_INSPECTION_ENABLED = "http_inspection_enabled"
    private const val KEY_HTTP_INSPECTION_APP_PACKAGES = "http_inspection_app_packages"
    private const val KEY_HTTP_INSPECTION_APPS_INITIALIZED = "http_inspection_apps_initialized"
    private const val KEY_HTTP_INSPECTION_APPS_FILTER = "http_inspection_apps_filter"
    private const val KEY_HTTP_INSPECTION_APPS_SORT = "http_inspection_apps_sort"
    private const val KEY_SETTINGS_GUIDE_ACKNOWLEDGED_IDS = "settings_guide_acknowledged_ids"
    private const val KEY_INITIAL_AGREEMENT_ACCEPTED = "initial_agreement_accepted"
    private const val KEY_HTTPS_INSPECTION_READY = "https_inspection_ready"
    private const val KEY_HTTPS_INSPECTION_CA_BACKEND = "https_inspection_ca_backend"
    private const val KEY_HTTP3_INSPECTION_ENABLED = "http3_inspection_enabled"
    private const val KEY_ENCRYPTED_DNS_BLOCKING_ENABLED = "encrypted_dns_blocking_enabled"
    private const val KEY_APP_UPDATE_DOWNLOAD_PATH = "app_update_download_path"
    private const val KEY_APP_UPDATE_DOWNLOAD_VERSION = "app_update_download_version"
    private const val KEY_DISABLE_STARTUP_UPDATE_CHECK = "disable_startup_update_check"
    private const val KEY_OUTBOUND_PROXY_ENABLED = "outbound_proxy_enabled"
    private const val KEY_OUTBOUND_PROXY_PROTOCOL = "outbound_proxy_protocol"
    private const val KEY_OUTBOUND_PROXY_HOST = "outbound_proxy_host"
    private const val KEY_OUTBOUND_PROXY_PORT = "outbound_proxy_port"
    private const val KEY_OUTBOUND_PROXY_USERNAME = "outbound_proxy_username"
    private const val KEY_OUTBOUND_PROXY_PASSWORD = "outbound_proxy_password"
    private const val KEY_OUTBOUND_PROXY_APP = "outbound_proxy_app"
    private const val KEY_OUTBOUND_PROXY_STATUS = "outbound_proxy_status"
    private const val KEY_OUTBOUND_PROXY_STATUS_MESSAGE = "outbound_proxy_status_message"

    private const val MIN_CACHE_SECONDS = 30L
    private const val MAX_CACHE_SECONDS = 86_400L
    private const val DEFAULT_CACHE_ENABLED = true
    private const val DEFAULT_CACHE_MAX_TTL_SECONDS = 3600L
    private const val DEFAULT_CACHE_FIXED_TTL_SECONDS = 3600L
    private const val DEFAULT_CACHE_MIN_TTL_SECONDS = 60L
    private const val DEFAULT_CACHE_STALE_FALLBACK_SECONDS = 300L
    private const val DEFAULT_LOG_RETENTION_DAYS = 7
    private const val GO_CA_BACKEND = "go-v1"
    private const val DEFAULT_RACE_MODE_ENABLED = false
    private val DEFAULT_RACE_PROVIDER_IDS = setOf(
        "preset_alidns_dns",
        "preset_dnspod_dns",
    )
    private val DEFAULT_LATENCY_TEST_PROVIDER_IDS = emptySet<String>()
    private const val DEFAULT_RACE_TEST_DOMAIN = "mihoyo.com"
    private val DEFAULT_RACE_MODE_STRATEGY = RaceModeStrategy.SMART_PREDICTION
    private val DEFAULT_BLOCK_RESPONSE_MODE = BlockResponseMode.NXDOMAIN
    private const val DEFAULT_BOOTSTRAP_ENABLED = true
    private const val DEFAULT_HIDE_FROM_RECENTS_ENABLED = false
    const val DEFAULT_PERSISTENT_NOTIFICATION_ENABLED = true
    private const val DEFAULT_LEGACY_ICON_ENABLED = false
    private const val DEFAULT_LEGACY_LOG_PAGE_ENABLED = false
    private const val DEFAULT_SERVICE_LIGHT_EFFECT_ENABLED = true
    private const val DEFAULT_HIDE_GO_TUNNEL_DISABLE_BUTTON_WHEN_INACTIVE = true
    const val DEFAULT_HOME_COMPONENT_OPACITY = 1f
    private val DEFAULT_BOOTSTRAP_PRESET_IDS = setOf(
        "preset_volcengine",
        "preset_dnspod",
        "preset_alidns"
    )

    fun getAppThemeMode(context: Context): AppThemeMode {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_APP_THEME_MODE, null)
        return AppThemeMode.fromStorageValue(value)
    }

    fun setAppThemeMode(context: Context, mode: AppThemeMode) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_APP_THEME_MODE, mode.storageValue)
            .apply()
    }

    fun getThemeColorStyle(context: Context): ThemeColorStyle {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_THEME_COLOR_STYLE, null)
        return ThemeColorStyle.fromStorageValue(value)
    }

    fun setThemeColorStyle(context: Context, style: ThemeColorStyle) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_THEME_COLOR_STYLE, style.storageValue)
            .apply()
    }

    fun getHomeComponentOpacity(context: Context): Float {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getFloat(KEY_HOME_COMPONENT_OPACITY, DEFAULT_HOME_COMPONENT_OPACITY)
            .coerceIn(0.1f, 1f)
    }

    fun setHomeComponentOpacity(context: Context, opacity: Float) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_HOME_COMPONENT_OPACITY, opacity.coerceIn(0.1f, 1f))
            .apply()
    }

    private fun getHomeOpacity(context: Context, key: String): Float {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getFloat(key, prefs.getFloat(KEY_HOME_COMPONENT_OPACITY, DEFAULT_HOME_COMPONENT_OPACITY))
            .coerceIn(0.1f, 1f)
    }

    private fun setHomeOpacity(context: Context, key: String, opacity: Float) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putFloat(key, opacity.coerceIn(0.1f, 1f))
            .apply()
    }

    fun getHomePowerButtonOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_POWER_BUTTON_OPACITY)
    fun setHomePowerButtonOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_POWER_BUTTON_OPACITY, opacity)

    fun getHomeProviderSelectorOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_PROVIDER_SELECTOR_OPACITY)
    fun setHomeProviderSelectorOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_PROVIDER_SELECTOR_OPACITY, opacity)

    fun getHomeModeButtonOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_MODE_BUTTON_OPACITY)
    fun setHomeModeButtonOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_MODE_BUTTON_OPACITY, opacity)

    fun getHomePoemOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_POEM_OPACITY)
    fun setHomePoemOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_POEM_OPACITY, opacity)

    fun getHomeDnsDetailOpacity(context: Context) = getHomeOpacity(context, KEY_HOME_DNS_DETAIL_OPACITY)
    fun setHomeDnsDetailOpacity(context: Context, opacity: Float) =
        setHomeOpacity(context, KEY_HOME_DNS_DETAIL_OPACITY, opacity)

    fun getHomeSentenceRunning(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_HOME_SENTENCE_RUNNING, "谛听万象，明察清浊")
            .orEmpty()
    }

    fun getHomeSentenceStopped(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_HOME_SENTENCE_STOPPED, "收耳静眠，归于无声")
            .orEmpty()
    }

    fun setHomeSentences(context: Context, running: String, stopped: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_HOME_SENTENCE_RUNNING, running)
            .putString(KEY_HOME_SENTENCE_STOPPED, stopped)
            .apply()
    }

    fun getAppUpdateDownloadPath(context: Context): String = context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString(KEY_APP_UPDATE_DOWNLOAD_PATH, "")
        .orEmpty()

    fun getAppUpdateDownloadVersion(context: Context): String = context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString(KEY_APP_UPDATE_DOWNLOAD_VERSION, "")
        .orEmpty()

    fun rememberAppUpdateDownload(context: Context, path: String, version: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_APP_UPDATE_DOWNLOAD_PATH, path)
            .putString(KEY_APP_UPDATE_DOWNLOAD_VERSION, version.trim())
            .apply()
    }

    fun clearAppUpdateDownload(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .remove(KEY_APP_UPDATE_DOWNLOAD_PATH)
            .remove(KEY_APP_UPDATE_DOWNLOAD_VERSION)
            .apply()
    }

    fun isStartupUpdateCheckDisabled(context: Context): Boolean = context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(KEY_DISABLE_STARTUP_UPDATE_CHECK, true)

    fun setStartupUpdateCheckDisabled(context: Context, disabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_DISABLE_STARTUP_UPDATE_CHECK, disabled)
            .apply()
    }

    fun getNotificationTextRunning(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_NOTIFICATION_TEXT_RUNNING, "")
            .orEmpty()
    }

    fun getNotificationTextStopped(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_NOTIFICATION_TEXT_STOPPED, "")
            .orEmpty()
    }

    fun setNotificationTexts(context: Context, running: String, stopped: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_NOTIFICATION_TEXT_RUNNING, running)
            .putString(KEY_NOTIFICATION_TEXT_STOPPED, stopped)
            .apply()
    }

    fun getExcludedAppPackages(context: Context): Set<String> {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(KEY_EXCLUDED_APP_PACKAGES, emptySet())
            .orEmpty()
            .filter { it.isNotBlank() }
            .toSet()
    }

    fun setExcludedAppPackages(context: Context, packageNames: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_EXCLUDED_APP_PACKAGES, packageNames.filter { it.isNotBlank() }.toSet())
            .apply()
    }

    fun getExcludedAppsFilter(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_EXCLUDED_APPS_FILTER, "USER")
            ?: "USER"
    }

    fun setExcludedAppsFilter(context: Context, filter: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_EXCLUDED_APPS_FILTER, filter)
            .apply()
    }

    fun isHttpInspectionEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_HTTP_INSPECTION_ENABLED, false)
    }

    fun setHttpInspectionEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_HTTP_INSPECTION_ENABLED, enabled)
            .apply()
    }

    fun getHttpInspectionAppPackages(context: Context): Set<String> {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(KEY_HTTP_INSPECTION_APP_PACKAGES, emptySet())
            .orEmpty()
            .filter { it.isNotBlank() }
            .toSet()
    }

    fun getOutboundProxyConfig(context: Context): OutboundProxyConfig {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = preferences.getBoolean(KEY_OUTBOUND_PROXY_ENABLED, false)
        val username = decryptProxySecret(preferences.getString(KEY_OUTBOUND_PROXY_USERNAME, null))
        val password = decryptProxySecret(preferences.getString(KEY_OUTBOUND_PROXY_PASSWORD, null))
        if (enabled && (username.failed || password.failed)) {
            setOutboundProxyStatus(context, "error", "代理凭据无法恢复，请重新输入")
        }
        return OutboundProxyConfig(
            enabled = enabled,
            protocol = OutboundProxyProtocol.fromStorageValue(preferences.getString(KEY_OUTBOUND_PROXY_PROTOCOL, null)),
            host = preferences.getString(KEY_OUTBOUND_PROXY_HOST, "127.0.0.1") ?: "127.0.0.1",
            port = preferences.getInt(KEY_OUTBOUND_PROXY_PORT, 7890),
            username = username.value,
            password = password.value,
            proxyAppPackage = preferences.getString(KEY_OUTBOUND_PROXY_APP, "").orEmpty()
        )
    }

    fun setOutboundProxyConfig(context: Context, config: OutboundProxyConfig) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_OUTBOUND_PROXY_ENABLED, config.enabled)
            .putString(KEY_OUTBOUND_PROXY_PROTOCOL, config.protocol.storageValue)
            .putString(KEY_OUTBOUND_PROXY_HOST, config.host)
            .putInt(KEY_OUTBOUND_PROXY_PORT, config.port)
            .putString(KEY_OUTBOUND_PROXY_USERNAME, encryptProxySecret(config.username))
            .putString(KEY_OUTBOUND_PROXY_PASSWORD, encryptProxySecret(config.password))
            .putString(KEY_OUTBOUND_PROXY_APP, config.proxyAppPackage)
            .apply()
    }

    fun setOutboundProxyStatus(context: Context, state: String, message: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_OUTBOUND_PROXY_STATUS, state)
            .putString(KEY_OUTBOUND_PROXY_STATUS_MESSAGE, message)
            .apply()
    }

    fun getOutboundProxyStatus(context: Context): Pair<String, String> {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return preferences.getString(KEY_OUTBOUND_PROXY_STATUS, "disabled").orEmpty() to
            preferences.getString(KEY_OUTBOUND_PROXY_STATUS_MESSAGE, "").orEmpty()
    }

    private fun proxySecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey("dnssr_outbound_proxy", null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                "dnssr_outbound_proxy",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    private fun encryptProxySecret(value: String): String {
        if (value.isEmpty()) return ""
        return runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, proxySecretKey())
            val payload = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            Base64.encodeToString(payload, Base64.NO_WRAP)
        }.getOrDefault("")
    }

    private data class DecryptedProxySecret(
        val value: String,
        val failed: Boolean
    )

    private fun decryptProxySecret(value: String?): DecryptedProxySecret {
        if (value.isNullOrEmpty()) return DecryptedProxySecret("", failed = false)
        return runCatching {
            val payload = Base64.decode(value, Base64.NO_WRAP)
            val iv = payload.copyOfRange(0, 12)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, proxySecretKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(payload.copyOfRange(12, payload.size)), Charsets.UTF_8)
        }.fold(
            onSuccess = { DecryptedProxySecret(it, failed = false) },
            onFailure = { DecryptedProxySecret("", failed = true) }
        )
    }

    fun isHttpInspectionAppPackagesInitialized(context: Context): Boolean {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (preferences.getBoolean(KEY_HTTP_INSPECTION_APPS_INITIALIZED, false)) {
            return true
        }

        // A non-empty package set written by an older version is already an
        // explicit choice. Empty legacy sets may have been written as a side
        // effect by another app-scope screen and are not distinguishable.
        if (preferences.getStringSet(KEY_HTTP_INSPECTION_APP_PACKAGES, emptySet())
                ?.any { it.isNotBlank() } == true
        ) {
            preferences.edit()
                .putBoolean(KEY_HTTP_INSPECTION_APPS_INITIALIZED, true)
                .apply()
            return true
        }

        return false
    }

    fun setHttpInspectionAppPackages(context: Context, packageNames: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_HTTP_INSPECTION_APP_PACKAGES, packageNames.filter { it.isNotBlank() }.toSet())
            .putBoolean(KEY_HTTP_INSPECTION_APPS_INITIALIZED, true)
            .apply()
    }

    fun removeHttpInspectionAppPackages(context: Context, packageNames: Set<String>) {
        if (packageNames.isEmpty()) return
        val remaining = getHttpInspectionAppPackages(context) - packageNames
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_HTTP_INSPECTION_APP_PACKAGES, remaining)
            .apply()
    }

    fun isSettingsGuideAcknowledged(context: Context, guideId: String): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(KEY_SETTINGS_GUIDE_ACKNOWLEDGED_IDS, emptySet())
            .orEmpty()
            .contains(guideId)

    fun acknowledgeSettingsGuide(context: Context, guideId: String) {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val acknowledgedIds = preferences
            .getStringSet(KEY_SETTINGS_GUIDE_ACKNOWLEDGED_IDS, emptySet())
            .orEmpty()
            .toMutableSet()
        acknowledgedIds += guideId
        preferences.edit()
            .putStringSet(KEY_SETTINGS_GUIDE_ACKNOWLEDGED_IDS, acknowledgedIds)
            .apply()
    }

    fun resetAllSettingsGuides(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_SETTINGS_GUIDE_ACKNOWLEDGED_IDS)
            .remove(KEY_INITIAL_AGREEMENT_ACCEPTED)
            .apply()
    }

    fun isInitialAgreementAccepted(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_INITIAL_AGREEMENT_ACCEPTED, false)

    fun setInitialAgreementAccepted(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_INITIAL_AGREEMENT_ACCEPTED, true)
            .apply()
    }

    fun isHttpsInspectionReady(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .let { preferences ->
                preferences.getBoolean(KEY_HTTPS_INSPECTION_READY, false) &&
                    preferences.getString(KEY_HTTPS_INSPECTION_CA_BACKEND, null) == GO_CA_BACKEND
            }

    fun setHttpsInspectionReady(context: Context, ready: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_HTTPS_INSPECTION_READY, ready)
            .putString(KEY_HTTPS_INSPECTION_CA_BACKEND, GO_CA_BACKEND)
            .apply()
    }

    fun isHttp3InspectionEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_HTTP3_INSPECTION_ENABLED, false)

    fun setHttp3InspectionEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_HTTP3_INSPECTION_ENABLED, enabled)
            .apply()
    }

    fun getExcludedAppsSort(context: Context) = getAppListPreference(context, KEY_EXCLUDED_APPS_SORT, "LABEL_ASC")
    fun setExcludedAppsSort(context: Context, sort: String) = setAppListPreference(context, KEY_EXCLUDED_APPS_SORT, sort)
    fun getHttpInspectionAppsFilter(context: Context) =
        getAppListPreference(context, KEY_HTTP_INSPECTION_APPS_FILTER, getExcludedAppsFilter(context))
    fun setHttpInspectionAppsFilter(context: Context, filter: String) = setAppListPreference(context, KEY_HTTP_INSPECTION_APPS_FILTER, filter)
    fun getHttpInspectionAppsSort(context: Context) = getAppListPreference(context, KEY_HTTP_INSPECTION_APPS_SORT, "LABEL_ASC")
    fun setHttpInspectionAppsSort(context: Context, sort: String) = setAppListPreference(context, KEY_HTTP_INSPECTION_APPS_SORT, sort)
    fun getBlockedAppsFilter(context: Context) =
        getAppListPreference(context, KEY_BLOCKED_APPS_FILTER, getExcludedAppsFilter(context))
    fun setBlockedAppsFilter(context: Context, filter: String) = setAppListPreference(context, KEY_BLOCKED_APPS_FILTER, filter)
    fun getBlockedAppsSort(context: Context) = getAppListPreference(context, KEY_BLOCKED_APPS_SORT, "LABEL_ASC")
    fun setBlockedAppsSort(context: Context, sort: String) = setAppListPreference(context, KEY_BLOCKED_APPS_SORT, sort)
    fun getAppAllowlistFilter(context: Context) = getAppListPreference(context, KEY_APP_ALLOWLIST_FILTER, getExcludedAppsFilter(context))
    fun setAppAllowlistFilter(context: Context, filter: String) = setAppListPreference(context, KEY_APP_ALLOWLIST_FILTER, filter)
    fun getAppAllowlistSort(context: Context) = getAppListPreference(context, KEY_APP_ALLOWLIST_SORT, "LABEL_ASC")
    fun setAppAllowlistSort(context: Context, sort: String) = setAppListPreference(context, KEY_APP_ALLOWLIST_SORT, sort)

    private fun getAppListPreference(context: Context, key: String, default: String): String =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(key, default) ?: default

    private fun setAppListPreference(context: Context, key: String, value: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().putString(key, value).apply()
    }

    fun getBlockedAppPackages(context: Context): Set<String> {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(KEY_BLOCKED_APP_PACKAGES, emptySet())
            .orEmpty()
            .filter { it.isNotBlank() && it != context.packageName }
            .toSet()
    }

    fun isBlockedAppsEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_BLOCKED_APPS_ENABLED, false)

    fun setBlockedAppsEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_BLOCKED_APPS_ENABLED, enabled).apply()
    }

    fun getGoTunnelReasons(context: Context): Set<GoTunnelReason> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptySet()
        return buildSet {
            if (isHttpInspectionEnabled(context) && getHttpInspectionAppPackages(context).isNotEmpty()) {
                add(GoTunnelReason.HTTPS_INSPECTION)
            }
            if (isBlockedAppsEnabled(context) && getBlockedAppPackages(context).isNotEmpty()) {
                add(GoTunnelReason.BLOCKED_APPS)
            }
            if (isAppAllowlistEnabled(context) && getAppAllowlistPackages(context).isNotEmpty() && getAppAllowlistDomains(context).isNotEmpty()) {
                add(GoTunnelReason.APP_ALLOWLIST)
            }
            if (getOutboundProxyConfig(context).enabled) add(GoTunnelReason.OUTBOUND_PROXY)
        }
    }

    fun isGoTunnelRequired(context: Context): Boolean = getGoTunnelReasons(context).isNotEmpty()

    fun setBlockedAppPackages(context: Context, packageNames: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(
                KEY_BLOCKED_APP_PACKAGES,
                packageNames.filter { it.isNotBlank() && it != context.packageName }.toSet()
            )
            .apply()
    }

    fun isEncryptedDnsBlockingEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENCRYPTED_DNS_BLOCKING_ENABLED, false)

    fun setEncryptedDnsBlockingEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENCRYPTED_DNS_BLOCKING_ENABLED, enabled)
            .apply()
    }

    fun isCacheEnabled(context: Context): Boolean {
        return getDnsCachePolicy(context).enabled
    }

    fun setCacheEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_DNS_CACHE_ENABLED, enabled)
            .apply()
    }

    fun getDnsCachePolicy(context: Context): DnsCachePolicy {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return DnsCachePolicy(
            enabled = prefs.getBoolean(KEY_DNS_CACHE_ENABLED, DEFAULT_CACHE_ENABLED),
            mode = DnsCacheMode.fromStorageValue(
                prefs.getString(KEY_DNS_CACHE_MODE, DnsCacheMode.LIMIT_MAX_TTL.storageValue)
            ),
            maxTtlSeconds = prefs.getLong(KEY_DNS_CACHE_MAX_TTL_SECONDS, DEFAULT_CACHE_MAX_TTL_SECONDS)
                .coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS),
            fixedTtlSeconds = prefs.getLong(KEY_DNS_CACHE_FIXED_TTL_SECONDS, DEFAULT_CACHE_FIXED_TTL_SECONDS)
                .coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS),
            minTtlEnabled = prefs.getBoolean(KEY_DNS_CACHE_MIN_TTL_ENABLED, false),
            minTtlSeconds = prefs.getLong(KEY_DNS_CACHE_MIN_TTL_SECONDS, DEFAULT_CACHE_MIN_TTL_SECONDS)
                .coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS),
            staleFallbackEnabled = prefs.getBoolean(KEY_DNS_CACHE_STALE_FALLBACK_ENABLED, false),
            staleFallbackSeconds = prefs.getLong(
                KEY_DNS_CACHE_STALE_FALLBACK_SECONDS,
                DEFAULT_CACHE_STALE_FALLBACK_SECONDS
            ).coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS)
        )
    }

    fun getDnsCachePreset(context: Context): DnsCachePreset {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return DnsCachePreset.fromStorageValue(prefs.getString(KEY_DNS_CACHE_PRESET, null))
            ?: DnsCachePreset.fromPolicy(getDnsCachePolicy(context))
    }

    fun setDnsCachePreset(context: Context, preset: DnsCachePreset) {
        val enabled = getDnsCachePolicy(context).enabled
        setDnsCachePolicy(context, preset.toPolicy(enabled = enabled), preset)
    }

    fun setDnsCachePolicy(context: Context, policy: DnsCachePolicy) {
        setDnsCachePolicy(context, policy, DnsCachePreset.fromPolicy(policy))
    }

    private fun setDnsCachePolicy(context: Context, policy: DnsCachePolicy, preset: DnsCachePreset) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DNS_CACHE_PRESET, preset.storageValue)
            .putBoolean(KEY_DNS_CACHE_ENABLED, policy.enabled)
            .putString(KEY_DNS_CACHE_MODE, policy.mode.storageValue)
            .putLong(KEY_DNS_CACHE_MAX_TTL_SECONDS, policy.maxTtlSeconds.coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS))
            .putLong(KEY_DNS_CACHE_FIXED_TTL_SECONDS, policy.fixedTtlSeconds.coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS))
            .putBoolean(KEY_DNS_CACHE_MIN_TTL_ENABLED, policy.minTtlEnabled)
            .putLong(KEY_DNS_CACHE_MIN_TTL_SECONDS, policy.minTtlSeconds.coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS))
            .putBoolean(KEY_DNS_CACHE_STALE_FALLBACK_ENABLED, policy.staleFallbackEnabled)
            .putLong(
                KEY_DNS_CACHE_STALE_FALLBACK_SECONDS,
                policy.staleFallbackSeconds.coerceIn(MIN_CACHE_SECONDS, MAX_CACHE_SECONDS)
            )
            .apply()
    }

    fun logRetentionDays(context: Context): Int {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_LOG_RETENTION_DAYS, DEFAULT_LOG_RETENTION_DAYS)
    }

    fun setLogRetentionDays(context: Context, days: Int) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_LOG_RETENTION_DAYS, days.coerceIn(1, 30))
            .apply()
    }

    fun isRaceModeEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_RACE_MODE_ENABLED, DEFAULT_RACE_MODE_ENABLED)
    }

    fun setRaceModeEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_RACE_MODE_ENABLED, enabled)
            .apply()
    }

    fun getRaceProviderIds(context: Context): Set<String> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_RACE_PROVIDER_IDS, null) ?: return DEFAULT_RACE_PROVIDER_IDS
        return try {
            val array = org.json.JSONArray(json)
            val ids = mutableSetOf<String>()
            for (i in 0 until array.length()) {
                ids.add(array.getString(i))
            }
            migrateLegacyProviderIds(context, KEY_RACE_PROVIDER_IDS, ids)
        } catch (_: Exception) {
            DEFAULT_RACE_PROVIDER_IDS
        }
    }

    fun hasRaceProviderIds(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .contains(KEY_RACE_PROVIDER_IDS)
    }

    fun setRaceProviderIds(context: Context, ids: Set<String>) {
        val array = org.json.JSONArray()
        ids.forEach { array.put(it) }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_RACE_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun getLatencyTestProviderIds(context: Context): Set<String> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_LATENCY_TEST_PROVIDER_IDS, null) ?: return DEFAULT_LATENCY_TEST_PROVIDER_IDS
        return try {
            val array = org.json.JSONArray(json)
            val ids = mutableSetOf<String>()
            for (i in 0 until array.length()) {
                ids.add(array.getString(i))
            }
            migrateLegacyProviderIds(context, KEY_LATENCY_TEST_PROVIDER_IDS, ids)
        } catch (_: Exception) {
            DEFAULT_LATENCY_TEST_PROVIDER_IDS
        }
    }

    fun hasLatencyTestProviderIds(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .contains(KEY_LATENCY_TEST_PROVIDER_IDS)
    }

    fun setLatencyTestProviderIds(context: Context, ids: Set<String>) {
        val array = org.json.JSONArray()
        ids.forEach { array.put(it) }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LATENCY_TEST_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun getDnsLogMode(context: Context): DnsLogMode {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_DNS_LOG_MODE, null)
        return DnsLogMode.fromStorageValue(value)
    }

    fun setDnsLogMode(context: Context, mode: DnsLogMode) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DNS_LOG_MODE, mode.storageValue)
            .apply()
    }

    fun isFloatingLogEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_FLOATING_LOG_ENABLED, false)
    }

    fun setFloatingLogEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_FLOATING_LOG_ENABLED, enabled)
            .apply()
    }

    fun getFloatingLogPanelSize(context: Context): Int {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_FLOATING_LOG_PANEL_SIZE, 0)
            .coerceIn(0, 2)
    }

    fun setFloatingLogPanelSize(context: Context, size: Int) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_FLOATING_LOG_PANEL_SIZE, size.coerceIn(0, 2))
            .apply()
    }

    fun isMainActivityForeground(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_MAIN_ACTIVITY_FOREGROUND, true)
    }

    fun setMainActivityForeground(context: Context, foreground: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_MAIN_ACTIVITY_FOREGROUND, foreground)
            .apply()
    }

    fun getRaceTestDomain(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_RACE_TEST_DOMAIN, DEFAULT_RACE_TEST_DOMAIN)
            ?.takeIf { it.isNotBlank() }
            ?: DEFAULT_RACE_TEST_DOMAIN
    }

    fun setRaceTestDomain(context: Context, domain: String) {
        val trimmed = domain.trim()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_RACE_TEST_DOMAIN, trimmed.takeIf { it.isNotBlank() } ?: DEFAULT_RACE_TEST_DOMAIN)
            .apply()
    }

    fun getRaceModeStrategy(context: Context): RaceModeStrategy {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_RACE_MODE_STRATEGY, DEFAULT_RACE_MODE_STRATEGY.storageValue)
        return RaceModeStrategy.fromStorageValue(value)
    }

    fun setRaceModeStrategy(context: Context, strategy: RaceModeStrategy) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_RACE_MODE_STRATEGY, strategy.storageValue)
            .apply()
    }

    fun getDnsResolutionMode(context: Context): DnsResolutionMode {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        DnsResolutionMode.fromStorageValue(prefs.getString(KEY_DNS_RESOLUTION_MODE, null))?.let { return it }

        val migrated = if (!prefs.getBoolean(KEY_RACE_MODE_ENABLED, DEFAULT_RACE_MODE_ENABLED)) {
            DnsResolutionMode.SINGLE
        } else {
            when (RaceModeStrategy.fromStorageValue(prefs.getString(KEY_RACE_MODE_STRATEGY, null))) {
                RaceModeStrategy.BRUTE_FORCE_PARALLEL -> DnsResolutionMode.PARALLEL_RACE
                RaceModeStrategy.SMART_PREDICTION -> DnsResolutionMode.SMART_PREDICTION
                RaceModeStrategy.PRIMARY_BACKUP -> DnsResolutionMode.PRIMARY_BACKUP
            }
        }
        prefs.edit().putString(KEY_DNS_RESOLUTION_MODE, migrated.storageValue).apply()
        return migrated
    }

    fun setDnsResolutionMode(context: Context, mode: DnsResolutionMode) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DNS_RESOLUTION_MODE, mode.storageValue)
            .putBoolean(KEY_RACE_MODE_ENABLED, mode != DnsResolutionMode.SINGLE)
            .putString(
                KEY_RACE_MODE_STRATEGY,
                when (mode) {
                    DnsResolutionMode.PARALLEL_RACE -> RaceModeStrategy.BRUTE_FORCE_PARALLEL
                    DnsResolutionMode.PRIMARY_BACKUP -> RaceModeStrategy.PRIMARY_BACKUP
                    else -> RaceModeStrategy.SMART_PREDICTION
                }.storageValue
            )
            .apply()
    }

    private fun getModeProviderIds(context: Context, key: String): Set<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(key, null)
        if (json == null) {
            val migrated = getRaceProviderIds(context)
            setModeProviderIds(context, key, migrated)
            return migrated
        }
        return try {
            val array = JSONArray(json)
            migrateLegacyProviderIds(
                context,
                key,
                buildSet { for (index in 0 until array.length()) add(array.getString(index)) }
            )
        } catch (_: Exception) {
            emptySet()
        }
    }

    private fun setModeProviderIds(context: Context, key: String, ids: Set<String>) {
        val array = JSONArray()
        ids.forEach(array::put)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(key, array.toString()).apply()
    }

    fun getSmartPredictionProviderIds(context: Context) =
        getModeProviderIds(context, KEY_SMART_PREDICTION_PROVIDER_IDS)

    fun setSmartPredictionProviderIds(context: Context, ids: Set<String>) =
        setModeProviderIds(context, KEY_SMART_PREDICTION_PROVIDER_IDS, ids)

    fun getParallelRaceProviderIds(context: Context) =
        getModeProviderIds(context, KEY_PARALLEL_RACE_PROVIDER_IDS)

    fun setParallelRaceProviderIds(context: Context, ids: Set<String>) =
        setModeProviderIds(context, KEY_PARALLEL_RACE_PROVIDER_IDS, ids)

    fun getPrimaryBackupProviderIds(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_PRIMARY_BACKUP_PROVIDER_IDS, null)
            ?: return getRaceProviderIds(context).toList()
        return try {
            val array = JSONArray(json)
            migrateLegacyProviderIds(context, KEY_PRIMARY_BACKUP_PROVIDER_IDS, buildList {
                for (index in 0 until array.length()) add(array.getString(index))
            }.distinct()).toList()
        } catch (_: Exception) {
            getRaceProviderIds(context).toList()
        }
    }

    fun setPrimaryBackupProviderIds(context: Context, ids: List<String>) {
        val array = JSONArray()
        ids.distinct().forEach(array::put)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PRIMARY_BACKUP_PROVIDER_IDS, array.toString())
            .apply()
    }

    fun removeProviderFromResolutionModes(context: Context, id: String) {
        setSmartPredictionProviderIds(context, getSmartPredictionProviderIds(context) - id)
        setParallelRaceProviderIds(context, getParallelRaceProviderIds(context) - id)
        setPrimaryBackupProviderIds(context, getPrimaryBackupProviderIds(context) - id)
    }

    fun getHomeProviderVisibility(context: Context): HomeProviderVisibility {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return HomeProviderVisibility(
            visibleProtocols = readStringSet(prefs.getString(KEY_HOME_VISIBLE_PROTOCOLS, null))
                ?.mapNotNull { value -> DnsProtocol.entries.firstOrNull { it.name == value } }
                ?.toSet()
                ?: DEFAULT_HOME_VISIBLE_PROTOCOLS,
            hiddenProviderIds = readStringSet(prefs.getString(KEY_HOME_HIDDEN_PROVIDER_IDS, null)) ?: emptySet(),
            visibleProviderIds = readStringSet(prefs.getString(KEY_HOME_VISIBLE_PROVIDER_IDS, null)) ?: emptySet()
        )
    }

    fun setHomeProviderVisibility(context: Context, visibility: HomeProviderVisibility) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_HOME_VISIBLE_PROTOCOLS, writeStringSet(visibility.visibleProtocols.map { it.name }.toSet()))
            .putString(KEY_HOME_HIDDEN_PROVIDER_IDS, writeStringSet(visibility.hiddenProviderIds))
            .putString(KEY_HOME_VISIBLE_PROVIDER_IDS, writeStringSet(visibility.visibleProviderIds))
            .apply()
    }

    private fun readStringSet(json: String?): Set<String>? {
        if (json == null) return null
        return try {
            val array = JSONArray(json)
            buildSet {
                for (index in 0 until array.length()) add(array.getString(index))
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun writeStringSet(values: Set<String>): String {
        return JSONArray().apply { values.sorted().forEach(::put) }.toString()
    }

    fun getBlockResponseMode(context: Context): BlockResponseMode {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_BLOCK_RESPONSE_MODE, DEFAULT_BLOCK_RESPONSE_MODE.storageValue)
        return BlockResponseMode.fromStorageValue(value)
    }

    fun setBlockResponseMode(context: Context, mode: BlockResponseMode) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_BLOCK_RESPONSE_MODE, mode.storageValue)
            .apply()
    }

    fun isBootstrapEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_BOOTSTRAP_ENABLED, DEFAULT_BOOTSTRAP_ENABLED)
    }

    fun setBootstrapEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_BOOTSTRAP_ENABLED, enabled)
            .apply()
    }

    fun isHideFromRecentsEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_HIDE_FROM_RECENTS_ENABLED, DEFAULT_HIDE_FROM_RECENTS_ENABLED)
    }

    fun setHideFromRecentsEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_HIDE_FROM_RECENTS_ENABLED, enabled)
            .apply()
    }

    fun isPersistentNotificationEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_PERSISTENT_NOTIFICATION_ENABLED, DEFAULT_PERSISTENT_NOTIFICATION_ENABLED)
    }

    fun setPersistentNotificationEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PERSISTENT_NOTIFICATION_ENABLED, enabled)
            .apply()
    }

    fun isLegacyIconEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_LEGACY_ICON_ENABLED, DEFAULT_LEGACY_ICON_ENABLED)
    }

    fun setLegacyIconEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_LEGACY_ICON_ENABLED, enabled)
            .apply()
    }

    fun getPresetDnsService(context: Context): PresetDnsService {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PRESET_DNS_SERVICE, null)
        return PresetDnsService.fromStorageValue(value)
    }

    fun setPresetDnsService(context: Context, service: PresetDnsService) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PRESET_DNS_SERVICE, service.name)
            .apply()
    }

    fun getDynamicBlockResponseConfig(context: Context): DynamicBlockResponseConfig {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return DynamicBlockResponseConfig(
            enabled = prefs.getBoolean(KEY_DYNAMIC_BLOCK_RESPONSE_ENABLED, false),
            requestThreshold = prefs.getInt(
                KEY_DYNAMIC_BLOCK_REQUEST_THRESHOLD,
                DynamicBlockResponseConfig.DEFAULT_REQUEST_THRESHOLD
            ).coerceIn(
                DynamicBlockResponseConfig.MIN_REQUEST_THRESHOLD,
                DynamicBlockResponseConfig.MAX_REQUEST_THRESHOLD
            ),
            windowSeconds = prefs.getInt(
                KEY_DYNAMIC_BLOCK_WINDOW_SECONDS,
                DynamicBlockResponseConfig.DEFAULT_WINDOW_SECONDS
            ).coerceIn(
                DynamicBlockResponseConfig.MIN_WINDOW_SECONDS,
                DynamicBlockResponseConfig.MAX_WINDOW_SECONDS
            ),
            nxDomainDurationSeconds = prefs.getInt(
                KEY_DYNAMIC_BLOCK_NXDOMAIN_DURATION_SECONDS,
                DynamicBlockResponseConfig.DEFAULT_NXDOMAIN_DURATION_SECONDS
            ).coerceIn(
                DynamicBlockResponseConfig.MIN_NXDOMAIN_DURATION_SECONDS,
                DynamicBlockResponseConfig.MAX_NXDOMAIN_DURATION_SECONDS
            )
        )
    }

    fun setDynamicBlockResponseConfig(context: Context, config: DynamicBlockResponseConfig) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_DYNAMIC_BLOCK_RESPONSE_ENABLED, config.enabled)
            .putInt(
                KEY_DYNAMIC_BLOCK_REQUEST_THRESHOLD,
                config.requestThreshold.coerceIn(
                    DynamicBlockResponseConfig.MIN_REQUEST_THRESHOLD,
                    DynamicBlockResponseConfig.MAX_REQUEST_THRESHOLD
                )
            )
            .putInt(
                KEY_DYNAMIC_BLOCK_WINDOW_SECONDS,
                config.windowSeconds.coerceIn(
                    DynamicBlockResponseConfig.MIN_WINDOW_SECONDS,
                    DynamicBlockResponseConfig.MAX_WINDOW_SECONDS
                )
            )
            .putInt(
                KEY_DYNAMIC_BLOCK_NXDOMAIN_DURATION_SECONDS,
                config.nxDomainDurationSeconds.coerceIn(
                    DynamicBlockResponseConfig.MIN_NXDOMAIN_DURATION_SECONDS,
                    DynamicBlockResponseConfig.MAX_NXDOMAIN_DURATION_SECONDS
                )
            )
            .apply()
    }

    private fun migrateLegacyProviderIds(context: Context, key: String, ids: Collection<String>): Set<String> {
        val migrated = ids.mapTo(linkedSetOf()) { id ->
            if (id in DnsProvider.LEGACY_DOH3_PRESET_IDS) DnsProvider.GOOGLE_DOH_PROVIDER_ID else id
        }
        if (migrated != ids.toSet()) {
            val array = JSONArray()
            migrated.forEach(array::put)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putString(key, array.toString()).apply()
        }
        return migrated
    }

    fun isLegacyLogPageEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_LEGACY_LOG_PAGE_ENABLED, DEFAULT_LEGACY_LOG_PAGE_ENABLED)
    }

    fun setLegacyLogPageEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_LEGACY_LOG_PAGE_ENABLED, enabled)
            .apply()
    }

    fun getAppAllowlistPackages(context: Context): Set<String> = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getStringSet(KEY_APP_ALLOWLIST_PACKAGES, emptySet()).orEmpty()
        .filter { it.isNotBlank() && it != context.packageName }.toSet()

    fun setAppAllowlistPackages(context: Context, packageNames: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putStringSet(KEY_APP_ALLOWLIST_PACKAGES, packageNames.filter { it.isNotBlank() && it != context.packageName }.toSet()).apply()
    }

    fun getAppAllowlistDomains(context: Context): Set<String> = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getStringSet(KEY_APP_ALLOWLIST_DOMAINS, emptySet()).orEmpty().filter { it.isNotBlank() }.toSet()

    fun setAppAllowlistDomains(context: Context, domains: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putStringSet(KEY_APP_ALLOWLIST_DOMAINS, domains.filter { it.isNotBlank() }.toSet()).apply()
    }

    fun isAppAllowlistEnabled(context: Context): Boolean = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(KEY_APP_ALLOWLIST_ENABLED, false)

    fun setAppAllowlistEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().putBoolean(KEY_APP_ALLOWLIST_ENABLED, enabled).apply()
    }

    fun shouldHideGoTunnelDisableButtonWhenInactive(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(
                KEY_HIDE_GO_TUNNEL_DISABLE_BUTTON_WHEN_INACTIVE,
                DEFAULT_HIDE_GO_TUNNEL_DISABLE_BUTTON_WHEN_INACTIVE
            )
    }

    fun setHideGoTunnelDisableButtonWhenInactive(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_HIDE_GO_TUNNEL_DISABLE_BUTTON_WHEN_INACTIVE, enabled)
            .apply()
    }

    fun isServiceLightEffectEnabled(context: Context): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) {
            return false
        }
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_SERVICE_LIGHT_EFFECT_ENABLED, DEFAULT_SERVICE_LIGHT_EFFECT_ENABLED)
    }

    fun setServiceLightEffectEnabled(context: Context, enabled: Boolean) {
        val supportedEnabled = enabled && !isCustomBackgroundEnabled(context) &&
            android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_SERVICE_LIGHT_EFFECT_ENABLED, supportedEnabled)
            .apply()
    }

    fun isCustomBackgroundEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_CUSTOM_BACKGROUND_ENABLED, false) &&
            getCustomBackgroundUri(context) in getCustomBackgroundUris(context)
    }

    fun getCustomBackgroundUri(context: Context): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_CUSTOM_BACKGROUND_URI, null)
    }

    fun getCustomBackgroundUris(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val stored = prefs.getString(KEY_CUSTOM_BACKGROUND_URIS, null)
        if (stored != null) {
            return try {
                val array = JSONArray(stored)
                buildList {
                    for (index in 0 until array.length()) {
                        array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
                    }
                }.distinct()
            } catch (_: Exception) {
                emptyList()
            }
        }

        val legacyUri = prefs.getString(KEY_CUSTOM_BACKGROUND_URI, null)?.takeIf { it.isNotBlank() }
        val uris = listOfNotNull(legacyUri)
        saveCustomBackgroundUris(context, uris)
        return uris
    }

    fun addCustomBackgroundUri(context: Context, uri: String) {
        val normalizedUri = uri.takeIf { it.isNotBlank() } ?: return
        val uris = getCustomBackgroundUris(context)
        if (normalizedUri !in uris) {
            saveCustomBackgroundUris(context, uris + normalizedUri)
        }
    }

    fun removeCustomBackgroundUri(context: Context, uri: String) {
        val remainingUris = getCustomBackgroundUris(context).filterNot { it == uri }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isCurrentUri = prefs.getString(KEY_CUSTOM_BACKGROUND_URI, null) == uri
        saveCustomBackgroundUris(context, remainingUris)
        if (isCurrentUri) {
            prefs.edit()
                .putBoolean(KEY_CUSTOM_BACKGROUND_ENABLED, false)
                .putString(KEY_CUSTOM_BACKGROUND_URI, null)
                .apply()
        }
    }

    fun setCustomBackground(context: Context, enabled: Boolean, uri: String?) {
        val normalizedUri = uri?.takeIf { it.isNotBlank() }
        if (normalizedUri != null) addCustomBackgroundUri(context, normalizedUri)
        val actualEnabled = enabled && normalizedUri != null
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_CUSTOM_BACKGROUND_ENABLED, actualEnabled)
            .putString(KEY_CUSTOM_BACKGROUND_URI, normalizedUri)
            .apply {
                if (actualEnabled) putBoolean(KEY_SERVICE_LIGHT_EFFECT_ENABLED, false)
            }
            .apply()
    }

    private fun saveCustomBackgroundUris(context: Context, uris: List<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CUSTOM_BACKGROUND_URIS, JSONArray(uris.distinct()).toString())
            .apply()
    }

    fun loadBootstrapIpEntries(context: Context): List<BootstrapIpEntry> {
        val selectedPresetIds = getBootstrapPresetIds(context)
        val presets = BootstrapIpDefaults.PRESETS.map { entry ->
            entry.copy(enabled = entry.id in selectedPresetIds)
        }
        return presets + getCustomBootstrapIpEntries(context)
    }

    fun loadEnabledBootstrapIpEntries(context: Context): List<BootstrapIpEntry> {
        if (!isBootstrapEnabled(context)) return emptyList()
        return loadBootstrapIpEntries(context).filter { it.enabled }
    }

    fun setBootstrapIpEnabled(context: Context, id: String, enabled: Boolean) {
        val presetIds = BootstrapIpDefaults.PRESETS.map { it.id }.toSet()
        if (id in presetIds) {
            val selected = getBootstrapPresetIds(context).toMutableSet()
            if (enabled) selected.add(id) else selected.remove(id)
            setBootstrapPresetIds(context, selected)
            return
        }
        val updated = getCustomBootstrapIpEntries(context).map { entry ->
            if (entry.id == id) entry.copy(enabled = enabled) else entry
        }
        saveCustomBootstrapIpEntries(context, updated)
    }

    fun addCustomBootstrapIp(context: Context, name: String, ip: String): BootstrapIpEntry? {
        val trimmedIp = ip.trim()
        if (!BootstrapIpValidator.isValidIp(trimmedIp)) return null
        val entry = BootstrapIpEntry(
            id = "custom_${UUID.randomUUID()}",
            name = name.trim().ifBlank { trimmedIp },
            ip = trimmedIp,
            isPreset = false,
            enabled = true
        )
        saveCustomBootstrapIpEntries(context, getCustomBootstrapIpEntries(context) + entry)
        return entry
    }

    fun deleteCustomBootstrapIp(context: Context, id: String) {
        saveCustomBootstrapIpEntries(
            context,
            getCustomBootstrapIpEntries(context).filter { it.id != id }
        )
    }

    fun isValidBootstrapIp(ip: String?): Boolean {
        return BootstrapIpValidator.isValidIp(ip)
    }

    private fun getBootstrapPresetIds(context: Context): Set<String> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_BOOTSTRAP_PRESET_IDS, null)
            ?: return DEFAULT_BOOTSTRAP_PRESET_IDS
        return try {
            val array = JSONArray(json)
            buildSet {
                for (i in 0 until array.length()) {
                    add(array.getString(i))
                }
            }
        } catch (_: Exception) {
            DEFAULT_BOOTSTRAP_PRESET_IDS
        }
    }

    private fun setBootstrapPresetIds(context: Context, ids: Set<String>) {
        val validIds = BootstrapIpDefaults.PRESETS.map { it.id }.toSet()
        val array = JSONArray()
        ids.filter { it in validIds }.forEach { array.put(it) }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_BOOTSTRAP_PRESET_IDS, array.toString())
            .apply()
    }

    private fun getCustomBootstrapIpEntries(context: Context): List<BootstrapIpEntry> {
        val json = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_BOOTSTRAP_CUSTOM_JSON, null)
            ?: return emptyList()
        return try {
            val array = JSONArray(json)
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val ip = obj.optString("ip", "").trim()
                    if (!BootstrapIpValidator.isValidIp(ip)) continue
                    add(
                        BootstrapIpEntry(
                            id = obj.optString("id", "").takeIf { it.isNotBlank() } ?: "custom_${UUID.randomUUID()}",
                            name = obj.optString("name", ip).takeIf { it.isNotBlank() } ?: ip,
                            ip = ip,
                            isPreset = false,
                            enabled = obj.optBoolean("enabled", true)
                        )
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveCustomBootstrapIpEntries(context: Context, entries: List<BootstrapIpEntry>) {
        val array = JSONArray()
        entries.filter { !it.isPreset && BootstrapIpValidator.isValidIp(it.ip) }.forEach { entry ->
            array.put(
                JSONObject().apply {
                    put("id", entry.id)
                    put("name", entry.name)
                    put("ip", entry.ip)
                    put("enabled", entry.enabled)
                }
            )
        }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_BOOTSTRAP_CUSTOM_JSON, array.toString())
            .apply()
    }
}
