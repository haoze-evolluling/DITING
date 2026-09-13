package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsLoadingContent
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider

@Composable
fun ResolutionModeConfigScreen(
    mode: DnsResolutionMode,
    onBack: () -> Unit,
    viewModel: RaceModeSettingsViewModel = viewModel()
) {
    val providers by viewModel.providers.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val smartIds by viewModel.smartPredictionIds.collectAsStateWithLifecycle()
    val parallelIds by viewModel.parallelRaceIds.collectAsStateWithLifecycle()
    val backupIds by viewModel.primaryBackupIds.collectAsStateWithLifecycle()
    val singleId by viewModel.singleProviderId.collectAsStateWithLifecycle()
    val loading by viewModel.initialLoading.collectAsStateWithLifecycle()
    var protocol by remember { mutableStateOf(DnsProtocol.DNS) }
    val listState = rememberLazyListState()
    var listViewportBounds by remember { mutableStateOf<Rect?>(null) }
    NavigationSettledEffect { viewModel.activate() }
    val selected = when (mode) {
        DnsResolutionMode.SMART_PREDICTION -> smartIds
        DnsResolutionMode.PARALLEL_RACE -> parallelIds
        DnsResolutionMode.PRIMARY_BACKUP -> backupIds.toSet()
        DnsResolutionMode.SINGLE -> setOf(singleId)
    }
    val isValid = viewModel.isModeValid(mode)
    val availableProtocols = remember(providers) {
        DnsProtocol.MANAGED_PROTOCOLS.filter { p -> providers.any { it.protocol == p } }
    }

    // Once the provider list loads, snap the protocol filter to the first available protocol instead of lingering on an empty list.
    LaunchedEffect(availableProtocols) {
        if (availableProtocols.isNotEmpty() && protocol !in availableProtocols) {
            protocol = availableProtocols.first()
        }
    }

    fun applyProviderSelection(provider: DnsProvider) {
        if (mode == DnsResolutionMode.SINGLE) {
            viewModel.selectSingleProvider(provider.id)
        } else {
            viewModel.toggleModeProvider(mode, provider.id)
        }
    }

    fun handleProviderSelection(provider: DnsProvider) {
        if (mode == DnsResolutionMode.SINGLE && provider.id == singleId) return
        if (mode != DnsResolutionMode.SINGLE && provider.id in selected) {
            applyProviderSelection(provider)
        } else {
            applyProviderSelection(provider)
        }
    }

    SettingsScaffold(title = localizedText(mode.displayName), onBack = onBack) { padding ->
        if (loading) return@SettingsScaffold SettingsLoadingContent(Modifier.padding(padding))
        LazyColumn(
            state = listState,
            modifier = Modifier
                .padding(padding)
                .onGloballyPositioned { listViewportBounds = it.boundsInWindow() },
            contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                ModeSummaryCard(
                    mode = mode,
                    description = descriptionFor(mode, selected.size),
                    isValid = isValid
                )
            }
            if (availableProtocols.isNotEmpty()) {
                item {
                    SingleChoiceSegmentedButtonRow(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp)
                    ) {
                        availableProtocols.forEachIndexed { index, p ->
                            SegmentedButton(
                                selected = protocol == p,
                                onClick = { protocol = p },
                                shape = SegmentedButtonDefaults.itemShape(index, availableProtocols.size),
                                label = { Text(p.label) }
                            )
                        }
                    }
                }
            }
            item {
                SettingsGroupTitle(localizedText(when (mode) {
                    DnsResolutionMode.SINGLE -> "查询服务"
                    DnsResolutionMode.SMART_PREDICTION -> "候选服务"
                    DnsResolutionMode.PARALLEL_RACE -> "同时查询的服务"
                    DnsResolutionMode.PRIMARY_BACKUP -> "依次尝试的服务"
                }))
            }
            item {
                val filtered = providers.filter { it.protocol == protocol }
                if (filtered.isEmpty()) {
                    EmptyProviderCard()
                } else {
                    SettingsSurfaceGroup(
                        content = filtered.map { provider ->
                            {
                                if (mode == DnsResolutionMode.SINGLE) {
                                    SettingsRadioItem(localizedText(provider.name), provider.id == singleId, { handleProviderSelection(provider) }, subtitle = provider.endpointLabel())
                                } else {
                                    SettingsCheckboxItem(localizedText(provider.name), provider.id in selected, { handleProviderSelection(provider) }, subtitle = provider.endpointLabel())
                                }
                            }
                        }
                    )
                }
            }
            if (mode == DnsResolutionMode.PRIMARY_BACKUP && backupIds.isNotEmpty()) {
                item { SettingsGroupTitle(localizedText("查询顺序")) }
                item {
                    PrimaryBackupOrderGroup(
                        backupIds = backupIds,
                        providersById = providers.associateBy { it.id },
                        listState = listState,
                        listViewportBounds = listViewportBounds,
                        onReorder = viewModel::reorderPrimaryBackupProvider
                    )
                }
            }
        }
    }
}

/** Summary card at the top of the mode config screen: describes the current selection state and uses a status pill to indicate whether the activation conditions are met. */
@Composable
private fun ModeSummaryCard(
    mode: DnsResolutionMode,
    description: String,
    isValid: Boolean
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = ResolutionModeHeroShape,
        color = MaterialTheme.colorScheme.primaryContainer
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Icon(
                imageVector = mode.iconVector(),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.size(28.dp)
            )
            Text(
                text = localizedText(description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.weight(1f)
            )
            Surface(
                shape = CircleShape,
                color = if (isValid) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.surface
                }
            ) {
                Text(
                    text = localizedText(if (isValid) "已就绪" else "待配置"),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isValid) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                )
            }
        }
    }
}

/** Empty-state placeholder shown when a protocol has no providers. */
@Composable
private fun EmptyProviderCard() {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = ResolutionModeHeroShape,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
    ) {
        Text(
            text = localizedText("暂无此协议的服务商"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 32.dp)
        )
    }
}
