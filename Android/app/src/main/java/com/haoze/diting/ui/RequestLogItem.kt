package com.haoze.diting.ui

import com.haoze.diting.core.log.LogResult
import com.haoze.diting.data.RequestSource
import com.haoze.diting.data.RequestStatus
import com.haoze.diting.data.entity.DnsLogEntity
import com.haoze.diting.data.entity.HttpRequestLogEntity
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class RequestLogItem(
    val key: String,
    val timestamp: Long,
    val source: RequestSource,
    val status: RequestStatus,
    val title: String,
    val subtitle: String,
    val detail: String?,
    val domain: String?,
    val cached: Boolean = false
)

private val requestTimeFormatter = ThreadLocal.withInitial {
    SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
}

private fun formatRequestTime(timestamp: Long): String =
    requestTimeFormatter.get()?.format(Date(timestamp)).orEmpty()

private val directOutcomes = setOf("passthrough", "bypassed", "unsupported_protocol", "resource_bypass")

fun dnsRequestItem(log: DnsLogEntity): RequestLogItem {
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

    return if (isConnection) {
        val proto = if (log.queryName.startsWith("UDP", ignoreCase = true)) "UDP" else "TCP"
        val status = if (isBlocked) RequestStatus.BLOCKED else RequestStatus.BYPASSED
        val tag = if (isBlocked) "${proto}拦截" else "${proto}直连"
        RequestLogItem(
            key = "conn-${log.id}",
            timestamp = log.timestamp,
            source = RequestSource.DNS,
            status = status,
            title = log.queryName,
            subtitle = "${formatRequestTime(log.timestamp)} · $tag$appInfo",
            detail = log.message,
            domain = null,
            cached = false
        )
    } else {
        RequestLogItem(
            key = "dns-${log.id}",
            timestamp = log.timestamp,
            source = RequestSource.DNS,
            status = when {
                rewritten -> RequestStatus.REWRITTEN
                log.result == LogResult.PASSED.value -> RequestStatus.PASSED
                log.result == LogResult.BLOCKED.value -> RequestStatus.BLOCKED
                else -> RequestStatus.ERROR
            },
            title = log.queryName,
            subtitle = "${formatRequestTime(log.timestamp)} · DNS · ${dnsRequestType(log.queryType)}${if (log.cached) " · 命中缓存" else ""}$appInfo",
            detail = log.message,
            domain = log.queryName,
            cached = log.cached
        )
    }
}

fun httpRequestItem(log: HttpRequestLogEntity): RequestLogItem {
    val isBypassed = log.outcome in directOutcomes
    val isError = log.outcome in setOf("decryption_failed", "handshake_failed", "upstream_failed", "error")
    val detail = when {
        isBypassed -> {
            when (log.matchedRule) {
                "passthrough" -> "旁路直连 · 安全白名单 / 证书固定自动旁路"
                "unsupported_protocol" -> "旁路直连 · 不支持的协议直接转发"
                "resource_bypass" -> "旁路直连 · 静态资源旁路"
                null, "" -> "旁路直连 · 未解密直接转发"
                else -> "旁路原因 · ${log.matchedRule}"
            }
        }
        isError -> {
            when (log.matchedRule) {
                "client_tls" -> "握手失败 · 客户端拒绝证书 (可能存在证书绑定/Pinning) 未能建立连接"
                "upstream_tls" -> "上游异常 · 与目标服务器 TLS 握手失败"
                "upstream_dial" -> "建连异常 · 无法连接至上游服务器"
                "upstream_read_failed" -> "传输异常 · 读取上游响应失败"
                "upstream_write_failed" -> "传输异常 · 发送请求至上游失败"
                "client_write_failed" -> "传输异常 · 写回响应至客户端失败"
                "peek_flow_failed" -> "传输异常 · 客户端未发送有效数据或连接超时"
                null, "" -> "请求异常 · 处理过程出错"
                else -> "异常原因 · ${log.matchedRule}"
            }
        }
        else -> {
            log.matchedRule?.takeIf { it.isNotBlank() }?.let { "匹配规则 · $it" }
        }
    }

    val status = when (log.outcome) {
        "allowed" -> RequestStatus.PASSED
        "rewritten" -> RequestStatus.REWRITTEN
        "blocked", "invalid" -> RequestStatus.BLOCKED
        "passthrough", "bypassed", "unsupported_protocol", "resource_bypass" -> RequestStatus.BYPASSED
        else -> RequestStatus.ERROR
    }

    return RequestLogItem(
        key = "https-${log.id}",
        timestamp = log.timestamp,
        source = RequestSource.HTTPS,
        status = status,
        title = log.authority ?: "未取得 authority",
        subtitle = "${formatRequestTime(log.timestamp)} · ${log.protocol} · ${log.packageName}",
        detail = detail,
        domain = log.authority
    )
}

private fun dnsRequestType(type: Int) = when (type) {
    1 -> "A"
    28 -> "AAAA"
    5 -> "CNAME"
    15 -> "MX"
    16 -> "TXT"
    2 -> "NS"
    else -> "TYPE_$type"
}
