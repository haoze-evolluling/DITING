package com.haoze.diting

import com.haoze.diting.ui.settings.AiProviderManageScreen
import com.haoze.diting.ui.settings.AppearanceSettingsStore

import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.ui.showToast
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
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
import com.haoze.diting.data.RequestSource
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.dnsmode.DnsMainActivity
import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.express.ui.*
import com.haoze.diting.notification.VpnMonitorManager
import com.haoze.diting.ui.*
import com.haoze.diting.ui.batch.BatchAddRulesScreen
import com.haoze.diting.ui.batch.BatchRuleTarget
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeSelectionScreen
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.ui.traffic.AppTrafficStatsScreen
import com.haoze.diting.ui.theme.ThemeColorStyle
import com.haoze.diting.update.AppUpdateHost
import com.haoze.diting.update.AppUpdateUiState
import com.haoze.diting.vpn.DnsVpnService
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
    private val requestedRuleDataset: RuleDataset
        get() = intent.getStringExtra(EXTRA_RULE_DATASET)?.let { value ->
            runCatching { RuleDataset.valueOf(value) }.getOrNull()
        } ?: RuleDataset.NORMAL
    private val requestedRequestSource: RequestSource?
        get() = intent.getStringExtra(EXTRA_REQUEST_SOURCE)?.let { value ->
            runCatching { RequestSource.valueOf(value) }.getOrNull()
        }
    private val requestedTitle: String?
        get() = intent.getStringExtra(EXTRA_TITLE)
    private val requestedBatchRuleTarget: BatchRuleTarget?
        get() = intent.getStringExtra(EXTRA_BATCH_RULE_TARGET)?.let { value ->
            runCatching { BatchRuleTarget.valueOf(value) }.getOrNull()
        }

    private var resultData = Intent()
    private var languageModeAtCreate = AppLanguageMode.SYSTEM
    private var childLaunchInProgress = false
    private var routeRefreshVersion by mutableStateOf(0)
    private var outboundProxyAppSelectionResult by mutableStateOf<Pair<Boolean, String?>?>(null)
    private val appUpdateHost = AppUpdateHost(this)

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
            var themeMode by remember(routeRefreshVersion) { mutableStateOf(AppearanceSettingsStore.getAppThemeMode(this)) }
            var colorStyle by remember(routeRefreshVersion) { mutableStateOf(AppearanceSettingsStore.getThemeColorStyle(this)) }
            var backgroundEnabled by remember(routeRefreshVersion) { mutableStateOf(AppearanceSettingsStore.isCustomBackgroundEnabled(this)) }
            var backgroundUri by remember(routeRefreshVersion) { mutableStateOf(AppearanceSettingsStore.getCustomBackgroundUri(this)) }

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
                    ruleDataset = requestedRuleDataset,
                    requestedTitle = requestedTitle,
                    outboundProxyAppSelectionResult = outboundProxyAppSelectionResult,
                    onBack = ::finishSettings,
                    onNavigate = ::openRoute,
                    onNavigateWithSource = ::openRoute,
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
                        com.haoze.diting.ui.background.CustomBackgroundManager.applyWindowBackground(this@SettingsRouteActivity)
                        recordThemeChanged()
                    },
                    onThemeColorStyleChanged = { style ->
                        colorStyle = style
                        recordThemeChanged()
                    },
                    onCustomBackgroundChanged = {
                        backgroundEnabled = AppearanceSettingsStore.isCustomBackgroundEnabled(this@SettingsRouteActivity)
                        backgroundUri = AppearanceSettingsStore.getCustomBackgroundUri(this@SettingsRouteActivity)
                        com.haoze.diting.ui.background.CustomBackgroundManager.applyWindowBackground(this@SettingsRouteActivity)
                        recordBackgroundChanged()
                    },
                    onExitApp = ::finishAndRemoveTask,
                    appUpdateState = appUpdateHost.state,
                    onCheckForAppUpdate = { appUpdateHost.checkForUpdate(manual = true) },
                    onDownloadAppUpdate = { appUpdateHost.downloadUpdate() },
                    onJoinQqGroup = ::joinQqGroup,
                    startupUpdateCheckDisabled = SystemSettingsStore.isStartupUpdateCheckDisabled(this),
                    onStartupUpdateCheckDisabledChange = {
                        SystemSettingsStore.setStartupUpdateCheckDisabled(this, it)
                    }
                )
                if (route == Routes.APP_UPDATE) {
                    appUpdateHost.state.availableUpdate?.let { update ->
                        if (appUpdateHost.dismissedVersion != update.version) {
                            AppUpdateDialog(
                                update = update,
                                downloadState = appUpdateHost.state.downloadState,
                                onDismiss = { appUpdateHost.dismissedVersion = update.version },
                                onDownload = { appUpdateHost.downloadUpdate() },
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
        com.haoze.diting.express.ExpressModeLauncher.updateFloatingLogAppState(this, true)
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
        com.haoze.diting.express.ExpressModeLauncher.updateFloatingLogAppState(this, false)
        super.onStop()
    }

    private fun openRoute(
        nextRoute: String,
        requestSource: RequestSource? = null,
        ruleScope: RuleScope? = requestedRuleScope,
        batchTarget: BatchRuleTarget? = null
    ) {
        if (childLaunchInProgress || (nextRoute == route && requestSource == requestedRequestSource)) return
        childLaunchInProgress = true
        childActivityLauncher.launch(
            createIntent(
                this,
                nextRoute,
                ruleScope = ruleScope,
                requestSource = requestSource,
                dataset = requestedRuleDataset,
                batchTarget = batchTarget
            )
        )
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
        if (data.getBooleanExtra(EXTRA_BOTTOM_BAR_CHANGED, false)) recordBottomBarChanged()
        if (data.getBooleanExtra(EXTRA_WORK_MODE_CHANGED, false)) recordWorkModeChanged()
        if (data.hasExtra(EXTRA_HIDE_FROM_RECENTS)) {
            recordHideFromRecentsChanged(data.getBooleanExtra(EXTRA_HIDE_FROM_RECENTS, false))
        }
        if (data.getBooleanExtra(EXTRA_OUTBOUND_PROXY_APP_SELECTED, false)) {
            outboundProxyAppSelectionResult = true to data.getStringExtra(EXTRA_OUTBOUND_PROXY_APP_PACKAGE)
        }
        routeRefreshVersion++
    }

    private fun recordWorkModeChanged() {
        resultData.putExtra(EXTRA_WORK_MODE_CHANGED, true)
        setResult(RESULT_OK, resultData)
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

    private fun recordBottomBarChanged() {
        resultData.putExtra(EXTRA_BOTTOM_BAR_CHANGED, true)
        setResult(RESULT_OK, resultData)
    }

    private fun recordHideFromRecentsChanged(hide: Boolean) {
        resultData.putExtra(EXTRA_HIDE_FROM_RECENTS, hide)
        setResult(RESULT_OK, resultData)
    }

    private fun applyRecentsPrivacy(hideFromRecents: Boolean) {
        RecentsPrivacyController.apply(this, hideFromRecents)
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
            this.showToast("未检测到 QQ，请搜索群号 1090225658 加入。", Toast.LENGTH_LONG)
        }
    }

    @androidx.compose.runtime.Composable
    private fun SettingsRouteContent(
        route: String,
        ruleScope: RuleScope?,
        ruleKind: ManagedRuleKind?,
        ruleDataset: RuleDataset,
        requestedTitle: String?,
        outboundProxyAppSelectionResult: Pair<Boolean, String?>?,
        onBack: () -> Unit,
        onNavigate: (String) -> Unit,
        onNavigateWithSource: (String, RequestSource?) -> Unit = { r, s -> onNavigate(r) },
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
        val isExpress = WorkModeStore.getAppWorkMode(this) == AppWorkMode.EXPRESS
        when (route) {
            Routes.SETTINGS -> SettingsScreen(onBack, onNavigate)
            Routes.LANGUAGE_SETTINGS -> LanguageSettingsScreen(::finishSettings, ::applyLanguage)
            Routes.RULE_MANAGEMENT,
            Routes.RULE_CONTROL,
            Routes.DOMAIN_RULE_MANAGEMENT,
            Routes.ADDRESS_RULE_MANAGEMENT -> SettingsGuideHost(SettingsGuides.DOMAIN_RULES) {
                if (isExpress) {
                    ExpressRuleControlScreen(
                        onBack = onBack,
                        onNavigateToBlockResponseSettings = { onNavigate(Routes.BLOCK_RESPONSE_SETTINGS) },
                        onNavigateToSubscription = { onNavigate(Routes.SUBSCRIPTION_MANAGEMENT) },
                        onNavigateToAutoUpdateInterval = { onNavigate(Routes.SUBSCRIPTION_AUTO_UPDATE_INTERVAL) },
                        onNavigateToMirrorTemplates = { onNavigate(Routes.MIRROR_TEMPLATES) },
                        dataset = ruleDataset,
                        onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged
                    )
                } else {
                    RuleControlScreen(
                        onBack = onBack,
                        onNavigateToBlockResponseSettings = { onNavigate(Routes.BLOCK_RESPONSE_SETTINGS) },
                        onNavigateToSubscription = { onNavigate(Routes.SUBSCRIPTION_MANAGEMENT) },
                        onNavigateToAutoUpdateInterval = { onNavigate(Routes.SUBSCRIPTION_AUTO_UPDATE_INTERVAL) },
                        onNavigateToMirrorTemplates = { onNavigate(Routes.MIRROR_TEMPLATES) },
                        onNavigateToHttpInspection = { onNavigate(Routes.HTTP_INSPECTION_SETTINGS) },
                        dataset = ruleDataset,
                        onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged
                    )
                }
            }
            Routes.APP_RULE_MANAGEMENT -> SettingsGuideHost(SettingsGuides.APP_ALLOWLIST) { AppRuleManagementScreen(onBack) }
            Routes.WHITELIST_MANAGEMENT -> WhitelistScreen(
                onBack,
                onRuntimeDnsSettingsChanged,
                onNavigateToBatchAdd = { openRoute(Routes.BATCH_ADD_RULES, batchTarget = BatchRuleTarget.WHITELIST) },
                dataset = ruleDataset
            )
            Routes.BLACKLIST_MANAGEMENT -> BlacklistScreen(
                onBack,
                onRuntimeDnsSettingsChanged,
                onNavigateToBatchAdd = { openRoute(Routes.BATCH_ADD_RULES, batchTarget = BatchRuleTarget.BLACKLIST) },
                dataset = ruleDataset
            )
            Routes.REWRITELIST_MANAGEMENT -> RewriteListScreen(
                onBack,
                onRuntimeDnsSettingsChanged,
                onNavigateToBatchAdd = { openRoute(Routes.BATCH_ADD_RULES, batchTarget = BatchRuleTarget.REWRITE) },
                dataset = ruleDataset
            )
            Routes.BATCH_ADD_RULES -> BatchAddRulesScreen(
                target = requestedBatchRuleTarget ?: BatchRuleTarget.BLACKLIST,
                dataset = ruleDataset,
                onBack = onBack,
                onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged
            )
            Routes.RULE_LIST -> RuleListScreen(onBack, ruleKind = ruleKind ?: ManagedRuleKind.BLOCK, ruleScope = ruleScope ?: RuleScope.DNS, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged, dataset = ruleDataset)
            Routes.ALLOW_RULE_LIST -> RuleListScreen(onBack, ruleKind = ruleKind ?: ManagedRuleKind.ALLOW, ruleScope = ruleScope ?: RuleScope.DNS, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged, dataset = ruleDataset)
            Routes.REWRITE_RULE_LIST -> RewriteListScreen(onBack, onRuntimeDnsSettingsChanged, dataset = ruleDataset)
            Routes.ADDRESS_RULE_LIST -> RuleListScreen(onBack, ruleKind = ManagedRuleKind.URL_BLOCK, ruleScope = RuleScope.DNS, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged, dataset = ruleDataset)
            Routes.ADDRESS_ALLOW_RULE_LIST -> RuleListScreen(onBack, ruleKind = ManagedRuleKind.URL_ALLOW, ruleScope = RuleScope.DNS, onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged, dataset = ruleDataset)
            Routes.EXCLUDED_APPS -> SettingsGuideHost(SettingsGuides.EXCLUDED_APPS) { ExcludedAppsScreen(onBack) }
            Routes.OUTBOUND_PROXY_SETTINGS -> OutboundProxySettingsScreen(
                onBack = onBack,
                onSelectApp = { onNavigate(Routes.OUTBOUND_PROXY_APP_SELECTION) },
                selectedAppOverride = outboundProxyAppSelectionResult
            )
            Routes.OUTBOUND_PROXY_APP_SELECTION -> OutboundProxyAppsScreen(onBack, ::finishOutboundProxyAppSelection)
            Routes.BLOCK_RESPONSE_SETTINGS -> BlockResponseSettingsScreen(onBack, onRuntimeDnsSettingsChanged, dataset = ruleDataset)
            Routes.AGENT_API_SETTINGS -> AgentApiSettingsScreen(onBack, onNavigate = onNavigate)
            Routes.AI_PROVIDER_MANAGEMENT,
            Routes.AGENT_API_CREDENTIALS,
            Routes.AGENT_API_PRESETS -> AiProviderManageScreen(onBack)
            Routes.AGENT_API_PARAMS -> AgentApiParamsScreen(onBack)
            Routes.DATA_CLEANUP -> SettingsGuideHost(SettingsGuides.DATA_CLEANUP) {
                val cleanupTitle = requestedTitle ?: ScreenDestinations.dataCleanup.title
                if (isExpress) {
                    ExpressDataCleanupScreen(onBack, cleanupTitle, onRuntimeDnsSettingsChanged, onExitApp)
                } else {
                    DataCleanupScreen(onBack, cleanupTitle, onRuntimeDnsSettingsChanged, onExitApp)
                }
            }
            Routes.CONFIG_TRANSFER,
            Routes.CONFIG_IMPORT_EXPORT,
            Routes.RULE_EXPORT,
            Routes.RULE_IMPORT -> SettingsGuideHost(SettingsGuides.CONFIG_TRANSFER) {
                if (isExpress) ExpressConfigTransferScreen(onBack, "备份与迁移") else ConfigTransferScreen(onBack, "备份与迁移")
            }
            Routes.PROVIDER_MANAGEMENT -> SettingsGuideHost(SettingsGuides.PROVIDER_MANAGEMENT) { ProviderManagementScreen(onBack, "服务商管理") }
            Routes.HOME_PROVIDER_VISIBILITY -> SettingsGuideHost(SettingsGuides.SERVICE_DISPLAY) { HomeProviderVisibilityScreen(onBack, "服务显示") }
            Routes.BLOCKED_APPS,
            Routes.BLOCKED_APPS_SELECTION -> SettingsGuideHost(SettingsGuides.BLOCKED_APPS) { BlockedAppsScreen(onBack) }
            Routes.APP_ALLOWLIST,
            Routes.APP_ALLOWLIST_SELECTION -> SettingsGuideHost(SettingsGuides.APP_ALLOWLIST) { AppRuleManagementScreen(onBack) }
            Routes.BOOTSTRAP_SETTINGS -> SettingsGuideHost(SettingsGuides.BOOTSTRAP) { BootstrapSettingsScreen(onBack, "Bootstrap 设置") }
            Routes.NETWORK_TOOLS -> SettingsGuideHost(SettingsGuides.NETWORK_TOOLS) { NetworkToolsScreen(onBack, "网络诊断") }
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
            Routes.CACHE_SETTINGS -> SettingsGuideHost(SettingsGuides.CACHE) { CacheSettingsScreen(onBack, ScreenDestinations.cacheSettings.title, onRuntimeDnsSettingsChanged, dataset = requestedRuleDataset) }
            Routes.LOG_RETENTION_SETTINGS -> SettingsGuideHost(SettingsGuides.LOG_MODE) { LogRetentionSettingsScreen(onBack, onRuntimeDnsSettingsChanged, ScreenDestinations.logRetentionSettings.title) }
            Routes.FOREGROUND_BACKGROUND_SETTINGS -> SettingsGuideHost(SettingsGuides.FOREGROUND_BACKGROUND) {
                if (isExpress) {
                    ExpressForegroundBackgroundSettingsScreen(onBack, ScreenDestinations.foregroundBackgroundSettings.title, onHideFromRecentsChanged)
                } else {
                    ForegroundBackgroundSettingsScreen(onBack, ScreenDestinations.foregroundBackgroundSettings.title, onHideFromRecentsChanged)
                }
            }
            Routes.HTTP_INSPECTION_SETTINGS -> SettingsGuideHost(SettingsGuides.HTTP_INSPECTION) { HttpInspectionSettingsScreen(onBack, { onNavigateWithSource(Routes.DNS_LOGS, RequestSource.HTTPS) }, { onNavigate(Routes.HTTP_INSPECTION_APPS) }, { onNavigate(Routes.CA_CERTIFICATE_SETTINGS) }) }
            Routes.CA_CERTIFICATE_GUIDE -> CaCertificateGuideScreen(onBack)
            Routes.CA_CERTIFICATE_SETTINGS -> CaCertificateSettingsScreen(onBack, { onNavigate(Routes.CA_CERTIFICATE_GUIDE) })
            Routes.HTTP_INSPECTION_APPS -> HttpInspectionAppsScreen(onBack)
            Routes.DNS_LOGS,
            Routes.HTTP_REQUEST_LOGS -> {
                if (isExpress) {
                    com.haoze.diting.express.ui.ExpressRequestLogScreen(
                        onBack = onBack,
                        onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged
                    )
                } else {
                    RequestLogScreen(
                        onBack = onBack,
                        initialSource = requestedRequestSource ?: if (route == Routes.HTTP_REQUEST_LOGS) RequestSource.HTTPS else RequestSource.ALL,
                        onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged
                    )
                }
            }
            Routes.SUBSCRIPTION_MANAGEMENT -> SubscriptionScreen(
                onBack = onBack,
                ruleScope = ruleScope ?: RuleScope.DNS,
                onNavigateToAddSubscription = { onNavigate(Routes.ADD_SUBSCRIPTION) },
                onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged,
                dataset = ruleDataset
            )
            Routes.SUBSCRIPTION_AUTO_UPDATE_INTERVAL -> SubscriptionAutoUpdateIntervalScreen(onBack, dataset = ruleDataset)
            Routes.ADD_SUBSCRIPTION -> AddSubscriptionScreen(
                onBack = onBack,
                ruleScope = ruleScope ?: RuleScope.DNS,
                onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged,
                dataset = ruleDataset
            )
            Routes.ABOUT -> AboutScreen(onBack, "应用信息")
            Routes.APP_UPDATE -> AppUpdateScreen(appUpdateState, onBack, onCheckForAppUpdate, onDownloadAppUpdate, onJoinQqGroup, startupUpdateCheckDisabled, onStartupUpdateCheckDisabledChange)
            Routes.APPEARANCE_SETTINGS -> SettingsGuideHost(SettingsGuides.APPEARANCE) {
                AppearanceSettingsScreen(
                    onBack = onBack,
                    title = "外观设置",
                    onNavigateToDayNightMode = { onNavigate(Routes.DAY_NIGHT_MODE) },
                    onNavigateToThemeColorSettings = { onNavigate(Routes.THEME_COLOR_SETTINGS) },
                    onNavigateToHomeComponentOpacity = { onNavigate(Routes.HOME_COMPONENT_OPACITY) },
                    onNavigateToHomeSentence = { onNavigate(Routes.HOME_SENTENCE_SETTINGS) },
                    onNavigateToNotificationSettings = { onNavigate(Routes.NOTIFICATION_SETTINGS) },
                    onNavigateToCustomBackground = { onNavigate(Routes.CUSTOM_BACKGROUND_SETTINGS) },
                    onNavigateToBottomBarCustomization = { onNavigate(Routes.BOTTOM_BAR_CUSTOMIZATION) }
                )
            }
            Routes.BOTTOM_BAR_CUSTOMIZATION -> if (isExpress) {
                ExpressBottomBarCustomizationScreen(onBack, ::recordBottomBarChanged)
            } else {
                BottomBarCustomizationScreen(onBack, ::recordBottomBarChanged)
            }
            Routes.DAY_NIGHT_MODE -> DayNightModeScreen(onBack, "日夜模式", onThemeModeChanged)
            Routes.THEME_COLOR_SETTINGS -> ThemeColorSettingsScreen(onBack, "主题色配置", onThemeColorStyleChanged)
            Routes.HOME_COMPONENT_OPACITY -> HomeComponentOpacityScreen(onBack, "首页透明度")
            Routes.HOME_SENTENCE_SETTINGS -> HomeSentenceSettingsScreen(onBack, "首页句子")
            Routes.NOTIFICATION_SETTINGS -> if (isExpress) ExpressNotificationSettingsScreen(onBack, "通知设置") else NotificationSettingsScreen(onBack, "通知设置")
            Routes.CUSTOM_BACKGROUND_SETTINGS -> CustomBackgroundSettingsScreen(onBack, "软件背景", onCustomBackgroundChanged)
            Routes.MIRROR_TEMPLATES -> MirrorTemplateScreen(
                onBack = onBack,
                onNavigateToFormatGuide = { onNavigate(Routes.MIRROR_FORMAT_GUIDE) },
                dataset = ruleDataset
            )
            Routes.MIRROR_FORMAT_GUIDE -> MirrorFormatGuideScreen(onBack)
            Routes.SPONSOR -> SponsorScreen(onBack, "赞助")
            Routes.SPONSOR_LIST -> SponsorListScreen(onBack, "赞助者名单")
            Routes.CO_BUILDER_LIST -> CoBuilderListScreen(onBack, "共建者名单")
            Routes.APP_TRAFFIC_STATS -> AppTrafficStatsScreen(onBack)
            Routes.OPTIONAL_FEATURES,
            Routes.HIDDEN_FEATURES -> if (isExpress) ExpressHiddenFeaturesScreen(onBack) else HiddenFeaturesScreen(onBack)
            Routes.WORK_MODE_SELECTION -> WorkModeSelectionScreen(
                isFirstLaunch = false,
                currentMode = WorkModeStore.getAppWorkMode(this),
                onBack = onBack,
                onModeSelected = { selectedMode ->
                    val previousMode = WorkModeStore.getAppWorkMode(this)
                    WorkModeStore.setAppWorkMode(this, selectedMode)
                    recordWorkModeChanged()
                    if (selectedMode == AppWorkMode.EXPRESS) {
                        com.haoze.diting.express.ExpressModeLauncher.handleRouteModeSelected(this, previousMode) { onBack() }
                    } else if (selectedMode == AppWorkMode.DNS) {
                        if (previousMode == AppWorkMode.EXPRESS) {
                            com.haoze.diting.express.ExpressModeLauncher.stopExpress(this)
                        }
                        try {
                            startService(DnsVpnService.stopIntent(this))
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to stop VPN service when switching to DNS mode", e)
                        }
                        // Keep the persistent monitor from outliving the VPN.
                        VpnMonitorManager.stop(this)
                        val intent = DnsMainActivity.createIntent(this).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                        }
                        startActivity(intent)
                        finish()
                    } else if (previousMode == AppWorkMode.DNS) {
                        DnsModeManager.stopService(this)
                        val intent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                        }
                        startActivity(intent)
                        finish()
                    } else {
                        if (previousMode == AppWorkMode.EXPRESS) {
                            com.haoze.diting.express.ExpressModeLauncher.stopExpress(this)
                        }
                        onBack()
                    }
                }
            )
            else -> SettingsScreen(onBack, onNavigate)
        }
    }

    companion object {
        private const val TAG = "SettingsRoute"
        const val EXTRA_ROUTE = "settings_route"
        const val EXTRA_REQUEST_SOURCE = "settings_request_source"
        const val EXTRA_RUNTIME_DNS_CHANGED = "settings_runtime_dns_changed"
        const val EXTRA_WORK_MODE_CHANGED = "settings_work_mode_changed"
        const val EXTRA_HIDE_FROM_RECENTS = "settings_hide_from_recents"
        const val EXTRA_THEME_CHANGED = "settings_theme_changed"
        const val EXTRA_BACKGROUND_CHANGED = "settings_background_changed"
        const val EXTRA_BOTTOM_BAR_CHANGED = "settings_bottom_bar_changed"
        const val EXTRA_OUTBOUND_PROXY_APP_SELECTED = "settings_outbound_proxy_app_selected"
        const val EXTRA_OUTBOUND_PROXY_APP_PACKAGE = "settings_outbound_proxy_app_package"
        const val EXTRA_BATCH_RULE_TARGET = "settings_batch_rule_target"

        fun createIntent(
            context: android.content.Context,
            route: String,
            ruleScope: RuleScope? = null,
            ruleKind: ManagedRuleKind? = null,
            title: String? = null,
            requestSource: RequestSource? = null,
            dataset: RuleDataset? = null,
            batchTarget: BatchRuleTarget? = null
        ): Intent = Intent(context, SettingsRouteActivity::class.java)
            .putExtra(EXTRA_ROUTE, route)
            .apply {
                ruleScope?.let { putExtra(EXTRA_RULE_SCOPE, it.name) }
                ruleKind?.let { putExtra(EXTRA_RULE_KIND, it.name) }
                title?.let { putExtra(EXTRA_TITLE, it) }
                requestSource?.let { putExtra(EXTRA_REQUEST_SOURCE, it.name) }
                dataset?.let { putExtra(EXTRA_RULE_DATASET, it.name) }
                batchTarget?.let { putExtra(EXTRA_BATCH_RULE_TARGET, it.name) }
            }

        const val EXTRA_RULE_SCOPE = "settings_rule_scope"
        const val EXTRA_RULE_KIND = "settings_rule_kind"
        const val EXTRA_RULE_DATASET = "settings_rule_dataset"
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
