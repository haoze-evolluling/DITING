package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Policy
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.filled.Update
import androidx.compose.material.icons.automirrored.filled.Rule
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.effect.ServiceLightEffect
import com.haoze.dnssr.vpn.DnsProvider

private const val MANAGE_PROVIDER_ID = "__manage__"
private const val PROVIDER_VISIBILITY_ID = "__provider_visibility__"

internal fun raceProviderSummary(providerNames: List<String>): String {
    if (providerNames.isEmpty()) return "未选择服务商"
    val names = providerNames.take(2).joinToString("、")
    val suffix = if (providerNames.size > 2) " 等" else ""
    return "已选 ${providerNames.size} 个：$names$suffix"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    onToggle: (isRunning: Boolean) -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToLogs: () -> Unit,
    onNavigateToProviderManagement: () -> Unit,
    onNavigateToHomeProviderVisibility: () -> Unit,
    onNavigateToRaceModeSettings: () -> Unit,
    onNavigateToBlockedApps: () -> Unit,
    onNavigateToAppAllowlist: () -> Unit,
    onNavigateToAppearanceSettings: () -> Unit,
    onNavigateToDnsRuleManagement: () -> Unit,
    onNavigateToHttpsRuleManagement: () -> Unit,
    onNavigateToHttpInspection: () -> Unit,
    onNavigateToLogRetentionSettings: () -> Unit,
    onNavigateToRaceModeLatency: () -> Unit,
    onNavigateToHomeProviderVisibilityFromFeatureHub: () -> Unit,
    onNavigateToAbout: () -> Unit,
    onNavigateToSponsor: () -> Unit,
    onNavigateToSponsorList: () -> Unit,
    onNavigateToCoBuilderList: () -> Unit,
    onNavigateToAppUpdate: () -> Unit,
    viewModel: MainViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val message by viewModel.message.collectAsStateWithLifecycle()
    var serviceLightEffectEnabled by remember {
        mutableStateOf(AppSettings.isServiceLightEffectEnabled(context))
    }
    var hideGoTunnelDisableButtonWhenInactive by remember {
        mutableStateOf(AppSettings.shouldHideGoTunnelDisableButtonWhenInactive(context))
    }
    var goTunnelRequired by remember { mutableStateOf(AppSettings.isGoTunnelRequired(context)) }
    var goTunnelReasons by remember { mutableStateOf(AppSettings.getGoTunnelReasons(context)) }
    var showGoTunnelInfo by remember { mutableStateOf(false) }
    var powerButtonCenter by remember { mutableStateOf(Offset.Unspecified) }
    val pagerState = rememberPagerState(initialPage = 1) { 2 }
    val coroutineScope = rememberCoroutineScope()

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                serviceLightEffectEnabled = AppSettings.isServiceLightEffectEnabled(context)
                hideGoTunnelDisableButtonWhenInactive =
                    AppSettings.shouldHideGoTunnelDisableButtonWhenInactive(context)
                goTunnelRequired = AppSettings.isGoTunnelRequired(context)
                goTunnelReasons = AppSettings.getGoTunnelReasons(context)
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
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(localizedText("谛听"))
                        if (goTunnelRequired) {
                            IconButton(
                                onClick = { showGoTunnelInfo = true },
                                modifier = Modifier.size(40.dp)
                            ) {
                                Icon(
                                    painter = painterResource(R.drawable.ic_google_g),
                                    contentDescription = localizedText("查看 Go 隧道限制"),
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        }
                    }
                },
                actions = {
                    IconButton(
                        onClick = {
                            coroutineScope.launch {
                                pagerState.animateScrollToPage(
                                    page = 0,
                                    animationSpec = tween(durationMillis = 280)
                                )
                            }
                        }
                    ) {
                        Icon(
                            imageVector = Icons.Default.Apps,
                            contentDescription = localizedText("功能中心")
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        HorizontalPager(
            state = pagerState,
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) { page ->
            if (page == 1) {
                MainContent(
                    uiState = uiState,
                    onToggle = { onToggle(uiState.isRunning) },
                    onPowerButtonCenterChanged = { powerButtonCenter = it },
                    onNavigateToProviderManagement = onNavigateToProviderManagement,
                    onNavigateToHomeProviderVisibility = onNavigateToHomeProviderVisibility,
                    onNavigateToRaceModeSettings = onNavigateToRaceModeSettings,
                    hideGoTunnelDisableButtonWhenInactive = hideGoTunnelDisableButtonWhenInactive,
                    goTunnelRequired = goTunnelRequired,
                    goTunnelReasons = goTunnelReasons,
                    onGoTunnelDisabled = {
                        goTunnelRequired = false
                        goTunnelReasons = emptySet()
                    },
                    viewModel = viewModel
                )
            } else {
                FeatureHubScreen(
                    onNavigateToBlockedApps = onNavigateToBlockedApps,
                    onNavigateToAppAllowlist = onNavigateToAppAllowlist,
                    onNavigateToAppearanceSettings = onNavigateToAppearanceSettings,
                    onNavigateToDnsRuleManagement = onNavigateToDnsRuleManagement,
                    onNavigateToHttpsRuleManagement = onNavigateToHttpsRuleManagement,
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
                    onNavigateToAppUpdate = onNavigateToAppUpdate
                )
            }
        }
    }
    if (showGoTunnelInfo) {
        AlertDialog(
            onDismissRequest = { showGoTunnelInfo = false },
            title = { Text(localizedText("Go 隧道已启用")) },
            text = {
                Text(
                    localizedText(context, "Go 隧道用于在本机 VPN 中接管 TCP、UDP、DNS 和 HTTP(S) 流量，使谛听能识别应用连接。") +
                        "\n\n" + localizedText(context, "当前触发功能：") + "\n" +
                        goTunnelReasons.joinToString("\n") { "• ${localizedText(context, it.displayName)}" } +
                        "\n\n" + localizedText(context, "启用期间，智能选择和最快响应解析模式不可用，只能使用单一服务或依次尝试模式。")
                )
            },
            confirmButton = {
                TextButton(onClick = { showGoTunnelInfo = false }) {
                    Text(localizedText(context, "知道了"))
                }
            }
        )
    }
    }
}

private data class FeatureHubItem(
    val title: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val onClick: () -> Unit,
    val onLongClick: (() -> Unit)? = null
)

private data class FeatureHubCategory(
    val title: String,
    val items: List<FeatureHubItem>
)

@Composable
private fun FeatureHubScreen(
    onNavigateToBlockedApps: () -> Unit,
    onNavigateToAppAllowlist: () -> Unit,
    onNavigateToAppearanceSettings: () -> Unit,
    onNavigateToDnsRuleManagement: () -> Unit,
    onNavigateToHttpsRuleManagement: () -> Unit,
    onNavigateToHttpInspection: () -> Unit,
    onNavigateToLogs: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToLogRetentionSettings: () -> Unit,
    onNavigateToRaceModeLatency: () -> Unit,
    onNavigateToHomeProviderVisibility: () -> Unit,
    onNavigateToAbout: () -> Unit,
    onNavigateToSponsor: () -> Unit,
    onNavigateToSponsorList: () -> Unit,
    onNavigateToCoBuilderList: () -> Unit,
    onNavigateToAppUpdate: () -> Unit
) {
    val context = LocalContext.current
    var showLogLongPressHint by remember {
        mutableStateOf(!AppSettings.isSettingsGuideAcknowledged(context, SettingsGuides.HOME_LOG_LONG_PRESS_ID))
    }
    val categories = listOf(
        FeatureHubCategory(
            stringResource(R.string.feature_hub_network_control),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_app_allowlist), Icons.Filled.Policy, onNavigateToAppAllowlist),
                FeatureHubItem(stringResource(R.string.feature_hub_blocked_apps), Icons.Filled.WifiOff, onNavigateToBlockedApps)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_policies_rules),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_https_inspection), Icons.Filled.Policy, onNavigateToHttpInspection),
                FeatureHubItem(stringResource(R.string.feature_hub_speed_test), Icons.Filled.Speed, onNavigateToRaceModeLatency),
                FeatureHubItem(stringResource(R.string.feature_hub_https_rules), Icons.Filled.Policy, onNavigateToHttpsRuleManagement),
                FeatureHubItem(stringResource(R.string.feature_hub_dns_rules), Icons.AutoMirrored.Filled.Rule, onNavigateToDnsRuleManagement)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_interface_management),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_appearance), Icons.Filled.Palette, onNavigateToAppearanceSettings),
                FeatureHubItem(stringResource(R.string.feature_hub_service_display), Icons.Filled.Visibility, onNavigateToHomeProviderVisibility),
                FeatureHubItem(
                    title = stringResource(R.string.feature_hub_logs),
                    icon = Icons.Filled.History,
                    onClick = onNavigateToLogs,
                    onLongClick = {
                        AppSettings.acknowledgeSettingsGuide(context, SettingsGuides.HOME_LOG_LONG_PRESS_ID)
                        showLogLongPressHint = false
                        onNavigateToLogRetentionSettings()
                    }
                ),
                FeatureHubItem(stringResource(R.string.feature_hub_other_settings), Icons.Filled.Settings, onNavigateToSettings)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_about_app),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_app_info), Icons.Filled.Info, onNavigateToAbout),
                FeatureHubItem(stringResource(R.string.feature_hub_sponsor), Icons.Filled.Favorite, onNavigateToSponsor),
                FeatureHubItem(stringResource(R.string.feature_hub_sponsor_list), Icons.Filled.WorkspacePremium, onNavigateToSponsorList),
                FeatureHubItem(stringResource(R.string.feature_hub_contributors), Icons.Filled.Groups, onNavigateToCoBuilderList),
                FeatureHubItem(stringResource(R.string.feature_hub_updates_support), Icons.Filled.Update, onNavigateToAppUpdate)
            )
        )
    )

    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 24.dp, top = 20.dp, end = 24.dp, bottom = 48.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        categories.forEach { category ->
            item(span = { GridItemSpan(maxLineSpan) }) {
                Text(
                    text = category.title,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            items(category.items.size) { index ->
                val item = category.items[index]
                Card(
                    shape = SettingsCornerShape,
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(SettingsCornerShape)
                        .combinedClickable(
                            onClick = item.onClick,
                            onLongClick = item.onLongClick
                        )
                        .heightIn(min = 80.dp)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Box(modifier = Modifier.fillMaxWidth()) {
                            Icon(
                                imageVector = item.icon,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(24.dp)
                            )
                            if (item.title == stringResource(R.string.feature_hub_logs) && showLogLongPressHint) {
                                Text(
                                    text = stringResource(R.string.feature_hub_long_press_hint),
                                    style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .combinedClickable(
                                            onClick = {},
                                            onLongClick = { item.onLongClick?.invoke() }
                                        )
                                )
                            }
                        }
                        Text(text = item.title, style = MaterialTheme.typography.titleSmall)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainContent(
    uiState: MainUiState,
    onToggle: () -> Unit,
    onPowerButtonCenterChanged: (Offset) -> Unit,
    onNavigateToProviderManagement: () -> Unit,
    onNavigateToHomeProviderVisibility: () -> Unit,
    onNavigateToRaceModeSettings: () -> Unit,
    hideGoTunnelDisableButtonWhenInactive: Boolean,
    goTunnelRequired: Boolean,
    goTunnelReasons: Set<GoTunnelReason>,
    onGoTunnelDisabled: () -> Unit,
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val context = LocalContext.current
    val providers by viewModel.providers.collectAsStateWithLifecycle()
    val selectedProvider by viewModel.selectedProvider.collectAsStateWithLifecycle()
    val raceModeEnabled by viewModel.raceModeEnabled.collectAsStateWithLifecycle()
    val resolutionMode by viewModel.resolutionMode.collectAsStateWithLifecycle()
    val raceProviderIds by viewModel.raceProviderIds.collectAsStateWithLifecycle()
    val homeProviderVisibility by viewModel.homeProviderVisibility.collectAsStateWithLifecycle()
    var powerButtonOpacity by remember { mutableStateOf(AppSettings.getHomePowerButtonOpacity(context)) }
    var providerSelectorOpacity by remember { mutableStateOf(AppSettings.getHomeProviderSelectorOpacity(context)) }
    var modeButtonOpacity by remember { mutableStateOf(AppSettings.getHomeModeButtonOpacity(context)) }
    var poemOpacity by remember { mutableStateOf(AppSettings.getHomePoemOpacity(context)) }
    var dnsDetailOpacity by remember { mutableStateOf(AppSettings.getHomeDnsDetailOpacity(context)) }
    var runningSentence by remember { mutableStateOf(AppSettings.getHomeSentenceRunning(context)) }
    var stoppedSentence by remember { mutableStateOf(AppSettings.getHomeSentenceStopped(context)) }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.loadProviders()
                powerButtonOpacity = AppSettings.getHomePowerButtonOpacity(context)
                providerSelectorOpacity = AppSettings.getHomeProviderSelectorOpacity(context)
                modeButtonOpacity = AppSettings.getHomeModeButtonOpacity(context)
                poemOpacity = AppSettings.getHomePoemOpacity(context)
                dnsDetailOpacity = AppSettings.getHomeDnsDetailOpacity(context)
                runningSentence = AppSettings.getHomeSentenceRunning(context)
                stoppedSentence = AppSettings.getHomeSentenceStopped(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    val raceProviders = providers.filter { it.id in raceProviderIds }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp)
            .padding(bottom = 48.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(modifier = Modifier.alpha(powerButtonOpacity)) {
            PowerToggleButton(
                isRunning = uiState.isRunning,
                isBusy = uiState.isBusy,
                enabled = !uiState.isBusy && selectedProvider != null &&
                    (resolutionMode == DnsResolutionMode.SINGLE || raceProviderIds.size >= 2),
                onCenterChanged = onPowerButtonCenterChanged,
                onToggle = onToggle
            )
        }

        val homeSentence = if (uiState.isRunning) runningSentence else stoppedSentence
        if (homeSentence.isNotEmpty()) {
            Text(
                text = localizedText(homeSentence),
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 20.dp, bottom = 24.dp)
                    .alpha(poemOpacity)
            )
        } else {
            Spacer(modifier = Modifier.padding(vertical = 12.dp))
        }

        val filteredProviders = providers.filter(homeProviderVisibility::isVisible)
        val manageProviderName = localizedText("管理服务...")
        val providerVisibilityName = localizedText("服务显示...")
        val displayProviders = buildList {
            selectedProvider?.takeIf { selected -> filteredProviders.none { it.id == selected.id } }?.let(::add)
            addAll(filteredProviders)
            add(DnsProvider(id = MANAGE_PROVIDER_ID, name = manageProviderName, isPreset = true))
            add(DnsProvider(id = PROVIDER_VISIBILITY_ID, name = providerVisibilityName, isPreset = true))
        }
        val selectedIndex = displayProviders.indexOfFirst { it.id == selectedProvider?.id }
            .coerceAtLeast(0)
        val raceDisplayValue = localizedText(raceProviderSummary(raceProviders.map { localizedText(it.name) }))
        var showProviderDialog by remember { mutableStateOf(false) }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .animateContentSize(animationSpec = tween(180))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
                    .alpha(providerSelectorOpacity)
            ) {
                Crossfade(
                    targetState = resolutionMode != DnsResolutionMode.SINGLE,
                    animationSpec = tween(160),
                    label = "RaceModeProviderContent"
                ) { enabled ->
                    if (enabled) {
                        OutlinedTextField(
                            value = raceDisplayValue,
                            onValueChange = {},
                            readOnly = true,
                            enabled = true,
                            singleLine = true,
                            label = { Text(localizedText("解析服务（") + localizedText(resolutionMode.displayName) + "）") },
                            shape = SettingsCornerShape,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onNavigateToRaceModeSettings() }
                        )
                    } else {
                        Box(modifier = Modifier.fillMaxWidth()) {
                            OutlinedTextField(
                                value = displayProviders.getOrNull(selectedIndex)?.let { localizedText(it.name) } ?: "",
                                onValueChange = {},
                                readOnly = true,
                                label = { Text(localizedText("解析服务")) },
                                trailingIcon = {
                                    Icon(
                                        imageVector = Icons.Default.KeyboardArrowDown,
                                        contentDescription = localizedText("选择解析服务")
                                    )
                                },
                                shape = SettingsCornerShape,
                                modifier = Modifier.fillMaxWidth()
                            )
                            Box(
                                modifier = Modifier
                                    .matchParentSize()
                                    .clickable(onClickLabel = localizedText("选择解析服务")) {
                                        showProviderDialog = true
                                    }
                            )
                        }
                    }
                }
            }

            ProviderSelectionDialog(
                visible = showProviderDialog && resolutionMode == DnsResolutionMode.SINGLE,
                providers = displayProviders,
                onDismissRequest = { showProviderDialog = false },
                onProviderSelected = { provider ->
                    showProviderDialog = false
                    when (provider.id) {
                        MANAGE_PROVIDER_ID -> onNavigateToProviderManagement()
                        PROVIDER_VISIBILITY_ID -> onNavigateToHomeProviderVisibility()
                        else -> viewModel.selectProvider(provider.id)
                    }
                }
            )

            if (resolutionMode != DnsResolutionMode.SINGLE) {
                ProviderEndpointList(providers = raceProviders, modifier = Modifier.alpha(dnsDetailOpacity))
            } else {
                selectedProvider?.let { provider ->
                    Text(
                        text = provider.endpointLabel(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                            .alpha(dnsDetailOpacity)
                    )
                }
            }
        }

        val raceButtonContainerColor by animateColorAsState(
            targetValue = if (resolutionMode != DnsResolutionMode.SINGLE) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                Color.Transparent
            },
            animationSpec = tween(200),
            label = "RaceModeButtonContainerColor"
        )
        val raceButtonContentColor by animateColorAsState(
            targetValue = if (resolutionMode != DnsResolutionMode.SINGLE) {
                MaterialTheme.colorScheme.onPrimaryContainer
            } else {
                MaterialTheme.colorScheme.primary
            },
            animationSpec = tween(200),
            label = "RaceModeButtonContentColor"
        )
        var showGoTunnelDisableConfirm by remember { mutableStateOf(false) }
        Row(
            modifier = Modifier
                .padding(top = 24.dp)
                .alpha(modeButtonOpacity),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (!hideGoTunnelDisableButtonWhenInactive || goTunnelRequired) {
                Button(
                    onClick = { showGoTunnelDisableConfirm = true },
                    shape = SettingsCornerShape,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (goTunnelRequired) {
                            MaterialTheme.colorScheme.primaryContainer
                        } else {
                            Color.Transparent
                        },
                        contentColor = if (goTunnelRequired) {
                            MaterialTheme.colorScheme.onPrimaryContainer
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                        disabledContainerColor = Color.Transparent,
                        disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                    ),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    enabled = goTunnelRequired && !uiState.isBusy
                ) {
                    Text(text = localizedText(if (goTunnelRequired) "Go 隧道 · 开启" else "Go 隧道 · 关闭"))
                }
            }
            Button(
                onClick = onNavigateToRaceModeSettings,
                shape = SettingsCornerShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = raceButtonContainerColor,
                    contentColor = raceButtonContentColor
                ),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                enabled = !uiState.isBusy
            ) {
                Text(text = localizedText(resolutionMode.displayName))
            }
        }
        if (showGoTunnelDisableConfirm) {
            AlertDialog(
                onDismissRequest = { showGoTunnelDisableConfirm = false },
                title = { Text(localizedText("关闭 Go 隧道")) },
                text = {
                    Column {
                        Text(localizedText("关闭后将停用以下依赖 Go 隧道的功能："))
                        Spacer(modifier = Modifier.height(8.dp))
                        goTunnelReasons.forEach { reason ->
                            Text("• ${localizedText(reason.displayName)}")
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(localizedText("如果 VPN 正在运行，服务将自动重连。"))
                    }
                },
                confirmButton = {
                    TextButton(onClick = {
                        showGoTunnelDisableConfirm = false
                        AppSettings.setHttpInspectionEnabled(context, false)
                        AppSettings.setBlockedAppsEnabled(context, false)
                        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                        onGoTunnelDisabled()
                    }) {
                        Text(localizedText("关闭"))
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showGoTunnelDisableConfirm = false }) {
                        Text(localizedText("取消"))
                    }
                }
            )
        }

    }
}

@Composable
private fun PowerToggleButton(
    isRunning: Boolean,
    isBusy: Boolean,
    enabled: Boolean,
    onCenterChanged: (Offset) -> Unit,
    onToggle: () -> Unit
) {
    val glowColor by animateColorAsState(
        targetValue = if (isRunning) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.28f)
        } else {
            MaterialTheme.colorScheme.outline.copy(alpha = 0.12f)
        },
        animationSpec = tween(250),
        label = "PowerToggleGlowColor"
    )
    val haloColor by animateColorAsState(
        targetValue = if (isRunning) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
        } else {
            Color.Transparent
        },
        animationSpec = tween(250),
        label = "PowerToggleHaloColor"
    )
    val containerColor by animateColorAsState(
        targetValue = if (isRunning) {
            MaterialTheme.colorScheme.primary
        } else {
            MaterialTheme.colorScheme.surface
        },
        animationSpec = tween(250),
        label = "PowerToggleContainerColor"
    )
    val contentColor by animateColorAsState(
        targetValue = if (isRunning) {
            MaterialTheme.colorScheme.onPrimary
        } else {
            MaterialTheme.colorScheme.primary
        },
        animationSpec = tween(250),
        label = "PowerToggleContentColor"
    )
    val glowSize by animateDpAsState(
        targetValue = if (isRunning) 128.dp else 108.dp,
        animationSpec = tween(250),
        label = "PowerToggleGlowSize"
    )
    val haloSize by animateDpAsState(
        targetValue = if (isRunning) 148.dp else 124.dp,
        animationSpec = tween(250),
        label = "PowerToggleHaloSize"
    )
    val buttonSize by animateDpAsState(
        targetValue = if (isRunning) 92.dp else 84.dp,
        animationSpec = tween(250),
        label = "PowerToggleButtonSize"
    )
    val buttonAlpha = if (enabled) 1f else 0.5f
    val description = when {
        isBusy -> "连接中"
        isRunning -> "断开"
        else -> "开启"
    }

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(156.dp)
            .onGloballyPositioned { coordinates ->
                onCenterChanged(coordinates.boundsInRoot().center)
            }
            .alpha(buttonAlpha)
    ) {
        Box(
            modifier = Modifier
                .size(haloSize)
                .background(haloColor, CircleShape)
        )
        Box(
            modifier = Modifier
                .size(glowSize)
                .background(glowColor, CircleShape)
        )
        FilledIconButton(
            onClick = onToggle,
            enabled = enabled,
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = containerColor,
                contentColor = contentColor,
                disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            modifier = Modifier.size(buttonSize)
        ) {
            Icon(
                imageVector = Icons.Default.PowerSettingsNew,
                contentDescription = localizedText(description),
                modifier = Modifier.size(42.dp)
            )
        }
    }
}

@Composable
private fun ProviderEndpointList(providers: List<DnsProvider>, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        providers.forEach { provider ->
            Text(
                text = provider.endpointLabel(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun ProviderSelectionDialog(
    visible: Boolean,
    providers: List<DnsProvider>,
    onDismissRequest: () -> Unit,
    onProviderSelected: (DnsProvider) -> Unit
) {
    val dialogVisibility = remember { MutableTransitionState(false) }
    dialogVisibility.targetState = visible

    if (dialogVisibility.currentState || dialogVisibility.targetState) {
        Dialog(
            onDismissRequest = onDismissRequest,
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            DisableDialogDimming()
            AnimatedVisibility(
                visibleState = dialogVisibility,
                enter = fadeIn(animationSpec = tween(120)) +
                    scaleIn(initialScale = 0.92f, animationSpec = tween(180)),
                exit = fadeOut(animationSpec = tween(90)) +
                    scaleOut(targetScale = 0.92f, animationSpec = tween(120))
            ) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp)
                        .heightIn(max = 520.dp),
                    shape = SettingsCornerShape,
                    color = MaterialTheme.colorScheme.surface,
                    tonalElevation = 6.dp
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .verticalScroll(rememberScrollState())
                            .padding(vertical = 8.dp)
                    ) {
                        Text(
                            text = localizedText("解析服务"),
                            style = MaterialTheme.typography.titleLarge,
                            fontSize = 24.sp,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
                        )
                        providers.forEachIndexed { index, provider ->
                            DropdownMenuItem(
                                text = {
                                    ProviderDropdownText(
                                        provider = provider,
                                        showProtocolBadge = provider.id != MANAGE_PROVIDER_ID &&
                                            provider.id != PROVIDER_VISIBILITY_ID
                                    )
                                },
                                onClick = { onProviderSelected(provider) },
                                modifier = Modifier.padding(horizontal = 8.dp)
                            )
                            if (index < providers.lastIndex) {
                                Spacer(modifier = Modifier.padding(vertical = 1.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DisableDialogDimming() {
    val view = LocalView.current
    SideEffect {
        (view.parent as? DialogWindowProvider)?.window?.setDimAmount(0f)
    }
}

@Composable
private fun ProviderDropdownText(
    provider: DnsProvider,
    showProtocolBadge: Boolean
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = localizedText(provider.name),
            style = MaterialTheme.typography.bodyLarge
        )
        Spacer(modifier = Modifier.weight(1f))
        if (showProtocolBadge) {
            DnsProtocolBadge(protocol = provider.protocol)
        }
    }
}
