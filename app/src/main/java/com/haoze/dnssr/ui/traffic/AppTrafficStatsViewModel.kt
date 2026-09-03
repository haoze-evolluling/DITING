package com.haoze.dnssr.ui.traffic

import android.app.Application
import android.content.pm.ApplicationInfo
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.AppTrafficDailyEntity
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.vpn.LogMaintenance
import com.haoze.dnssr.vpn.traffic.SystemAppClassifier
import com.haoze.dnssr.vpn.traffic.TrafficStatsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max

class AppTrafficStatsViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getInstance(application)
    private val systemAppCache = ConcurrentHashMap<String, Boolean>()
    private val appNameCache = ConcurrentHashMap<String, String>()

    private val _uiState = MutableStateFlow(
        AppTrafficStatsUiState(
            hideSystemApps = AppSettings.isTrafficStatsHideSystemApps(application)
        )
    )
    val uiState: StateFlow<AppTrafficStatsUiState> = _uiState.asStateFlow()

    private var historicalItems: List<AppTrafficDailyEntity> = emptyList()
    private var historicalJob: Job? = null

    private var isScreenActive = false

    init {
        preloadInstalledApps()
        viewModelScope.launch {
            TrafficStatsManager.uiSnapshot.collect { snap ->
                _uiState.update { current ->
                    current.copy(
                        isRunning = snap.isRunning,
                        isGoTunnelActive = snap.isGoTunnelActive,
                        totalTxSpeedBps = snap.totalTxSpeedBps,
                        totalRxSpeedBps = snap.totalRxSpeedBps,
                        sessionStartTimeMs = snap.sessionStartTimeMs
                    )
                }
                if (isScreenActive) {
                    recomputeAppList()
                }
            }
        }

        loadDataForCurrentRange()
    }

    fun setScreenActive(active: Boolean) {
        if (isScreenActive == active) return
        isScreenActive = active
        if (active) {
            TrafficStatsManager.registerDetailedConsumer()
            recomputeAppList()
        } else {
            TrafficStatsManager.unregisterDetailedConsumer()
        }
    }

    override fun onCleared() {
        super.onCleared()
        if (isScreenActive) {
            isScreenActive = false
            TrafficStatsManager.unregisterDetailedConsumer()
        }
    }

    fun setTimeRange(range: TrafficTimeRange) {
        if (_uiState.value.selectedTimeRange == range) return
        _uiState.update { it.copy(selectedTimeRange = range) }
        loadDataForCurrentRange()
    }

    fun setSortMode(mode: TrafficSortMode) {
        _uiState.update { it.copy(selectedSortMode = mode) }
        recomputeAppList()
    }

    fun setSearchQuery(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        recomputeAppList()
    }

    fun setHideSystemApps(hide: Boolean) {
        AppSettings.setTrafficStatsHideSystemApps(getApplication(), hide)
        _uiState.update { it.copy(hideSystemApps = hide) }
        recomputeAppList()
    }

    fun refresh() {
        loadDataForCurrentRange()
    }

    fun clearHistory() {
        viewModelScope.launch(Dispatchers.IO) {
            LogMaintenance.clearAllTrafficStats(db)
            historicalItems = emptyList()
            withContext(Dispatchers.Main) {
                recomputeAppList()
            }
        }
    }

    fun selectAppDetail(packageName: String?) {
        if (packageName == null) {
            _uiState.update { it.copy(selectedAppDetail = null) }
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            val records = db.appTrafficDao().queryByPackage(packageName)
            val snap = TrafficStatsManager.uiSnapshot.value
            val liveItem = snap.appStatsList.firstOrNull { it.packageName == packageName }

            var totalHistTx = 0L
            var totalHistRx = 0L
            for (r in records) {
                totalHistTx += r.txBytes
                totalHistRx += r.rxBytes
            }

            val detail = AppDetailTrafficState(
                packageName = packageName,
                appName = liveItem?.appName ?: resolveAppName(packageName, records.firstOrNull()?.appName),
                isSystemApp = isSystemApp(packageName, liveItem?.isSystemApp),
                todayTxBytes = liveItem?.todayTxBytes ?: 0L,
                todayRxBytes = liveItem?.todayRxBytes ?: 0L,
                sessionTxBytes = liveItem?.sessionTxBytes ?: 0L,
                sessionRxBytes = liveItem?.sessionRxBytes ?: 0L,
                totalHistoryTxBytes = totalHistTx,
                totalHistoryRxBytes = totalHistRx,
                dailyRecords = records
            )
            _uiState.update { it.copy(selectedAppDetail = detail) }
        }
    }

    private fun loadDataForCurrentRange() {
        val range = _uiState.value.selectedTimeRange
        if (range == TrafficTimeRange.SESSION) {
            historicalItems = emptyList()
            recomputeAppList()
            return
        }

        historicalJob?.cancel()
        historicalJob = viewModelScope.launch(Dispatchers.IO) {
            _uiState.update { it.copy(isLoading = true) }
            val now = System.currentTimeMillis()
            val todayStr = formatDate(now)

            val items = when (range) {
                TrafficTimeRange.TODAY -> {
                    db.appTrafficDao().queryByDate(todayStr)
                }
                TrafficTimeRange.THIS_WEEK -> {
                    val cal = Calendar.getInstance()
                    cal.add(Calendar.DAY_OF_YEAR, -6)
                    val startStr = formatDate(cal.timeInMillis)
                    db.appTrafficDao().queryDateRange(startStr, todayStr)
                }
                TrafficTimeRange.THIS_MONTH -> {
                    val cal = Calendar.getInstance()
                    cal.add(Calendar.DAY_OF_YEAR, -29)
                    val startStr = formatDate(cal.timeInMillis)
                    db.appTrafficDao().queryDateRange(startStr, todayStr)
                }
                TrafficTimeRange.ALL_HISTORY -> {
                    db.appTrafficDao().queryAllHistory()
                }
                else -> emptyList()
            }

            historicalItems = items
            withContext(Dispatchers.Main) {
                _uiState.update { it.copy(isLoading = false) }
                recomputeAppList()
            }
        }
    }

    private fun recomputeAppList() {
        val currentState = _uiState.value
        val snap = TrafficStatsManager.uiSnapshot.value
        val range = currentState.selectedTimeRange
        val liveMap = snap.appStatsList.associateBy { it.packageName }

        val computedMap = mutableMapOf<String, AppTrafficUiItem>()

        when (range) {
            TrafficTimeRange.SESSION -> {
                for (item in snap.appStatsList) {
                    if (item.sessionTxBytes > 0 || item.sessionRxBytes > 0 || item.currentTotalSpeedBps > 0) {
                        val isSys = isSystemApp(item.packageName, item.isSystemApp)
                        val appName = resolveAppName(item.packageName, item.appName)
                        computedMap[item.packageName] = AppTrafficUiItem(
                            packageName = item.packageName,
                            appName = appName,
                            isSystemApp = isSys,
                            txBytes = item.sessionTxBytes,
                            rxBytes = item.sessionRxBytes,
                            totalBytes = item.sessionTotalBytes,
                            percentage = 0f,
                            currentTxSpeedBps = item.currentTxSpeedBps,
                            currentRxSpeedBps = item.currentRxSpeedBps,
                            currentTotalSpeedBps = item.currentTotalSpeedBps
                        )
                    }
                }
            }
            TrafficTimeRange.TODAY -> {
                for (record in historicalItems) {
                    val live = liveMap[record.packageName]
                    val appName = resolveAppName(record.packageName, live?.appName ?: record.appName)
                    val isSys = isSystemApp(record.packageName, live?.isSystemApp)
                    val tx = max(record.txBytes, live?.todayTxBytes ?: 0L)
                    val rx = max(record.rxBytes, live?.todayRxBytes ?: 0L)
                    if (tx > 0 || rx > 0 || (live?.currentTotalSpeedBps ?: 0L) > 0) {
                        computedMap[record.packageName] = AppTrafficUiItem(
                            packageName = record.packageName,
                            appName = appName,
                            isSystemApp = isSys,
                            txBytes = tx,
                            rxBytes = rx,
                            totalBytes = tx + rx,
                            percentage = 0f,
                            currentTxSpeedBps = live?.currentTxSpeedBps ?: 0L,
                            currentRxSpeedBps = live?.currentRxSpeedBps ?: 0L,
                            currentTotalSpeedBps = live?.currentTotalSpeedBps ?: 0L
                        )
                    }
                }
                for (live in snap.appStatsList) {
                    if (!computedMap.containsKey(live.packageName)) {
                        if (live.todayTxBytes > 0 || live.todayRxBytes > 0 || live.currentTotalSpeedBps > 0) {
                            val isSys = isSystemApp(live.packageName, live.isSystemApp)
                            val appName = resolveAppName(live.packageName, live.appName)
                            computedMap[live.packageName] = AppTrafficUiItem(
                                packageName = live.packageName,
                                appName = appName,
                                isSystemApp = isSys,
                                txBytes = live.todayTxBytes,
                                rxBytes = live.todayRxBytes,
                                totalBytes = live.todayTotalBytes,
                                percentage = 0f,
                                currentTxSpeedBps = live.currentTxSpeedBps,
                                currentRxSpeedBps = live.currentRxSpeedBps,
                                currentTotalSpeedBps = live.currentTotalSpeedBps
                            )
                        }
                    }
                }
            }
            TrafficTimeRange.THIS_WEEK, TrafficTimeRange.THIS_MONTH, TrafficTimeRange.ALL_HISTORY -> {
                for (record in historicalItems) {
                    val live = liveMap[record.packageName]
                    val appName = resolveAppName(record.packageName, live?.appName ?: record.appName)
                    val isSys = isSystemApp(record.packageName, live?.isSystemApp)
                    computedMap[record.packageName] = AppTrafficUiItem(
                        packageName = record.packageName,
                        appName = appName,
                        isSystemApp = isSys,
                        txBytes = record.txBytes,
                        rxBytes = record.rxBytes,
                        totalBytes = record.txBytes + record.rxBytes,
                        percentage = 0f,
                        currentTxSpeedBps = live?.currentTxSpeedBps ?: 0L,
                        currentRxSpeedBps = live?.currentRxSpeedBps ?: 0L,
                        currentTotalSpeedBps = live?.currentTotalSpeedBps ?: 0L
                    )
                }
                // Merge in any active live items that might not yet be in the database
                for (live in snap.appStatsList) {
                    if (!computedMap.containsKey(live.packageName) && live.todayTotalBytes > 0) {
                        val isSys = isSystemApp(live.packageName, live.isSystemApp)
                        val appName = resolveAppName(live.packageName, live.appName)
                        computedMap[live.packageName] = AppTrafficUiItem(
                            packageName = live.packageName,
                            appName = appName,
                            isSystemApp = isSys,
                            txBytes = live.todayTxBytes,
                            rxBytes = live.todayRxBytes,
                            totalBytes = live.todayTotalBytes,
                            percentage = 0f,
                            currentTxSpeedBps = live.currentTxSpeedBps,
                            currentRxSpeedBps = live.currentRxSpeedBps,
                            currentTotalSpeedBps = live.currentTotalSpeedBps
                        )
                    }
                }
            }
        }

        var periodTx = 0L
        var periodRx = 0L
        var maxBytes = 1L

        for (item in computedMap.values) {
            periodTx += item.txBytes
            periodRx += item.rxBytes
            if (item.totalBytes > maxBytes) {
                maxBytes = item.totalBytes
            }
        }

        val filtered = computedMap.values.filter { item ->
            if (currentState.hideSystemApps && item.isSystemApp) false
            else if (currentState.searchQuery.isNotBlank()) {
                item.appName.contains(currentState.searchQuery, ignoreCase = true) ||
                    item.packageName.contains(currentState.searchQuery, ignoreCase = true)
            } else true
        }.map { item ->
            val pct = (item.totalBytes.toDouble() / maxBytes.toDouble()).coerceIn(0.0, 1.0).toFloat()
            item.copy(percentage = pct)
        }

        val sorted = when (currentState.selectedSortMode) {
            TrafficSortMode.TOTAL_TRAFFIC -> filtered.sortedByDescending { it.totalBytes }
            TrafficSortMode.DOWNLOAD -> filtered.sortedByDescending { it.rxBytes }
            TrafficSortMode.UPLOAD -> filtered.sortedByDescending { it.txBytes }
            TrafficSortMode.REALTIME_SPEED -> filtered.sortedByDescending { it.currentTotalSpeedBps }
        }

        _uiState.update { current ->
            current.copy(
                currentPeriodTxBytes = periodTx,
                currentPeriodRxBytes = periodRx,
                currentPeriodTotalBytes = periodTx + periodRx,
                appItems = sorted
            )
        }
    }

    private fun preloadInstalledApps() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val context = getApplication<Application>()
                val pm = context.packageManager
                @Suppress("DEPRECATION")
                val installed = pm.getInstalledApplications(0)
                for (info in installed) {
                    val isSys = SystemAppClassifier.isSystemApplicationInfo(info)
                    systemAppCache[info.packageName] = isSys
                    val label = runCatching { info.loadLabel(pm).toString() }.getOrNull()
                    if (!label.isNullOrBlank()) {
                        appNameCache[info.packageName] = label
                    }
                }
                withContext(Dispatchers.Main) {
                    recomputeAppList()
                }
            } catch (_: Exception) {
                // Ignore and fall back to dynamic resolution
            }
        }
    }

    private fun isSystemApp(packageName: String, liveIsSystem: Boolean? = null): Boolean {
        if (liveIsSystem == true) return true
        if (packageName.isBlank()) return false

        // 1. 优先查已预热或已缓存的结果（与「排除应用」完全对齐）
        val cached = systemAppCache[packageName]
        if (cached != null) return cached

        // 2. 特殊前缀与系统底层/厂商预装服务规则匹配兜底
        if (SystemAppClassifier.isKnownSystemPackagePrefix(packageName)) {
            systemAppCache[packageName] = true
            return true
        }

        // 3. 动态单包查询兜底
        return try {
            val pm = getApplication<Application>().packageManager
            @Suppress("DEPRECATION")
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val isSys = SystemAppClassifier.isSystemApplicationInfo(appInfo)
            systemAppCache[packageName] = isSys
            isSys
        } catch (_: Exception) {
            // 查询受限/抛出异常时，若命中厂商/系统特征前缀仍判定为系统应用，否则暂时返回 false
            val fallbackSys = SystemAppClassifier.isKnownSystemPackagePrefix(packageName)
            if (fallbackSys) {
                systemAppCache[packageName] = true
                true
            } else {
                false
            }
        }
    }

    private fun resolveAppName(packageName: String, fallback: String? = null): String {
        if (!fallback.isNullOrBlank() && fallback != packageName) return fallback
        val cached = appNameCache[packageName]
        if (!cached.isNullOrBlank()) return cached
        return try {
            val pm = getApplication<Application>().packageManager
            @Suppress("DEPRECATION")
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val label = appInfo.loadLabel(pm).toString()
            appNameCache[packageName] = label
            label
        } catch (_: Exception) {
            fallback?.ifBlank { packageName } ?: packageName
        }
    }

    private fun formatDate(timestamp: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(timestamp))
}
