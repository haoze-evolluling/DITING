package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.data.entity.SubscriptionSourceType
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup

@Composable
fun SubscriptionScreen(
    onBack: () -> Unit,
    ruleScope: com.haoze.dnssr.data.entity.RuleScope = com.haoze.dnssr.data.entity.RuleScope.DNS,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    viewModel: SubscriptionViewModel = viewModel()
) {
    val context = LocalContext.current
    val subscriptions by viewModel.subscriptions.collectAsStateWithLifecycle()
    val pendingSubscriptions by viewModel.pendingSubscriptions.collectAsStateWithLifecycle()
    val dnsImportCandidates by viewModel.dnsImportCandidates.collectAsStateWithLifecycle()
    val mirrorTemplates by viewModel.mirrorTemplates.collectAsStateWithLifecycle(initialValue = emptyList())
    val subscriptionGroups by viewModel.subscriptionGroups.collectAsStateWithLifecycle(initialValue = emptyList())
    val allSubscriptions by viewModel.allSubscriptions.collectAsStateWithLifecycle(initialValue = emptyList())
    val ruleBreakdowns by viewModel.ruleBreakdowns.collectAsStateWithLifecycle()
    val importing by viewModel.importing.collectAsStateWithLifecycle()
    val importingSubscriptionId by viewModel.importingSubscriptionId.collectAsStateWithLifecycle()
    val subscriptionProgress by viewModel.progress.collectAsStateWithLifecycle()
    val operationMessage by viewModel.operationMessage.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val busy = importing || operationMessage != null
    val displayedSubscriptions = pendingSubscriptions.filter { pending ->
        subscriptions.none { it.url == pending.url }
    } + subscriptions

    var showAddChoiceDialog by remember { mutableStateOf(false) }
    var showAddDialog by remember { mutableStateOf(false) }
    var pendingKind by remember { mutableStateOf(SubscriptionKind.UNIFIED) }
    var showDnsImportDialog by remember { mutableStateOf(false) }
    var showActionDialog by remember { mutableStateOf<SubscriptionEntity?>(null) }
    var showDeleteDialog by remember { mutableStateOf<SubscriptionEntity?>(null) }
    var showUrlDialog by remember { mutableStateOf<SubscriptionEntity?>(null) }
    var showEditDialog by remember { mutableStateOf<SubscriptionEntity?>(null) }
    var showRenameDialog by remember { mutableStateOf<SubscriptionEntity?>(null) }
    var showGroupActionDialog by remember { mutableStateOf<SubscriptionGroupEntity?>(null) }
    var showRenameGroupDialog by remember { mutableStateOf<SubscriptionGroupEntity?>(null) }
    var showDeleteGroupDialog by remember { mutableStateOf<SubscriptionGroupEntity?>(null) }
    var showDeleteGroupSubscriptionsDialog by remember { mutableStateOf<SubscriptionGroupEntity?>(null) }
    var selectedGroupId by remember { mutableStateOf<Long?>(null) }
    var selectionInitialized by remember { mutableStateOf(false) }

    LaunchedEffect(subscriptionGroups) {
        if (!selectionInitialized && subscriptionGroups.isNotEmpty()) {
            selectedGroupId = subscriptionGroups.first().id
            selectionInitialized = true
        }
        if (selectedGroupId != null && subscriptionGroups.none { it.id == selectedGroupId }) {
            selectedGroupId = null
        }
    }

    NavigationSettledEffect(ruleScope) {
        viewModel.activate(ruleScope)
    }

    message?.let { resultMessage ->
        androidx.compose.runtime.LaunchedEffect(resultMessage) {
            context.showToast(resultMessage, Toast.LENGTH_LONG)
            kotlinx.coroutines.delay(3000)
            viewModel.clearMessage()
        }
    }

    SettingsScaffold(
        title = localizedText("规则订阅"),
        onBack = onBack,
        actions = {
            IconButton(onClick = viewModel::updateAllSubscriptions, enabled = displayedSubscriptions.isNotEmpty() && !busy) {
                Icon(Icons.Default.Refresh, contentDescription = localizedText("更新所有订阅"))
            }
            IconButton(onClick = {
                if (ruleScope == com.haoze.dnssr.data.entity.RuleScope.HTTPS) {
                    showAddChoiceDialog = true
                } else {
                    pendingKind = SubscriptionKind.UNIFIED
                    showAddDialog = true
                }
            }, enabled = !busy) {
                Icon(Icons.Default.Add, contentDescription = localizedText("添加规则订阅"))
            }
        },
        belowTopBar = {
            SubscriptionGroupTabs(
                groups = subscriptionGroups,
                selectedGroupId = selectedGroupId,
                onGroupSelected = {
                    selectionInitialized = true
                    selectedGroupId = it
                },
                onGroupLongClick = { showGroupActionDialog = it }
            )
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(top = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            message?.let {
                item {
                    SettingsInfoText(text = localizedText(it), modifier = Modifier.padding(top = 8.dp))
                }
            }

            item {
                if (displayedSubscriptions.isEmpty() && !busy) {
                    SettingsGroupTitle(localizedText("规则订阅"))
                    SettingsSurfaceGroup(
                        content = listOf {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    text = localizedText("暂无规则订阅"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    text = localizedText("点击右上角 + 添加 AdGuard DNS 规则地址"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    )
                } else {
                    Column {
                        val selectedGroup = subscriptionGroups.firstOrNull { it.id == selectedGroupId }
                        val selectedSubscriptions = displayedSubscriptions.filter {
                            it.groupId == selectedGroupId
                        }
                        SettingsGroupTitle(selectedGroup?.name ?: localizedText("未分组"))
                        if (selectedSubscriptions.isNotEmpty()) {
                            SubscriptionItems(
                                selectedSubscriptions,
                                busy,
                                importingSubscriptionId,
                                subscriptionProgress,
                                ruleBreakdowns,
                                onShowUrl = { if (it.sourceType == SubscriptionSourceType.REMOTE) showUrlDialog = it },
                                onShowActions = { showActionDialog = it }
                            )
                        } else {
                            SettingsSurfaceGroup(
                                content = listOf(
                                    {
                                        Box(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .padding(24.dp),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Text(
                                                text = localizedText("该分组暂无规则订阅"),
                                                style = MaterialTheme.typography.bodyMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
            }

            item {
                SettingsInfoText(
                    text = localizedText("支持 AdGuard DNS 过滤、白名单、hosts IP 覆写及复合规则自动分类。支持 BOM、行尾注释、hosts 多域名和 IDN 域名。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }
    }

    if (showAddChoiceDialog) {
        AddSubscriptionChoiceDialog(
            onDismiss = { showAddChoiceDialog = false },
            onAddRemote = {
                pendingKind = SubscriptionKind.UNIFIED
                showAddChoiceDialog = false
                showAddDialog = true
            },
            onImportFromDns = if (ruleScope == com.haoze.dnssr.data.entity.RuleScope.HTTPS) {
                {
                    showAddChoiceDialog = false
                    showDnsImportDialog = true
                }
            } else null
        )
    }

    if (showAddDialog) {
        AddSubscriptionDialog(
            onDismiss = { showAddDialog = false },
            mirrorTemplates = mirrorTemplates,
            groups = subscriptionGroups,
            onConfirm = { url, name, mirrorTemplate, mirrorFallback, groupId, newGroupName ->
                viewModel.addSubscription(url, name, pendingKind, mirrorTemplate, mirrorFallback, groupId, newGroupName)
                showAddDialog = false
            }
        )
    }

    if (showDnsImportDialog) {
        DnsSubscriptionImportDialog(
            candidates = dnsImportCandidates,
            existingUrls = displayedSubscriptions.mapTo(HashSet()) { it.url },
            onDismiss = { showDnsImportDialog = false },
            onConfirm = { ids ->
                viewModel.importDnsSubscriptions(ids)
                showDnsImportDialog = false
            }
        )
    }

    showUrlDialog?.let { sub ->
        AlertDialog(
            onDismissRequest = { showUrlDialog = null },
            title = { Text(localizedText("订阅地址")) },
            text = {
                Column {
                    SelectionContainer {
                        Text(
                            text = sub.url,
                            style = MaterialTheme.typography.bodyMedium,
                            softWrap = true
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showUrlDialog = null }) {
                    Text(localizedText("关闭"))
                }
            }
        )
    }

    showActionDialog?.let { sub ->
        SubscriptionActionDialog(
            subscription = sub,
            onDismiss = { showActionDialog = null },
            onUpdate = {
                viewModel.updateSubscription(sub.id)
                showActionDialog = null
            },
            onDelete = {
                showActionDialog = null
                showDeleteDialog = sub
            },
            onEdit = {
                showActionDialog = null
                if (sub.sourceType == SubscriptionSourceType.LOCAL) {
                    showRenameDialog = sub
                } else {
                    showEditDialog = sub
                }
            },
            onToggleEnabled = {
                viewModel.toggleSubscriptionEnabled(sub.id, !sub.enabled)
                showActionDialog = null
            }
        )
    }

    showEditDialog?.let { sub ->
        EditSubscriptionDialog(
            subscription = sub,
            mirrorTemplates = mirrorTemplates,
            groups = subscriptionGroups,
            onDismiss = { showEditDialog = null },
            onConfirm = { url, name, mirrorTemplate, mirrorFallback, groupId, newGroupName ->
                viewModel.editSubscription(sub.id, url, name, mirrorTemplate, mirrorFallback, groupId, newGroupName)
                showEditDialog = null
            }
        )
    }

    showRenameDialog?.let { sub ->
        RenameSubscriptionDialog(
            subscription = sub,
            onDismiss = { showRenameDialog = null },
            onConfirm = { name ->
                viewModel.renameSubscription(sub.id, name)
                showRenameDialog = null
            }
        )
    }

    showDeleteDialog?.let { sub ->
        AlertDialog(
            onDismissRequest = { showDeleteDialog = null },
            title = { Text(localizedText("删除规则订阅")) },
            text = {
                Column {
                    Text(localizedText("确定删除「${sub.name}」及其导入的所有规则吗？"))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteSubscription(sub.id)
                    showDeleteDialog = null
                }) {
                    Text(localizedText("删除"), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = null }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }
    showGroupActionDialog?.let { group ->
        SubscriptionGroupActionDialog(
            group = group,
            onDismiss = { showGroupActionDialog = null },
            onRename = { showGroupActionDialog = null; showRenameGroupDialog = group },
            onDissolve = { showGroupActionDialog = null; showDeleteGroupDialog = group },
            onDeleteSubscriptions = { showGroupActionDialog = null; showDeleteGroupSubscriptionsDialog = group }
        )
    }
    showRenameGroupDialog?.let { group ->
        RenameGroupDialog(group, { showRenameGroupDialog = null }, {
            viewModel.renameGroup(group.id, it)
            showRenameGroupDialog = null
        })
    }
    showDeleteGroupDialog?.let { group ->
        AlertDialog(
            onDismissRequest = { showDeleteGroupDialog = null },
            title = { Text(localizedText("解散分组")) },
            text = { Text(localizedText("解散「${group.name}」后，组内订阅将移至未分组，不会删除订阅及规则。")) },
            confirmButton = { TextButton(onClick = { viewModel.deleteGroup(group.id); showDeleteGroupDialog = null }) { Text(localizedText("解散"), color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { showDeleteGroupDialog = null }) { Text(localizedText("取消")) } }
        )
    }
    showDeleteGroupSubscriptionsDialog?.let { group ->
        val members = allSubscriptions.filter { it.groupId == group.id }
        AlertDialog(
            onDismissRequest = { showDeleteGroupSubscriptionsDialog = null },
            title = { Text(localizedText("删除分组订阅")) },
            text = { Text(localizedText("确定删除「${group.name}」中的全部 ${members.size} 个订阅及其规则吗？")) },
            confirmButton = { TextButton(onClick = { viewModel.deleteGroupSubscriptions(group.id); showDeleteGroupSubscriptionsDialog = null }) { Text(localizedText("删除"), color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { showDeleteGroupSubscriptionsDialog = null }) { Text(localizedText("取消")) } }
        )
    }
}
