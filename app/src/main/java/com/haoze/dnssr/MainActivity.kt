package com.haoze.dnssr

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import com.haoze.dnssr.ui.showToast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
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
import androidx.lifecycle.lifecycleScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.AppLanguageManager
import com.haoze.dnssr.ui.AppLanguageMode
import com.haoze.dnssr.ui.AppThemeMode
import com.haoze.dnssr.ui.AppThemeSurface
import com.haoze.dnssr.ui.LauncherIconManager
import com.haoze.dnssr.ui.MainScreen
import com.haoze.dnssr.ui.MainViewModel
import com.haoze.dnssr.ui.PermissionDisclosureSettings
import com.haoze.dnssr.ui.RecentsPrivacyController
import com.haoze.dnssr.ui.Routes
import com.haoze.dnssr.notification.AppNotificationChannels
import com.haoze.dnssr.notification.NotificationPermissionHelper
import com.haoze.dnssr.notification.VpnMonitorManager
import com.haoze.dnssr.ui.AppUpdateDialog
import com.haoze.dnssr.update.AppUpdateHost
import com.haoze.dnssr.ui.localizedText
import com.haoze.dnssr.vpn.DnsVpnService
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateScheduler
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
    private var startupUpdateCheckDisabled by mutableStateOf(true)
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
        }
    }

    private var mainThemeRefreshRequested by mutableStateOf(false)
    private var backgroundRefreshRequested by mutableStateOf(false)

    private fun launchSettings(route: String) {
        if (settingsLaunchInProgress) return
        settingsLaunchInProgress = true
        settingsLauncher.launch(SettingsRouteActivity.createIntent(this, route))
    }

    private fun launchLogs() {
        startActivity(LogRouteActivity.createIntent(this, Routes.LOG_DASHBOARD))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        languageModeAtCreate = AppLanguageManager.getMode(this)
        enableEdgeToEdge()
        AppSettings.performStartupSelfCheck(this)
        applyRecentsPrivacySetting()
        LauncherIconManager.applyPreferredIcon(this)
        startupUpdateCheckDisabled = AppSettings.isStartupUpdateCheckDisabled(this)
        if (com.haoze.dnssr.crash.CrashLogManager.consumePendingAutoExportNotice(this)) {
            showToast("软件连续异常退出，崩溃日志已自动备份至系统“下载”目录", Toast.LENGTH_LONG)
        }
        setContent {
            var initialAgreementAccepted by remember {
                mutableStateOf(AppSettings.isInitialAgreementAccepted(this))
            }
            var themeMode by remember { mutableStateOf(AppSettings.getAppThemeMode(this)) }
            var colorStyle by remember { mutableStateOf(AppSettings.getThemeColorStyle(this)) }
            var backgroundEnabled by remember { mutableStateOf(AppSettings.isCustomBackgroundEnabled(this)) }
            var backgroundUri by remember { mutableStateOf(AppSettings.getCustomBackgroundUri(this)) }
            LaunchedEffect(mainThemeRefreshRequested, backgroundRefreshRequested) {
                if (mainThemeRefreshRequested) {
                    themeMode = AppSettings.getAppThemeMode(this@MainActivity)
                    colorStyle = AppSettings.getThemeColorStyle(this@MainActivity)
                    mainThemeRefreshRequested = false
                }
                if (backgroundRefreshRequested) {
                    backgroundEnabled = AppSettings.isCustomBackgroundEnabled(this@MainActivity)
                    backgroundUri = AppSettings.getCustomBackgroundUri(this@MainActivity)
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
                                onNavigateToTrafficStats = { launchSettings(Routes.APP_TRAFFIC_STATS) }
                            )
                        } else {
                            InitialAgreementDialog(
                                onAccept = {
                                    AppSettings.setInitialAgreementAccepted(this@MainActivity)
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
        if (AppSettings.isInitialAgreementAccepted(this)) {
            initializeAcceptedExperience()
        }
    }

    private fun initializeAcceptedExperience() {
        if (acceptedExperienceInitialized) return
        acceptedExperienceInitialized = true
        AppNotificationChannels.createAllChannels(this)
        SubscriptionAutoUpdateScheduler.sync(this)
        if (!AppSettings.isStartupUpdateCheckDisabled(this)) {
            appUpdateHost.checkForUpdate(manual = false)
        }
        lifecycleScope.launch {
            delay(DATABASE_WARMUP_DELAY_MS)
            withContext(Dispatchers.IO) {
                runCatching {
                    val db = AppDatabase.getInstance(applicationContext)
                    db.openHelper.writableDatabase
                    com.haoze.dnssr.vpn.DefaultWhitelistSeeder.ensureInitialized(applicationContext, db)
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
        if (AppSettings.isInitialAgreementAccepted(this)) {
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

    private fun updateStartupUpdateCheckPreference(disabled: Boolean) {
        AppSettings.setStartupUpdateCheckDisabled(this, disabled)
        startupUpdateCheckDisabled = disabled
    }

    private fun applyRecentsPrivacySetting() {
        applyRecentsPrivacy(AppSettings.isHideFromRecentsEnabled(this))
    }

    private fun applyRecentsPrivacy(hideFromRecents: Boolean) {
        RecentsPrivacyController.apply(this, hideFromRecents)
    }

    private fun handleAutoStartIfNeeded(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_AUTO_START_VPN, false) != true) return
        // 消费 extra，防止重复触发
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
        // 由 DnsVpnService 自行读取选中的单个 provider 或竞速列表
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
                localizedText("软件介绍\n" +
                    "谛听是一款基于 Android 本地 VPN 的 DNS 管理工具，支持 DNS、DoH、DoT、服务商管理、缓存、规则、日志和按应用控制等功能。\n\n" +
                    "注意事项\n" +
                    "本软件依赖本地 VPN 与上游 DNS 服务运行，解析速度、稳定性和可用性会受到网络环境、所选上游和规则配置影响。缓存、日志、规则与配置保存在设备本机，但上游仍会收到完成解析所必需的查询。启用 HTTPS 流量检查等扩展功能可能影响网络行为，请在了解其作用后谨慎使用。\n\n" +
                    "免责条款\n" +
                    "本软件按现状提供，不保证服务可用性、解析速度或与所有设备和网络环境兼容。请自行确认上游服务、规则和配置来源的可靠性，并承担相应使用风险。不得将本软件用于违法用途；因配置或使用本软件造成的网络、数据或其他损失，由用户自行承担。")
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
