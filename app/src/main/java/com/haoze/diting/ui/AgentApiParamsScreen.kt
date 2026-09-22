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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.settings.AgentApiConfig
import com.haoze.diting.ui.settings.AgentApiSettingsStore
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Secondary settings page: Agent Model Parameters and System Prompt configuration.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentApiParamsScreen(
    onBack: () -> Unit,
    title: String = "参数与提示词"
) {
    val context = LocalContext.current

    var config by remember { mutableStateOf(AgentApiSettingsStore.getAgentApiConfig(context)) }

    fun updateConfig(newConfig: AgentApiConfig) {
        config = newConfig
        AgentApiSettingsStore.setAgentApiConfig(context, newConfig)
    }

    val promptTemplates = listOf(
        "安全威胁分析" to "你是一名网络安全与 DNS 威胁情报专家。擅长对域名安全性、防盗链、DGA 随机特征、恶意软件外联及追踪探针进行分析，并给出明确的处置建议。",
        "极简技术审查" to "你是一名资深网络协议工程师。请对给定的域名和流量快速给出最精炼的技术分类、风险等级与规则处置建议，格式化输出，杜绝多余套话。",
        "隐私与遥测审查" to "你是一名数字隐私与数据保护合规审计师。重点分析该域名是否涉及未经授权的用户行为遥测、设备指纹追踪或广告归因统计。"
    )

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // 1. System Prompt
            item { SettingsGroupTitle(localizedText("系统提示词")) }
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
                                    imageVector = Icons.Filled.Psychology,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(20.dp)
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = localizedText("系统提示词设定"),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            OutlinedTextField(
                                value = config.systemPrompt,
                                onValueChange = { updateConfig(config.copy(systemPrompt = it)) },
                                label = { Text(localizedText("系统提示词")) },
                                placeholder = { Text("例如：你是一名网络安全与 DNS 威胁情报专家...") },
                                modifier = Modifier.fillMaxWidth(),
                                minLines = 3,
                                maxLines = 7
                            )
                            Spacer(modifier = Modifier.height(10.dp))
                            Text(
                                text = localizedText("一键套用推荐角色模板："),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.height(6.dp))
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                promptTemplates.forEach { (label, content) ->
                                    FilterChip(
                                        selected = config.systemPrompt == content,
                                        onClick = {
                                            updateConfig(config.copy(systemPrompt = content))
                                            Toast.makeText(context, "已套用 $label 模板", Toast.LENGTH_SHORT).show()
                                        },
                                        label = { Text(label, style = MaterialTheme.typography.labelSmall) }
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = localizedText("说明：在日志、仪表盘或缓存页面发起 AI 分析时，将使用此系统提示词引导大语言模型进行分析。"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
            }

            // 2. Temperature Parameter
            item { SettingsGroupTitle(localizedText("采样温度 (Temperature)")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        imageVector = Icons.Filled.Thermostat,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(20.dp)
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = localizedText("生成随机度与创造性"),
                                        style = MaterialTheme.typography.labelLarge,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                                Surface(
                                    shape = RoundedCornerShape(8.dp),
                                    color = MaterialTheme.colorScheme.primaryContainer
                                ) {
                                    Text(
                                        text = String.format(Locale.US, "%.1f", config.temperature),
                                        style = MaterialTheme.typography.labelMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                                    )
                                }
                            }

                            Spacer(modifier = Modifier.height(8.dp))
                            Slider(
                                value = config.temperature.toFloat(),
                                onValueChange = { value ->
                                    val rounded = (value * 10).roundToInt() / 10.0
                                    updateConfig(config.copy(temperature = rounded))
                                },
                                valueRange = 0.0f..2.0f,
                                steps = 19
                            )

                            val styleLabel = when {
                                config.temperature <= 0.3 -> "严谨精确 (适合安全分析与结构化输出)"
                                config.temperature <= 0.8 -> "平衡适中 (推荐日常综合分析场景)"
                                else -> "发散多变 (输出内容更为丰富自由)"
                            }

                            Card(
                                shape = RoundedCornerShape(8.dp),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.5f)
                                ),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = localizedText("当前模式：$styleLabel"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(10.dp)
                                )
                            }
                        }
                    }
                )
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
                            updateConfig(
                                config.copy(
                                    temperature = AgentApiConfig.DEFAULT_TEMPERATURE,
                                    systemPrompt = ""
                                )
                            )
                            Toast.makeText(context, "推理参数已重置为默认值", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(localizedText("恢复默认参数"))
                    }
                }
            }

            item { Spacer(modifier = Modifier.height(24.dp)) }
        }
    }
}
