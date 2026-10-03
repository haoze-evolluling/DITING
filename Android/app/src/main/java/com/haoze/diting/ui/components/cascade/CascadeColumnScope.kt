package com.haoze.diting.ui.components.cascade

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.LayoutScopeMarker
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.MenuItemColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment.Companion.CenterVertically
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

@Immutable
@LayoutScopeMarker
interface CascadeColumnScope : ColumnScope {
    val cascadeState: CascadeState
    val hasParentMenu: Boolean
    val isNavigationRunning: Boolean

    /**
     * 级联子菜单项：点击后向右平滑滑入嵌套子菜单。
     */
    @Composable
    fun DropdownMenuItem(
        text: @Composable () -> Unit,
        children: @Composable CascadeColumnScope.() -> Unit,
        modifier: Modifier = Modifier,
        childrenHeader: @Composable CascadeColumnScope.() -> Unit = { DropdownMenuHeader(text = text) },
        leadingIcon: @Composable (() -> Unit)? = null,
        trailingIcon: @Composable (() -> Unit)? = null,
        enabled: Boolean = true,
        colors: MenuItemColors = MenuDefaults.itemColors(),
        contentPadding: PaddingValues = MenuDefaults.DropdownMenuItemContentPadding,
        interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    ) {
        DropdownMenuItem(
            text = text,
            onClick = {
                cascadeState.navigateTo(
                    CascadeBackStackEntry(
                        header = childrenHeader,
                        childrenContent = children
                    )
                )
            },
            modifier = modifier,
            leadingIcon = leadingIcon,
            trailingIcon = {
                Row(verticalAlignment = CenterVertically) {
                    trailingIcon?.invoke()
                    val requiredGapWithEdge = 4.dp
                    val iconOffset = contentPadding.calculateEndPadding(LocalLayoutDirection.current) - requiredGapWithEdge
                    Icon(
                        modifier = Modifier
                            .offset(x = iconOffset)
                            .size(24.dp)
                            .wrapContentSize(),
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null
                    )
                }
            },
            enabled = enabled,
            colors = colors,
            contentPadding = contentPadding,
            interactionSource = interactionSource,
        )
    }

    /**
     * 标准菜单项：点击后执行回调。
     */
    @Composable
    fun DropdownMenuItem(
        text: @Composable () -> Unit,
        onClick: () -> Unit,
        modifier: Modifier = Modifier,
        leadingIcon: @Composable (() -> Unit)? = null,
        trailingIcon: @Composable (() -> Unit)? = null,
        enabled: Boolean = true,
        colors: MenuItemColors = MenuDefaults.itemColors(),
        contentPadding: PaddingValues = MenuDefaults.DropdownMenuItemContentPadding,
        interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    ) {
        androidx.compose.material3.DropdownMenuItem(
            text = text,
            onClick = onClick,
            modifier = modifier,
            leadingIcon = leadingIcon,
            trailingIcon = trailingIcon,
            enabled = enabled,
            colors = colors,
            contentPadding = contentPadding,
            interactionSource = interactionSource,
        )
    }

    /**
     * 级联子菜单头部组件：展示标题与返回箭头，点击返回上一级菜单。
     */
    @Composable
    fun DropdownMenuHeader(
        modifier: Modifier = Modifier,
        contentPadding: PaddingValues = PaddingValues(10.5.dp),
        text: @Composable () -> Unit,
    ) {
        Row(
            modifier = modifier
                .fillMaxWidth()
                .clickable(enabled = hasParentMenu, role = Role.Button) {
                    if (!isNavigationRunning) {
                        cascadeState.navigateBack()
                    }
                }
                .padding(contentPadding),
            verticalAlignment = CenterVertically,
        ) {
            val headerColor = LocalContentColor.current.copy(alpha = 0.6f)
            val headerStyle = MaterialTheme.typography.labelLarge.run {
                copy(
                    fontSize = fontSize * 0.9f,
                    letterSpacing = letterSpacing * 0.9f
                )
            }
            CompositionLocalProvider(
                LocalContentColor provides headerColor,
                LocalTextStyle provides headerStyle
            ) {
                if (this@CascadeColumnScope.hasParentMenu) {
                    Icon(
                        modifier = Modifier
                            .padding(end = contentPadding.calculateEndPadding(LocalLayoutDirection.current))
                            .size(16.dp),
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                        contentDescription = null,
                        tint = headerColor
                    )
                }
                Box(Modifier.weight(1f)) {
                    text()
                }
            }
        }
    }
}
