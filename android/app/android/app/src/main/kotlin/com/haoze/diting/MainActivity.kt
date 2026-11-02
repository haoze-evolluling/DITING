package com.haoze.diting

import android.content.Intent
import com.haoze.diting.apps.AppsBridge
import com.haoze.diting.cert.CaInspectionBridge
import com.haoze.diting.net.DiagnosticsBridge
import com.haoze.diting.net.DnsLatencyBridge
import com.haoze.diting.overlay.FloatingLogOverlay
import com.haoze.diting.platform.BackgroundBridge
import com.haoze.diting.platform.DbHealthBridge
import com.haoze.diting.platform.NotificationBridge
import com.haoze.diting.platform.PermissionsBridge
import com.haoze.diting.platform.PlatformBridge
import com.haoze.diting.platform.RecognitionAvatarBridge
import com.haoze.diting.platform.RuntimeLogBridge
import com.haoze.diting.platform.UpdateBridge
import com.haoze.diting.proxy.OutboundProxyBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        /// Set by the quick settings tile when it needs the app to start the data plane.
        const val EXTRA_AUTO_START_VPN = "auto_start_vpn"
    }

    private var vpnBridge: VpnBridge? = null
    private var expressVpnBridge: ExpressVpnBridge? = null
    private var platformBridge: PlatformBridge? = null
    private var backgroundBridge: BackgroundBridge? = null
    private var permissionsBridge: PermissionsBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        LegacyPrefsBridge(applicationContext).register(messenger)
        vpnBridge = VpnBridge(this, messenger)
        expressVpnBridge = ExpressVpnBridge(this, messenger)
        DnsServerBridge(applicationContext, messenger)
        RuleIndexBridge(applicationContext, messenger)

        AppsBridge(applicationContext).register(messenger)
        CaInspectionBridge(applicationContext).register(messenger)
        OutboundProxyBridge(applicationContext).register(messenger)
        DiagnosticsBridge(applicationContext).register(messenger)

        // Needs an Activity: starts intents and reaches ActivityManager.appTasks.
        DnsLatencyBridge(applicationContext).register(messenger)
        platformBridge = PlatformBridge(this).also { it.register(messenger) }
        UpdateBridge(this).register(messenger)
        backgroundBridge = BackgroundBridge(this).also { it.register(messenger) }
        permissionsBridge = PermissionsBridge(this).also { it.register(messenger) }
        TileBridge(this).register(messenger)
        RecognitionAvatarBridge(applicationContext).register(messenger)
        // Manual runtime-log capture: its own channel, so PlatformBridge stays crash-only.
        RuntimeLogBridge(applicationContext).register(messenger)
        // Notification repaints after a Dart-side settings edit: same reasoning.
        NotificationBridge(applicationContext).register(messenger)
        DbHealthBridge(applicationContext).register(messenger)
    }

    /// The floating log window only shows while the app is in the background.
    override fun onStart() {
        super.onStart()
        FloatingLogOverlay.setAppForeground(this, true)
    }

    override fun onStop() {
        FloatingLogOverlay.setAppForeground(this, false)
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        // Relaunching from the app icon recreates the task entry, resetting excludeFromRecents.
        platformBridge?.reapplyRecentsPrivacy()
    }

    /// `singleTop`: a tile tap reuses this instance, and only `setIntent` makes the new extra
    /// visible to `TileBridge`.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (vpnBridge?.onActivityResult(requestCode, resultCode) == true) return
        // Codes never collide with the VPN ones: this reads data.data, those read only resultCode.
        if (platformBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        if (backgroundBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        // Last, because it only claims its own codes and answers a pending request.
        if (permissionsBridge?.onActivityResult(requestCode, resultCode) == true) return
        expressVpnBridge?.onActivityResult(requestCode, resultCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionsBridge?.onRequestPermissionsResult(requestCode)
    }
}
