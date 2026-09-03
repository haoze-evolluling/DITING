package com.haoze.dnssr.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp

@Composable
internal fun PowerToggleButton(
    isRunning: Boolean,
    isBusy: Boolean,
    enabled: Boolean,
    onCenterChanged: (Offset) -> Unit,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier
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
        modifier = modifier
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
