package com.haoze.diting.main

import android.app.Activity
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import com.haoze.diting.LogRouteActivity
import com.haoze.diting.SettingsRouteActivity
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.RecentsPrivacyController
import com.haoze.diting.ui.Routes
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeActivity
import com.haoze.diting.ui.mode.WorkModeStore

/**
 * Coordinates navigation routing and handles Activity results returned from settings and sub-screens.
 */
class MainNavigationCoordinator(
    private val activity: ComponentActivity,
    private val onRefreshRuntimeDns: () -> Unit,
    private val onThemeChanged: () -> Unit,
    private val onBackgroundChanged: () -> Unit,
    private val onBottomBarChanged: () -> Unit,
    private val onWorkModeChanged: (AppWorkMode) -> Unit
) {
    private var settingsLaunchInProgress = false

    private val settingsLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        settingsLaunchInProgress = false
        if (result.resultCode != Activity.RESULT_OK) return@registerForActivityResult
        result.data?.let { data ->
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_RUNTIME_DNS_CHANGED, false)) {
                onRefreshRuntimeDns()
            }
            if (data.hasExtra(SettingsRouteActivity.EXTRA_HIDE_FROM_RECENTS)) {
                RecentsPrivacyController.apply(
                    activity,
                    data.getBooleanExtra(SettingsRouteActivity.EXTRA_HIDE_FROM_RECENTS, false)
                )
            }
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_THEME_CHANGED, false)) {
                // The setting screen persists the value before returning.
                onThemeChanged()
            }
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_BACKGROUND_CHANGED, false)) {
                onBackgroundChanged()
            }
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_BOTTOM_BAR_CHANGED, false)) {
                onBottomBarChanged()
            }
            if (data.getBooleanExtra(SettingsRouteActivity.EXTRA_WORK_MODE_CHANGED, false)) {
                onWorkModeChanged(WorkModeStore.getAppWorkMode(activity))
            }
        }
    }

    fun launchSettings(route: String, dataset: RuleDataset? = null) {
        if (settingsLaunchInProgress) return
        settingsLaunchInProgress = true
        try {
            settingsLauncher.launch(SettingsRouteActivity.createIntent(activity, route, dataset = dataset))
        } catch (e: Throwable) {
            settingsLaunchInProgress = false
            throw e
        }
    }

    fun launchLogs(dataset: RuleDataset? = null) {
        launchLogRoute(Routes.LOG_DASHBOARD, dataset)
    }

    fun launchLogRoute(route: String, dataset: RuleDataset? = null) {
        activity.startActivity(LogRouteActivity.createIntent(activity, route, dataset = dataset))
    }

    fun launchModeSelection(isFirstLaunch: Boolean = false) {
        WorkModeActivity.start(activity, isFirstLaunch = isFirstLaunch)
    }
}
