package com.haoze.diting.onboarding

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import com.haoze.diting.AppLocalizedActivity
import com.haoze.diting.MainActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.haoze.diting.permission.AppPermission
import com.haoze.diting.permission.ModePermissionStore
import com.haoze.diting.ui.AppThemeSurface
import com.haoze.diting.ui.PermissionDisclosureSettings
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.ui.mode.overrideFadeTransition
import com.haoze.diting.ui.mode.overrideOpenFadeTransition
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import com.haoze.diting.vpn.NetworkInfoProbe

/**
 * 独立的模式专属新手引导 Activity。
 *
 * 承载三步式向导的权限申请 Launcher、局域网 IP 探测以及流程流转，
 * 避免膨胀 MainActivity 与设置页，严格保持高内聚低耦合。
 */
class ModeOnboardingActivity : AppLocalizedActivity() {

    private val targetMode: AppWorkMode
        get() = intent.getStringExtra(EXTRA_MODE)?.let { runCatching { AppWorkMode.valueOf(it) }.getOrNull() }
            ?: WorkModeStore.getAppWorkMode(this)

    private val isFirstLaunch: Boolean
        get() = intent.getBooleanExtra(EXTRA_FIRST_LAUNCH, false)

    private val permissionStates = mutableStateMapOf<AppPermission, Boolean>()
    private var localIps by mutableStateOf<List<String>>(emptyList())

    private val vpnLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        refreshPermissionStates()
    }

    private val notificationLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {
        refreshPermissionStates()
    }

    private val genericSettingsLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        triggerAppListProbeAndRefresh()
    }

    private val appListPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ ->
        triggerAppListProbeAndRefresh()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        refreshPermissionStates()

        lifecycleScope.launch(Dispatchers.IO) {
            val ips = NetworkInfoProbe.probe(this@ModeOnboardingActivity)?.ipv4Addresses ?: emptyList()
            withContext(Dispatchers.Main) {
                localIps = ips
            }
        }

        setContent {
            val themeMode by remember { mutableStateOf(AppearanceSettingsStore.getAppThemeMode(this)) }
            val colorStyle by remember { mutableStateOf(AppearanceSettingsStore.getThemeColorStyle(this)) }
            val backgroundEnabled by remember { mutableStateOf(AppearanceSettingsStore.isCustomBackgroundEnabled(this)) }
            val backgroundUri by remember { mutableStateOf(AppearanceSettingsStore.getCustomBackgroundUri(this)) }

            AppThemeSurface(
                themeMode = themeMode,
                colorStyle = colorStyle,
                backgroundEnabled = backgroundEnabled,
                backgroundUri = backgroundUri,
                modifier = Modifier.fillMaxSize()
            ) {
                BackHandler {
                    finishAndReturnToMain(startService = false)
                }

                ModeOnboardingScreen(
                    mode = targetMode,
                    permissionStates = permissionStates,
                    localIps = localIps,
                    onGrantPermission = ::requestAppPermission,
                    onComplete = { startService ->
                        finishAndReturnToMain(startService)
                    },
                    onSkip = {
                        finishAndReturnToMain(startService = false)
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshPermissionStates()
    }

    private fun refreshPermissionStates() {
        AppPermission.entries.forEach { perm ->
            permissionStates[perm] = perm.isGranted(this)
        }
    }

    private fun triggerAppListProbeAndRefresh() {
        lifecycleScope.launch(Dispatchers.IO) {
            val isAccessible = AppPermission.isAppListAccessible(this@ModeOnboardingActivity)
            withContext(Dispatchers.Main) {
                if (isAccessible) {
                    PermissionDisclosureSettings.markAppListAvailable(this@ModeOnboardingActivity)
                }
                refreshPermissionStates()
            }
        }
    }

    private fun requestAppPermission(permission: AppPermission) {
        when (permission) {
            AppPermission.VPN -> {
                val prepareIntent = VpnService.prepare(this)
                if (prepareIntent != null) {
                    vpnLauncher.launch(prepareIntent)
                } else {
                    refreshPermissionStates()
                }
            }
            AppPermission.NOTIFICATION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    val intent = permission.createRequestIntent(this)
                    if (intent != null) {
                        genericSettingsLauncher.launch(intent)
                    }
                }
            }
            AppPermission.BATTERY_OPTIMIZATION -> {
                val intent = permission.createRequestIntent(this)
                if (intent != null) {
                    try {
                        genericSettingsLauncher.launch(intent)
                    } catch (_: ActivityNotFoundException) {
                        genericSettingsLauncher.launch(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    }
                }
            }
            AppPermission.SYSTEM_ALERT_WINDOW -> {
                val intent = permission.createRequestIntent(this)
                if (intent != null) {
                    genericSettingsLauncher.launch(intent)
                }
            }
            AppPermission.PACKAGE_QUERY -> {
                val alreadyExplained = PermissionDisclosureSettings.isAppListExplained(this)
                PermissionDisclosureSettings.setAppListExplained(this, true)
                if (alreadyExplained && !PermissionDisclosureSettings.wasAppListAvailable(this)) {
                    val intent = permission.createRequestIntent(this)
                    if (intent != null) {
                        try {
                            genericSettingsLauncher.launch(intent)
                            return
                        } catch (_: ActivityNotFoundException) {}
                    }
                }
                try {
                    appListPermissionLauncher.launch("com.android.permission.GET_INSTALLED_APPS")
                } catch (_: Exception) {
                    triggerAppListProbeAndRefresh()
                }
            }
        }
    }

    private fun finishAndReturnToMain(startService: Boolean) {
        ModePermissionStore.setOnboardingCompleted(this, targetMode, true)
        WorkModeStore.setAppWorkMode(this, targetMode)
        WorkModeStore.setWorkModeSelected(this, true)

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_WORK_MODE_CHANGED, true)
            putExtra(MainActivity.EXTRA_TARGET_WORK_MODE, targetMode.name)
            if (startService) {
                putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
            }
        }
        startActivity(intent)
        overrideFadeTransition()
        finish()
    }

    companion object {
        const val EXTRA_MODE = "extra_work_mode"
        const val EXTRA_FIRST_LAUNCH = "extra_first_launch"

        fun createIntent(context: Context, mode: AppWorkMode, isFirstLaunch: Boolean = false): Intent {
            return Intent(context, ModeOnboardingActivity::class.java).apply {
                putExtra(EXTRA_MODE, mode.name)
                putExtra(EXTRA_FIRST_LAUNCH, isFirstLaunch)
            }
        }

        fun start(context: Context, mode: AppWorkMode, isFirstLaunch: Boolean = false) {
            val intent = createIntent(context, mode, isFirstLaunch)
            context.startActivity(intent)
            (context as? Activity)?.overrideOpenFadeTransition()
        }
    }
}
