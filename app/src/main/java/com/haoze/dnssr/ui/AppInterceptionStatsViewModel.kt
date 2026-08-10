package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppInterceptionStatsRange
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.util.dayStartMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AppInterceptionStatItem(
    val packageName: String,
    val appName: String,
    val total: Int,
    val blocked: Int,
    val allowed: Int,
    val bypassed: Int,
    val errors: Int,
    val lastTimestamp: Long
) {
    val blockRate: Double
        get() = if (total == 0) 0.0 else blocked.toDouble() / total
}

data class AppInterceptionStatsSummary(
    val total: Int = 0,
    val blocked: Int = 0,
    val allowed: Int = 0,
    val bypassed: Int = 0,
    val errors: Int = 0
) {
    val blockRate: Double
        get() = if (total == 0) 0.0 else blocked.toDouble() / total
}

class AppInterceptionStatsViewModel(application: Application) : AndroidViewModel(application) {
    private val database = AppDatabase.getInstance(application)
    private val packageManager = application.packageManager

    private val _range = MutableStateFlow(AppInterceptionStatsRange.TODAY)
    val range: StateFlow<AppInterceptionStatsRange> = _range.asStateFlow()

    private val _summary = MutableStateFlow(AppInterceptionStatsSummary())
    val summary: StateFlow<AppInterceptionStatsSummary> = _summary.asStateFlow()

    private val _items = MutableStateFlow<List<AppInterceptionStatItem>>(emptyList())
    val items: StateFlow<List<AppInterceptionStatItem>> = _items.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    fun setRange(range: AppInterceptionStatsRange) {
        if (_range.value == range) return
        _range.value = range
        refresh()
    }

    fun refresh() {
        viewModelScope.launch(Dispatchers.IO) {
            _loading.value = true
            try {
                val rows = database.httpRequestLogDao().appInterceptionStats(
                    since = since(_range.value),
                    limit = MAX_APPS
                )
                _summary.value = AppInterceptionStatsSummary(
                    total = rows.sumOf { it.total },
                    blocked = rows.sumOf { it.blocked },
                    allowed = rows.sumOf { it.allowed },
                    bypassed = rows.sumOf { it.bypassed },
                    errors = rows.sumOf { it.errors }
                )
                _items.value = rows.map { row ->
                    AppInterceptionStatItem(
                        packageName = row.packageName,
                        appName = applicationLabel(row.packageName),
                        total = row.total,
                        blocked = row.blocked,
                        allowed = row.allowed,
                        bypassed = row.bypassed,
                        errors = row.errors,
                        lastTimestamp = row.lastTimestamp
                    )
                }
            } finally {
                _loading.value = false
            }
        }
    }

    private fun applicationLabel(packageName: String): String = runCatching {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0)).toString()
    }.getOrDefault(packageName)

    private fun since(range: AppInterceptionStatsRange): Long = when (range) {
        AppInterceptionStatsRange.TODAY -> dayStartMillis()
        AppInterceptionStatsRange.SEVEN_DAYS -> dayStartMillis() - 6L * DAY_MS
        AppInterceptionStatsRange.ALL -> 0L
    }

    private companion object {
        const val MAX_APPS = 100
        const val DAY_MS = 24L * 60L * 60L * 1_000L
    }
}
