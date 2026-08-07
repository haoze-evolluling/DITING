package com.haoze.dnssr.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.localizedText

/**
 * 统一设置页 Scaffold：顶部标题栏 + 返回按钮。
 * content 接收 innerPadding，由各页面自行决定滚动方式。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScaffold(
    title: String,
    onBack: () -> Unit,
    titleTrailing: @Composable RowScope.() -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {},
    belowTopBar: @Composable ColumnScope.() -> Unit = {},
    content: @Composable (PaddingValues) -> Unit
) {
    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.background,
                        scrolledContainerColor = MaterialTheme.colorScheme.background
                    ),
                    title = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(localizedText(title))
                            titleTrailing()
                        }
                    },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = localizedText("返回")
                            )
                        }
                    },
                    actions = actions
                )
                belowTopBar()
            }
        }
    ) { innerPadding ->
        content(innerPadding)
    }
}

/**
 * 设置页统一的圆角幅度，与分组卡片外圈圆角保持一致。
 */
val SettingsCornerShape = RoundedCornerShape(12.dp)
private val SettingsGroupCornerShape = RoundedCornerShape(28.dp)
private val DefaultSettingsItemContentPadding = PaddingValues(horizontal = 24.dp, vertical = 16.dp)
val SettingsSectionSpacing = 12.dp
val SettingsItemSpacing = 2.dp

data class SettingsNavigationItemData(
    val title: String,
    val subtitle: String? = null,
    val leadingIcon: ImageVector? = null,
    val value: String? = null,
    val valueMaxScreenFraction: Float? = null,
    val enabled: Boolean = true,
    val onClick: () -> Unit,
    val contentPadding: PaddingValues? = null
)

/**
 * BLUKE 风格的独立圆角卡片组，可承载导航项以外的设置控件或数据项。
 */
@Composable
fun SettingsSurfaceGroup(
    content: List<@Composable () -> Unit>,
    modifier: Modifier = Modifier,
    groupContentPadding: PaddingValues = PaddingValues(horizontal = 16.dp),
    containerColor: Color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
) {
    if (content.isEmpty()) return

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(groupContentPadding),
        verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
    ) {
        content.forEachIndexed { index, itemContent ->
            SettingsSurfaceItem(
                index = index,
                itemCount = content.size,
                containerColor = containerColor,
                content = itemContent
            )
        }
    }
}

@Composable
fun SettingsSurfaceItem(
    index: Int,
    itemCount: Int,
    modifier: Modifier = Modifier,
    containerColor: Color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
    content: @Composable () -> Unit
) {
    val topRadius = if (index == 0) 28.dp else 4.dp
    val bottomRadius = if (index == itemCount - 1) 28.dp else 4.dp
    val shape = RoundedCornerShape(
        topStart = topRadius,
        topEnd = topRadius,
        bottomStart = bottomRadius,
        bottomEnd = bottomRadius
    )
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape),
        shape = shape,
        color = containerColor,
        content = content
    )
}

/**
 * BLUKE 风格导航分组：每个可导航项独立裁剪，条目之间保留 2.dp 间距。
 */
@Composable
fun SettingsNavigationGroup(
    items: List<SettingsNavigationItemData>,
    modifier: Modifier = Modifier
) {
    SettingsSurfaceGroup(
        modifier = modifier,
        content = items.map { item ->
            {
                SettingsNavigationItem(
                    title = item.title,
                    subtitle = item.subtitle,
                    leadingIcon = item.leadingIcon,
                    value = item.value,
                    valueMaxScreenFraction = item.valueMaxScreenFraction,
                    enabled = item.enabled,
                    onClick = item.onClick,
                    contentPadding = item.contentPadding ?: PaddingValues(
                        horizontal = 24.dp,
                        vertical = if (item.subtitle == null && item.leadingIcon == null) 12.dp else 20.dp
                    )
                )
            }
        }
    )
}

/**
 * 页面主要操作按钮，使用统一的圆角矩形形状。
 */
@Composable
fun SettingsActionButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        shape = SettingsCornerShape,
        content = content
    )
}

/**
 * 页面次要操作按钮，使用统一的圆角矩形形状。
 */
@Composable
fun SettingsOutlinedActionButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    contentPadding: PaddingValues = ButtonDefaults.ContentPadding,
    content: @Composable RowScope.() -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        shape = SettingsCornerShape,
        contentPadding = contentPadding,
        content = content
    )
}

/**
 * iOS 风格分组卡片：圆角、白色/表面色背景、水平外边距。
 */
@Composable
fun SettingsGroup(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = SettingsGroupCornerShape,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f)
        )
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            content = content
        )
    }
}

/**
 * 分组标题（Section Header），位于分组卡片上方。
 */
@Composable
fun SettingsGroupTitle(
    text: String,
    modifier: Modifier = Modifier
) {
    Text(
        text = localizedText(text),
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier
            .padding(start = 24.dp, top = 24.dp, bottom = 8.dp, end = 24.dp)
            .fillMaxWidth()
    )
}

/**
 * 分组底部说明文字。
 */
@Composable
fun SettingsInfoText(
    text: String,
    modifier: Modifier = Modifier
) {
    Text(
        text = localizedText(text),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier
            .padding(start = 24.dp, top = 4.dp, bottom = 8.dp, end = 24.dp)
            .fillMaxWidth()
    )
}

/**
 * 设置二级页通用的初始加载占位。
 */
@Composable
fun SettingsLoadingContent(
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator()
    }
}

/**
 * 基础列表项。高度最低 44.dp，左侧标题区，右侧 trailing 内容。
 */
@Composable
fun SettingsItem(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leadingIcon: ImageVector? = null,
    titleColor: Color = MaterialTheme.colorScheme.onSurface,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    subtitleContent: @Composable ColumnScope.() -> Unit = {},
    contentPadding: PaddingValues = DefaultSettingsItemContentPadding,
    trailing: @Composable RowScope.() -> Unit = {}
) {
    val rowModifier = if (onClick != null) {
        modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
    } else {
        modifier.fillMaxWidth()
    }

    Row(
        modifier = rowModifier
            .heightIn(min = 44.dp)
            .padding(contentPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        leadingIcon?.let { icon ->
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = localizedText(title),
                style = MaterialTheme.typography.bodyLarge,
                color = if (enabled) titleColor else titleColor.copy(alpha = 0.38f)
            )
            subtitle?.let {
                Text(
                    text = localizedText(it),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                        alpha = if (enabled) 1f else 0.38f
                    )
                )
            }
            subtitleContent()
        }

        trailing()
    }
}

/**
 * 开关项：整行可点击切换。
 */
@Composable
fun SettingsSwitchItem(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
    contentPadding: PaddingValues = DefaultSettingsItemContentPadding
) {
    SettingsItem(
        title = title,
        subtitle = subtitle,
        modifier = modifier,
        contentPadding = contentPadding,
        enabled = enabled,
        onClick = { onCheckedChange(!checked) }
    ) {
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled
        )
    }
}

/**
 * 复选框项：整行可点击切换勾选状态。
 */
@Composable
fun SettingsCheckboxItem(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
    contentPadding: PaddingValues = DefaultSettingsItemContentPadding
) {
    SettingsItem(
        title = title,
        subtitle = subtitle,
        modifier = modifier,
        contentPadding = contentPadding,
        enabled = enabled,
        onClick = { onCheckedChange(!checked) }
    ) {
        Checkbox(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled
        )
    }
}

/**
 * 导航项：右侧显示当前值与箭头。
 */
@Composable
fun SettingsNavigationItem(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leadingIcon: ImageVector? = null,
    value: String? = null,
    valueMaxScreenFraction: Float? = null,
    enabled: Boolean = true,
    onClick: () -> Unit,
    contentPadding: PaddingValues = DefaultSettingsItemContentPadding
) {
    val configuration = LocalConfiguration.current
    val valueMaxWidth = valueMaxScreenFraction
        ?.coerceIn(0.1f, 1f)
        ?.let { (configuration.screenWidthDp.dp * it) }

    SettingsItem(
        title = title,
        subtitle = subtitle,
        leadingIcon = leadingIcon,
        modifier = modifier,
        contentPadding = contentPadding,
        enabled = enabled,
        onClick = onClick
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            value?.let {
                Text(
                    text = localizedText(it),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                        alpha = if (enabled) 1f else 0.38f
                    ),
                    textAlign = TextAlign.End,
                    modifier = valueMaxWidth?.let { maxWidth ->
                        Modifier.widthIn(max = maxWidth)
                    } ?: Modifier
                )
            }
            if (enabled) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * 文本/操作项：可用于普通操作或危险操作。
 */
@Composable
fun SettingsTextItem(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    subtitleContent: @Composable ColumnScope.() -> Unit = {},
    textColor: Color = MaterialTheme.colorScheme.onSurface,
    enabled: Boolean = true,
    onClick: () -> Unit,
    contentPadding: PaddingValues = DefaultSettingsItemContentPadding,
    trailing: @Composable RowScope.() -> Unit = {}
) {
    SettingsItem(
        title = title,
        subtitle = subtitle,
        subtitleContent = subtitleContent,
        titleColor = textColor,
        modifier = modifier,
        contentPadding = contentPadding,
        enabled = enabled,
        onClick = onClick,
        trailing = trailing
    )
}

/**
 * 单选项：选中时右侧显示对勾。
 */
@Composable
fun SettingsRadioItem(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
    contentPadding: PaddingValues = DefaultSettingsItemContentPadding
) {
    SettingsItem(
        title = title,
        subtitle = subtitle,
        modifier = modifier,
        contentPadding = contentPadding,
        enabled = enabled,
        onClick = onClick
    ) {
        if (selected) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = localizedText("已选中"),
                tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
            )
        }
    }
}

/**
 * 旧调用点兼容 API：使用间距替代组内横线。
 */
@Composable
fun SettingsDivider(modifier: Modifier = Modifier) {
    androidx.compose.foundation.layout.Spacer(
        modifier = modifier
            .fillMaxWidth()
            .height(2.dp)
    )
}
