package com.haoze.dnssr.ui.traffic

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DataUsage
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SecondaryScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.DisposableEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.AppAlertDialog
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.localizedText

@Composable
fun AppTrafficStatsScreen(
    onBack: () -> Unit,
    viewModel: AppTrafficStatsViewModel = viewModel()
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, viewModel) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> viewModel.setScreenActive(true)
                Lifecycle.Event.ON_STOP -> viewModel.setScreenActive(false)
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            viewModel.setScreenActive(false)
        }
    }

    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showAttributionDialog by remember { mutableStateOf(false) }
    var showClearConfirmDialog by remember { mutableStateOf(false) }
    val colors = MaterialTheme.colorScheme

    SettingsScaffold(
        title = localizedText("应用流量统计"),
        onBack = onBack,
        actions = {
            IconButton(onClick = { showClearConfirmDialog = true }) {
                Icon(
                    imageVector = Icons.Default.DeleteSweep,
                    contentDescription = localizedText("清除历史")
                )
            }
            IconButton(onClick = viewModel::refresh) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = localizedText("刷新")
                )
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .background(colors.background)
        ) {
            SecondaryScrollableTabRow(
                selectedTabIndex = uiState.selectedTimeRange.ordinal,
                edgePadding = 16.dp,
                containerColor = Color.Transparent,
                indicator = {
                    TabRowDefaults.SecondaryIndicator(
                        Modifier.tabIndicatorOffset(uiState.selectedTimeRange.ordinal),
                        color = colors.primary
                    )
                },
                divider = { HorizontalDivider(color = colors.outlineVariant.copy(alpha = 0.3f)) }
            ) {
                TrafficTimeRange.entries.forEach { range ->
                    Tab(
                        selected = uiState.selectedTimeRange == range,
                        onClick = { viewModel.setTimeRange(range) },
                        text = {
                            Text(
                                text = localizedText(range.displayName),
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = if (uiState.selectedTimeRange == range) FontWeight.Bold else FontWeight.Normal
                            )
                        }
                    )
                }
            }

            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item(key = "speed_gauge") {
                    TrafficGaugeCard(uiState = uiState)
                }

                item(key = "attribution_banner") {
                    AttributionBannerCard(onClick = { showAttributionDialog = true })
                }

                item(key = "filter_bar") {
                    TrafficFilterBar(
                        uiState = uiState,
                        onSearchChange = viewModel::setSearchQuery,
                        onSortChange = viewModel::setSortMode,
                        onHideSystemAppsChange = viewModel::setHideSystemApps
                    )
                }

                if (uiState.isLoading) {
                    item(key = "loading") {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 40.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                } else if (uiState.appItems.isEmpty()) {
                    item(key = "empty") {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 48.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.DataUsage,
                                    contentDescription = null,
                                    tint = colors.onSurfaceVariant.copy(alpha = 0.5f),
                                    modifier = Modifier.size(48.dp)
                                )
                                Text(
                                    text = localizedText("暂无流量数据"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = colors.onSurfaceVariant
                                )
                            }
                        }
                    }
                } else {
                    items(
                        items = uiState.appItems,
                        key = { it.packageName }
                    ) { item ->
                        AppTrafficRankItem(
                            item = item,
                            onClick = { viewModel.selectAppDetail(item.packageName) }
                        )
                    }
                }
            }
        }
    }

    if (showAttributionDialog) {
        TrafficAttributionDialog(onDismiss = { showAttributionDialog = false })
    }

    if (showClearConfirmDialog) {
        AppAlertDialog(
            onDismissRequest = { showClearConfirmDialog = false },
            title = { Text(localizedText("清除全部流量记录？")) },
            text = { Text(localizedText("此操作将清空所有已持久化的应用历史流量统计，清除后无法恢复。")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.clearHistory()
                        showClearConfirmDialog = false
                    }
                ) {
                    Text(localizedText("清除"), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearConfirmDialog = false }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

    uiState.selectedAppDetail?.let { detail ->
        AppTrafficDetailDialog(
            detail = detail,
            onDismiss = { viewModel.selectAppDetail(null) }
        )
    }
}
