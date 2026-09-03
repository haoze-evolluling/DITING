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

    // 内核采样自适应退避：连续 8 个零增量周期后 1s → 3s → 10s，检测到增量立即回落 1s。
    private const val KERNEL_SAMPLE_IDLE_CYCLES_BEFORE_BACKOFF = 8
    private const val KERNEL_SAMPLE_BACKOFF_STEP_MS = 3_000L
    private const val KERNEL_SAMPLE_MAX_BACKOFF_MS = 10_000L
    // 灭屏时采样间隔下限：退避只降低空闲唤醒，有流量时灭屏采样间隔不低于 5s
    private const val KERNEL_SAMPLE_SCREEN_OFF_MIN_MS = 5_000L

    // Go 隧道模式不跑固定 Kotlin 心跳：EMA 衰减由惰性 watchdog 驱动，
    // 速度全部归零后 watchdog 退出，空闲期零唤醒。
    private const val GO_DECAY_WATCHDOG_INTERVAL_MS = 1_000L

    // 停止时有界同步刷库：主线程阻塞上限 500ms，超时放弃落库
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

    // 快照路径的异步包名解析去重 + 负缓存
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
        // restartVpnLocked 路径会不经 stop() 直接再次 start()，清掉上一会话的 watchdog
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

        // 有界同步刷库：主线程阻塞上限 500ms，超时放弃落库；丢失量受
        // 15s 周期 flush / 1MB 阈值约束，today 统计由 DB 已落库数据兜底。
        runBlocking {
            withTimeoutOrNull(FLUSH_STOP_TIMEOUT_MS) {
                flushPendingDeltas(context.applicationContext)
            }
        }
        // force：即使灭屏也要把 isRunning=false 传播给收集者，
        // 否则灭屏期间停止 VPN 后 UI 会停留在"运行中"的旧快照
        publishSnapshot(force = true)
        Log.i(TAG, "TrafficStatsManager stopped")
    }

    /**
     * 屏幕状态由 [DnsVpnService] 的 SCREEN_ON/SCREEN_OFF 广播驱动。
     * 灭屏期间采样照常累计，但跳过快照发布（省分配与发射）。
     */
    fun setScreenInteractive(interactive: Boolean) {
        val changed = screenInteractive != interactive
        screenInteractive = interactive
        if (!changed || !interactive) return
        // 灭屏期间 watchdog 已退出：亮屏时若有残留非零速度（灭屏前流量中断），
        // 重启衰减并补一次发布，恢复 UI/通知的速度显示
        if (isRunning && hasNonZeroSpeed()) {
            ensureGoDecayWatchdog()
        }
        publishSnapshot()
    }

    fun onGoTrafficTick(jsonDeltas: String) {
        if (!isRunning || !isGoTunnel || jsonDeltas.isBlank()) return
        try {
            // 日期翻转惰性检查：Go 模式在流量 tick 事件点触发，
            // 保证 VPN 跨天运行时"今日"统计归属正确
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

            // EMA 用实际 tick 间隔补偿：灭屏聚合 tick（如 10s 一次）恢复后速度不失真
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
     * Go 隧道模式的惰性衰减 watchdog：仅在存在非零速度（即最近有流量）且亮屏时
     * 以 1s 节奏衰减 EMA 并发布快照；全部归零或灭屏后自行退出，空闲/灭屏期零唤醒。
     * 灭屏期间速度冻结（无观察者），亮屏时由 [setScreenInteractive] 重启衰减。
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
                // 自适应退避：连续零增量周期越多，采样间隔越长（1s → 3s → 10s）；
                // 灭屏时保底下限 5s
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

                // 灭屏暂停发布：内存计数照常累计，亮屏后下一周期恢复
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
                // 日期翻转惰性检查：复用 15s 既有唤醒，无新增功耗
                //（Go 模式已无逐秒采样循环，此处是 tick 空窗期的兜底检查点）
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
                // 设备重启或 UID 被回收复用导致计数器回退
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
     * 按实际 elapsed 补偿的惰性衰减：采样退避（3s/10s 周期）下与 1s 周期收敛一致。
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

    // 串行化多触发源（tick 事件 / flush 循环 / 采样循环）的翻转处理，避免双重 flush/clear。
    // 注意：@Synchronized 不能用于 suspend 函数（编译错误），改用协程 Mutex。
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

    private fun publishSnapshot(force: Boolean = false) {
        // 灭屏暂停发布：计数照常累计，快照等亮屏（setScreenInteractive 会补发一次）。
        // force 用于状态跃迁（stop），即使灭屏也必须传播给收集者。
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

        // 无变化不发布：跳过 StateFlow 写入，避免无谓的收集者重组
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
     * 未知包名的 PackageManager 解析移出采样路径：快照先用包名兜底显示，
     * 后台解析完成后缓存回填并补发一次快照。
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
                        // 查不到的应用缓存负结果，避免每次发布重复查询
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
