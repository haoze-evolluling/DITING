package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AltRoute
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.RuleConfirmDialog
import com.haoze.dnssr.ui.components.RuleFilterChipRow
import com.haoze.dnssr.ui.components.RuleListCountHeader
import com.haoze.dnssr.ui.components.RuleListEmptyState
import com.haoze.dnssr.ui.components.RuleListPaginationBar
import com.haoze.dnssr.ui.components.RuleSearchField
import com.haoze.dnssr.ui.components.RuleStatsCard
import com.haoze.dnssr.ui.components.RuleTagChip
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsItemSpacing
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import kotlinx.coroutines.launch

@Composable
fun RewriteListScreen(
    onBack: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    viewModel: RewriteListViewModel = viewModel()
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    val stats by viewModel.stats.collectAsStateWithLifecycle()
    val items by viewModel.items.collectAsStateWithLifecycle()
    val currentPage by viewModel.currentPage.collectAsStateWithLifecycle()
    val totalPages by viewModel.totalPages.collectAsStateWithLifecycle()
    val totalCount by viewModel.totalCount.collectAsStateWithLifecycle()
    val searchQuery by viewModel.searchQuery.collectAsStateWithLifecycle()
    val filter by viewModel.filter.collectAsStateWithLifecycle()

    var showAddDialog by remember { mutableStateOf(false) }
    var editingItem by remember { mutableStateOf<RewriteListItem?>(null) }
    var itemToDelete by remember { mutableStateOf<RewriteListItem?>(null) }
    var showClearUserDialog by remember { mutableStateOf(false) }
    var showTopMenu by remember { mutableStateOf(false) }

    var addDomain by remember { mutableStateOf("") }
    var addTargetType by remember { mutableStateOf(RewriteTargetType.IPV4) }
    var addTargetValue by remember { mutableStateOf("") }
    var addError by remember { mutableStateOf<String?>(null) }

    var editDomain by remember { mutableStateOf("") }
    var editTargetType by remember { mutableStateOf(RewriteTargetType.IPV4) }
    var editTargetValue by remember { mutableStateOf("") }
    var editError by remember { mutableStateOf<String?>(null) }

    DisposableEffect(lifecycleOwner) {
        viewModel.activate()
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshAll()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    SettingsScaffold(
        title = localizedText("覆写名单"),
        onBack = onBack,
        actions = {
            IconButton(onClick = { showTopMenu = true }) {
                Icon(Icons.Filled.MoreVert, contentDescription = localizedText("更多选项"))
            }
            DropdownMenu(
                expanded = showTopMenu,
                onDismissRequest = { showTopMenu = false }
            ) {
                DropdownMenuItem(
                    text = { Text(localizedText("添加覆写规则")) },
                    leadingIcon = { Icon(Icons.Filled.Add, contentDescription = null) },
                    onClick = {
                        showTopMenu = false
                        addDomain = ""
                        addTargetType = RewriteTargetType.IPV4
                        addTargetValue = ""
                        addError = null
                        showAddDialog = true
                    }
                )
                DropdownMenuItem(
                    text = { Text(localizedText("清空自定义覆写")) },
                    leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
                    onClick = {
                        showTopMenu = false
                        showClearUserDialog = true
                    }
                )
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 96.dp),
                verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
            ) {
                // 1. 顶部统计面板
                item(key = "stats_card") {
                    RewriteListStatsCard(stats = stats)
                }

                // 2. 搜索与过滤筛选栏
                item(key = "rules_title") {
                    Text(
                        text = localizedText("规则管理"),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 8.dp, bottom = 4.dp)
                    )
                }
                item(key = "search_and_filter") {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 6.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        RuleSearchField(
                            value = searchQuery,
                            onValueChange = viewModel::setSearchQuery,
                            placeholder = localizedText("搜索域名或目标地址...")
                        )

                        RuleFilterChipRow(
                            filters = RewriteListFilter.entries,
                            selectedFilter = filter,
                            onSelect = viewModel::setFilter,
                            labelKeyOf = { it.labelResName }
                        )
                    }
                }

                // 3. 列表标题与总数
                item(key = "list_header") {
                    RuleListCountHeader(totalCount = totalCount)
                }

                // 4. 规则列表项
                if (items.isEmpty()) {
                    item(key = "empty_state") {
                        RuleListEmptyState(
                            message = localizedText(if (searchQuery.isEmpty()) "暂无覆写规则" else "未找到匹配的规则")
                        )
                    }
                } else {
                    itemsIndexed(items, key = { _, item -> item.id }) { index, item ->
                        SettingsSurfaceItem(
                            index = index,
                            itemCount = items.size
                        ) {
                            RewriteListItemRow(
                                item = item,
                                onToggle = { enabled ->
                                    if (!item.masterEnabled) {
                                        val isDomainType = item.targetType == RewriteTargetType.IPV4 || item.targetType == RewriteTargetType.IPV6
                                        val message = if (isDomainType) {
                                            "请先在规则控制中开启【启用域名规则】"
                                        } else if (!AppSettings.isAddressRulesEnabled(context)) {
                                            "请先在规则控制中开启【启用地址规则】"
                                        } else if (!AppSettings.isHttpsInspectionReady(context)) {
                                            "请先安装并验证 CA 根证书"
                                        } else if (!AppSettings.isHttpInspectionEnabled(context)) {
                                            "请先在 HTTPS 流量检查中开启检查"
                                        } else {
                                            "请先在 HTTPS 流量检查中选择目标应用"
                                        }
                                        Toast.makeText(context, localizedText(context, message), Toast.LENGTH_SHORT).show()
                                    } else {
                                        viewModel.toggleRule(item, enabled)
                                        onRuntimeDnsSettingsChanged()
                                    }
                                },
                                onEdit = {
                                    editingItem = item
                                    editDomain = item.pattern
                                    editTargetType = item.targetType
                                    editTargetValue = item.targetValue
                                    editError = null
                                },
                                onDelete = {
                                    itemToDelete = item
                                }
                            )
                        }
                    }
                }
            }

            // 悬浮分页控件
            RuleListPaginationBar(
                currentPage = currentPage,
                totalPages = totalPages,
                onLoadPage = viewModel::loadPage
            )

            FloatingActionButton(
                onClick = {
                    addDomain = ""
                    addTargetType = RewriteTargetType.IPV4
                    addTargetValue = ""
                    addError = null
                    showAddDialog = true
                },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp),
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary
            ) {
                Icon(Icons.Filled.Add, contentDescription = localizedText("添加覆写规则"))
            }
        }
    }

    // 添加规则弹窗
    if (showAddDialog) {
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text(localizedText("添加覆写规则")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = localizedText("将域名解析覆写为指定的 IPv4、IPv6 地址或 CNAME 目标域名。"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        listOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6, RewriteTargetType.CNAME).forEach { type ->
                            FilterChip(
                                selected = addTargetType == type,
                                onClick = {
                                    addTargetType = type
                                    addError = null
                                },
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                                label = {
                                    Box(
                                        modifier = Modifier.fillMaxWidth(),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(type)
                                    }
                                },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }

                    OutlinedTextField(
                        value = addDomain,
                        onValueChange = {
                            addDomain = it
                            addError = null
                        },
                        label = { Text(localizedText("域名，如 example.com")) },
                        singleLine = true,
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )

                    val targetLabel = when (addTargetType) {
                        RewriteTargetType.CNAME -> "目标域名 (CNAME)"
                        RewriteTargetType.IPV6 -> "IPv6 地址"
                        else -> "IPv4 地址"
                    }

                    OutlinedTextField(
                        value = addTargetValue,
                        onValueChange = {
                            addTargetValue = it
                            addError = null
                        },
                        label = { Text(localizedText(targetLabel)) },
                        supportingText = addError?.let { msg -> { Text(localizedText(msg)) } },
                        isError = addError != null,
                        singleLine = true,
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        val result = viewModel.addRule(
                            domain = addDomain,
                            targetType = addTargetType,
                            targetValue = addTargetValue
                        )
                        result.onSuccess { msg ->
                            Toast.makeText(context, localizedText(context, msg), Toast.LENGTH_SHORT).show()
                            showAddDialog = false
                            onRuntimeDnsSettingsChanged()
                        }.onFailure { err ->
                            addError = err.message ?: localizedText(context, "添加失败")
                        }
                    }
                }) {
                    Text(localizedText("添加"))
                }
            },
            dismissButton = {
                TextButton(onClick = { showAddDialog = false }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

    // 编辑规则弹窗
    editingItem?.let { item ->
        AlertDialog(
            onDismissRequest = { editingItem = null },
            title = { Text(localizedText("编辑覆写规则")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        listOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6, RewriteTargetType.CNAME).forEach { type ->
                            FilterChip(
                                selected = editTargetType == type,
                                onClick = {
                                    editTargetType = type
                                    editError = null
                                },
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                                label = {
                                    Box(
                                        modifier = Modifier.fillMaxWidth(),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(type)
                                    }
                                },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }

                    OutlinedTextField(
                        value = editDomain,
                        onValueChange = {
                            editDomain = it
                            editError = null
                        },
                        label = { Text(localizedText("域名")) },
                        singleLine = true,
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )

                    val targetLabel = when (editTargetType) {
                        RewriteTargetType.CNAME -> "目标域名 (CNAME)"
                        RewriteTargetType.IPV6 -> "IPv6 地址"
                        else -> "IPv4 地址"
                    }

                    OutlinedTextField(
                        value = editTargetValue,
                        onValueChange = {
                            editTargetValue = it
                            editError = null
                        },
                        label = { Text(localizedText(targetLabel)) },
                        supportingText = editError?.let { msg -> { Text(localizedText(msg)) } },
                        isError = editError != null,
                        singleLine = true,
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        val result = viewModel.editRule(
                            item = item,
                            newPattern = editDomain,
                            newTargetType = editTargetType,
                            newTargetValue = editTargetValue
                        )
                        result.onSuccess { msg ->
                            Toast.makeText(context, localizedText(context, msg), Toast.LENGTH_SHORT).show()
                            editingItem = null
                            onRuntimeDnsSettingsChanged()
                        }.onFailure { err ->
                            editError = err.message ?: localizedText(context, "修改失败")
                        }
                    }
                }) {
                    Text(localizedText("保存"))
                }
            },
            dismissButton = {
                TextButton(onClick = { editingItem = null }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

    // 删除单条确认弹窗
    itemToDelete?.let { item ->
        RuleConfirmDialog(
            title = localizedText("删除覆写规则"),
            message = localizedText("确定要删除覆写规则「${item.pattern} -> ${item.targetValue}」吗？"),
            confirmText = localizedText("删除"),
            onDismiss = { itemToDelete = null },
            onConfirm = {
                viewModel.deleteRule(item)
                Toast.makeText(context, localizedText(context, "已删除"), Toast.LENGTH_SHORT).show()
                onRuntimeDnsSettingsChanged()
            }
        )
    }

    // 清空自定义覆写确认弹窗
    if (showClearUserDialog) {
        RuleConfirmDialog(
            title = localizedText("清空自定义覆写"),
            message = localizedText("确定要清空所有由您添加的自定义覆写规则吗？规则订阅等内容不受影响。"),
            confirmText = localizedText("确认清空"),
            onDismiss = { showClearUserDialog = false },
            onConfirm = {
                viewModel.clearUserRules()
                Toast.makeText(context, localizedText(context, "已清空自定义覆写"), Toast.LENGTH_SHORT).show()
                onRuntimeDnsSettingsChanged()
            }
        )
    }

}

@Composable
private fun RewriteListStatsCard(stats: RewriteListStats) {
    RuleStatsCard(
        icon = Icons.Filled.AltRoute,
        title = localizedText("覆写统计与状态"),
        activeBadgeText = localizedText("生效中: ${stats.totalActive} 条"),
        stats = listOf(
            "IPv4 覆写" to stats.ipv4Count.toString(),
            "IPv6 覆写" to stats.ipv6Count.toString(),
            "CNAME 覆写" to stats.cnameCount.toString(),
            "用户自定义" to "${stats.userEnabled}/${stats.userTotal}"
        )
    )
}

@Composable
private fun RewriteListItemRow(
    item: RewriteListItem,
    onToggle: (Boolean) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    var showItemMenu by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(end = 8.dp)
                .alpha(if (!item.effectiveEnabled) 0.5f else 1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // 规则域名
            Text(
                text = item.pattern,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            // 覆写目标指示
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = "-> ${item.targetValue}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            // 标签行
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // 来源标签
                if (item.isUserRule) {
                    RuleTagChip(
                        text = localizedText("自定义"),
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
                if (item.isSubscription) {
                    RuleTagChip(
                        text = item.subscriptionName?.let { localizedText(it) } ?: localizedText("规则订阅"),
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                // 目标类型标签
                Surface(
                    shape = RoundedCornerShape(4.dp),
                    color = when (item.targetType) {
                        RewriteTargetType.IPV4 -> MaterialTheme.colorScheme.tertiaryContainer
                        RewriteTargetType.IPV6 -> MaterialTheme.colorScheme.secondaryContainer
                        else -> MaterialTheme.colorScheme.surfaceVariant
                    }
                ) {
                    Text(
                        text = item.targetType,
                        style = MaterialTheme.typography.labelSmall,
                        color = when (item.targetType) {
                            RewriteTargetType.IPV4 -> MaterialTheme.colorScheme.onTertiaryContainer
                            RewriteTargetType.IPV6 -> MaterialTheme.colorScheme.onSecondaryContainer
                            else -> MaterialTheme.colorScheme.onSurfaceVariant
                        },
                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                }
            }

            // 原始规则行（当原始行与 pattern -> targetValue 不同时展示）
            val standardLine = "${item.pattern} -> ${item.targetValue}"
            if (item.rawLine != standardLine && item.rawLine.isNotBlank() && item.rawLine != item.pattern) {
                Text(
                    text = item.rawLine,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Switch(
                checked = item.effectiveEnabled,
                onCheckedChange = onToggle,
                enabled = item.masterEnabled,
                modifier = Modifier.alpha(if (!item.masterEnabled) 0.5f else 1f)
            )

            Box {
                IconButton(onClick = { showItemMenu = true }) {
                    Icon(
                        imageVector = Icons.Filled.MoreVert,
                        contentDescription = localizedText("更多操作"),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                DropdownMenu(
                    expanded = showItemMenu,
                    onDismissRequest = { showItemMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text(localizedText("编辑")) },
                        leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                        onClick = {
                            showItemMenu = false
                            onEdit()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedText("删除"), color = MaterialTheme.colorScheme.error) },
                        leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                        onClick = {
                            showItemMenu = false
                            onDelete()
                        }
                    )
                }
            }
        }
    }
}
