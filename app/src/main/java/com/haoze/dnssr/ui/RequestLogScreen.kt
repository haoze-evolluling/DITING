package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.SettingsItemSpacing
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.RequestSource
import com.haoze.dnssr.data.RequestStatus
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.BlockListManager
import com.haoze.dnssr.vpn.LogResult
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsOutlinedActionButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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

@Composable
fun RequestLogScreen(onBack: () -> Unit, onRuntimeDnsSettingsChanged: () -> Unit = {}) {
    val context = LocalContext.current
    val database = remember(context) { AppDatabase.getInstance(context) }
    val viewModel: RequestLogViewModel = androidx.lifecycle.viewmodel.compose.viewModel()
    val state by viewModel.state.collectAsStateWithLifecycle()
    val source = state.source
    val status = state.status
    val query = state.query
    val searching = state.searching
    var pendingDomain by remember { mutableStateOf<String?>(null) }
    var pendingRuleScope by remember { mutableStateOf(RuleScope.DNS) }
    var showStatusDialog by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val visibleItems = state.items
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        if (uri != null) scope.launch {
            val result = runCatching { withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.bufferedWriter()?.use { it.write(requestCsv(visibleItems)) } ?: error("无法打开导出文件") } }
            context.showToast(if (result.isSuccess) "日志已导出" else "导出失败", Toast.LENGTH_SHORT)
        }
    }

    val listState = rememberLazyListState()
    val shouldLoadMore by remember { derivedStateOf {
        val last = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
        visibleItems.isNotEmpty() && last >= visibleItems.lastIndex - 5 && state.hasMore && !state.loading
    } }
    LaunchedEffect(shouldLoadMore) { if (shouldLoadMore) viewModel.loadMore() }

    SettingsScaffold(
        titleContent = {
            if (searching) {
                OutlinedTextField(
                    value = query,
                    onValueChange = viewModel::setQuery,
                    singleLine = true,
                    placeholder = { Text(localizedText("搜索请求")) },
                    shape = RoundedCornerShape(28.dp),
                    modifier = Modifier.fillMaxWidth()
                )
            } else {
                Text(localizedText("请求日志"))
            }
        },
        onBack = onBack,
        actions = {
            if (searching) {
                IconButton(onClick = { if (query.isNotEmpty()) viewModel.setQuery("") else viewModel.setSearching(false) }) {
                    Icon(Icons.Default.Close, localizedText("关闭搜索"))
                }
            } else {
                IconButton(onClick = { viewModel.setSearching(true) }) { Icon(Icons.Default.Search, localizedText("搜索")) }
                IconButton(onClick = { exportLauncher.launch("dnssr-request-logs-${System.currentTimeMillis()}.csv") }) { Icon(Icons.Default.FileDownload, localizedText("导出 CSV")) }
                IconButton(onClick = { showStatusDialog = true }) { Icon(Icons.Default.FilterList, localizedText("选择状态")) }
                IconButton(
                    onClick = {
                        viewModel.refresh()
                        scope.launch {
                            listState.scrollToItem(0)
                        }
                    },
                    enabled = !state.loading
                ) {
                    Icon(Icons.Default.Refresh, localizedText("刷新"))
                }
            }
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            RequestFilterRow(RequestSource.entries, source, { it.label }, viewModel::setSource)
            SettingsDivider()
            if (visibleItems.isEmpty() && !state.loading) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(localizedText("当前筛选下暂无请求日志"), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            else LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)) {
                itemsIndexed(visibleItems, key = { _, it -> it.key }) { index, item ->
                    SettingsSurfaceItem(
                        index = index,
                        itemCount = visibleItems.size
                    ) {
                        RequestLogCard(item) {
                            item.domain?.let { domain ->
                                pendingDomain = domain
                                pendingRuleScope = RuleScope.DNS
                            }
                        }
                    }
                }
                if (state.loading) item { Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { Text(localizedText("正在加载…")) } }
            }
        }
    }
    if (showStatusDialog) {
        AlertDialog(
            onDismissRequest = { showStatusDialog = false },
            title = { Text(localizedText("筛选请求状态")) },
            text = {
                SettingsSurfaceGroup(
                    groupContentPadding = PaddingValues.Zero,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    content = RequestStatus.entries.map { option ->
                        {
                            SettingsItem(
                                title = localizedText(option.label),
                                subtitle = localizedText(option.explanation),
                                onClick = { viewModel.setStatus(option); showStatusDialog = false }
                            ) {
                                if (status == option) {
                                    Icon(
                                        Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        }
                    }
                )
            },
            confirmButton = { TextButton(onClick = { showStatusDialog = false }) { Text(localizedText("取消")) } }
        )
    }
    pendingDomain?.let { domain ->
        DomainActionDialog(domain, { pendingDomain = null }, {
            context.copyToClipboard("domain", domain); pendingDomain = null
        }, { allow ->
            val ruleScope = pendingRuleScope
            scope.launch(Dispatchers.IO) {
                val success = if (allow) {
                    AllowListManager(database.allowRuleDao(), scope = ruleScope).addRule(domain)
                } else {
                    BlockListManager(database.blockRuleDao(), scope = ruleScope).addRule(domain)
                }
                withContext(Dispatchers.Main) {
                    if (success) RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, if (allow) "allow" else "block", domain, ruleScope)
                    context.showToast(if (success) "已添加规则" else "规则格式无效", Toast.LENGTH_SHORT)
                    pendingDomain = null
                }
            }
        })
    }
}

@Composable
private fun <T> RequestFilterRow(values: List<T>, selected: T, label: (T) -> String, select: (T) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        values.forEach { value -> TextButton(onClick = { select(value) }, shape = SettingsCornerShape, colors = ButtonDefaults.textButtonColors(containerColor = if (value == selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent)) { Text(localizedText(label(value))) } }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun RequestLogCard(item: RequestLogItem, onLongClick: () -> Unit) {
    val color = when (item.status) {
        RequestStatus.BLOCKED,
        RequestStatus.ERROR -> MaterialTheme.colorScheme.error
        RequestStatus.BYPASSED -> MaterialTheme.colorScheme.onSurfaceVariant
        RequestStatus.REWRITTEN -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.primary
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = {}, onLongClick = onLongClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(item.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
            Surface(shape = RoundedCornerShape(4.dp), color = color.copy(alpha = .12f)) { Text(localizedText(item.status.label), color = color, style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)) }
        }
        Text(localizedText(item.subtitle), style = MaterialTheme.typography.bodySmall)
        item.detail?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
fun DomainActionDialog(domain: String, dismiss: () -> Unit, copy: () -> Unit, add: (Boolean) -> Unit) {
    AlertDialog(onDismissRequest = dismiss, title = { Text(localizedText("处理域名")) }, text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(domain); SettingsOutlinedActionButton(copy, Modifier.fillMaxWidth()) { Text(localizedText("复制域名")) }; SettingsOutlinedActionButton({ add(true) }, Modifier.fillMaxWidth()) { Text(localizedText("加入白名单规则")) }; SettingsOutlinedActionButton({ add(false) }, Modifier.fillMaxWidth()) { Text(localizedText("加入屏蔽规则")) }
    } }, confirmButton = { TextButton(dismiss) { Text(localizedText("取消")) } })
}

private val requestTime = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
private val directOutcomes = setOf("decryption_failed", "unsupported_protocol", "resource_bypass")

fun dnsRequestItem(log: DnsLogEntity): RequestLogItem {
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

    return if (isConnection) {
        val proto = if (log.queryName.startsWith("UDP", ignoreCase = true)) "UDP" else "TCP"
        RequestLogItem(
            key = "conn-${log.id}",
            timestamp = log.timestamp,
            source = RequestSource.DNS,
            status = RequestStatus.BYPASSED,
            title = log.queryName,
            subtitle = "${requestTime.format(Date(log.timestamp))} · ${proto}直连$appInfo",
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
            subtitle = "${requestTime.format(Date(log.timestamp))} · DNS · ${dnsRequestType(log.queryType)}${if (log.cached) " · 命中缓存" else ""}$appInfo",
            detail = log.message,
            domain = log.queryName,
            cached = log.cached
        )
    }
}

fun httpRequestItem(log: HttpRequestLogEntity): RequestLogItem {
    val isBypassed = log.outcome in directOutcomes
    val detail = if (isBypassed) {
        when (log.matchedRule) {
            "client_tls" -> "旁路原因 · 客户端 TLS 验证或握手未解密"
            "upstream_tls" -> "旁路原因 · 上游服务器 TLS 握手异常"
            "passthrough" -> "旁路原因 · 安全白名单 / 证书固定自动旁路"
            null, "" -> "旁路原因 · 未解密直接转发"
            else -> "旁路原因 · ${log.matchedRule}"
        }
    } else {
        log.matchedRule?.takeIf { it.isNotBlank() }?.let { "匹配规则 · $it" }
    }

    val status = when (log.outcome) {
        "allowed" -> RequestStatus.PASSED
        "rewritten" -> RequestStatus.REWRITTEN
        "blocked", "invalid" -> RequestStatus.BLOCKED
        "decryption_failed", "unsupported_protocol", "resource_bypass" -> RequestStatus.BYPASSED
        else -> RequestStatus.ERROR
    }

    return RequestLogItem(
        key = "https-${log.id}",
        timestamp = log.timestamp,
        source = RequestSource.HTTPS,
        status = status,
        title = log.authority ?: "未取得 authority",
        subtitle = "${requestTime.format(Date(log.timestamp))} · ${log.protocol} · ${log.packageName}",
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
    12 -> "PTR"
    255 -> "ANY"
    else -> "TYPE$type"
}

private fun requestCsv(items: List<RequestLogItem>) = buildString {
    append('\uFEFF')
    appendLine("timestamp,time,source,status,request,details")
    items.forEach {
        appendLine(
            listOf(
                it.timestamp,
                requestTime.format(Date(it.timestamp)),
                it.source.label,
                it.status.label,
                it.title,
                it.subtitle + (it.detail?.let { d -> " · $d" } ?: "")
            ).joinToString(",") { v -> "\"${v.toString().replace("\"", "\"\"")}\"" }
        )
    }
}
