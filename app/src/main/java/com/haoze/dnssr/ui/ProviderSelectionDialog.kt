package com.haoze.dnssr.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.vpn.DnsProvider

internal const val MANAGE_PROVIDER_ID = "__manage__"
internal const val PROVIDER_VISIBILITY_ID = "__provider_visibility__"

internal fun raceProviderSummary(providerNames: List<String>): String {
    if (providerNames.isEmpty()) return "未选择服务商"
    val names = providerNames.take(2).joinToString("、")
    val suffix = if (providerNames.size > 2) " 等" else ""
    return "已选 ${providerNames.size} 个：$names$suffix"
}

/** 弹窗容器圆角：与首页 Hero 卡片一致的 M3 extra-large 圆角。 */
private val ProviderDialogCornerShape = RoundedCornerShape(28.dp)

/** 列表行圆角，与设置分组内条目保持一致。 */
private val ProviderDialogRowCorner = 12.dp

private val ProviderDialogRowShape = RoundedCornerShape(ProviderDialogRowCorner)

@Composable
internal fun ProviderSelectionDialog(
    visible: Boolean,
    providers: List<DnsProvider>,
    selectedProvider: DnsProvider?,
    onDismissRequest: () -> Unit,
    onProviderSelected: (DnsProvider) -> Unit
) {
    ProviderDialog(
        visible = visible,
        icon = Icons.Filled.Dns,
        title = localizedText("解析服务"),
        subtitle = selectedProvider?.let { localizedText("当前使用：") + localizedText(it.name) }
            ?: localizedText("选择一个服务进行查询"),
        providers = providers,
        isProviderSelected = { provider -> provider.id == selectedProvider?.id },
        onProviderClick = onProviderSelected,
        onActionClick = onProviderSelected,
        onDismissRequest = onDismissRequest
    )
}

/** 非单一模式的多选弹窗：勾选/取消参与当前模式的服务，与模式配置页的选择集合同步。 */
@Composable
internal fun ModeProviderSelectionDialog(
    visible: Boolean,
    mode: DnsResolutionMode,
    providers: List<DnsProvider>,
    selectedIds: Set<String>,
    onDismissRequest: () -> Unit,
    onProviderToggled: (DnsProvider) -> Unit,
    onActionSelected: (DnsProvider) -> Unit
) {
    val selectableProviders = providers.filter {
        it.id != MANAGE_PROVIDER_ID && it.id != PROVIDER_VISIBILITY_ID
    }
    val selectedNames = selectableProviders
        .filter { it.id in selectedIds }
        .map { localizedText(it.name) }
    ProviderDialog(
        visible = visible,
        icon = mode.iconVector(),
        title = localizedText("解析服务"),
        subtitle = localizedText(mode.displayName) + " · " +
            localizedText(raceProviderSummary(selectedNames)),
        providers = providers,
        isProviderSelected = { provider -> provider.id in selectedIds },
        onProviderClick = onProviderToggled,
        onActionClick = onActionSelected,
        onDismissRequest = onDismissRequest
    )
}

@Composable
private fun ProviderDialog(
    visible: Boolean,
    icon: ImageVector,
    title: String,
    subtitle: String,
    providers: List<DnsProvider>,
    isProviderSelected: (DnsProvider) -> Boolean,
    onProviderClick: (DnsProvider) -> Unit,
    onActionClick: (DnsProvider) -> Unit,
    onDismissRequest: () -> Unit
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
                    scaleIn(
                        initialScale = 0.88f,
                        animationSpec = spring(
                            dampingRatio = Spring.DampingRatioNoBouncy,
                            stiffness = Spring.StiffnessMediumLow
                        )
                    ),
                exit = fadeOut(animationSpec = tween(90)) +
                    scaleOut(targetScale = 0.92f, animationSpec = tween(120))
            ) {
                val maxDialogHeight = LocalConfiguration.current.screenHeightDp.dp * 0.68f
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp)
                        .heightIn(max = maxDialogHeight),
                    shape = ProviderDialogCornerShape,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    tonalElevation = 3.dp,
                    shadowElevation = 6.dp
                ) {
                    val regularProviders = providers.filter {
                        it.id != MANAGE_PROVIDER_ID && it.id != PROVIDER_VISIBILITY_ID
                    }
                    val manageProvider = providers.firstOrNull { it.id == MANAGE_PROVIDER_ID }
                    val visibilityProvider =
                        providers.firstOrNull { it.id == PROVIDER_VISIBILITY_ID }

                    Column(modifier = Modifier.fillMaxWidth()) {
                        ProviderDialogTitleRow(
                            icon = icon,
                            title = title,
                            subtitle = subtitle,
                            onDismissRequest = onDismissRequest
                        )
                        Column(
                            modifier = Modifier
                                .weight(1f, fill = false)
                                .verticalScroll(rememberScrollState())
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            regularProviders.forEach { provider ->
                                ProviderOptionRow(
                                    provider = provider,
                                    isSelected = isProviderSelected(provider),
                                    onClick = { onProviderClick(provider) }
                                )
                            }
                        }
                        if (manageProvider != null || visibilityProvider != null) {
                            HorizontalDivider(
                                modifier = Modifier.padding(horizontal = 16.dp),
                                color = MaterialTheme.colorScheme.outlineVariant
                            )
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 8.dp, vertical = 8.dp),
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                manageProvider?.let { provider ->
                                    DialogActionRow(
                                        label = localizedText(provider.name),
                                        icon = Icons.Filled.Tune,
                                        contentDescription = localizedText("管理服务"),
                                        onClick = { onActionClick(provider) },
                                        modifier = Modifier.weight(1f)
                                    )
                                }
                                visibilityProvider?.let { provider ->
                                    DialogActionRow(
                                        label = localizedText(provider.name),
                                        icon = Icons.Filled.Visibility,
                                        contentDescription = localizedText("设置服务显示"),
                                        onClick = { onActionClick(provider) },
                                        modifier = Modifier.weight(1f)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** 头部：primaryContainer 圆形图标 + 标题与当前服务副标题 + 关闭按钮。 */
@Composable
private fun ProviderDialogTitleRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onDismissRequest: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 8.dp, top = 16.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.primaryContainer,
            modifier = Modifier.size(40.dp)
        ) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.size(22.dp)
                )
            }
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(1.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        IconButton(onClick = onDismissRequest) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = localizedText("关闭"),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/** 服务商条目：选中时用 secondaryContainer 色调与对勾标识当前查询服务。 */
@Composable
private fun ProviderOptionRow(
    provider: DnsProvider,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(ProviderDialogRowShape)
            .background(
                color = if (isSelected) {
                    MaterialTheme.colorScheme.secondaryContainer
                } else {
                    Color.Transparent
                },
                shape = ProviderDialogRowShape
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = localizedText(provider.name),
                style = MaterialTheme.typography.bodyLarge,
                color = if (isSelected) {
                    MaterialTheme.colorScheme.onSecondaryContainer
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = provider.endpointLabel(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        DnsProtocolBadge(protocol = provider.protocol)
        if (isSelected) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = localizedText("已选中"),
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(22.dp)
            )
        }
    }
}

/** 底部管理入口：tonal 圆形图标 + 文字 + 右箭头，承担导航动作。 */
@Composable
private fun DialogActionRow(
    label: String,
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(ProviderDialogRowShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surfaceContainerHighest,
            modifier = Modifier.size(32.dp)
        ) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = contentDescription,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp)
        )
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
internal fun ProviderEndpointList(providers: List<DnsProvider>, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
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
