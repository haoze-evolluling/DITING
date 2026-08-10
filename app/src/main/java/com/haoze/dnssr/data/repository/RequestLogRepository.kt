package com.haoze.dnssr.data.repository

import com.haoze.dnssr.data.dao.DnsLogDao
import com.haoze.dnssr.data.dao.HttpRequestLogDao
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

data class RequestLogBatch(
    val dns: List<DnsLogEntity>,
    val http: List<HttpRequestLogEntity>,
    val hasMore: Boolean
)

class RequestLogRepository(
    private val dnsDao: DnsLogDao,
    private val httpDao: HttpRequestLogDao
) {
    suspend fun load(limit: Int): RequestLogBatch = coroutineScope {
        val safeLimit = limit.coerceIn(1, MAX_PAGE_SIZE)
        val dns = async {
            dnsDao.queryList(
                androidx.sqlite.db.SimpleSQLiteQuery(
                    "SELECT * FROM dns_log ORDER BY timestamp DESC LIMIT ?",
                    arrayOf(safeLimit)
                )
            )
        }
        val http = async { httpDao.recent(safeLimit) }
        val dnsRows = dns.await()
        val httpRows = http.await()
        RequestLogBatch(dnsRows, httpRows, dnsRows.size >= safeLimit || httpRows.size >= safeLimit)
    }

    private companion object {
        const val MAX_PAGE_SIZE = 500
    }
}
