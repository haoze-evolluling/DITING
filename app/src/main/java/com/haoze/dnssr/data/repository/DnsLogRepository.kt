package com.haoze.dnssr.data.repository

import androidx.paging.PagingSource
import androidx.paging.PagingState
import androidx.sqlite.db.SimpleSQLiteQuery
import com.haoze.dnssr.data.LogDailyStats
import com.haoze.dnssr.data.LogFilter
import com.haoze.dnssr.data.LogQueryParams
import com.haoze.dnssr.data.SubscriptionInterceptionStats
import com.haoze.dnssr.data.SubscriptionInterceptionStatsRange
import com.haoze.dnssr.data.dao.DailyStatRow
import com.haoze.dnssr.data.dao.DnsLogDao
import com.haoze.dnssr.data.dao.HttpRequestLogDao
import com.haoze.dnssr.vpn.HttpRequestOutcome
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.vpn.LogResult
import com.haoze.dnssr.util.dayStartMillis
import com.haoze.dnssr.ui.DnsLogMode

class DnsLogRepository(
    private val dao: DnsLogDao,
    private val httpRequestLogDao: HttpRequestLogDao? = null
) {

    companion object {
        const val PAGE_SIZE = 50
        private const val SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000L
    }

    fun logsPagingSource(params: LogQueryParams): PagingSource<Int, DnsLogEntity> {
        return DnsLogPagingSource(params)
    }

    suspend fun count(params: LogQueryParams): Int {
        return dao.count(buildCountQuery(params))
    }

    suspend fun exportLogs(params: LogQueryParams): List<DnsLogEntity> {
        val args = mutableListOf<Any>()
        val sql = StringBuilder("SELECT * FROM dns_log WHERE 1=1")
        appendFilter(sql, args, params)
        sql.append(" ORDER BY timestamp DESC")
        return dao.queryList(SimpleSQLiteQuery(sql.toString(), args.toTypedArray()))
    }

    suspend fun recentLogs(limit: Int): List<DnsLogEntity> {
        return dao.queryList(
            SimpleSQLiteQuery(
                "SELECT * FROM dns_log ORDER BY timestamp DESC LIMIT ?",
                arrayOf(limit.coerceAtLeast(0))
            )
        )
    }

    suspend fun recentLogs(limit: Int, mode: DnsLogMode): List<DnsLogEntity> {
        if (mode == DnsLogMode.OFF) return emptyList()
        val where = if (mode == DnsLogMode.BLOCKED_AND_ERRORS) {
            "WHERE result IN ('${LogResult.BLOCKED.value}', '${LogResult.ERROR.value}') "
        } else {
            ""
        }
        return dao.queryList(
            SimpleSQLiteQuery(
                "SELECT * FROM dns_log $where ORDER BY timestamp DESC LIMIT ?",
                arrayOf(limit.coerceAtLeast(0))
            )
        )
    }

    suspend fun dailyStats(since: Long): LogDailyStats {
        val rows = dao.dailyStats(since)
        var passed = 0
        var blocked = 0
        var error = 0
        var cached = 0
        rows.forEach { row ->
            when (row.result) {
                LogResult.PASSED.value -> {
                    passed += row.count
                    if (row.cached) cached += row.count
                }
                LogResult.BLOCKED.value -> blocked += row.count
                LogResult.ERROR.value -> error += row.count
            }
        }
        return LogDailyStats(passed, blocked, error, cached)
    }

    suspend fun subscriptionInterceptionStats(
        range: SubscriptionInterceptionStatsRange
    ): SubscriptionInterceptionStats {
        val since = when (range) {
            SubscriptionInterceptionStatsRange.TODAY -> dayStartMillis()
            SubscriptionInterceptionStatsRange.SEVEN_DAYS -> System.currentTimeMillis() - SEVEN_DAYS_MS
            SubscriptionInterceptionStatsRange.ALL -> 0L
        }
        val dnsTotal = dao.countSince(since)
        val httpsTotal = httpRequestLogDao?.countSince(since) ?: 0
        val hits = mutableMapOf<Long, Int>()
        dao.subscriptionInterceptionStats(since, LogResult.BLOCKED.value).forEach { row ->
            hits[row.subscriptionId] = (hits[row.subscriptionId] ?: 0) + row.hits
        }
        httpRequestLogDao
            ?.subscriptionInterceptionStats(since, HttpRequestOutcome.BLOCKED.storageValue)
            ?.forEach { row ->
                hits[row.subscriptionId] = (hits[row.subscriptionId] ?: 0) + row.hits
            }
        return SubscriptionInterceptionStats(
            totalRequests = dnsTotal + httpsTotal,
            hitsBySubscriptionId = hits
        )
    }

    private fun buildCountQuery(params: LogQueryParams): SimpleSQLiteQuery {
        val args = mutableListOf<Any>()
        val sql = StringBuilder("SELECT COUNT(*) FROM dns_log WHERE 1=1")
        appendFilter(sql, args, params)
        return SimpleSQLiteQuery(sql.toString(), args.toTypedArray())
    }

    private fun appendFilter(sql: StringBuilder, args: MutableList<Any>, params: LogQueryParams) {
        val trimmed = params.query.trim()
        if (trimmed.isNotEmpty()) {
            sql.append(" AND queryName LIKE ?")
            args.add("%${trimmed.lowercase()}%")
        }
        when (params.filter) {
            LogFilter.PASSED -> { sql.append(" AND result = ?"); args.add(LogResult.PASSED.value) }
            LogFilter.BLOCKED -> { sql.append(" AND result = ?"); args.add(LogResult.BLOCKED.value) }
            LogFilter.ERROR -> { sql.append(" AND result = ?"); args.add(LogResult.ERROR.value) }
            LogFilter.CACHED -> {
                sql.append(" AND result = ? AND cached = 1")
                args.add(LogResult.PASSED.value)
            }
            LogFilter.ALL -> Unit
        }
    }

    /**
     * 自定义 PagingSource，不注册 Room InvalidationTracker，
     * 避免新记录插入时自动刷新列表，仅在用户手动刷新时才加载新数据。
     */
    private inner class DnsLogPagingSource(
        private val queryParams: LogQueryParams
    ) : PagingSource<Int, DnsLogEntity>() {

        override suspend fun load(params: LoadParams<Int>): LoadResult<Int, DnsLogEntity> {
            val offset = params.key ?: 0
            val limit = params.loadSize

            val args = mutableListOf<Any>()
            val sql = StringBuilder("SELECT * FROM dns_log WHERE 1=1")
            appendFilter(sql, args, queryParams)
            sql.append(" ORDER BY timestamp DESC LIMIT $limit OFFSET $offset")

            val items = dao.queryList(SimpleSQLiteQuery(sql.toString(), args.toTypedArray()))

            return LoadResult.Page(
                data = items,
                prevKey = if (offset == 0) null else offset,
                nextKey = if (items.size < limit) null else offset + items.size
            )
        }

        override fun getRefreshKey(state: PagingState<Int, DnsLogEntity>): Int? {
            return state.anchorPosition?.let { anchorPosition ->
                state.closestPageToPosition(anchorPosition)?.prevKey
            }
        }
    }
}
