package com.haoze.diting.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.haoze.diting.SettingsRouteActivity
import com.haoze.diting.ui.agent.AgentAnalysisSheet
import com.haoze.diting.ui.agent.AnalysisTarget
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.dashboard.AllModeDashboard
import com.haoze.diting.ui.dashboard.FilteredModeDashboard
import com.haoze.diting.ui.dashboard.OffModeDashboard
import com.haoze.diting.ui.dashboard.formatClockTime

@Composable
fun ModernLogDashboardScreen(
    onBack: () -> Unit = {},
    onNavigateToDnsLogs: () -> Unit,
    onNavigateToDnsCache: () -> Unit,
    onNavigateToRaceStats: () -> Unit,
    onNavigateToBootstrapStats: () -> Unit,
    onNavigateToSubscriptionInterceptionStats: () -> Unit,
    onNavigateToTrafficStats: (() -> Unit)? = null,
    viewModel: ModernLogDashboardViewModel = viewModel(),
    showBackIcon: Boolean = true,
    contentBottomPadding: androidx.compose.ui.unit.Dp = 0.dp,
    isActive: Boolean = true,
    refreshTrigger: Long = 0L
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val colors = MaterialTheme.colorScheme
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var showAgentAnalysis by remember { mutableStateOf(false) }

    LaunchedEffect(isActive, refreshTrigger) {
        if (isActive) {
            viewModel.refresh(force = refreshTrigger > 0L)
        }
    }

    DisposableEffect(lifecycleOwner, isActive) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && isActive) {
                viewModel.refresh()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    val subtitle = remember(uiState.logMode, uiState.generatedAt, uiState.hasData) {
        val modeLabel = when (uiState.logMode) {
            DnsLogMode.ALL -> "记录全部请求"
            DnsLogMode.BLOCKED_AND_ERRORS -> "仅记录拦截与错误"
            DnsLogMode.OFF -> "请求日志已关闭"
        }
        if (!uiState.hasData || uiState.generatedAt <= 0L) {
            modeLabel
        } else {
            val time = formatClockTime(uiState.generatedAt)
            when (uiState.logMode) {
                DnsLogMode.ALL -> "$modeLabel · 更新于 $time"
                else -> "$modeLabel · $time"
            }
        }
    }

    SettingsScaffold(
        titleContent = {
            Column {
                Text(
                    text = localizedText("日志仪表盘"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = localizedText(subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        },
        onBack = onBack,
        showBackIcon = showBackIcon,
        containerColor = if (!showBackIcon) Color.Transparent else MaterialTheme.colorScheme.background,
        topBarContainerColor = if (!showBackIcon) Color.Transparent else MaterialTheme.colorScheme.background,
        actions = {
            IconButton(onClick = { showAgentAnalysis = true }) {
                Icon(
                    imageVector = Icons.Filled.AutoAwesome,
                    contentDescription = localizedText("AI 网络分析"),
                    tint = colors.primary
                )
            }
            IconButton(onClick = { viewModel.refresh(force = true) }) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = localizedText("刷新")
                )
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = innerPadding.calculateTopPadding())
        ) {
            if (uiState.loading && !uiState.hasData) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else {
                when (uiState.logMode) {
                    DnsLogMode.ALL -> AllModeDashboard(
                        state = uiState,
                        onNavigateToDnsLogs = onNavigateToDnsLogs,
                        onNavigateToDnsCache = onNavigateToDnsCache,
                        onNavigateToRaceStats = onNavigateToRaceStats,
                        onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                        onNavigateToSubscriptionInterceptionStats = onNavigateToSubscriptionInterceptionStats,
                        onNavigateToTrafficStats = onNavigateToTrafficStats,
                        contentBottomPadding = contentBottomPadding
                    )
                    DnsLogMode.BLOCKED_AND_ERRORS -> FilteredModeDashboard(
                        state = uiState,
                        onNavigateToDnsLogs = onNavigateToDnsLogs,
                        onNavigateToDnsCache = onNavigateToDnsCache,
                        onNavigateToRaceStats = onNavigateToRaceStats,
                        onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                        onNavigateToSubscriptionInterceptionStats = onNavigateToSubscriptionInterceptionStats,
                        onNavigateToTrafficStats = onNavigateToTrafficStats,
                        contentBottomPadding = contentBottomPadding
                    )
                    DnsLogMode.OFF -> OffModeDashboard(
                        state = uiState,
                        onNavigateToDnsCache = onNavigateToDnsCache,
                        onNavigateToRaceStats = onNavigateToRaceStats,
                        onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                        onNavigateToTrafficStats = onNavigateToTrafficStats,
                        contentBottomPadding = contentBottomPadding
                    )
                }
            }
        }
    }

    if (showAgentAnalysis) {
        AgentAnalysisSheet(
            target = AnalysisTarget.RecentTraffic(),
            onDismiss = { showAgentAnalysis = false },
            onNavigateToSettings = {
                context.startActivity(SettingsRouteActivity.createIntent(context, Routes.AGENT_API_SETTINGS))
            },
            onRuleAdded = {
                viewModel.refresh()
            }
        )
    }
}
