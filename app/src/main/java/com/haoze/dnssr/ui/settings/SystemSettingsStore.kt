package com.haoze.dnssr.ui.settings

import android.content.Context
import com.haoze.dnssr.ui.DnsLogMode

object SystemSettingsStore {
    const val KEY_LOG_RETENTION_DAYS = "log_retention_days"
    const val KEY_HIDE_FROM_RECENTS_ENABLED = "hide_from_recents_enabled"
    const val KEY_BYPASS_LAN_ENABLED = "bypass_lan_enabled"
    const val DEFAULT_BYPASS_LAN_ENABLED = true

    private const val KEY_DNS_LOG_MODE = "dns_log_mode"
    private const val KEY_FLOATING_LOG_ENABLED = "floating_log_enabled"
    private const val KEY_FLOATING_LOG_PANEL_SIZE = "floating_log_panel_size"
    private const val KEY_MAIN_ACTIVITY_FOREGROUND = "main_activity_foreground"
    private const val KEY_APP_UPDATE_DOWNLOAD_PATH = "app_update_download_path"
    private const val KEY_APP_UPDATE_DOWNLOAD_VERSION = "app_update_download_version"
    private const val KEY_DISABLE_STARTUP_UPDATE_CHECK = "disable_startup_update_check"
    private const val KEY_SETTINGS_GUIDE_ACKNOWLEDGED_IDS = "settings_guide_acknowledged_ids"
    private const val KEY_INITIAL_AGREEMENT_ACCEPTED = "initial_agreement_accepted"
    private const val KEY_DATA_RESET_NOTICE_PENDING = "data_reset_notice_pending"
    private const val KEY_APP_TRAFFIC_STATS_ENABLED = "app_traffic_stats_enabled"
    private const val KEY_TRAFFIC_STATS_RETENTION_DAYS = "traffic_stats_retention_days"
    private const val KEY_TRAFFIC_STATS_HIDE_SYSTEM_APPS = "traffic_stats_hide_system_apps"

    private const val DEFAULT_LOG_RETENTION_DAYS = 7
    private const val DEFAULT_TRAFFIC_STATS_RETENTION_DAYS = 30
    private const val DEFAULT_HIDE_FROM_RECENTS_ENABLED = false

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

    fun isAppTrafficStatsEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_APP_TRAFFIC_STATS_ENABLED, true)
    }

    fun setAppTrafficStatsEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_APP_TRAFFIC_STATS_ENABLED, enabled)
            .apply()
    }

    fun getTrafficStatsRetentionDays(context: Context): Int {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_TRAFFIC_STATS_RETENTION_DAYS, DEFAULT_TRAFFIC_STATS_RETENTION_DAYS)
    }

    fun setTrafficStatsRetentionDays(context: Context, days: Int) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_TRAFFIC_STATS_RETENTION_DAYS, days.coerceIn(1, 90))
            .apply()
    }

    fun isTrafficStatsHideSystemApps(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_TRAFFIC_STATS_HIDE_SYSTEM_APPS, false)
    }

    fun setTrafficStatsHideSystemApps(context: Context, hide: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_TRAFFIC_STATS_HIDE_SYSTEM_APPS, hide)
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

    fun isDataResetNoticePending(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_DATA_RESET_NOTICE_PENDING, false)
    }

    fun setDataResetNoticePending(context: Context, pending: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_DATA_RESET_NOTICE_PENDING, pending)
            .apply()
    }

    fun dismissDataResetNotice(context: Context) {
        setDataResetNoticePending(context, false)
    }

    fun isBypassLanEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_BYPASS_LAN_ENABLED, DEFAULT_BYPASS_LAN_ENABLED)
    }

    fun setBypassLanEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_BYPASS_LAN_ENABLED, enabled)
            .apply()
    }
}
