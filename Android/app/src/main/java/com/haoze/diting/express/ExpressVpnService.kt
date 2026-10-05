package com.haoze.diting.express

import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.util.Log
import com.haoze.diting.crash.CrashBreadcrumbs
import com.haoze.diting.express.notification.ExpressNotificationBuilder
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.ui.PermissionDisclosureSettings
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.ui.settings.DnsCacheSettingsStore
import com.haoze.diting.ui.settings.ResolutionSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.vpn.DnsProtocol
import com.haoze.diting.vpn.DnsProvider
import com.haoze.diting.vpn.DnsVpnProviderResolver
import com.haoze.diting.vpn.FloatingLogOverlayController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.net.DatagramSocket
import java.net.Socket

/**
 * Pure Kotlin VpnService implementation dedicated to Express Mode.
 *
 * Implements narrow DNS TUN routing, public DNS hijacking, lightweight
 * DNS engine resolution, and independent foreground notifications.
 */
class ExpressVpnService : VpnService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val tunnelManager = ExpressTunnelManager()
    private lateinit var floatingLogOverlay: FloatingLogOverlayController

    private var startIntent: Intent? = null
    private var wasStopped = false
    private var activeProviders: List<DnsProvider> = emptyList()
    private var activeResolutionMode: DnsResolutionMode = DnsResolutionMode.SINGLE

    override fun onCreate() {
        super.onCreate()
        isServiceAlive = true
        activeService = this
        floatingLogOverlay = FloatingLogOverlayController(this)
        ExpressNotificationBuilder.ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ExpressVpnIntents.ACTION_STOP -> stopVpn()
            ExpressVpnIntents.ACTION_REFRESH_CONFIG -> refreshConfig(intent)
            ExpressVpnIntents.ACTION_SYNC_RULES -> tunnelManager.syncRules(serviceScope)
            ExpressVpnIntents.ACTION_CLEAR_CACHE -> tunnelManager.clearCache()
            ExpressVpnIntents.ACTION_REFRESH_FLOATING_LOG -> {
                if (::floatingLogOverlay.isInitialized) floatingLogOverlay.refreshSettings()
            }
            ExpressVpnIntents.ACTION_FLOATING_LOG_APP_STATE -> {
                val foreground = intent.getBooleanExtra(ExpressVpnIntents.EXTRA_APP_FOREGROUND, true)
                SystemSettingsStore.setMainActivityForeground(this, foreground)
                if (::floatingLogOverlay.isInitialized) floatingLogOverlay.setAppInForeground(foreground)
            }
            else -> startVpn(intent)
        }
        return START_STICKY
    }

    private fun startVpn(intent: Intent?) {
        if (tunnelManager.vpnInterface != null) {
            ExpressVpnController.onServiceStateChanged(this, true)
            return
        }
        startIntent = intent
        activeResolutionMode = ResolutionSettingsStore.getDnsResolutionMode(this)
        activeProviders = resolveActiveProviders(intent)

        CrashBreadcrumbs.record("ExpressVPN", "Starting Express VPN, mode=${activeResolutionMode.name}")

        val ipv6Mode = SystemSettingsStore.getIpv6Mode(this)
        val pfd = tunnelManager.establishVpnInterface(this, ipv6Mode) ?: run {
            Log.e(TAG, "Failed to establish VPN interface")
            PermissionDisclosureSettings.updateVpnGrant(this, false)
            ExpressVpnController.onServiceStateChanged(this, false)
            stopSelf()
            return
        }

        val started = tunnelManager.start(
            service = this,
            pfd = pfd,
            scope = serviceScope,
            providersProvider = { activeProviders },
            resolutionModeProvider = { activeResolutionMode },
            blockResponseModeProvider = { AppRulesSettingsStore.getBlockResponseMode(this) },
            domainRulesEnabledProvider = { AppRulesSettingsStore.isDomainRulesEnabled(this) },
            cachePolicyProvider = { DnsCacheSettingsStore.getDnsCachePolicy(this) },
            dnsLogModeProvider = { SystemSettingsStore.getDnsLogMode(this) }
        )
        if (!started) {
            Log.e(TAG, "Failed to start Express tunnel data plane")
            ExpressVpnController.onServiceStateChanged(this, false)
            stopSelf()
            return
        }

        updateForegroundNotification()
        floatingLogOverlay.setVpnRunning(true)
        ExpressVpnController.onServiceStateChanged(this, true)
    }

    private fun updateForegroundNotification() {
        val notification = ExpressNotificationBuilder.build(
            this,
            activeProviders,
            activeResolutionMode
        )
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForeground(
                        ExpressNotificationBuilder.NOTIFICATION_ID_EXPRESS_VPN,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                    )
                } else {
                    startForeground(
                        ExpressNotificationBuilder.NOTIFICATION_ID_EXPRESS_VPN,
                        notification
                    )
                }
            } else {
                startForeground(
                    ExpressNotificationBuilder.NOTIFICATION_ID_EXPRESS_VPN,
                    notification
                )
            }
        }
    }

    private fun refreshConfig(intent: Intent?) {
        activeResolutionMode = ResolutionSettingsStore.getDnsResolutionMode(this)
        activeProviders = resolveActiveProviders(intent)
        updateForegroundNotification()
    }

    private fun stopVpn() {
        CrashBreadcrumbs.record("ExpressVPN", "stopVpn called")
        wasStopped = true
        if (::floatingLogOverlay.isInitialized) floatingLogOverlay.setVpnRunning(false)
        ExpressVpnController.onServiceStateChanged(this, false)
        tunnelManager.stop()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onRevoke() {
        super.onRevoke()
        Log.w(TAG, "VPN permission revoked, stopping ExpressVpnService")
        PermissionDisclosureSettings.updateVpnGrant(this, false)
        wasStopped = false
        stopVpn()
    }

    override fun onDestroy() {
        CrashBreadcrumbs.record("ExpressVPN", "ExpressVpnService onDestroy")
        if (::floatingLogOverlay.isInitialized) floatingLogOverlay.destroy()
        isServiceAlive = false
        if (activeService === this) activeService = null
        ExpressVpnController.onServiceStateChanged(this, false)
        tunnelManager.stop()
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun resolveActiveProviders(intent: Intent?): List<DnsProvider> {
        val protocol = DnsProtocol.fromStorage(intent?.getStringExtra(ExpressVpnIntents.EXTRA_DNS_PROTOCOL))
        val url = intent?.getStringExtra(ExpressVpnIntents.EXTRA_DOH_URL)
        if (!url.isNullOrBlank()) {
            val name = intent.getStringExtra(ExpressVpnIntents.EXTRA_DNS_NAME)?.takeIf { it.isNotBlank() } ?: "自定义"
            return listOf(
                DnsProvider(
                    id = DnsVpnProviderResolver.runtimeCustomProviderId(url),
                    name = name,
                    protocol = DnsProtocol.DOH,
                    url = url,
                    isPreset = false
                )
            )
        }
        if (protocol == DnsProtocol.DOT || protocol == DnsProtocol.DNS) {
            val host = intent?.getStringExtra(ExpressVpnIntents.EXTRA_DNS_HOST)
            if (!host.isNullOrBlank()) {
                val port = intent.getIntExtra(ExpressVpnIntents.EXTRA_DNS_PORT, DnsProvider.DEFAULT_DOT_PORT)
                val name = intent.getStringExtra(ExpressVpnIntents.EXTRA_DNS_NAME)?.takeIf { it.isNotBlank() } ?: "自定义"
                return listOf(
                    DnsProvider(
                        id = DnsVpnProviderResolver.runtimeCustomProviderId("$host:$port"),
                        name = name,
                        protocol = protocol,
                        host = host,
                        port = port,
                        isPreset = false
                    )
                )
            }
        }
        val mode = ResolutionSettingsStore.getDnsResolutionMode(this)
        when (mode) {
            DnsResolutionMode.SINGLE -> Unit
            DnsResolutionMode.SMART_PREDICTION,
            DnsResolutionMode.PARALLEL_RACE -> {
                val ids = if (mode == DnsResolutionMode.SMART_PREDICTION) {
                    ResolutionSettingsStore.getSmartPredictionProviderIds(this)
                } else {
                    ResolutionSettingsStore.getParallelRaceProviderIds(this)
                }
                val raceProviders = DnsProvider.loadRuntimeProviders(this).filter { it.id in ids }
                if (raceProviders.size >= 2) return raceProviders
            }
            DnsResolutionMode.PRIMARY_BACKUP -> {
                val byId = DnsProvider.loadRuntimeProviders(this).associateBy { it.id }
                val ordered = ResolutionSettingsStore.getPrimaryBackupProviderIds(this).mapNotNull(byId::get)
                if (ordered.size >= 2) return ordered
            }
        }
        return listOf(DnsProvider.loadSelected(this))
    }

    companion object {
        private const val TAG = "ExpressVpnService"

        @Volatile
        var isServiceAlive: Boolean = false
            internal set

        @Volatile
        private var activeService: ExpressVpnService? = null

        fun protectSocket(socket: Socket): Boolean =
            activeService?.protect(socket) ?: false

        fun protectDatagramSocket(socket: DatagramSocket): Boolean =
            activeService?.protect(socket) ?: false

        fun protectFd(fd: Int): Boolean =
            activeService?.protect(fd) ?: false
    }
}
