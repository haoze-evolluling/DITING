package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsLoadingContent
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import com.haoze.dnssr.ui.components.SettingsItemSpacing

@Composable
fun ResolutionModeHomeScreen(
    onBack: () -> Unit,
    onOpenMode: (DnsResolutionMode) -> Unit,
    viewModel: RaceModeSettingsViewModel = viewModel()
) {
    val mode by viewModel.resolutionMode.collectAsStateWithLifecycle()
    val providers by viewModel.providers.collectAsStateWithLifecycle()
    val smartIds by viewModel.smartPredictionIds.collectAsStateWithLifecycle()
    val parallelIds by viewModel.parallelRaceIds.collectAsStateWithLifecycle()
    val backupIds by viewModel.primaryBackupIds.collectAsStateWithLifecycle()
    val singleId by viewModel.singleProviderId.collectAsStateWithLifecycle()
    val presetDnsService by viewModel.presetDnsService.collectAsStateWithLifecycle()
    val loading by viewModel.initialLoading.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showModeDialog by remember { mutableStateOf(false) }
    NavigationSettledEffect { viewModel.activate() }
    LaunchedEffect(message) { message?.let { context.showToast(it, Toast.LENGTH_SHORT); viewModel.clearMessage() } }

    if (showModeDialog) {
        ResolutionModePickerDialog(
            selectedMode = mode,
            onSelect = { selectedMode ->
                showModeDialog = false
                if (!viewModel.setResolutionMode(selectedMode) && mode != selectedMode) {
                    onOpenMode(selectedMode)
                }
            },
            onDismiss = { showModeDialog = false }
        )
    }

    SettingsScaffold(
        title = localizedText("解析模式"),
        onBack = onBack
    ) { padding ->
        if (loading) return@SettingsScaffold SettingsLoadingContent(Modifier.padding(padding))
        LazyColumn(
            modifier = Modifier.padding(padding),
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("当前模式")) }
            item {
                CurrentModeCard(
                    mode = mode,
                    onClick = { showModeDialog = true }
                )
            }
            item { SettingsGroupTitle(localizedText("内置服务协议")) }
            item {
                PresetProtocolSelector(
                    selected = presetDnsService,
                    onSelect = viewModel::setPresetDnsService
                )
            }
            item {
                SettingsInfoText(localizedText("仅切换阿里云和 DNSPod 内置服务的 DNS、DoT 或 DoH 协议，并同步四种模式中的对应预设服务"))
            }
            item { SettingsGroupTitle(localizedText("模式配置")) }
            item {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
                ) {
                    DnsResolutionMode.entries.forEachIndexed { index, itemMode ->
                        val summary = when (itemMode) {
                            DnsResolutionMode.SINGLE -> providers.firstOrNull { it.id == singleId }
                                ?.let { localizedText(it.name) } ?: localizedText("未配置")
                            DnsResolutionMode.SMART_PREDICTION -> localizedText("${smartIds.size} 个服务商")
                            DnsResolutionMode.PARALLEL_RACE -> localizedText("${parallelIds.size} 个服务商")
                            DnsResolutionMode.PRIMARY_BACKUP -> localizedText("${backupIds.size} 个服务商")
                        }
                        ModeConfigCard(
                            mode = itemMode,
                            isCurrent = itemMode == mode,
                            summary = summary,
                            index = index,
                            itemCount = DnsResolutionMode.entries.size,
                            onClick = { onOpenMode(itemMode) }
                        )
                    }
                }
            }
        }
    }
}

/** Current mode hero card: primaryContainer coloring carries the most important selection state. */
@Composable
private fun CurrentModeCard(
    mode: DnsResolutionMode,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = ResolutionModeHeroShape,
        color = MaterialTheme.colorScheme.primaryContainer
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primary
            ) {
                Icon(
                    imageVector = mode.iconVector(),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier
                        .padding(10.dp)
                        .size(24.dp)
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = localizedText(mode.displayName),
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
                Text(
                    text = localizedText(subtitleFor(mode)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = localizedText("选择解析模式"),
                tint = MaterialTheme.colorScheme.onPrimaryContainer
            )
        }
    }
}

/** Built-in service protocol: three fixed options switch inline with segmented buttons, avoiding an extra dialog hop. */
@Composable
private fun PresetProtocolSelector(
    selected: PresetDnsService,
    onSelect: (PresetDnsService) -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = ResolutionModeHeroShape,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
    ) {
        SingleChoiceSegmentedButtonRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp)
        ) {
            PresetDnsService.entries.forEachIndexed { index, service ->
                SegmentedButton(
                    selected = selected == service,
                    onClick = { onSelect(service) },
                    shape = SegmentedButtonDefaults.itemShape(index, PresetDnsService.entries.size),
                    label = { Text(localizedText(service.displayName)) }
                )
            }
        }
    }
}

/** Mode config cards: the current mode is marked with a primary icon container and a check mark; others show a config summary. */
@Composable
private fun ModeConfigCard(
    mode: DnsResolutionMode,
    isCurrent: Boolean,
    summary: String,
    index: Int,
    itemCount: Int,
    onClick: () -> Unit
) {
    SettingsSurfaceItem(
        index = index,
        itemCount = itemCount,
        containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        content = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onClick)
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = if (isCurrent) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerHighest
                    },
                    modifier = Modifier.size(40.dp)
                ) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = mode.iconVector(),
                            contentDescription = null,
                            tint = if (isCurrent) {
                                MaterialTheme.colorScheme.onPrimary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                            modifier = Modifier.size(22.dp)
                        )
                    }
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = localizedText(mode.displayName),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = localizedText(subtitleFor(mode)),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (isCurrent) {
                    Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = localizedText("当前模式"),
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(22.dp)
                    )
                } else {
                    Text(
                        text = summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    )
}

@Composable
private fun ResolutionModePickerDialog(
    selectedMode: DnsResolutionMode,
    onSelect: (DnsResolutionMode) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("选择解析模式")) },
        text = {
            Column {
                SettingsSurfaceGroup(
                    groupContentPadding = PaddingValues.Zero,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    content = DnsResolutionMode.entries.map { mode ->
                        {
                            SettingsItem(
                                title = localizedText(mode.displayName),
                                subtitle = localizedText(subtitleFor(mode)),
                                leadingIcon = mode.iconVector(),
                                onClick = { onSelect(mode) }
                            ) {
                                if (selectedMode == mode) {
                                    Icon(
                                        imageVector = Icons.Default.CheckCircle,
                                        contentDescription = localizedText("已选中"),
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        }
                    }
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(localizedText("取消")) }
        }
    )
}
