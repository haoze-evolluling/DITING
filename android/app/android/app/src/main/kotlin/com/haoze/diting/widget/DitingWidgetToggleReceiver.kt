package com.haoze.diting.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.haoze.diting.MainActivity
import com.haoze.diting.control.DataPlaneControl

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
                } else if (DataPlaneControl.toggle(context) == DataPlaneControl.Result.NeedsApp) {
                    openApp(context, requestStart = true)
                }
            } catch (error: Throwable) {
                Log.w(TAG, "Failed to toggle from widget", error)
            } finally {
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
