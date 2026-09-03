package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.activity.compose.BackHandler
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.effect.ServiceLightEffect
import kotlinx.coroutines.launch

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
    onNavigateToRaceModeLatency: () -> Unit,
    onNavigateToHomeProviderVisibilityFromFeatureHub: () -> Unit,
    onNavigateToAbout: () -> Unit,
    onNavigateToSponsor: () -> Unit,
    onNavigateToSponsorList: () -> Unit,
    onNavigateToCoBuilderList: () -> Unit,
    onNavigateToAppUpdate: () -> Unit,
    onNavigateToDataManagement: () -> Unit,
    onNavigateToTrafficStats: () -> Unit,
    viewModel: MainViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val message by viewModel.message.collectAsStateWithLifecycle()
    var serviceLightEffectEnabled by remember {
        mutableStateOf(AppSettings.isServiceLightEffectEnabled(context))
    }
    var liquidGlassBottomBarEnabled by remember {
        mutableStateOf(AppSettings.isLiquidGlassBottomBarEnabled(context))
    }
    var showDataResetNotice by remember {
        mutableStateOf(AppSettings.isDataResetNoticePending(context))
    }
    var powerButtonCenter by remember { mutableStateOf(Offset.Zero) }
    val pagerState = rememberPagerState(initialPage = 0) { 2 }
    val coroutineScope = rememberCoroutineScope()

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                serviceLightEffectEnabled = AppSettings.isServiceLightEffectEnabled(context)
                liquidGlassBottomBarEnabled = AppSettings.isLiquidGlassBottomBarEnabled(context)
                showDataResetNotice = AppSettings.isDataResetNoticePending(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(message) {
        message?.let {
            Toast.makeText(context, localizedText(context, it), Toast.LENGTH_SHORT).show()
            viewModel.clearMessage()
        }
    }

    BackHandler(enabled = pagerState.currentPage == 1) {
        coroutineScope.launch {
            pagerState.animateScrollToPage(
                page = 0,
                animationSpec = tween(durationMillis = 280)
            )
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        ServiceLightEffect(
            visible = serviceLightEffectEnabled && uiState.isRunning,
            revealOrigin = powerButtonCenter,
            modifier = Modifier.fillMaxSize()
        )
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                TopAppBar(
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = Color.Transparent,
                        scrolledContainerColor = Color.Transparent
                    ),
                    title = {
                        Text(if (pagerState.currentPage == 0) localizedText("谛听") else localizedText("功能中心"))
                    }
                )
            }
        ) { innerPadding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(top = innerPadding.calculateTopPadding())
            ) {
                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize()
                ) { page ->
                    if (page == 0) {
                        MainContent(
                            uiState = uiState,
                            onToggle = { onToggle(uiState.isRunning) },
                            onPowerButtonCenterChanged = { powerButtonCenter = it },
                            onNavigateToProviderManagement = onNavigateToProviderManagement,
                            onNavigateToHomeProviderVisibility = onNavigateToHomeProviderVisibility,
                            onNavigateToRaceModeSettings = onNavigateToRaceModeSettings,
                            showDataResetNotice = showDataResetNotice,
                            onDismissDataResetNotice = {
                                AppSettings.dismissDataResetNotice(context)
                                showDataResetNotice = false
                            },
                            viewModel = viewModel
                        )
                    } else {
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
                            onNavigateToRaceModeLatency = onNavigateToRaceModeLatency,
                            onNavigateToHomeProviderVisibility = onNavigateToHomeProviderVisibilityFromFeatureHub,
                            onNavigateToAbout = onNavigateToAbout,
                            onNavigateToSponsor = onNavigateToSponsor,
                            onNavigateToSponsorList = onNavigateToSponsorList,
                            onNavigateToCoBuilderList = onNavigateToCoBuilderList,
                            onNavigateToAppUpdate = onNavigateToAppUpdate,
                            onNavigateToDataManagement = onNavigateToDataManagement,
                            onNavigateToTrafficStats = onNavigateToTrafficStats
                        )
                    }
                }

                FloatingNavigationBar(
                    currentPage = pagerState.currentPage,
                    onPageSelected = { targetPage ->
                        if (pagerState.currentPage != targetPage) {
                            coroutineScope.launch {
                                pagerState.animateScrollToPage(
                                    page = targetPage,
                                    animationSpec = tween(durationMillis = 280)
                                )
                            }
                        }
                    },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                        .padding(bottom = 16.dp),
                    isGlassEnabled = liquidGlassBottomBarEnabled,
                    pagerProgress = { pagerState.currentPage + pagerState.currentPageOffsetFraction }
                )
            }
        }
    }
}
