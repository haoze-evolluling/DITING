package com.haoze.diting.express.ui

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
import androidx.compose.runtime.mutableLongStateOf
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
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.diting.express.ExpressVpnController
import com.haoze.diting.ui.FloatingNavigationBar
import com.haoze.diting.ui.MainViewModel
import com.haoze.diting.ui.Routes
import com.haoze.diting.ui.SettingsScreen
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.settings.SystemSettingsStore
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme

/**
 * Main container screen for Express Mode.
 *
 * Hosts dedicated Express Home, Feature Hub, Log Dashboard, and Settings tabs
 * while binding VPN status directly to [ExpressVpnController.isRunning].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpressMainScreen(
    onToggle: (isRunning: Boolean) -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToLogs: () -> Unit,
    onNavigateToProviderManagement: () -> Unit,
    onNavigateToBootstrapSettings: () -> Unit,
    onNavigateToHomeProviderVisibility: () -> Unit,
    onNavigateToRaceModeSettings: () -> Unit,
    onNavigateToAppearanceSettings: () -> Unit,
    onNavigateToRuleControl: () -> Unit,
    onNavigateToBlacklist: () -> Unit,
    onNavigateToWhitelist: () -> Unit,
    onNavigateToLogRetentionSettings: () -> Unit,
    onNavigateToHomeProviderVisibilityFromFeatureHub: () -> Unit = onNavigateToHomeProviderVisibility,
    onNavigateToAbout: () -> Unit,
    onNavigateToSponsor: () -> Unit,
    onNavigateToSponsorList: () -> Unit,
    onNavigateToCoBuilderList: () -> Unit,
    onNavigateToAppUpdate: () -> Unit,
    onNavigateToDataManagement: () -> Unit,
    onNavigateToHiddenFeatures: () -> Unit = {},
    onNavigateToCacheSettings: () -> Unit = {},
    onNavigateToDataCleanup: () -> Unit = {},
    onNavigateToLogRoute: (String) -> Unit = { onNavigateToLogs() },
    onNavigateToSettingsRoute: (String) -> Unit = { onNavigateToSettings() },
    onNavigateToModeSelection: () -> Unit = {},
    resetToHomeTrigger: Long = 0L,
    bottomBarRefreshRequested: Boolean = false,
    onBottomBarRefreshConsumed: () -> Unit = {},
    viewModel: MainViewModel = viewModel()
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var showDataResetNotice by remember {
        mutableStateOf(SystemSettingsStore.isDataResetNoticePending(context))
    }
    var bottomBarItems by remember {
        mutableStateOf(ExpressBottomBarDestination.getDestinations(context))
    }
    val pagerState = rememberPagerState(initialPage = 0) { bottomBarItems.size }
    val coroutineScope = rememberCoroutineScope()
    val pageAlpha = remember { Animatable(1f) }
    var pageSwitchJob by remember { mutableStateOf<Job?>(null) }
    var logDashboardRefreshTrigger by remember { mutableLongStateOf(0L) }

    LaunchedEffect(bottomBarRefreshRequested) {
        if (bottomBarRefreshRequested) {
            bottomBarItems = ExpressBottomBarDestination.getDestinations(context)
            onBottomBarRefreshConsumed()
        }
    }

    LaunchedEffect(resetToHomeTrigger) {
        if (resetToHomeTrigger > 0L && pagerState.currentPage != 0) {
            pagerState.scrollToPage(0)
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
                bottomBarItems = ExpressBottomBarDestination.getDestinations(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    BackHandler(enabled = pagerState.currentPage != 0) {
        coroutineScope.launch {
            pagerState.animateScrollToPage(page = 0, animationSpec = tween(durationMillis = 280))
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = pageAlpha.value },
            beyondViewportPageCount = (bottomBarItems.size - 1).coerceAtLeast(1)
        ) { page ->
            when (bottomBarItems.getOrNull(page)) {
                ExpressBottomBarDestination.HOME -> {
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
                                    Text(localizedText("谛听") + " · " + localizedText("极速"))
                                },
                                actions = {
                                    IconButton(onClick = onNavigateToModeSelection) {
                                        Icon(
                                            imageVector = Icons.Default.SwapHoriz,
                                            contentDescription = localizedText("模式切换"),
                                            tint = MaterialTheme.colorScheme.onSurface
                                        )
                                    }
                                }
                            )
                        }
                    ) { innerPadding ->
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(top = innerPadding.calculateTopPadding())
                        ) {
                            ExpressHomeContent(
                                onToggle = onToggle,
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
                ExpressBottomBarDestination.FEATURE_HUB -> {
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
                            ExpressFeatureHubScreen(
                                onNavigateToProviderManagement = onNavigateToProviderManagement,
                                onNavigateToBootstrapSettings = onNavigateToBootstrapSettings,
                                onNavigateToAppearanceSettings = onNavigateToAppearanceSettings,
                                onNavigateToRuleControl = onNavigateToRuleControl,
                                onNavigateToBlacklist = onNavigateToBlacklist,
                                onNavigateToWhitelist = onNavigateToWhitelist,
                                onNavigateToLogs = onNavigateToLogs,
                                onNavigateToSettings = onNavigateToSettings,
                                onNavigateToLogRetentionSettings = onNavigateToLogRetentionSettings,
                                onNavigateToHomeProviderVisibility = onNavigateToHomeProviderVisibilityFromFeatureHub,
                                onNavigateToAbout = onNavigateToAbout,
                                onNavigateToSponsor = onNavigateToSponsor,
                                onNavigateToSponsorList = onNavigateToSponsorList,
                                onNavigateToCoBuilderList = onNavigateToCoBuilderList,
                                onNavigateToAppUpdate = onNavigateToAppUpdate,
                                onNavigateToDataManagement = onNavigateToDataManagement,
                                onNavigateToHiddenFeatures = onNavigateToHiddenFeatures,
                                onNavigateToCacheSettings = onNavigateToCacheSettings,
                                onNavigateToRaceModeSettings = onNavigateToRaceModeSettings,
                                onNavigateToDataCleanup = onNavigateToDataCleanup
                            )
                        }
                    }
                }
                ExpressBottomBarDestination.LOG_DASHBOARD -> {
                    ExpressLogDashboardScreen(
                        onBack = {},
                        onNavigateToDnsLogs = { onNavigateToLogRoute(Routes.DNS_LOGS) },
                        onNavigateToDnsCache = { onNavigateToLogRoute(Routes.DNS_CACHE) },
                        onNavigateToRaceStats = { onNavigateToLogRoute(Routes.RACE_STATS) },
                        onNavigateToBootstrapStats = { onNavigateToLogRoute(Routes.BOOTSTRAP_STATS) },
                        onNavigateToSubscriptionInterceptionStats = { onNavigateToLogRoute(Routes.SUBSCRIPTION_INTERCEPTION_STATS) },
                        showBackIcon = false,
                        contentBottomPadding = 108.dp,
                        isActive = pagerState.currentPage == page,
                        refreshTrigger = logDashboardRefreshTrigger
                    )
                }
                ExpressBottomBarDestination.SETTINGS -> {
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
                                pageAlpha.animateTo(0f, animationSpec = tween(durationMillis = 90, easing = LinearEasing))
                                pagerState.scrollToPage(targetPage)
                                pageAlpha.animateTo(1f, animationSpec = tween(durationMillis = 150, easing = FastOutSlowInEasing))
                            } finally {
                                pageAlpha.snapTo(1f)
                            }
                        }
                    } else if (bottomBarItems.getOrNull(targetPage) == ExpressBottomBarDestination.LOG_DASHBOARD) {
                        logDashboardRefreshTrigger++
                    }
                },
                items = bottomBarItems,
                pagerProgress = { pagerState.currentPage + pagerState.currentPageOffsetFraction }
            )
        }
    }
}
