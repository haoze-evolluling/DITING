package com.haoze.diting.dnsmode

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.haoze.diting.AppLocalizedActivity
import com.haoze.diting.MainActivity
import com.haoze.diting.SettingsRouteActivity
import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.dnsmode.backend.DnsModePreferences
import com.haoze.diting.dnsmode.model.DnsServiceStatus
import com.haoze.diting.dnsmode.ui.DnsMainScreen
import com.haoze.diting.dnsmode.viewmodel.DnsMainViewModel
import com.haoze.diting.notification.NotificationPermissionHelper
import com.haoze.diting.ui.AppLanguageManager
import com.haoze.diting.ui.AppLanguageMode
import com.haoze.diting.ui.AppThemeSurface
import com.haoze.diting.ui.Routes
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.ui.settings.AppearanceSettingsStore

class DnsMainActivity : AppLocalizedActivity() {
    private var languageModeAtCreate = AppLanguageMode.SYSTEM
    private val viewModel: DnsMainViewModel by viewModels()
    private var appearanceRefreshVersion by mutableStateOf(0)
    private var batteryOptimizationIgnored by mutableStateOf(false)

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        languageModeAtCreate = AppLanguageManager.getMode(this)
        enableEdgeToEdge()
        applyRecentsPrivacySetting()
        requestNotificationPermissionIfNeeded()

        setContent {
            val themeMode = remember(appearanceRefreshVersion) { AppearanceSettingsStore.getAppThemeMode(this) }
            val colorStyle = remember(appearanceRefreshVersion) { AppearanceSettingsStore.getThemeColorStyle(this) }
            val backgroundEnabled = remember(appearanceRefreshVersion) { AppearanceSettingsStore.isCustomBackgroundEnabled(this) }
            val backgroundUri = remember(appearanceRefreshVersion) { AppearanceSettingsStore.getCustomBackgroundUri(this) }

            AppThemeSurface(
                themeMode = themeMode,
                colorStyle = colorStyle,
                backgroundEnabled = backgroundEnabled,
                backgroundUri = backgroundUri,
                modifier = Modifier.fillMaxSize()
            ) {
                DnsMainScreen(
                    viewModel = viewModel,
                    batteryOptimizationIgnored = batteryOptimizationIgnored,
                    onRequestIgnoreBatteryOptimization = ::requestIgnoreBatteryOptimization,
                    onSwitchToNormalMode = ::switchToNormalMode,
                    onSelectMode = ::openModeSelection
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (WorkModeStore.getAppWorkMode(this) != AppWorkMode.DNS) {
            switchToNormalMode()
            return
        }
        val currentLanguageMode = AppLanguageManager.getMode(this)
        if (currentLanguageMode != languageModeAtCreate) {
            languageModeAtCreate = currentLanguageMode
            recreate()
            return
        }
        applyRecentsPrivacySetting()
        appearanceRefreshVersion++
        batteryOptimizationIgnored = isBatteryOptimizationIgnored(this)
        com.haoze.diting.ui.background.CustomBackgroundManager.applyWindowBackground(this)

        if (DnsModePreferences.isServiceActive(this) && DnsModeManager.status.value == DnsServiceStatus.STOPPED) {
            DnsModeManager.startService(this)
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !NotificationPermissionHelper.hasPermission(this)
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun isBatteryOptimizationIgnored(context: Context): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        return powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
    }

    private fun requestIgnoreBatteryOptimization() {
        // The DNS service holds an unbounded wake lock, so aggressive battery
        // optimizations can kill the LAN resolver; guide the user to the
        // system whitelist.
        val requestIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = android.net.Uri.parse("package:$packageName")
        }
        try {
            startActivity(requestIntent)
        } catch (_: ActivityNotFoundException) {
            runCatching {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            }
        }
    }

    private fun applyRecentsPrivacySetting() {
        com.haoze.diting.ui.RecentsPrivacyController.apply(
            this,
            com.haoze.diting.ui.settings.SystemSettingsStore.isHideFromRecentsEnabled(this)
        )
    }

    private fun switchToNormalMode() {
        DnsModeManager.stopService(this)
        WorkModeStore.setAppWorkMode(this, AppWorkMode.NORMAL)
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        startActivity(intent)
        finish()
    }

    private fun openModeSelection() {
        val intent = SettingsRouteActivity.createIntent(this, Routes.WORK_MODE_SELECTION)
        startActivity(intent)
    }

    companion object {
        fun createIntent(context: Context): Intent {
            return Intent(context, DnsMainActivity::class.java)
        }
    }
}
