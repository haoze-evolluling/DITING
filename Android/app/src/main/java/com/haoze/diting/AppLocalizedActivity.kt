package com.haoze.diting

import android.content.Context
import android.content.pm.ActivityInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import com.haoze.diting.ui.AppLanguageManager
import com.haoze.diting.ui.background.CustomBackgroundManager
import com.haoze.diting.util.DeviceScreenHelper

abstract class AppLocalizedActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppLanguageManager.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        applyOrientationPolicy()
        CustomBackgroundManager.ensureLoaded(this)
        CustomBackgroundManager.applyWindowBackground(this)
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        CustomBackgroundManager.applyWindowBackground(this)
    }

    /**
     * Orientation policy: phones are locked to portrait and cannot rotate to
     * landscape; tablets are left alone and may switch freely between portrait
     * and landscape (following the system auto-rotate setting).
     */
    private fun applyOrientationPolicy() {
        if (DeviceScreenHelper.isTabletDevice(this)) return
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }
}
