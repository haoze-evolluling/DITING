package com.haoze.dnssr.ui.traffic

import com.haoze.dnssr.data.entity.AppTrafficDailyEntity

enum class TrafficTimeRange(val displayName: String) {
    SESSION("本次会话"),
    TODAY("今日"),
    THIS_WEEK("本周"),
    THIS_MONTH("本月"),
    ALL_HISTORY("全部历史")
}

enum class TrafficSortMode(val displayName: String) {
    TOTAL_TRAFFIC("按总流量"),
    DOWNLOAD("按下载流量"),
    UPLOAD("按上传流量"),
    REALTIME_SPEED("按实时网速")
}

data class AppTrafficUiItem(
    val packageName: String,
    val appName: String,
    val isSystemApp: Boolean,
    val txBytes: Long,
    val rxBytes: Long,
    val totalBytes: Long,
    val percentage: Float, // 0.0f - 1.0f
    val currentTxSpeedBps: Long,
    val currentRxSpeedBps: Long,
    val currentTotalSpeedBps: Long
)

data class AppDetailTrafficState(
    val packageName: String,
    val appName: String,
    val isSystemApp: Boolean,
    val todayTxBytes: Long,
    val todayRxBytes: Long,
    val sessionTxBytes: Long,
    val sessionRxBytes: Long,
    val totalHistoryTxBytes: Long,
    val totalHistoryRxBytes: Long,
    val dailyRecords: List<AppTrafficDailyEntity> = emptyList()
)

data class AppTrafficStatsUiState(
    val isRunning: Boolean = false,
    val isGoTunnelActive: Boolean = false,
    val selectedTimeRange: TrafficTimeRange = TrafficTimeRange.TODAY,
    val selectedSortMode: TrafficSortMode = TrafficSortMode.TOTAL_TRAFFIC,
    val searchQuery: String = "",
    val hideSystemApps: Boolean = false,
    val totalTxSpeedBps: Long = 0L,
    val totalRxSpeedBps: Long = 0L,
    val currentPeriodTxBytes: Long = 0L,
    val currentPeriodRxBytes: Long = 0L,
    val currentPeriodTotalBytes: Long = 0L,
    val sessionStartTimeMs: Long = 0L,
    val appItems: List<AppTrafficUiItem> = emptyList(),
    val isLoading: Boolean = false,
    val selectedAppDetail: AppDetailTrafficState? = null
)
