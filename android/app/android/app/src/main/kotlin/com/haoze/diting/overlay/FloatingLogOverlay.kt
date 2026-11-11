package com.haoze.diting.overlay

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log

/// Decides whether the floating log window is on screen; [FloatingLogWindow] draws it.
///
/// Shown only while the normal-mode tunnel runs, the app is in the background, the user enabled it
/// and the overlay permission is granted. "Hide" from the panel lasts until the app comes back to
/// the foreground. Every entry point hops to the main thread: callers include the VPN service's
/// teardown path, which is not guaranteed to run there.
object FloatingLogOverlay {
    private const val TAG = "FloatingLogOverlay"
    internal const val UI_PREFS = "dns_vpn_prefs"
    private const val KEY_ENABLED = "floating_log_enabled"

    private val main = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var vpnRunning = false

    /// False until MainActivity reports in: a tunnel started from the quick settings tile with no
    /// activity alive is a background session too.
    private var appForeground = false
    private var dismissed = false
    private var window: FloatingLogWindow? = null

    fun setVpnRunning(context: Context, running: Boolean) = post(context) {
        vpnRunning = running
        if (!running) dismissed = false
        sync()
    }

    fun setAppForeground(context: Context, foreground: Boolean) = post(context) {
        appForeground = foreground
        // Each background session starts visible again.
        if (foreground) dismissed = false
        sync()
    }

    /// "Hide for now" from the panel; posted, since it runs inside the window's own channel call.
    internal fun dismissForBackground() = main.post {
        dismissed = true
        sync()
    }

    private fun post(context: Context, block: () -> Unit) {
        val app = context.applicationContext
        main.post {
            appContext = app
            block()
        }
    }

    private fun sync() {
        val context = appContext ?: return
        val show = vpnRunning && !appForeground && !dismissed &&
            isEnabled(context) && canDrawOverlays(context)
        if (!show) {
            window?.destroy()
            window = null
            return
        }
        if (window != null) return
        val created = FloatingLogWindow(context)
        if (created.show()) {
            window = created
        } else {
            Log.w(TAG, "floating log window could not be shown")
        }
    }

    private fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)

    fun canDrawOverlays(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
}
