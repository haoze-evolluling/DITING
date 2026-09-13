package com.haoze.dnssr.ui

import android.content.ClipboardManager
import com.haoze.dnssr.ui.settings.AgentApiClient
import android.content.Context
import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.*
import com.haoze.dnssr.ui.settings.AgentApiConfig
import com.haoze.dnssr.ui.settings.AgentApiPresetStore
import com.haoze.dnssr.ui.settings.ModelPreset
import kotlinx.coroutines.launch
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentApiSettingsScreen(onBack: () -> Unit, title: String = "智能体 API") {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    var config by remember { mutableStateOf(AppSettings.getAgentApiConfig(context)) }
    var presets by remember { mutableStateOf(AgentApiPresetStore.getOrderedPresets(context)) }
    var apiKeyVisible by remember { mutableStateOf(false) }

    var isTesting by remember { mutableStateOf(false) }
    var testResultText by remember { mutableStateOf<String?>(null) }
    var testResultSuccess by remember { mutableStateOf<Boolean?>(null) }

    var isFetchingModels by remember { mutableStateOf(false) }
    var fetchedModels by remember { mutableStateOf<List<String>>(emptyList()) }
    var showModelPicker by remember { mutableStateOf(false) }
    var modelFetchError by remember { mutableStateOf<String?>(null) }

    var showPresetManager by remember { mutableStateOf(false) }
    var editingPreset by remember { mutableStateOf<ModelPreset?>(null) }
    var isCreatingPreset by remember { mutableStateOf(false) }

    fun updateConfig(newConfig: AgentApiConfig) {
        config = newConfig
        AppSettings.setAgentApiConfig(context, newConfig)
    }

    fun reloadPresets() {
        presets = AgentApiPresetStore.getOrderedPresets(context)
    }

    /** Which preset the current config matches (matched on both baseUrl and model) */
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
            // 1. Basic switch
            item { SettingsGroupTitle(localizedText("功能授权")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("允许插件调用智能体 API"),
                            subtitle = localizedText("开启后，获得授权的外挂插件可直接复用软件配置的 API 密钥发起大模型分析与查询"),
                            checked = config.enabled,
                            onCheckedChange = { enabled ->
                                updateConfig(config.copy(enabled = enabled))
                            }
                        )
                    }
                )
            }

            // 2. Provider presets
            item { SettingsGroupTitle(localizedText("服务提供方预设")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 12.dp)
                            ) {
                                Text(
                                    text = localizedText("快速切换服务商"),
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                    fontWeight = FontWeight.Bold
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    presets.forEach { preset ->
                                        FilterChip(
                                            selected = preset.id == activePresetId,
                                            onClick = {
                                                updateConfig(
                                                    config.copy(
                                                        baseUrl = preset.baseUrl,
                                                        model = preset.model
                                                    )
                                                )
                                                Toast.makeText(
                                                    context,
                                                    "已切换至 ${preset.name}",
                                                    Toast.LENGTH_SHORT
                                                ).show()
                                            },
                                            label = { Text(preset.name) }
                                        )
                                    }
                                }
                                Spacer(modifier = Modifier.height(6.dp))
                                Text(
                                    text = localizedText("预设模板随官方模型下线节奏维护，点击右侧“管理预设”可增删改，或添加自己的私有网关。"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        },
                        {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 4.dp),
                                horizontalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                OutlinedButton(
                                    onClick = { showPresetManager = true },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Filled.Edit, contentDescription = null)
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text(localizedText("管理预设"))
                                }
                                OutlinedButton(
                                    onClick = { isCreatingPreset = true },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Filled.Add, contentDescription = null)
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text(localizedText("新增预设"))
                                }
                            }
                        }
                    )
                )
            }

            // 3. API service and credentials
            item { SettingsGroupTitle(localizedText("服务提供方配置")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp)
                            ) {
                                OutlinedTextField(
                                    value = config.apiKey,
                                    onValueChange = { input ->
                                        // Smart-compat: accept pasted content that bundles the URL and key together
                                        if (input.contains("http://") || input.contains("https://")) {
                                            val urlRegex = Regex("""https?://[^\s,;"'\(\)]+""")
                                            val urlMatch = urlRegex.find(input)
                                            if (urlMatch != null) {
                                                val extractedUrl = urlMatch.value.trimEnd('/')
                                                val remaining = input.replace(urlMatch.value, "")
                                                    .removePrefix("Bearer ")
                                                    .replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "")
                                                    .trim(',', ';', ':', ' ')
                                                if (remaining.isNotBlank()) {
                                                    updateConfig(config.copy(baseUrl = extractedUrl, apiKey = remaining))
                                                    Toast.makeText(context, "已自动识别并填入 Base URL 和 API Key", Toast.LENGTH_SHORT).show()
                                                    return@OutlinedTextField
                                                }
                                            }
                                        }
                                        val sanitized = input
                                            .removePrefix("Bearer ")
                                            .replace("\r", "")
                                            .replace("\n", "")
                                            .replace("\t", "")
                                            .replace(" ", "")
                                            .trim()
                                        updateConfig(config.copy(apiKey = sanitized))
                                    },
                                    label = { Text(localizedText("API Key (密钥)")) },
                                    placeholder = { Text("sk-...") },
                                    modifier = Modifier.fillMaxWidth(),
                                    singleLine = false,
                                    maxLines = 4,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii, imeAction = ImeAction.Done),
                                    visualTransformation = if (apiKeyVisible) VisualTransformation.None else PasswordVisualTransformation(),
                                    trailingIcon = {
                                        Row {
                                            IconButton(onClick = {
                                                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                                val clip = cm.primaryClip
                                                if (clip != null && clip.itemCount > 0) {
                                                    val pasteText = clip.getItemAt(0).text?.toString().orEmpty()
                                                    if (pasteText.isNotBlank()) {
                                                        val tip = parseAndApplyApiText(pasteText, config, ::updateConfig)
                                                        Toast.makeText(context, tip, Toast.LENGTH_SHORT).show()
                                                    } else {
                                                        Toast.makeText(context, "剪贴板为空", Toast.LENGTH_SHORT).show()
                                                    }
                                                } else {
                                                    Toast.makeText(context, "剪贴板为空", Toast.LENGTH_SHORT).show()
                                                }
                                            }) {
                                                Icon(Icons.Filled.ContentPaste, contentDescription = "粘贴")
                                            }
                                            if (config.apiKey.isNotEmpty()) {
                                                IconButton(onClick = { updateConfig(config.copy(apiKey = "")) }) {
                                                    Icon(Icons.Filled.Clear, contentDescription = "清空")
                                                }
                                            }
                                            IconButton(onClick = { apiKeyVisible = !apiKeyVisible }) {
                                                Icon(
                                                    if (apiKeyVisible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                                                    contentDescription = if (apiKeyVisible) "隐藏" else "显示"
                                                )
                                            }
                                        }
                                    }
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    text = localizedText("凭据保存在本地私有安全存储中，不会上传到任何第三方服务器。"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        },
                        {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp)
                            ) {
                                OutlinedTextField(
                                    value = config.baseUrl,
                                    onValueChange = { input ->
                                        val cleaned = input.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim()
                                        updateConfig(config.copy(baseUrl = cleaned))
                                    },
                                    label = { Text(localizedText("服务地址 (Base URL)")) },
                                    placeholder = { Text("https://api.deepseek.com/v1") },
                                    modifier = Modifier.fillMaxWidth(),
                                    singleLine = false,
                                    maxLines = 3,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                                    trailingIcon = {
                                        Row {
                                            if (config.baseUrl.isNotEmpty()) {
                                                IconButton(onClick = { updateConfig(config.copy(baseUrl = "")) }) {
                                                    Icon(Icons.Filled.Clear, contentDescription = "清空")
                                                }
                                            }
                                            IconButton(onClick = {
                                                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                                val clip = cm.primaryClip
                                                if (clip != null && clip.itemCount > 0) {
                                                    val pasteText = clip.getItemAt(0).text?.toString().orEmpty()
                                                    val cleaned = pasteText.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim()
                                                    if (cleaned.isNotBlank()) {
                                                        updateConfig(config.copy(baseUrl = cleaned))
                                                        Toast.makeText(context, "已从剪贴板粘贴服务地址", Toast.LENGTH_SHORT).show()
                                                    }
                                                }
                                            }) {
                                                Icon(Icons.Filled.ContentPaste, contentDescription = "粘贴")
                                            }
                                        }
                                    }
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    text = localizedText("兼容 OpenAI 协议规范，端点支持自动适配补全 /chat/completions。"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        },
                        {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp)
                            ) {
                                OutlinedTextField(
                                    value = config.model,
                                    onValueChange = { input ->
                                        val cleaned = input.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim()
                                        updateConfig(config.copy(model = cleaned))
                                    },
                                    label = { Text(localizedText("模型名称 (Model)")) },
                                    placeholder = { Text(AgentApiConfig.DEFAULT_MODEL) },
                                    modifier = Modifier.fillMaxWidth(),
                                    singleLine = false,
                                    maxLines = 2,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii, imeAction = ImeAction.Done)
                                )
                                Spacer(modifier = Modifier.height(6.dp))
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .horizontalScroll(rememberScrollState()),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    AgentApiPresetStore.MODEL_SUGGESTIONS.forEach { m ->
                                        SuggestionChip(
                                            onClick = { updateConfig(config.copy(model = m)) },
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
                                    .padding(horizontal = 16.dp, vertical = 8.dp)
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
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(16.dp),
                                            strokeWidth = 2.dp
                                        )
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text(localizedText("正在拉取模型列表..."))
                                    } else {
                                        Icon(Icons.Filled.CloudDownload, contentDescription = null)
                                        Spacer(modifier = Modifier.width(6.dp))
                                        Text(localizedText("从服务端拉取可用模型"))
                                    }
                                }
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    text = modelFetchError
                                        ?: localizedText("通过 OpenAI 兼容的 /models 端点获取该服务商当前真实提供的模型，避免手写模型名过期。"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = if (modelFetchError != null) {
                                        MaterialTheme.colorScheme.error
                                    } else {
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    }
                                )
                            }
                        }
                    )
                )
            }

            // 4. Advanced role/persona settings
            item { SettingsGroupTitle(localizedText("高级角色提示词 (可选)")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp)
                        ) {
                            OutlinedTextField(
                                value = config.systemPrompt,
                                onValueChange = { updateConfig(config.copy(systemPrompt = it)) },
                                label = { Text(localizedText("全局 System Prompt")) },
                                placeholder = { Text("例如：你是一名网络安全与 DNS 威胁情报专家...") },
                                modifier = Modifier.fillMaxWidth(),
                                minLines = 2,
                                maxLines = 5
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = localizedText("当插件未指定系统提示词时，将自动注入此全局设定。"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
            }

            // 5. Connectivity test and actions
            item { SettingsGroupTitle(localizedText("配置验证")) }
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Button(
                        onClick = {
                            if (config.apiKey.isBlank()) {
                                Toast.makeText(context, "请先输入 API Key", Toast.LENGTH_SHORT).show()
                                return@Button
                            }
                            isTesting = true
                            testResultText = null
                            testResultSuccess = null
                            coroutineScope.launch {
                                val startTime = System.currentTimeMillis()
                                val res = AgentApiClient.testConnection(config)
                                val elapsed = System.currentTimeMillis() - startTime
                                isTesting = false
                                res.onSuccess { chatResult ->
                                    testResultSuccess = true
                                    testResultText = "【连接正常】耗时 ${elapsed}ms | 模型: ${chatResult.model}\n" +
                                            "响应: ${chatResult.content.trim()}\n" +
                                            "消耗 Token: ${chatResult.totalTokens}"
                                }.onFailure { error ->
                                    testResultSuccess = false
                                    testResultText = "【连接失败】${error.message}"
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isTesting
                    ) {
                        if (isTesting) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(localizedText("正在连线验证..."))
                        } else {
                            Icon(Icons.Filled.PlayArrow, contentDescription = null)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(localizedText("测试 API 连通性"))
                        }
                    }

                    AnimatedVisibility(visible = testResultText != null) {
                        val isSuccess = testResultSuccess == true
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(
                                containerColor = if (isSuccess) {
                                    MaterialTheme.colorScheme.primaryContainer
                                } else {
                                    MaterialTheme.colorScheme.errorContainer
                                }
                            ),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(14.dp),
                                verticalAlignment = Alignment.Top
                            ) {
                                Icon(
                                    imageVector = if (isSuccess) Icons.Filled.CheckCircle else Icons.Filled.Error,
                                    contentDescription = null,
                                    tint = if (isSuccess) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                                    modifier = Modifier.size(24.dp)
                                )
                                Spacer(modifier = Modifier.width(10.dp))
                                Text(
                                    text = testResultText.orEmpty(),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = if (isSuccess) {
                                        MaterialTheme.colorScheme.onPrimaryContainer
                                    } else {
                                        MaterialTheme.colorScheme.onErrorContainer
                                    }
                                )
                            }
                        }
                    }

                    OutlinedButton(
                        onClick = {
                            val defaultConfig = AgentApiConfig()
                            updateConfig(defaultConfig)
                            testResultText = null
                            testResultSuccess = null
                            modelFetchError = null
                            Toast.makeText(context, "已恢复默认配置", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(localizedText("恢复默认配置"))
                    }
                }
            }

            item {
                SettingsInfoText(
                    localizedText("提示：配置此智能体服务后，所有申请了 AI_AGENT 权限的外挂插件均可通过 ai.chat(...) 或 ai.analyzeDnsLogs(...) 无缝调用大模型进行域名安全评估与实时 DNS 日志深度审查。")
                )
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

    if (showPresetManager) {
        PresetManagerDialog(
            presets = presets,
            activePresetId = activePresetId,
            onDismiss = { showPresetManager = false },
            onEdit = { preset ->
                showPresetManager = false
                isCreatingPreset = false
                editingPreset = preset
            },
            onDelete = { preset ->
                presets = AgentApiPresetStore.deleteCustomPreset(context, preset.id)
                Toast.makeText(context, "已删除预设 ${preset.name}", Toast.LENGTH_SHORT).show()
            },
            onAdd = {
                showPresetManager = false
                editingPreset = null
                isCreatingPreset = true
            },
            onReset = {
                AgentApiPresetStore.resetToDefault(context)
                reloadPresets()
                Toast.makeText(context, "已恢复出厂预设", Toast.LENGTH_SHORT).show()
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
            onSave = { preset ->
                AgentApiPresetStore.upsertCustomPreset(context, preset)
                reloadPresets()
                isCreatingPreset = false
                editingPreset = null
                Toast.makeText(context, "预设已保存", Toast.LENGTH_SHORT).show()
            }
        )
    }
}

/**
 * Smart-parses API text from the clipboard or user input:
 * 1. Strips carriage returns (\r), line feeds (\n), tabs (\t), and leading/
 *    trailing whitespace, fixing single-line input fields / soft keyboards
 *    truncating multi-line pastes and losing the tail;
 * 2. Removes the common "Bearer " prefix;
 * 3. Smart-compat with JSON configs, composite strings containing both Base
 *    URL and key (e.g. url,key or multi-line text), or a standalone API key.
 */
private fun parseAndApplyApiText(
    rawText: String,
    currentConfig: AgentApiConfig,
    onUpdate: (AgentApiConfig) -> Unit
): String {
    val text = rawText.trim()
    if (text.isBlank()) return "剪贴板为空"

    // 1. Try parsing as JSON
    if (text.startsWith("{") && text.endsWith("}")) {
        val parsedJson = runCatching {
            val json = JSONObject(text)
            var newConfig = currentConfig
            var updatedCount = 0
            val key = json.optString("apiKey").ifBlank { json.optString("api_key") }.ifBlank { json.optString("key") }
            val url = json.optString("baseUrl").ifBlank { json.optString("base_url") }.ifBlank { json.optString("url") }
            val model = json.optString("model")

            if (key.isNotBlank()) {
                newConfig = newConfig.copy(apiKey = key.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim())
                updatedCount++
            }
            if (url.isNotBlank()) {
                newConfig = newConfig.copy(baseUrl = url.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim())
                updatedCount++
            }
            if (model.isNotBlank()) {
                newConfig = newConfig.copy(model = model.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim())
                updatedCount++
            }
            if (updatedCount > 0) {
                onUpdate(newConfig)
                "已从 JSON 中识别并更新 API 配置"
            } else null
        }.getOrNull()
        if (parsedJson != null) return parsedJson
    }

    // 2. Match composite content containing both a Base URL and an API key (multi-line text, comma- or @-separated, etc.)
    val urlRegex = Regex("""https?://[^\s,;"'\(\)]+""")
    val keyRegex = Regex("""(?:sk-[a-zA-Z0-9_\-]{16,}|(?:Bearer\s+)?([a-zA-Z0-9_\-]{32,}))""")

    val foundUrl = urlRegex.find(text)?.value?.trimEnd('/')
    val textWithoutUrl = if (foundUrl != null) text.replace(foundUrl, "") else text
    val foundKeyMatch = keyRegex.find(textWithoutUrl)
    val foundKey = foundKeyMatch?.value?.removePrefix("Bearer ")?.trim()

    if (foundUrl != null && !foundKey.isNullOrBlank()) {
        val sanitizedKey = foundKey.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim()
        val sanitizedUrl = foundUrl.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim()
        onUpdate(currentConfig.copy(baseUrl = sanitizedUrl, apiKey = sanitizedKey))
        return "已自动识别并填入服务地址与 API Key"
    }

    // 3. Only a server address was matched
    if (foundUrl != null && text.lines().size <= 2 && !text.contains("sk-")) {
        val sanitizedUrl = foundUrl.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim()
        onUpdate(currentConfig.copy(baseUrl = sanitizedUrl))
        return "已填入服务地址"
    }

    // 4. Default to treating it as an API key: strip all newlines, carriage returns, tabs, and inner spaces to assemble the full long key
    val cleanedKey = text
        .removePrefix("Bearer ")
        .replace("\r", "")
        .replace("\n", "")
        .replace("\t", "")
        .replace(" ", "")
        .trim()
    onUpdate(currentConfig.copy(apiKey = cleanedKey))
    return "已填入 API Key"
}

/**
     * Preset management panel: supports editing, deleting, and restoring
     * factory presets.
     */
@Composable
private fun PresetManagerDialog(
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
private fun PresetEditDialog(
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
                    onValueChange = { baseUrl = it.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim() },
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
                    onValueChange = { model = it.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").trim() },
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
private fun ServerModelPickerDialog(
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
