package com.haoze.diting.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.haoze.diting.MainActivity
import com.haoze.diting.control.DataPlaneControl

/// Unexported receiver behind the widget's toggle button. Kept apart from the provider, which must
/// be exported for the system's update broadcasts, so no other app can flip the tunnel.
class DitingWidgetToggleReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_TOGGLE = "com.haoze.diting.widget.TOGGLE"
        private const val TAG = "DitingWidgetToggle"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE) return
        val pendingResult = goAsync()
        Thread {
            try {
                if (!DataPlaneControl.isAgreementAccepted(context)) {
                    openApp(context, requestStart = false)
                } else {
                    when (DataPlaneControl.toggle(context)) {
                        DataPlaneControl.Result.NeedsApp -> openApp(context, requestStart = true)
                        else -> Unit
                    }
                }
            } catch (error: Throwable) {
                Log.w(TAG, "Failed to toggle from widget", error)
            } finally {
                // Repaint even after a failed attempt: the state may have changed anyway.
                DitingWidgetProvider.requestRefresh(context)
                pendingResult?.finish()
            }
        }.start()
    }

    private fun openApp(context: Context, requestStart: Boolean) {
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (requestStart) putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
        }
        runCatching { context.startActivity(launch) }
            .onFailure { Log.w(TAG, "Failed to open app from widget", it) }
    }
}
