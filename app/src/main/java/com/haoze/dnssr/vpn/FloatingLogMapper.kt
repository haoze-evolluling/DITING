package com.haoze.dnssr.vpn

import android.content.Context
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import com.haoze.dnssr.data.repository.RequestLogRepository
import com.haoze.dnssr.ui.localizedText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date

/**
 * Handles conversion from database log entities (DNS and HTTP) into presentation log items,
 * and loading recent logs asynchronously.
 */
object FloatingLogMapper {

    fun fromDnsLog(
        log: DnsLogEntity,
        context: Context,
        timeFormatter: SimpleDateFormat
    ): FloatingLogItem {
        val message = log.message.orEmpty()
        val isConnection = log.queryType == 0 ||
            message.contains("blocked_by=connection", ignoreCase = true) ||
            log.queryName.startsWith("TCP ", ignoreCase = true) ||
            log.queryName.startsWith("UDP ", ignoreCase = true)
        val rewritten = log.result == LogResult.REWRITTEN.value ||
            message.contains("matched rewrite rule", ignoreCase = true) ||
            message.contains("blocked_by=rewrite=", ignoreCase = true) ||
            message.contains("复写") || message.contains("覆写")
        val appInfo = log.packageName?.let { " · $it" } ?: ""
        val time = timeFormatter.format(Date(log.timestamp))

        return if (isConnection) {
            val proto = if (log.queryName.startsWith("UDP", ignoreCase = true)) "UDP" else "TCP"
            FloatingLogItem(
                timestamp = log.timestamp,
                title = log.queryName,
                subtitle = localizedText(context, "$time · ${proto}直连$appInfo"),
                detail = log.message?.takeIf { it.isNotBlank() },
                status = FloatingLogStatus.BYPASSED
            )
        } else {
            val status = when {
                rewritten -> FloatingLogStatus.REWRITTEN
                log.result == LogResult.PASSED.value -> FloatingLogStatus.PASSED
                log.result == LogResult.BLOCKED.value -> FloatingLogStatus.BLOCKED
                else -> FloatingLogStatus.ERROR
            }
            val queryType = dnsType(log.queryType)
            val cachedInfo = if (log.cached) " · 命中缓存" else ""
            FloatingLogItem(
                timestamp = log.timestamp,
                title = log.queryName,
                subtitle = localizedText(context, "$time · DNS · $queryType$cachedInfo$appInfo"),
                detail = log.message?.takeIf { it.isNotBlank() },
                status = status
            )
        }
    }

    fun fromHttpLog(
        log: HttpRequestLogEntity,
        context: Context,
        timeFormatter: SimpleDateFormat
    ): FloatingLogItem {
        val isBypassed = log.outcome in setOf("decryption_failed", "unsupported_protocol", "resource_bypass")
        val status = when (log.outcome) {
            "allowed" -> FloatingLogStatus.PASSED
            "rewritten" -> FloatingLogStatus.REWRITTEN
            "blocked", "invalid" -> FloatingLogStatus.BLOCKED
            "decryption_failed", "unsupported_protocol", "resource_bypass" -> FloatingLogStatus.BYPASSED
            else -> FloatingLogStatus.ERROR
        }
        val time = timeFormatter.format(Date(log.timestamp))
        val detail = if (isBypassed) {
            val reason = when (log.matchedRule) {
                "client_tls" -> "客户端 TLS 验证或握手未解密"
                "upstream_tls" -> "上游服务器 TLS 握手异常"
                "passthrough" -> "安全白名单 / 证书固定自动旁路"
                null, "" -> "未解密直接转发"
                else -> log.matchedRule
            }
            localizedText(context, "旁路原因 · $reason")
        } else {
            log.matchedRule?.takeIf { it.isNotBlank() }?.let { localizedText(context, "匹配规则 · $it") }
        }

        return FloatingLogItem(
            timestamp = log.timestamp,
            title = log.authority ?: localizedText(context, "未取得 authority"),
            subtitle = "$time · ${log.protocol} · ${log.packageName}",
            detail = detail,
            status = status
        )
    }

    fun dnsType(type: Int): String = when (type) {
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

    suspend fun loadRecentLogs(
        repository: RequestLogRepository,
        context: Context,
        timeFormatter: SimpleDateFormat,
        limit: Int = 30
    ): List<FloatingLogItem> = runCatching {
        withContext(Dispatchers.IO) {
            val batch = repository.load(limit)
            (batch.dns.map { fromDnsLog(it, context, timeFormatter) } +
                batch.http.map { fromHttpLog(it, context, timeFormatter) })
                .sortedByDescending { it.timestamp }
                .take(limit)
        }
    }.getOrElse { emptyList() }
}
