package com.haoze.diting.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AlertDialogDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties

@Composable
fun AppAlertDialog(
    onDismissRequest: () -> Unit,
    confirmButton: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    dismissButton: @Composable (() -> Unit)? = null,
    icon: @Composable (() -> Unit)? = null,
    title: @Composable (() -> Unit)? = null,
    text: @Composable (() -> Unit)? = null,
    shape: Shape = AlertDialogDefaults.shape,
    containerColor: Color = AlertDialogDefaults.containerColor,
    iconContentColor: Color = AlertDialogDefaults.iconContentColor,
    titleContentColor: Color = AlertDialogDefaults.titleContentColor,
    textContentColor: Color = AlertDialogDefaults.textContentColor,
    tonalElevation: Dp = AlertDialogDefaults.TonalElevation,
    properties: DialogProperties = DialogProperties(),
    scrollable: Boolean = true
) {
    val maxHeight = LocalConfiguration.current.screenHeightDp.dp * 0.8f
    val scrollableText: (@Composable () -> Unit)? = text?.let { content ->
        {
            if (scrollable) {
                Box(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    content()
                }
            } else {
                content()
            }
        }
    }

    AlertDialog(
        onDismissRequest = onDismissRequest,
        confirmButton = confirmButton,
        modifier = Modifier
            .heightIn(max = maxHeight)
            .then(modifier),
        dismissButton = dismissButton,
        icon = icon,
        title = title,
        text = scrollableText,
        shape = shape,
        containerColor = containerColor,
        iconContentColor = iconContentColor,
        titleContentColor = titleContentColor,
        textContentColor = textContentColor,
        tonalElevation = tonalElevation,
        properties = properties
    )
}

/** 对话框底部动作按钮：统一文字按钮样式，支持破坏性操作标红。 */
@Composable
fun AppDialogButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    destructive: Boolean = false,
    enabled: Boolean = true
) {
    androidx.compose.material3.TextButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        colors = androidx.compose.material3.ButtonDefaults.textButtonColors(
            contentColor = if (destructive) androidx.compose.material3.MaterialTheme.colorScheme.error
            else androidx.compose.material3.MaterialTheme.colorScheme.primary
        )
    ) {
        androidx.compose.material3.Text(label)
    }
}

/** 统一确认提示框：标题 + 正文 + 取消与确认按钮。 */
@Composable
fun AppConfirmDialog(
    onDismissRequest: () -> Unit,
    title: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    modifier: Modifier = Modifier,
    message: String? = null,
    cancelLabel: String? = "取消",
    destructive: Boolean = false,
    confirmEnabled: Boolean = true
) {
    AppAlertDialog(
        onDismissRequest = onDismissRequest,
        modifier = modifier,
        title = { androidx.compose.material3.Text(title) },
        text = message?.let { msg ->
            { androidx.compose.material3.Text(msg, style = androidx.compose.material3.MaterialTheme.typography.bodyMedium) }
        },
        confirmButton = {
            AppDialogButton(
                label = confirmLabel,
                onClick = onConfirm,
                destructive = destructive,
                enabled = confirmEnabled
            )
        },
        dismissButton = cancelLabel?.let { label ->
            { AppDialogButton(label, onDismissRequest) }
        }
    )
}

