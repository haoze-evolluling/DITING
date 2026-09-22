package com.haoze.diting.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
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
import com.haoze.diting.data.entity.MirrorTemplateEntity
import com.haoze.diting.data.entity.SubscriptionEntity
import com.haoze.diting.data.entity.SubscriptionGroupEntity
import com.haoze.diting.data.entity.SubscriptionKind
import com.haoze.diting.data.entity.SubscriptionSourceType
import com.haoze.diting.ui.components.AppAlertDialog as AlertDialog
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsDivider
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsSurfaceGroup

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
                Text(
                    text = localizedText("规则类型：${SubscriptionKind.displayName(subscription.kind)}（不可修改，如需更换请删除后重新添加）"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 12.dp)
                )
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
