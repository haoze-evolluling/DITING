package com.haoze.diting

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.ui.showToast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.AppConfirmDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.AppSettings
import com.haoze.diting.ui.AppLanguageManager
import com.haoze.diting.ui.AppLanguageMode
import com.haoze.diting.ui.AppThemeMode
import com.haoze.diting.ui.AppThemeSurface
import com.haoze.diting.ui.MainScreen
import com.haoze.diting.ui.MainViewModel
import com.haoze.diting.ui.PermissionDisclosureSettings
import com.haoze.diting.ui.RecentsPrivacyController
import com.haoze.diting.ui.Routes
import com.haoze.diting.notification.AppNotificationChannels
import com.haoze.diting.notification.NotificationPermissionHelper
import com.haoze.diting.notification.VpnMonitorManager
import com.haoze.diting.ui.AppUpdateDialog
import com.haoze.diting.dnsmode.DnsMainActivity
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeSelectionScreen
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.update.AppUpdateHost
import com.haoze.diting.ui.localizedText
import com.haoze.diting.vpn.DnsVpnService
import com.haoze.diting.vpn.SubscriptionAutoUpdateScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

import com.haoze.diting.ui.InitialAgreementDialog
import com.haoze.diting.ui.PermissionDisclosure
import com.haoze.diting.ui.PermissionDisclosureDialog
import com.haoze.diting.ui.mode.disableWindowTransitions

private const val DATABASE_WARMUP_DELAY_MS = 500L

class MainActivity : AppLocalizedActivity() {
    private var languageModeAtCreate = AppLanguageMode.SYSTEM

    private var permissionDisclosure by mutableStateOf<PermissionDisclosure?>(null)
    private val appUpdateHost = AppUpdateHost(this)
    private var acceptedExperienceInitialized = false
    private var settingsLaunchInProgress = false

    private val vpnPrepareLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            PermissionDisclosureSettings.updateVpnGrant(this, true)
            startVpnService()
        } else {
            PermissionDisclosureSettings.updateVpnGrant(this, false)
            VpnMonitorManager.sync(this)
            mainViewModel.refreshStatus()
        }
    }

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {
        prepareVpn()
    }

    private val mainViewModel: MainViewModel by viewModels()

    private val settingsLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        settingsLaunchInProgress = false
        if (result.resultCode != RESULT_OK) return@registerForActivityResult
        result.data?.let { data ->
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_RUNTIME_DNS_CHANGED, false)) {
                refreshRuntimeConfigIfRunning()
            }
            if (data.hasExtra(SettingsRouteActivity.EXTRA_HIDE_FROM_RECENTS)) {
                applyRecentsPrivacy(data.getBooleanExtra(SettingsRouteActivity.EXTRA_HIDE_FROM_RECENTS, false))
            }
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_THEME_CHANGED, false)) {
                // The setting screen persists the value before returning.
                mainThemeRefreshRequested = true
            }
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_BACKGROUND_CHANGED, false)) {
                backgroundRefreshRequested = true
            }
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_BOTTOM_BAR_CHANGED, false)) {
                bottomBarRefreshRequested = true
            }
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_WORK_MODE_CHANGED, false)) {
                workModeRefreshRequested = true
            }
        }
    }

    private var mainThemeRefreshRequested by mutableStateOf(false)
    private var backgroundRefreshRequested by mutableStateOf(false)
    private var bottomBarRefreshRequested by mutableStateOf(false)
    private var workModeRefreshRequested by mutableStateOf(false)

    private fun launchSettings(route: String, dataset: RuleDataset? = null) {
        if (settingsLaunchInProgress) return
        settingsLaunchInProgress = true
        settingsLauncher.launch(SettingsRouteActivity.createIntent(this, route, dataset = dataset))
    }

    private fun launchLogs(dataset: RuleDataset? = null) {
        startActivity(LogRouteActivity.createIntent(this, Routes.LOG_DASHBOARD, dataset = dataset))
    }

    private fun launchLogRoute(route: String, dataset: RuleDataset? = null) {
        startActivity(LogRouteActivity.createIntent(this, route, dataset = dataset))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        languageModeAtCreate = AppLanguageManager.getMode(this)
        enableEdgeToEdge()
        AppSettings.performStartupSelfCheck(this)
        applyRecentsPrivacySetting()
        if (com.haoze.diting.crash.CrashLogManager.consumePendingAutoExportNotice(this)) {
            showToast("软件连续异常退出，崩溃日志已自动备份至系统“下载”目录", Toast.LENGTH_LONG)
        }
        setContent {
            var initialAgreementAccepted by remember {
                mutableStateOf(SystemSettingsStore.isInitialAgreementAccepted(this))
            }
            var currentWorkMode by remember {
                mutableStateOf(WorkModeStore.getAppWorkMode(this))
            }
            var hasSelectedWorkMode by remember {
                mutableStateOf(WorkModeStore.hasSelectedWorkMode(this))
            }
            var isSelectingWorkMode by remember {
                mutableStateOf(false)
            }
            var resetToHomeTrigger by remember {
                mutableLongStateOf(0L)
            }
            var themeMode by remember { mutableStateOf(AppearanceSettingsStore.getAppThemeMode(this)) }
            var colorStyle by remember { mutableStateOf(AppearanceSettingsStore.getThemeColorStyle(this)) }
            var backgroundEnabled by remember { mutableStateOf(AppearanceSettingsStore.isCustomBackgroundEnabled(this)) }
            var backgroundUri by remember { mutableStateOf(AppearanceSettingsStore.getCustomBackgroundUri(this)) }

            fun switchWorkMode(selectedMode: AppWorkMode) {
                val previousMode = currentWorkMode
                WorkModeStore.setAppWorkMode(this@MainActivity, selectedMode)
                WorkModeStore.setWorkModeSelected(this@MainActivity, true)
                hasSelectedWorkMode = true
                resetToHomeTrigger = System.currentTimeMillis()

                if (previousMode == AppWorkMode.DNS && selectedMode != AppWorkMode.DNS) {
                    com.haoze.diting.dnsmode.backend.DnsModeManager.stopService(this@MainActivity)
                } else if (previousMode == AppWorkMode.EXPRESS && selectedMode != AppWorkMode.EXPRESS) {
                    com.haoze.diting.express.ExpressModeLauncher.stopExpress(this@MainActivity)
                }

                if (selectedMode == AppWorkMode.DNS) {
                    stopVpnService()
                    VpnMonitorManager.stop(this@MainActivity)
                    currentWorkMode = selectedMode
                } else if (selectedMode == AppWorkMode.EXPRESS) {
                    com.haoze.diting.express.ExpressModeLauncher.handleModeSelected(this@MainActivity, selectedMode) {
                        currentWorkMode = selectedMode
                        initializeAcceptedExperience()
                    }
                } else {
                    currentWorkMode = selectedMode
                    initializeAcceptedExperience()
                }
            }

            LaunchedEffect(mainThemeRefreshRequested, backgroundRefreshRequested, workModeRefreshRequested) {
                if (mainThemeRefreshRequested) {
                    themeMode = AppearanceSettingsStore.getAppThemeMode(this@MainActivity)
                    colorStyle = AppearanceSettingsStore.getThemeColorStyle(this@MainActivity)
                    com.haoze.diting.ui.background.CustomBackgroundManager.applyWindowBackground(this@MainActivity)
                    mainThemeRefreshRequested = false
                }
                if (backgroundRefreshRequested) {
                    backgroundEnabled = AppearanceSettingsStore.isCustomBackgroundEnabled(this@MainActivity)
                    backgroundUri = AppearanceSettingsStore.getCustomBackgroundUri(this@MainActivity)
                    com.haoze.diting.ui.background.CustomBackgroundManager.applyWindowBackground(this@MainActivity)
                    backgroundRefreshRequested = false
                }
                if (workModeRefreshRequested) {
                    val targetMode = WorkModeStore.getAppWorkMode(this@MainActivity)
                    switchWorkMode(targetMode)
                    workModeRefreshRequested = false
                }
            }
            AppThemeSurface(
                themeMode = themeMode,
                colorStyle = colorStyle,
                backgroundEnabled = backgroundEnabled,
                backgroundUri = backgroundUri,
                modifier = Modifier.fillMaxSize()
            ) {
                        BackHandler(enabled = isSelectingWorkMode) {
                            isSelectingWorkMode = false
                        }

                        if (!initialAgreementAccepted) {
                            InitialAgreementDialog(
                                onAccept = {
                                    SystemSettingsStore.setInitialAgreementAccepted(this@MainActivity)
                                    initialAgreementAccepted = true
                                    if (WorkModeStore.hasSelectedWorkMode(this@MainActivity)) {
                                        initializeAcceptedExperience()
                                        if (WorkModeStore.getAppWorkMode(this@MainActivity) == AppWorkMode.EXPRESS) {
                                            com.haoze.diting.express.ExpressModeLauncher.switchToExpress(this@MainActivity, AppWorkMode.EXPRESS)
                                        }
                                    }
                                },
                                onDecline = ::declineInitialAgreement
                            )
                        } else {
                            Box(modifier = Modifier.fillMaxSize()) {
                                if (hasSelectedWorkMode) {
                                    when (currentWorkMode) {
                                        AppWorkMode.EXPRESS -> {
                                            com.haoze.diting.express.ui.ExpressMainScreen(
                                                onToggle = { isRunning -> onToggleVpn(isRunning) },
                                                onNavigateToSettings = { launchSettings(Routes.SETTINGS, RuleDataset.EXPRESS) },
                                                onNavigateToLogs = { launchLogs(RuleDataset.EXPRESS) },
                                                onNavigateToProviderManagement = { launchSettings(Routes.PROVIDER_MANAGEMENT, RuleDataset.EXPRESS) },
                                                onNavigateToBootstrapSettings = { launchSettings(Routes.BOOTSTRAP_SETTINGS, RuleDataset.EXPRESS) },
                                                onNavigateToHomeProviderVisibility = { launchSettings(Routes.HOME_PROVIDER_VISIBILITY, RuleDataset.EXPRESS) },
                                                onNavigateToRaceModeSettings = { launchSettings(Routes.RACE_MODE_PROVIDERS, RuleDataset.EXPRESS) },
                                                onNavigateToAppearanceSettings = { launchSettings(Routes.APPEARANCE_SETTINGS) },
                                                onNavigateToRuleControl = { launchSettings(Routes.RULE_CONTROL, RuleDataset.EXPRESS) },
                                                onNavigateToBlacklist = { launchSettings(Routes.BLACKLIST_MANAGEMENT, RuleDataset.EXPRESS) },
                                                onNavigateToWhitelist = { launchSettings(Routes.WHITELIST_MANAGEMENT, RuleDataset.EXPRESS) },
                                                onNavigateToLogRetentionSettings = { launchSettings(Routes.LOG_RETENTION_SETTINGS, RuleDataset.EXPRESS) },
                                                onNavigateToHomeProviderVisibilityFromFeatureHub = { launchSettings(Routes.HOME_PROVIDER_VISIBILITY, RuleDataset.EXPRESS) },
                                                onNavigateToAbout = { launchSettings(Routes.ABOUT) },
                                                onNavigateToSponsor = { launchSettings(Routes.SPONSOR) },
                                                onNavigateToSponsorList = { launchSettings(Routes.SPONSOR_LIST) },
                                                onNavigateToCoBuilderList = { launchSettings(Routes.CO_BUILDER_LIST) },
                                                onNavigateToAppUpdate = { launchSettings(Routes.APP_UPDATE) },
                                                onNavigateToDataManagement = { launchSettings(Routes.CONFIG_TRANSFER, RuleDataset.EXPRESS) },
                                                onNavigateToHiddenFeatures = { launchSettings(Routes.HIDDEN_FEATURES) },
                                                onNavigateToCacheSettings = { launchSettings(Routes.CACHE_SETTINGS, RuleDataset.EXPRESS) },
                                                onNavigateToDataCleanup = { launchSettings(Routes.DATA_CLEANUP, RuleDataset.EXPRESS) },
                                                onNavigateToLogRoute = { r -> launchLogRoute(r, RuleDataset.EXPRESS) },
                                                onNavigateToSettingsRoute = { r -> launchSettings(r, RuleDataset.EXPRESS) },
                                                onNavigateToModeSelection = { isSelectingWorkMode = true },
                                                resetToHomeTrigger = resetToHomeTrigger,
                                                bottomBarRefreshRequested = bottomBarRefreshRequested,
                                                onBottomBarRefreshConsumed = { bottomBarRefreshRequested = false },
                                                viewModel = mainViewModel
                                            )
                                        }
                                        AppWorkMode.DNS -> {
                                            com.haoze.diting.dnsmode.ui.DnsModeHost(
                                                onSelectMode = { isSelectingWorkMode = true },
                                                resetToHomeTrigger = resetToHomeTrigger,
                                                onSwitchToNormalMode = {
                                                    switchWorkMode(AppWorkMode.NORMAL)
                                                },
                                                modifier = Modifier.fillMaxSize()
                                            )
                                        }
                                        else -> {
                                            MainScreen(
                                                onToggle = { isRunning -> onToggleVpn(isRunning) },
                                                onNavigateToSettings = { launchSettings(Routes.SETTINGS) },
                                                onNavigateToLogs = ::launchLogs,
                                                onNavigateToProviderManagement = { launchSettings(Routes.PROVIDER_MANAGEMENT) },
                                                onNavigateToBootstrapSettings = { launchSettings(Routes.BOOTSTRAP_SETTINGS) },
                                                onNavigateToHomeProviderVisibility = { launchSettings(Routes.HOME_PROVIDER_VISIBILITY) },
                                                onNavigateToRaceModeSettings = { launchSettings(Routes.RACE_MODE_PROVIDERS) },
                                                onNavigateToBlockedApps = { launchSettings(Routes.BLOCKED_APPS) },
                                                onNavigateToAppAllowlist = { launchSettings(Routes.APP_ALLOWLIST) },
                                                onNavigateToExcludedApps = { launchSettings(Routes.EXCLUDED_APPS) },
                                                onNavigateToAppearanceSettings = { launchSettings(Routes.APPEARANCE_SETTINGS) },
                                                onNavigateToRuleControl = { launchSettings(Routes.RULE_CONTROL) },
                                                onNavigateToBlacklist = { launchSettings(Routes.BLACKLIST_MANAGEMENT) },
                                                onNavigateToWhitelist = { launchSettings(Routes.WHITELIST_MANAGEMENT) },
                                                onNavigateToRewriteList = { launchSettings(Routes.REWRITELIST_MANAGEMENT) },
                                                onNavigateToAppRules = { launchSettings(Routes.APP_RULE_MANAGEMENT) },
                                                onNavigateToHttpInspection = { launchSettings(Routes.HTTP_INSPECTION_SETTINGS) },
                                                onNavigateToLogRetentionSettings = { launchSettings(Routes.LOG_RETENTION_SETTINGS) },
                                                onNavigateToNetworkTools = { launchSettings(Routes.NETWORK_TOOLS) },
                                                onNavigateToHomeProviderVisibilityFromFeatureHub = { launchSettings(Routes.HOME_PROVIDER_VISIBILITY) },
                                                onNavigateToAbout = { launchSettings(Routes.ABOUT) },
                                                onNavigateToSponsor = { launchSettings(Routes.SPONSOR) },
                                                onNavigateToSponsorList = { launchSettings(Routes.SPONSOR_LIST) },
                                                onNavigateToCoBuilderList = { launchSettings(Routes.CO_BUILDER_LIST) },
                                                onNavigateToAppUpdate = { launchSettings(Routes.APP_UPDATE) },
                                                onNavigateToDataManagement = { launchSettings(Routes.CONFIG_TRANSFER) },
                                                onNavigateToTrafficStats = { launchSettings(Routes.APP_TRAFFIC_STATS) },
                                                onNavigateToHiddenFeatures = { launchSettings(Routes.HIDDEN_FEATURES) },
                                                onNavigateToCacheSettings = { launchSettings(Routes.CACHE_SETTINGS) },
                                                onNavigateToOutboundProxy = { launchSettings(Routes.OUTBOUND_PROXY_SETTINGS) },
                                                onNavigateToDataCleanup = { launchSettings(Routes.DATA_CLEANUP) },
                                                onNavigateToAgentApiSettings = { launchSettings(Routes.AGENT_API_SETTINGS) },
                                                onNavigateToLogRoute = ::launchLogRoute,
                                                onNavigateToSettingsRoute = ::launchSettings,
                                                onNavigateToModeSelection = { isSelectingWorkMode = true },
                                                resetToHomeTrigger = resetToHomeTrigger,
                                                bottomBarRefreshRequested = bottomBarRefreshRequested,
                                                onBottomBarRefreshConsumed = { bottomBarRefreshRequested = false }
                                            )
                                        }
                                    }
                                }

                                if (!hasSelectedWorkMode || isSelectingWorkMode) {
                                    WorkModeSelectionScreen(
                                        isFirstLaunch = !hasSelectedWorkMode,
                                        currentMode = currentWorkMode,
                                        onBack = { isSelectingWorkMode = false },
                                        onModeSelected = { selectedMode ->
                                            switchWorkMode(selectedMode)
                                        },
                                        onTransitionFinished = {
                                            isSelectingWorkMode = false
                                        },
                                        modifier = Modifier.fillMaxSize()
                                    )
                                }
                            }
                        }
                        permissionDisclosure?.let { disclosure ->
                            PermissionDisclosureDialog(
                                disclosure = disclosure,
                                onContinue = { continuePermissionRequest(disclosure) },
                                onDismiss = { dismissPermissionRequest(disclosure) }
                            )
                        }
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
        if (SystemSettingsStore.isInitialAgreementAccepted(this) &&
            WorkModeStore.hasSelectedWorkMode(this)
        ) {
            initializeAcceptedExperience()
            if (WorkModeStore.getAppWorkMode(this) == AppWorkMode.EXPRESS) {
                com.haoze.diting.express.ExpressModeLauncher.switchToExpress(this, AppWorkMode.EXPRESS)
            }
        }
    }

    private fun initializeAcceptedExperience() {
        if (acceptedExperienceInitialized) return
        acceptedExperienceInitialized = true
        AppNotificationChannels.createAllChannels(this)
        SubscriptionAutoUpdateScheduler.sync(this)
        if (!SystemSettingsStore.isStartupUpdateCheckDisabled(this)) {
            appUpdateHost.checkForUpdate(manual = false)
        }
        lifecycleScope.launch {
            delay(DATABASE_WARMUP_DELAY_MS)
            withContext(Dispatchers.IO) {
                runCatching {
                    val db = AppDatabase.getInstance(applicationContext)
                    db.openHelper.writableDatabase
                    com.haoze.diting.vpn.DefaultWhitelistSeeder.ensureInitialized(applicationContext, db)
                }
            }
        }
        handleAutoStartIfNeeded(intent)
        VpnMonitorManager.sync(this)
    }

    private fun declineInitialAgreement() {
        permissionDisclosure = null
        stopVpnService()
        VpnMonitorManager.stop(this)
        finishAndRemoveTask()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (SystemSettingsStore.isInitialAgreementAccepted(this)) {
            handleAutoStartIfNeeded(intent)
        }
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
            return
        }
        applyRecentsPrivacySetting()
        if (WorkModeStore.getAppWorkMode(this) == AppWorkMode.DNS) {
            // DNS mode lifecycle and status are managed inside DnsModeHost
        } else if (WorkModeStore.getAppWorkMode(this) == AppWorkMode.EXPRESS) {
            val isRunning = com.haoze.diting.express.ExpressVpnController.isRunning(this)
            val legacyIntent = Intent(DnsVpnService.ACTION_VPN_STATUS_CHANGED).apply {
                `package` = packageName
                putExtra(DnsVpnService.EXTRA_VPN_RUNNING, isRunning)
            }
            sendBroadcast(legacyIntent)
        } else {
            mainViewModel.refreshStatus()
        }
        VpnMonitorManager.sync(this)
        appUpdateHost.refreshDownloadState()
    }

    override fun onStop() {
        com.haoze.diting.express.ExpressModeLauncher.updateFloatingLogAppState(this, false)
        appUpdateHost.cancelActiveDownload()
        super.onStop()
    }

    private fun applyRecentsPrivacySetting() {
        applyRecentsPrivacy(SystemSettingsStore.isHideFromRecentsEnabled(this))
    }

    private fun applyRecentsPrivacy(hideFromRecents: Boolean) {
        RecentsPrivacyController.apply(this, hideFromRecents)
    }

    private fun handleAutoStartIfNeeded(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_AUTO_START_VPN, false) != true) return
        // Consume the extra so auto-start is not triggered again.
        setIntent(intent.replaceExtras(null))
        val isRunning = com.haoze.diting.express.ExpressModeLauncher.isCurrentModeRunning(this)
        if (!isRunning) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !NotificationPermissionHelper.hasPermission(this)) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                prepareVpn()
            }
        }
    }

    private fun onToggleVpn(isRunning: Boolean) {
        if (WorkModeStore.getAppWorkMode(this) == AppWorkMode.DNS) {
            return
        }
        if (WorkModeStore.getAppWorkMode(this) == AppWorkMode.EXPRESS) {
            com.haoze.diting.express.ExpressModeLauncher.toggle(this, ::prepareVpn)
            return
        }
        if (isRunning) {
            stopVpnService()
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !NotificationPermissionHelper.hasPermission(this)) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                prepareVpn()
            }
        }
    }

    private fun refreshRuntimeConfigIfRunning() {
        mainViewModel.loadProviders()
        mainViewModel.refreshRuntimeConfigIfRunning()
    }

    private fun prepareVpn() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            PermissionDisclosureSettings.updateVpnGrant(this, false)
            if (PermissionDisclosureSettings.isVpnExplained(this)) {
                vpnPrepareLauncher.launch(intent)
            } else {
                permissionDisclosure = PermissionDisclosure.VPN
            }
        } else {
            PermissionDisclosureSettings.updateVpnGrant(this, true)
            startVpnService()
        }
    }

    private fun continuePermissionRequest(disclosure: PermissionDisclosure) {
        permissionDisclosure = null
        when (disclosure) {
            PermissionDisclosure.VPN -> {
                PermissionDisclosureSettings.setVpnExplained(this, true)
                prepareVpn()
            }
        }
    }

    private fun dismissPermissionRequest(disclosure: PermissionDisclosure) {
        permissionDisclosure = null
        when (disclosure) {
            PermissionDisclosure.VPN -> {
                PermissionDisclosureSettings.setVpnExplained(this, true)
                mainViewModel.refreshStatus()
            }
        }
    }

    private fun startVpnService() {
        if (WorkModeStore.getAppWorkMode(this) == AppWorkMode.EXPRESS) {
            com.haoze.diting.express.ExpressModeLauncher.start(this)
            return
        }
        // DnsVpnService reads the selected provider (or race list) on its own.
        ContextCompat.startForegroundService(this, DnsVpnService.startIntent(this))
    }

    private fun stopVpnService() {
        if (WorkModeStore.getAppWorkMode(this) == AppWorkMode.EXPRESS) {
            com.haoze.diting.express.ExpressModeLauncher.stop(this)
            return
        }
        startService(DnsVpnService.stopIntent(this))
    }

    companion object {
        const val EXTRA_AUTO_START_VPN = "auto_start_vpn"
    }
}

