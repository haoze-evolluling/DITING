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
 * Shared settings-page Scaffold: top title bar with a back button.
 * [content] receives innerPadding and each page decides its own scrolling behavior.
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
    SettingsScaffold(
        titleContent = {
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(localizedText(title))
                titleTrailing()
            }
        },
        onBack = onBack,
        actions = actions,
        belowTopBar = belowTopBar,
        content = content
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScaffold(
    titleContent: @Composable () -> Unit,
    onBack: () -> Unit,
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
                    title = titleContent,
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
 * Corner radius used across settings pages, kept consistent with the outer radius of group cards.
 */
val SettingsCornerShape = RoundedCornerShape(12.dp)
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
 * BLUKE-style standalone rounded card group; can host settings controls or data items beyond navigation entries.
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
 * BLUKE-style navigation group: each navigable item is clipped independently, with 2.dp spacing between entries.
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
 * Primary action button of a page, using the shared rounded-rectangle shape.
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
 * Secondary action button of a page, using the shared rounded-rectangle shape.
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
 * Section header placed above a group card.
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
 * Supporting caption at the bottom of a group.
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
 * Shared initial-loading placeholder for settings sub-pages.
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
 * Basic list item: minimum height 44.dp, title block on the left, trailing content on the right.
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
 * Switch row: the whole row is clickable to toggle.
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
 * Checkbox row: the whole row is clickable to toggle the checked state.
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
 * Navigation row: shows the current value and a chevron on the right.
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
 * Text/action row: usable for ordinary actions or destructive ones.
 */
@Composable
fun SettingsTextItem(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leadingIcon: ImageVector? = null,
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
        leadingIcon = leadingIcon,
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
 * Radio row: shows a check mark on the right when selected.
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
 * Backward-compatible wrapper for older call sites: replaces in-group dividers with spacing.
 */
@Composable
fun SettingsDivider(modifier: Modifier = Modifier) {
    androidx.compose.foundation.layout.Spacer(
        modifier = modifier
            .fillMaxWidth()
            .height(2.dp)
    )
}
