package com.haoze.diting.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.RuleConfirmDialog
import com.haoze.diting.ui.components.SettingsCornerShape
import kotlinx.coroutines.launch

@Composable
internal fun BlacklistAddDialog(
    dataset: RuleDataset,
    onDismiss: () -> Unit,
    onBatchAdd: () -> Unit,
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
        title = { Text(localizedText("添加黑名单规则")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = localizedText(
                        if (dataset == RuleDataset.NORMAL && com.haoze.diting.ui.mode.WorkModeStore.getAppWorkMode(context) != com.haoze.diting.ui.mode.AppWorkMode.EXPRESS) {
                            "支持域名（如 example.com）、AdGuard 规则（||example.com^）、URL 屏蔽前缀或元素隐藏规则（如 com.app##.ad）。"
                        } else {
                            "支持域名（如 example.com、*.google.com）或 AdGuard 规则（||example.com^）。"
                        }
                    ),
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
internal fun BlacklistEditDialog(
    item: BlacklistItem,
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
        title = { Text(localizedText("编辑黑名单规则")) },
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
                if (item.type == BlacklistType.DOMAIN) {
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
internal fun BlacklistDeleteConfirmDialog(
    item: BlacklistItem,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val message = if (item.isUserRule && !item.isSubscription) {
        "确定要删除自定义黑名单规则「${item.pattern}」吗？"
    } else {
        "确定要删除黑名单规则「${item.pattern}」吗？"
    }
    RuleConfirmDialog(
        title = localizedText("删除黑名单规则"),
        message = localizedText(message),
        confirmText = localizedText("删除"),
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}

@Composable
internal fun BlacklistClearUserConfirmDialog(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    RuleConfirmDialog(
        title = localizedText("清空自定义黑名单"),
        message = localizedText("确定要清空所有由您添加的自定义黑名单规则吗？规则订阅等内容不受影响。"),
        confirmText = localizedText("确认清空"),
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}
