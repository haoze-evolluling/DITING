package com.haoze.diting

import com.haoze.diting.core.rule.DefaultWhitelistSeeder
import com.haoze.diting.normal.ui.*

import android.Manifest
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.ui.showToast
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.AppSettings
import com.haoze.diting.ui.AppLanguageManager
import com.haoze.diting.ui.AppLanguageMode
import com.haoze.diting.ui.AppThemeSurface
import com.haoze.diting.ui.MainViewModel
import com.haoze.diting.ui.PermissionDisclosureSettings
import com.haoze.diting.ui.RecentsPrivacyController
import com.haoze.diting.ui.Routes
import com.haoze.diting.notification.AppNotificationChannels
import com.haoze.diting.notification.NotificationPermissionHelper
import com.haoze.diting.notification.VpnMonitorManager
import com.haoze.diting.permission.ModePermissionStore
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeActivity
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.update.AppUpdateHost
import com.haoze.diting.normal.DnsVpnService
import com.haoze.diting.core.rule.SubscriptionAutoUpdateScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

import com.haoze.diting.ui.AppUpdateDialog
import com.haoze.diting.ui.InitialAgreementDialog
import com.haoze.diting.normal.ui.MainScreen
import com.haoze.diting.ui.PermissionDisclosure
import com.haoze.diting.ui.PermissionDisclosureDialog

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

    private val batteryOptimizationLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        com.haoze.diting.permission.BatteryOptimizationHelper.invalidateCache()
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
                switchWorkMode(WorkModeStore.getAppWorkMode(this@MainActivity))
            }
        }
    }

    private var mainThemeRefreshRequested by mutableStateOf(false)
    private var backgroundRefreshRequested by mutableStateOf(false)
    private var bottomBarRefreshRequested by mutableStateOf(false)
    private var currentWorkMode by mutableStateOf(AppWorkMode.NORMAL)
    private var hasSelectedWorkMode by mutableStateOf(false)
    private var resetToHomeTrigger by mutableLongStateOf(0L)

    private fun switchWorkMode(selectedMode: AppWorkMode) {
        val previousMode = currentWorkMode
        WorkModeStore.setAppWorkMode(this, selectedMode)
        WorkModeStore.setWorkModeSelected(this, true)
        hasSelectedWorkMode = true
        currentWorkMode = selectedMode
        resetToHomeTrigger = System.currentTimeMillis()

        if (previousMode == AppWorkMode.DNS && selectedMode != AppWorkMode.DNS) {
            com.haoze.diting.server.backend.DnsModeManager.stopService(this)
        } else if (previousMode == AppWorkMode.EXPRESS && selectedMode != AppWorkMode.EXPRESS) {
            com.haoze.diting.express.ExpressModeLauncher.stopExpress(this)
        }

        if (!com.haoze.diting.permission.ModePermissionStore.isOnboardingCompleted(this, selectedMode)) {
            com.haoze.diting.onboarding.ModeOnboardingActivity.start(this, selectedMode)
            return
        }

        if (selectedMode == AppWorkMode.DNS) {
            stopVpnService()
            VpnMonitorManager.stop(this)
        } else if (selectedMode == AppWorkMode.EXPRESS) {
            com.haoze.diting.express.ExpressModeLauncher.handleModeSelected(this, selectedMode) {
                initializeAcceptedExperience()
            }
        } else {
            initializeAcceptedExperience()
        }
    }

    private fun handleWorkModeChangeIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_WORK_MODE_CHANGED, false) == true) {
            val targetModeStr = intent.getStringExtra(EXTRA_TARGET_WORK_MODE)
            val targetMode = targetModeStr?.let { runCatching { AppWorkMode.valueOf(it) }.getOrNull() }
                ?: WorkModeStore.getAppWorkMode(this)
            intent.removeExtra(EXTRA_WORK_MODE_CHANGED)
            intent.removeExtra(EXTRA_TARGET_WORK_MODE)
            switchWorkMode(targetMode)
        }
    }

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
        currentWorkMode = WorkModeStore.getAppWorkMode(this)
        hasSelectedWorkMode = WorkModeStore.hasSelectedWorkMode(this)
        val isExistingUser = SystemSettingsStore.isInitialAgreementAccepted(this) && hasSelectedWorkMode
        if (isExistingUser && !ModePermissionStore.isOnboardingCompleted(this, currentWorkMode)) {
            AppWorkMode.entries.forEach { mode ->
                ModePermissionStore.setOnboardingCompleted(this, mode, true)
            }
        }
        handleWorkModeChangeIntent(intent)
        if (SystemSettingsStore.isInitialAgreementAccepted(this) && !hasSelectedWorkMode) {
            WorkModeActivity.start(this, isFirstLaunch = true)
            finish()
            return
        } else if (SystemSettingsStore.isInitialAgreementAccepted(this) &&
            !ModePermissionStore.isOnboardingCompleted(this, currentWorkMode)
        ) {
            com.haoze.diting.onboarding.ModeOnboardingActivity.start(this, currentWorkMode, isFirstLaunch = true)
            finish()
            return
        }
        setContent {
            var initialAgreementAccepted by remember {
                mutableStateOf(SystemSettingsStore.isInitialAgreementAccepted(this))
            }
            var themeMode by remember { mutableStateOf(AppearanceSettingsStore.getAppThemeMode(this)) }
            var colorStyle by remember { mutableStateOf(AppearanceSettingsStore.getThemeColorStyle(this)) }
            var backgroundEnabled by remember { mutableStateOf(AppearanceSettingsStore.isCustomBackgroundEnabled(this)) }
            var backgroundUri by remember { mutableStateOf(AppearanceSettingsStore.getCustomBackgroundUri(this)) }

            LaunchedEffect(mainThemeRefreshRequested, backgroundRefreshRequested) {
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
            }
            AppThemeSurface(
                themeMode = themeMode,
                colorStyle = colorStyle,
                backgroundEnabled = backgroundEnabled,
                backgroundUri = backgroundUri,
                modifier = Modifier.fillMaxSize()
            ) {

                        if (!initialAgreementAccepted) {
                            InitialAgreementDialog(
                                onAccept = {
                                    SystemSettingsStore.setInitialAgreementAccepted(this@MainActivity)
                                    initialAgreementAccepted = true
                                    if (WorkModeStore.hasSelectedWorkMode(this@MainActivity)) {
                                        val mode = WorkModeStore.getAppWorkMode(this@MainActivity)
                                        if (!com.haoze.diting.permission.ModePermissionStore.isOnboardingCompleted(this@MainActivity, mode)) {
                                            com.haoze.diting.onboarding.ModeOnboardingActivity.start(this@MainActivity, mode, isFirstLaunch = true)
                                        } else {
                                            initializeAcceptedExperience()
                                            if (mode == AppWorkMode.EXPRESS) {
                                                com.haoze.diting.express.ExpressModeLauncher.switchToExpress(this@MainActivity, AppWorkMode.EXPRESS)
                                            }
                                        }
                                    } else {
                                        WorkModeActivity.start(this@MainActivity, isFirstLaunch = true)
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
                                                onNavigateToModeSelection = { WorkModeActivity.start(this@MainActivity, isFirstLaunch = false) },
                                                resetToHomeTrigger = resetToHomeTrigger,
                                                bottomBarRefreshRequested = bottomBarRefreshRequested,
                                                onBottomBarRefreshConsumed = { bottomBarRefreshRequested = false },
                                                viewModel = mainViewModel
                                            )
                                        }
                                        AppWorkMode.DNS -> {
                                            com.haoze.diting.server.ui.DnsModeHost(
                                                onSelectMode = { WorkModeActivity.start(this@MainActivity, isFirstLaunch = false) },
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
                                                onNavigateToModeSelection = { WorkModeActivity.start(this@MainActivity, isFirstLaunch = false) },
                                                resetToHomeTrigger = resetToHomeTrigger,
                                                bottomBarRefreshRequested = bottomBarRefreshRequested,
                                                onBottomBarRefreshConsumed = { bottomBarRefreshRequested = false }
                                            )
                                        }
                                    }
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
                    com.haoze.diting.core.rule.DefaultWhitelistSeeder.ensureInitialized(applicationContext, db)
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
        handleWorkModeChangeIntent(intent)
        hasSelectedWorkMode = WorkModeStore.hasSelectedWorkMode(this)
        currentWorkMode = WorkModeStore.getAppWorkMode(this)
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
        com.haoze.diting.permission.BatteryOptimizationHelper.invalidateCache()
        hasSelectedWorkMode = WorkModeStore.hasSelectedWorkMode(this)
        currentWorkMode = WorkModeStore.getAppWorkMode(this)
        applyRecentsPrivacySetting()
        if (currentWorkMode == AppWorkMode.DNS) {
            // DNS mode lifecycle and status are managed inside DnsModeHost
        } else if (currentWorkMode == AppWorkMode.EXPRESS) {
            val isRunning = com.haoze.diting.express.ExpressVpnController.isRunning(this)
            val legacyIntent = Intent(com.haoze.diting.core.VpnStateRegistry.ACTION_VPN_STATUS_CHANGED).apply {
                `package` = packageName
                putExtra(com.haoze.diting.core.VpnStateRegistry.EXTRA_VPN_RUNNING, isRunning)
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

    private fun applyRecentsPrivacySetting() =
        RecentsPrivacyController.apply(this, SystemSettingsStore.isHideFromRecentsEnabled(this))

    private fun applyRecentsPrivacy(hideFromRecents: Boolean) =
        RecentsPrivacyController.apply(this, hideFromRecents)

    private fun handleAutoStartIfNeeded(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_AUTO_START_VPN, false) != true) return
        intent.removeExtra(EXTRA_AUTO_START_VPN)
        if (currentWorkMode == AppWorkMode.DNS) {
            com.haoze.diting.server.backend.DnsModeManager.startService(this)
            return
        }
        if (!com.haoze.diting.express.ExpressModeLauncher.isCurrentModeRunning(this)) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !NotificationPermissionHelper.hasPermission(this)) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                prepareVpn()
            }
        }
    }

    private fun onToggleVpn(isRunning: Boolean) {
        if (currentWorkMode == AppWorkMode.DNS) return
        if (currentWorkMode == AppWorkMode.EXPRESS) {
            com.haoze.diting.express.ExpressModeLauncher.toggle(this, ::prepareVpn)
            return
        }
        if (isRunning) {
            stopVpnService()
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !NotificationPermissionHelper.hasPermission(this)) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            prepareVpn()
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
            PermissionDisclosure.NOTIFICATION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
            }
            PermissionDisclosure.BATTERY_OPTIMIZATION -> {
                com.haoze.diting.permission.BatteryOptimizationHelper.requestPermission(
                    context = this,
                    launcher = batteryOptimizationLauncher,
                    onAlreadyGranted = { prepareVpn() }
                )
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
            PermissionDisclosure.NOTIFICATION -> {
                // User declined notification disclosure; proceed without notifications
                prepareVpn()
            }
            PermissionDisclosure.BATTERY_OPTIMIZATION -> {
                com.haoze.diting.permission.BatteryOptimizationHelper.setDismissed(this, true)
                prepareVpn()
            }
        }
    }

    private fun startVpnService() {
        if (currentWorkMode == AppWorkMode.EXPRESS) {
            com.haoze.diting.express.ExpressModeLauncher.start(this)
        } else {
            ContextCompat.startForegroundService(this, DnsVpnService.startIntent(this))
        }
    }

    private fun stopVpnService() {
        if (currentWorkMode == AppWorkMode.EXPRESS) {
            com.haoze.diting.express.ExpressModeLauncher.stop(this)
        } else {
            startService(DnsVpnService.stopIntent(this))
        }
    }

    companion object {
        const val EXTRA_AUTO_START_VPN = "auto_start_vpn"
        const val EXTRA_WORK_MODE_CHANGED = "main_work_mode_changed"
        const val EXTRA_TARGET_WORK_MODE = "main_target_work_mode"
    }
}

