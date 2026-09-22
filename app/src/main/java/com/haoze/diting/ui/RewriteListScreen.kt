package com.haoze.diting.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.ui.components.RuleFilterChipRow
import com.haoze.diting.ui.components.RuleListCountHeader
import com.haoze.diting.ui.components.RuleListEmptyState
import com.haoze.diting.ui.components.RuleListPaginationBar
import com.haoze.diting.ui.components.RuleSearchField
import com.haoze.diting.ui.components.SettingsItemSpacing
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceItem
import com.haoze.diting.ui.components.masterDisabledMessage

@Composable
fun RewriteListScreen(
    onBack: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    viewModel: RewriteListViewModel = viewModel()
) {
    val context = LocalContext.current
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
                // 1. Top stats panel
                item(key = "stats_card") {
                    RewriteListStatsCard(stats = stats)
                }

                // 2. Search and filter bar
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

                // 3. List title and total count
                item(key = "list_header") {
                    RuleListCountHeader(totalCount = totalCount)
                }

                // 4. Rule list items
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
                                        context.showToast(
                                            masterDisabledMessage(context, item.targetType == RewriteTargetType.IPV4 || item.targetType == RewriteTargetType.IPV6),
                                            Toast.LENGTH_SHORT
                                        )
                                    } else {
                                        viewModel.toggleRule(item, enabled)
                                        onRuntimeDnsSettingsChanged()
                                    }
                                },
                                onEdit = {
                                    editingItem = item
                                },
                                onDelete = {
                                    itemToDelete = item
                                }
                            )
                        }
                    }
                }
            }

            // Floating pagination control
            RuleListPaginationBar(
                currentPage = currentPage,
                totalPages = totalPages,
                onLoadPage = viewModel::loadPage
            )

            FloatingActionButton(
                onClick = {
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

    // Add rule dialog
    if (showAddDialog) {
        RewriteAddDialog(
            onDismiss = { showAddDialog = false },
            onConfirm = { domain, targetType, targetValue ->
                val result = viewModel.addRule(
                    domain = domain,
                    targetType = targetType,
                    targetValue = targetValue
                )
                if (result.isSuccess) {
                    onRuntimeDnsSettingsChanged()
                }
                result
            }
        )
    }

    // Edit rule dialog
    editingItem?.let { item ->
        RewriteEditDialog(
            item = item,
            onDismiss = { editingItem = null },
            onConfirm = { newPattern, newTargetType, newTargetValue ->
                val result = viewModel.editRule(
                    item = item,
                    newPattern = newPattern,
                    newTargetType = newTargetType,
                    newTargetValue = newTargetValue
                )
                if (result.isSuccess) {
                    onRuntimeDnsSettingsChanged()
                }
                result
            }
        )
    }

    // Delete single rule confirmation dialog
    itemToDelete?.let { item ->
        RewriteDeleteConfirmDialog(
            item = item,
            onDismiss = { itemToDelete = null },
            onConfirm = {
                viewModel.deleteRule(item)
                context.showToast("已删除", Toast.LENGTH_SHORT)
                onRuntimeDnsSettingsChanged()
            }
        )
    }

    // Clear custom rewrite rules confirmation dialog
    if (showClearUserDialog) {
        RewriteClearUserConfirmDialog(
            onDismiss = { showClearUserDialog = false },
            onConfirm = {
                viewModel.clearUserRules()
                context.showToast("已清空自定义覆写", Toast.LENGTH_SHORT)
                onRuntimeDnsSettingsChanged()
            }
        )
    }
}
