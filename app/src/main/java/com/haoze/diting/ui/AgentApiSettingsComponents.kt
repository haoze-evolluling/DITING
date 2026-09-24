package com.haoze.diting.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.settings.AgentApiConfig
import com.haoze.diting.ui.settings.AiProvider

/**
 * Main overview and status card on the Agent API hub page.
 */
@Composable
internal fun AgentApiStatusCard(
    config: AgentApiConfig,
    activeProvider: AiProvider?,
    onEnabledChange: (Boolean) -> Unit
) {
    SettingsSurfaceGroup(
        content = listOf(
            {
                SettingsSwitchItem(
                    title = localizedText("启用 AI 分析"),
                    subtitle = localizedText("开启后，可在 DNS 日志、请求日志、仪表盘等页面使用 AI 分析域名与网络流量"),
                    checked = config.enabled,
                    onCheckedChange = onEnabledChange
                )
            },
            {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                ) {
                    Text(
                        text = localizedText("当前服务运行状态"),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.height(8.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        // Model Card
                        Card(
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(10.dp),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.6f)
                            )
                        ) {
                            Column(modifier = Modifier.padding(10.dp)) {
                                Text(
                                    text = localizedText("当前厂商与模型"),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    text = if (activeProvider != null) {
                                        "${activeProvider.name} (${activeProvider.modelName.ifBlank { config.model }})"
                                    } else {
                                        config.model
                                    },
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1
                                )
                            }
                        }

                        // Credential Card
                        Card(
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(10.dp),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.6f)
                            )
                        ) {
                            Column(modifier = Modifier.padding(10.dp)) {
                                Text(
                                    text = localizedText("API 凭据"),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    text = if (config.apiKey.isNotBlank()) "已就绪 (sk-••••)" else "未配置 Key",
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = if (config.apiKey.isNotBlank()) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                                    maxLines = 1
                                )
                            }
                        }
                    }
                }
            }
        )
    )
}

/**
 * Secondary settings page navigation entry group.
 */
@Composable
internal fun AgentApiNavigationGroup(
    onNavigateToProviders: () -> Unit,
    onNavigateToParams: () -> Unit
) {
    SettingsSurfaceGroup(
        content = listOf(
            {
                SettingsNavigationRow(
                    icon = Icons.Filled.Layers,
                    title = localizedText("AI 厂商管理"),
                    subtitle = localizedText("管理服务厂商、在线拉取模型与配置密钥"),
                    onClick = onNavigateToProviders
                )
            },
            {
                SettingsNavigationRow(
                    icon = Icons.Filled.Psychology,
                    title = localizedText("参数与提示词"),
                    subtitle = localizedText("配置系统提示词与采样温度等生成参数"),
                    onClick = onNavigateToParams
                )
            }
        )
    )
}


@Composable
private fun SettingsNavigationRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    SettingsItem(
        title = title,
        subtitle = subtitle,
        leadingIcon = icon,
        onClick = onClick
    ) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.ArrowForward,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp)
        )
    }
}

/**
 * Playground card for testing agent intelligence directly from the settings screen.
 */
@Composable
internal fun AgentApiPlaygroundCard(
    onAnalyzeDomain: (String) -> Unit,
    onAnalyzeTraffic: () -> Unit
) {
    var testDomain by remember { mutableStateOf("tracking.analytics-service.net") }

    SettingsSurfaceGroup(
        content = listOf {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 14.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = localizedText("功能测试"),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = localizedText("输入任意域名，测试 AI 安全分析与处置建议："),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(10.dp))
                OutlinedTextField(
                    value = testDomain,
                    onValueChange = { testDomain = it },
                    label = { Text(localizedText("测试域名")) },
                    placeholder = { Text("example.com") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    FilledTonalButton(
                        onClick = {
                            if (testDomain.isNotBlank()) {
                                onAnalyzeDomain(testDomain.trim())
                            }
                        },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(10.dp)
                    ) {
                        Icon(Icons.Filled.Search, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(localizedText("分析测试域名"))
                    }

                    OutlinedButton(
                        onClick = onAnalyzeTraffic,
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(10.dp)
                    ) {
                        Icon(Icons.Filled.AutoAwesome, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(localizedText("分析当前网络"))
                    }
                }
            }
        }
    )
}

/**
 * Informational note regarding Agent API features across app modules.
 */
@Composable
internal fun AgentApiNoticeSection() {
    SettingsInfoText(
        localizedText("提示：配置并启用后，您可以在【DNS 日志】、【HTTP 请求日志】、【日志仪表盘】及【DNS 缓存】等页面随时点击“AI 分析”按钮，对异常流量和未知域名进行安全分析并一键添加规则。")
    )
}
