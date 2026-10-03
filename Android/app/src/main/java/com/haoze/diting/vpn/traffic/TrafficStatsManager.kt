package com.haoze.diting.vpn.traffic

import android.content.Context
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.max

/**
 * Main coordinator for VPN traffic statistics, tracking session & daily byte totals,
 * estimating real-time bandwidth speeds, and publishing UI snapshots.
 */
object TrafficStatsManager {
    private const val TAG = "TrafficStatsManager"

    // Go tunnel mode runs no fixed Kotlin heartbeat: EMA decay is driven by a
    // lazy watchdog that exits once all speeds reach zero, so idle periods
    // cause zero wakeups.
    private const val GO_DECAY_WATCHDOG_INTERVAL_MS = 1_000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var sampleJob: Job? = null
    private var goDecayJob: Job? = null
    private var flushJob: Job? = null

    @Volatile
    private var isRunning = false
    @Volatile
    private var isGoTunnel = false
    @Volatile
    private var screenInteractive = true

    private val lastGoTickTimeMs = AtomicLong(0L)

    private val sessionStartTime = AtomicLong(0L)
    private val sessionTxTotal = AtomicLong(0L)
    private val sessionRxTotal = AtomicLong(0L)
    private val sessionAppBytes = ConcurrentHashMap<String, AppByteCounters>()

    private val detailedSubscribersCount = AtomicInteger(0)

    private val appResolver = TrafficAppResolver()
    private val speedEstimator = TrafficSpeedEstimator()
    private val dbSyncer = TrafficDatabaseSyncer()
    private val kernelSampler = KernelTrafficSampler()

    private val _uiSnapshot = MutableStateFlow(TrafficStatsUiSnapshot())
    val uiSnapshot: StateFlow<TrafficStatsUiSnapshot> = _uiSnapshot.asStateFlow()

    private var applicationContext: Context? = null

    fun registerDetailedConsumer() {
        if (detailedSubscribersCount.incrementAndGet() == 1) {
            publishSnapshot()
        }
    }

    fun unregisterDetailedConsumer() {
        detailedSubscribersCount.decrementAndGet()
    }

    fun getAppStatsList(): List<AppTrafficItem> = buildAppStatsList()

    fun refreshAppList(context: Context) {
        appResolver.refreshAppList(context)
    }

    @Synchronized
    fun start(context: Context, isGoTunnelActive: Boolean) {
        val appContext = context.applicationContext
        applicationContext = appContext
        dbSyncer.resetTodayDate()
        isRunning = true
        isGoTunnel = isGoTunnelActive
        sessionStartTime.set(System.currentTimeMillis())
        sessionTxTotal.set(0L)
        sessionRxTotal.set(0L)
        lastGoTickTimeMs.set(System.currentTimeMillis())

        sessionAppBytes.clear()
        speedEstimator.clear()

        // The restartVpnLocked path can call start() again without a stop()
        // in between; clear the previous session's watchdog.
        goDecayJob?.cancel()
        goDecayJob = null

        scope.launch(Dispatchers.IO) {
            appResolver.refreshAppList(appContext)
            if (!isGoTunnelActive) {
                kernelSampler.initBaseline(appResolver.getAllAppInfos())
            }
            dbSyncer.initTodayFromDb(appContext)

            publishSnapshot()
        }

        if (!isGoTunnelActive) {
            startSamplingLoop(appContext)
        }
        startFlushLoop(appContext)

        publishSnapshot()
        Log.i(TAG, "TrafficStatsManager started (GoTunnel=$isGoTunnelActive)")
    }

    @Synchronized
    fun stop(context: Context) {
        isRunning = false
        sampleJob?.cancel()
        sampleJob = null
        goDecayJob?.cancel()
        goDecayJob = null
        flushJob?.cancel()
        flushJob = null

        // Bounded synchronous flush: main-thread blocking capped at 500ms, the
        // DB write is abandoned on timeout. Losses are bounded by the 15s
        // periodic flush / 1MB threshold, and today's totals are anchored by
        // data already persisted in the DB.
        runBlocking {
            withTimeoutOrNull(TrafficDatabaseSyncer.FLUSH_STOP_TIMEOUT_MS) {
                dbSyncer.flushPendingDeltas(context.applicationContext)
            }
        }
        // force: propagate isRunning=false to collectors even while the screen
        // is off; otherwise, stopping the VPN during off-screen time leaves
        // the UI stuck on a stale "running" snapshot.
        publishSnapshot(force = true)
        Log.i(TAG, "TrafficStatsManager stopped")
    }

    /**
     * Screen state is driven by the SCREEN_ON/SCREEN_OFF broadcasts from
     * [DnsVpnService]. While the screen is off, sampling keeps accumulating
     * counters but snapshot publishing is skipped (saves allocations and emissions).
     */
    fun setScreenInteractive(interactive: Boolean) {
        val changed = screenInteractive != interactive
        screenInteractive = interactive
        if (!changed || !interactive) return
        // The watchdog exited during off-screen time: on screen-on, if there
        // is residual non-zero speed (traffic cut off before screen off),
        // restart the decay and publish once to restore the speed display in
        // the UI and notification.
        if (isRunning && speedEstimator.hasNonZeroSpeed()) {
            ensureGoDecayWatchdog()
        }
        publishSnapshot()
    }

    fun onGoTrafficTick(jsonDeltas: String) {
        if (!isRunning || !isGoTunnel || jsonDeltas.isBlank()) return
        try {
            val rolloverContext = applicationContext
            if (rolloverContext != null && dbSyncer.isDateRolloverNeeded()) {
                scope.launch { dbSyncer.checkDateRollover(rolloverContext) }
            }

            val array = JSONArray(jsonDeltas)
            var totalTxDelta = 0L
            var totalRxDelta = 0L
            val tickTime = System.currentTimeMillis()

            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val uid = obj.getInt("uid")
                val tx = obj.getLong("tx")
                val rx = obj.getLong("rx")
                if (tx > 0 || rx > 0) {
                    val appInfo = applicationContext?.let { appResolver.getOrResolveAppInfo(it, uid) }
                    if (appInfo != null) {
                        recordAppTraffic(appInfo, tx, rx)
                        totalTxDelta += tx
                        totalRxDelta += rx
                    }
                }
            }

            // EMA compensates with the actual tick interval: aggregated
            // off-screen ticks (e.g. one every 10s) do not distort the speed
            // once sampling resumes.
            val lastTick = lastGoTickTimeMs.getAndSet(tickTime)
            val elapsedSeconds = if (lastTick > 0) max(0.2, (tickTime - lastTick) / 1000.0) else 1.0
            speedEstimator.updateSpeedEma(totalTxDelta, totalRxDelta, elapsedSeconds)
            ensureGoDecayWatchdog()
            publishSnapshot()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse Go traffic tick: ${e.message}")
        }
    }

    /**
     * Lazy decay watchdog for Go tunnel mode: only while a non-zero speed
     * exists (i.e. traffic was seen recently) and the screen is on, it decays
     * the EMA and publishes a snapshot every 1s; it exits on its own once
     * everything reaches zero or the screen turns off, producing zero wakeups
     * during idle/off-screen periods.
     */
    private fun ensureGoDecayWatchdog() {
        synchronized(this) {
            if (!screenInteractive) return
            if (goDecayJob?.isActive == true) return
            goDecayJob = scope.launch {
                while (isActive && isRunning) {
                    delay(GO_DECAY_WATCHDOG_INTERVAL_MS)
                    if (!isRunning || !screenInteractive) break
                    speedEstimator.decayIdleSpeeds()
                    publishSnapshot()
                    if (!speedEstimator.hasNonZeroSpeed()) break
                }
            }
        }
    }

    private fun startSamplingLoop(context: Context) {
        sampleJob?.cancel()
        sampleJob = scope.launch {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            var lastSampleTime = System.currentTimeMillis()
            var idleCycles = 0

            while (isActive && isRunning) {
                val isScreenOn = powerManager?.isInteractive ?: true
                val intervalMs = kernelSampler.calculateBackoffInterval(idleCycles, isScreenOn)
                delay(intervalMs)

                if (!isRunning) break

                val now = System.currentTimeMillis()
                val elapsedSeconds = max(0.2, (now - lastSampleTime) / 1000.0)
                lastSampleTime = now

                dbSyncer.checkDateRollover(context)

                val (txDelta, rxDelta) = kernelSampler.sampleTraffic(
                    appInfos = appResolver.getAllAppInfos(),
                    onAppDelta = { appInfo, deltaTx, deltaRx ->
                        recordAppTraffic(appInfo, deltaTx, deltaRx)
                        speedEstimator.updateSingleAppSpeedEma(appInfo.packageName, deltaTx, deltaRx, elapsedSeconds)
                    },
                    onAppIdle = { pkg ->
                        speedEstimator.decaySingleAppSpeed(pkg, elapsedSeconds)
                    }
                )

                speedEstimator.updateSpeedEma(txDelta, rxDelta, elapsedSeconds)
                val hadTraffic = txDelta > 0 || rxDelta > 0
                idleCycles = if (hadTraffic) 0 else idleCycles + 1

                if (isScreenOn) {
                    publishSnapshot()
                }
            }
        }
    }

    private fun startFlushLoop(context: Context) {
        flushJob?.cancel()
        flushJob = scope.launch {
            while (isActive && isRunning) {
                delay(TrafficDatabaseSyncer.BATCH_FLUSH_INTERVAL_MS)
                if (!isRunning) break
                dbSyncer.checkDateRollover(context)
                dbSyncer.flushPendingDeltas(context)
            }
        }
    }

    private fun recordAppTraffic(appInfo: CachedAppInfo, txDelta: Long, rxDelta: Long) {
        sessionTxTotal.addAndGet(txDelta)
        sessionRxTotal.addAndGet(rxDelta)

        val sessionCounters = sessionAppBytes.getOrPut(appInfo.packageName) { AppByteCounters() }
        sessionCounters.tx.addAndGet(txDelta)
        sessionCounters.rx.addAndGet(rxDelta)

        val thresholdExceeded = dbSyncer.recordDelta(appInfo.packageName, appInfo.appName, txDelta, rxDelta)
        if (thresholdExceeded) {
            scope.launch { dbSyncer.flushPendingDeltas(applicationContext) }
        }
    }

    suspend fun flush(context: Context) {
        dbSyncer.flushPendingDeltas(context)
    }

    /**
     * Clears all in-memory app traffic accumulators, the pending DB delta
     * buffer, and the live statistics state, then force-publishes an all-zero snapshot.
     */
    @Synchronized
    fun clearAllTrafficStats(context: Context? = null) {
        dbSyncer.clear()
        sessionAppBytes.clear()
        sessionTxTotal.set(0L)
        sessionRxTotal.set(0L)
        speedEstimator.clear()

        val appContext = context?.applicationContext ?: applicationContext
        if (appContext != null && isRunning && !isGoTunnel) {
            kernelSampler.initBaseline(appResolver.getAllAppInfos())
        }

        publishSnapshot(force = true)
    }

    private fun publishSnapshot(force: Boolean = false) {
        if (!force && !screenInteractive) return

        val txSpeed = speedEstimator.currentTotalTxSpeedBps
        val rxSpeed = speedEstimator.currentTotalRxSpeedBps
        val sessionTx = sessionTxTotal.get()
        val sessionRx = sessionRxTotal.get()
        val startMs = sessionStartTime.get()
        val sumTodayTx = dbSyncer.currentTodayTxTotal
        val sumTodayRx = dbSyncer.currentTodayRxTotal

        val needsAppList = detailedSubscribersCount.get() > 0
        val appList = if (needsAppList) buildAppStatsList() else emptyList()

        // No-change fast path: skip the StateFlow write to avoid needless collector recompositions
        val prev = _uiSnapshot.value
        if (prev.isRunning == isRunning &&
            prev.isGoTunnelActive == isGoTunnel &&
            prev.totalTxSpeedBps == txSpeed &&
            prev.totalRxSpeedBps == rxSpeed &&
            prev.sessionTxBytes == sessionTx &&
            prev.sessionRxBytes == sessionRx &&
            prev.sessionStartTimeMs == startMs &&
            prev.todayTxBytes == sumTodayTx &&
            prev.todayRxBytes == sumTodayRx &&
            (!needsAppList || prev.appStatsList == appList)
        ) {
            return
        }

        _uiSnapshot.value = TrafficStatsUiSnapshot(
            isRunning = isRunning,
            isGoTunnelActive = isGoTunnel,
            totalTxSpeedBps = txSpeed,
            totalRxSpeedBps = rxSpeed,
            sessionTxBytes = sessionTx,
            sessionRxBytes = sessionRx,
            todayTxBytes = sumTodayTx,
            todayRxBytes = sumTodayRx,
            sessionStartTimeMs = startMs,
            appStatsList = appList,
            updatedAt = System.currentTimeMillis()
        )
    }

    private fun buildAppStatsList(): List<AppTrafficItem> {
        val appList = mutableListOf<AppTrafficItem>()

        val allPackages = HashSet<String>()
        allPackages.addAll(sessionAppBytes.keys)
        allPackages.addAll(dbSyncer.todayPackages)
        allPackages.addAll(speedEstimator.activeAppPackages)

        val context = applicationContext
        for (pkg in allPackages) {
            val info = appResolver.getAppInfo(pkg)
            if (info == null && context != null) {
                appResolver.schedulePackageLookup(context, pkg, scope) {
                    if (screenInteractive && isRunning) {
                        publishSnapshot()
                    }
                }
            }
            val appName = info?.appName ?: pkg
            val isSys = info?.isSystemApp ?: SystemAppClassifier.isKnownSystemPackagePrefix(pkg)

            val session = sessionAppBytes[pkg]
            val sTx = session?.tx?.get() ?: 0L
            val sRx = session?.rx?.get() ?: 0L

            val today = dbSyncer.getTodayCounters(pkg)
            val tTx = today?.tx?.get() ?: 0L
            val tRx = today?.rx?.get() ?: 0L

            val speed = speedEstimator.getAppSpeed(pkg)
            val speedTx = (speed?.txSpeed ?: 0.0).toLong()
            val speedRx = (speed?.rxSpeed ?: 0.0).toLong()

            if (sTx > 0 || sRx > 0 || tTx > 0 || tRx > 0 || speedTx > 0 || speedRx > 0) {
                appList.add(
                    AppTrafficItem(
                        packageName = pkg,
                        appName = appName,
                        isSystemApp = isSys,
                        sessionTxBytes = sTx,
                        sessionRxBytes = sRx,
                        todayTxBytes = tTx,
                        todayRxBytes = tRx,
                        currentTxSpeedBps = speedTx,
                        currentRxSpeedBps = speedRx
                    )
                )
            }
        }

        return appList
    }
}
