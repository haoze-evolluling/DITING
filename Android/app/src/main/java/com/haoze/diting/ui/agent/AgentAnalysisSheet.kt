package com.haoze.diting.ui.agent

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.sqlite.db.SimpleSQLiteQuery
import com.haoze.diting.core.rule.AllowListManager
import com.haoze.diting.core.rule.BlockListManager
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher
import com.haoze.diting.ui.components.SettingsCardMargin
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.settings.AgentApiClient
import com.haoze.diting.ui.settings.AgentApiSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
            .padding(horizontal = SettingsCardMargin, vertical = 8.dp)
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
                config.apiKey.isBlank() -> {
                    AgentApiKeyMissingCard(
                        onDismiss = onDismiss,
                        onNavigateToSettings = onNavigateToSettings
                    )
                }

                !config.enabled -> {
                    AgentApiDisabledCard(
                        onEnableAndAnalyze = {
                            val updated = config.copy(enabled = true)
                            AgentApiSettingsStore.setAgentApiConfig(context, updated)
                            config = updated
                            executeAnalysis()
                        }
                    )
                }

                isLoading -> {
                    AgentAnalysisLoadingView(modelName = config.model)
                }

                errorMessage != null -> {
                    AgentAnalysisErrorCard(
                        errorMessage = errorMessage.orEmpty(),
                        onDismiss = onDismiss,
                        onNavigateToSettings = onNavigateToSettings,
                        onRetry = ::executeAnalysis
                    )
                }

                analysisResult != null -> {
                    AgentAnalysisResultContent(
                        result = analysisResult!!,
                        appliedActionText = appliedActionText
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Bottom Action Bar (when result is present)
        val currentResult = analysisResult
        if (currentResult != null && !isLoading) {
            AgentAnalysisBottomBar(
                isDomainTarget = target is AnalysisTarget.Domain,
                analysisContent = currentResult.content,
                onAddWhitelist = {
                    if (target is AnalysisTarget.Domain) {
                        val domain = target.domain
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
                    }
                },
                onAddBlocklist = {
                    if (target is AnalysisTarget.Domain) {
                        val domain = target.domain
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
                    }
                },
                onReAnalyze = ::executeAnalysis
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
    }
}
