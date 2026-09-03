package com.haoze.dnssr

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize
import androidx.lifecycle.lifecycleScope
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.ui.*
import com.haoze.dnssr.ui.traffic.AppTrafficStatsScreen
import com.haoze.dnssr.ui.theme.ThemeColorStyle
import com.haoze.dnssr.update.AppUpdateDownloadStatus
import com.haoze.dnssr.update.AppUpdateDownloadState
import com.haoze.dnssr.update.AppUpdateManager
import com.haoze.dnssr.update.AppUpdateNotifier
import com.haoze.dnssr.update.AppUpdateUiState
import com.haoze.dnssr.vpn.DnsVpnService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class SettingsRouteActivity : AppLocalizedActivity() {
    private val route: String
        get() = intent.getStringExtra(EXTRA_ROUTE) ?: Routes.SETTINGS
    private val requestedRuleScope: RuleScope?
        get() = intent.getStringExtra(EXTRA_RULE_SCOPE)?.let { value ->
            runCatching { RuleScope.valueOf(value) }.getOrNull()
        }
    private val requestedRuleKind: ManagedRuleKind?
        get() = intent.getStringExtra(EXTRA_RULE_KIND)?.let { value ->
            runCatching { ManagedRuleKind.valueOf(value) }.getOrNull()
        }
    private val requestedTitle: String?
        get() = intent.getStringExtra(EXTRA_TITLE)

    private var resultData = Intent()
    private var languageModeAtCreate = AppLanguageMode.SYSTEM
    private var childLaunchInProgress = false
    private var routeRefreshVersion by mutableStateOf(0)
    private var outboundProxyAppSelectionResult by mutableStateOf<Pair<Boolean, String?>?>(null)
    private var appUpdateState by mutableStateOf(AppUpdateUiState())
    private var dismissedUpdateVersion by mutableStateOf("")
    private var appUpdateDownloadJob: Job? = null
    private var appUpdateDownloadGeneration = 0L
    private val appUpdateManager by lazy { AppUpdateManager(applicationContext) }
    private val appUpdateNotifier by lazy { AppUpdateNotifier(applicationContext) }

    private val childActivityLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        childLaunchInProgress = false
        mergeResult(result.data)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        languageModeAtCreate = AppLanguageManager.getMode(this)
        enableEdgeToEdge()
        setResult(RESULT_OK, resultData)
        setContent {
            var themeMode by remember(routeRefreshVersion) { mutableStateOf(AppSettings.getAppThemeMode(this)) }
            var colorStyle by remember(routeRefreshVersion) { mutableStateOf(AppSettings.getThemeColorStyle(this)) }
            var backgroundEnabled by remember(routeRefreshVersion) { mutableStateOf(AppSettings.isCustomBackgroundEnabled(this)) }
            var backgroundUri by remember(routeRefreshVersion) { mutableStateOf(AppSettings.getCustomBackgroundUri(this)) }

            AppThemeSurface(
                themeMode = themeMode,
                colorStyle = colorStyle,
                backgroundEnabled = backgroundEnabled,
                backgroundUri = backgroundUri,
                modifier = Modifier.fillMaxSize()
            ) {
                SettingsRouteContent(
                    route = route,
                    ruleScope = requestedRuleScope,
                    ruleKind = requestedRuleKind,
                    requestedTitle = requestedTitle,
                    outboundProxyAppSelectionResult = outboundProxyAppSelectionResult,
                    onBack = ::finishSettings,
                    onNavigate = ::openRoute,
                    onRuntimeDnsSettingsChanged = {
                        RuntimeDnsSettingsRefresher.refreshIfRunning(this@SettingsRouteActivity)
                        recordRuntimeDnsChanged()
                    },
                    onHideFromRecentsChanged = { hide ->
                        applyRecentsPrivacy(hide)
                        recordHideFromRecentsChanged(hide)
                    },
                    onThemeModeChanged = { mode ->
                        themeMode = mode
                        recordThemeChanged()
                    },
                    onThemeColorStyleChanged = { style ->
                        colorStyle = style
                        recordThemeChanged()
                    },
                    onCustomBackgroundChanged = {
                        backgroundEnabled = AppSettings.isCustomBackgroundEnabled(this@SettingsRouteActivity)
                        backgroundUri = AppSettings.getCustomBackgroundUri(this@SettingsRouteActivity)
                        recordBackgroundChanged()
                    },
                    onExitApp = ::finishAndRemoveTask,
                    appUpdateState = appUpdateState,
                    onCheckForAppUpdate = ::checkForAppUpdate,
                    onDownloadAppUpdate = ::downloadAppUpdate,
                    onJoinQqGroup = ::joinQqGroup,
                    startupUpdateCheckDisabled = AppSettings.isStartupUpdateCheckDisabled(this),
                    onStartupUpdateCheckDisabledChange = {
                        AppSettings.setStartupUpdateCheckDisabled(this, it)
                    }
                )
                if (route == Routes.APP_UPDATE) {
                    appUpdateState.availableUpdate?.let { update ->
                        if (dismissedUpdateVersion != update.version) {
                            AppUpdateDialog(
                                update = update,
                                downloadState = appUpdateState.downloadState,
                                onDismiss = { dismissedUpdateVersion = update.version },
                                onDownload = ::downloadAppUpdate,
                            )
                        }
                    }
                }
            }
        }
    }

    private fun applyLanguage(mode: AppLanguageMode) {
        AppLanguageManager.setMode(this, mode)
        recreate()
    }

    override fun onStart() {
        super.onStart()
        DnsVpnService.updateFloatingLogAppState(this, true)
    }

    override fun onResume() {
        super.onResume()
        val currentLanguageMode = AppLanguageManager.getMode(this)
        if (currentLanguageMode != languageModeAtCreate) {
            languageModeAtCreate = currentLanguageMode
            recreate()
        }
    }

    override fun onStop() {
        DnsVpnService.updateFloatingLogAppState(this, false)
        super.onStop()
    }

    private fun openRoute(nextRoute: String) {
        if (childLaunchInProgress || nextRoute == route) return
        childLaunchInProgress = true
        childActivityLauncher.launch(createIntent(this, nextRoute))
    }

    private fun finishSettings() {
        setResult(RESULT_OK, resultData)
        finish()
    }

    private fun finishOutboundProxyAppSelection(packageName: String) {
        resultData.putExtra(EXTRA_OUTBOUND_PROXY_APP_SELECTED, true)
        resultData.putExtra(EXTRA_OUTBOUND_PROXY_APP_PACKAGE, packageName)
        setResult(RESULT_OK, resultData)
        finish()
    }

    private fun mergeResult(data: Intent?) {
        if (data == null) return
        if (data.getBooleanExtra(EXTRA_RUNTIME_DNS_CHANGED, false)) recordRuntimeDnsChanged()
        if (data.getBooleanExtra(EXTRA_THEME_CHANGED, false)) recordThemeChanged()
        if (data.getBooleanExtra(EXTRA_BACKGROUND_CHANGED, false)) recordBackgroundChanged()
        if (data.hasExtra(EXTRA_HIDE_FROM_RECENTS)) {
            recordHideFromRecentsChanged(data.getBooleanExtra(EXTRA_HIDE_FROM_RECENTS, false))
        }
        if (data.getBooleanExtra(EXTRA_OUTBOUND_PROXY_APP_SELECTED, false)) {
            outboundProxyAppSelectionResult = true to data.getStringExtra(EXTRA_OUTBOUND_PROXY_APP_PACKAGE)
        }
        routeRefreshVersion++
    }

    private fun recordRuntimeDnsChanged() {
        resultData.putExtra(EXTRA_RUNTIME_DNS_CHANGED, true)
        setResult(RESULT_OK, resultData)
    }

    private fun recordThemeChanged() {
        resultData.putExtra(EXTRA_THEME_CHANGED, true)
        setResult(RESULT_OK, resultData)
    }

    private fun recordBackgroundChanged() {
        resultData.putExtra(EXTRA_BACKGROUND_CHANGED, true)
        setResult(RESULT_OK, resultData)
    }

    private fun recordHideFromRecentsChanged(hide: Boolean) {
        resultData.putExtra(EXTRA_HIDE_FROM_RECENTS, hide)
        setResult(RESULT_OK, resultData)
    }

    private fun applyRecentsPrivacy(hideFromRecents: Boolean) {
        RecentsPrivacyController.apply(this, hideFromRecents)
    }

    private fun checkForAppUpdate() {
        if (appUpdateState.checking) return
        dismissedUpdateVersion = ""
        appUpdateState = appUpdateState.copy(checking = true, error = "", message = "正在检查 GitHub Release")
        lifecycleScope.launch {
            try {
                val update = appUpdateManager.checkForUpdate()
                val downloadState = update?.let { appUpdateManager.refreshDownloadState(it) }
                appUpdateState = AppUpdateUiState(
                    availableUpdate = update,
                    downloadState = downloadState ?: appUpdateState.downloadState,
                    message = if (update == null) "当前已是最新版本。" else "发现 ${update.version} 新版本。"
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                appUpdateState = appUpdateState.copy(checking = false, error = error.message ?: "检查更新失败。")
            }
        }
    }

    private fun joinQqGroup() {
        try {
            startActivity(
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("mqqapi://card/show_pslcard?src_type=internal&version=1&uin=1090225658&card_type=group&source=qrcode"),
                ),
            )
        } catch (_: Exception) {
            Toast.makeText(this, localizedText(this, "未检测到 QQ，请搜索群号 1090225658 加入。"), Toast.LENGTH_LONG).show()
        }
    }

    private fun downloadAppUpdate() {
        val update = appUpdateState.availableUpdate ?: return
        val status = appUpdateState.downloadState.status.takeIf { appUpdateState.downloadState.version == update.version }
        if (status == AppUpdateDownloadStatus.Downloading) return
        if (status == AppUpdateDownloadStatus.Downloaded) {
            if (!appUpdateManager.installDownloadedUpdate(update)) {
                appUpdateState = appUpdateState.copy(downloadState = AppUpdateDownloadState(version = update.version), error = "安装包不存在或无法打开，请重新下载。")
            }
            return
        }
        appUpdateDownloadJob?.cancel()
        appUpdateNotifier.clear()
        val generation = ++appUpdateDownloadGeneration
        appUpdateDownloadJob = lifecycleScope.launch {
            try {
                appUpdateState = appUpdateState.copy(downloadState = AppUpdateDownloadState(version = update.version, status = AppUpdateDownloadStatus.Downloading), error = "")
                appUpdateNotifier.showProgress(update, 0L, -1L)
                val downloadState = appUpdateManager.download(update) { downloadedBytes, totalBytes ->
                    runOnUiThread {
                        if (generation == appUpdateDownloadGeneration) {
                            appUpdateState = appUpdateState.copy(
                                downloadState = AppUpdateDownloadState(
                                    version = update.version,
                                    status = AppUpdateDownloadStatus.Downloading,
                                    downloadedBytes = downloadedBytes,
                                    totalBytes = totalBytes
                                )
                            )
                            appUpdateNotifier.showProgress(update, downloadedBytes, totalBytes)
                        }
                    }
                }
                if (generation != appUpdateDownloadGeneration) return@launch
                appUpdateState = appUpdateState.copy(downloadState = downloadState, error = if (downloadState.status == AppUpdateDownloadStatus.Failed) "更新包下载失败，请重试。" else "")
                if (downloadState.status == AppUpdateDownloadStatus.Downloaded) appUpdateNotifier.showCompleted(update) else appUpdateNotifier.clear()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                appUpdateNotifier.clear()
                appUpdateState = appUpdateState.copy(error = error.message ?: "无法开始下载更新。")
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun SettingsRouteContent(
        route: String,
        ruleScope: RuleScope?,
        ruleKind: ManagedRuleKind?,
        requestedTitle: String?,
        outboundProxyAppSelectionResult: Pair<Boolean, String?>?,
        onBack: () -> Unit,
        onNavigate: (String) -> Unit,
        onRuntimeDnsSettingsChanged: () -> Unit,
        onHideFromRecentsChanged: (Boolean) -> Unit,
        onThemeModeChanged: (AppThemeMode) -> Unit,
        onThemeColorStyleChanged: (ThemeColorStyle) -> Unit,
        onCustomBackgroundChanged: () -> Unit,
        onExitApp: () -> Unit,
        appUpdateState: AppUpdateUiState,
        onCheckForAppUpdate: () -> Unit,
        onDownloadAppUpdate: () -> Unit,
        onJoinQqGroup: () -> Unit,
        startupUpdateCheckDisabled: Boolean,
        onStartupUpdateCheckDisabledChange: (Boolean) -> Unit
    ) {
        when (route) {
            Routes.SETTINGS -> SettingsScreen(onBack, onNavigate)
            Routes.LANGUAGE_SETTINGS -> LanguageSettingsScreen(::finishSettings, ::applyLanguage)
            Routes.RULE_MANAGEMENT -> SettingsGuideHost(SettingsGuides.DOMAIN_RULES) { RuleControlScreen(onBack, onNavigateToBlockResponseSettings = { onNavigate(Routes.BLOCK_RESPONSE_SETTINGS) }, onNavigateToSubscription = { onNavigate(Routes.SUBSCRIPTION_MANAGEMENT) }, onNavigateToAutoUpdateInterval = { onNavigate(Routes.SUBSCRIPTION_AUTO_UPDATE_INTERVAL) }, onNavigateToMirrorTemplates = { onNavigate(Routes.MIRROR_TEMPLATES) }, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged) }
            Routes.RULE_CONTROL -> SettingsGuideHost(SettingsGuides.DOMAIN_RULES) { RuleControlScreen(onBack, onNavigateToBlockResponseSettings = { onNavigate(Routes.BLOCK_RESPONSE_SETTINGS) }, onNavigateToSubscription = { onNavigate(Routes.SUBSCRIPTION_MANAGEMENT) }, onNavigateToAutoUpdateInterval = { onNavigate(Routes.SUBSCRIPTION_AUTO_UPDATE_INTERVAL) }, onNavigateToMirrorTemplates = { onNavigate(Routes.MIRROR_TEMPLATES) }, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged) }
            Routes.APP_RULE_MANAGEMENT -> SettingsGuideHost(SettingsGuides.APP_ALLOWLIST) { AppRuleManagementScreen(onBack) }
            Routes.WHITELIST_MANAGEMENT -> WhitelistScreen(onBack, onRuntimeDnsSettingsChanged)
            Routes.BLACKLIST_MANAGEMENT -> BlacklistScreen(onBack, onRuntimeDnsSettingsChanged)
            Routes.REWRITELIST_MANAGEMENT -> RewriteListScreen(onBack, onRuntimeDnsSettingsChanged)
            Routes.DOMAIN_RULE_MANAGEMENT -> SettingsGuideHost(SettingsGuides.DOMAIN_RULES) { RuleControlScreen(onBack, onNavigateToBlockResponseSettings = { onNavigate(Routes.BLOCK_RESPONSE_SETTINGS) }, onNavigateToSubscription = { onNavigate(Routes.SUBSCRIPTION_MANAGEMENT) }, onNavigateToAutoUpdateInterval = { onNavigate(Routes.SUBSCRIPTION_AUTO_UPDATE_INTERVAL) }, onNavigateToMirrorTemplates = { onNavigate(Routes.MIRROR_TEMPLATES) }, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged) }
            Routes.ADDRESS_RULE_MANAGEMENT -> SettingsGuideHost(SettingsGuides.DOMAIN_RULES) { RuleControlScreen(onBack, onNavigateToBlockResponseSettings = { onNavigate(Routes.BLOCK_RESPONSE_SETTINGS) }, onNavigateToSubscription = { onNavigate(Routes.SUBSCRIPTION_MANAGEMENT) }, onNavigateToAutoUpdateInterval = { onNavigate(Routes.SUBSCRIPTION_AUTO_UPDATE_INTERVAL) }, onNavigateToMirrorTemplates = { onNavigate(Routes.MIRROR_TEMPLATES) }, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged) }
            Routes.RULE_LIST -> RuleListScreen(onBack, ruleKind = ruleKind ?: ManagedRuleKind.BLOCK, ruleScope = ruleScope ?: RuleScope.DNS, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged)
            Routes.ALLOW_RULE_LIST -> RuleListScreen(onBack, ruleKind = ruleKind ?: ManagedRuleKind.ALLOW, ruleScope = ruleScope ?: RuleScope.DNS, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged)
            Routes.REWRITE_RULE_LIST -> RewriteListScreen(onBack, onRuntimeDnsSettingsChanged)
            Routes.ADDRESS_RULE_LIST -> RuleListScreen(onBack, ruleKind = ManagedRuleKind.URL_BLOCK, ruleScope = RuleScope.DNS, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged)
            Routes.ADDRESS_ALLOW_RULE_LIST -> RuleListScreen(onBack, ruleKind = ManagedRuleKind.URL_ALLOW, ruleScope = RuleScope.DNS, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged)
            Routes.EXCLUDED_APPS -> SettingsGuideHost(SettingsGuides.EXCLUDED_APPS) { ExcludedAppsScreen(onBack) }
            Routes.OUTBOUND_PROXY_SETTINGS -> OutboundProxySettingsScreen(
                onBack = onBack,
                onSelectApp = { onNavigate(Routes.OUTBOUND_PROXY_APP_SELECTION) },
                selectedAppOverride = outboundProxyAppSelectionResult
            )
            Routes.OUTBOUND_PROXY_APP_SELECTION -> OutboundProxyAppsScreen(onBack, ::finishOutboundProxyAppSelection)
            Routes.BLOCK_RESPONSE_SETTINGS -> BlockResponseSettingsScreen(onBack, onRuntimeDnsSettingsChanged)
            Routes.DATA_CLEANUP -> SettingsGuideHost(SettingsGuides.DATA_CLEANUP) { DataCleanupScreen(onBack, requestedTitle ?: ScreenDestinations.dataCleanup.title, onRuntimeDnsSettingsChanged, onExitApp) }
            Routes.CONFIG_TRANSFER -> SettingsGuideHost(SettingsGuides.CONFIG_TRANSFER) { ConfigTransferScreen(onBack, "备份与迁移") }
            Routes.CONFIG_IMPORT_EXPORT -> SettingsGuideHost(SettingsGuides.CONFIG_TRANSFER) { ConfigTransferScreen(onBack, "备份与迁移") }
            Routes.RULE_EXPORT -> SettingsGuideHost(SettingsGuides.CONFIG_TRANSFER) { ConfigTransferScreen(onBack, "备份与迁移") }
            Routes.RULE_IMPORT -> SettingsGuideHost(SettingsGuides.CONFIG_TRANSFER) { ConfigTransferScreen(onBack, "备份与迁移") }
            Routes.PROVIDER_MANAGEMENT -> SettingsGuideHost(SettingsGuides.PROVIDER_MANAGEMENT) { ProviderManagementScreen(onBack, "服务商管理") }
            Routes.HOME_PROVIDER_VISIBILITY -> SettingsGuideHost(SettingsGuides.SERVICE_DISPLAY) { HomeProviderVisibilityScreen(onBack, "服务显示") }
            Routes.BLOCKED_APPS -> SettingsGuideHost(SettingsGuides.BLOCKED_APPS) { BlockedAppsScreen(onBack) }
            Routes.BLOCKED_APPS_SELECTION -> BlockedAppsScreen(onBack)
            Routes.APP_ALLOWLIST -> SettingsGuideHost(SettingsGuides.APP_ALLOWLIST) { AppRuleManagementScreen(onBack) }
            Routes.APP_ALLOWLIST_SELECTION -> AppRuleManagementScreen(onBack)
            Routes.BOOTSTRAP_SETTINGS -> SettingsGuideHost(SettingsGuides.BOOTSTRAP) { BootstrapSettingsScreen(onBack, "Bootstrap 设置") }
            Routes.RACE_MODE_LATENCY -> SettingsGuideHost(SettingsGuides.LATENCY_TEST) { RaceModeLatencySettingsScreen(onBack, "查询测速") }
            Routes.RACE_MODE_PROVIDERS -> SettingsGuideHost(SettingsGuides.RESOLUTION_MODE) {
                ResolutionModeHomeScreen(
                    onBack = onBack,
                    onOpenMode = { mode -> onNavigate(mode.route) }
                )
            }
            Routes.RESOLUTION_SINGLE -> ResolutionModeConfigScreen(DnsResolutionMode.SINGLE, onBack)
            Routes.RESOLUTION_SMART -> ResolutionModeConfigScreen(DnsResolutionMode.SMART_PREDICTION, onBack)
            Routes.RESOLUTION_PARALLEL -> ResolutionModeConfigScreen(DnsResolutionMode.PARALLEL_RACE, onBack)
            Routes.RESOLUTION_BACKUP -> ResolutionModeConfigScreen(DnsResolutionMode.PRIMARY_BACKUP, onBack)
            Routes.CACHE_SETTINGS -> SettingsGuideHost(SettingsGuides.CACHE) { CacheSettingsScreen(onBack, ScreenDestinations.cacheSettings.title, onRuntimeDnsSettingsChanged) }
            Routes.LOG_RETENTION_SETTINGS -> SettingsGuideHost(SettingsGuides.LOG_MODE) { LogRetentionSettingsScreen(onBack, onRuntimeDnsSettingsChanged, ScreenDestinations.logRetentionSettings.title) }
            Routes.FOREGROUND_BACKGROUND_SETTINGS -> SettingsGuideHost(SettingsGuides.FOREGROUND_BACKGROUND) { ForegroundBackgroundSettingsScreen(onBack, ScreenDestinations.foregroundBackgroundSettings.title, onHideFromRecentsChanged) }
            Routes.HTTP_INSPECTION_SETTINGS -> SettingsGuideHost(SettingsGuides.HTTP_INSPECTION) { HttpInspectionSettingsScreen(onBack, { onNavigate(Routes.HTTP_REQUEST_LOGS) }, { onNavigate(Routes.HTTP_INSPECTION_APPS) }, { onNavigate(Routes.CA_CERTIFICATE_SETTINGS) }) }
            Routes.CA_CERTIFICATE_GUIDE -> CaCertificateGuideScreen(onBack)
            Routes.CA_CERTIFICATE_SETTINGS -> CaCertificateSettingsScreen(onBack, { onNavigate(Routes.CA_CERTIFICATE_GUIDE) })
            Routes.HTTP_INSPECTION_APPS -> HttpInspectionAppsScreen(onBack)
            Routes.HTTP_REQUEST_LOGS -> HttpRequestLogScreen(onBack)
            Routes.SUBSCRIPTION_MANAGEMENT -> SubscriptionScreen(onBack, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged)
            Routes.SUBSCRIPTION_AUTO_UPDATE_INTERVAL -> SubscriptionAutoUpdateIntervalScreen(onBack)
            Routes.ABOUT -> AboutScreen(onBack, "应用信息")
            Routes.APP_UPDATE -> AppUpdateScreen(appUpdateState, onBack, onCheckForAppUpdate, onDownloadAppUpdate, onJoinQqGroup, startupUpdateCheckDisabled, onStartupUpdateCheckDisabledChange)
            Routes.APPEARANCE_SETTINGS -> SettingsGuideHost(SettingsGuides.APPEARANCE) { AppearanceSettingsScreen(onBack, "外观设置", { onNavigate(Routes.DAY_NIGHT_MODE) }, { onNavigate(Routes.THEME_COLOR_SETTINGS) }, { onNavigate(Routes.HOME_COMPONENT_OPACITY) }, { onNavigate(Routes.HOME_SENTENCE_SETTINGS) }, { onNavigate(Routes.NOTIFICATION_SETTINGS) }, { onNavigate(Routes.CUSTOM_BACKGROUND_SETTINGS) }) }
            Routes.DAY_NIGHT_MODE -> DayNightModeScreen(onBack, "日夜模式", onThemeModeChanged)
            Routes.THEME_COLOR_SETTINGS -> ThemeColorSettingsScreen(onBack, "主题色配置", onThemeColorStyleChanged)
            Routes.HOME_COMPONENT_OPACITY -> HomeComponentOpacityScreen(onBack, "首页透明度")
            Routes.HOME_SENTENCE_SETTINGS -> HomeSentenceSettingsScreen(onBack, "首页句子")
            Routes.NOTIFICATION_SETTINGS -> NotificationSettingsScreen(onBack, "通知设置")
            Routes.CUSTOM_BACKGROUND_SETTINGS -> CustomBackgroundSettingsScreen(onBack, "软件背景", onCustomBackgroundChanged)
            Routes.MIRROR_TEMPLATES -> MirrorTemplateScreen(
                onBack = onBack,
                onNavigateToFormatGuide = { onNavigate(Routes.MIRROR_FORMAT_GUIDE) }
            )
            Routes.MIRROR_FORMAT_GUIDE -> MirrorFormatGuideScreen(onBack)
            Routes.SPONSOR -> SponsorScreen(onBack, "赞助")
            Routes.SPONSOR_LIST -> SponsorListScreen(onBack, "赞助者名单")
            Routes.CO_BUILDER_LIST -> CoBuilderListScreen(onBack, "共建者名单")
            Routes.APP_TRAFFIC_STATS -> AppTrafficStatsScreen(onBack)
            else -> SettingsScreen(onBack, onNavigate)
        }
    }

    companion object {
        const val EXTRA_ROUTE = "settings_route"
        const val EXTRA_RUNTIME_DNS_CHANGED = "settings_runtime_dns_changed"
        const val EXTRA_HIDE_FROM_RECENTS = "settings_hide_from_recents"
        const val EXTRA_THEME_CHANGED = "settings_theme_changed"
        const val EXTRA_BACKGROUND_CHANGED = "settings_background_changed"
        const val EXTRA_OUTBOUND_PROXY_APP_SELECTED = "settings_outbound_proxy_app_selected"
        const val EXTRA_OUTBOUND_PROXY_APP_PACKAGE = "settings_outbound_proxy_app_package"

        fun createIntent(
            context: android.content.Context,
            route: String,
            ruleScope: RuleScope? = null,
            ruleKind: ManagedRuleKind? = null,
            title: String? = null
        ): Intent = Intent(context, SettingsRouteActivity::class.java)
            .putExtra(EXTRA_ROUTE, route)
            .apply {
                ruleScope?.let { putExtra(EXTRA_RULE_SCOPE, it.name) }
                ruleKind?.let { putExtra(EXTRA_RULE_KIND, it.name) }
                title?.let { putExtra(EXTRA_TITLE, it) }
            }

        const val EXTRA_RULE_SCOPE = "settings_rule_scope"
        const val EXTRA_RULE_KIND = "settings_rule_kind"
        const val EXTRA_TITLE = "settings_title"
    }
}

private val DnsResolutionMode.route: String
    get() = when (this) {
        DnsResolutionMode.SINGLE -> Routes.RESOLUTION_SINGLE
        DnsResolutionMode.SMART_PREDICTION -> Routes.RESOLUTION_SMART
        DnsResolutionMode.PARALLEL_RACE -> Routes.RESOLUTION_PARALLEL
        DnsResolutionMode.PRIMARY_BACKUP -> Routes.RESOLUTION_BACKUP
    }
