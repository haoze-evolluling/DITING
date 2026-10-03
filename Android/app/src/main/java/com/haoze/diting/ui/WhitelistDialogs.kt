package com.haoze.diting.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.RuleConfirmDialog
import com.haoze.diting.ui.components.SettingsCornerShape
import kotlinx.coroutines.launch

@Composable
internal fun WhitelistRiskWarningDialog(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AppConfirmDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
        title = "风险提示",
        message = "修改软件预设白名单可能造成不可预料的影响，例如网络异常或网络连接中断。\n\n如非排查特定网络问题，建议保持默认设置。确定要开启编辑权限吗？",
        confirmLabel = "确定开启",
        cancelLabel = "取消",
        destructive = true,
        onConfirm = onConfirm
    )
}

@Composable
internal fun WhitelistAddDialog(
    onDismiss: () -> Unit,
    onBatchAdd: () -> Unit = {},
    onConfirm: suspend (input: String, appScope: String?, important: Boolean) -> Result<String>
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var appScope by remember { mutableStateOf("") }
    var important by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("添加白名单规则")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = localizedText("支持域名（如 example.com）、AdGuard 白名单（@@||example.com^）、URL 放行前缀或元素放行规则（如 com.app#@#.ad）。"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                OutlinedTextField(
                    value = input,
                    onValueChange = {
                        input = it
                        error = null
                    },
                    label = { Text(localizedText("规则内容")) },
                    singleLine = true,
                    isError = error != null,
                    supportingText = error?.let { msg -> { Text(msg) } },
                    shape = SettingsCornerShape
                )
                OutlinedTextField(
                    value = appScope,
                    onValueChange = { appScope = it },
                    label = { Text(localizedText("指定应用包名 (可选)")) },
                    placeholder = { Text("com.example.app") },
                    singleLine = true,
                    shape = SettingsCornerShape
                )
            }
        },
        confirmButton = {
            AppDialogButton(
                label = "添加",
                onClick = {
                    scope.launch {
                        val result = onConfirm(
                            input,
                            appScope.trim().takeIf { it.isNotEmpty() },
                            important
                        )
                        result.onSuccess { msg ->
                            context.showToast(msg, Toast.LENGTH_SHORT)
                            onDismiss()
                        }.onFailure { err ->
                            error = err.message ?: localizedText(context, "添加失败")
                        }
                    }
                }
            )
        },
        dismissButton = {
            AppDialogButton(label = "取消", onClick = onDismiss)
        },
        neutralButton = {
            AppDialogButton(
                label = "批量添加",
                onClick = {
                    onDismiss()
                    onBatchAdd()
                }
            )
        }
    )
}

@Composable
internal fun WhitelistEditDialog(
    item: WhitelistItem,
    onDismiss: () -> Unit,
    onConfirm: suspend (newPattern: String, newAppScope: String?, newImportant: Boolean) -> Result<String>
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var input by remember(item) { mutableStateOf(item.rawLine) }
    var appScope by remember(item) { mutableStateOf(item.appScope.orEmpty()) }
    var important by remember(item) { mutableStateOf(item.important) }
    var error by remember(item) { mutableStateOf<String?>(null) }

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText(if (item.isPreset) "编辑默认预设规则" else "编辑白名单规则")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = input,
                    onValueChange = {
                        input = it
                        error = null
                    },
                    label = { Text(localizedText("规则内容")) },
                    singleLine = true,
                    isError = error != null,
                    supportingText = error?.let { msg -> { Text(msg) } },
                    shape = SettingsCornerShape
                )
                if (item.type == WhitelistType.DOMAIN) {
                    OutlinedTextField(
                        value = appScope,
                        onValueChange = { appScope = it },
                        label = { Text(localizedText("指定应用包名 (可选)")) },
                        placeholder = { Text("com.example.app") },
                        singleLine = true,
                        shape = SettingsCornerShape
                    )
                }
            }
        },
        confirmButton = {
            AppDialogButton(
                label = "保存",
                onClick = {
                    scope.launch {
                        val result = onConfirm(
                            input,
                            appScope.trim().takeIf { it.isNotEmpty() },
                            important
                        )
                        result.onSuccess { msg ->
                            context.showToast(msg, Toast.LENGTH_SHORT)
                            onDismiss()
                        }.onFailure { err ->
                            error = err.message ?: localizedText(context, "修改失败")
                        }
                    }
                }
            )
        },
        dismissButton = {
            AppDialogButton(label = "取消", onClick = onDismiss)
        }
    )
}

@Composable
internal fun WhitelistDeleteConfirmDialog(
    item: WhitelistItem,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val deletePrompt = if (item.isPreset) {
        localizedText("确定要删除默认预设白名单规则「${item.pattern}」吗？若网络异常可通过右上角菜单重置恢复。")
    } else if (item.isSubscription) {
        localizedText("确定要删除白名单规则「${item.pattern}」吗？")
    } else {
        localizedText("确定要删除自定义白名单规则「${item.pattern}」吗？")
    }
    RuleConfirmDialog(
        title = localizedText("删除白名单规则"),
        message = deletePrompt,
        confirmText = localizedText("删除"),
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}

@Composable
internal fun WhitelistResetDefaultsConfirmDialog(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    RuleConfirmDialog(
        title = localizedText("重置默认白名单"),
        message = localizedText("确定要将软件预设的默认白名单重置为初始状态吗？此操作不会影响您自己添加的自定义白名单。"),
        confirmText = localizedText("确认重置"),
        destructive = false,
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}

@Composable
internal fun WhitelistClearUserConfirmDialog(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    RuleConfirmDialog(
        title = localizedText("清空自定义白名单"),
        message = localizedText("确定要清空所有由您添加的自定义白名单规则吗？软件预设的默认白名单将予以保留。"),
        confirmText = localizedText("确认清空"),
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}
