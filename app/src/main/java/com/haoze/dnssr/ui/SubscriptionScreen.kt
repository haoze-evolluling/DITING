package com.haoze.dnssr.ui

import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.BorderStroke
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlaylistAdd
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.data.entity.SubscriptionImportState
import com.haoze.dnssr.data.entity.SubscriptionSourceType
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
    val importing by viewModel.importing.collectAsStateWithLifecycle()
    val importingSubscriptionId by viewModel.importingSubscriptionId.collectAsStateWithLifecycle()
    val operationMessage by viewModel.operationMessage.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val busy = importing || operationMessage != null
    val displayedSubscriptions = pendingSubscriptions.filter { pending ->
        subscriptions.none { it.url == pending.url && it.scope == pending.scope }
    } + subscriptions

    var showAddChoiceDialog by remember { mutableStateOf(false) }
    var showAddDialog by remember { mutableStateOf(false) }
    var pendingKind by remember { mutableStateOf(SubscriptionKind.BLOCK) }
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

    // 消息自动清除
    message?.let { resultMessage ->
        androidx.compose.runtime.LaunchedEffect(resultMessage) {
            Toast.makeText(context, localizedText(context, resultMessage), Toast.LENGTH_LONG).show()
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
            IconButton(onClick = { showAddChoiceDialog = true }, enabled = !busy) {
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
            // 操作结果消息
            message?.let {
                item {
                    SettingsInfoText(text = localizedText(it), modifier = Modifier.padding(top = 8.dp))
                }
            }

            item {
                if (displayedSubscriptions.isEmpty() && !busy) {
                    SettingsGroupTitle(localizedText("规则订阅"))
                    SettingsGroup {
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
                } else {
                    Column {
                        val selectedGroup = subscriptionGroups.firstOrNull { it.id == selectedGroupId }
                        val selectedSubscriptions = displayedSubscriptions.filter {
                            it.groupId == selectedGroupId
                        }
                        SettingsGroupTitle(selectedGroup?.name ?: localizedText("未分组"))
                        if (selectedSubscriptions.isNotEmpty()) {
                            SubscriptionItems(selectedSubscriptions, busy, importingSubscriptionId,
                                onShowUrl = { if (it.sourceType == SubscriptionSourceType.REMOTE) showUrlDialog = it },
                                onShowActions = { showActionDialog = it })
                        } else {
                            SettingsGroup {
                                Text(
                                    text = localizedText("该分组暂无规则订阅"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(24.dp)
                                )
                            }
                        }
                    }
                }
            }

            item {
                SettingsInfoText(
                    text = localizedText("依据 AdGuard DNS 语法自动分类黑白名单。支持 BOM、行尾注释、hosts 多域名和 IDN 域名。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }
    }

    if (showAddChoiceDialog) {
        AddSubscriptionChoiceDialog(
            onDismiss = { showAddChoiceDialog = false },
            onAddRemote = {
                pendingKind = SubscriptionKind.BLOCK
                showAddChoiceDialog = false
                showAddDialog = true
            },
            onImportFromDns = if (ruleScope == com.haoze.dnssr.data.entity.RuleScope.HTTPS) {
                {
                    showAddChoiceDialog = false
                    showDnsImportDialog = true
                }
            } else null,
            onAddRewriteRemote = {
                pendingKind = SubscriptionKind.REWRITE
                showAddChoiceDialog = false
                showAddDialog = true
            }
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

    // 订阅操作对话框
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

    // 删除确认对话框
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
        val dnsCount = members.count { it.scope == com.haoze.dnssr.data.entity.RuleScope.DNS.storageValue }
        val httpsCount = members.size - dnsCount
        AlertDialog(
            onDismissRequest = { showDeleteGroupSubscriptionsDialog = null },
            title = { Text(localizedText("删除分组订阅")) },
            text = { Text(localizedText("确定删除「${group.name}」中的全部 ${members.size} 个订阅及其规则吗？DNS $dnsCount 个，HTTPS $httpsCount 个。")) },
            confirmButton = { TextButton(onClick = { viewModel.deleteGroupSubscriptions(group.id); showDeleteGroupSubscriptionsDialog = null }) { Text(localizedText("删除"), color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { showDeleteGroupSubscriptionsDialog = null }) { Text(localizedText("取消")) } }
        )
    }
}

@Composable
private fun SubscriptionItem(
    subscription: SubscriptionEntity,
    onShowUrl: () -> Unit,
    onShowActions: () -> Unit,
    actionsEnabled: Boolean,
    isUpdating: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = subscription.name,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (subscription.enabled) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
                Text(
                    text = buildString {
                        append(localizedText(if (subscription.kind == SubscriptionKind.REWRITE) "hosts 覆写" else "DNS 过滤"))
                        if (subscription.mirrorTemplate != null) append(localizedText(" · 自定义镜像"))
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = if (subscription.sourceType == SubscriptionSourceType.LOCAL) localizedText("本地文件") else subscription.url,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = if (subscription.sourceType == SubscriptionSourceType.REMOTE) {
                        Modifier.clickable(onClick = onShowUrl)
                    } else {
                        Modifier
                    }
                )
            }
            IconButton(onClick = onShowActions, enabled = actionsEnabled) {
                Icon(
                    Icons.Default.MoreVert,
                    contentDescription = localizedText("打开规则订阅操作")
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = localizedText(if (subscription.enabled) "已启用" else "已禁用"),
                style = MaterialTheme.typography.bodySmall,
                color = if (subscription.enabled) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
            Text(
                text = localizedText("${subscription.ruleCount} 条规则"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (subscription.lastUpdated > 0) {
                val dateStr = remember(subscription.lastUpdated) {
                    SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
                        .format(Date(subscription.lastUpdated))
                }
                Text(
                    text = localizedText(if (subscription.sourceType == SubscriptionSourceType.LOCAL) {
                        "导入于 $dateStr"
                    } else {
                        "更新于 $dateStr"
                    }),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (subscription.sourceType == SubscriptionSourceType.REMOTE && subscription.lastAttemptAt > 0) {
            val attemptDate = remember(subscription.lastAttemptAt) {
                SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
                    .format(Date(subscription.lastAttemptAt))
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = localizedText("上次尝试于 $attemptDate"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (isUpdating || subscription.importState == SubscriptionImportState.IMPORTING) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = localizedText("正在下载并更新规则..."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(4.dp))
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
        if (subscription.importState == SubscriptionImportState.FAILED) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = localizedText(if (subscription.sourceType == SubscriptionSourceType.REMOTE) {
                    "更新失败（连续 ${subscription.consecutiveFailureCount} 次）：" +
                        (subscription.importError ?: "未知错误")
                } else {
                    "导入失败：${subscription.importError ?: "未知错误"}"
                }),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }
    }
}

@Composable
private fun SubscriptionGroupTabs(
    groups: List<SubscriptionGroupEntity>,
    selectedGroupId: Long?,
    onGroupSelected: (Long?) -> Unit,
    onGroupLongClick: (SubscriptionGroupEntity) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SubscriptionGroupTab(localizedText("未分组"), selectedGroupId == null, { onGroupSelected(null) })
        groups.forEach { group ->
            SubscriptionGroupTab(
                name = group.name,
                selected = selectedGroupId == group.id,
                onClick = { onGroupSelected(group.id) },
                onLongClick = { onGroupLongClick(group) }
            )
        }
    }
}

@Composable
private fun SubscriptionGroupTab(
    name: String,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null
) {
    val containerColor = if (selected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent
    val contentColor = if (selected) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant
    Text(
        text = name,
        style = MaterialTheme.typography.labelLarge,
        color = contentColor,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(containerColor)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 16.dp, vertical = 10.dp)
    )
}

@Composable
private fun SubscriptionItems(
    subscriptions: List<SubscriptionEntity>,
    busy: Boolean,
    importingSubscriptionId: Long?,
    onShowUrl: (SubscriptionEntity) -> Unit,
    onShowActions: (SubscriptionEntity) -> Unit
) {
    SettingsSurfaceGroup(
        content = subscriptions.map { sub ->
            {
                SubscriptionItem(
                    sub,
                    { onShowUrl(sub) },
                    { onShowActions(sub) },
                    !busy,
                    importingSubscriptionId == sub.id
                )
            }
        }
    )
}

@Composable
private fun SubscriptionActionDialog(
    subscription: SubscriptionEntity,
    onDismiss: () -> Unit,
    onUpdate: () -> Unit,
    onDelete: () -> Unit,
    onEdit: () -> Unit,
    onToggleEnabled: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(subscription.name) },
        text = {
            SettingsSurfaceGroup(
                groupContentPadding = PaddingValues.Zero,
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                content = buildList {
                    if (subscription.sourceType == SubscriptionSourceType.REMOTE) {
                        add {
                            SettingsItem(
                                title = localizedText("更新规则"),
                                leadingIcon = Icons.Default.Refresh,
                                onClick = onUpdate,
                            )
                        }
                    }
                    add {
                        SettingsItem(
                            title = localizedText(if (subscription.sourceType == SubscriptionSourceType.LOCAL) "重命名订阅" else "编辑订阅"),
                            leadingIcon = Icons.Default.Edit,
                            onClick = onEdit,
                        )
                    }
                    add {
                        SettingsItem(
                            title = localizedText(if (subscription.enabled) "禁用规则" else "启用规则"),
                            leadingIcon = Icons.Default.PowerSettingsNew,
                            onClick = onToggleEnabled,
                        )
                    }
                    add {
                        SettingsItem(
                            title = localizedText("删除规则"),
                            leadingIcon = Icons.Default.Delete,
                            titleColor = MaterialTheme.colorScheme.error,
                            onClick = onDelete,
                        )
                    }
                }
            )
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}

@Composable
private fun AddSubscriptionDialog(
    onDismiss: () -> Unit,
    mirrorTemplates: List<MirrorTemplateEntity>,
    groups: List<SubscriptionGroupEntity>,
    onConfirm: (url: String, name: String, mirrorTemplate: String?, mirrorFallback: Boolean, groupId: Long?, newGroupName: String?) -> Unit
) {
    var url by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var useMirror by remember { mutableStateOf(false) }
    var mirrorTemplate by remember { mutableStateOf("") }
    var mirrorFallback by remember { mutableStateOf(true) }
    var groupId by remember { mutableStateOf<Long?>(null) }
    var newGroupName by remember { mutableStateOf("") }
    var groupExpanded by remember { mutableStateOf(false) }
    var mirrorExpanded by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("添加规则订阅")) },
        text = {
            Column {
                Text(
                    text = localizedText("输入 AdGuard DNS 规则订阅地址，导入时会自动区分黑名单和白名单规则。"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(16.dp))
                SubscriptionDialogCard(title = localizedText("订阅信息")) {
                    SubscriptionUrlField(
                        url = url,
                        onUrlChange = { url = it },
                        placeholder = "https://example.com/filter.txt"
                    )
                    SettingsDivider()
                    SubscriptionNameField(name = name, onNameChange = { name = it }, optional = true)
                }
                Spacer(modifier = Modifier.height(12.dp))
                SubscriptionDialogExpandableCard(
                    title = localizedText("订阅分组"),
                    summary = selectedGroupSummary(groups, groupId, newGroupName),
                    expanded = groupExpanded,
                    onExpandedChange = { groupExpanded = it }
                ) {
                    SubscriptionGroupSelector(groups, groupId, newGroupName, { groupId = it }, { newGroupName = it })
                }
                Spacer(modifier = Modifier.height(12.dp))
                SubscriptionDialogExpandableCard(
                    title = localizedText("自定义镜像"),
                    summary = mirrorSummary(mirrorTemplates, useMirror, mirrorTemplate),
                    expanded = mirrorExpanded,
                    onExpandedChange = { mirrorExpanded = it }
                ) {
                    MirrorEditor(
                        originalUrl = url,
                        mirrorTemplates = mirrorTemplates,
                        enabled = useMirror,
                        template = mirrorTemplate,
                        fallback = mirrorFallback,
                        onEnabledChange = { useMirror = it },
                        onTemplateChange = { mirrorTemplate = it },
                        onFallbackChange = { mirrorFallback = it }
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onConfirm(url.trim(), name.trim(), mirrorTemplate.trim().takeIf { useMirror }, mirrorFallback, groupId, newGroupName.trim().takeIf { it.isNotEmpty() })
                },
                enabled = url.trim().startsWith("http") && (!useMirror || validMirrorTemplate(mirrorTemplate))
            ) {
                Text(localizedText("导入规则"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}

@Composable
private fun AddSubscriptionChoiceDialog(
    onDismiss: () -> Unit,
    onAddRemote: () -> Unit,
    onImportFromDns: (() -> Unit)?,
    onAddRewriteRemote: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("添加规则订阅")) },
        text = {
            Column {
                Text(
                    text = localizedText("DNS 过滤规则"),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                )
                SettingsSurfaceGroup(
                    groupContentPadding = PaddingValues.Zero,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    content = buildList {
                        add {
                            SettingsItem(
                                title = localizedText("网络 DNS 过滤订阅"),
                                leadingIcon = Icons.Default.CloudDownload,
                                onClick = onAddRemote
                            )
                        }
                        if (onImportFromDns != null) {
                            add {
                                SettingsItem(
                                    title = localizedText("复制 DNS 订阅导入"),
                                    leadingIcon = Icons.Default.PlaylistAdd,
                                    onClick = onImportFromDns
                                )
                            }
                        }
                    }
                )
                Text(
                    text = localizedText("hosts 覆写规则"),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                )
                SettingsSurfaceGroup(
                    groupContentPadding = PaddingValues.Zero,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    content = listOf {
                        SettingsItem(
                            title = localizedText("网络 hosts 覆写订阅"),
                            leadingIcon = Icons.Default.CloudDownload,
                            onClick = onAddRewriteRemote
                        )
                    }
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(localizedText("取消")) }
        }
    )
}

@Composable
private fun DnsSubscriptionImportDialog(
    candidates: List<SubscriptionEntity>,
    existingUrls: Set<String>,
    onDismiss: () -> Unit,
    onConfirm: (Set<Long>) -> Unit
) {
    var selectedIds by remember { mutableStateOf<Set<Long>>(emptySet()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("复制 DNS 订阅导入")) },
        text = {
            Column {
                Text(
                    text = localizedText("复制 DNS 的网络过滤订阅到 HTTPS，之后两边可独立维护。"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 12.dp)
                )
                if (candidates.isEmpty()) {
                    Text(
                        text = localizedText("暂无可导入的 DNS 网络过滤订阅"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 12.dp)
                    )
                } else {
                    candidates.forEachIndexed { index, subscription ->
                        val alreadyImported = subscription.url in existingUrls
                        SettingsCheckboxItem(
                            title = subscription.name,
                            subtitle = if (alreadyImported) localizedText("已导入 HTTPS") else subscription.url,
                            checked = subscription.id in selectedIds,
                            enabled = !alreadyImported,
                            contentPadding = PaddingValues(vertical = 12.dp),
                            onCheckedChange = { checked ->
                                selectedIds = if (checked) selectedIds + subscription.id else selectedIds - subscription.id
                            }
                        )
                        if (index < candidates.lastIndex) SettingsDivider()
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(selectedIds) }, enabled = selectedIds.isNotEmpty()) {
                Text(localizedText("导入规则"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(localizedText("取消")) }
        }
    )
}

@Composable
private fun EditSubscriptionDialog(
    subscription: SubscriptionEntity,
    mirrorTemplates: List<MirrorTemplateEntity>,
    groups: List<SubscriptionGroupEntity>,
    onDismiss: () -> Unit,
    onConfirm: (String, String, String?, Boolean, Long?, String?) -> Unit
) {
    var name by remember(subscription.id) { mutableStateOf(subscription.name) }
    var url by remember(subscription.id) { mutableStateOf(subscription.url) }
    var useMirror by remember(subscription.id) { mutableStateOf(subscription.mirrorTemplate != null) }
    var mirrorTemplate by remember(subscription.id) { mutableStateOf(subscription.mirrorTemplate.orEmpty()) }
    var mirrorFallback by remember(subscription.id) { mutableStateOf(subscription.mirrorFallback) }
    var groupId by remember(subscription.id) { mutableStateOf(subscription.groupId) }
    var newGroupName by remember(subscription.id) { mutableStateOf("") }
    var groupExpanded by remember(subscription.id) { mutableStateOf(false) }
    var mirrorExpanded by remember(subscription.id) { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("编辑规则订阅")) },
        text = {
            Column {
                SubscriptionDialogCard(title = localizedText("订阅信息")) {
                    SubscriptionUrlField(url = url, onUrlChange = { url = it })
                    SettingsDivider()
                    SubscriptionNameField(name = name, onNameChange = { name = it })
                }
                Spacer(modifier = Modifier.height(12.dp))
                SubscriptionDialogExpandableCard(
                    title = localizedText("订阅分组"),
                    summary = selectedGroupSummary(groups, groupId, newGroupName),
                    expanded = groupExpanded,
                    onExpandedChange = { groupExpanded = it }
                ) {
                    SubscriptionGroupSelector(groups, groupId, newGroupName, { groupId = it }, { newGroupName = it })
                }
                Spacer(modifier = Modifier.height(12.dp))
                SubscriptionDialogExpandableCard(
                    title = localizedText("自定义镜像"),
                    summary = mirrorSummary(mirrorTemplates, useMirror, mirrorTemplate),
                    expanded = mirrorExpanded,
                    onExpandedChange = { mirrorExpanded = it }
                ) {
                    MirrorEditor(
                        originalUrl = url,
                        mirrorTemplates = mirrorTemplates,
                        enabled = useMirror,
                        template = mirrorTemplate,
                        fallback = mirrorFallback,
                        onEnabledChange = { useMirror = it },
                        onTemplateChange = { mirrorTemplate = it },
                        onFallbackChange = { mirrorFallback = it }
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onConfirm(url.trim(), name.trim(), mirrorTemplate.trim().takeIf { useMirror }, mirrorFallback, groupId, newGroupName.trim().takeIf { it.isNotEmpty() })
                },
                enabled = url.trim().isNotEmpty() && name.trim().isNotEmpty() &&
                    (!useMirror || validMirrorTemplate(mirrorTemplate))
            ) {
                Text(localizedText("保存"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}

@Composable
private fun SubscriptionGroupActionDialog(
    group: SubscriptionGroupEntity,
    onDismiss: () -> Unit,
    onRename: () -> Unit,
    onDissolve: () -> Unit,
    onDeleteSubscriptions: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(group.name) },
        text = {
            Column {
                SettingsItem(localizedText("重命名分组"), leadingIcon = Icons.Default.Edit, onClick = onRename)
                SettingsDivider()
                SettingsItem(localizedText("解散分组"), leadingIcon = Icons.Default.Delete, onClick = onDissolve)
                SettingsDivider()
                SettingsItem(localizedText("删除本组全部订阅"), leadingIcon = Icons.Default.Delete, titleColor = MaterialTheme.colorScheme.error, onClick = onDeleteSubscriptions)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(localizedText("取消")) } }
    )
}

@Composable
private fun RenameGroupDialog(group: SubscriptionGroupEntity, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var name by remember(group.id) { mutableStateOf(group.name) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("重命名分组")) },
        text = { OutlinedTextField(name, { name = it }, label = { Text(localizedText("分组名称")) }, singleLine = true, shape = SettingsCornerShape, modifier = Modifier.fillMaxWidth()) },
        confirmButton = { TextButton(onClick = { onConfirm(name.trim()) }, enabled = name.isNotBlank()) { Text(localizedText("保存")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(localizedText("取消")) } }
    )
}

@Composable
private fun SubscriptionDialogCard(
    title: String,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit
) {
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.outlinedCardColors(
            containerColor = Color.Transparent
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    ) {
        Text(
            text = localizedText(title),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
        )
        SettingsDivider()
        Column(content = content)
    }
}

@Composable
private fun SubscriptionDialogExpandableCard(
    title: String,
    summary: String,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit
) {
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.outlinedCardColors(
            containerColor = Color.Transparent
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    ) {
        SettingsItem(
            title = title,
            subtitle = summary,
            onClick = { onExpandedChange(!expanded) }
        ) {
            Icon(
                imageVector = if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                contentDescription = localizedText(if (expanded) "收起$title" else "展开$title"),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (expanded) {
            SettingsDivider()
            Column(content = content)
        }
    }
}

@Composable
private fun SubscriptionUrlField(
    url: String,
    onUrlChange: (String) -> Unit,
    placeholder: String? = null
) {
    OutlinedTextField(
        value = url,
        onValueChange = onUrlChange,
        label = { Text(localizedText("订阅地址")) },
        placeholder = placeholder?.let { value -> { Text(localizedText(value)) } },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
        minLines = 2,
        maxLines = 4,
        shape = SettingsCornerShape,
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
    )
}

@Composable
private fun SubscriptionNameField(
    name: String,
    onNameChange: (String) -> Unit,
    optional: Boolean = false
) {
    OutlinedTextField(
        value = name,
        onValueChange = onNameChange,
        label = { Text(localizedText(if (optional) "订阅名称（可选）" else "订阅名称")) },
        placeholder = if (optional) { { Text(localizedText("例如：EasyList China")) } } else null,
        singleLine = true,
        shape = SettingsCornerShape,
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
    )
}

@Composable
private fun selectedGroupSummary(
    groups: List<SubscriptionGroupEntity>,
    selectedGroupId: Long?,
    newGroupName: String
): String = newGroupName.trim().takeIf { it.isNotEmpty() }
    ?: groups.firstOrNull { it.id == selectedGroupId }?.name
    ?: localizedText("未分组")

@Composable
private fun mirrorSummary(
    mirrorTemplates: List<MirrorTemplateEntity>,
    enabled: Boolean,
    template: String
): String {
    if (!enabled) return localizedText("未使用")
    return mirrorTemplates.firstOrNull { it.template == template }?.name
        ?: if (template.isBlank()) localizedText("未选择模板") else localizedText("自定义镜像")
}

@Composable
private fun SubscriptionGroupSelector(
    groups: List<SubscriptionGroupEntity>,
    selectedGroupId: Long?,
    newGroupName: String,
    onGroupSelected: (Long?) -> Unit,
    onNewGroupNameChange: (String) -> Unit
) {
    SettingsSurfaceGroup(
        groupContentPadding = PaddingValues.Zero,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        content = buildList {
            add {
                SettingsRadioItem(localizedText("未分组"), selectedGroupId == null && newGroupName.isBlank(), { onGroupSelected(null); onNewGroupNameChange("") })
            }
            groups.forEach { group ->
                add {
                    SettingsRadioItem(group.name, selectedGroupId == group.id && newGroupName.isBlank(), {
                        onGroupSelected(group.id); onNewGroupNameChange("")
                    })
                }
            }
        }
    )
    OutlinedTextField(
        value = newGroupName,
        onValueChange = { value -> onNewGroupNameChange(value); if (value.isNotBlank()) onGroupSelected(null) },
        label = { Text(localizedText("新建分组名称（可选）")) },
        singleLine = true,
        shape = SettingsCornerShape,
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
    )
}

@Composable
private fun MirrorEditor(
    originalUrl: String,
    mirrorTemplates: List<MirrorTemplateEntity>,
    enabled: Boolean,
    template: String,
    fallback: Boolean,
    onEnabledChange: (Boolean) -> Unit,
    onTemplateChange: (String) -> Unit,
    onFallbackChange: (Boolean) -> Unit
) {
    SettingsSurfaceGroup(
        groupContentPadding = PaddingValues.Zero,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        content = buildList {
            add {
                SettingsSwitchItem(
                    title = localizedText("使用自定义镜像"),
                    checked = enabled,
                    onCheckedChange = onEnabledChange
                )
            }
            if (enabled) {
                if (mirrorTemplates.isEmpty()) {
                    add {
                        SettingsItem(
                            title = localizedText("选择镜像站模板"),
                            subtitle = localizedText("暂无模板，请先在域名规则 → 镜像站模板中添加。"),
                            titleColor = MaterialTheme.colorScheme.error
                        )
                    }
                } else {
                    mirrorTemplates.forEach { item ->
                        add {
                            SubscriptionRadioItem(
                                title = item.name,
                                selected = template == item.template,
                                onClick = { onTemplateChange(item.template) }
                            )
                        }
                    }
                }
                mirrorPreview(template, originalUrl)?.let { preview ->
                    add { SettingsItem(title = localizedText("请求预览"), subtitle = preview) }
                }
                add {
                    SettingsSwitchItem(
                        title = localizedText("失败后回退直连"),
                        checked = fallback,
                        onCheckedChange = onFallbackChange
                    )
                }
            }
        }
    )

}

@Composable
private fun SubscriptionRadioItem(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    subtitle: String? = null
) {
    SettingsItem(
        title = title,
        subtitle = subtitle,
        onClick = onClick
    ) {
        RadioButton(
            selected = selected,
            onClick = null
        )
    }
}

private fun validMirrorTemplate(template: String): Boolean {
    val trimmed = template.trim()
    return (trimmed.startsWith("https://") || trimmed.startsWith("http://")) &&
        listOf("{url}", "{urlEncoded}", "{scheme}", "{host}", "{path}", "{pathAndQuery}").any { it in trimmed }
}

private fun mirrorPreview(template: String, originalUrl: String): String? {
    if (!validMirrorTemplate(template) || originalUrl.isBlank()) return null
    val uri = runCatching { Uri.parse(originalUrl.trim()) }.getOrNull() ?: return null
    val path = uri.encodedPath?.takeIf { it.isNotEmpty() } ?: "/"
    val pathAndQuery = path + (uri.encodedQuery?.let { "?$it" } ?: "")
    return template.trim()
        .replace("{urlEncoded}", Uri.encode(originalUrl.trim()))
        .replace("{url}", originalUrl.trim())
        .replace("{scheme}", uri.scheme.orEmpty())
        .replace("{host}", uri.host.orEmpty())
        .replace("{pathAndQuery}", pathAndQuery)
        .replace("{path}", path)
}

@Composable
private fun RenameSubscriptionDialog(
    subscription: SubscriptionEntity,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var name by remember(subscription.id) { mutableStateOf(subscription.name) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("重命名规则订阅")) },
        text = {
            Column {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(localizedText("订阅名称")) },
                    singleLine = true,
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(name.trim()) }, enabled = name.isNotBlank()) { Text(localizedText("保存")) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(localizedText("取消")) }
        }
    )
}


