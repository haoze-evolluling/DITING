package com.haoze.diting

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.haoze.diting.control.DataPlaneControl

/// Headless entry point for Tasker / MacroDroid / adb: starting it with one of the exported actions
/// starts, stops or toggles whichever data plane the current work mode uses, then finishes.
///
/// Mirrors FlClash's `QuickActionActivity`. Anything it cannot do alone (agreement not accepted,
/// VPN consent missing, no saved start config) opens the app instead of failing silently.
class QuickActionActivity : Activity() {

    companion object {
        const val ACTION_START = "com.haoze.diting.action.START"
        const val ACTION_STOP = "com.haoze.diting.action.STOP"
        const val ACTION_TOGGLE = "com.haoze.diting.action.TOGGLE"
        private const val TAG = "QuickActionActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handle(intent)
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        val action = intent?.action ?: return
        if (action != ACTION_START && action != ACTION_STOP && action != ACTION_TOGGLE) return
        if (!DataPlaneControl.isAgreementAccepted(this)) {
            openApp(requestStart = false)
            return
        }
        val result = when (action) {
            ACTION_START -> DataPlaneControl.start(this)
            ACTION_STOP -> DataPlaneControl.stop(this)
            else -> DataPlaneControl.toggle(this)
        }
        if (result == DataPlaneControl.Result.NeedsApp && action != ACTION_STOP) {
            openApp(requestStart = true)
        }
    }

    private fun openApp(requestStart: Boolean) {
        val launch = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (requestStart) putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
        }
        runCatching { startActivity(launch) }
            .onFailure { Log.w(TAG, "Failed to open app from quick action", it) }
    }
}
