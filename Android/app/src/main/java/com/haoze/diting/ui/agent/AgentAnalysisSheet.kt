package com.haoze.diting.ui.agent

import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SheetState
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.sqlite.db.SimpleSQLiteQuery
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.RequestSource
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.settings.AgentApiClient
import com.haoze.diting.ui.settings.AgentApiSettingsStore
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher
import com.haoze.diting.vpn.AllowListManager
import com.haoze.diting.vpn.BlockListManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Represents the target entity for agent intelligence analysis.
 */
sealed interface AnalysisTarget {
    data class Domain(
        val domain: String,
        val contextLogs: List<String> = emptyList()
    ) : AnalysisTarget

    data class RecentTraffic(
        val source: RequestSource = RequestSource.ALL
    ) : AnalysisTarget
}

/**
 * Material 3 Agent Analysis Modal Sheet.
 * Provides deep AI-driven cybersecurity evaluation and traffic diagnosis.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentAnalysisSheet(
    target: AnalysisTarget?,
    onDismiss: () -> Unit,
    onNavigateToSettings: () -> Unit = {},
    onRuleAdded: (() -> Unit)? = null
) {
    if (target == null) return

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 6.dp
    ) {
        AgentAnalysisSheetContent(
            target = target,
            onDismiss = onDismiss,
            onNavigateToSettings = onNavigateToSettings,
            onRuleAdded = onRuleAdded
        )
    }
}

@Composable
internal fun AgentAnalysisSheetContent(
    target: AnalysisTarget,
    onDismiss: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onRuleAdded: (() -> Unit)?
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val database = remember(context) { AppDatabase.getInstance(context) }

    var config by remember { mutableStateOf(AgentApiSettingsStore.getAgentApiConfig(context)) }

    var isLoading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var analysisResult by remember { mutableStateOf<AgentApiClient.AgentChatResult?>(null) }
    var appliedActionText by remember { mutableStateOf<String?>(null) }

    fun executeAnalysis() {
        isLoading = true
        errorMessage = null
        appliedActionText = null

        scope.launch {
            if (config.apiKey.isBlank()) {
                isLoading = false
                errorMessage = "未检测到配置的 API Key，请先进入 AI 设置配置接口密钥。"
                return@launch
            }

            val result = withContext(Dispatchers.IO) {
                when (target) {
                    is AnalysisTarget.Domain -> {
                        // Gather recent context for this domain
                        val logs = runCatching {
                            val pattern = "%${target.domain.lowercase()}%"
                            val query = SimpleSQLiteQuery(
                                "SELECT queryName, result, message FROM dns_log WHERE queryName LIKE ? ORDER BY timestamp DESC LIMIT 5",
                                arrayOf(pattern)
                            )
                            database.dnsLogDao().queryList(query).map {
                                "DNS: ${it.queryName} -> ${it.result} (${it.message ?: "无"})"
                            }
                        }.getOrDefault(emptyList())

                        val contextStr = (target.contextLogs + logs).distinct().joinToString("\n")
                        AgentApiClient.analyzeDomain(config, target.domain, contextStr.ifBlank { null })
                    }
                    is AnalysisTarget.RecentTraffic -> {
                        // Gather recent traffic summary
                        val summary = runCatching {
                            val recentDns = database.dnsLogDao().queryList(
                                SimpleSQLiteQuery("SELECT * FROM dns_log ORDER BY timestamp DESC LIMIT 40")
                            )
                            val recentHttp = database.httpRequestLogDao().queryList(
                                SimpleSQLiteQuery("SELECT * FROM http_request_log ORDER BY timestamp DESC LIMIT 30")
                            )

                            val totalDns = recentDns.size
                            val blockedDns = recentDns.count { it.result.equals("BLOCKED", ignoreCase = true) }
                            val rewrittenDns = recentDns.count { it.result.equals("REWRITTEN", ignoreCase = true) }
                            val cachedDns = recentDns.count { it.cached }
                            val topDnsDomains = recentDns.groupBy { it.queryName }
                                .mapValues { it.value.size }
                                .toList()
                                .sortedByDescending { it.second }
                                .take(8)

                            val totalHttp = recentHttp.size
                            val blockedHttp = recentHttp.count { it.outcome.equals("blocked", ignoreCase = true) }
                            val bypassedHttp = recentHttp.count { it.outcome in setOf("passthrough", "bypassed") }

                            buildString {
                                appendLine("【近期 DNS 监控统计】")
                                appendLine("- 采样数量: $totalDns 条")
                                appendLine("- 规则拦截: $blockedDns 条, 规则覆写: $rewrittenDns 条, 缓存命中: $cachedDns 条")
                                appendLine("- 高频请求域名:")
                                topDnsDomains.forEach { (d, c) -> appendLine("  * $d (请求 $c 次)") }
                                if (totalHttp > 0) {
                                    appendLine()
                                    appendLine("【近期 HTTP/HTTPS 流量统计】")
                                    appendLine("- 采样数量: $totalHttp 条, 拦截数: $blockedHttp, 旁路直连数: $bypassedHttp")
                                }
                            }
                        }.getOrElse { "无法提取近期流量统计：${it.message}" }

                        AgentApiClient.analyzeNetworkTraffic(config, summary)
                    }
                }
            }

            isLoading = false
            result.onSuccess { chatResult ->
                analysisResult = chatResult
            }.onFailure { err ->
                errorMessage = err.message ?: "智能分析请求失败"
            }
        }
    }

    LaunchedEffect(target) {
        config = AgentApiSettingsStore.getAgentApiConfig(context)
        if (config.apiKey.isNotBlank() && config.enabled) {
            executeAnalysis()
        } else {
            isLoading = false
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp)
            .heightIn(max = 680.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.size(38.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Filled.AutoAwesome,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = when (target) {
                            is AnalysisTarget.Domain -> localizedText("域名安全分析")
                            is AnalysisTarget.RecentTraffic -> localizedText("网络流量分析")
                        },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = when (target) {
                            is AnalysisTarget.Domain -> target.domain
                            is AnalysisTarget.RecentTraffic -> localizedText("基于近期网络与 DNS 监控数据")
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Medium
                    )
                }
            }

            IconButton(onClick = onDismiss) {
                Icon(Icons.Filled.Close, contentDescription = localizedText("关闭"))
            }
        }

        Spacer(modifier = Modifier.height(14.dp))
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        Spacer(modifier = Modifier.height(14.dp))

        // Content Area
        Box(
            modifier = Modifier
                .weight(1f, fill = false)
                .fillMaxWidth()
        ) {
            when {
                // Not configured
                config.apiKey.isBlank() -> {
                    Card(
                        shape = RoundedCornerShape(16.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHighest),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier.padding(20.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Settings,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(44.dp)
                            )
                            Spacer(modifier = Modifier.height(12.dp))
                            Text(
                                text = localizedText("未配置 API 密钥"),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Spacer(modifier = Modifier.height(6.dp))
                            Text(
                                text = localizedText("需配置 OpenAI / DeepSeek 兼容的 API 密钥后，方可使用 AI 域名与流量分析功能。"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Button(
                                onClick = {
                                    onDismiss()
                                    onNavigateToSettings()
                                },
                                shape = RoundedCornerShape(12.dp)
                            ) {
                                Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(16.dp))
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(localizedText("前往配置"))
                            }
                        }
                    }
                }

                // Disabled
                !config.enabled -> {
                    Card(
                        shape = RoundedCornerShape(16.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHighest),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier.padding(20.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Security,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.tertiary,
                                modifier = Modifier.size(44.dp)
                            )
                            Spacer(modifier = Modifier.height(12.dp))
                            Text(
                                text = localizedText("AI 分析功能已关闭"),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Spacer(modifier = Modifier.height(6.dp))
                            Text(
                                text = localizedText("AI 分析服务当前处于停用状态。您可以直接在此开启，或前往设置页面管理。"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Button(
                                onClick = {
                                    val updated = config.copy(enabled = true)
                                    AgentApiSettingsStore.setAgentApiConfig(context, updated)
                                    config = updated
                                    executeAnalysis()
                                },
                                shape = RoundedCornerShape(12.dp)
                            ) {
                                Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(16.dp))
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(localizedText("开启 AI 分析并继续"))
                            }
                        }
                    }
                }

                // Loading
                isLoading -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 48.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(44.dp),
                            strokeWidth = 3.dp,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.height(18.dp))
                        Text(
                            text = localizedText("正在进行 AI 分析..."),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = localizedText("模型: ${config.model}"),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                // Error
                errorMessage != null -> {
                    Card(
                        shape = RoundedCornerShape(16.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    Icons.Filled.ErrorOutline,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = localizedText("分析失败"),
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onErrorContainer,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = errorMessage.orEmpty(),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onErrorContainer
                            )
                            Spacer(modifier = Modifier.height(14.dp))
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.End
                            ) {
                                OutlinedButton(
                                    onClick = {
                                        onDismiss()
                                        onNavigateToSettings()
                                    }
                                ) {
                                    Text(localizedText("检查设置"))
                                }
                                Spacer(modifier = Modifier.width(10.dp))
                                Button(
                                    onClick = ::executeAnalysis,
                                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                                ) {
                                    Text(localizedText("重试"))
                                }
                            }
                        }
                    }
                }

                // Success
                analysisResult != null -> {
                    val res = analysisResult!!
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        // Chips row: Model, Token count
                        item {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                SuggestionChip(
                                    onClick = {},
                                    label = { Text("模型: ${res.model}", fontSize = 11.sp) },
                                    shape = RoundedCornerShape(8.dp)
                                )
                                if (res.totalTokens > 0) {
                                    Text(
                                        text = "消耗 ${res.totalTokens} Tokens",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }

                        // Formatted content card
                        item {
                            Card(
                                shape = RoundedCornerShape(16.dp),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.6f)),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    FormattedAnalysisText(res.content)
                                }
                            }
                        }

                        // Action feedback toast
                        if (appliedActionText != null) {
                            item {
                                Card(
                                    shape = RoundedCornerShape(10.dp),
                                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Row(
                                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            Icons.Filled.Check,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.size(16.dp)
                                        )
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text(
                                            text = appliedActionText.orEmpty(),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onPrimaryContainer
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Bottom Action Bar (when result is present)
        if (analysisResult != null && !isLoading) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // If it's a domain, show rule quick-add buttons
                if (target is AnalysisTarget.Domain) {
                    val domain = target.domain
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        FilledTonalButton(
                            onClick = {
                                scope.launch(Dispatchers.IO) {
                                    val success = AllowListManager(database.allowRuleDao(), scope = RuleScope.DNS).addRule(domain)
                                    withContext(Dispatchers.Main) {
                                        if (success) {
                                            RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "allow", domain, RuleScope.DNS)
                                            onRuleAdded?.invoke()
                                            appliedActionText = "已成功加入白名单并热更新生效"
                                        } else {
                                            appliedActionText = "添加白名单失败（可能格式不规范或已存在）"
                                        }
                                    }
                                }
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Icon(Icons.Filled.Shield, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(localizedText("加入白名单"))
                        }

                        Button(
                            onClick = {
                                scope.launch(Dispatchers.IO) {
                                    val success = BlockListManager(database.blockRuleDao(), scope = RuleScope.DNS).addRule(domain)
                                    withContext(Dispatchers.Main) {
                                        if (success) {
                                            RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "block", domain, RuleScope.DNS)
                                            onRuleAdded?.invoke()
                                            appliedActionText = "已成功加入屏蔽黑名单并热更新生效"
                                        } else {
                                            appliedActionText = "添加屏蔽规则失败（可能已存在）"
                                        }
                                    }
                                }
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Icon(Icons.Filled.Close, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(localizedText("加入屏蔽规则"))
                        }
                    }
                }

                // General operations: Copy & Re-analyze
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = {
                            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            cm.setPrimaryClip(
                                android.content.ClipData.newPlainText("AgentAnalysis", analysisResult?.content.orEmpty())
                            )
                            Toast.makeText(context, "分析结果已复制到剪贴板", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Icon(Icons.Filled.ContentCopy, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(localizedText("复制结果"))
                    }

                    OutlinedButton(
                        onClick = ::executeAnalysis,
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(localizedText("重新分析"))
                    }
                }
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
    }
}

/**
 * Text formatter that renders Markdown-style headings, lists, code blocks, and highlights.
 */
@Composable
private fun FormattedAnalysisText(rawText: String) {
    MarkdownViewer(markdown = rawText)
}
