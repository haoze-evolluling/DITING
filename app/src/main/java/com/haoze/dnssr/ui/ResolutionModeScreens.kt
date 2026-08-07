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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DragHandle
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.style.TextAlign
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.haoze.dnssr.ui.components.SettingsDivider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsLoadingContent
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.DnsProtocol
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

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
    val goTunnelRequired by viewModel.goTunnelRequired.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showModeDialog by remember { mutableStateOf(false) }
    var showPresetDnsServiceDialog by remember { mutableStateOf(false) }
    var showGoTunnelInfo by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { viewModel.activate() }
    LaunchedEffect(message) { message?.let { Toast.makeText(context, localizedText(context, it), Toast.LENGTH_SHORT).show(); viewModel.clearMessage() } }

    if (showModeDialog) {
        ResolutionModePickerDialog(
            selectedMode = mode,
            goTunnelRequired = goTunnelRequired,
            onSelect = { selectedMode ->
                showModeDialog = false
                if (!viewModel.setResolutionMode(selectedMode) && mode != selectedMode) {
                    onOpenMode(selectedMode)
                }
            },
            onDismiss = { showModeDialog = false }
        )
    }

    if (showPresetDnsServiceDialog) {
        PresetDnsServicePickerDialog(
            selectedService = presetDnsService,
            onSelect = { service ->
                showPresetDnsServiceDialog = false
                viewModel.setPresetDnsService(service)
            },
            onDismiss = { showPresetDnsServiceDialog = false }
        )
    }

    if (showGoTunnelInfo) {
        val reasons = AppSettings.getGoTunnelReasons(context)
        AlertDialog(
            onDismissRequest = { showGoTunnelInfo = false },
            title = { Text(localizedText("Go 隧道已启用")) },
            text = {
                Text(
                    localizedText(context, "Go 隧道用于在本机 VPN 中接管 TCP、UDP、DNS 和 HTTP(S) 流量，使谛听能识别应用连接。") +
                        "\n\n" + localizedText(context, "当前触发功能：") + "\n" +
                        reasons.joinToString("\n") { "• ${localizedText(context, it.displayName)}" } +
                        "\n\n" + localizedText(context, "启用期间，智能选择和最快响应解析模式不可用，只能使用单一服务或依次尝试模式。")
                )
            },
            confirmButton = {
                TextButton(onClick = { showGoTunnelInfo = false }) { Text(localizedText(context, "知道了")) }
            }
        )
    }

    SettingsScaffold(
        title = localizedText("解析模式"),
        onBack = onBack,
        titleTrailing = {
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
    ) { padding ->
        if (loading) return@SettingsScaffold SettingsLoadingContent(Modifier.padding(padding))
        LazyColumn(
            modifier = Modifier.padding(padding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("当前模式")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("解析模式"),
                        subtitle = localizedText(subtitleFor(mode)),
                        value = localizedText(mode.displayName),
                        onClick = { showModeDialog = true }
                        )
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("内置服务协议")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("内置服务协议"),
                        subtitle = localizedText("仅切换阿里云和 DNSPod 内置服务的 DNS、DoT 或 DoH 协议，并同步四种模式中的对应预设服务"),
                        value = localizedText(presetDnsService.displayName),
                        onClick = { showPresetDnsServiceDialog = true }
                        )
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("模式配置")) }
            item {
                SettingsNavigationGroup(
                    items = DnsResolutionMode.entries.map { itemMode ->
                        val summary = when (itemMode) {
                            DnsResolutionMode.SINGLE -> providers.firstOrNull { it.id == singleId }?.let { localizedText(it.name) } ?: "未配置"
                            DnsResolutionMode.SMART_PREDICTION -> "${smartIds.size} 个服务商"
                            DnsResolutionMode.PARALLEL_RACE -> "${parallelIds.size} 个服务商"
                            DnsResolutionMode.PRIMARY_BACKUP -> "${backupIds.size} 个服务商"
                        }
                        SettingsNavigationItemData(
                            title = localizedText(itemMode.displayName),
                            subtitle = localizedText(subtitleFor(itemMode)),
                            value = localizedText(summary),
                            enabled = viewModel.isModeEnabled(itemMode),
                            onClick = { onOpenMode(itemMode) }
                        )
                    }
                )
            }
        }
    }
}

@Composable
private fun PresetDnsServicePickerDialog(
    selectedService: PresetDnsService,
    onSelect: (PresetDnsService) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("选择内置服务协议")) },
        text = {
            Column {
                Text(
                    text = localizedText("仅影响阿里云和 DNSPod 的内置服务；四种解析模式中已选择的对应预设服务会同步切换协议。"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
                )
                SettingsSurfaceGroup(
                    groupContentPadding = PaddingValues.Zero,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    content = PresetDnsService.entries.map { service ->
                        {
                            SettingsItem(
                                title = localizedText(service.displayName),
                                onClick = { onSelect(service) }
                            ) {
                                if (selectedService == service) {
                                    Icon(
                                        imageVector = Icons.Default.CheckCircle,
                                        contentDescription = null,
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
private fun ResolutionModePickerDialog(
    selectedMode: DnsResolutionMode,
    goTunnelRequired: Boolean,
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
                            val enabled = !goTunnelRequired || mode == DnsResolutionMode.SINGLE || mode == DnsResolutionMode.PRIMARY_BACKUP
                            SettingsItem(
                                title = localizedText(mode.displayName),
                                subtitle = localizedText(subtitleFor(mode)),
                                enabled = enabled,
                                onClick = { onSelect(mode) }
                            ) {
                                if (selectedMode == mode) {
                                    Icon(
                                        imageVector = Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
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
    LaunchedEffect(Unit) { viewModel.activate() }
    val selected = when (mode) {
        DnsResolutionMode.SMART_PREDICTION -> smartIds
        DnsResolutionMode.PARALLEL_RACE -> parallelIds
        DnsResolutionMode.PRIMARY_BACKUP -> backupIds.toSet()
        DnsResolutionMode.SINGLE -> setOf(singleId)
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
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    DnsProtocol.MANAGED_PROTOCOLS.filter { p -> providers.any { it.protocol == p } }.forEach { p ->
                        FilterChip(
                            selected = protocol == p,
                            onClick = { protocol = p },
                            label = {
                                Text(
                                    text = p.label,
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier.fillMaxWidth()
                                )
                            },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
            item {
                SettingsGroupTitle(
                    localizedText(when (mode) {
                        DnsResolutionMode.SINGLE -> "查询服务"
                        DnsResolutionMode.SMART_PREDICTION -> "候选服务"
                        DnsResolutionMode.PARALLEL_RACE -> "同时查询的服务"
                        DnsResolutionMode.PRIMARY_BACKUP -> "依次尝试的服务"
                    })
                )
            }
            item {
                SettingsSurfaceGroup(
                    content = providers.filter { it.protocol == protocol }.map { provider ->
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
            item { SettingsInfoText(localizedText(descriptionFor(mode, selected.size))) }
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
    val liftedShape = RoundedCornerShape(6.dp)
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
        Card(
            modifier = Modifier.fillMaxSize(),
            shape = SettingsCornerShape,
            colors = CardDefaults.cardColors(containerColor = rowColor)
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
