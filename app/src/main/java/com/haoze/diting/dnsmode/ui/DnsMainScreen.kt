package com.haoze.diting.dnsmode.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.haoze.diting.dnsmode.ui.navigation.DnsNavTab
import com.haoze.diting.dnsmode.viewmodel.DnsMainViewModel
import com.haoze.diting.ui.FloatingNavigationBar
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.localizedText
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DnsMainScreen(
    viewModel: DnsMainViewModel,
    onSwitchToNormalMode: () -> Unit,
    onSelectMode: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val tabs = remember { DnsNavTab.entries }
    val pagerState = rememberPagerState(initialPage = 0) { tabs.size }
    val coroutineScope = rememberCoroutineScope()
    val pageAlpha = remember { Animatable(1f) }
    var pageSwitchJob by remember { mutableStateOf<Job?>(null) }
    var showSwitchConfirmDialog by remember { mutableStateOf(false) }

    val navigateToPage: (Int) -> Unit = { targetPage ->
        if (pagerState.currentPage != targetPage) {
            pageSwitchJob?.cancel()
            pageSwitchJob = coroutineScope.launch {
                try {
                    pageAlpha.animateTo(
                        targetValue = 0f,
                        animationSpec = tween(durationMillis = 90, easing = LinearEasing)
                    )
                    pagerState.scrollToPage(targetPage)
                    pageAlpha.animateTo(
                        targetValue = 1f,
                        animationSpec = tween(durationMillis = 150, easing = FastOutSlowInEasing)
                    )
                } finally {
                    pageAlpha.snapTo(1f)
                }
            }
        }
    }

    BackHandler(enabled = pagerState.currentPage != 0) {
        coroutineScope.launch {
            pagerState.animateScrollToPage(
                page = 0,
                animationSpec = tween(durationMillis = 280)
            )
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            topBar = {
                val currentTab = tabs.getOrElse(pagerState.currentPage) { DnsNavTab.HOME }
                TopAppBar(
                    title = {
                        Text(
                            text = if (currentTab == DnsNavTab.HOME) {
                                localizedText("谛听 · DNS模式")
                            } else {
                                localizedText(currentTab.title)
                            }
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
                        scrolledContainerColor = Color.Transparent,
                        titleContentColor = MaterialTheme.colorScheme.onSurface
                    )
                )
            },
            containerColor = Color.Transparent
        ) { innerPadding ->
            HorizontalPager(
                state = pagerState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(top = innerPadding.calculateTopPadding())
                    .graphicsLayer { alpha = pageAlpha.value },
                beyondViewportPageCount = (tabs.size - 1).coerceAtLeast(1)
            ) { page ->
                when (tabs.getOrNull(page)) {
                    DnsNavTab.HOME -> DnsHomeScreen(
                        status = uiState.status,
                        activeUpstream = uiState.activeUpstream,
                        stats = uiState.stats,
                        onToggleService = viewModel::toggleService,
                        onNavigateToServers = { navigateToPage(DnsNavTab.SERVERS.ordinal) },
                        onSwitchToNormalMode = { showSwitchConfirmDialog = true },
                        onSelectMode = onSelectMode,
                        contentBottomPadding = 108.dp
                    )
                    DnsNavTab.SERVERS -> DnsServersScreen(
                        upstreams = uiState.upstreams,
                        selectedUpstreamId = uiState.config.selectedUpstreamId,
                        onSelectUpstream = viewModel::selectUpstream,
                        contentBottomPadding = 108.dp
                    )
                    DnsNavTab.SETTINGS -> DnsSettingsScreen(
                        config = uiState.config,
                        onUpdateConfig = viewModel::updateConfig,
                        onResetStats = viewModel::resetStats,
                        onSwitchToNormalMode = { showSwitchConfirmDialog = true },
                        onSelectMode = onSelectMode,
                        contentBottomPadding = 108.dp
                    )
                    null -> Unit
                }
            }
        }

        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            FloatingNavigationBar(
                selectedPage = pagerState.currentPage,
                onPageSelected = navigateToPage,
                items = tabs,
                pagerProgress = { pagerState.currentPage + pagerState.currentPageOffsetFraction }
            )
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

