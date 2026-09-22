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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.AppAlertDialog as AlertDialog
import com.haoze.diting.ui.components.RuleConfirmDialog
import com.haoze.diting.ui.components.SettingsCornerShape
import kotlinx.coroutines.launch

@Composable
internal fun WhitelistRiskWarningDialog(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
        title = { Text(localizedText("风险提示")) },
        text = {
            Text(
                localizedText("修改软件预设白名单可能造成不可预料的影响，例如网络异常或网络连接中断。\n\n如非排查特定网络问题，建议保持默认设置。确定要开启编辑权限吗？")
            )
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(localizedText("确定开启"), color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}

@Composable
internal fun WhitelistAddDialog(
    onDismiss: () -> Unit,
    onConfirm: suspend (input: String, appScope: String?, important: Boolean) -> Result<String>
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var appScope by remember { mutableStateOf("") }
    var important by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("添加白名单规则")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = localizedText("支持域名（如 example.com、*.google.com）、AdGuard 白名单（@@||example.com^）或 URL 放行前缀（https://example.com/api）。"),
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
            TextButton(onClick = {
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
            }) {
                Text(localizedText("添加"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
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

    AlertDialog(
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
            TextButton(onClick = {
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
            }) {
                Text(localizedText("保存"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
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
