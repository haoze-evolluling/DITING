package com.haoze.diting.ui

import android.widget.Toast
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.settings.AgentApiClient
import com.haoze.diting.ui.settings.AgentApiConfig
import com.haoze.diting.ui.settings.AgentApiPresetStore
import com.haoze.diting.ui.settings.AgentApiSettingsStore
import com.haoze.diting.ui.settings.ModelPreset
import kotlinx.coroutines.launch

/**
 * Secondary settings page: Preset models and providers management.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentApiPresetsScreen(
    onBack: () -> Unit,
    title: String = "模型与预设中心"
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    var config by remember { mutableStateOf(AgentApiSettingsStore.getAgentApiConfig(context)) }
    var presets by remember { mutableStateOf(AgentApiPresetStore.getOrderedPresets(context)) }

    var isFetchingModels by remember { mutableStateOf(false) }
    var fetchedModels by remember { mutableStateOf<List<String>>(emptyList()) }
    var showModelPicker by remember { mutableStateOf(false) }
    var modelFetchError by remember { mutableStateOf<String?>(null) }

    var editingPreset by remember { mutableStateOf<ModelPreset?>(null) }
    var isCreatingPreset by remember { mutableStateOf(false) }

    fun updateConfig(newConfig: AgentApiConfig) {
        config = newConfig
        AgentApiSettingsStore.setAgentApiConfig(context, newConfig)
    }

    fun reloadPresets() {
        presets = AgentApiPresetStore.getOrderedPresets(context)
    }

    val activePresetId = presets.firstOrNull {
        it.baseUrl.equals(config.baseUrl, ignoreCase = true) &&
                it.model.equals(config.model, ignoreCase = true)
    }?.id

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // 1. Current Model Card & Fetch Online
            item { SettingsGroupTitle(localizedText("当前激活模型")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 12.dp)
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        imageVector = Icons.Filled.SmartToy,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(20.dp)
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = localizedText("当前模型标识 (Model)"),
                                        style = MaterialTheme.typography.labelLarge,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                                Spacer(modifier = Modifier.height(8.dp))
                                OutlinedTextField(
                                    value = config.model,
                                    onValueChange = { input ->
                                        val cleaned = AgentApiTextParser.sanitizeInput(input)
                                        updateConfig(config.copy(model = cleaned))
                                    },
                                    label = { Text(localizedText("模型名称 (Model)")) },
                                    placeholder = { Text(AgentApiConfig.DEFAULT_MODEL) },
                                    modifier = Modifier.fillMaxWidth(),
                                    singleLine = false,
                                    maxLines = 2
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    text = localizedText("主流厂商推荐模型："),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    AgentApiPresetStore.MODEL_SUGGESTIONS.forEach { m ->
                                        SuggestionChip(
                                            onClick = {
                                                updateConfig(config.copy(model = m))
                                                Toast.makeText(context, "已切换模型为 $m", Toast.LENGTH_SHORT).show()
                                            },
                                            label = { Text(m, style = MaterialTheme.typography.labelSmall) }
                                        )
                                    }
                                }
                            }
                        },
                        {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 10.dp)
                            ) {
                                OutlinedButton(
                                    onClick = {
                                        if (config.apiKey.isBlank()) {
                                            Toast.makeText(context, "请先输入 API Key", Toast.LENGTH_SHORT).show()
                                            return@OutlinedButton
                                        }
                                        isFetchingModels = true
                                        modelFetchError = null
                                        coroutineScope.launch {
                                            val result = AgentApiClient.fetchModels(config)
                                            isFetchingModels = false
                                            result.onSuccess { models ->
                                                if (models.isEmpty()) {
                                                    modelFetchError = "服务端返回的模型列表为空"
                                                } else {
                                                    fetchedModels = models
                                                    showModelPicker = true
                                                }
                                            }.onFailure { error ->
                                                modelFetchError = error.message ?: "拉取失败"
                                            }
                                        }
                                    },
                                    modifier = Modifier.fillMaxWidth(),
                                    enabled = !isFetchingModels
                                ) {
                                    if (isFetchingModels) {
                                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text(localizedText("正在从服务端拉取模型列表..."))
                                    } else {
                                        Icon(Icons.Filled.CloudDownload, contentDescription = null)
                                        Spacer(modifier = Modifier.width(6.dp))
                                        Text(localizedText("从服务商拉取可用模型列表"))
                                    }
                                }
                                if (modelFetchError != null) {
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        text = modelFetchError.orEmpty(),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                        }
                    )
                )
            }

            // 2. Preset Templates List
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = localizedText("预设模板列表"),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold
                    )
                    Row {
                        OutlinedButton(onClick = { isCreatingPreset = true }) {
                            Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(localizedText("新增预设"))
                        }
                    }
                }
            }

            items(presets, key = { it.id }) { preset ->
                val isActive = preset.id == activePresetId
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = if (isActive) {
                            MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerLow
                        }
                    )
                ) {
                    Column(modifier = Modifier.padding(14.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = preset.name,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Bold
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Surface(
                                    shape = RoundedCornerShape(4.dp),
                                    color = if (preset.builtin) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.tertiaryContainer
                                ) {
                                    Text(
                                        text = localizedText(if (preset.builtin) "官方精选" else "自定义"),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = if (preset.builtin) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onTertiaryContainer,
                                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                    )
                                }
                            }

                            if (isActive) {
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.primary
                                ) {
                                    Row(
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            Icons.Filled.Check,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onPrimary,
                                            modifier = Modifier.size(14.dp)
                                        )
                                        Spacer(modifier = Modifier.width(4.dp))
                                        Text(
                                            text = localizedText("当前使用"),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onPrimary
                                        )
                                    }
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(6.dp))
                        Text(
                            text = "模型: ${preset.model}",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text = "端点: ${preset.baseUrl}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (preset.description.isNotBlank()) {
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = preset.description,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }

                        Spacer(modifier = Modifier.height(10.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.End,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (!isActive) {
                                FilledTonalButton(
                                    onClick = {
                                        updateConfig(
                                            config.copy(
                                                baseUrl = preset.baseUrl,
                                                model = preset.model
                                            )
                                        )
                                        Toast.makeText(context, "已切换至 ${preset.name}", Toast.LENGTH_SHORT).show()
                                    }
                                ) {
                                    Text(localizedText("应用预设"))
                                }
                                Spacer(modifier = Modifier.width(8.dp))
                            }

                            OutlinedButton(onClick = { editingPreset = preset }) {
                                Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(14.dp))
                                Spacer(modifier = Modifier.width(4.dp))
                                Text(localizedText(if (preset.builtin) "另存为" else "编辑"))
                            }

                            if (!preset.builtin) {
                                Spacer(modifier = Modifier.width(8.dp))
                                IconButton(onClick = {
                                    presets = AgentApiPresetStore.deleteCustomPreset(context, preset.id)
                                    Toast.makeText(context, "已删除预设 ${preset.name}", Toast.LENGTH_SHORT).show()
                                }) {
                                    Icon(
                                        Icons.Filled.Delete,
                                        contentDescription = localizedText("删除"),
                                        tint = MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // 3. Reset Button
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    OutlinedButton(
                        onClick = {
                            AgentApiPresetStore.resetToDefault(context)
                            reloadPresets()
                            Toast.makeText(context, "已恢复出厂预设列表", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(localizedText("恢复出厂官方预设"))
                    }
                }
            }

            item { Spacer(modifier = Modifier.height(24.dp)) }
        }
    }

    if (showModelPicker) {
        ServerModelPickerDialog(
            models = fetchedModels,
            currentModel = config.model,
            onDismiss = { showModelPicker = false },
            onPick = { model ->
                updateConfig(config.copy(model = model))
                showModelPicker = false
                Toast.makeText(context, "已选择模型 $model", Toast.LENGTH_SHORT).show()
            }
        )
    }

    if (isCreatingPreset || editingPreset != null) {
        PresetEditDialog(
            initial = editingPreset,
            onDismiss = {
                isCreatingPreset = false
                editingPreset = null
            },
            onSave = { updatedPreset ->
                presets = AgentApiPresetStore.upsertCustomPreset(context, updatedPreset)
                isCreatingPreset = false
                editingPreset = null
                Toast.makeText(context, "预设已保存", Toast.LENGTH_SHORT).show()
            }
        )
    }
}
