package com.haoze.dnssr.ui

import android.widget.Toast
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
import androidx.compose.material.icons.filled.Block
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
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
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.RuleConfirmDialog
import com.haoze.dnssr.ui.components.RuleItemActionsMenu
import com.haoze.dnssr.ui.components.masterDisabledMessage
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
fun BlacklistScreen(
    onBack: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    viewModel: BlacklistViewModel = viewModel()
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
    var editingItem by remember { mutableStateOf<BlacklistItem?>(null) }
    var itemToDelete by remember { mutableStateOf<BlacklistItem?>(null) }
    var showClearUserDialog by remember { mutableStateOf(false) }
    var showTopMenu by remember { mutableStateOf(false) }

    var addInput by remember { mutableStateOf("") }
    var addAppScope by remember { mutableStateOf("") }
    var addImportant by remember { mutableStateOf(false) }
    var addError by remember { mutableStateOf<String?>(null) }

    var editInput by remember { mutableStateOf("") }
    var editAppScope by remember { mutableStateOf("") }
    var editImportant by remember { mutableStateOf(false) }
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
        title = localizedText("黑名单"),
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
                    text = { Text(localizedText("添加黑名单规则")) },
                    leadingIcon = { Icon(Icons.Filled.Add, contentDescription = null) },
                    onClick = {
                        showTopMenu = false
                        addInput = ""
                        addAppScope = ""
                        addImportant = false
                        addError = null
                        showAddDialog = true
                    }
                )
                DropdownMenuItem(
                    text = { Text(localizedText("清空自定义黑名单")) },
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
                    BlacklistStatsCard(stats = stats)
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
                            placeholder = localizedText("搜索域名、URL 或分组...")
                        )

                        RuleFilterChipRow(
                            filters = BlacklistFilter.entries,
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
                            message = localizedText(if (searchQuery.isEmpty()) "暂无黑名单规则" else "未找到匹配的规则")
                        )
                    }
                } else {
                    itemsIndexed(items, key = { _, item -> "${item.type}_${item.id}" }) { index, item ->
                        SettingsSurfaceItem(
                            index = index,
                            itemCount = items.size
                        ) {
                            BlacklistItemRow(
                                item = item,
                                onToggle = { enabled ->
                                    if (!item.masterEnabled) {
                                        context.showToast(
                                            masterDisabledMessage(context, item.type == BlacklistType.DOMAIN),
                                            Toast.LENGTH_SHORT
                                        )
                                    } else {
                                        viewModel.toggleRule(item, enabled)
                                        onRuntimeDnsSettingsChanged()
                                    }
                                },
                                onEdit = {
                                    editingItem = item
                                    editInput = item.rawLine
                                    editAppScope = item.appScope.orEmpty()
                                    editImportant = item.important
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
                    addInput = ""
                    addAppScope = ""
                    addImportant = false
                    addError = null
                    showAddDialog = true
                },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp),
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary
            ) {
                Icon(Icons.Filled.Add, contentDescription = localizedText("添加黑名单"))
            }
        }
    }

    // 添加规则弹窗
    if (showAddDialog) {
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text(localizedText("添加黑名单规则")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = localizedText("支持域名（如 example.com、*.google.com）、AdGuard 规则（||example.com^）或 URL 屏蔽前缀（https://example.com/api）。"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = addInput,
                        onValueChange = {
                            addInput = it
                            addError = null
                        },
                        label = { Text(localizedText("规则内容")) },
                        singleLine = true,
                        isError = addError != null,
                        supportingText = addError?.let { msg -> { Text(msg) } },
                        shape = SettingsCornerShape
                    )
                    OutlinedTextField(
                        value = addAppScope,
                        onValueChange = { addAppScope = it },
                        label = { Text(localizedText("指定应用包名 (可选)")) },
                        placeholder = { Text("com.example.app") },
                        singleLine = true,
                        shape = SettingsCornerShape
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        val result = viewModel.addRule(
                            input = addInput,
                            appScope = addAppScope.trim().takeIf { it.isNotEmpty() },
                            important = addImportant
                        )
                        result.onSuccess { msg ->
                            context.showToast(msg, Toast.LENGTH_SHORT)
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
            title = { Text(localizedText("编辑黑名单规则")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = editInput,
                        onValueChange = {
                            editInput = it
                            editError = null
                        },
                        label = { Text(localizedText("规则内容")) },
                        singleLine = true,
                        isError = editError != null,
                        supportingText = editError?.let { msg -> { Text(msg) } },
                        shape = SettingsCornerShape
                    )
                    if (item.type == BlacklistType.DOMAIN) {
                        OutlinedTextField(
                            value = editAppScope,
                            onValueChange = { editAppScope = it },
                            label = { Text(localizedText("指定应用包名 (可选)")) },
                            placeholder = { Text("com.example.app") },
                            singleLine = true,
                            shape = SettingsCornerShape
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        val result = viewModel.editRule(
                            item = item,
                            newPattern = editInput,
                            newAppScope = editAppScope.trim().takeIf { it.isNotEmpty() },
                            newImportant = editImportant
                        )
                        result.onSuccess { msg ->
                            context.showToast(msg, Toast.LENGTH_SHORT)
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
        val message = if (item.isUserRule && !item.isSubscription) {
            "确定要删除自定义黑名单规则「${item.pattern}」吗？"
        } else {
            "确定要删除黑名单规则「${item.pattern}」吗？"
        }
        RuleConfirmDialog(
            title = localizedText("删除黑名单规则"),
            message = localizedText(message),
            confirmText = localizedText("删除"),
            onDismiss = { itemToDelete = null },
            onConfirm = {
                viewModel.deleteRule(item)
                context.showToast("已删除", Toast.LENGTH_SHORT)
                onRuntimeDnsSettingsChanged()
            }
        )
    }

    // 清空自定义黑名单确认弹窗
    if (showClearUserDialog) {
        RuleConfirmDialog(
            title = localizedText("清空自定义黑名单"),
            message = localizedText("确定要清空所有由您添加的自定义黑名单规则吗？规则订阅等内容不受影响。"),
            confirmText = localizedText("确认清空"),
            onDismiss = { showClearUserDialog = false },
            onConfirm = {
                viewModel.clearUserBlacklist()
                context.showToast("已清空自定义黑名单", Toast.LENGTH_SHORT)
                onRuntimeDnsSettingsChanged()
            }
        )
    }

}

@Composable
private fun BlacklistStatsCard(stats: BlacklistStats) {
    RuleStatsCard(
        icon = Icons.Filled.Block,
        title = localizedText("拦截统计与状态"),
        activeBadgeText = localizedText("生效中: ${stats.totalActive} 条"),
        stats = listOf(
            "拦截域名数" to stats.totalDomains.toString(),
            "用户自定义" to "${stats.userEnabled}/${stats.userTotal}",
            "屏蔽 URL" to stats.urlBlockCount.toString()
        )
    )
}

@Composable
private fun BlacklistItemRow(
    item: BlacklistItem,
    onToggle: (Boolean) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {

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
            // 规则内容
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = item.pattern,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
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

                // 类型标签 (URL 屏蔽)
                if (item.type == BlacklistType.URL) {
                    RuleTagChip(
                        text = "URL",
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                        contentColor = MaterialTheme.colorScheme.onTertiaryContainer
                    )
                }

                // 重要规则标签
                if (item.important) {
                    RuleTagChip(
                        text = localizedText("重要"),
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer
                    )
                }

                // 通配符标签
                if (item.isWildcard) {
                    RuleTagChip(
                        text = localizedText("通配符"),
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                    )
                }

                // 应用作用域标签
                item.appScope?.takeIf { it.isNotBlank() }?.let { app ->
                    val label = (if (item.appInverted) "~" else "") + app
                    RuleTagChip(
                        text = "App: $label",
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                        contentColor = MaterialTheme.colorScheme.onTertiaryContainer,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                // 分组标签
                item.groupName?.takeIf { it.isNotBlank() }?.let { group ->
                    RuleTagChip(
                        text = group,
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            // 原始规则行（当原始行与 pattern 不同时展示）
            if (item.rawLine != item.pattern && item.rawLine.isNotBlank()) {
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

            RuleItemActionsMenu(
                onEdit = onEdit,
                onDelete = onDelete
            )
        }
    }
}
