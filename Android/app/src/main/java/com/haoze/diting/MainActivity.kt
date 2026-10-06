package com.haoze.diting

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.haoze.diting.express.ExpressModeLauncher
import com.haoze.diting.main.MainModeDispatcher
import com.haoze.diting.main.MainNavigationCoordinator
import com.haoze.diting.main.MainStartupCoordinator
import com.haoze.diting.main.MainVpnController
import com.haoze.diting.main.MainWorkModeCoordinator
import com.haoze.diting.permission.BatteryOptimizationHelper
import com.haoze.diting.ui.AppLanguageManager
import com.haoze.diting.ui.AppLanguageMode
import com.haoze.diting.ui.AppThemeSurface
import com.haoze.diting.ui.AppUpdateDialog
import com.haoze.diting.ui.InitialAgreementDialog
import com.haoze.diting.ui.MainViewModel
import com.haoze.diting.ui.PermissionDisclosureDialog
import com.haoze.diting.ui.RecentsPrivacyController
import com.haoze.diting.ui.background.CustomBackgroundManager
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.update.AppUpdateHost

class MainActivity : AppLocalizedActivity() {
    private var languageModeAtCreate = AppLanguageMode.SYSTEM
    private val appUpdateHost = AppUpdateHost(this)
    private val mainViewModel: MainViewModel by viewModels()

    private var mainThemeRefreshRequested by mutableStateOf(false)
    private var backgroundRefreshRequested by mutableStateOf(false)
    private var bottomBarRefreshRequested by mutableStateOf(false)

    private val startupCoordinator = MainStartupCoordinator()
    private val workModeCoordinator = MainWorkModeCoordinator()

    private val vpnController = MainVpnController(
        activity = this,
        getCurrentWorkMode = { workModeCoordinator.currentWorkMode },
        onRefreshStatus = { mainViewModel.refreshStatus() }
    )

    private val navigationCoordinator = MainNavigationCoordinator(
        activity = this,
        onRefreshRuntimeDns = {
            mainViewModel.loadProviders()
            mainViewModel.refreshRuntimeConfigIfRunning()
        },
        onThemeChanged = { mainThemeRefreshRequested = true },
        onBackgroundChanged = { backgroundRefreshRequested = true },
        onBottomBarChanged = { bottomBarRefreshRequested = true },
        onWorkModeChanged = { targetMode ->
            workModeCoordinator.switchWorkMode(
                activity = this,
                selectedMode = targetMode,
                onInitializeAcceptedExperience = ::initializeAcceptedExperience,
                onStopVpn = { vpnController.stopVpnService() }
            )
        }
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        languageModeAtCreate = AppLanguageManager.getMode(this)
        enableEdgeToEdge()
        startupCoordinator.performStartupChecks(this)
        applyRecentsPrivacySetting()

        if (!workModeCoordinator.checkStartupOnboarding(
                activity = this,
                intent = intent,
                onInitializeAcceptedExperience = ::initializeAcceptedExperience,
                onStopVpn = { vpnController.stopVpnService() }
            )
        ) {
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
                    CustomBackgroundManager.applyWindowBackground(this@MainActivity)
                    mainThemeRefreshRequested = false
                }
                if (backgroundRefreshRequested) {
                    backgroundEnabled = AppearanceSettingsStore.isCustomBackgroundEnabled(this@MainActivity)
                    backgroundUri = AppearanceSettingsStore.getCustomBackgroundUri(this@MainActivity)
                    CustomBackgroundManager.applyWindowBackground(this@MainActivity)
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
                            workModeCoordinator.onAgreementAccepted(
                                activity = this@MainActivity,
                                onInitializeAcceptedExperience = ::initializeAcceptedExperience
                            )
                        },
                        onDecline = {
                            vpnController.permissionDisclosure = null
                            startupCoordinator.declineInitialAgreement(this@MainActivity) {
                                vpnController.stopVpnService()
                            }
                        }
                    )
                } else {
                    Box(modifier = Modifier.fillMaxSize()) {
                        if (workModeCoordinator.hasSelectedWorkMode) {
                            MainModeDispatcher(
                                currentWorkMode = workModeCoordinator.currentWorkMode,
                                mainViewModel = mainViewModel,
                                onToggleVpn = { isRunning -> vpnController.onToggleVpn(isRunning) },
                                onNavigateToSettings = { route, dataset ->
                                    navigationCoordinator.launchSettings(route, dataset)
                                },
                                onNavigateToLogs = { dataset ->
                                    navigationCoordinator.launchLogs(dataset)
                                },
                                onNavigateToLogRoute = { route, dataset ->
                                    navigationCoordinator.launchLogRoute(route, dataset)
                                },
                                onNavigateToModeSelection = {
                                    navigationCoordinator.launchModeSelection()
                                },
                                onSwitchToNormalMode = {
                                    workModeCoordinator.switchWorkMode(
                                        activity = this@MainActivity,
                                        selectedMode = AppWorkMode.NORMAL,
                                        onInitializeAcceptedExperience = ::initializeAcceptedExperience,
                                        onStopVpn = { vpnController.stopVpnService() }
                                    )
                                },
                                resetToHomeTrigger = workModeCoordinator.resetToHomeTrigger,
                                bottomBarRefreshRequested = bottomBarRefreshRequested,
                                onBottomBarRefreshConsumed = { bottomBarRefreshRequested = false }
                            )
                        }
                    }
                }

                vpnController.permissionDisclosure?.let { disclosure ->
                    PermissionDisclosureDialog(
                        disclosure = disclosure,
                        onContinue = { vpnController.continuePermissionRequest(disclosure) },
                        onDismiss = { vpnController.dismissPermissionRequest(disclosure) }
                    )
                }

                appUpdateHost.state.availableUpdate?.let { update ->
                    if (appUpdateHost.dismissedVersion != update.version) {
                        AppUpdateDialog(
                            update = update,
                            downloadState = appUpdateHost.state.downloadState,
                            onDismiss = { appUpdateHost.dismissedVersion = update.version },
                            onDownload = { appUpdateHost.downloadUpdate() }
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
                ExpressModeLauncher.switchToExpress(this, AppWorkMode.EXPRESS)
            }
        }
    }

    private fun initializeAcceptedExperience() {
        startupCoordinator.initializeAcceptedExperience(
            activity = this,
            lifecycleScope = lifecycleScope,
            appUpdateHost = appUpdateHost,
            onAutoStartVpn = { vpnController.handleAutoStartIfNeeded(intent) }
        )
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        workModeCoordinator.syncOnNewIntent(
            activity = this,
            intent = intent,
            onInitializeAcceptedExperience = ::initializeAcceptedExperience,
            onStopVpn = { vpnController.stopVpnService() }
        )
        if (SystemSettingsStore.isInitialAgreementAccepted(this)) {
            vpnController.handleAutoStartIfNeeded(intent)
        }
    }

    override fun onStart() {
        super.onStart()
        ExpressModeLauncher.updateFloatingLogAppState(this, true)
    }

    override fun onResume() {
        super.onResume()
        val currentLanguageMode = AppLanguageManager.getMode(this)
        if (currentLanguageMode != languageModeAtCreate) {
            languageModeAtCreate = currentLanguageMode
            recreate()
            return
        }
        BatteryOptimizationHelper.invalidateCache()
        workModeCoordinator.syncOnResume(this, mainViewModel)
        applyRecentsPrivacySetting()
        appUpdateHost.refreshDownloadState()
    }

    override fun onStop() {
        ExpressModeLauncher.updateFloatingLogAppState(this, false)
        appUpdateHost.cancelActiveDownload()
        super.onStop()
    }

    private fun applyRecentsPrivacySetting() =
        RecentsPrivacyController.apply(this, SystemSettingsStore.isHideFromRecentsEnabled(this))

    companion object {
        const val EXTRA_AUTO_START_VPN = "auto_start_vpn"
        const val EXTRA_WORK_MODE_CHANGED = "main_work_mode_changed"
        const val EXTRA_TARGET_WORK_MODE = "main_target_work_mode"
    }
}
