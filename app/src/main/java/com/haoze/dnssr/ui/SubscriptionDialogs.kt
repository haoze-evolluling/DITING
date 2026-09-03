package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.data.entity.SubscriptionSourceType
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup

@Composable
internal fun SubscriptionActionDialog(
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
internal fun AddSubscriptionChoiceDialog(
    onDismiss: () -> Unit,
    onAddRemote: () -> Unit,
    onImportFromDns: (() -> Unit)?
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("添加规则订阅")) },
        text = {
            Column {
                SettingsSurfaceGroup(
                    groupContentPadding = PaddingValues.Zero,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    content = buildList {
                        add {
                            SettingsItem(
                                title = localizedText("添加网络规则订阅"),
                                subtitle = localizedText("支持 AdGuard、hosts 及复合网络规则订阅链接"),
                                leadingIcon = Icons.Default.CloudDownload,
                                onClick = onAddRemote
                            )
                        }
                        if (onImportFromDns != null) {
                            add {
                                SettingsItem(
                                    title = localizedText("复制 DNS 订阅导入"),
                                    subtitle = localizedText("从 DNS 范围复制已有网络订阅"),
                                    leadingIcon = Icons.AutoMirrored.Filled.PlaylistAdd,
                                    onClick = onImportFromDns
                                )
                            }
                        }
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
internal fun AddSubscriptionDialog(
    onDismiss: () -> Unit,
    mirrorTemplates: List<MirrorTemplateEntity>,
    groups: List<SubscriptionGroupEntity>,
    onConfirm: (url: String, name: String, mirrorTemplate: String?, mirrorFallback: Boolean, groupId: Long?, newGroupName: String?) -> Unit
) {
    var step by remember { mutableStateOf(1) }
    var url by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var useMirror by remember { mutableStateOf(false) }
    var mirrorTemplate by remember { mutableStateOf("") }
    var mirrorFallback by remember { mutableStateOf(true) }
    var groupId by remember { mutableStateOf<Long?>(null) }
    var newGroupName by remember { mutableStateOf("") }

    when (step) {
        1 -> {
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text(localizedText("添加规则订阅 (1/3)")) },
                text = {
                    Column {
                        Text(
                            text = localizedText("输入规则订阅链接（支持 AdGuard 过滤/白名单、hosts 覆写及复合规则），系统将自动识别并分类导入。"),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        SubscriptionDialogCard(title = localizedText("订阅信息")) {
                            SubscriptionUrlField(
                                url = url,
                                onUrlChange = { url = it },
                                placeholder = "https://example.com/rules.txt"
                            )
                            SettingsDivider()
                            SubscriptionNameField(name = name, onNameChange = { name = it }, optional = true)
                        }
                    }
                },
                confirmButton = {
                    TextButton(
                        onClick = { step = 2 },
                        enabled = url.trim().startsWith("http")
                    ) {
                        Text(localizedText("下一步"))
                    }
                },
                dismissButton = {
                    TextButton(onClick = onDismiss) {
                        Text(localizedText("取消"))
                    }
                }
            )
        }
        2 -> {
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text(localizedText("添加规则订阅 (2/3)")) },
                text = {
                    Column {
                        Text(
                            text = localizedText("为订阅指定所属分组，便于分类管理和批量操作；也可以在此新建分组或保持未分组。"),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        SubscriptionGroupSelector(
                            groups = groups,
                            selectedGroupId = groupId,
                            newGroupName = newGroupName,
                            onGroupSelected = { groupId = it },
                            onNewGroupNameChange = { newGroupName = it }
                        )
                    }
                },
                confirmButton = {
                    TextButton(onClick = { step = 3 }) {
                        Text(localizedText("下一步"))
                    }
                },
                dismissButton = {
                    TextButton(onClick = { step = 1 }) {
                        Text(localizedText("上一步"))
                    }
                }
            )
        }
        3 -> {
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text(localizedText("添加规则订阅 (3/3)")) },
                text = {
                    Column {
                        Text(
                            text = localizedText("若订阅源访问较慢或受限，可启用镜像站加速下载规则；无需加速可直接导入。"),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(16.dp))
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
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            onConfirm(
                                url.trim(),
                                name.trim(),
                                mirrorTemplate.trim().takeIf { useMirror },
                                mirrorFallback,
                                groupId,
                                newGroupName.trim().takeIf { it.isNotEmpty() }
                            )
                        },
                        enabled = !useMirror || validMirrorTemplate(mirrorTemplate)
                    ) {
                        Text(localizedText("导入规则"))
                    }
                },
                dismissButton = {
                    TextButton(onClick = { step = 2 }) {
                        Text(localizedText("上一步"))
                    }
                }
            )
        }
    }
}

@Composable
internal fun DnsSubscriptionImportDialog(
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
internal fun EditSubscriptionDialog(
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
internal fun RenameSubscriptionDialog(
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
