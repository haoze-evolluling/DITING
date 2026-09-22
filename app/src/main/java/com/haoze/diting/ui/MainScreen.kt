package com.haoze.diting.ui

import android.widget.Toast
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.ui.traffic.AppTrafficStatsScreen
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.draw.clip

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    onToggle: (isRunning: Boolean) -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToLogs: () -> Unit,
    onNavigateToProviderManagement: () -> Unit,
    onNavigateToBootstrapSettings: () -> Unit,
    onNavigateToHomeProviderVisibility: () -> Unit,
    onNavigateToRaceModeSettings: () -> Unit,
    onNavigateToBlockedApps: () -> Unit,
    onNavigateToAppAllowlist: () -> Unit,
    onNavigateToExcludedApps: () -> Unit,
    onNavigateToAppearanceSettings: () -> Unit,
    onNavigateToRuleControl: () -> Unit,
    onNavigateToBlacklist: () -> Unit,
    onNavigateToWhitelist: () -> Unit,
    onNavigateToRewriteList: () -> Unit,
    onNavigateToAppRules: () -> Unit,
    onNavigateToHttpInspection: () -> Unit,
    onNavigateToLogRetentionSettings: () -> Unit,
    onNavigateToNetworkTools: () -> Unit,
    onNavigateToHomeProviderVisibilityFromFeatureHub: () -> Unit,
    onNavigateToAbout: () -> Unit,
    onNavigateToSponsor: () -> Unit,
    onNavigateToSponsorList: () -> Unit,
    onNavigateToCoBuilderList: () -> Unit,
    onNavigateToAppUpdate: () -> Unit,
    onNavigateToDataManagement: () -> Unit,
    onNavigateToTrafficStats: () -> Unit,
    onNavigateToOptionalFeatures: () -> Unit = {},
    onNavigateToOutboundProxy: () -> Unit = {},
    onNavigateToDataCleanup: () -> Unit = {},
    onNavigateToAgentApiSettings: () -> Unit = {},
    onNavigateToLogRoute: (String) -> Unit = { onNavigateToLogs() },
    onNavigateToSettingsRoute: (String) -> Unit = { onNavigateToSettings() },
    bottomBarRefreshRequested: Boolean = false,
    onBottomBarRefreshConsumed: () -> Unit = {},
    viewModel: MainViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val message by viewModel.message.collectAsStateWithLifecycle()
    var showDataResetNotice by remember {
        mutableStateOf(SystemSettingsStore.isDataResetNoticePending(context))
    }
    var bottomBarItems by remember {
        mutableStateOf(AppearanceSettingsStore.getBottomBarDestinations(context))
    }
    val pagerState = rememberPagerState(initialPage = 0) { bottomBarItems.size }
    val coroutineScope = rememberCoroutineScope()
    val pageAlpha = remember { Animatable(1f) }
    var pageSwitchJob by remember { mutableStateOf<Job?>(null) }

    LaunchedEffect(bottomBarRefreshRequested) {
        if (bottomBarRefreshRequested) {
            bottomBarItems = AppearanceSettingsStore.getBottomBarDestinations(context)
            onBottomBarRefreshConsumed()
        }
    }

    LaunchedEffect(bottomBarItems.size) {
        if (pagerState.currentPage >= bottomBarItems.size) {
            pagerState.scrollToPage(0)
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                showDataResetNotice = SystemSettingsStore.isDataResetNoticePending(context)
                bottomBarItems = AppearanceSettingsStore.getBottomBarDestinations(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(message) {
        message?.let {
            context.showToast(it, Toast.LENGTH_SHORT)
            viewModel.clearMessage()
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

    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = pageAlpha.value },
            beyondViewportPageCount = (bottomBarItems.size - 1).coerceAtLeast(1)
        ) { page ->
            when (bottomBarItems.getOrNull(page)) {
                BottomBarDestination.HOME -> {
                    Scaffold(
                        modifier = Modifier.fillMaxSize(),
                        containerColor = Color.Transparent,
                        topBar = {
                            TopAppBar(
                                colors = TopAppBarDefaults.topAppBarColors(
                                    containerColor = Color.Transparent,
                                    scrolledContainerColor = Color.Transparent
                                ),
                                title = {
                                    Text(localizedText("谛听"))
                                }
                            )
                        }
                    ) { innerPadding ->
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(top = innerPadding.calculateTopPadding())
                        ) {
                            MainContent(
                                uiState = uiState,
                                onToggle = { onToggle(uiState.isRunning) },
                                onNavigateToProviderManagement = onNavigateToProviderManagement,
                                onNavigateToHomeProviderVisibility = onNavigateToHomeProviderVisibility,
                                onNavigateToRaceModeSettings = onNavigateToRaceModeSettings,
                                showDataResetNotice = showDataResetNotice,
                                onDismissDataResetNotice = {
                                    SystemSettingsStore.dismissDataResetNotice(context)
                                    showDataResetNotice = false
                                },
                                viewModel = viewModel
                            )
                        }
                    }
                }
                BottomBarDestination.FEATURE_HUB -> {
                    Scaffold(
                        modifier = Modifier.fillMaxSize(),
                        containerColor = Color.Transparent,
                        topBar = {
                            TopAppBar(
                                colors = TopAppBarDefaults.topAppBarColors(
                                    containerColor = Color.Transparent,
                                    scrolledContainerColor = Color.Transparent
                                ),
                                title = {
                                    Text(localizedText("功能中心"))
                                }
                            )
                        }
                    ) { innerPadding ->
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(top = innerPadding.calculateTopPadding())
                        ) {
                            FeatureHubScreen(
                                onNavigateToProviderManagement = onNavigateToProviderManagement,
                                onNavigateToBootstrapSettings = onNavigateToBootstrapSettings,
                                onNavigateToBlockedApps = onNavigateToBlockedApps,
                                onNavigateToAppAllowlist = onNavigateToAppAllowlist,
                                onNavigateToExcludedApps = onNavigateToExcludedApps,
                                onNavigateToAppearanceSettings = onNavigateToAppearanceSettings,
                                onNavigateToRuleControl = onNavigateToRuleControl,
                                onNavigateToBlacklist = onNavigateToBlacklist,
                                onNavigateToWhitelist = onNavigateToWhitelist,
                                onNavigateToRewriteList = onNavigateToRewriteList,
                                onNavigateToAppRules = onNavigateToAppRules,
                                onNavigateToHttpInspection = onNavigateToHttpInspection,
                                onNavigateToLogs = onNavigateToLogs,
                                onNavigateToSettings = onNavigateToSettings,
                                onNavigateToLogRetentionSettings = onNavigateToLogRetentionSettings,
                                onNavigateToNetworkTools = onNavigateToNetworkTools,
                                onNavigateToHomeProviderVisibility = onNavigateToHomeProviderVisibilityFromFeatureHub,
                                onNavigateToAbout = onNavigateToAbout,
                                onNavigateToSponsor = onNavigateToSponsor,
                                onNavigateToSponsorList = onNavigateToSponsorList,
                                onNavigateToCoBuilderList = onNavigateToCoBuilderList,
                                onNavigateToAppUpdate = onNavigateToAppUpdate,
                                onNavigateToDataManagement = onNavigateToDataManagement,
                                onNavigateToTrafficStats = onNavigateToTrafficStats,
                                onNavigateToOptionalFeatures = onNavigateToOptionalFeatures,
                                onNavigateToOutboundProxy = onNavigateToOutboundProxy,
                                onNavigateToRaceModeSettings = onNavigateToRaceModeSettings,
                                onNavigateToDataCleanup = onNavigateToDataCleanup,
                                onNavigateToAgentApiSettings = onNavigateToAgentApiSettings
                            )
                        }
                    }
                }
                BottomBarDestination.LOG_DASHBOARD -> {
                    ModernLogDashboardScreen(
                        onBack = {},
                        onNavigateToDnsLogs = { onNavigateToLogRoute(Routes.DNS_LOGS) },
                        onNavigateToDnsCache = { onNavigateToLogRoute(Routes.DNS_CACHE) },
                        onNavigateToRaceStats = { onNavigateToLogRoute(Routes.RACE_STATS) },
                        onNavigateToBootstrapStats = { onNavigateToLogRoute(Routes.BOOTSTRAP_STATS) },
                        onNavigateToSubscriptionInterceptionStats = { onNavigateToLogRoute(Routes.SUBSCRIPTION_INTERCEPTION_STATS) },
                        onNavigateToTrafficStats = onNavigateToTrafficStats,
                        showBackIcon = false,
                        contentBottomPadding = 108.dp
                    )
                }
                BottomBarDestination.APP_TRAFFIC_STATS -> {
                    AppTrafficStatsScreen(
                        onBack = {},
                        showBackIcon = false,
                        contentBottomPadding = 108.dp
                    )
                }
                BottomBarDestination.NETWORK_TOOLS -> {
                    NetworkToolsScreen(
                        onBack = {},
                        showBackIcon = false,
                        contentBottomPadding = 108.dp
                    )
                }
                BottomBarDestination.SETTINGS -> {
                    SettingsScreen(
                        onBack = {},
                        onNavigateToRoute = onNavigateToSettingsRoute,
                        showBackIcon = false,
                        contentBottomPadding = 108.dp
                    )
                }
                null -> Unit
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
                onPageSelected = { targetPage ->
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
                },
                items = bottomBarItems,
                pagerProgress = { pagerState.currentPage + pagerState.currentPageOffsetFraction }
            )
        }
    }
}
