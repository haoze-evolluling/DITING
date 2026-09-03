package com.haoze.dnssr.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.vpn.DnsProvider

@Composable
internal fun MainContent(
    uiState: MainUiState,
    onToggle: () -> Unit,
    onNavigateToProviderManagement: () -> Unit,
    onNavigateToHomeProviderVisibility: () -> Unit,
    onNavigateToRaceModeSettings: () -> Unit,
    showDataResetNotice: Boolean,
    onDismissDataResetNotice: () -> Unit,
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val context = LocalContext.current
    val providers by viewModel.providers.collectAsStateWithLifecycle()
    val selectedProvider by viewModel.selectedProvider.collectAsStateWithLifecycle()
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
            .padding(bottom = 88.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        AnimatedVisibility(
            visible = showDataResetNotice,
            enter = fadeIn(animationSpec = tween(180)) + scaleIn(initialScale = 0.95f),
            exit = fadeOut(animationSpec = tween(180)) + scaleOut(targetScale = 0.95f)
        ) {
            DataResetNoticeCard(
                onDismiss = onDismissDataResetNotice,
                modifier = Modifier.padding(bottom = 16.dp)
            )
        }

        Box(modifier = Modifier.alpha(powerButtonOpacity)) {
            PowerToggleButton(
                isRunning = uiState.isRunning,
                isBusy = uiState.isBusy,
                enabled = !uiState.isBusy && selectedProvider != null &&
                    (resolutionMode == DnsResolutionMode.SINGLE || raceProviderIds.size >= 2),
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
        Row(
            modifier = Modifier
                .padding(top = 24.dp)
                .alpha(modeButtonOpacity),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
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
    }
}
