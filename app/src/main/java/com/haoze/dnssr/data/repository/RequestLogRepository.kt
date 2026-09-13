package com.haoze.dnssr.data.repository

import androidx.sqlite.db.SimpleSQLiteQuery
import com.haoze.dnssr.data.RequestSource
import com.haoze.dnssr.data.RequestStatus
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
    private val httpDao: HttpRequestLogDao,
    private val onFlushRequested: (suspend () -> Unit)? = null
) {
    companion object {
        var activeFlusher: (suspend () -> Unit)? = null
    }

    suspend fun load(
        limit: Int,
        source: RequestSource = RequestSource.ALL,
        status: RequestStatus = RequestStatus.ALL,
        query: String = ""
    ): RequestLogBatch = coroutineScope {
        runCatching {
            onFlushRequested?.invoke() ?: activeFlusher?.invoke()
        }
        val trimmed = query.trim()

        val dns = async {
            if (source == RequestSource.HTTPS) {
                emptyList()
            } else {
                val sql = StringBuilder("SELECT * FROM dns_log WHERE 1=1")
                val args = mutableListOf<Any>()

                if (trimmed.isNotEmpty()) {
                    sql.append(" AND (queryName LIKE ? OR packageName LIKE ? OR message LIKE ?)")
                    val pattern = "%${trimmed.lowercase()}%"
                    args.add(pattern)
                    args.add(pattern)
                    args.add(pattern)
                }

                when (status) {
                    RequestStatus.ALL -> Unit
                    RequestStatus.PASSED -> {
                        sql.append(" AND result = 'PASSED' AND queryType > 0 AND queryName NOT LIKE 'TCP %' AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR (message NOT LIKE '%blocked_by=connection%' AND message NOT LIKE '%blocked_by=rewrite=%' AND message NOT LIKE '%matched rewrite rule%' AND message NOT LIKE '%复写%' AND message NOT LIKE '%覆写%'))")
                    }
                    RequestStatus.REWRITTEN -> {
                        sql.append(" AND (result = 'REWRITTEN' OR message LIKE '%blocked_by=rewrite=%' OR message LIKE '%matched rewrite rule%' OR message LIKE '%复写%' OR message LIKE '%覆写%') AND queryType > 0 AND queryName NOT LIKE 'TCP %' AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR message NOT LIKE '%blocked_by=connection%')")
                    }
                    RequestStatus.BLOCKED -> {
                        sql.append(" AND (result = 'BLOCKED' OR message LIKE '%blocked_by=firewall:%') AND (message IS NULL OR (message NOT LIKE '%blocked_by=rewrite=%' AND message NOT LIKE '%matched rewrite rule%' AND message NOT LIKE '%复写%' AND message NOT LIKE '%覆写%'))")
                    }
                    RequestStatus.ERROR -> {
                        sql.append(" AND result = 'ERROR' AND queryType > 0 AND queryName NOT LIKE 'TCP %' AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR (message NOT LIKE '%blocked_by=connection%' AND message NOT LIKE '%blocked_by=rewrite=%' AND message NOT LIKE '%matched rewrite rule%' AND message NOT LIKE '%复写%' AND message NOT LIKE '%覆写%'))")
                    }
                    RequestStatus.BYPASSED -> {
                        sql.append(" AND (queryType = 0 OR queryName LIKE 'TCP %' OR queryName LIKE 'UDP %' OR message LIKE '%blocked_by=connection%') AND (message IS NULL OR message NOT LIKE '%blocked_by=firewall:%')")
                    }
                }

                sql.append(" ORDER BY timestamp DESC LIMIT $limit")
                dnsDao.queryList(SimpleSQLiteQuery(sql.toString(), args.toTypedArray()))
            }
        }

        val http = async {
            if (source == RequestSource.DNS) {
                emptyList()
            } else {
                val sql = StringBuilder("SELECT * FROM http_request_log WHERE 1=1")
                val args = mutableListOf<Any>()

                if (trimmed.isNotEmpty()) {
                    sql.append(" AND (authority LIKE ? OR packageName LIKE ? OR matchedRule LIKE ?)")
                    val pattern = "%${trimmed.lowercase()}%"
                    args.add(pattern)
                    args.add(pattern)
                    args.add(pattern)
                }

                when (status) {
                    RequestStatus.ALL -> Unit
                    RequestStatus.PASSED -> {
                        sql.append(" AND outcome = 'allowed'")
                    }
                    RequestStatus.REWRITTEN -> {
                        sql.append(" AND outcome = 'rewritten'")
                    }
                    RequestStatus.BLOCKED -> {
                        sql.append(" AND outcome IN ('blocked', 'invalid')")
                    }
                    RequestStatus.ERROR -> {
                        sql.append(" AND outcome NOT IN ('allowed', 'rewritten', 'blocked', 'invalid', 'passthrough', 'bypassed', 'unsupported_protocol', 'resource_bypass')")
                    }
                    RequestStatus.BYPASSED -> {
                        sql.append(" AND outcome IN ('passthrough', 'bypassed', 'unsupported_protocol', 'resource_bypass')")
                    }
                }

                sql.append(" ORDER BY timestamp DESC LIMIT $limit")
                httpDao.queryList(SimpleSQLiteQuery(sql.toString(), args.toTypedArray()))
            }
        }

        val dnsRows = dns.await()
        val httpRows = http.await()
        RequestLogBatch(dnsRows, httpRows, dnsRows.size >= limit || httpRows.size >= limit)
    }
}
