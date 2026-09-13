package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MoreVert
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsOutlinedActionButton
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup

private val mirrorTemplatePlaceholders = listOf(
    "{url}",
    "{scheme}",
    "{urlEncoded}",
    "{host}",
    "{path}",
    "{pathAndQuery}"
)

@Composable
fun MirrorTemplateScreen(
    onBack: () -> Unit,
    onNavigateToFormatGuide: () -> Unit,
    viewModel: RuleManagementViewModel = viewModel()
) {
    val templates by viewModel.mirrorTemplates.collectAsStateWithLifecycle(initialValue = emptyList())
    var showAddDialog by remember { mutableStateOf(false) }
    var editingTemplate by remember { mutableStateOf<MirrorTemplateEntity?>(null) }
    var selectedTemplate by remember { mutableStateOf<MirrorTemplateEntity?>(null) }
    var pendingDeletion by remember { mutableStateOf<MirrorTemplateEntity?>(null) }

    SettingsScaffold(title = localizedText("镜像站模板"), onBack = onBack) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsInfoText(
            localizedText("保存常用的订阅下载镜像。添加规则订阅时，可以直接选择这里的模板。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
            item { SettingsGroupTitle(localizedText("操作")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("添加模板"),
                        subtitle = localizedText("填写镜像站名称和地址格式"),
                        leadingIcon = Icons.Default.Add,
                        onClick = { showAddDialog = true }
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("镜像站格式示例"),
                        subtitle = localizedText("了解占位符如何组成镜像地址"),
                        leadingIcon = Icons.Default.Info,
                        onClick = onNavigateToFormatGuide
                        )
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("已保存模板（${templates.size}）")) }
            if (templates.isEmpty()) {
                item { SettingsInfoText(localizedText("暂无模板。点击上方“添加模板”开始使用。")) }
            } else {
                item {
                    SettingsSurfaceGroup(
                        content = templates.map { template ->
                            {
                                SettingsItem(
                                    title = template.name,
                                    subtitle = template.template,
                                    trailing = {
                                        IconButton(onClick = { selectedTemplate = template }) {
                Icon(Icons.Default.MoreVert, contentDescription = localizedText("${template.name} 的更多操作"))
                                        }
                                    }
                                )
                            }
                        }
                    )
                }
            }
        }
    }

    if (showAddDialog) {
        MirrorTemplateDialog(
            onDismiss = { showAddDialog = false },
            onSubmit = { name, template, onResult -> viewModel.addMirrorTemplate(name, template, onResult) },
            onSaved = { showAddDialog = false }
        )
    }

    selectedTemplate?.let { template ->
        AlertDialog(
            onDismissRequest = { selectedTemplate = null },
            title = { Text(template.name) },
            text = {
                SettingsSurfaceGroup(
                    groupContentPadding = PaddingValues.Zero,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    content = listOf(
                        {
                            SettingsItem(
                                title = localizedText("编辑模板"),
                                leadingIcon = Icons.Default.Edit,
                                onClick = {
                                    selectedTemplate = null
                                    editingTemplate = template
                                }
                            )
                        },
                        {
                            SettingsItem(
                                title = localizedText("删除模板"),
                                leadingIcon = Icons.Default.Delete,
                                titleColor = MaterialTheme.colorScheme.error,
                                onClick = {
                                    selectedTemplate = null
                                    pendingDeletion = template
                                }
                            )
                        }
                    )
                )
            },
            confirmButton = {
                TextButton(onClick = { selectedTemplate = null }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

    editingTemplate?.let { template ->
        MirrorTemplateDialog(
            template = template,
            onDismiss = { editingTemplate = null },
            onSubmit = { name, address, onResult -> viewModel.editMirrorTemplate(template, name, address, onResult) },
            onSaved = { editingTemplate = null }
        )
    }

    pendingDeletion?.let { template ->
        AlertDialog(
            onDismissRequest = { pendingDeletion = null },
            title = { Text(localizedText("删除镜像站模板")) },
            text = { Text(localizedText("确定要删除“${template.name}”吗？已使用此模板的订阅不会被修改。")) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteMirrorTemplate(template)
                    pendingDeletion = null
                }) { Text(localizedText("删除"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { pendingDeletion = null }) { Text(localizedText("取消")) } }
        )
    }
}

@Composable
private fun MirrorTemplateDialog(
    template: MirrorTemplateEntity? = null,
    onDismiss: () -> Unit,
    onSubmit: (String, String, (String) -> Unit) -> Unit,
    onSaved: () -> Unit
) {
    val isEditing = template != null
    var name by remember(template?.id) { mutableStateOf(template?.name.orEmpty()) }
    var address by remember(template?.id) { mutableStateOf(template?.template.orEmpty()) }
    var error by remember { mutableStateOf<String?>(null) }
    var submitting by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = { if (!submitting) onDismiss() },
        title = { Text(localizedText(if (isEditing) "编辑镜像站模板" else "添加镜像站模板")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(localizedText(if (isEditing) "修改后，已使用此模板的订阅不会被自动更新。" else "保存后，可在添加规则订阅时直接选择。"), style = MaterialTheme.typography.bodyMedium)
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it; error = null },
                    label = { Text(localizedText("模板名称")) },
                    placeholder = { Text(localizedText("例如：GitHub 镜像")) },
                    singleLine = true,
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = address,
                    onValueChange = { address = it; error = null },
                    label = { Text(localizedText("模板地址")) },
                placeholder = { Text(localizedText("https://mirror.example.com/{url}")) },
                    supportingText = { Text(localizedText(error ?: "必须使用 HTTP(S) 并包含至少一个占位符")) },
                    isError = error != null,
                    minLines = 2,
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    mirrorTemplatePlaceholders.chunked(3).forEach { rowPlaceholders ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            rowPlaceholders.forEachIndexed { index, placeholder ->
                                SettingsOutlinedActionButton(
                                    onClick = {
                                        address += placeholder
                                        error = null
                                    },
                                    modifier = Modifier.weight(if (index == 2) 0.4f else 0.3f),
                                    contentPadding = PaddingValues(horizontal = 4.dp)
                                ) {
                                    Text(placeholder, style = MaterialTheme.typography.labelMedium)
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !submitting && name.isNotBlank() && address.isNotBlank(),
                onClick = {
                    submitting = true
                    onSubmit(name, address) { message ->
                        submitting = false
                        if (message == "已添加镜像站模板" || message == "已更新镜像站模板") onSaved() else error = message
                    }
                }
            ) { Text(localizedText(if (submitting) if (isEditing) "保存中..." else "添加中..." else if (isEditing) "保存" else "添加")) }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !submitting) { Text(localizedText("取消")) } }
    )
}
