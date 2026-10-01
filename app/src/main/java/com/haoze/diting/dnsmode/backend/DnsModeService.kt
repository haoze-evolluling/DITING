package com.haoze.diting.dnsmode.backend

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.net.wifi.WifiManager
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.haoze.diting.R
import com.haoze.diting.dnsmode.DnsMainActivity
import com.haoze.diting.ui.localizedText
import com.haoze.diting.vpn.DitingTileService

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class DnsModeService : Service() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var dnsServerEngine: DnsServerEngine? = null
    private var queryFilter: DnsQueryFilter? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // START_STICKY may restart this service in a fresh process without any Activity;
        // load persisted config here so the engine never runs on defaults.
        DnsModeManager.initialize(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_REFRESH -> {
                refreshNotification()
                refreshDnsEngine()
                ensureFilterLoaded()
                return START_STICKY
            }
            ACTION_START -> {
                startForegroundServiceInternal()
                if (dnsServerEngine?.isEngineRunning == true) {
                    // Service was already running (e.g. START_STICKY restart); rebuilding
                    // the engine would drop the cache and briefly release the port.
                    // Resync the manager status anyway, or a manager left in STARTING
                    // (e.g. after a failed stop) would disable the power button forever.
                    DnsModeManager.onServiceStarted()
                    return START_STICKY
                }
                startDnsEngine()
            }
            null -> {
                if (DnsModePreferences.isServiceActive(this)) {
                    startForegroundServiceInternal()
                    if (dnsServerEngine?.isEngineRunning != true) {
                        startDnsEngine()
                    }
                } else {
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopDnsEngine()
        releaseLocks()
        serviceScope.cancel()
        DnsModePreferences.setServiceActive(this, false)
        DnsModeManager.onServiceStopped()
        DitingTileService.requestTileUpdate(this)
        super.onDestroy()
    }

    private fun startDnsEngine() {
        acquireLocks()
        val config = DnsModeManager.config.value
        val upstream = DnsModeManager.getActiveUpstream()
        if (queryFilter == null) {
            queryFilter = DnsQueryFilter(this)
        }

        dnsServerEngine?.stop()
        val engine = DnsServerEngine(
            config = config,
            upstream = upstream,
            onQueryProcessed = { cacheHit, blocked, failed, latencyMs ->
                DnsModeManager.recordQuery(
                    cacheHit = cacheHit,
                    blocked = blocked,
                    failed = failed,
                    latencyMs = latencyMs
                )
            },
            queryFilter = queryFilter
        )

        if (engine.start()) {
            dnsServerEngine = engine
            DnsModeManager.onServiceStarted()
            ensureFilterLoaded()
            DitingTileService.requestTileUpdate(this)
            Log.i(TAG, "DnsModeService successfully started DNS server on port ${config.localListenPort}")
        } else {
            Log.e(TAG, "DnsModeService failed to start DNS server on port ${config.localListenPort}")
            DnsModeManager.onServiceError("DNS 服务启动失败，监听端口可能被占用")
            stopSelf()
        }
    }

    private fun refreshDnsEngine() {
        val engine = dnsServerEngine ?: return
        val config = DnsModeManager.config.value
        val upstream = DnsModeManager.getActiveUpstream()
        if (!engine.updateConfig(config, upstream)) {
            Log.e(TAG, "DNS engine stopped during config refresh (port change restart likely failed)")
            DnsModeManager.onServiceError("DNS 服务更新失败，监听端口可能被占用")
            stopSelf()
        } else {
            engine.syncRules()
        }
    }

    /**
     * Reloads the rule base on every start and every config refresh, so rule
     * edits made in the DNS mode rule screens apply on the next refresh
     * instead of waiting for a service restart. Rewrite (hosts) answers work
     * regardless of the filtering master switch, so rules load unconditionally;
     * blocking itself is gated in the engine.
     */
    private fun ensureFilterLoaded() {
        val filter = queryFilter ?: return
        serviceScope.launch {
            filter.reloadSync()
            dnsServerEngine?.syncRules()
        }
    }

    private fun stopDnsEngine() {
        dnsServerEngine?.stop()
        dnsServerEngine = null
    }

    private fun acquireLocks() {
        runCatching {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = powerManager?.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "Diting:DnsModeWakeLock"
                )?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            if (wifiLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                @Suppress("DEPRECATION")
                wifiLock = wifiManager?.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "Diting:DnsModeWifiLock"
                )?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        }.onFailure { Log.w(TAG, "Failed to acquire power/wifi locks", it) }
    }

    private fun releaseLocks() {
        runCatching {
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
            wifiLock?.let { if (it.isHeld) it.release() }
            wifiLock = null
        }.onFailure { Log.w(TAG, "Failed to release power/wifi locks", it) }
    }

    private fun startForegroundServiceInternal() {
        val notification = buildForegroundNotification()
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        }.onFailure {
            runCatching {
                startForeground(NOTIFICATION_ID, notification)
            }
        }
    }

    private fun refreshNotification() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildForegroundNotification())
    }

    private fun buildForegroundNotification(): Notification {
        val openAppIntent = Intent(this, DnsMainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, DnsModeService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val activeUpstream = DnsModeManager.getActiveUpstream()
        val contentText = localizedText(this, "当前上游") + ": " +
            localizedText(this, activeUpstream.name) +
            " (${activeUpstream.address})"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.dns_svgrepo_com)
            .setContentTitle(localizedText(this, "谛听 · DNS 模式运行中"))
            .setContentText(contentText)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                localizedText(this, "停止"),
                stopPendingIntent
            )
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(
                CHANNEL_ID,
                localizedText(this, "DNS 模式"),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = localizedText(this@DnsModeService, "显示 DNS 模式的运行状态")
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val TAG = "DnsModeService"
        private const val CHANNEL_ID = "channel_dns_mode"
        private const val NOTIFICATION_ID = 2002

        const val ACTION_START = "com.haoze.diting.dnsmode.START"
        const val ACTION_STOP = "com.haoze.diting.dnsmode.STOP"
        const val ACTION_REFRESH = "com.haoze.diting.dnsmode.REFRESH"

        fun startIntent(context: Context): Intent {
            return Intent(context, DnsModeService::class.java).apply {
                action = ACTION_START
            }
        }

        fun stopIntent(context: Context): Intent {
            return Intent(context, DnsModeService::class.java).apply {
                action = ACTION_STOP
            }
        }

        fun refreshIntent(context: Context): Intent {
            return Intent(context, DnsModeService::class.java).apply {
                action = ACTION_REFRESH
            }
        }
    }
}
