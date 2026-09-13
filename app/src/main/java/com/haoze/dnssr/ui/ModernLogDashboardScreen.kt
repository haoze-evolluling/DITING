package com.haoze.dnssr.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.dashboard.AllModeDashboard
import com.haoze.dnssr.ui.dashboard.FilteredModeDashboard
import com.haoze.dnssr.ui.dashboard.OffModeDashboard
import com.haoze.dnssr.ui.dashboard.formatClockTime

@Composable
fun ModernLogDashboardScreen(
    onBack: () -> Unit,
    onNavigateToDnsLogs: () -> Unit,
    onNavigateToDnsCache: () -> Unit,
    onNavigateToRaceStats: () -> Unit,
    onNavigateToBootstrapStats: () -> Unit,
    onNavigateToSubscriptionInterceptionStats: () -> Unit,
    onNavigateToTrafficStats: (() -> Unit)? = null,
    viewModel: ModernLogDashboardViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val colors = MaterialTheme.colorScheme

    LaunchedEffect(viewModel) {
        viewModel.refresh()
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
        actions = {
            IconButton(onClick = viewModel::refresh) {
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
                .padding(innerPadding)
                .background(colors.background)
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
                        onNavigateToTrafficStats = onNavigateToTrafficStats
                    )
                    DnsLogMode.BLOCKED_AND_ERRORS -> FilteredModeDashboard(
                        state = uiState,
                        onNavigateToDnsLogs = onNavigateToDnsLogs,
                        onNavigateToDnsCache = onNavigateToDnsCache,
                        onNavigateToRaceStats = onNavigateToRaceStats,
                        onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                        onNavigateToSubscriptionInterceptionStats = onNavigateToSubscriptionInterceptionStats,
                        onNavigateToTrafficStats = onNavigateToTrafficStats
                    )
                    DnsLogMode.OFF -> OffModeDashboard(
                        state = uiState,
                        onNavigateToDnsCache = onNavigateToDnsCache,
                        onNavigateToRaceStats = onNavigateToRaceStats,
                        onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                        onNavigateToTrafficStats = onNavigateToTrafficStats
                    )
                }
            }
        }
    }
}
