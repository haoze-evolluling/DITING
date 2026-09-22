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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import com.haoze.diting.update.AppUpdateHost
import com.haoze.diting.ui.localizedText
import com.haoze.diting.vpn.DnsVpnService
import com.haoze.diting.vpn.SubscriptionAutoUpdateScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val DATABASE_WARMUP_DELAY_MS = 500L

private enum class PermissionDisclosure {
    VPN
}

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
        VpnMonitorManager.sync(this)
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
        }
    }

    private var mainThemeRefreshRequested by mutableStateOf(false)
    private var backgroundRefreshRequested by mutableStateOf(false)
    private var bottomBarRefreshRequested by mutableStateOf(false)

    private fun launchSettings(route: String) {
        if (settingsLaunchInProgress) return
        settingsLaunchInProgress = true
        settingsLauncher.launch(SettingsRouteActivity.createIntent(this, route))
    }

    private fun launchLogs() {
        startActivity(LogRouteActivity.createIntent(this, Routes.LOG_DASHBOARD))
    }

    private fun launchLogRoute(route: String) {
        startActivity(LogRouteActivity.createIntent(this, route))
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
                        if (initialAgreementAccepted) {
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
                                onNavigateToOptionalFeatures = { launchSettings(Routes.OPTIONAL_FEATURES) },
                                onNavigateToOutboundProxy = { launchSettings(Routes.OUTBOUND_PROXY_SETTINGS) },
                                onNavigateToDataCleanup = { launchSettings(Routes.DATA_CLEANUP) },
                                onNavigateToAgentApiSettings = { launchSettings(Routes.AGENT_API_SETTINGS) },
                                onNavigateToLogRoute = ::launchLogRoute,
                                onNavigateToSettingsRoute = ::launchSettings,
                                bottomBarRefreshRequested = bottomBarRefreshRequested,
                                onBottomBarRefreshConsumed = { bottomBarRefreshRequested = false }
                            )
                        } else {
                            InitialAgreementDialog(
                                onAccept = {
                                    SystemSettingsStore.setInitialAgreementAccepted(this@MainActivity)
                                    initialAgreementAccepted = true
                                    initializeAcceptedExperience()
                                },
                                onDecline = ::declineInitialAgreement
                            )
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
        if (SystemSettingsStore.isInitialAgreementAccepted(this)) {
            initializeAcceptedExperience()
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
        DnsVpnService.updateFloatingLogAppState(this, true)
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
        mainViewModel.refreshStatus()
        VpnMonitorManager.sync(this)
        appUpdateHost.refreshDownloadState()
    }

    override fun onStop() {
        DnsVpnService.updateFloatingLogAppState(this, false)
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
        mainViewModel.refreshStatus { isRunning ->
            if (!isRunning) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !NotificationPermissionHelper.hasPermission(this)) {
                    notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    prepareVpn()
                }
            }
        }
    }

    private fun onToggleVpn(isRunning: Boolean) {
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
        // DnsVpnService reads the selected provider (or race list) on its own.
        ContextCompat.startForegroundService(this, DnsVpnService.startIntent(this))
    }

    private fun stopVpnService() {
        startService(DnsVpnService.stopIntent(this))
    }

    companion object {
        const val EXTRA_AUTO_START_VPN = "auto_start_vpn"
    }
}

@androidx.compose.runtime.Composable
private fun InitialAgreementDialog(
    onAccept: () -> Unit,
    onDecline: () -> Unit
) {
    BackHandler(enabled = true, onBack = onDecline)
    AlertDialog(
        onDismissRequest = onDecline,
        title = { Text(localizedText("使用须知")) },
        text = {
            Text(
                localizedText(
                    "软件说明\n" +
                        "谛听是一款基于 Android 本地 VPN 的 DNS 管理工具。本软件旨在屏蔽、过滤有害域名，净化网络环境，并不用于过滤商业广告。\n\n" +
                        "注意事项\n" +
                        "软件依赖本地 VPN 与上游 DNS 运行，解析表现受网络环境与配置影响；规则与日志均保存在设备本机。启用扩展功能可能改变网络行为，请在了解其作用后谨慎使用。\n\n" +
                        "免责条款\n" +
                        "本软件按现状提供。使用者须遵守相关法律法规，自行确认规则与上游来源的合法性及安全性。严禁将本软件用于任何违法用途；对于滥用软件或将其用于其他用途所产生的后果，由使用者自行承担。"
                )
            )
        },
        confirmButton = {
            TextButton(onClick = onAccept) {
                Text(localizedText("同意并继续"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDecline) {
                Text(localizedText("不同意并退出"))
            }
        },
        properties = DialogProperties(
            dismissOnBackPress = true,
            dismissOnClickOutside = true
        )
    )
}

@androidx.compose.runtime.Composable
private fun PermissionDisclosureDialog(
    disclosure: PermissionDisclosure,
    onContinue: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("VPN 连接权限")) },
        text = { Text(localizedText("谛听需要建立本地 VPN 来处理和过滤 DNS 请求。此权限用于在设备上接管 DNS流量，不会将全部网络流量发送到远程 VPN 服务器。")) },
        confirmButton = { TextButton(onClick = onContinue) { Text(localizedText("继续")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(localizedText("暂不允许")) } }
    )
}

