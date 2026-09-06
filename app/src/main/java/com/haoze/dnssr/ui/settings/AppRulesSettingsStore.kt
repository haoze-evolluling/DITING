package com.haoze.dnssr.ui.settings

import android.content.Context
import com.haoze.dnssr.vpn.BlockResponseMode
import com.haoze.dnssr.vpn.DynamicBlockResponseConfig

object AppRulesSettingsStore {
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
    private const val KEY_HTTP_INSPECTION_APPS_FILTER = "http_inspection_apps_filter"
    private const val KEY_HTTP_INSPECTION_APPS_SORT = "http_inspection_apps_sort"
    private const val KEY_HTTPS_INSPECTION_READY = "https_inspection_ready"
    private const val KEY_HTTPS_INSPECTION_CA_BACKEND = "https_inspection_ca_backend"
    private const val KEY_HTTP3_INSPECTION_ENABLED = "http3_inspection_enabled"
    private const val KEY_ENCRYPTED_DNS_BLOCKING_ENABLED = "encrypted_dns_blocking_enabled"
    private const val KEY_DOMAIN_RULES_ENABLED = "domain_rules_enabled"
    private const val KEY_ADDRESS_RULES_ENABLED = "address_rules_enabled"
    private const val KEY_BLOCK_RESPONSE_MODE = "block_response_mode"
    private const val KEY_DYNAMIC_BLOCK_RESPONSE_ENABLED = "dynamic_block_response_enabled"
    private const val KEY_DYNAMIC_BLOCK_REQUEST_THRESHOLD = "dynamic_block_request_threshold"
    private const val KEY_DYNAMIC_BLOCK_WINDOW_SECONDS = "dynamic_block_window_seconds"
    private const val KEY_DYNAMIC_BLOCK_NXDOMAIN_DURATION_SECONDS = "dynamic_block_nxdomain_duration_seconds"
    private const val KEY_ALLOW_EDIT_DEFAULT_WHITELIST = "allow_edit_default_whitelist"
    private const val KEY_DEFAULT_WHITELIST_INITIALIZED = "default_whitelist_initialized"
    private const val KEY_DEFAULT_WHITELIST_SEEDED_VERSION = "default_whitelist_seeded_version"

    private const val GO_CA_BACKEND = "go-v1"
    private val DEFAULT_BLOCK_RESPONSE_MODE = BlockResponseMode.NXDOMAIN

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

    fun getExcludedAppsSort(context: Context) = getAppListPreference(context, KEY_EXCLUDED_APPS_SORT, "LABEL_ASC")
    fun setExcludedAppsSort(context: Context, sort: String) = setAppListPreference(context, KEY_EXCLUDED_APPS_SORT, sort)

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

    fun setBlockedAppPackages(context: Context, packageNames: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(
                KEY_BLOCKED_APP_PACKAGES,
                packageNames.filter { it.isNotBlank() && it != context.packageName }.toSet()
            )
            .apply()
    }

    fun getBlockedAppsFilter(context: Context) =
        getAppListPreference(context, KEY_BLOCKED_APPS_FILTER, getExcludedAppsFilter(context))
    fun setBlockedAppsFilter(context: Context, filter: String) = setAppListPreference(context, KEY_BLOCKED_APPS_FILTER, filter)
    fun getBlockedAppsSort(context: Context) = getAppListPreference(context, KEY_BLOCKED_APPS_SORT, "LABEL_ASC")
    fun setBlockedAppsSort(context: Context, sort: String) = setAppListPreference(context, KEY_BLOCKED_APPS_SORT, sort)

    private const val KEY_APP_ALLOWLIST_RULES_JSON = "app_allowlist_rules_json"

    fun getAppAllowlistRuleMap(context: Context): Map<String, Set<String>> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        // Directly remove and reset legacy configuration for this feature
        if (prefs.contains(KEY_APP_ALLOWLIST_DOMAINS) || prefs.contains(KEY_APP_ALLOWLIST_PACKAGES)) {
            prefs.edit()
                .remove(KEY_APP_ALLOWLIST_DOMAINS)
                .remove(KEY_APP_ALLOWLIST_PACKAGES)
                .remove(KEY_APP_ALLOWLIST_ENABLED)
                .apply()
        }
        val jsonStr = prefs.getString(KEY_APP_ALLOWLIST_RULES_JSON, null) ?: return emptyMap()
        val result = mutableMapOf<String, Set<String>>()
        try {
            val json = org.json.JSONObject(jsonStr)
            val keys = json.keys()
            while (keys.hasNext()) {
                val pkg = keys.next()
                if (pkg.isBlank() || pkg == context.packageName) continue
                val arr = json.optJSONArray(pkg) ?: continue
                val set = mutableSetOf<String>()
                for (i in 0 until arr.length()) {
                    val dom = arr.optString(i)?.trim().orEmpty()
                    if (dom.isNotEmpty()) set.add(dom)
                }
                if (set.isNotEmpty()) {
                    result[pkg] = set
                }
            }
            return result
        } catch (_: Exception) {
            return emptyMap()
        }
    }

    fun setAppAllowlistRuleMap(context: Context, rules: Map<String, Set<String>>) {
        val json = org.json.JSONObject()
        rules.forEach { (pkg, domains) ->
            if (pkg.isNotBlank() && pkg != context.packageName && domains.isNotEmpty()) {
                val arr = org.json.JSONArray()
                domains.filter { it.isNotBlank() }.forEach { arr.put(it) }
                if (arr.length() > 0) {
                    json.put(pkg, arr)
                }
            }
        }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_APP_ALLOWLIST_RULES_JSON, json.toString())
            .apply()
    }

    fun getAppAllowlistDomainsForApp(context: Context, packageName: String): Set<String> {
        return getAppAllowlistRuleMap(context)[packageName].orEmpty()
    }

    fun setAppAllowlistDomainsForApp(context: Context, packageName: String, domains: Set<String>) {
        val rules = getAppAllowlistRuleMap(context).toMutableMap()
        val cleanDomains = domains.filter { it.isNotBlank() }.toSet()
        if (cleanDomains.isEmpty()) {
            rules.remove(packageName)
        } else {
            rules[packageName] = cleanDomains
        }
        setAppAllowlistRuleMap(context, rules)
    }

    fun removeAppAllowlistForApp(context: Context, packageName: String) {
        val rules = getAppAllowlistRuleMap(context).toMutableMap()
        if (rules.remove(packageName) != null) {
            setAppAllowlistRuleMap(context, rules)
        }
    }

    fun getAppAllowlistPackages(context: Context): Set<String> =
        getAppAllowlistRuleMap(context).keys

    fun setAppAllowlistPackages(context: Context, packageNames: Set<String>) {
        val currentRules = getAppAllowlistRuleMap(context).toMutableMap()
        val toKeep = packageNames.filter { it.isNotBlank() && it != context.packageName }.toSet()
        currentRules.keys.retainAll(toKeep)
        setAppAllowlistRuleMap(context, currentRules)
    }

    fun isAppAllowlistEnabled(context: Context): Boolean = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(KEY_APP_ALLOWLIST_ENABLED, false)

    fun setAppAllowlistEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().putBoolean(KEY_APP_ALLOWLIST_ENABLED, enabled).apply()
    }

    fun getAppAllowlistFilter(context: Context) = getAppListPreference(context, KEY_APP_ALLOWLIST_FILTER, "USER")
    fun setAppAllowlistFilter(context: Context, filter: String) = setAppListPreference(context, KEY_APP_ALLOWLIST_FILTER, filter)
    fun getAppAllowlistSort(context: Context) = getAppListPreference(context, KEY_APP_ALLOWLIST_SORT, "LABEL_ASC")
    fun setAppAllowlistSort(context: Context, sort: String) = setAppListPreference(context, KEY_APP_ALLOWLIST_SORT, sort)

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

    fun setHttpInspectionAppPackages(context: Context, packageNames: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_HTTP_INSPECTION_APP_PACKAGES, packageNames.filter { it.isNotBlank() }.toSet())
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

    fun getHttpInspectionAppsFilter(context: Context) =
        getAppListPreference(context, KEY_HTTP_INSPECTION_APPS_FILTER, getExcludedAppsFilter(context))
    fun setHttpInspectionAppsFilter(context: Context, filter: String) = setAppListPreference(context, KEY_HTTP_INSPECTION_APPS_FILTER, filter)
    fun getHttpInspectionAppsSort(context: Context) = getAppListPreference(context, KEY_HTTP_INSPECTION_APPS_SORT, "LABEL_ASC")
    fun setHttpInspectionAppsSort(context: Context, sort: String) = setAppListPreference(context, KEY_HTTP_INSPECTION_APPS_SORT, sort)

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

    fun isHttpsInspectionOperational(context: Context): Boolean =
        isHttpsInspectionReady(context) &&
            isHttpInspectionEnabled(context) &&
            getHttpInspectionAppPackages(context).isNotEmpty()

    fun isAddressRulesFullyOperational(context: Context): Boolean =
        isAddressRulesEnabled(context) && isHttpsInspectionOperational(context)

    fun checkAndUpdateHttpsInspectionReady(context: Context): Boolean {
        val installed = runCatching {
            com.haoze.dnssr.vpn.GoInspectionCaManager.isInstalled(context)
        }.getOrDefault(false)
        setHttpsInspectionReady(context, installed)
        if (!installed) {
            setHttpInspectionEnabled(context, false)
        }
        return installed
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

    fun isEncryptedDnsBlockingEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENCRYPTED_DNS_BLOCKING_ENABLED, false)

    fun setEncryptedDnsBlockingEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENCRYPTED_DNS_BLOCKING_ENABLED, enabled)
            .apply()
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

    fun isDomainRulesEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_DOMAIN_RULES_ENABLED, true)

    fun setDomainRulesEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_DOMAIN_RULES_ENABLED, enabled)
            .apply()
    }

    fun isAddressRulesEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ADDRESS_RULES_ENABLED, true)

    fun setAddressRulesEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ADDRESS_RULES_ENABLED, enabled)
            .apply()
    }

    fun isAllowEditDefaultWhitelist(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ALLOW_EDIT_DEFAULT_WHITELIST, false)

    fun setAllowEditDefaultWhitelist(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ALLOW_EDIT_DEFAULT_WHITELIST, enabled)
            .apply()
    }

    fun isDefaultWhitelistInitialized(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_DEFAULT_WHITELIST_INITIALIZED, false)

    fun setDefaultWhitelistInitialized(context: Context, initialized: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_DEFAULT_WHITELIST_INITIALIZED, initialized)
            .apply()
    }

    /** 记录上次灌入/重置预设白名单时的应用版本号；0 表示从未记录（旧版本升级而来）。 */
    fun getDefaultWhitelistSeededVersion(context: Context): Long =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getLong(KEY_DEFAULT_WHITELIST_SEEDED_VERSION, 0L)

    fun setDefaultWhitelistSeededVersion(context: Context, versionCode: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_DEFAULT_WHITELIST_SEEDED_VERSION, versionCode)
            .apply()
    }

    private fun getAppListPreference(context: Context, key: String, default: String): String =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(key, default) ?: default

    private fun setAppListPreference(context: Context, key: String, value: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().putString(key, value).apply()
    }
}
