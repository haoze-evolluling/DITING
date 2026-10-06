package com.haoze.diting.main

import android.app.Activity
import android.widget.Toast
import com.haoze.diting.core.rule.DefaultWhitelistSeeder
import com.haoze.diting.core.rule.SubscriptionAutoUpdateScheduler
import com.haoze.diting.crash.CrashLogManager
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.notification.AppNotificationChannels
import com.haoze.diting.notification.VpnMonitorManager
import com.haoze.diting.ui.AppSettings
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.ui.showToast
import com.haoze.diting.update.AppUpdateHost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Coordinates initial startup checks, experience bootstrapping, and application maintenance.
 */
class MainStartupCoordinator {
    private var acceptedExperienceInitialized = false

    fun performStartupChecks(activity: Activity) {
        AppSettings.performStartupSelfCheck(activity)
        if (CrashLogManager.consumePendingAutoExportNotice(activity)) {
            activity.showToast("软件连续异常退出，崩溃日志已自动备份至系统“下载”目录", Toast.LENGTH_LONG)
        }
    }

    fun initializeAcceptedExperience(
        activity: Activity,
        lifecycleScope: CoroutineScope,
        appUpdateHost: AppUpdateHost,
        onAutoStartVpn: () -> Unit
    ) {
        if (acceptedExperienceInitialized) return
        acceptedExperienceInitialized = true
        AppNotificationChannels.createAllChannels(activity)
        SubscriptionAutoUpdateScheduler.sync(activity)
        if (!SystemSettingsStore.isStartupUpdateCheckDisabled(activity)) {
            appUpdateHost.checkForUpdate(manual = false)
        }
        lifecycleScope.launch {
            delay(DATABASE_WARMUP_DELAY_MS)
            withContext(Dispatchers.IO) {
                runCatching {
                    val db = AppDatabase.getInstance(activity.applicationContext)
                    db.openHelper.writableDatabase
                    DefaultWhitelistSeeder.ensureInitialized(activity.applicationContext, db)
                }
            }
        }
        onAutoStartVpn()
        VpnMonitorManager.sync(activity)
    }

    fun declineInitialAgreement(
        activity: Activity,
        onStopVpn: () -> Unit
    ) {
        onStopVpn()
        VpnMonitorManager.stop(activity)
        activity.finishAndRemoveTask()
    }

    companion object {
        const val DATABASE_WARMUP_DELAY_MS = 500L
    }
}
