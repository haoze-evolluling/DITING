package com.haoze.diting.normal.ui

import com.haoze.diting.ui.*
import com.haoze.diting.ui.dashboard.*
import android.app.Application
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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import com.haoze.diting.SettingsRouteActivity
import com.haoze.diting.ui.agent.AgentAnalysisSheet
import com.haoze.diting.ui.agent.AnalysisTarget
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.RuleFilterChipRow
import com.haoze.diting.ui.components.RuleTagChip
import com.haoze.diting.ui.components.SettingsItemSpacing
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceItem
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
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.RequestSource
import com.haoze.diting.data.RequestStatus
import com.haoze.diting.data.entity.DnsLogEntity
import com.haoze.diting.data.entity.HttpRequestLogEntity
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.core.rule.AllowListManager
import com.haoze.diting.core.rule.BlockListManager
import com.haoze.diting.core.log.LogResult
import com.haoze.diting.ui.components.cascade.CascadeDropdownMenu
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsDivider
import com.haoze.diting.ui.components.SettingsOutlinedActionButton
import com.haoze.diting.ui.components.SettingsCardMargin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun RequestLogScreen(
    onBack: () -> Unit,
    initialSource: RequestSource = RequestSource.ALL,
    onRuntimeDnsSettingsChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    val database = remember(context) { AppDatabase.getInstance(context) }
    val viewModel: RequestLogViewModel = androidx.lifecycle.viewmodel.compose.viewModel(
        key = "RequestLogViewModel_${initialSource.name}",
        factory = RequestLogViewModel.factory(
            context.applicationContext as Application,
            initialSource
        )
    )
    LaunchedEffect(initialSource) {
        if (viewModel.state.value.source != initialSource) {
            viewModel.setSource(initialSource)
        }
    }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val source = state.source
    val status = state.status
    val query = state.query
    val searching = state.searching
    var pendingDomain by remember { mutableStateOf<String?>(null) }
    var pendingRuleScope by remember { mutableStateOf(RuleScope.DNS) }
    var showTopMenu by remember { mutableStateOf(false) }
    var activeAnalysisTarget by remember { mutableStateOf<AnalysisTarget?>(null) }
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
    LaunchedEffect(source, status, query) {
        listState.scrollToItem(0)
    }

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
            } else if (status != RequestStatus.ALL) {
                Column {
                    Text(localizedText("请求日志"))
                    Text(
                        text = localizedText(status.label),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
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
                IconButton(onClick = { showTopMenu = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = localizedText("更多选项"))
                }
                CascadeDropdownMenu(
                    expanded = showTopMenu,
                    onDismissRequest = { showTopMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text(localizedText("刷新")) },
                        leadingIcon = { Icon(Icons.Default.Refresh, contentDescription = null) },
                        enabled = !state.loading,
                        onClick = {
                            showTopMenu = false
                            viewModel.refresh()
                            scope.launch {
                                listState.scrollToItem(0)
                            }
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedText("搜索")) },
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                        onClick = {
                            showTopMenu = false
                            viewModel.setSearching(true)
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedText("状态筛选")) },
                        leadingIcon = {
                            Icon(
                                Icons.Default.FilterList,
                                contentDescription = null,
                                tint = if (status != RequestStatus.ALL) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                            )
                        },
                        childrenHeader = { DropdownMenuHeader(text = { Text(localizedText("筛选请求状态")) }) },
                        children = {
                            RequestStatus.entries.forEach { option ->
                                DropdownMenuItem(
                                    text = { Text(localizedText(option.label)) },
                                    trailingIcon = {
                                        if (status == option) {
                                            Icon(
                                                Icons.Default.CheckCircle,
                                                contentDescription = null,
                                                tint = MaterialTheme.colorScheme.primary,
                                                modifier = Modifier.size(20.dp)
                                            )
                                        }
                                    },
                                    onClick = {
                                        viewModel.setStatus(option)
                                        showTopMenu = false
                                    }
                                )
                            }
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedText("导出 CSV")) },
                        leadingIcon = { Icon(Icons.Default.FileDownload, contentDescription = null) },
                        onClick = {
                            showTopMenu = false
                            exportLauncher.launch("diting-request-logs-${System.currentTimeMillis()}.csv")
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedText("AI 流量分析")) },
                        leadingIcon = {
                            Icon(
                                Icons.Default.AutoAwesome,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                        },
                        onClick = {
                            showTopMenu = false
                            activeAnalysisTarget = AnalysisTarget.RecentTraffic(source)
                        }
                    )
                }
            }
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            RequestFilterRow(RequestSource.entries, source, { it.label }, viewModel::setSource)
            SettingsDivider()
            val currentError = state.error
            if (currentError != null && visibleItems.isEmpty() && !state.loading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = localizedText("加载失败：$currentError"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            } else if (visibleItems.isEmpty() && !state.loading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        localizedText("当前筛选下暂无请求日志"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(SettingsCardMargin),
                    verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
                ) {
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
                val ruleScope = pendingRuleScope
                scope.launch(Dispatchers.IO) {
                    val success = if (allow) {
                        AllowListManager(database.allowRuleDao(), scope = ruleScope).addRule(domain)
                    } else {
                        BlockListManager(database.blockRuleDao(), scope = ruleScope).addRule(domain)
                    }
                    withContext(Dispatchers.Main) {
                        if (success) {
                            RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, if (allow) "allow" else "block", domain, ruleScope)
                            onRuntimeDnsSettingsChanged()
                        }
                        context.showToast(if (success) "已添加规则" else "规则格式无效", Toast.LENGTH_SHORT)
                        pendingDomain = null
                    }
                }
            },
            analyze = {
                activeAnalysisTarget = AnalysisTarget.Domain(domain)
                pendingDomain = null
            }
        )
    }

    AgentAnalysisSheet(
        target = activeAnalysisTarget,
        onDismiss = { activeAnalysisTarget = null },
        onNavigateToSettings = {
            context.startActivity(SettingsRouteActivity.createIntent(context, Routes.AGENT_API_SETTINGS))
        },
        onRuleAdded = {
            onRuntimeDnsSettingsChanged()
            viewModel.refresh()
        }
    )
}

@Composable
private fun <T> RequestFilterRow(values: List<T>, selected: T, label: (T) -> String, select: (T) -> Unit) {
    RuleFilterChipRow(
        filters = values,
        selectedFilter = selected,
        onSelect = select,
        labelKeyOf = label,
        modifier = Modifier.padding(horizontal = SettingsCardMargin)
    )
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
            .combinedClickable(onClick = onLongClick, onLongClick = onLongClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(item.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
            RuleTagChip(
                text = localizedText(item.status.label),
                containerColor = color.copy(alpha = .12f),
                contentColor = color
            )
        }
        Text(localizedText(item.subtitle), style = MaterialTheme.typography.bodySmall)
        item.detail?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

private val requestTimeFormatter = ThreadLocal.withInitial {
    SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
}

private fun formatRequestTime(timestamp: Long): String =
    requestTimeFormatter.get()?.format(Date(timestamp)).orEmpty()

private fun requestCsv(items: List<RequestLogItem>) = buildString {
    append('\uFEFF')
    appendLine("timestamp,time,source,status,request,details")
    items.forEach {
        appendLine(
            listOf(
                it.timestamp,
                formatRequestTime(it.timestamp),
                it.source.label,
                it.status.label,
                it.title,
                it.subtitle + (it.detail?.let { d -> " · $d" } ?: "")
            ).joinToString(",") { v -> "\"${v.toString().replace("\"", "\"\"")}\"" }
        )
    }
}
