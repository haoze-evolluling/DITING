package com.haoze.diting.vpn.traffic

import android.content.Context
import android.util.Log
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.dao.AppTrafficDeltaItem
import com.haoze.diting.util.currentDayString
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Handles batching and persisting app traffic deltas to Room database,
 * as well as tracking daily totals and handling midnight date rollovers.
 */
internal class TrafficDatabaseSyncer {

    private val todayAppBytes = ConcurrentHashMap<String, AppByteCounters>()
    private val todayTxTotal = AtomicLong(0L)
    private val todayRxTotal = AtomicLong(0L)

    private val pendingDbDeltas = ConcurrentHashMap<String, PendingDelta>()
    private val pendingDbBytesCounter = AtomicLong(0L)

    private val dateRolloverMutex = Mutex()
    private var todayDateString: String = currentDayString()

    val currentTodayTxTotal: Long get() = todayTxTotal.get()
    val currentTodayRxTotal: Long get() = todayRxTotal.get()
    val todayPackages: Set<String> get() = todayAppBytes.keys

    fun getTodayCounters(packageName: String): AppByteCounters? = todayAppBytes[packageName]

    fun resetTodayDate() {
        todayDateString = currentDayString()
    }

    fun isDateRolloverNeeded(): Boolean = currentDayString() != todayDateString

    /**
     * Records app traffic deltas into daily totals and the pending DB buffer.
     * Returns true if the accumulated delta bytes exceed the batch flush threshold.
     */
    fun recordDelta(packageName: String, appName: String, txDelta: Long, rxDelta: Long): Boolean {
        val todayCounters = todayAppBytes.getOrPut(packageName) { AppByteCounters() }
        todayCounters.tx.addAndGet(txDelta)
        todayCounters.rx.addAndGet(rxDelta)

        todayTxTotal.addAndGet(txDelta)
        todayRxTotal.addAndGet(rxDelta)

        val pending = pendingDbDeltas.getOrPut(packageName) {
            PendingDelta(packageName, appName)
        }
        pending.tx.addAndGet(txDelta)
        pending.rx.addAndGet(rxDelta)

        return pendingDbBytesCounter.addAndGet(txDelta + rxDelta) > BATCH_FLUSH_THRESHOLD_BYTES
    }

    /**
     * Serializes rollover handling across trigger sources (tick events / flush
     * loop / sampling loop) to avoid double flush/clear.
     */
    suspend fun checkDateRollover(context: Context) {
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

    suspend fun initTodayFromDb(context: Context) {
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

    suspend fun flushPendingDeltas(context: Context?) {
        if (pendingDbDeltas.isEmpty()) return
        val dbContext = context ?: return
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

    fun clear() {
        pendingDbDeltas.clear()
        pendingDbBytesCounter.set(0L)
        todayAppBytes.clear()
        todayTxTotal.set(0L)
        todayRxTotal.set(0L)
    }

    companion object {
        private const val TAG = "TrafficDatabaseSyncer"
        const val BATCH_FLUSH_INTERVAL_MS = 15_000L
        const val BATCH_FLUSH_THRESHOLD_BYTES = 1024 * 1024L // 1 MB
        const val FLUSH_STOP_TIMEOUT_MS = 500L
    }
}
