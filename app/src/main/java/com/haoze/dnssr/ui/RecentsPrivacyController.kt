package com.haoze.dnssr.ui

import android.app.Activity
import android.app.ActivityManager

object RecentsPrivacyController {
    fun apply(activity: Activity, hideFromRecents: Boolean) {
        activity.getSystemService(ActivityManager::class.java).appTasks.forEach { task ->
            runCatching { task.setExcludeFromRecents(hideFromRecents) }
        }
    }
}
