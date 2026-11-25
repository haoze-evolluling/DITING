package com.haoze.diting.vpn

import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import com.haoze.diting.engine.Engine
import com.haoze.diting.log.DnsLogWriter
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.LogRetention
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.log.TrafficRateMonitor
import com.haoze.diting.overlay.FloatingLogOverlay
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.watchdog.VpnReclaimer

/**
 * 普通模式与简洁模式共用的 VpnService。
 *
 * 子类只提供 [modeProfile]；普通模式建全隧道，简洁模式只把 DNS 查询路由进 TUN。
 * 规则库、日志库与偏好容器由 profile 注入，通知、回收与启停流程保持一致。
 */
internal abstract class FullTunnelVpnService : VpnService() {
    protected abstract fun modeProfile(): VpnModeProfile

    /** 惰性求值：抽象成员在构造期尚未由子类赋值。 */
    private val profile: VpnModeProfile by lazy(LazyThreadSafetyMode.NONE) { modeProfile() }

    private val runtime: VpnRuntime get() = profile.runtime

    private var tun: ParcelFileDescriptor? = null
    private var engine: Engine? = null
    private var dataPlane: EngineDataPlane? = null
    private var networkMonitor: UnderlyingNetworkMonitor? = null

    @Volatile
    private var worker: Thread? = null

    @Volatile
    private var stopping = false

    private val mainHandler = Handler(Looper.getMainLooper())

    private var tunnelGeneration = 0

    private val speedTicker by lazy {
        SpeedTicker(
            context = this,
            active = { runtime.isRunning && !stopping },
            onTick = { VpnModeNotification.refresh(this, profile) },
        )
    }

    private val reclaimer by lazy {
        VpnReclaimer(
            service = this,
            workMode = profile.workMode,
            modeTitle = profile.modeTitle,
            channelId = profile.channelId,
            notificationId = profile.notificationId,
            stopIntent = { VpnServiceApi.stopIntent(this, profile) },
            restoreIntent = { VpnServiceApi.restoreIntent(this, profile) },
            onWaitingChanged = { runtime.reclaiming = it },
            onGiveUp = { stopTunnel() },
        )
    }

    override fun onCreate() {
        super.onCreate()
        RuntimeEventLog.info(profile.eventDomain, "service.create")
        VpnServiceForeground.createChannel(
            this,
            profile.channelId,
            profile.channelName,
            profile.channelDescription,
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground()
        if (intent?.action == profile.reloadAction) {
            reloadRules()
            return START_NOT_STICKY
        }
        if (intent?.action == profile.stopAction) {
            stopTunnel()
            return START_NOT_STICKY
        }
        reclaimer.cancel()
        val dnsConfig = intent?.getStringExtra(VpnServiceApi.EXTRA_DNS_CONFIG)
        if (dnsConfig.isNullOrBlank()) {
            Log.w(profile.logTag, "start intent without DNS config")
            RuntimeEventLog.warn(profile.eventDomain, "start.no_config")
            stopTunnel()
            return START_NOT_STICKY
        }
        val defaults = VpnPlanNative.startDefaults
        val args = TunnelStartArgs(
            dnsConfig = dnsConfig,
            proxyJson = intent.getStringExtra(VpnServiceApi.EXTRA_OUTBOUND_PROXY).orEmpty(),
            proxyAppPackage = intent.getStringExtra(VpnServiceApi.EXTRA_PROXY_APP).orEmpty(),
            bypassLan = intent.getBooleanExtra(VpnServiceApi.EXTRA_BYPASS_LAN, defaults.bypassLan),
            ipv6Mode = Ipv6Mode.fromWire(
                intent.getStringExtra(VpnServiceApi.EXTRA_IPV6_MODE) ?: defaults.ipv6Mode,
            ).wire,
            routeAddress = intent
                .getStringArrayListExtra(VpnServiceApi.EXTRA_ROUTE_ADDRESS)
                .orEmpty()
                .toSet(),
            routeExcludeAddress = intent
                .getStringArrayListExtra(VpnServiceApi.EXTRA_ROUTE_EXCLUDE_ADDRESS)
                .orEmpty()
                .toSet(),
            excludedPackages = intent
                .getStringArrayListExtra(VpnServiceApi.EXTRA_EXCLUDED_PACKAGES)
                .orEmpty()
                .toSet(),
            blockedPackages = intent
                .getStringArrayListExtra(VpnServiceApi.EXTRA_BLOCKED_PACKAGES)
                .orEmpty()
                .toSet(),
            inspectionPackages = intent
                .getStringArrayListExtra(VpnServiceApi.EXTRA_INSPECTION_PACKAGES)
                .orEmpty()
                .toSet(),
            inspectionEnabled = intent.getBooleanExtra(
                VpnServiceApi.EXTRA_INSPECTION_ENABLED,
                defaults.inspectionEnabled,
            ),
        )
        profile.startConfig.remember(this, args)
        try {
            startTunnel(args)
        } catch (t: Throwable) {
            // onStartCommand 抛出的任何异常都会被 ActivityThread 升级成
            // “Unable to start service” 并直接杀进程，这里降级为受控的失败清理。
            Log.e(profile.logTag, "tunnel start failed", t)
            fail(tunnelGeneration, "隧道启动失败：${t.message ?: t.javaClass.simpleName}")
        }
        return START_NOT_STICKY
    }

    @Synchronized
    private fun startTunnel(args: TunnelStartArgs) {
        if (engine != null) {
            Log.i(profile.logTag, "tunnel already running; ignoring duplicate start")
            return
        }
        val generation = ++tunnelGeneration
        stopping = false
        runtime.lastError = null

        val clat = VpnRouteConfig.clatDetected(this)
        val ipv6 = Ipv6Policy.resolve(
            mode = Ipv6Mode.fromWire(args.ipv6Mode),
            hasRoutableIpv6 = Ipv6Policy.hasRoutableIpv6(this),
            clat = clat,
        )
        val established = VpnRouteConfig.establish(
            service = this,
            excludedPackages = args.excludedPackages,
            proxyPackage = args.proxyAppPackage.ifBlank { null },
            bypassPrivate = args.bypassLan,
            tunnelIpv6 = ipv6.tunnelIpv6,
            clat = clat,
            routeAddress = args.routeAddress,
            routeExcludeAddress = args.routeExcludeAddress,
            dnsOnly = profile.dnsOnly,
            logTag = profile.logTag,
        )
        val pfd = established.fd
        if (pfd == null) {
            fail(generation, "无法建立 VPN 接口")
            return
        }
        tun = pfd
        // 尽早固定 fd：之后任何并发清理（拓扑变化重建、旧会话异常退出）都可能关闭这个
        // PFD，那时再读 pfd.fd 会抛 IllegalStateException("Already closed") 并杀死进程。
        val tunFd = try {
            pfd.fd
        } catch (t: IllegalStateException) {
            fail(generation, "无法获取隧道文件描述符：${t.message ?: t.javaClass.simpleName}")
            return
        }
        val blockIpv6 = ipv6.blockIpv6 && !established.clatOnly

        val rustEngine = try {
            Engine()
        } catch (t: Throwable) {
            Log.e(profile.logTag, "Unable to load the engine", t)
            RuntimeEventLog.error(
                profile.eventDomain,
                "engine.load_fail",
                "error" to (t.message ?: t.javaClass.simpleName),
            )
            releaseResources()
            fail(generation, "引擎加载失败：${t.message ?: t.javaClass.simpleName}")
            return
        }
        engine = rustEngine
        runtime.engine = rustEngine

        try {
            val logMode = getSharedPreferences(profile.settingsPrefs, MODE_PRIVATE)
                .getString(KEY_LOG_MODE, DnsLogWriter.MODE_ALL)
                ?: DnsLogWriter.MODE_ALL
            // https_bypass_rules 是全局 UI 设置，两种模式共用 dns_vpn_prefs；
            // 只有 dns_log_mode 等模式级设置走 profile.settingsPrefs。
            val httpsBypassRules = getSharedPreferences(VpnRuntime.NORMAL_PREFS, MODE_PRIVATE)
                .getStringSet(KEY_HTTPS_BYPASS_RULES, null)
                .orEmpty()
            dataPlane = FullTunnelEngineConfig.configure(
                context = this,
                dataset = profile.dataset,
                engine = rustEngine,
                args = args,
                blockIpv6 = blockIpv6,
                preferIpv6 = ipv6.preferIpv6,
                logMode = logMode,
                httpsBypassRules = httpsBypassRules,
                dnsOnly = profile.dnsOnly,
                logTag = profile.logTag,
            )
        } catch (t: Throwable) {
            Log.e(profile.logTag, "Unable to configure the engine", t)
            RuntimeEventLog.error(
                profile.eventDomain,
                "engine.config_fail",
                "error" to (t.message ?: t.javaClass.simpleName),
            )
            releaseResources()
            fail(generation, "隧道配置失败：${t.message ?: t.javaClass.simpleName}")
            return
        }

        networkMonitor = UnderlyingNetworkMonitor(this, this) { state ->
            state.applyTo(rustEngine)
        }.also { it.start() }

        runtime.isRunning = true
        runtime.startedAt = System.currentTimeMillis()
        runtime.setPersistedRunning(this, true)
        if (!profile.dnsOnly) speedTicker.start()
        FloatingLogOverlay.setVpnRunning(this, true)
        LogRetention.start(
            context = this,
            databaseName = profile.dataset.logsDatabase(),
            prefsName = profile.settingsPrefs,
            includeHttpAndTraffic = !profile.dnsOnly,
        )
        worker = TunnelRunner.start(
            context = this,
            engine = rustEngine,
            dataset = profile.dataset,
            eventDomain = profile.eventDomain,
            threadName = profile.tunnelThreadName,
            logTag = profile.logTag,
            tunFd = tunFd,
            protect = { fd -> this.protect(fd) },
            isStopping = { stopping },
            onFatal = { fail(generation, it) },
        )
    }

    private fun reloadRules() {
        val current = engine
        if (current == null || !runtime.isRunning) {
            Log.i(profile.logTag, "rule reload requested but the tunnel is not running")
            return
        }
        TunnelRunner.reload(
            context = this,
            engine = current,
            dataset = profile.dataset,
            eventDomain = profile.eventDomain,
            threadName = profile.reloadThreadName,
            logTag = profile.logTag,
            isStopping = { stopping },
        )
    }

    @Synchronized
    private fun stopTunnel() {
        reclaimer.cancel()
        stopping = true
        val generation = tunnelGeneration
        val current = engine
        val plane = dataPlane
        val currentTun = tun
        engine = null
        runtime.engine = null
        dataPlane = null
        tun = null
        runtime.isRunning = false
        runtime.startedAt = 0L
        FloatingLogOverlay.setVpnRunning(this, false)
        Thread({
            releaseTunnel(current, plane)
            runCatching { currentTun?.close() }
            mainHandler.post {
                if (generation != tunnelGeneration) return@post
                releaseResources()
                runtime.setPersistedRunning(this@FullTunnelVpnService, false)
                VpnServiceForeground.stop(this@FullTunnelVpnService)
                stopSelf()
            }
        }, profile.teardownThreadName).start()
    }

    @Synchronized
    private fun teardown() {
        stopping = true
        val current = engine
        val plane = dataPlane
        engine = null
        runtime.engine = null
        dataPlane = null
        releaseTunnel(current, plane)
        releaseResources()
        runtime.isRunning = false
        runtime.startedAt = 0L
        FloatingLogOverlay.setVpnRunning(this, false)
    }

    private fun releaseTunnel(engine: Engine?, plane: EngineDataPlane?) {
        runCatching { engine?.stop() }
            .onFailure { Log.w(profile.logTag, "engine.stop failed", it) }
        runCatching { engine?.stopStackMitm() }
        runCatching { engine?.releaseTun() }
        runCatching { plane?.close() }
    }

    private fun closeDataPlane() {
        val plane = dataPlane
        dataPlane = null
        runCatching { plane?.close() }
    }

    private fun releaseResources() {
        networkMonitor?.stop()
        networkMonitor = null
        runCatching { tun?.close() }
        tun = null
        worker = null
        speedTicker.stop()
        FloatingLogOverlay.setVpnRunning(this, false)
        TrafficRateMonitor.reset()
        LogRetention.stop()
    }

    /**
     * 失败清理只对发起失败的那一代会话生效。
     *
     * 旧会话的隧道线程可能在新的 startTunnel 已经换上新 fd 之后才报错回调；
     * 若不加代际校验，这里会关掉新会话的 PFD，让启动流程读到已关闭的描述符。
     */
    @Synchronized
    private fun fail(generation: Int, message: String) {
        if (generation != tunnelGeneration) {
            Log.i(profile.logTag, "ignoring failure from a stale tunnel generation")
            return
        }
        RuntimeEventLog.error(profile.eventDomain, "tunnel.fail", "message" to message)
        runtime.lastError = message
        runtime.isRunning = false
        runtime.startedAt = 0L
        runtime.engine = null
        closeDataPlane()
        runtime.setPersistedRunning(this, false)
        releaseResources()
        VpnServiceForeground.stop(this)
        stopSelf()
    }

    override fun onRevoke() {
        RuntimeEventLog.warn(profile.eventDomain, "revoked")
        if (reclaimer.shouldFollow()) {
            Log.w(profile.logTag, "VPN revoked; waiting for the slot to free up")
            teardown()
            QuickSettingsTileUpdater.requestTileUpdate(this)
            reclaimer.begin()
            return
        }
        Log.w(profile.logTag, "VPN permission revoked")
        stopTunnel()
        super.onRevoke()
    }

    override fun onDestroy() {
        RuntimeEventLog.info(profile.eventDomain, "service.destroy")
        reclaimer.cancel()
        if (engine != null || runtime.isRunning || dataPlane != null) {
            teardown()
            runtime.setPersistedRunning(this, false)
            VpnServiceForeground.stop(this)
        }
        super.onDestroy()
    }

    private fun promoteToForeground() {
        val error = VpnServiceForeground.promote(
            this,
            profile.notificationId,
            VpnModeNotification.build(this, profile),
        ) ?: return
        Log.e(profile.logTag, "startForeground failed", error)
        RuntimeEventLog.error(
            profile.eventDomain,
            "foreground.fail",
            "error" to (error.message ?: error.javaClass.simpleName),
        )
    }

    private companion object {
        const val KEY_LOG_MODE = "dns_log_mode"

        const val KEY_HTTPS_BYPASS_RULES = "https_bypass_rules"
    }
}
