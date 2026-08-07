package com.haoze.dnssr.ui

import android.app.Activity
import android.app.ActivityManager
import android.os.Build

object RecentsPrivacyController {
    fun apply(activity: Activity, hideFromRecents: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.setRecentsScreenshotEnabled(!hideFromRecents)
        }
        activity.getSystemService(ActivityManager::class.java).appTasks.forEach { task ->
            runCatching { task.setExcludeFromRecents(hideFromRecents) }
        }
    }
}
