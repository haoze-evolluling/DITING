package com.haoze.diting.main

import android.app.Activity
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.haoze.diting.MainActivity
import com.haoze.diting.core.VpnStateRegistry
import com.haoze.diting.express.ExpressModeLauncher
import com.haoze.diting.express.ExpressVpnController
import com.haoze.diting.notification.VpnMonitorManager
import com.haoze.diting.onboarding.ModeOnboardingActivity
import com.haoze.diting.permission.ModePermissionStore
import com.haoze.diting.server.backend.DnsModeManager
import com.haoze.diting.ui.MainViewModel
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeActivity
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.ui.settings.SystemSettingsStore

/**
 * Coordinates app work modes (Normal, Express, Server/DNS), onboarding prerequisites,
 * and state transitions.
 */
class MainWorkModeCoordinator {
    var currentWorkMode by mutableStateOf(AppWorkMode.NORMAL)
        private set
    var hasSelectedWorkMode by mutableStateOf(false)
        private set
    var resetToHomeTrigger by mutableLongStateOf(0L)
        private set

    fun checkStartupOnboarding(
        activity: Activity,
        intent: Intent?,
        onInitializeAcceptedExperience: () -> Unit,
        onStopVpn: () -> Unit
    ): Boolean {
        currentWorkMode = WorkModeStore.getAppWorkMode(activity)
        hasSelectedWorkMode = WorkModeStore.hasSelectedWorkMode(activity)
        val isExistingUser = SystemSettingsStore.isInitialAgreementAccepted(activity) && hasSelectedWorkMode
        if (isExistingUser && !ModePermissionStore.isOnboardingCompleted(activity, currentWorkMode)) {
            AppWorkMode.entries.forEach { mode ->
                ModePermissionStore.setOnboardingCompleted(activity, mode, true)
            }
        }
        handleWorkModeChangeIntent(activity, intent, onInitializeAcceptedExperience, onStopVpn)
        if (SystemSettingsStore.isInitialAgreementAccepted(activity) && !hasSelectedWorkMode) {
            WorkModeActivity.start(activity, isFirstLaunch = true)
            activity.finish()
            return false
        } else if (SystemSettingsStore.isInitialAgreementAccepted(activity) &&
            !ModePermissionStore.isOnboardingCompleted(activity, currentWorkMode)
        ) {
            ModeOnboardingActivity.start(activity, currentWorkMode, isFirstLaunch = true)
            activity.finish()
            return false
        }
        return true
    }

    fun handleWorkModeChangeIntent(
        activity: Activity,
        intent: Intent?,
        onInitializeAcceptedExperience: () -> Unit,
        onStopVpn: () -> Unit
    ) {
        if (intent?.getBooleanExtra(MainActivity.EXTRA_WORK_MODE_CHANGED, false) == true) {
            val targetModeStr = intent.getStringExtra(MainActivity.EXTRA_TARGET_WORK_MODE)
            val targetMode = targetModeStr?.let { runCatching { AppWorkMode.valueOf(it) }.getOrNull() }
                ?: WorkModeStore.getAppWorkMode(activity)
            intent.removeExtra(MainActivity.EXTRA_WORK_MODE_CHANGED)
            intent.removeExtra(MainActivity.EXTRA_TARGET_WORK_MODE)
            switchWorkMode(activity, targetMode, onInitializeAcceptedExperience, onStopVpn)
        }
    }

    fun switchWorkMode(
        activity: Activity,
        selectedMode: AppWorkMode,
        onInitializeAcceptedExperience: () -> Unit,
        onStopVpn: () -> Unit
    ) {
        val previousMode = currentWorkMode
        WorkModeStore.setAppWorkMode(activity, selectedMode)
        WorkModeStore.setWorkModeSelected(activity, true)
        hasSelectedWorkMode = true
        currentWorkMode = selectedMode
        resetToHomeTrigger = System.currentTimeMillis()

        if (previousMode == AppWorkMode.DNS && selectedMode != AppWorkMode.DNS) {
            DnsModeManager.stopService(activity)
        } else if (previousMode == AppWorkMode.EXPRESS && selectedMode != AppWorkMode.EXPRESS) {
            ExpressModeLauncher.stopExpress(activity)
        }

        if (!ModePermissionStore.isOnboardingCompleted(activity, selectedMode)) {
            ModeOnboardingActivity.start(activity, selectedMode)
            return
        }

        if (selectedMode == AppWorkMode.DNS) {
            onStopVpn()
            VpnMonitorManager.stop(activity)
        } else if (selectedMode == AppWorkMode.EXPRESS) {
            ExpressModeLauncher.handleModeSelected(activity, selectedMode) {
                onInitializeAcceptedExperience()
            }
        } else {
            onInitializeAcceptedExperience()
        }
    }

    fun onAgreementAccepted(
        activity: Activity,
        onInitializeAcceptedExperience: () -> Unit
    ) {
        if (WorkModeStore.hasSelectedWorkMode(activity)) {
            val mode = WorkModeStore.getAppWorkMode(activity)
            if (!ModePermissionStore.isOnboardingCompleted(activity, mode)) {
                ModeOnboardingActivity.start(activity, mode, isFirstLaunch = true)
            } else {
                onInitializeAcceptedExperience()
                if (mode == AppWorkMode.EXPRESS) {
                    ExpressModeLauncher.switchToExpress(activity, AppWorkMode.EXPRESS)
                }
            }
        } else {
            WorkModeActivity.start(activity, isFirstLaunch = true)
        }
    }

    fun syncOnNewIntent(
        activity: Activity,
        intent: Intent?,
        onInitializeAcceptedExperience: () -> Unit,
        onStopVpn: () -> Unit
    ) {
        handleWorkModeChangeIntent(activity, intent, onInitializeAcceptedExperience, onStopVpn)
        hasSelectedWorkMode = WorkModeStore.hasSelectedWorkMode(activity)
        currentWorkMode = WorkModeStore.getAppWorkMode(activity)
    }

    fun syncOnResume(activity: Activity, mainViewModel: MainViewModel) {
        hasSelectedWorkMode = WorkModeStore.hasSelectedWorkMode(activity)
        currentWorkMode = WorkModeStore.getAppWorkMode(activity)
        if (currentWorkMode == AppWorkMode.DNS) {
            // DNS mode lifecycle and status are managed inside DnsModeHost
        } else if (currentWorkMode == AppWorkMode.EXPRESS) {
            val isRunning = ExpressVpnController.isRunning(activity)
            val legacyIntent = Intent(VpnStateRegistry.ACTION_VPN_STATUS_CHANGED).apply {
                `package` = activity.packageName
                putExtra(VpnStateRegistry.EXTRA_VPN_RUNNING, isRunning)
            }
            activity.sendBroadcast(legacyIntent)
        } else {
            mainViewModel.refreshStatus()
        }
        VpnMonitorManager.sync(activity)
    }
}
