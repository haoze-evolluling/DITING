package com.haoze.dnssr

import android.content.Context
import android.content.pm.ActivityInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import com.haoze.dnssr.ui.AppLanguageManager
import com.haoze.dnssr.util.DeviceScreenHelper

abstract class AppLocalizedActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppLanguageManager.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        applyOrientationPolicy()
        super.onCreate(savedInstanceState)
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
