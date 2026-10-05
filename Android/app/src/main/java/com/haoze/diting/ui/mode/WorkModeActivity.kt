package com.haoze.diting.ui.mode

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.haoze.diting.AppLocalizedActivity
import com.haoze.diting.MainActivity
import com.haoze.diting.ui.AppThemeSurface
import com.haoze.diting.ui.settings.AppearanceSettingsStore

/**
 * Dedicated independent activity hosting [WorkModeSelectionScreen].
 *
 * Decouples work mode selection from both [MainActivity] and [com.haoze.diting.SettingsRouteActivity].
 * On mode transition completion, it returns directly to [MainActivity] with CLEAR_TOP and a seamless
 * crossfade, eliminating intermediate stack exposure.
 */
class WorkModeActivity : AppLocalizedActivity() {

    private val isFirstLaunch: Boolean
        get() = intent.getBooleanExtra(EXTRA_FIRST_LAUNCH, false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
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
                var selectedTargetMode by remember { mutableStateOf<AppWorkMode?>(null) }

                BackHandler {
                    if (isFirstLaunch) {
                        finishAffinity()
                    } else {
                        finishWithFade()
                    }
                }

                WorkModeSelectionScreen(
                    isFirstLaunch = isFirstLaunch,
                    currentMode = WorkModeStore.getAppWorkMode(this),
                    onBack = {
                        if (isFirstLaunch) {
                            finishAffinity()
                        } else {
                            finishWithFade()
                        }
                    },
                    onModeSelected = { mode ->
                        selectedTargetMode = mode
                        WorkModeStore.setAppWorkMode(this, mode)
                        WorkModeStore.setWorkModeSelected(this, true)
                    },
                    onTransitionFinished = {
                        val modeToReturn = selectedTargetMode ?: WorkModeStore.getAppWorkMode(this)
                        if (isFirstLaunch || !com.haoze.diting.permission.ModePermissionStore.isOnboardingCompleted(this, modeToReturn)) {
                            com.haoze.diting.onboarding.ModeOnboardingActivity.start(this, modeToReturn, isFirstLaunch = isFirstLaunch)
                            finish()
                            overrideFadeTransition()
                        } else {
                            returnToMainActivity(modeToReturn)
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }

    private fun returnToMainActivity(targetMode: AppWorkMode) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_WORK_MODE_CHANGED, true)
            putExtra(MainActivity.EXTRA_TARGET_WORK_MODE, targetMode.name)
        }
        startActivity(intent)
        overrideFadeTransition()
        finish()
    }

    private fun finishWithFade() {
        finish()
        overrideFadeTransition()
    }

    companion object {
        const val EXTRA_FIRST_LAUNCH = "extra_first_launch"

        fun createIntent(context: Context, isFirstLaunch: Boolean = false): Intent {
            return Intent(context, WorkModeActivity::class.java).apply {
                putExtra(EXTRA_FIRST_LAUNCH, isFirstLaunch)
            }
        }

        fun start(context: Context, isFirstLaunch: Boolean = false) {
            val intent = createIntent(context, isFirstLaunch)
            context.startActivity(intent)
            (context as? Activity)?.overrideOpenFadeTransition()
        }
    }
}
