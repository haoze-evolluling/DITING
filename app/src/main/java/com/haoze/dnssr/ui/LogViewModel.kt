package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.LogDailyStats
import com.haoze.dnssr.data.LogFilter
import com.haoze.dnssr.data.LogQueryParams
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.data.repository.DnsLogRepository
import com.haoze.dnssr.util.dayStartMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
class LogViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = DnsLogRepository(AppDatabase.getInstance(application).dnsLogDao())

    private val _activated = MutableStateFlow(false)
    private val _params = MutableStateFlow(LogQueryParams(LogFilter.ALL, ""))
    val params: StateFlow<LogQueryParams> = _params.asStateFlow()

    private val _dailyStats = MutableStateFlow(LogDailyStats(0, 0, 0, 0))
    val dailyStats: StateFlow<LogDailyStats> = _dailyStats.asStateFlow()

    fun activate() { _activated.value = true }

    val logs: Flow<PagingData<DnsLogEntity>> = _activated
        .filter { it }
        .flatMapLatest {
            _params
                .debounce { if (it.query.isBlank()) 0L else 300L }
                .flatMapLatest { p ->
                    Pager(
                        config = PagingConfig(
                            pageSize = DnsLogRepository.PAGE_SIZE,
                            enablePlaceholders = false
                        ),
                        pagingSourceFactory = { repository.logsPagingSource(p) }
                    ).flow
                }
        }
        .cachedIn(viewModelScope)

    init {
        viewModelScope.launch(Dispatchers.IO) {
            loadDailyStats()
        }
    }

    fun onSearchQueryChange(query: String) {
        _params.update { it.copy(query = query, filter = LogFilter.ALL) }
    }

    fun onFilterChange(filter: LogFilter) {
        _params.update { it.copy(filter = filter) }
    }

    fun refresh() {
        viewModelScope.launch(Dispatchers.IO) {
            loadDailyStats()
        }
    }

    suspend fun exportCurrentLogsCsv(): String = withContext(Dispatchers.IO) {
        val logs = repository.exportLogs(_params.value)
        buildString {
            append('\uFEFF')
            appendLine("timestamp,time,queryName,queryType,result,cached,message")
            logs.forEach { log ->
                appendSpreadsheetTextField(log.timestamp.toString())
                append(',')
                appendSpreadsheetTextField(exportTimeFormatter.format(Date(log.timestamp)))
                append(',')
                appendCsvField(log.queryName)
                append(',')
                appendCsvField(log.queryType.toString())
                append(',')
                appendCsvField(log.result)
                append(',')
                appendCsvField(if (log.cached) "true" else "false")
                append(',')
                appendCsvField(log.message.orEmpty())
                appendLine()
            }
        }
    }

    fun exportFileName(): String {
        return "dnssr-logs-${fileNameTimeFormatter.format(Date())}.csv"
    }

    private suspend fun loadDailyStats() {
        _dailyStats.value = repository.dailyStats(dayStartMillis())
    }

    private fun StringBuilder.appendCsvField(value: String) {
        append('"')
        value.forEach { char ->
            if (char == '"') append("\"\"") else append(char)
        }
        append('"')
    }

    private fun StringBuilder.appendSpreadsheetTextField(value: String) {
        // Excel/WPS will otherwise auto-detect millisecond timestamps as scientific notation
        // and date-time values as narrow date cells ("#######"). A leading tab keeps the
        // visible value as text when users open the CSV directly in spreadsheet apps.
        appendCsvField("\t$value")
    }

    private companion object {
        val exportTimeFormatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())
        val fileNameTimeFormatter = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.getDefault())
    }
}
