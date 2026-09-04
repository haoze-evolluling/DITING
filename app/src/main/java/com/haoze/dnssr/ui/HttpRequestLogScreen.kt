package com.haoze.dnssr.ui

import android.widget.Toast
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ErrorOutline
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.SettingsItemSpacing
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.BlockListManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private enum class HttpLogFilter(val label: String) {
    ALL("全部"),
    ALLOWED("放行"),
    REWRITTEN("覆写"),
    BLOCKED("拦截"),
    BYPASSED("直连")
}

private data class HttpLogFilterOption(
    val filter: HttpLogFilter,
    val count: Int,
    val color: Color
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HttpRequestLogScreen(onBack: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val database = remember(context) { AppDatabase.getInstance(context) }
    var loadLimit by remember { mutableStateOf(50) }
    val logs by remember(context, loadLimit) {
        AppDatabase.getInstance(context).httpRequestLogDao().observeRecent(loadLimit)
    }.collectAsStateWithLifecycle(initialValue = emptyList())
    var selectedFilter by remember { mutableStateOf(HttpLogFilter.ALL) }
    var showExplanation by remember { mutableStateOf(false) }
    var initialScrollDone by remember { mutableStateOf(false) }
    var pendingDomain by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val filteredLogs = remember(logs, selectedFilter) {
        logs.filter { log ->
            when (selectedFilter) {
                HttpLogFilter.ALL -> true
                HttpLogFilter.ALLOWED -> log.outcome == "allowed"
                HttpLogFilter.REWRITTEN -> log.outcome == "rewritten"
                HttpLogFilter.BLOCKED -> log.outcome == "blocked" || log.outcome == "invalid"
                HttpLogFilter.BYPASSED -> log.outcome in directOutcomes
            }
        }
    }
    val listState = rememberLazyListState()
    val shouldLoadMore by remember { derivedStateOf {
        val last = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
        initialScrollDone && listState.firstVisibleItemIndex > 0 && filteredLogs.isNotEmpty() && last >= filteredLogs.lastIndex - 5 && logs.size >= loadLimit
    } }
    LaunchedEffect(logs.isNotEmpty()) {
        if (!initialScrollDone && logs.isNotEmpty()) {
            listState.scrollToItem(0)
            initialScrollDone = true
        }
    }
    LaunchedEffect(shouldLoadMore) { if (shouldLoadMore) loadLimit += 50 }
    LaunchedEffect(filteredLogs.isNotEmpty()) {
        if (filteredLogs.isNotEmpty()) listState.scrollToItem(0)
    }

    SettingsScaffold(
        title = localizedText("HTTPS 请求记录"),
        onBack = onBack,
        actions = {
            IconButton(onClick = { showExplanation = true }) {
                Icon(
                    imageVector = Icons.Outlined.ErrorOutline,
                    contentDescription = localizedText("请求记录说明")
                )
            }
        }
    ) { innerPadding ->
        Column(Modifier.fillMaxSize().padding(innerPadding)) {
            HttpLogFilterBar(logs, selectedFilter, onFilterChange = { selectedFilter = it })
            SettingsDivider()
            if (logs.isEmpty()) {
                EmptyHttpLogMessage()
            } else if (filteredLogs.isEmpty()) {
                EmptyHttpLogMessage("当前筛选下暂无请求记录")
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
                ) {
                    itemsIndexed(filteredLogs, key = { _, log -> log.id }) { index, log ->
                        SettingsSurfaceItem(
                            index = index,
                            itemCount = filteredLogs.size
                        ) {
                            HttpRequestLogCard(log) { log.authority?.let { pendingDomain = it } }
                        }
                    }
                }
            }
        }
    }

    if (showExplanation) {
        AlertDialog(
            onDismissRequest = { showExplanation = false },
            title = { Text(localizedText("请求记录说明")) },
            text = {
                Text(
                    localizedText(
                        "“已放行/已拦截”表示谛听已读取 HTTP 请求的 authority，并已按现有域名规则完成匹配。\n\n" +
                            "“HTTPS 检查自动旁路”表示 HTTPS 流量检查因证书固定、双向 TLS、EV 证书、安全域名策略或握手失败而直接转发连接，未读取其中的 HTTP 请求。\n\n" +
                            "请求记录只保存应用、authority、协议、结果、匹配规则和时间，不保存路径、请求头或正文。"
                    )
                )
            },
            confirmButton = {
                TextButton(onClick = { showExplanation = false }) { Text(localizedText("知道了")) }
            }
        )
    }
    pendingDomain?.let { domain ->
        DomainActionDialog(
            domain = domain,
            dismiss = { pendingDomain = null },
            copy = {
                context.copyToClipboard("domain", domain)
                pendingDomain = null
            },
            add = { allow ->
                scope.launch(Dispatchers.IO) {
                    val success = if (allow) {
                        AllowListManager(database.allowRuleDao(), scope = RuleScope.DNS).addRule(domain)
                    } else {
                        BlockListManager(database.blockRuleDao(), scope = RuleScope.DNS).addRule(domain)
                    }
                    withContext(Dispatchers.Main) {
                        if (success) {
                            RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                                context,
                                if (allow) "allow" else "block",
                                domain,
                                RuleScope.DNS
                            )
                        }
                        context.showToast(if (success) "已添加规则" else "规则格式无效")
                        pendingDomain = null
                    }
                }
            }
        )
    }
}

@Composable
private fun HttpLogFilterBar(
    logs: List<HttpRequestLogEntity>,
    selectedFilter: HttpLogFilter,
    onFilterChange: (HttpLogFilter) -> Unit
) {
    val colors = MaterialTheme.colorScheme
    val allColor = colors.onSurface
    val options = listOf(
        HttpLogFilterOption(HttpLogFilter.ALL, logs.size, allColor),
        HttpLogFilterOption(HttpLogFilter.ALLOWED, logs.count { it.outcome == "allowed" }, colors.primary),
        HttpLogFilterOption(HttpLogFilter.REWRITTEN, logs.count { it.outcome == "rewritten" }, colors.tertiary),
        HttpLogFilterOption(HttpLogFilter.BLOCKED, logs.count { it.outcome == "blocked" || it.outcome == "invalid" }, colors.error),
        HttpLogFilterOption(HttpLogFilter.BYPASSED, logs.count { it.outcome in directOutcomes }, colors.onSurfaceVariant)
    )
    Row(
        modifier = Modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        options.forEach { option ->
            TextButton(
                onClick = { onFilterChange(option.filter) },
                shape = SettingsCornerShape,
                colors = ButtonDefaults.textButtonColors(
                    containerColor = if (selectedFilter == option.filter) option.color.copy(alpha = 0.12f) else Color.Transparent,
                    contentColor = if (selectedFilter == option.filter) option.color else option.color.copy(alpha = 0.7f)
                )
            ) {
                Text("${localizedText(option.filter.label)} · ${option.count}", style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun EmptyHttpLogMessage(message: String = "暂无请求记录") {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(localizedText(message), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun HttpRequestLogCard(log: HttpRequestLogEntity, onLongClick: () -> Unit) {
    val timeFormatter = remember { SimpleDateFormat("HH:mm:ss", Locale.getDefault()) }
    val formattedTime = remember(log.timestamp) { timeFormatter.format(Date(log.timestamp)) }
    val outcome = httpOutcomePresentation(log.outcome)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = {}, onLongClick = onLongClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = log.authority ?: localizedText("未取得 authority"),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f)
            )
            Surface(
                shape = RoundedCornerShape(4.dp),
                color = outcome.color.copy(alpha = 0.12f),
                modifier = Modifier.padding(start = 8.dp)
            ) {
                Text(
                    text = localizedText(outcome.label),
                    color = outcome.color,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(formattedTime, style = MaterialTheme.typography.bodySmall)
            Text(" · ${log.protocol}", style = MaterialTheme.typography.bodySmall)
            Text(" · ${log.packageName}", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
        }
        log.matchedRule?.let { rule ->
            Text(
                text = localizedText("匹配规则 · $rule"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private data class HttpOutcomePresentation(val label: String, val color: Color)

@Composable
private fun httpOutcomePresentation(outcome: String): HttpOutcomePresentation {
    val colors = MaterialTheme.colorScheme
    return when (outcome) {
        "allowed" -> HttpOutcomePresentation("已放行", colors.primary)
        "rewritten" -> HttpOutcomePresentation("已覆写", colors.tertiary)
        "blocked", "invalid" -> HttpOutcomePresentation(
            if (outcome == "blocked") "已拦截" else "无效请求",
            colors.error
        )
        "decryption_failed" -> HttpOutcomePresentation("HTTPS 检查自动旁路", colors.onSurfaceVariant)
        "unsupported_protocol" -> HttpOutcomePresentation("协议不支持 · 直连", colors.onSurfaceVariant)
        "resource_bypass" -> HttpOutcomePresentation("资源保护 · 直连", colors.onSurfaceVariant)
        else -> HttpOutcomePresentation(outcome, colors.onSurfaceVariant)
    }
}

private val directOutcomes = setOf("decryption_failed", "unsupported_protocol", "resource_bypass")
