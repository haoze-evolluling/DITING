package com.haoze.diting.dnsmode.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.haoze.diting.dnsmode.ui.navigation.DnsNavTab
import com.haoze.diting.dnsmode.viewmodel.DnsMainViewModel
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.localizedText

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DnsMainScreen(
    viewModel: DnsMainViewModel,
    onSwitchToNormalMode: () -> Unit,
    onSelectMode: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    var currentTab by remember { mutableStateOf(DnsNavTab.HOME) }
    var showSwitchConfirmDialog by remember { mutableStateOf(false) }

    BackHandler(enabled = currentTab != DnsNavTab.HOME) {
        currentTab = DnsNavTab.HOME
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = localizedText("谛听 · DNS模式"),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                },
                actions = {
                    Surface(
                        shape = RoundedCornerShape(8.dp),
                        color = MaterialTheme.colorScheme.tertiaryContainer,
                        modifier = Modifier.padding(end = 4.dp)
                    ) {
                        Text(
                            text = localizedText("DNS 模式"),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onTertiaryContainer,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }

                    IconButton(onClick = { showSwitchConfirmDialog = true }) {
                        Icon(
                            imageVector = Icons.Default.SwapHoriz,
                            contentDescription = localizedText("切换到普通模式"),
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onSurface
                ),
                windowInsets = WindowInsets(0, 0, 0, 0)
            )
        },
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surfaceContainer,
                tonalElevation = 0.dp
            ) {
                DnsNavTab.entries.forEach { tab ->
                    val isSelected = currentTab == tab
                    NavigationBarItem(
                        selected = isSelected,
                        onClick = { currentTab = tab },
                        icon = {
                            Icon(
                                imageVector = tab.icon,
                                contentDescription = localizedText(tab.title)
                            )
                        },
                        label = {
                            Text(
                                text = localizedText(tab.title),
                                style = MaterialTheme.typography.labelMedium
                            )
                        }
                    )
                }
            }
        },
        containerColor = Color.Transparent
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when (currentTab) {
                DnsNavTab.HOME -> DnsHomeScreen(
                    status = uiState.status,
                    activeUpstream = uiState.activeUpstream,
                    stats = uiState.stats,
                    onToggleService = viewModel::toggleService,
                    onNavigateToServers = { currentTab = DnsNavTab.SERVERS },
                    onSwitchToNormalMode = { showSwitchConfirmDialog = true },
                    onSelectMode = onSelectMode
                )
                DnsNavTab.SERVERS -> DnsServersScreen(
                    upstreams = uiState.upstreams,
                    selectedUpstreamId = uiState.config.selectedUpstreamId,
                    onSelectUpstream = viewModel::selectUpstream
                )
                DnsNavTab.SETTINGS -> DnsSettingsScreen(
                    config = uiState.config,
                    onUpdateConfig = viewModel::updateConfig,
                    onResetStats = viewModel::resetStats,
                    onSwitchToNormalMode = { showSwitchConfirmDialog = true },
                    onSelectMode = onSelectMode
                )
            }
        }
    }

    if (showSwitchConfirmDialog) {
        AppConfirmDialog(
            onDismissRequest = { showSwitchConfirmDialog = false },
            title = localizedText("切换到普通模式"),
            message = localizedText("切换后将启动普通工作模式，具备完整的规则过滤、HTTPS 检查与全量网络代理功能。确认切换吗？"),
            confirmLabel = localizedText("确认切换"),
            cancelLabel = localizedText("取消"),
            onConfirm = {
                showSwitchConfirmDialog = false
                onSwitchToNormalMode()
            }
        )
    }
}
