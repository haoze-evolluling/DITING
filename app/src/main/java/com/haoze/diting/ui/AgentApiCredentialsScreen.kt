package com.haoze.diting.ui

import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SuggestionChip
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.settings.AgentApiClient
import com.haoze.diting.ui.settings.AgentApiConfig
import com.haoze.diting.ui.settings.AgentApiSettingsStore
import kotlinx.coroutines.launch

/**
 * Secondary settings page: Agent API Credentials and Endpoint configuration.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentApiCredentialsScreen(
    onBack: () -> Unit,
    title: String = "服务商与密钥"
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    var config by remember { mutableStateOf(AgentApiSettingsStore.getAgentApiConfig(context)) }
    var apiKeyVisible by remember { mutableStateOf(false) }

    var isTesting by remember { mutableStateOf(false) }
    var testResultText by remember { mutableStateOf<String?>(null) }
    var testResultSuccess by remember { mutableStateOf<Boolean?>(null) }

    fun updateConfig(newConfig: AgentApiConfig) {
        config = newConfig
        AgentApiSettingsStore.setAgentApiConfig(context, newConfig)
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // 1. API Key Card
            item { SettingsGroupTitle(localizedText("API 访问密钥")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Filled.Key,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(20.dp)
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = localizedText("API Key (凭据)"),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            OutlinedTextField(
                                value = config.apiKey,
                                onValueChange = { input ->
                                    val composite = AgentApiTextParser.parseCompositeUrlAndKey(input)
                                    if (composite != null) {
                                        val (extractedUrl, remaining) = composite
                                        updateConfig(config.copy(baseUrl = extractedUrl, apiKey = remaining))
                                        Toast.makeText(context, "已自动识别并填入 Base URL 和 API Key", Toast.LENGTH_SHORT).show()
                                        return@OutlinedTextField
                                    }
                                    val sanitized = AgentApiTextParser.sanitizeInput(input.removePrefix("Bearer "))
                                    updateConfig(config.copy(apiKey = sanitized))
                                },
                                label = { Text(localizedText("API Key")) },
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
                                                    val tip = AgentApiTextParser.parseAndApplyApiText(pasteText, config, ::updateConfig)
                                                    Toast.makeText(context, tip, Toast.LENGTH_SHORT).show()
                                                } else {
                                                    Toast.makeText(context, "剪贴板为空", Toast.LENGTH_SHORT).show()
                                                }
                                            } else {
                                                Toast.makeText(context, "剪贴板为空", Toast.LENGTH_SHORT).show()
                                            }
                                        }) {
                                            Icon(Icons.Filled.ContentPaste, contentDescription = localizedText("粘贴"))
                                        }
                                        if (config.apiKey.isNotEmpty()) {
                                            IconButton(onClick = { updateConfig(config.copy(apiKey = "")) }) {
                                                Icon(Icons.Filled.Clear, contentDescription = localizedText("清空"))
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
                            Spacer(modifier = Modifier.height(8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Filled.Security,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(14.dp)
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    text = localizedText("凭据保存在本地私有安全存储中，绝不上传到任何非目标中转服务器。"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                )
            }

            // 2. Base URL Card
            item { SettingsGroupTitle(localizedText("服务地址 (Base URL)")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Filled.Language,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(20.dp)
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = localizedText("服务地址"),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            OutlinedTextField(
                                value = config.baseUrl,
                                onValueChange = { input ->
                                    val cleaned = AgentApiTextParser.sanitizeInput(input)
                                    updateConfig(config.copy(baseUrl = cleaned))
                                },
                                label = { Text(localizedText("服务地址 (Base URL)")) },
                                placeholder = { Text(AgentApiConfig.DEFAULT_BASE_URL) },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = false,
                                maxLines = 3,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                                trailingIcon = {
                                    Row {
                                        if (config.baseUrl.isNotEmpty()) {
                                            IconButton(onClick = { updateConfig(config.copy(baseUrl = "")) }) {
                                                Icon(Icons.Filled.Clear, contentDescription = localizedText("清空"))
                                            }
                                        }
                                        IconButton(onClick = {
                                            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                            val clip = cm.primaryClip
                                            if (clip != null && clip.itemCount > 0) {
                                                val pasteText = clip.getItemAt(0).text?.toString().orEmpty()
                                                val cleaned = AgentApiTextParser.sanitizeInput(pasteText)
                                                if (cleaned.isNotBlank()) {
                                                    updateConfig(config.copy(baseUrl = cleaned))
                                                    Toast.makeText(context, "已从剪贴板粘贴服务地址", Toast.LENGTH_SHORT).show()
                                                }
                                            }
                                        }) {
                                            Icon(Icons.Filled.ContentPaste, contentDescription = localizedText("粘贴"))
                                        }
                                    }
                                }
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = localizedText("常用官方端点快速填入："),
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
                                listOf(
                                    "DeepSeek" to "https://api.deepseek.com/v1",
                                    "OpenAI" to "https://api.openai.com/v1",
                                    "Kimi" to "https://api.moonshot.cn/v1",
                                    "SiliconFlow" to "https://api.siliconflow.cn/v1"
                                ).forEach { (label, url) ->
                                    SuggestionChip(
                                        onClick = {
                                            updateConfig(config.copy(baseUrl = url))
                                            Toast.makeText(context, "已填入 $label 端点", Toast.LENGTH_SHORT).show()
                                        },
                                        label = { Text(label, style = MaterialTheme.typography.labelSmall) }
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.height(6.dp))
                            Text(
                                text = localizedText("规范兼容：端点支持自动适配补全 /chat/completions 与 /models。"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
            }

            // 3. Connectivity Verification Card
            item { SettingsGroupTitle(localizedText("连通性验证与诊断")) }
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
                                    testResultText = "【连通成功】耗时 ${elapsed}ms | 响应模型: ${chatResult.model}\n" +
                                            "测试回复: ${chatResult.content.trim()}\n" +
                                            "消耗 Token: ${chatResult.totalTokens}"
                                }.onFailure { error ->
                                    testResultSuccess = false
                                    testResultText = "【连通失败】${error.message}"
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
                            Text(localizedText("正在发起连线测试..."))
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
                }
            }

            item { Spacer(modifier = Modifier.height(24.dp)) }
        }
    }
}
