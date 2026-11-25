package com.haoze.diting

import android.content.Intent
import com.haoze.diting.apps.AppsBridge
import com.haoze.diting.automation.AutomationBridge
import com.haoze.diting.cert.CaInspectionBridge
import com.haoze.diting.deeplink.DeepLinkBridge
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
import com.haoze.diting.platform.TroubleshootingLogBridge
import com.haoze.diting.platform.UpdateBridge
import com.haoze.diting.proxy.OutboundProxyBridge
import com.haoze.diting.root.RootDnsBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        const val EXTRA_AUTO_START_VPN = "auto_start_vpn"
    }

    private var vpnBridge: VpnBridge? = null
    private var expressVpnBridge: ExpressVpnBridge? = null
    private var platformBridge: PlatformBridge? = null
    private var backgroundBridge: BackgroundBridge? = null
    private var permissionsBridge: PermissionsBridge? = null
    private var deepLinkBridge: DeepLinkBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        LegacyPrefsBridge(applicationContext).register(messenger)
        vpnBridge = VpnBridge(this, messenger)
        expressVpnBridge = ExpressVpnBridge(this, messenger)
        ServerBridge(applicationContext, messenger).register()
        RootDnsBridge(applicationContext, messenger).register()
        RuleIndexBridge(applicationContext, messenger)
        RuleTestBridge(applicationContext, messenger)
        BlockPauseBridge(applicationContext, messenger)
        AutomationBridge(applicationContext, messenger)
        FlowViewBridge(applicationContext, messenger)
        NetworkProfileBridge(applicationContext, messenger)

        AppsBridge(applicationContext).register(messenger)
        CaInspectionBridge(applicationContext).register(messenger)
        OutboundProxyBridge(applicationContext).register(messenger)
        DiagnosticsBridge(applicationContext).register(messenger)

        DnsLatencyBridge(applicationContext).register(messenger)
        platformBridge = PlatformBridge(this).also { it.register(messenger) }
        UpdateBridge(this).register(messenger)
        backgroundBridge = BackgroundBridge(this).also { it.register(messenger) }
        permissionsBridge = PermissionsBridge(this).also { it.register(messenger) }
        TileBridge(this).register(messenger)
        deepLinkBridge = DeepLinkBridge(this).also { it.register(messenger) }
        LauncherIconBridge(this).register(messenger)
        RecognitionAvatarBridge(applicationContext).register(messenger)
        RuntimeLogBridge(applicationContext).register(messenger)
        RuntimeLogBridge.restore(applicationContext)
        TroubleshootingLogBridge(applicationContext).register(messenger)
        NotificationBridge(applicationContext).register(messenger)
        DbHealthBridge(applicationContext).register(messenger)
    }

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
        platformBridge?.reapplyRecentsPrivacy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLinkBridge?.handleNewIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (vpnBridge?.onActivityResult(requestCode, resultCode) == true) return
        if (platformBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        if (backgroundBridge?.onActivityResult(requestCode, resultCode, data) == true) return
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
