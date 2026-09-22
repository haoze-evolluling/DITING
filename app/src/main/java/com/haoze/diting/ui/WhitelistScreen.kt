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
import androidx.compose.material.icons.filled.Refresh
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
import com.haoze.diting.ui.components.RuleFilterChipRow
import com.haoze.diting.ui.components.RuleListCountHeader
import com.haoze.diting.ui.components.RuleListEmptyState
import com.haoze.diting.ui.components.RuleListPaginationBar
import com.haoze.diting.ui.components.RuleSearchField
import com.haoze.diting.ui.components.SettingsItemSpacing
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSurfaceItem
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.components.masterDisabledMessage

@Composable
fun WhitelistScreen(
    onBack: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    viewModel: WhitelistViewModel = viewModel()
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
    val allowEditDefault by viewModel.allowEditDefault.collectAsStateWithLifecycle()

    var showRiskWarningDialog by remember { mutableStateOf(false) }
    var showAddDialog by remember { mutableStateOf(false) }
    var editingItem by remember { mutableStateOf<WhitelistItem?>(null) }
    var itemToDelete by remember { mutableStateOf<WhitelistItem?>(null) }
    var showResetDefaultsDialog by remember { mutableStateOf(false) }
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
        title = localizedText("白名单"),
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
                    text = { Text(localizedText("添加白名单规则")) },
                    leadingIcon = { Icon(Icons.Filled.Add, contentDescription = null) },
                    onClick = {
                        showTopMenu = false
                        showAddDialog = true
                    }
                )
                DropdownMenuItem(
                    text = { Text(localizedText("重置默认白名单")) },
                    leadingIcon = { Icon(Icons.Filled.Refresh, contentDescription = null) },
                    onClick = {
                        showTopMenu = false
                        showResetDefaultsDialog = true
                    }
                )
                DropdownMenuItem(
                    text = { Text(localizedText("清空自定义白名单")) },
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
                    WhitelistStatsCard(stats = stats)
                }

                // 2. Master switch controlling whether the default whitelist is editable
                item(key = "protection_title") {
                    Text(
                        text = localizedText("预设规则保护"),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 8.dp, bottom = 4.dp)
                    )
                }
                item(key = "protection_switch") {
                    val subtitleText = if (allowEditDefault) {
                        localizedText("已开启编辑权限：可修改、停用或删除软件预设的默认白名单")
                    } else {
                        localizedText("默认只读保护：修改预设白名单可能导致网络异常，需确认风险后开启")
                    }
                    SettingsSurfaceGroup(
                        groupContentPadding = PaddingValues.Zero,
                        content = listOf<@Composable () -> Unit>(
                            {
                                SettingsSwitchItem(
                                    title = localizedText("允许编辑默认白名单"),
                                    subtitle = subtitleText,
                                    checked = allowEditDefault,
                                    onCheckedChange = { checked ->
                                        if (checked) {
                                            showRiskWarningDialog = true
                                        } else {
                                            viewModel.setAllowEditDefault(false)
                                            context.showToast("已恢复默认白名单只读保护", Toast.LENGTH_SHORT)
                                        }
                                    }
                                )
                            }
                        )
                    )
                }

                // 3. Search and filter bar
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
                            filters = WhitelistFilter.entries,
                            selectedFilter = filter,
                            onSelect = viewModel::setFilter,
                            labelKeyOf = { it.labelResName }
                        )
                    }
                }

                // 4. List title and total count
                item(key = "list_header") {
                    RuleListCountHeader(totalCount = totalCount)
                }

                // 5. Rule list items
                if (items.isEmpty()) {
                    item(key = "empty_state") {
                        RuleListEmptyState(
                            message = localizedText(if (searchQuery.isEmpty()) "暂无白名单规则" else "未找到匹配的规则")
                        )
                    }
                } else {
                    itemsIndexed(items, key = { _, item -> "${item.type}_${item.id}" }) { index, item ->
                        SettingsSurfaceItem(
                            index = index,
                            itemCount = items.size
                        ) {
                            WhitelistItemRow(
                                item = item,
                                allowEditDefault = allowEditDefault,
                                onToggle = { enabled ->
                                    if (!item.masterEnabled) {
                                        context.showToast(
                                            masterDisabledMessage(context, item.type == WhitelistType.DOMAIN),
                                            Toast.LENGTH_SHORT
                                        )
                                    } else if (item.isPreset && !allowEditDefault) {
                                        context.showToast("请先开启【允许编辑默认白名单】开关", Toast.LENGTH_SHORT)
                                    } else {
                                        viewModel.toggleRule(item, enabled)
                                        onRuntimeDnsSettingsChanged()
                                    }
                                },
                                onEdit = {
                                    if (item.isPreset && !allowEditDefault) {
                                        context.showToast("请先开启【允许编辑默认白名单】开关", Toast.LENGTH_SHORT)
                                    } else {
                                        editingItem = item
                                    }
                                },
                                onDelete = {
                                    if (item.isPreset && !allowEditDefault) {
                                        context.showToast("请先开启【允许编辑默认白名单】开关", Toast.LENGTH_SHORT)
                                    } else {
                                        itemToDelete = item
                                    }
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
                Icon(Icons.Filled.Add, contentDescription = localizedText("添加白名单"))
            }
        }
    }

    // Risk warning dialog
    if (showRiskWarningDialog) {
        WhitelistRiskWarningDialog(
            onDismiss = { showRiskWarningDialog = false },
            onConfirm = {
                viewModel.setAllowEditDefault(true)
                showRiskWarningDialog = false
                context.showToast("已开启默认白名单编辑权限", Toast.LENGTH_SHORT)
            }
        )
    }

    // Add rule dialog
    if (showAddDialog) {
        WhitelistAddDialog(
            onDismiss = { showAddDialog = false },
            onConfirm = { input, appScope, important ->
                val result = viewModel.addRule(
                    input = input,
                    appScope = appScope,
                    important = important
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
        WhitelistEditDialog(
            item = item,
            onDismiss = { editingItem = null },
            onConfirm = { newPattern, newAppScope, newImportant ->
                val result = viewModel.editRule(
                    item = item,
                    newPattern = newPattern,
                    newAppScope = newAppScope,
                    newImportant = newImportant
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
        WhitelistDeleteConfirmDialog(
            item = item,
            onDismiss = { itemToDelete = null },
            onConfirm = {
                viewModel.deleteRule(item)
                context.showToast("已删除", Toast.LENGTH_SHORT)
                onRuntimeDnsSettingsChanged()
            }
        )
    }

    // Reset default whitelist confirmation dialog
    if (showResetDefaultsDialog) {
        WhitelistResetDefaultsConfirmDialog(
            onDismiss = { showResetDefaultsDialog = false },
            onConfirm = {
                viewModel.resetPresetWhitelist()
                context.showToast("默认白名单已重置恢复", Toast.LENGTH_SHORT)
                onRuntimeDnsSettingsChanged()
            }
        )
    }

    // Clear custom whitelist confirmation dialog
    if (showClearUserDialog) {
        WhitelistClearUserConfirmDialog(
            onDismiss = { showClearUserDialog = false },
            onConfirm = {
                viewModel.clearUserWhitelist()
                context.showToast("已清空自定义白名单", Toast.LENGTH_SHORT)
                onRuntimeDnsSettingsChanged()
            }
        )
    }
}
