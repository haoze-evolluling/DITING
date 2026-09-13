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
        val isBlocked = log.result == LogResult.BLOCKED.value ||
            message.contains("blocked_by=firewall:", ignoreCase = true)
        val isConnection = log.queryType == 0 ||
            message.contains("blocked_by=connection", ignoreCase = true) ||
            message.contains("blocked_by=firewall:", ignoreCase = true) ||
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
            val status = if (isBlocked) FloatingLogStatus.BLOCKED else FloatingLogStatus.BYPASSED
            val tag = if (isBlocked) "${proto}拦截" else "${proto}直连"
            FloatingLogItem(
                timestamp = log.timestamp,
                title = log.queryName,
                subtitle = localizedText(context, "$time · $tag$appInfo"),
                detail = log.message?.takeIf { it.isNotBlank() },
                status = status
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
        val isBypassed = log.outcome in setOf("passthrough", "bypassed", "unsupported_protocol", "resource_bypass")
        val isError = log.outcome in setOf("decryption_failed", "handshake_failed", "upstream_failed", "error")
        val status = when (log.outcome) {
            "allowed" -> FloatingLogStatus.PASSED
            "rewritten" -> FloatingLogStatus.REWRITTEN
            "blocked", "invalid" -> FloatingLogStatus.BLOCKED
            "passthrough", "bypassed", "unsupported_protocol", "resource_bypass" -> FloatingLogStatus.BYPASSED
            else -> FloatingLogStatus.ERROR
        }
        val time = timeFormatter.format(Date(log.timestamp))
        val detail = when {
            isBypassed -> {
                val reason = when (log.matchedRule) {
                    "passthrough" -> "安全白名单 / 证书固定自动旁路"
                    "unsupported_protocol" -> "不支持的协议直接转发"
                    "resource_bypass" -> "静态资源旁路"
                    null, "" -> "未解密直接转发"
                    else -> log.matchedRule
                }
                localizedText(context, "旁路原因 · $reason")
            }
            isError -> {
                val reason = when (log.matchedRule) {
                    "client_tls" -> "客户端拒绝证书 (可能存在证书绑定/Pinning)"
                    "upstream_tls" -> "上游服务器 TLS 握手异常"
                    "upstream_dial" -> "上游服务器连接失败"
                    "upstream_read_failed" -> "读取上游响应失败"
                    "upstream_write_failed" -> "发送请求至上游失败"
                    "client_write_failed" -> "写回响应至客户端失败"
                    "peek_flow_failed" -> "客户端未发送有效数据或连接超时"
                    null, "" -> "处理过程出错"
                    else -> log.matchedRule
                }
                localizedText(context, "异常原因 · $reason")
            }
            else -> {
                log.matchedRule?.takeIf { it.isNotBlank() }?.let { localizedText(context, "匹配规则 · $it") }
            }
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
