package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.BootstrapStatsRange
import com.haoze.dnssr.data.RaceStatsRange
import com.haoze.dnssr.data.SubscriptionInterceptionStatsRange
import com.haoze.dnssr.data.entity.DnsCacheEntity
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.data.repository.BootstrapLogRepository
import com.haoze.dnssr.data.repository.DnsCacheRepository
import com.haoze.dnssr.data.repository.DnsLogRepository
import com.haoze.dnssr.data.repository.RaceLogRepository
import com.haoze.dnssr.util.dayStartMillis
import com.haoze.dnssr.vpn.LogResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class DashboardDailyStats(
    val total: Int = 0,
    val passed: Int = 0,
    val blocked: Int = 0,
    val error: Int = 0,
    val bypassed: Int = 0,
    val cached: Int = 0
)

data class DashboardRequestLogItem(
    val timestamp: Long,
    val source: String,
    val name: String,
    val meta: String,
    val status: String,
    val resultLabel: String
)

data class DashboardCacheEntryItem(
    val queryName: String,
    val queryType: String,
    val expiresAt: Long,
    val remainingSeconds: Long,
    val hitCount: Int,
    val responseSize: Int,
    val originalTtlSeconds: Long,
    val lastHitAt: Long
)

data class DashboardRaceWinnerItem(
    val name: String,
    val wins: Int,
    val avgElapsedMs: Double
)

data class DashboardRaceSummary(
    val requests: Int = 0,
    val successes: Int = 0,
    val avgElapsedMs: Double = 0.0,
    val winners: List<DashboardRaceWinnerItem> = emptyList()
)

data class DashboardBootstrapIpItem(
    val name: String,
    val ip: String,
    val attempts: Int,
    val successRate: Double,
    val avgElapsedMs: Double
)

data class DashboardBootstrapSummary(
    val attempts: Int = 0,
    val successes: Int = 0,
    val successRate: Double = 0.0,
    val avgElapsedMs: Double = 0.0,
    val fallbackUses: Int = 0,
    val ips: List<DashboardBootstrapIpItem> = emptyList()
)

data class DashboardSubscriptionItem(
    val name: String,
    val enabled: Boolean,
    val deleted: Boolean,
    val hits: Int,
    val rate: Double
)

data class DashboardSubscriptionSummary(
    val items: List<DashboardSubscriptionItem> = emptyList()
)

data class ModernLogDashboardUiState(
    val loading: Boolean = true,
    val hasData: Boolean = false,
    val generatedAt: Long = 0L,
    val logMode: DnsLogMode = DnsLogMode.ALL,
    val error: String? = null,
    val dailyStats: DashboardDailyStats = DashboardDailyStats(),
    val recentLogs: List<DashboardRequestLogItem> = emptyList(),
    val cacheEntries: List<DashboardCacheEntryItem> = emptyList(),
    val race: DashboardRaceSummary = DashboardRaceSummary(),
    val bootstrap: DashboardBootstrapSummary = DashboardBootstrapSummary(),
    val subscriptions: DashboardSubscriptionSummary = DashboardSubscriptionSummary()
)

class ModernLogDashboardViewModel(application: Application) : AndroidViewModel(application) {
    private val database = AppDatabase.getInstance(application)
    private val dnsLogRepository = DnsLogRepository(database.dnsLogDao(), database.httpRequestLogDao())
    private val dnsCacheRepository = DnsCacheRepository(database.dnsCacheDao())
    private val raceLogRepository = RaceLogRepository(database.raceLogDao())
    private val bootstrapLogRepository = BootstrapLogRepository(application, database.bootstrapLogDao())

    private val _uiState = MutableStateFlow(ModernLogDashboardUiState())
    val uiState: StateFlow<ModernLogDashboardUiState> = _uiState.asStateFlow()

    fun refresh() {
        viewModelScope.launch(Dispatchers.IO) {
            _uiState.value = _uiState.value.copy(loading = true, error = null)
            val result = runCatching { buildDashboardState() }
            _uiState.value = result.fold(
                onSuccess = { it },
                onFailure = { error ->
                    _uiState.value.copy(
                        loading = false,
                        hasData = _uiState.value.hasData,
                        generatedAt = System.currentTimeMillis(),
                        error = error.message ?: "加载失败"
                    )
                }
            )
        }
    }

    private suspend fun buildDashboardState(): ModernLogDashboardUiState {
        val now = System.currentTimeMillis()
        val logMode = AppSettings.getDnsLogMode(getApplication())
        val storedDailyStats = if (logMode == DnsLogMode.OFF) null else dnsLogRepository.dailyStats(dayStartMillis())
        val dailyStats = storedDailyStats?.let {
            if (logMode == DnsLogMode.BLOCKED_AND_ERRORS) it.copy(passed = 0, cached = 0) else it
        }
        val recentLogs = dnsLogRepository.recentLogs(RECENT_LOG_LIMIT, logMode)
        val recentHttpLogs = if (logMode == DnsLogMode.OFF) {
            emptyList()
        } else {
            database.httpRequestLogDao().recent(RECENT_LOG_LIMIT)
                .filter { logMode == DnsLogMode.ALL || normalizeHttpOutcome(it.outcome) != "passed" }
        }
        val httpStats = if (logMode == DnsLogMode.OFF) {
            emptyList()
        } else {
            database.httpRequestLogDao().dailyStats(dayStartMillis())
        }
        var httpPassed = 0
        var httpBlocked = 0
        var httpError = 0
        var httpBypassed = 0
        httpStats.filter { logMode == DnsLogMode.ALL || normalizeHttpOutcome(it.outcome) != "passed" }
            .forEach { row ->
                when (normalizeHttpOutcome(row.outcome)) {
                    "passed" -> httpPassed += row.count
                    "blocked" -> httpBlocked += row.count
                    "bypassed" -> httpBypassed += row.count
                    else -> httpError += row.count
                }
            }
        val recentCacheEntries = dnsCacheRepository.recentEntries(now, RECENT_CACHE_LIMIT)
        val raceStats = raceLogRepository.stats(RaceStatsRange.TODAY)
        val bootstrapStats = bootstrapLogRepository.stats(BootstrapStatsRange.TODAY)
        val subscriptionStats = if (logMode == DnsLogMode.OFF) {
            null
        } else {
            dnsLogRepository.subscriptionInterceptionStats(SubscriptionInterceptionStatsRange.TODAY)
        }
        val subscriptions = if (logMode == DnsLogMode.OFF) {
            emptyList()
        } else {
            database.subscriptionDao().allByKind(SubscriptionKind.BLOCK)
        }
        val subscriptionsById = subscriptions.associateBy { it.id }
        val subscriptionItems = (subscriptionsById.keys + subscriptionStats?.hitsBySubscriptionId.orEmpty().keys)
            .map { id ->
                val subscription = subscriptionsById[id]
                val hits = subscriptionStats?.hitsBySubscriptionId?.get(id) ?: 0
                DashboardSubscriptionItem(
                    name = subscription?.name ?: "已删除订阅 #$id",
                    enabled = subscription?.enabled ?: false,
                    deleted = subscription == null,
                    hits = hits,
                    rate = if (subscriptionStats == null || subscriptionStats.totalRequests == 0) {
                        0.0
                    } else {
                        hits.toDouble() / subscriptionStats.totalRequests
                    }
                )
            }
            .sortedByDescending { it.hits }
            .take(SUBSCRIPTION_LIST_LIMIT)

        val passed = (dailyStats?.passed ?: 0) + httpPassed
        val blocked = (dailyStats?.blocked ?: 0) + httpBlocked
        val errors = (dailyStats?.error ?: 0) + httpError
        val totalLogs = passed + blocked + errors + httpBypassed

        return ModernLogDashboardUiState(
            loading = false,
            hasData = true,
            generatedAt = now,
            logMode = logMode,
            error = null,
            dailyStats = DashboardDailyStats(
                total = totalLogs,
                passed = passed,
                blocked = blocked,
                error = errors,
                bypassed = httpBypassed,
                cached = dailyStats?.cached ?: 0
            ),
            recentLogs = mergedRequestLogs(recentLogs, recentHttpLogs),
            cacheEntries = recentCacheEntries.toCacheItems(now),
            race = DashboardRaceSummary(
                requests = raceStats.strategyStats.sumOf { it.requests },
                successes = raceStats.strategyStats.sumOf { it.successes },
                avgElapsedMs = raceStats.strategyStats.weightedAverage { it.avgElapsedMs to it.requests },
                winners = raceStats.winnerStats.take(TOP_LIST_LIMIT).map { item ->
                    DashboardRaceWinnerItem(
                        name = item.providerName,
                        wins = item.wins,
                        avgElapsedMs = item.avgWinnerElapsedMs
                    )
                }
            ),
            bootstrap = DashboardBootstrapSummary(
                attempts = bootstrapStats.overall.attempts,
                successes = bootstrapStats.overall.successes,
                successRate = bootstrapStats.overall.successRate,
                avgElapsedMs = bootstrapStats.overall.avgElapsedMs,
                fallbackUses = bootstrapStats.overall.fallbackUses,
                ips = bootstrapStats.ipStats.take(TOP_LIST_LIMIT).map { item ->
                    DashboardBootstrapIpItem(
                        name = item.ipName,
                        ip = item.ip,
                        attempts = item.attempts,
                        successRate = item.successRate,
                        avgElapsedMs = item.avgElapsedMs
                    )
                }
            ),
            subscriptions = DashboardSubscriptionSummary(items = subscriptionItems)
        )
    }

    private fun mergedRequestLogs(
        dnsLogs: List<DnsLogEntity>,
        httpLogs: List<HttpRequestLogEntity>
    ): List<DashboardRequestLogItem> {
        val rows = dnsLogs.map { log ->
            DashboardRequestLogItem(
                timestamp = log.timestamp,
                source = "DNS",
                name = log.queryName,
                meta = buildString {
                    append(dnsTypeName(log.queryType))
                    if (log.cached) append(" · 命中缓存")
                    log.message?.let { append(" · ").append(it) }
                },
                status = when (log.result) {
                    LogResult.PASSED.value -> "passed"
                    LogResult.BLOCKED.value -> "blocked"
                    else -> "error"
                },
                resultLabel = resultLabel(log.result)
            )
        } + httpLogs.map { log ->
            val status = normalizeHttpOutcome(log.outcome)
            DashboardRequestLogItem(
                timestamp = log.timestamp,
                source = "HTTPS",
                name = log.authority ?: "未取得 authority",
                meta = buildString {
                    append(log.protocol)
                    append(" · ")
                    append(log.packageName)
                    log.matchedRule?.let { append(" · ").append(it) }
                },
                status = status,
                resultLabel = when (status) {
                    "passed" -> "通过"
                    "blocked" -> "过滤"
                    "bypassed" -> "旁路"
                    else -> "失败"
                }
            )
        }
        return rows.sortedByDescending { it.timestamp }.take(RECENT_LOG_LIMIT)
    }

    private fun List<DnsCacheEntity>.toCacheItems(now: Long): List<DashboardCacheEntryItem> {
        return map { entry ->
            DashboardCacheEntryItem(
                queryName = entry.queryName,
                queryType = dnsTypeName(entry.queryType),
                expiresAt = entry.expiresAt,
                remainingSeconds = ((entry.expiresAt - now).coerceAtLeast(0L) + 999L) / 1000L,
                hitCount = entry.hitCount,
                responseSize = entry.responseSize,
                originalTtlSeconds = entry.originalTtlSeconds,
                lastHitAt = entry.lastHitAt ?: 0L
            )
        }
    }

    private fun resultLabel(result: String): String {
        return when (result) {
            LogResult.PASSED.value -> "通过"
            LogResult.REWRITTEN.value -> "覆写"
            LogResult.BLOCKED.value -> "过滤"
            LogResult.ERROR.value -> "失败"
            else -> result
        }
    }

    private fun normalizeHttpOutcome(outcome: String): String = when (outcome.lowercase()) {
        "allowed", "rewritten", "passed", "success" -> "passed"
        "blocked", "invalid", "filtered", "denied" -> "blocked"
        "decryption_failed", "unsupported_protocol", "resource_bypass", "bypassed", "passthrough" -> "bypassed"
        else -> "error"
    }

    private fun dnsTypeName(type: Int): String {
        return when (type) {
            1 -> "A"
            28 -> "AAAA"
            5 -> "CNAME"
            15 -> "MX"
            16 -> "TXT"
            2 -> "NS"
            12 -> "PTR"
            255 -> "ANY"
            else -> "TYPE$type"
        }
    }

    private fun <T> List<T>.weightedAverage(valueAndWeight: (T) -> Pair<Double, Int>): Double {
        var weightedTotal = 0.0
        var totalWeight = 0
        forEach { item ->
            val (value, weight) = valueAndWeight(item)
            weightedTotal += value * weight
            totalWeight += weight
        }
        return if (totalWeight == 0) 0.0 else weightedTotal / totalWeight
    }

    private companion object {
        private const val RECENT_LOG_LIMIT = 5
        private const val RECENT_CACHE_LIMIT = 5
        private const val SUBSCRIPTION_LIST_LIMIT = 5
        private const val TOP_LIST_LIMIT = 8
    }
}
