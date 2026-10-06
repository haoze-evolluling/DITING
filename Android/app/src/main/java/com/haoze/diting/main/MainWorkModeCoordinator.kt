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
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeActivity
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.ui.settings.SystemSettingsStore

/**
 * Coordinates app work modes (Normal, Express, Server/DNS), onboarding prerequisites,
 * and state transitions.
 */
class MainWorkModeCoordinator(
    private val onInitializeAcceptedExperience: () -> Unit = {},
    private val onStopVpn: () -> Unit = {},
    private val onRefreshNormalStatus: () -> Unit = {}
) {
    var currentWorkMode by mutableStateOf(AppWorkMode.NORMAL)
        private set
    var hasSelectedWorkMode by mutableStateOf(false)
        private set
    var resetToHomeTrigger by mutableLongStateOf(0L)
        private set

    fun checkStartupOnboarding(
        activity: Activity,
        intent: Intent?,
        onInitializeAccepted: () -> Unit = onInitializeAcceptedExperience,
        onStop: () -> Unit = onStopVpn
    ): Boolean {
        currentWorkMode = WorkModeStore.getAppWorkMode(activity)
        hasSelectedWorkMode = WorkModeStore.hasSelectedWorkMode(activity)
        val isExistingUser = SystemSettingsStore.isInitialAgreementAccepted(activity) && hasSelectedWorkMode
        if (isExistingUser && !ModePermissionStore.isOnboardingCompleted(activity, currentWorkMode)) {
            AppWorkMode.entries.forEach { mode ->
                ModePermissionStore.setOnboardingCompleted(activity, mode, true)
            }
        }
        handleWorkModeChangeIntent(activity, intent, onInitializeAccepted, onStop)
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
        onInitializeAccepted: () -> Unit = onInitializeAcceptedExperience,
        onStop: () -> Unit = onStopVpn
    ) {
        if (intent?.getBooleanExtra(MainActivity.EXTRA_WORK_MODE_CHANGED, false) == true) {
            val targetModeStr = intent.getStringExtra(MainActivity.EXTRA_TARGET_WORK_MODE)
            val targetMode = targetModeStr?.let { runCatching { AppWorkMode.valueOf(it) }.getOrNull() }
                ?: WorkModeStore.getAppWorkMode(activity)
            intent.removeExtra(MainActivity.EXTRA_WORK_MODE_CHANGED)
            intent.removeExtra(MainActivity.EXTRA_TARGET_WORK_MODE)
            switchWorkMode(activity, targetMode, onInitializeAccepted, onStop)
        }
    }

    fun switchWorkMode(
        activity: Activity,
        selectedMode: AppWorkMode,
        onInitializeAccepted: () -> Unit = onInitializeAcceptedExperience,
        onStop: () -> Unit = onStopVpn
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
            onStop()
            VpnMonitorManager.stop(activity)
        } else if (selectedMode == AppWorkMode.EXPRESS) {
            ExpressModeLauncher.handleModeSelected(activity, selectedMode) {
                onInitializeAccepted()
            }
        } else {
            onInitializeAccepted()
        }
    }

    fun onAgreementAccepted(
        activity: Activity,
        onInitializeAccepted: () -> Unit = onInitializeAcceptedExperience
    ) {
        if (WorkModeStore.hasSelectedWorkMode(activity)) {
            val mode = WorkModeStore.getAppWorkMode(activity)
            if (!ModePermissionStore.isOnboardingCompleted(activity, mode)) {
                ModeOnboardingActivity.start(activity, mode, isFirstLaunch = true)
            } else {
                onInitializeAccepted()
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
        onInitializeAccepted: () -> Unit = onInitializeAcceptedExperience,
        onStop: () -> Unit = onStopVpn
    ) {
        handleWorkModeChangeIntent(activity, intent, onInitializeAccepted, onStop)
        hasSelectedWorkMode = WorkModeStore.hasSelectedWorkMode(activity)
        currentWorkMode = WorkModeStore.getAppWorkMode(activity)
    }

    fun syncOnResume(
        activity: Activity,
        onRefreshStatus: () -> Unit = onRefreshNormalStatus
    ) {
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
            onRefreshStatus()
        }
        VpnMonitorManager.sync(activity)
    }
}
