package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DragHandle
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
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsLoadingContent
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import com.haoze.dnssr.ui.components.SettingsItemSpacing
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.DnsProtocol
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** 解析模式页的 Hero 卡片圆角，与设置分组外圈圆角保持一致。 */
private val ResolutionModeHeroShape = RoundedCornerShape(28.dp)

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

/** 当前模式 Hero 卡片：primaryContainer 色调承载最重要的选择状态。 */
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

/** 内置服务协议：三个固定选项直接使用分段按钮内联切换，减少一层对话框跳转。 */
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

/** 模式配置卡片：当前模式用 primary 图标容器与对勾标识，其余显示配置摘要。 */
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

    // 服务商列表加载完成后，把协议筛选吸附到第一个可用协议，避免停留在空列表。
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

/** 模式配置页顶部的摘要卡：说明当前选择状态，并用状态胶囊提示是否满足生效条件。 */
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

/** 协议下暂无服务商时的空态占位。 */
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

@Composable
private fun PrimaryBackupOrderGroup(
    backupIds: List<String>,
    providersById: Map<String, DnsProvider>,
    listState: LazyListState,
    listViewportBounds: Rect?,
    onReorder: (String, Int) -> Unit
) {
    var orderedIds by remember(backupIds) { mutableStateOf(backupIds) }
    var draggedId by remember { mutableStateOf<String?>(null) }
    var settlingId by remember { mutableStateOf<String?>(null) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    var dragStartIndex by remember { mutableIntStateOf(0) }
    var targetIndex by remember { mutableIntStateOf(0) }
    var draggedCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var settleJob by remember { mutableStateOf<Job?>(null) }
    val latestBackupOrder = rememberUpdatedState(backupIds)
    val density = LocalDensity.current
    val hapticFeedback = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()
    val settleOffset = remember { Animatable(0f) }
    val reorderThresholdPx = with(density) { 40.dp.toPx() }
    val edgeOverscrollPx = with(density) { 20.dp.toPx() }
    val autoScrollEdgePx = with(density) { 72.dp.toPx() }
    val maxAutoScrollPxPerSecond = with(density) { 720.dp.toPx() }
    val rowHeight = 48.dp
    val dividerHeight = 1.dp
    val itemHeight = rowHeight + dividerHeight
    val itemHeightPx = with(density) { itemHeight.toPx() }
    val liftedShape = SettingsCornerShape
    val rowColor = MaterialTheme.colorScheme.surfaceContainer

    fun updateDraggedPosition(providerId: String) {
        while (true) {
            val current = orderedIds
            val from = current.indexOf(providerId)
            if (from < 0) return

            if (from == 0 && dragOffsetY < -edgeOverscrollPx) {
                dragOffsetY = -edgeOverscrollPx
            }
            if (from == current.lastIndex && dragOffsetY > edgeOverscrollPx) {
                dragOffsetY = edgeOverscrollPx
            }

            val direction = when {
                dragOffsetY <= -reorderThresholdPx -> -1
                dragOffsetY >= reorderThresholdPx -> 1
                else -> return
            }
            val to = (from + direction).coerceIn(current.indices)
            if (from == to) return

            orderedIds = current.toMutableList().apply {
                add(to, removeAt(from))
            }
            targetIndex = to
            dragOffsetY -= direction * itemHeightPx
        }
    }

    fun settleDraggedItem(providerId: String) {
        settleJob?.cancel()
        settleJob = coroutineScope.launch(start = CoroutineStart.UNDISPATCHED) {
            settleOffset.snapTo(dragOffsetY)
            settlingId = providerId
            draggedId = null
            draggedCoordinates = null
            settleOffset.animateTo(
                targetValue = 0f,
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioNoBouncy,
                    stiffness = Spring.StiffnessMedium
                )
            )
            if (settlingId == providerId) {
                dragOffsetY = 0f
                settlingId = null
            }
        }
    }

    LaunchedEffect(draggedId, listViewportBounds) {
        val providerId = draggedId ?: return@LaunchedEffect
        val viewport = listViewportBounds ?: return@LaunchedEffect
        var previousFrameNanos = withFrameNanos { it }

        while (draggedId == providerId) {
            val frameNanos = withFrameNanos { it }
            val frameSeconds = ((frameNanos - previousFrameNanos) / 1_000_000_000f)
                .coerceAtMost(0.05f)
            previousFrameNanos = frameNanos

            val coordinates = draggedCoordinates
            if (coordinates?.isAttached != true) continue
            val centerY = coordinates.boundsInWindow().center.y
            val topDistance = centerY - viewport.top
            val bottomDistance = viewport.bottom - centerY
            val scrollVelocity = when {
                topDistance < autoScrollEdgePx && listState.canScrollBackward -> {
                    -maxAutoScrollPxPerSecond *
                        (1f - topDistance / autoScrollEdgePx).coerceIn(0f, 1f)
                }
                bottomDistance < autoScrollEdgePx && listState.canScrollForward -> {
                    maxAutoScrollPxPerSecond *
                        (1f - bottomDistance / autoScrollEdgePx).coerceIn(0f, 1f)
                }
                else -> 0f
            }
            if (scrollVelocity == 0f) continue

            val consumedScroll = listState.scrollBy(scrollVelocity * frameSeconds)
            if (consumedScroll != 0f) {
                dragOffsetY += consumedScroll
                updateDraggedPosition(providerId)
            }
        }
    }

    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .height(itemHeight * orderedIds.size - dividerHeight)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            shape = SettingsCornerShape,
            color = rowColor
        ) {}

        orderedIds.forEachIndexed { index, providerId ->
            val provider = providersById[providerId] ?: return@forEachIndexed
            key(providerId) {
                var rowCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
                val isDragging = draggedId == providerId
                val isSettling = settlingId == providerId
                val isRaised = isDragging || isSettling
                val baseOffset by animateDpAsState(
                    targetValue = itemHeight * index,
                    animationSpec = if (isRaised) snap() else tween(durationMillis = 160),
                    label = "primaryBackupItemPlacement"
                )
                val liftedScale by animateFloatAsState(
                    targetValue = if (isRaised) 1.02f else 1f,
                    animationSpec = tween(durationMillis = 120),
                    label = "primaryBackupLiftScale"
                )
                val displayIndex = if (isRaised) dragStartIndex else index
                val accessibilityActions = buildList {
                    if (index > 0) {
                        add(CustomAccessibilityAction(localizedText("提高优先级")) {
                            onReorder(providerId, index - 1)
                            true
                        })
                    }
                    if (index < orderedIds.lastIndex) {
                        add(CustomAccessibilityAction(localizedText("降低优先级")) {
                            onReorder(providerId, index + 1)
                            true
                        })
                    }
                }

                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(rowHeight)
                        .offset(y = baseOffset)
                        .zIndex(if (isRaised) 1f else 0f)
                        .graphicsLayer {
                            translationY = when {
                                isDragging -> dragOffsetY
                                isSettling -> settleOffset.value
                                else -> 0f
                            }
                            scaleX = liftedScale
                            scaleY = liftedScale
                            shadowElevation = if (isDragging) 8.dp.toPx() else 0f
                            shape = liftedShape
                        }
                        .onGloballyPositioned {
                            rowCoordinates = it
                            if (isDragging) draggedCoordinates = it
                        }
                        .background(
                            color = if (isRaised) rowColor else Color.Transparent,
                            shape = liftedShape
                        )
                        .semantics(mergeDescendants = true) {
                            customActions = accessibilityActions
                        }
                        .padding(start = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = localizedText(if (displayIndex == 0) {
                            "主"
                        } else {
                            "备 $displayIndex"
                        }),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                    Text(
                        text = localizedText(provider.name),
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    DnsProtocolBadge(
                        protocol = provider.protocol,
                        modifier = Modifier.padding(start = 8.dp)
                    )
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .pointerInput(providerId, itemHeightPx, backupIds) {
                                detectDragGesturesAfterLongPress(
                                    onDragStart = {
                                        settleJob?.cancel()
                                        settlingId = null
                                        draggedId = providerId
                                        draggedCoordinates = rowCoordinates
                                        dragStartIndex = orderedIds.indexOf(providerId)
                                        targetIndex = dragStartIndex
                                        dragOffsetY = 0f
                                        hapticFeedback.performHapticFeedback(
                                            HapticFeedbackType.LongPress
                                        )
                                    },
                                    onDragCancel = {
                                        val currentIndex = orderedIds.indexOf(providerId)
                                        val backupOrder = latestBackupOrder.value
                                        val originalIndex = backupOrder.indexOf(providerId)
                                        if (currentIndex >= 0 && originalIndex >= 0) {
                                            dragOffsetY +=
                                                (currentIndex - originalIndex) * itemHeightPx
                                            targetIndex = originalIndex
                                        }
                                        orderedIds = backupOrder
                                        settleDraggedItem(providerId)
                                    },
                                    onDragEnd = {
                                        onReorder(providerId, targetIndex)
                                        settleDraggedItem(providerId)
                                    },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        dragOffsetY += dragAmount.y
                                        updateDraggedPosition(providerId)
                                    }
                                )
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.DragHandle,
                            contentDescription = localizedText("长按并拖动调整顺序"),
                            tint = if (isRaised) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            }
                        )
                    }
                }
            }
        }
        repeat(orderedIds.lastIndex) { index ->
            SettingsDivider(Modifier.offset(y = itemHeight * index + rowHeight))
        }
    }
}

private fun subtitleFor(mode: DnsResolutionMode) = when (mode) {
    DnsResolutionMode.SINGLE -> "选择一个 DNS 服务商进行查询"
    DnsResolutionMode.SMART_PREDICTION -> "根据近期成功率和延迟优先选择服务，失败或超时时自动兜底"
    DnsResolutionMode.PARALLEL_RACE -> "同时查询所有选中服务，采用最先成功的结果"
    DnsResolutionMode.PRIMARY_BACKUP -> "按设置顺序查询，前一个失败后切换下一个服务"
}

private fun descriptionFor(mode: DnsResolutionMode, count: Int) = when (mode) {
    DnsResolutionMode.SINGLE -> "选择一个服务进行查询。此选择与首页当前 DNS 服务商保持一致。"
    DnsResolutionMode.SMART_PREDICTION -> "已选择 $count 个候选服务。至少选择 2 个；系统会根据近期成功率和延迟优先选择，并在失败或超时时自动兜底。"
    DnsResolutionMode.PARALLEL_RACE -> "已选择 $count 个同时查询的服务。至少选择 2 个；查询会同时发送并采用最先成功的结果。"
    DnsResolutionMode.PRIMARY_BACKUP -> "已选择 $count 个依次尝试的服务。至少需要 1 个主服务和 1 个备用服务；长按并拖动可调整查询顺序。"
}
