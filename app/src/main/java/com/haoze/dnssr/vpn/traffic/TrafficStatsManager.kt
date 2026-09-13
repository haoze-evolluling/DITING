package com.haoze.dnssr.vpn.traffic

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.TrafficStats
import android.os.PowerManager
import android.util.Log
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.util.currentDayString
import com.haoze.dnssr.data.dao.AppTrafficDeltaItem
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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.max
import kotlin.math.pow

data class AppTrafficItem(
    val packageName: String,
    val appName: String,
    val isSystemApp: Boolean,
    val sessionTxBytes: Long,
    val sessionRxBytes: Long,
    val todayTxBytes: Long,
    val todayRxBytes: Long,
    val currentTxSpeedBps: Long,
    val currentRxSpeedBps: Long
) {
    val sessionTotalBytes: Long get() = sessionTxBytes + sessionRxBytes
    val todayTotalBytes: Long get() = todayTxBytes + todayRxBytes
    val currentTotalSpeedBps: Long get() = currentTxSpeedBps + currentRxSpeedBps
}

data class TrafficStatsUiSnapshot(
    val isRunning: Boolean = false,
    val isGoTunnelActive: Boolean = false,
    val totalTxSpeedBps: Long = 0L,
    val totalRxSpeedBps: Long = 0L,
    val sessionTxBytes: Long = 0L,
    val sessionRxBytes: Long = 0L,
    val todayTxBytes: Long = 0L,
    val todayRxBytes: Long = 0L,
    val sessionStartTimeMs: Long = 0L,
    val appStatsList: List<AppTrafficItem> = emptyList(),
    val updatedAt: Long = 0L
) {
    val sessionTotalBytes: Long get() = sessionTxBytes + sessionRxBytes
    val todayTotalBytes: Long get() = todayTxBytes + todayRxBytes
    val totalSpeedBps: Long get() = totalTxSpeedBps + totalRxSpeedBps
}

object TrafficStatsManager {
    private const val TAG = "TrafficStatsManager"
    private const val EMA_ALPHA = 0.3
    private const val BATCH_FLUSH_INTERVAL_MS = 15_000L
    private const val BATCH_FLUSH_THRESHOLD_BYTES = 1024 * 1024L // 1 MB

    // Kernel-sampling adaptive backoff: after 8 consecutive zero-delta cycles,
    // 1s -> 3s -> 10s; any detected delta immediately drops back to 1s.
    private const val KERNEL_SAMPLE_IDLE_CYCLES_BEFORE_BACKOFF = 8
    private const val KERNEL_SAMPLE_BACKOFF_STEP_MS = 3_000L
    private const val KERNEL_SAMPLE_MAX_BACKOFF_MS = 10_000L
    // Sampling interval floor while the screen is off: backoff only reduces
    // idle wakeups; with active traffic the off-screen interval stays at 5s or above
    private const val KERNEL_SAMPLE_SCREEN_OFF_MIN_MS = 5_000L

    // Go tunnel mode runs no fixed Kotlin heartbeat: EMA decay is driven by a
    // lazy watchdog that exits once all speeds reach zero, so idle periods
    // cause zero wakeups.
    private const val GO_DECAY_WATCHDOG_INTERVAL_MS = 1_000L

    // Bounded synchronous flush on stop: main-thread blocking capped at 500ms,
    // the DB write is abandoned on timeout.
    private const val FLUSH_STOP_TIMEOUT_MS = 500L

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

    private val todayTxTotal = AtomicLong(0L)
    private val todayRxTotal = AtomicLong(0L)

    private val detailedSubscribersCount = AtomicInteger(0)

    fun registerDetailedConsumer() {
        if (detailedSubscribersCount.incrementAndGet() == 1) {
            publishSnapshot()
        }
    }

    fun unregisterDetailedConsumer() {
        detailedSubscribersCount.decrementAndGet()
    }

    fun getAppStatsList(): List<AppTrafficItem> = buildAppStatsList()

    private val totalTxSpeedEma = AtomicLong(0L)
    private val totalRxSpeedEma = AtomicLong(0L)

    private val appInfoByUid = ConcurrentHashMap<Int, CachedAppInfo>()
    private val appInfoByPackage = ConcurrentHashMap<String, CachedAppInfo>()

    private val kernelBaseline = ConcurrentHashMap<Int, UidBaseline>()

    private val sessionAppBytes = ConcurrentHashMap<String, AppByteCounters>()
    private val todayAppBytes = ConcurrentHashMap<String, AppByteCounters>()
    private val appSpeedEma = ConcurrentHashMap<String, AppSpeedEma>()

    private val pendingDbDeltas = ConcurrentHashMap<String, PendingDelta>()
    private val pendingDbBytesCounter = AtomicLong(0L)

    // Deduplication + negative cache for async package lookups on the snapshot path
    private val pendingPackageLookups = ConcurrentHashMap.newKeySet<String>()
    private val unresolvablePackages = ConcurrentHashMap.newKeySet<String>()

    private val _uiSnapshot = MutableStateFlow(TrafficStatsUiSnapshot())
    val uiSnapshot: StateFlow<TrafficStatsUiSnapshot> = _uiSnapshot.asStateFlow()

    private var applicationContext: Context? = null
    private var todayDateString: String = currentDayString()

    private class CachedAppInfo(
        val uid: Int,
        val packageName: String,
        val appName: String,
        val isSystemApp: Boolean
    )

    private class UidBaseline(
        var tx: Long,
        var rx: Long
    )

    private class AppByteCounters {
        val tx = AtomicLong(0L)
        val rx = AtomicLong(0L)
    }

    private class AppSpeedEma {
        var txSpeed = 0.0
        var rxSpeed = 0.0
        var idleSeconds = 0.0
    }

    private class PendingDelta(
        val packageName: String,
        val appName: String
    ) {
        val tx = AtomicLong(0L)
        val rx = AtomicLong(0L)
    }

    @Synchronized
    fun start(context: Context, isGoTunnelActive: Boolean) {
        val appContext = context.applicationContext
        applicationContext = appContext
        todayDateString = currentDayString()
        isRunning = true
        isGoTunnel = isGoTunnelActive
        sessionStartTime.set(System.currentTimeMillis())
        sessionTxTotal.set(0L)
        sessionRxTotal.set(0L)
        totalTxSpeedEma.set(0L)
        totalRxSpeedEma.set(0L)
        lastGoTickTimeMs.set(System.currentTimeMillis())

        sessionAppBytes.clear()
        appSpeedEma.clear()
        // The restartVpnLocked path can call start() again without a stop()
        // in between; clear the previous session's watchdog.
        goDecayJob?.cancel()
        goDecayJob = null

        scope.launch(Dispatchers.IO) {
            refreshAppList(appContext)
            if (!isGoTunnelActive) {
                initKernelBaseline(appContext)
            }
            initTodayFromDb(appContext)

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
            withTimeoutOrNull(FLUSH_STOP_TIMEOUT_MS) {
                flushPendingDeltas(context.applicationContext)
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
     * counters but snapshot publishing is skipped (saves allocations and
     * emissions).
     */
    fun setScreenInteractive(interactive: Boolean) {
        val changed = screenInteractive != interactive
        screenInteractive = interactive
        if (!changed || !interactive) return
        // The watchdog exited during off-screen time: on screen-on, if there
        // is residual non-zero speed (traffic cut off before screen off),
        // restart the decay and publish once to restore the speed display in
        // the UI and notification.
        if (isRunning && hasNonZeroSpeed()) {
            ensureGoDecayWatchdog()
        }
        publishSnapshot()
    }

    fun onGoTrafficTick(jsonDeltas: String) {
        if (!isRunning || !isGoTunnel || jsonDeltas.isBlank()) return
        try {
            // Lazy date-rollover check: in Go mode this is triggered at traffic
            // tick events, keeping "today" statistics correctly attributed
            // when the VPN runs across midnight.
            val rolloverContext = applicationContext
            if (rolloverContext != null && currentDayString() != todayDateString) {
                scope.launch { checkDateRollover(rolloverContext) }
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
                    val appInfo = getOrResolveAppInfo(uid)
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
            updateSpeedEma(totalTxDelta, totalRxDelta, elapsedSeconds)
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
     * during idle/off-screen periods. Speeds stay frozen while the screen is
     * off (no observers); [setScreenInteractive] restarts the decay on screen-on.
     */
    private fun ensureGoDecayWatchdog() {
        synchronized(this) {
            if (!screenInteractive) return
            if (goDecayJob?.isActive == true) return
            goDecayJob = scope.launch {
                while (isActive && isRunning) {
                    delay(GO_DECAY_WATCHDOG_INTERVAL_MS)
                    if (!isRunning || !screenInteractive) break
                    decayIdleSpeeds()
                    publishSnapshot()
                    if (!hasNonZeroSpeed()) break
                }
            }
        }
    }

    private fun hasNonZeroSpeed(): Boolean {
        if (totalTxSpeedEma.get() > 0 || totalRxSpeedEma.get() > 0) return true
        for (ema in appSpeedEma.values) {
            if (ema.txSpeed > 0 || ema.rxSpeed > 0) return true
        }
        return false
    }

    private fun startSamplingLoop(context: Context) {
        sampleJob?.cancel()
        sampleJob = scope.launch {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            var lastSampleTime = System.currentTimeMillis()
            var idleCycles = 0

            while (isActive && isRunning) {
                val isScreenOn = powerManager?.isInteractive ?: true
                // Adaptive backoff: the more consecutive zero-delta cycles,
                // the longer the sampling interval (1s -> 3s -> 10s);
                // floored at 5s while the screen is off.
                val backoffMs = when {
                    idleCycles < KERNEL_SAMPLE_IDLE_CYCLES_BEFORE_BACKOFF -> 1_000L
                    idleCycles < KERNEL_SAMPLE_IDLE_CYCLES_BEFORE_BACKOFF * 2 -> KERNEL_SAMPLE_BACKOFF_STEP_MS
                    else -> KERNEL_SAMPLE_MAX_BACKOFF_MS
                }
                val intervalMs = if (isScreenOn) backoffMs else maxOf(KERNEL_SAMPLE_SCREEN_OFF_MIN_MS, backoffMs)
                delay(intervalMs)

                if (!isRunning) break

                val now = System.currentTimeMillis()
                val elapsedSeconds = max(0.2, (now - lastSampleTime) / 1000.0)
                lastSampleTime = now

                checkDateRollover(context)

                val hadTraffic = sampleKernelTraffic(elapsedSeconds)
                idleCycles = if (hadTraffic) 0 else idleCycles + 1

                // Publishing pauses while the screen is off: in-memory counters
                // keep accumulating, publishing resumes on the next cycle after screen-on.
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
                delay(BATCH_FLUSH_INTERVAL_MS)
                if (!isRunning) break
                // Lazy date-rollover check: reuses the existing 15s wakeup, no
                // extra power cost (Go mode has no per-second sampling loop,
                // so this is the safety-net check during tick gaps).
                checkDateRollover(context)
                flushPendingDeltas(context)
            }
        }
    }

    private fun sampleKernelTraffic(elapsedSeconds: Double): Boolean {
        var totalTxDelta = 0L
        var totalRxDelta = 0L

        for ((uid, appInfo) in appInfoByUid) {
            val currentTx = TrafficStats.getUidTxBytes(uid)
            val currentRx = TrafficStats.getUidRxBytes(uid)

            if (currentTx < 0 || currentRx < 0) continue

            val baseline = kernelBaseline.getOrPut(uid) { UidBaseline(currentTx, currentRx) }

            if (currentTx < baseline.tx || currentRx < baseline.rx) {
                // Counter went backwards: device reboot or a UID that was
                // recycled and reassigned.
                baseline.tx = currentTx
                baseline.rx = currentRx
                continue
            }

            val txDelta = currentTx - baseline.tx
            val rxDelta = currentRx - baseline.rx

            baseline.tx = currentTx
            baseline.rx = currentRx

            if (txDelta > 0 || rxDelta > 0) {
                recordAppTraffic(appInfo, txDelta, rxDelta)
                updateSingleAppSpeedEma(appInfo.packageName, txDelta, rxDelta, elapsedSeconds)
                totalTxDelta += txDelta
                totalRxDelta += rxDelta
            } else {
                decaySingleAppSpeed(appInfo.packageName, elapsedSeconds)
            }
        }

        updateSpeedEma(totalTxDelta, totalRxDelta, elapsedSeconds)
        return totalTxDelta > 0 || totalRxDelta > 0
    }

    private fun recordAppTraffic(appInfo: CachedAppInfo, txDelta: Long, rxDelta: Long) {
        sessionTxTotal.addAndGet(txDelta)
        sessionRxTotal.addAndGet(rxDelta)

        val sessionCounters = sessionAppBytes.getOrPut(appInfo.packageName) { AppByteCounters() }
        sessionCounters.tx.addAndGet(txDelta)
        sessionCounters.rx.addAndGet(rxDelta)

        val todayCounters = todayAppBytes.getOrPut(appInfo.packageName) { AppByteCounters() }
        todayCounters.tx.addAndGet(txDelta)
        todayCounters.rx.addAndGet(rxDelta)

        todayTxTotal.addAndGet(txDelta)
        todayRxTotal.addAndGet(rxDelta)

        val pending = pendingDbDeltas.getOrPut(appInfo.packageName) {
            PendingDelta(appInfo.packageName, appInfo.appName)
        }
        pending.tx.addAndGet(txDelta)
        pending.rx.addAndGet(rxDelta)

        if (pendingDbBytesCounter.addAndGet(txDelta + rxDelta) > BATCH_FLUSH_THRESHOLD_BYTES) {
            scope.launch { flushPendingDeltas(null) }
        }
    }

    private fun updateSpeedEma(totalTxDelta: Long, totalRxDelta: Long, elapsedSeconds: Double) {
        val instantTxSpeed = (totalTxDelta / elapsedSeconds)
        val instantRxSpeed = (totalRxDelta / elapsedSeconds)

        val prevTx = totalTxSpeedEma.get().toDouble()
        val prevRx = totalRxSpeedEma.get().toDouble()

        val nextTx = if (instantTxSpeed > 0 || prevTx > 0) (EMA_ALPHA * instantTxSpeed + (1 - EMA_ALPHA) * prevTx) else 0.0
        val nextRx = if (instantRxSpeed > 0 || prevRx > 0) (EMA_ALPHA * instantRxSpeed + (1 - EMA_ALPHA) * prevRx) else 0.0

        totalTxSpeedEma.set(if (nextTx < 1.0) 0L else nextTx.toLong())
        totalRxSpeedEma.set(if (nextRx < 1.0) 0L else nextRx.toLong())
    }

    private fun updateSingleAppSpeedEma(packageName: String, txDelta: Long, rxDelta: Long, elapsedSeconds: Double) {
        val ema = appSpeedEma.getOrPut(packageName) { AppSpeedEma() }
        val instantTx = txDelta / elapsedSeconds
        val instantRx = rxDelta / elapsedSeconds
        ema.txSpeed = EMA_ALPHA * instantTx + (1 - EMA_ALPHA) * ema.txSpeed
        ema.rxSpeed = EMA_ALPHA * instantRx + (1 - EMA_ALPHA) * ema.rxSpeed
        ema.idleSeconds = 0.0
    }

    /**
     * Lazy decay compensated by the actual elapsed time: converges to the same
     * result as a 1s cycle even under sampling backoff (3s/10s periods).
     */
    private fun decaySingleAppSpeed(packageName: String, elapsedSeconds: Double) {
        val ema = appSpeedEma[packageName] ?: return
        ema.idleSeconds += elapsedSeconds
        if (ema.idleSeconds >= 2.0) {
            ema.txSpeed = 0.0
            ema.rxSpeed = 0.0
        } else {
            val factor = 0.5.pow(elapsedSeconds)
            ema.txSpeed *= factor
            ema.rxSpeed *= factor
        }
    }

    private fun decayIdleSpeeds() {
        for ((_, ema) in appSpeedEma) {
            ema.idleSeconds += 1.0
            if (ema.idleSeconds >= 2.0) {
                ema.txSpeed = 0.0
                ema.rxSpeed = 0.0
            } else {
                ema.txSpeed *= 0.5
                ema.rxSpeed *= 0.5
            }
        }
        val prevTx = totalTxSpeedEma.get()
        val prevRx = totalRxSpeedEma.get()
        totalTxSpeedEma.set((prevTx * 0.5).toLong().takeIf { it > 10 } ?: 0L)
        totalRxSpeedEma.set((prevRx * 0.5).toLong().takeIf { it > 10 } ?: 0L)
    }

    // Serializes rollover handling across trigger sources (tick events / flush
    // loop / sampling loop) to avoid double flush/clear.
    // Note: @Synchronized cannot be applied to suspend functions (compile
    // error), so a coroutine Mutex is used instead.
    private val dateRolloverMutex = Mutex()

    private suspend fun checkDateRollover(context: Context) {
        dateRolloverMutex.withLock {
            val currentDate = currentDayString()
            if (currentDate != todayDateString) {
                flushPendingDeltas(context)
                todayDateString = currentDate
                todayAppBytes.clear()
                todayTxTotal.set(0L)
                todayRxTotal.set(0L)
                initTodayFromDb(context)
            }
        }
    }

    private suspend fun initTodayFromDb(context: Context) {
        try {
            val db = AppDatabase.getInstance(context)
            val records = db.appTrafficDao().queryByDate(todayDateString)
            var sumTx = 0L
            var sumRx = 0L
            for (record in records) {
                val counters = todayAppBytes.getOrPut(record.packageName) { AppByteCounters() }
                counters.tx.set(record.txBytes)
                counters.rx.set(record.rxBytes)
                sumTx += record.txBytes
                sumRx += record.rxBytes
            }
            todayTxTotal.set(sumTx)
            todayRxTotal.set(sumRx)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load today's traffic from DB: ${e.message}")
        }
    }

    private fun initKernelBaseline(context: Context) {
        kernelBaseline.clear()
        for ((uid, _) in appInfoByUid) {
            val tx = TrafficStats.getUidTxBytes(uid)
            val rx = TrafficStats.getUidRxBytes(uid)
            if (tx >= 0 && rx >= 0) {
                kernelBaseline[uid] = UidBaseline(tx, rx)
            }
        }
    }

    fun refreshAppList(context: Context) {
        try {
            val pm = context.packageManager
            val installed = pm.getInstalledApplications(0)
            val myPackage = context.packageName

            for (app in installed) {
                if (app.packageName == myPackage) continue
                val label = runCatching { app.loadLabel(pm).toString() }.getOrDefault(app.packageName)
                val isSys = SystemAppClassifier.isSystemApplicationInfo(app) ||
                    SystemAppClassifier.isKnownSystemPackagePrefix(app.packageName)
                val info = CachedAppInfo(app.uid, app.packageName, label, isSys)
                appInfoByUid[app.uid] = info
                appInfoByPackage[app.packageName] = info
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to refresh installed apps: ${e.message}")
        }
    }

    private fun getOrResolveAppInfo(uid: Int): CachedAppInfo? {
        val cached = appInfoByUid[uid]
        if (cached != null) return cached
        val context = applicationContext ?: return null
        return try {
            val pm = context.packageManager
            val packages = pm.getPackagesForUid(uid)
            val pkg = packages?.firstOrNull()
            if (pkg != null) {
                val app = runCatching { pm.getApplicationInfo(pkg, 0) }.getOrNull()
                val label = app?.let { runCatching { it.loadLabel(pm).toString() }.getOrNull() } ?: pkg
                val isSys = app?.let { SystemAppClassifier.isSystemApplicationInfo(it) }
                    ?: (SystemAppClassifier.isKnownSystemPackagePrefix(pkg) || uid < 10000)
                val info = CachedAppInfo(uid, pkg, label, isSys)
                appInfoByUid[uid] = info
                appInfoByPackage[pkg] = info
                info
            } else if (uid < 10000) {
                val name = when (uid) {
                    0 -> "Root"
                    1000 -> "System"
                    1001 -> "Phone"
                    1013 -> "Media"
                    1020 -> "mDNS"
                    1073 -> "NetworkStack"
                    else -> "System ($uid)"
                }
                val info = CachedAppInfo(uid, "android.uid.system:$uid", name, true)
                appInfoByUid[uid] = info
                appInfoByPackage[info.packageName] = info
                info
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun flushPendingDeltas(context: Context? = null) {
        if (pendingDbDeltas.isEmpty()) return
        val dbContext = context ?: applicationContext ?: return
        val itemsToFlush = mutableListOf<AppTrafficDeltaItem>()

        for ((pkg, pending) in pendingDbDeltas) {
            val tx = pending.tx.getAndSet(0L)
            val rx = pending.rx.getAndSet(0L)
            if (tx > 0 || rx > 0) {
                itemsToFlush.add(AppTrafficDeltaItem(pkg, pending.appName, tx, rx))
            }
        }

        pendingDbBytesCounter.set(0L)

        if (itemsToFlush.isNotEmpty()) {
            withContext(Dispatchers.IO) {
                try {
                    val db = AppDatabase.getInstance(dbContext)
                    db.appTrafficDao().upsertBatchDeltas(
                        date = todayDateString,
                        deltas = itemsToFlush,
                        updatedAt = System.currentTimeMillis()
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to flush traffic deltas to Room: ${e.message}")
                }
            }
        }
    }

    suspend fun flush(context: Context) {
        flushPendingDeltas(context)
    }

    /**
     * Clears all in-memory app traffic accumulators, the pending DB delta
     * buffer, and the live statistics state, then force-publishes an
     * all-zero snapshot.
     */
    @Synchronized
    fun clearAllTrafficStats(context: Context? = null) {
        pendingDbDeltas.clear()
        pendingDbBytesCounter.set(0L)

        todayAppBytes.clear()
        todayTxTotal.set(0L)
        todayRxTotal.set(0L)

        sessionAppBytes.clear()
        sessionTxTotal.set(0L)
        sessionRxTotal.set(0L)

        appSpeedEma.clear()
        totalTxSpeedEma.set(0L)
        totalRxSpeedEma.set(0L)

        val appContext = context?.applicationContext ?: applicationContext
        if (appContext != null && isRunning && !isGoTunnel) {
            initKernelBaseline(appContext)
        }

        publishSnapshot(force = true)
    }

    private fun publishSnapshot(force: Boolean = false) {
        // Publishing pauses while the screen is off: counters keep accumulating
        // and the snapshot waits for screen-on (setScreenInteractive publishes once).
        // force is for state transitions (stop): it must reach collectors even
        // with the screen off.
        if (!force && !screenInteractive) return

        val txSpeed = totalTxSpeedEma.get()
        val rxSpeed = totalRxSpeedEma.get()
        val sessionTx = sessionTxTotal.get()
        val sessionRx = sessionRxTotal.get()
        val startMs = sessionStartTime.get()
        val sumTodayTx = todayTxTotal.get()
        val sumTodayRx = todayRxTotal.get()

        val needsAppList = detailedSubscribersCount.get() > 0
        val appList = if (needsAppList) buildAppStatsList() else emptyList()

        // No-change fast path: skip the StateFlow write to avoid needless
        // collector recompositions
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

    /**
     * Keeps PackageManager resolution of unknown package names off the
     * sampling path: the snapshot first falls back to showing the package
     * name, and once the background lookup finishes, the cache is filled and
     * an extra snapshot is published.
     */
    private fun schedulePackageLookup(pkg: String) {
        if (pkg.startsWith("android.uid.system")) return
        if (unresolvablePackages.contains(pkg)) return
        if (!pendingPackageLookups.add(pkg)) return
        scope.launch(Dispatchers.IO) {
            try {
                val context = applicationContext ?: return@launch
                val pm = context.packageManager
                val app = runCatching { pm.getApplicationInfo(pkg, 0) }.getOrNull()
                if (app != null) {
                    val label = runCatching { app.loadLabel(pm).toString() }.getOrDefault(pkg)
                    val isSys = SystemAppClassifier.isSystemApplicationInfo(app) ||
                        SystemAppClassifier.isKnownSystemPackagePrefix(pkg)
                    appInfoByPackage[pkg] = CachedAppInfo(app.uid, pkg, label, isSys)
                } else {
                    val isSys = SystemAppClassifier.isKnownSystemPackagePrefix(pkg)
                    if (isSys) {
                        appInfoByPackage[pkg] = CachedAppInfo(0, pkg, pkg, true)
                    } else {
                        // Cache the negative result for apps that cannot be
                        // resolved, avoiding a repeated lookup on every publish
                        unresolvablePackages.add(pkg)
                    }
                }
            } catch (e: Exception) {
                val isSys = SystemAppClassifier.isKnownSystemPackagePrefix(pkg)
                if (isSys) {
                    appInfoByPackage[pkg] = CachedAppInfo(0, pkg, pkg, true)
                } else {
                    unresolvablePackages.add(pkg)
                }
            } finally {
                pendingPackageLookups.remove(pkg)
            }
            if (screenInteractive && isRunning) {
                publishSnapshot()
            }
        }
    }

    private fun buildAppStatsList(): List<AppTrafficItem> {
        val appList = mutableListOf<AppTrafficItem>()

        val allPackages = HashSet<String>()
        allPackages.addAll(sessionAppBytes.keys)
        allPackages.addAll(todayAppBytes.keys)
        allPackages.addAll(appSpeedEma.keys)

        for (pkg in allPackages) {
            val info = appInfoByPackage[pkg]
            if (info == null) {
                schedulePackageLookup(pkg)
            }
            val appName = info?.appName ?: pkg
            val isSys = info?.isSystemApp ?: SystemAppClassifier.isKnownSystemPackagePrefix(pkg)

            val session = sessionAppBytes[pkg]
            val sTx = session?.tx?.get() ?: 0L
            val sRx = session?.rx?.get() ?: 0L

            val today = todayAppBytes[pkg]
            val tTx = today?.tx?.get() ?: 0L
            val tRx = today?.rx?.get() ?: 0L

            val speed = appSpeedEma[pkg]
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
