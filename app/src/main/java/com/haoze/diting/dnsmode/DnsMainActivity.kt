package com.haoze.diting.dnsmode

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
import com.haoze.diting.dnsmode.ui.DnsMainScreen
import com.haoze.diting.dnsmode.viewmodel.DnsMainViewModel
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        languageModeAtCreate = AppLanguageManager.getMode(this)
        enableEdgeToEdge()
        applyRecentsPrivacySetting()

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
        com.haoze.diting.ui.background.CustomBackgroundManager.applyWindowBackground(this)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
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
