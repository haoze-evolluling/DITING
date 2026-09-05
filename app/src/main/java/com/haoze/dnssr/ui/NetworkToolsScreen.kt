package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lan
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.NetworkSnapshot
import kotlinx.coroutines.launch

/**
 * 统一的网络诊断模块：集中提供 DNS 查询测速、Ping 测试、DNS 解析查询与路由追踪。
 * 顶部固定网络概览卡与工具切换标签，四个工具分页承载、可左右滑动切换。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NetworkToolsScreen(
    onBack: () -> Unit,
    title: String = "网络诊断",
    viewModel: NetworkToolsViewModel = viewModel(),
    speedTestViewModel: RaceModeSettingsViewModel = viewModel()
) {
    val context = LocalContext.current
    val toolMode by viewModel.toolMode.collectAsStateWithLifecycle()
    val networkSnapshot by viewModel.networkSnapshot.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()

    LaunchedEffect(message) {
        message?.let {
            context.showToast(it, Toast.LENGTH_SHORT)
            viewModel.clearMessage()
        }
    }

    NavigationSettledEffect {
        viewModel.activate()
    }

    SettingsScaffold(
        title = title,
        onBack = onBack
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            NetworkOverviewCard(
                snapshot = networkSnapshot,
                onRefresh = viewModel::refreshNetworkInfo
            )

            val scope = rememberCoroutineScope()
            val modeIndex = NetworkToolMode.entries.indexOf(toolMode).coerceAtLeast(0)
            val pagerState = rememberPagerState(initialPage = modeIndex) {
                NetworkToolMode.entries.size
            }

            LaunchedEffect(toolMode) {
                val target = NetworkToolMode.entries.indexOf(toolMode)
                if (target >= 0 && pagerState.currentPage != target && !pagerState.isScrollInProgress) {
                    pagerState.animateScrollToPage(target)
                }
            }
            LaunchedEffect(pagerState) {
                snapshotFlow { pagerState.currentPage }.collect { page ->
                    val mode = NetworkToolMode.entries.getOrNull(page) ?: return@collect
                    if (mode != toolMode) {
                        viewModel.setToolMode(mode)
                    }
                }
            }

            PrimaryTabRow(selectedTabIndex = modeIndex) {
                NetworkToolMode.entries.forEachIndexed { index, mode ->
                    Tab(
                        selected = modeIndex == index,
                        onClick = { scope.launch { pagerState.animateScrollToPage(index) } },
                        icon = { Icon(imageVector = mode.icon(), contentDescription = null) },
                        text = { Text(text = localizedText(mode.label), maxLines = 1) }
                    )
                }
            }

            HorizontalPager(
                state = pagerState,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) { page ->
                when (NetworkToolMode.entries[page]) {
                    NetworkToolMode.SPEED_TEST -> SpeedTestSection(speedTestViewModel)
                    NetworkToolMode.PING -> PingSection(viewModel)
                    NetworkToolMode.DNS_LOOKUP -> DnsLookupSection(viewModel)
                    NetworkToolMode.TRACEROUTE -> TracerouteSection(viewModel)
                }
            }
        }
    }
}

private fun NetworkToolMode.icon(): ImageVector = when (this) {
    NetworkToolMode.SPEED_TEST -> Icons.Filled.Speed
    NetworkToolMode.PING -> Icons.Filled.NetworkCheck
    NetworkToolMode.DNS_LOOKUP -> Icons.Filled.Dns
    NetworkToolMode.TRACEROUTE -> Icons.AutoMirrored.Filled.AltRoute
}

/**
 * 当前网络概览卡：收起时仅显示网络类型、接口与地址摘要，展开后逐项列出
 * IPv4 / IPv6 / 网关 / DNS，各行等宽字体展示并支持点击复制。
 */
@Composable
private fun NetworkOverviewCard(
    snapshot: NetworkSnapshot?,
    onRefresh: () -> Unit
) {
    SettingsGroupTitle("当前网络")
    if (snapshot == null) {
        SettingsInfoText("未获取到当前网络信息")
        return
    }

    var expanded by rememberSaveable { mutableStateOf(false) }
    SettingsSurfaceGroup(
        content = listOf {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { expanded = !expanded }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Filled.Lan,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(22.dp)
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = listOfNotNull(snapshot.networkType, snapshot.interfaceName)
                                .joinToString(" · "),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        val summary = listOfNotNull(
                            snapshot.ipv4Addresses.firstOrNull(),
                            snapshot.gateway
                        ).joinToString(" · ")
                        if (summary.isNotEmpty()) {
                            Text(
                                text = summary,
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (snapshot.isVpnActive) {
                        Surface(
                            shape = RoundedCornerShape(6.dp),
                            color = MaterialTheme.colorScheme.secondaryContainer,
                            contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                        ) {
                            Text(
                                text = localizedText("VPN 已连接"),
                                style = MaterialTheme.typography.labelSmall,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                            )
                        }
                        Spacer(Modifier.width(8.dp))
                    }
                    IconButton(onClick = onRefresh) {
                        Icon(
                            imageVector = Icons.Filled.Refresh,
                            contentDescription = localizedText("刷新"),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    IconButton(onClick = { expanded = !expanded }) {
                        Icon(
                            imageVector = if (expanded) {
                                Icons.Filled.KeyboardArrowUp
                            } else {
                                Icons.Filled.KeyboardArrowDown
                            },
                            contentDescription = localizedText(
                                if (expanded) "收起网络详情" else "展开网络详情"
                            ),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                AnimatedVisibility(visible = expanded) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        HorizontalDivider(
                            thickness = 0.5.dp,
                            color = MaterialTheme.colorScheme.outlineVariant
                        )
                        NetworkAddressRow(
                            label = "IPv4 地址",
                            value = snapshot.ipv4Addresses.joinToString("\n").ifEmpty { "-" }
                        )
                        NetworkAddressRow(
                            label = "IPv6 地址",
                            value = snapshot.ipv6Addresses.joinToString("\n").ifEmpty { "-" }
                        )
                        NetworkAddressRow(
                            label = "网关",
                            value = snapshot.gateway ?: "-"
                        )
                        NetworkAddressRow(
                            label = "DNS 服务器",
                            value = snapshot.dnsServers.joinToString("\n").ifEmpty { "-" }
                        )
                    }
                }
            }
        }
    )
}

@Composable
private fun NetworkAddressRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = localizedText(label),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(96.dp)
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f)
        )
        if (value != "-") {
            val context = LocalContext.current
            IconButton(onClick = {
                context.copyToClipboard(label, value)
                context.showToast(localizedText(context, "已复制到剪贴板"))
            }) {
                Icon(
                    imageVector = Icons.Filled.ContentCopy,
                    contentDescription = localizedText("复制"),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}
