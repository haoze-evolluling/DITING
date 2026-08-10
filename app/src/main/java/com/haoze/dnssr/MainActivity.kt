package com.haoze.dnssr

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
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
import com.haoze.dnssr.ui.AppUpdateDialog
import com.haoze.dnssr.ui.localizedText
import com.haoze.dnssr.update.AppUpdateDownloadStatus
import com.haoze.dnssr.update.AppUpdateDownloadState
import com.haoze.dnssr.update.AppUpdateManager
import com.haoze.dnssr.update.AppUpdateNotifier
import com.haoze.dnssr.update.AppUpdateUiState
import com.haoze.dnssr.vpn.DnsVpnService
import com.haoze.dnssr.vpn.VpnMonitorService
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val DATABASE_WARMUP_DELAY_MS = 500L

private enum class PermissionDisclosure {
    NOTIFICATION,
    VPN
}

class MainActivity : AppLocalizedActivity() {
    private var languageModeAtCreate = AppLanguageMode.SYSTEM

    private var permissionDisclosure by mutableStateOf<PermissionDisclosure?>(null)
    private var appUpdateState by mutableStateOf(AppUpdateUiState())
    private var dismissedUpdateVersion by mutableStateOf("")
    private var acceptedExperienceInitialized = false
    private var appUpdateDownloadJob: Job? = null
    private var appUpdateDownloadGeneration = 0L
    private var startupUpdateCheckDisabled by mutableStateOf(true)
    private var settingsLaunchInProgress = false
    private val appUpdateManager by lazy { AppUpdateManager(applicationContext) }
    private val appUpdateNotifier by lazy { AppUpdateNotifier(applicationContext) }

    private val vpnPrepareLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            PermissionDisclosureSettings.updateVpnGrant(this, true)
            startVpnService()
        } else {
            PermissionDisclosureSettings.updateVpnGrant(this, false)
            ensureMonitorServiceState()
            mainViewModel?.refreshStatus()
        }
    }

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        PermissionDisclosureSettings.updateNotificationGrant(this, granted)
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
        val route = if (AppSettings.isLegacyLogPageEnabled(this)) {
            Routes.LOGS
        } else {
            Routes.LOG_DASHBOARD
        }
        startActivity(LogRouteActivity.createIntent(this, route))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        languageModeAtCreate = AppLanguageManager.getMode(this)
        enableEdgeToEdge()
        applyRecentsPrivacySetting()
        LauncherIconManager.applyPreferredIcon(this)
        startupUpdateCheckDisabled = AppSettings.isStartupUpdateCheckDisabled(this)
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
                                onNavigateToHomeProviderVisibility = { launchSettings(Routes.HOME_PROVIDER_VISIBILITY) },
                                onNavigateToRaceModeSettings = { launchSettings(Routes.RACE_MODE_PROVIDERS) },
                                onNavigateToBlockedApps = { launchSettings(Routes.BLOCKED_APPS) },
                                onNavigateToAppAllowlist = { launchSettings(Routes.APP_ALLOWLIST) },
                                onNavigateToAppearanceSettings = { launchSettings(Routes.APPEARANCE_SETTINGS) },
                                onNavigateToDomainRuleManagement = { launchSettings(Routes.DOMAIN_RULE_MANAGEMENT) },
                                onNavigateToAddressRuleManagement = { launchSettings(Routes.ADDRESS_RULE_MANAGEMENT) },
                                onNavigateToHttpInspection = { launchSettings(Routes.HTTP_INSPECTION_SETTINGS) },
                                onNavigateToLogRetentionSettings = { launchSettings(Routes.LOG_RETENTION_SETTINGS) },
                                onNavigateToRaceModeLatency = { launchSettings(Routes.RACE_MODE_LATENCY) },
                                onNavigateToHomeProviderVisibilityFromFeatureHub = { launchSettings(Routes.HOME_PROVIDER_VISIBILITY) },
                                onNavigateToAbout = { launchSettings(Routes.ABOUT) },
                                onNavigateToSponsor = { launchSettings(Routes.SPONSOR) },
                                onNavigateToSponsorList = { launchSettings(Routes.SPONSOR_LIST) },
                                onNavigateToCoBuilderList = { launchSettings(Routes.CO_BUILDER_LIST) },
                                onNavigateToAppUpdate = { launchSettings(Routes.APP_UPDATE) },
                                onNavigateToDataManagement = { launchSettings(Routes.CONFIG_TRANSFER) }
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
        if (AppSettings.isInitialAgreementAccepted(this)) {
            initializeAcceptedExperience()
        }
    }

    private fun initializeAcceptedExperience() {
        if (acceptedExperienceInitialized) return
        acceptedExperienceInitialized = true
        SubscriptionAutoUpdateScheduler.sync(this)
        if (!AppSettings.isStartupUpdateCheckDisabled(this)) {
            checkForAppUpdate(manual = false)
        }
        lifecycleScope.launch {
            delay(DATABASE_WARMUP_DELAY_MS)
            withContext(Dispatchers.IO) {
                AppDatabase.getInstance(applicationContext).openHelper.writableDatabase
            }
        }
        handleAutoStartIfNeeded(intent)
        ensureMonitorServiceState()
    }

    private fun declineInitialAgreement() {
        permissionDisclosure = null
        stopVpnService()
        stopService(VpnMonitorService.stopIntent(this))
        finishAndRemoveTask()
    }

    private fun ensureMonitorServiceState() {
        if (!AppSettings.isPersistentNotificationEnabled(this)) {
            stopService(VpnMonitorService.stopIntent(this))
            return
        }
        if (DnsVpnService.isRunning(this)) return
        if (!hasNotificationPermission()) return
        ContextCompat.startForegroundService(this, VpnMonitorService.startIntent(this))
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
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
        PermissionDisclosureSettings.updateNotificationGrant(this, hasNotificationPermission())
        refreshAppUpdateDownloadState()
    }

    override fun onStop() {
        DnsVpnService.updateFloatingLogAppState(this, false)
        if (appUpdateState.downloadState.status == AppUpdateDownloadStatus.Downloading) {
            appUpdateDownloadGeneration++
            appUpdateDownloadJob?.cancel()
            appUpdateDownloadJob = null
            appUpdateNotifier.clear()
            appUpdateState = appUpdateState.copy(
                downloadState = AppUpdateDownloadState(version = appUpdateState.downloadState.version)
            )
        }
        super.onStop()
    }

    private fun checkForAppUpdate(manual: Boolean) {
        if (appUpdateState.checking) return
        if (manual) dismissedUpdateVersion = ""
        appUpdateState = appUpdateState.copy(
            checking = true,
            error = "",
            message = if (manual) "正在检查 GitHub Release" else appUpdateState.message,
        )
        lifecycleScope.launch {
            try {
                val update = appUpdateManager.checkForUpdate()
                val downloadState = update?.let { appUpdateManager.refreshDownloadState(it) }
                appUpdateState = AppUpdateUiState(
                    availableUpdate = update,
                    downloadState = downloadState ?: appUpdateState.downloadState,
                    message = if (update == null) "当前已是最新版本。" else "发现 ${update.version} 新版本。",
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                appUpdateState = appUpdateState.copy(
                    checking = false,
                    error = if (manual) error.message ?: "检查更新失败。" else "",
                    message = if (manual) "" else appUpdateState.message,
                )
            }
        }
    }

    private fun downloadAppUpdate() {
        val update = appUpdateState.availableUpdate ?: return
        val status = appUpdateState.downloadState.status.takeIf { appUpdateState.downloadState.version == update.version }
        if (status == AppUpdateDownloadStatus.Downloading) return
        if (status == AppUpdateDownloadStatus.Downloaded) {
            if (!appUpdateManager.installDownloadedUpdate(update)) {
                appUpdateState = appUpdateState.copy(
                    downloadState = AppUpdateDownloadState(version = update.version),
                    error = "安装包不存在或无法打开，请重新下载。",
                )
            }
            return
        }
        appUpdateDownloadJob?.cancel()
        appUpdateNotifier.clear()
        val generation = ++appUpdateDownloadGeneration
        appUpdateDownloadJob = lifecycleScope.launch {
            try {
                appUpdateState = appUpdateState.copy(
                    downloadState = AppUpdateDownloadState(
                        version = update.version,
                        status = AppUpdateDownloadStatus.Downloading,
                    ),
                    error = "",
                )
                appUpdateNotifier.showProgress(update, 0L, -1L)
                val downloadState = appUpdateManager.download(update) { downloadedBytes, totalBytes ->
                    runOnUiThread {
                        if (
                            generation == appUpdateDownloadGeneration &&
                            appUpdateState.downloadState.status == AppUpdateDownloadStatus.Downloading
                        ) {
                            appUpdateState = appUpdateState.copy(
                                downloadState = AppUpdateDownloadState(
                                    version = update.version,
                                    status = AppUpdateDownloadStatus.Downloading,
                                    downloadedBytes = downloadedBytes,
                                    totalBytes = totalBytes,
                                )
                            )
                            appUpdateNotifier.showProgress(update, downloadedBytes, totalBytes)
                        }
                    }
                }
                if (generation != appUpdateDownloadGeneration) return@launch
                appUpdateState = appUpdateState.copy(
                    downloadState = downloadState,
                    error = if (downloadState.status == AppUpdateDownloadStatus.Failed) "更新包下载失败，请重试。" else "",
                    message = if (downloadState.status == AppUpdateDownloadStatus.Downloaded) "下载完成，请点击安装。" else appUpdateState.message,
                )
                if (downloadState.status == AppUpdateDownloadStatus.Downloaded) {
                    appUpdateNotifier.showCompleted(update)
                } else {
                    appUpdateNotifier.clear()
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                appUpdateNotifier.clear()
                appUpdateState = appUpdateState.copy(error = error.message ?: "无法开始下载更新。")
            }
        }
    }

    private fun updateStartupUpdateCheckPreference(disabled: Boolean) {
        AppSettings.setStartupUpdateCheckDisabled(this, disabled)
        startupUpdateCheckDisabled = disabled
    }

    private fun refreshAppUpdateDownloadState() {
        val update = appUpdateState.availableUpdate ?: return
        lifecycleScope.launch {
            runCatching { appUpdateManager.refreshDownloadState(update) }
                .onSuccess { downloadState -> appUpdateState = appUpdateState.copy(downloadState = downloadState) }
        }
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
                requestNotificationPermissionThenPrepare()
            }
        }
    }

    private fun onToggleVpn(isRunning: Boolean) {
        if (isRunning) {
            stopVpnService()
        } else {
            requestNotificationPermissionThenPrepare()
        }
    }

    private fun refreshRuntimeConfigIfRunning() {
        mainViewModel.loadProviders()
        mainViewModel.refreshRuntimeConfigIfRunning()
    }

    private fun requestNotificationPermissionThenPrepare() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            when (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)) {
                PackageManager.PERMISSION_GRANTED -> {
                    PermissionDisclosureSettings.updateNotificationGrant(this, true)
                    prepareVpn()
                }
                else -> {
                    PermissionDisclosureSettings.updateNotificationGrant(this, false)
                    when {
                        !PermissionDisclosureSettings.isNotificationExplained(this) -> {
                            permissionDisclosure = PermissionDisclosure.NOTIFICATION
                        }
                        PermissionDisclosureSettings.wasNotificationRequested(this) -> prepareVpn()
                        else -> requestNotificationPermission()
                    }
                }
            }
        } else {
            prepareVpn()
        }
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

    private fun requestNotificationPermission() {
        PermissionDisclosureSettings.markNotificationRequested(this)
        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun continuePermissionRequest(disclosure: PermissionDisclosure) {
        permissionDisclosure = null
        when (disclosure) {
            PermissionDisclosure.NOTIFICATION -> {
                PermissionDisclosureSettings.setNotificationExplained(this, true)
                requestNotificationPermission()
            }
            PermissionDisclosure.VPN -> {
                PermissionDisclosureSettings.setVpnExplained(this, true)
                prepareVpn()
            }
        }
    }

    private fun dismissPermissionRequest(disclosure: PermissionDisclosure) {
        permissionDisclosure = null
        when (disclosure) {
            PermissionDisclosure.NOTIFICATION -> {
                PermissionDisclosureSettings.setNotificationExplained(this, true)
                PermissionDisclosureSettings.markNotificationRequested(this)
                prepareVpn()
            }
            PermissionDisclosure.VPN -> {
                PermissionDisclosureSettings.setVpnExplained(this, true)
                ensureMonitorServiceState()
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
    val title: String
    val message: String
    when (disclosure) {
        PermissionDisclosure.NOTIFICATION -> {
            title = localizedText("通知权限")
            message = localizedText("通知用于显示 DNS VPN 的运行和停止状态。拒绝不会阻止核心功能运行，但你可能无法及时看到连接状态提醒。")
        }
        PermissionDisclosure.VPN -> {
            title = localizedText("VPN 连接权限")
            message = localizedText("谛听需要建立本地 VPN 来处理和过滤 DNS 请求。此权限用于在设备上接管 DNS 流量，不会将全部网络流量发送到远程 VPN 服务器。")
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onContinue) { Text(localizedText("继续")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(localizedText("暂不允许")) } }
    )
}
