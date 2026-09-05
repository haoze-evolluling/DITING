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
     * 屏幕方向自适应：手机设备强制锁定竖屏，禁止横屏；
     * 平板设备不干预方向，允许横竖屏自由切换（跟随系统自动旋转设置）。
     */
    private fun applyOrientationPolicy() {
        if (DeviceScreenHelper.isTabletDevice(this)) return
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }
}
