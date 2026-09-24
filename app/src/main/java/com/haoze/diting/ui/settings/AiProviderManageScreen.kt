package com.haoze.diting.ui.settings

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.localizedText
import kotlinx.coroutines.launch

/**
 * AI 厂商管理：上半部分为用户已配置的「我的厂商」，下半部分为内置预设厂商目录。
 * 预设仅预填接口地址，可用模型在编辑框里填入 API Key 现场拉取后以 Chips 形式点选。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AiProviderManageScreen(
    onBack: () -> Unit,
    title: String = "AI 厂商管理"
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var providers by remember { mutableStateOf(AgentApiSettingsStore.getProviders(context)) }
    var activeProviderId by remember { mutableStateOf(AgentApiSettingsStore.getActiveProviderId(context)) }
    val presets = remember { AiProviderPresets.all }

    var draft by remember { mutableStateOf<ProviderDraft?>(null) }
    var pendingDelete by remember { mutableStateOf<AiProvider?>(null) }
    var fetchedModelIds by remember { mutableStateOf<List<String>>(emptyList()) }
    var fetchingModels by remember { mutableStateOf(false) }

    fun reload() {
        providers = AgentApiSettingsStore.getProviders(context)
        activeProviderId = AgentApiSettingsStore.getActiveProviderId(context)
    }

    val presetsByGroup = remember { presets.groupBy { it.group }.toList() }
    val addedPresetIds = remember(providers) { providers.mapTo(mutableSetOf()) { it.presetId } }

    val openDraft: (ProviderDraft) -> Unit = { target ->
        fetchedModelIds = emptyList()
        draft = target
    }

    SettingsScaffold(
        title = localizedText(title),
        onBack = onBack,
        actions = {
            IconButton(onClick = { openDraft(ProviderDraft()) }) {
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = localizedText("添加自定义厂商"),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(0.dp)
        ) {
            item {
                SettingsInfoText(
                    localizedText("点选下方预设厂商会自动预填接口地址；模型不预置硬编码，填好 API Key 后点击「拉取模型列表」即可在线点选。编辑时若 API Key 留空则保留原密钥。")
                )
            }

            // 1. 我的厂商
            item { SettingsGroupTitle(localizedText("我的厂商")) }
            item {
                if (providers.isEmpty()) {
                    SettingsSurfaceGroup(
                        content = listOf {
                            SettingsItem(
                                title = localizedText("暂无厂商"),
                                subtitle = localizedText("从下方预设厂商目录点选，或点击右上角添加自定义厂商"),
                                enabled = false
                            )
                        }
                    )
                } else {
                    SettingsSurfaceGroup(
                        content = providers.map { provider ->
                            {
                                ProviderRow(
                                    provider = provider,
                                    isActive = provider.id == activeProviderId,
                                    onSelect = {
                                        AgentApiSettingsStore.setActiveProviderId(context, provider.id)
                                        activeProviderId = provider.id
                                        Toast.makeText(
                                            context,
                                            "已切换为：${provider.name}",
                                            Toast.LENGTH_SHORT
                                        ).show()
                                    },
                                    onEdit = {
                                        openDraft(
                                            ProviderDraft(
                                                existing = provider,
                                                preset = presets.find { it.id == provider.presetId }
                                            )
                                        )
                                    }
                                )
                            }
                        }
                    )
                }
            }

            // 2. 预设厂商目录分组
            presetsByGroup.forEach { (group, entries) ->
                item { SettingsGroupTitle(localizedText(group)) }
                item {
                    SettingsSurfaceGroup(
                        content = entries.map { preset ->
                            {
                                PresetRow(
                                    preset = preset,
                                    isAdded = preset.id in addedPresetIds,
                                    onAdd = { openDraft(ProviderDraft(preset = preset)) }
                                )
                            }
                        }
                    )
                }
            }

            item { Spacer(modifier = Modifier.height(24.dp)) }
        }
    }

    pendingDelete?.let { provider ->
        AppConfirmDialog(
            onDismissRequest = { pendingDelete = null },
            title = localizedText("删除厂商"),
            message = "确定要删除“${provider.name}”吗？相关 API Key 也会从本机移除。",
            confirmLabel = localizedText("删除"),
            destructive = true,
            onConfirm = {
                val list = providers.filterNot { it.id == provider.id }
                AgentApiSettingsStore.saveProviders(context, list)
                if (activeProviderId == provider.id) {
                    val nextActive = list.firstOrNull()?.id.orEmpty()
                    AgentApiSettingsStore.setActiveProviderId(context, nextActive)
                }
                reload()
                pendingDelete = null
                Toast.makeText(context, "已删除厂商", Toast.LENGTH_SHORT).show()
            }
        )
    }

    draft?.let { currentDraft ->
        ProviderEditorDialog(
            draft = currentDraft,
            initialApiKey = currentDraft.existing?.let { AgentApiSettingsStore.revealApiKey(it) }.orEmpty(),
            fetchedModelIds = fetchedModelIds,
            fetchingModels = fetchingModels,
            onFetchModels = { baseUrl, plainKey ->
                if (plainKey.isBlank()) {
                    Toast.makeText(context, "请先填写 API Key", Toast.LENGTH_SHORT).show()
                    return@ProviderEditorDialog
                }
                fetchingModels = true
                scope.launch {
                    try {
                        val ids = AiModelFetcher.fetchModelIds(baseUrl, plainKey.trim())
                        fetchedModelIds = ids
                        fetchingModels = false
                        Toast.makeText(context, "已获取 ${ids.size} 个可用模型", Toast.LENGTH_SHORT).show()
                    } catch (e: Exception) {
                        fetchingModels = false
                        Toast.makeText(context, e.message ?: "拉取模型列表失败", Toast.LENGTH_LONG).show()
                    }
                }
            },
            onDismiss = { draft = null },
            onDelete = if (currentDraft.existing != null) {
                {
                    val toDelete = currentDraft.existing
                    draft = null
                    pendingDelete = toDelete
                }
            } else null,
            onSave = { name, baseUrl, modelName, plainKey ->
                val existing = currentDraft.existing
                val presetId = existing?.presetId ?: currentDraft.preset?.id ?: ""
                val currentList = providers.toMutableList()

                if (existing == null) {
                    val newId = "provider_${System.currentTimeMillis()}"
                    val newProvider = AiProvider(
                        id = newId,
                        name = name,
                        baseUrl = baseUrl,
                        apiKey = if (plainKey.isBlank()) "" else AgentApiSettingsStore.sealApiKey(plainKey),
                        modelName = modelName,
                        presetId = presetId
                    )
                    currentList.add(newProvider)
                    AgentApiSettingsStore.saveProviders(context, currentList)
                    AgentApiSettingsStore.setActiveProviderId(context, newId)
                } else {
                    val updatedKey = if (plainKey.isBlank()) {
                        existing.apiKey
                    } else {
                        AgentApiSettingsStore.sealApiKey(plainKey)
                    }
                    val updatedProvider = existing.copy(
                        name = name,
                        baseUrl = baseUrl,
                        apiKey = updatedKey,
                        modelName = modelName,
                        presetId = presetId
                    )
                    val index = currentList.indexOfFirst { it.id == existing.id }
                    if (index >= 0) {
                        currentList[index] = updatedProvider
                    }
                    AgentApiSettingsStore.saveProviders(context, currentList)
                    AgentApiSettingsStore.setActiveProviderId(context, existing.id)
                }
                reload()
                draft = null
                Toast.makeText(context, "厂商已保存", Toast.LENGTH_SHORT).show()
            }
        )
    }
}

private data class ProviderDraft(
    val existing: AiProvider? = null,
    val preset: AiProviderPreset? = null
) {
    val initialName: String get() = existing?.name ?: preset?.name ?: ""
    val initialBaseUrl: String get() = existing?.baseUrl ?: preset?.baseUrl ?: ""
    val initialModelName: String get() = existing?.modelName ?: ""
}

@Composable
private fun ProviderRow(
    provider: AiProvider,
    isActive: Boolean,
    onSelect: () -> Unit,
    onEdit: () -> Unit
) {
    SettingsItem(
        title = provider.name.ifBlank { "未命名厂商" },
        subtitle = buildString {
            append(provider.baseUrl.ifBlank { "未设置基础地址" })
            append("\n")
            append(provider.modelName.ifBlank { "未选择模型" })
        },
        leadingIcon = Icons.Filled.Psychology,
        onClick = onSelect,
        trailing = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isActive) {
                    Icon(
                        imageVector = Icons.Filled.Check,
                        contentDescription = "当前厂商",
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(Modifier.width(4.dp))
                }
                IconButton(onClick = onEdit) {
                    Icon(
                        imageVector = Icons.Filled.Edit,
                        contentDescription = "编辑",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    )
}


@Composable
private fun PresetRow(
    preset: AiProviderPreset,
    isAdded: Boolean,
    onAdd: () -> Unit
) {
    SettingsItem(
        title = preset.name,
        subtitle = (if (isAdded) "已添加 · " else "") + preset.baseUrl,
        leadingIcon = Icons.Filled.Apps,
        onClick = onAdd,
        trailing = {
            IconButton(onClick = onAdd) {
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = "添加 ${preset.name}",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProviderEditorDialog(
    draft: ProviderDraft,
    initialApiKey: String,
    fetchedModelIds: List<String>,
    fetchingModels: Boolean,
    onFetchModels: (baseUrl: String, plainKey: String) -> Unit,
    onDismiss: () -> Unit,
    onDelete: (() -> Unit)? = null,
    onSave: (name: String, baseUrl: String, modelName: String, plainKey: String) -> Unit
) {
    var name by remember(draft) { mutableStateOf(draft.initialName) }
    var baseUrl by remember(draft) { mutableStateOf(draft.initialBaseUrl) }
    var modelName by remember(draft) { mutableStateOf(draft.initialModelName) }
    var apiKey by remember(draft) { mutableStateOf(initialApiKey) }
    var showKey by remember(draft) { mutableStateOf(false) }

    val modelChoices = remember(fetchedModelIds, draft) {
        (listOf(draft.initialModelName).filter { it.isNotBlank() } + fetchedModelIds).distinct()
    }

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                when {
                    draft.existing != null -> "编辑厂商"
                    draft.preset != null -> "添加 ${draft.preset.name}"
                    else -> "添加自定义厂商"
                }
            )
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("厂商名称") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = baseUrl,
                    onValueChange = { baseUrl = it },
                    label = { Text("基础地址 Base URL") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("https://api.example.com/v1") }
                )
                if (modelChoices.isNotEmpty()) {
                    Text(
                        text = "可用模型（点击快捷选择）：",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        modelChoices.forEach { id ->
                            FilterChip(
                                selected = id == modelName,
                                onClick = { modelName = id },
                                label = { Text(id, style = MaterialTheme.typography.labelSmall) },
                                shape = RoundedCornerShape(8.dp)
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = modelName,
                    onValueChange = { modelName = it },
                    label = { Text("模型名称") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = {
                        Text(if (modelChoices.isEmpty()) "填好 Key 后点下方拉取，或手动填写" else "接口要求的 model 取值")
                    }
                )
                OutlinedTextField(
                    value = apiKey,
                    onValueChange = { apiKey = it },
                    label = { Text("API Key") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = if (showKey) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Password,
                        imeAction = ImeAction.Done
                    ),
                    trailingIcon = {
                        IconButton(onClick = { showKey = !showKey }) {
                            Icon(
                                imageVector = if (showKey) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                                contentDescription = if (showKey) "隐藏" else "显示"
                            )
                        }
                    }
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    AppDialogButton(
                        label = if (fetchingModels) "拉取中…" else "拉取模型列表",
                        onClick = { onFetchModels(baseUrl, apiKey) },
                        enabled = !fetchingModels && baseUrl.isNotBlank()
                    )
                    if (fetchingModels) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    }
                }
            }
        },
        confirmButton = {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (draft.existing != null && onDelete != null) {
                    AppDialogButton(
                        label = "删除",
                        onClick = onDelete,
                        destructive = true
                    )
                } else {
                    Spacer(modifier = Modifier.width(1.dp))
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    AppDialogButton(label = "取消", onClick = onDismiss)
                    AppDialogButton(
                        label = "保存",
                        onClick = { onSave(name.trim(), baseUrl.trim(), modelName.trim(), apiKey.trim()) },
                        enabled = name.isNotBlank() && baseUrl.isNotBlank() && modelName.isNotBlank()
                    )
                }
            }
        },
        dismissButton = null
    )
}


