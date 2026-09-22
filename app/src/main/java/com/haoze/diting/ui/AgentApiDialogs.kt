package com.haoze.diting.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.settings.AgentApiConfig
import com.haoze.diting.ui.settings.ModelPreset

/**
 * Preset management panel: supports editing, deleting, and restoring
 * factory presets.
 */
@Composable
internal fun PresetManagerDialog(
    presets: List<ModelPreset>,
    activePresetId: String?,
    onDismiss: () -> Unit,
    onEdit: (ModelPreset) -> Unit,
    onDelete: (ModelPreset) -> Unit,
    onAdd: () -> Unit,
    onReset: () -> Unit
) {
    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("管理服务商预设")) },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                presets.forEachIndexed { index, preset ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = preset.name,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = if (preset.id == activePresetId) FontWeight.Bold else FontWeight.Normal
                                )
                                if (preset.builtin) {
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text(
                                        text = localizedText("内置"),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                            Text(
                                text = preset.model,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        IconButton(onClick = { onEdit(preset) }) {
                            Icon(Icons.Filled.Edit, contentDescription = "编辑")
                        }
                        if (!preset.builtin) {
                            IconButton(onClick = { onDelete(preset) }) {
                                Icon(
                                    Icons.Filled.Delete,
                                    contentDescription = "删除",
                                    tint = MaterialTheme.colorScheme.error
                                )
                            }
                        }
                    }
                    if (index < presets.size - 1) {
                        HorizontalDivider()
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onAdd) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(4.dp))
                Text(localizedText("新增"))
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = onReset) {
                    Text(localizedText("恢复出厂"))
                }
                TextButton(onClick = onDismiss) {
                    Text(localizedText("关闭"))
                }
            }
        }
    )
}

/**
 * Preset edit dialog. Built-in presets can also be "saved as" a custom
 * one (saving automatically converts them into a custom preset).
 */
@Composable
internal fun PresetEditDialog(
    initial: ModelPreset?,
    onDismiss: () -> Unit,
    onSave: (ModelPreset) -> Unit
) {
    // When editing a built-in preset, save as a new custom preset instead of overwriting the factory template
    val isBuiltin = initial?.builtin == true
    var name by remember { mutableStateOf(initial?.name.orEmpty()) }
    var baseUrl by remember { mutableStateOf(initial?.baseUrl.orEmpty()) }
    var model by remember { mutableStateOf(initial?.model.orEmpty()) }
    var description by remember { mutableStateOf(initial?.description.orEmpty()) }

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                localizedText(
                    when {
                        isBuiltin -> "另存为新预设"
                        initial != null -> "编辑预设"
                        else -> "新增服务商预设"
                    }
                )
            )
        },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(localizedText("预设名称")) },
                    placeholder = { Text("例如：公司私有网关") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                Spacer(modifier = Modifier.height(10.dp))
                OutlinedTextField(
                    value = baseUrl,
                    onValueChange = { baseUrl = AgentApiTextParser.sanitizeInput(it) },
                    label = { Text(localizedText("服务地址 (Base URL)")) },
                    placeholder = { Text("https://api.example.com/v1") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = false,
                    maxLines = 3,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done)
                )
                Spacer(modifier = Modifier.height(10.dp))
                OutlinedTextField(
                    value = model,
                    onValueChange = { model = AgentApiTextParser.sanitizeInput(it) },
                    label = { Text(localizedText("模型名称 (Model)")) },
                    placeholder = { Text(AgentApiConfig.DEFAULT_MODEL) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = false,
                    maxLines = 2,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii, imeAction = ImeAction.Done)
                )
                Spacer(modifier = Modifier.height(10.dp))
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text(localizedText("备注 (可选)")) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                if (isBuiltin) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = localizedText("这是内置预设，保存后将生成一条新的自定义预设，不会修改出厂模板。"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(
                        ModelPreset(
                            // When "save as" is used on a built-in item, clear the id so the storage layer generates a new custom id
                            id = if (isBuiltin) "" else initial?.id.orEmpty(),
                            name = name,
                            baseUrl = baseUrl,
                            model = model,
                            description = description
                        )
                    )
                },
                enabled = baseUrl.isNotBlank() && model.isNotBlank()
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

/**
 * Server-side model list picker.
 */
@Composable
internal fun ServerModelPickerDialog(
    models: List<String>,
    currentModel: String,
    onDismiss: () -> Unit,
    onPick: (String) -> Unit
) {
    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("选择模型（共 ${models.size} 个）")) },
        // Contains a LazyColumn: the outer scroll container must be disabled, otherwise infinite height constraints crash the layout
        scrollable = false,
        text = {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 380.dp)
            ) {
                items(models.size) { index ->
                    val model = models[index]
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = model == currentModel,
                            onClick = { onPick(model) }
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = model,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}
