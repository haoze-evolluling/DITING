package com.haoze.dnssr.ui.apprule

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.InstalledApp
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.RuleConfirmDialog
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.localizedText

@Composable
internal fun FullBlockConfirmDialog(
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    RuleConfirmDialog(
        title = localizedText("开启全外联拦截？"),
        message = localizedText("开启后该应用的所有常规网络连接都将被阻断，仅白名单域名可通行。若未添加放行白名单，可能导致应用无法使用。"),
        confirmText = localizedText("确定开启"),
        onConfirm = onConfirm,
        onDismiss = onDismiss
    )
}

@Composable
internal fun ClearAllowlistConfirmDialog(
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    RuleConfirmDialog(
        title = localizedText("清空放行域名？"),
        message = localizedText("此操作将移除该应用配置的所有网络层放行域名。"),
        confirmText = localizedText("清空"),
        onConfirm = onConfirm,
        onDismiss = onDismiss
    )
}

@Composable
internal fun ClearAllAllowlistDialog(
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    RuleConfirmDialog(
        title = localizedText("清空全部放行规则？"),
        message = localizedText("此操作将清空所有已配置的单应用域名放行规则，清空后各应用将恢复全部放行状态。"),
        confirmText = localizedText("清空"),
        onConfirm = onConfirm,
        onDismiss = onDismiss
    )
}

@Composable
internal fun AddAllowlistDomainDialog(
    app: InstalledApp,
    onDismiss: () -> Unit,
    onConfirm: (domain: String) -> Unit
) {
    var addAllowlistInput by remember { mutableStateOf("") }
    var addAllowlistError by remember { mutableStateOf<String?>(null) }

    fun submit() {
        val d = addAllowlistInput.trim()
        if (d.isBlank()) {
            addAllowlistError = "请输入有效的域名"
        } else {
            onConfirm(d)
            onDismiss()
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("添加放行域名")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = localizedText("目标应用：${app.label} (${app.packageName})"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary
                )
                OutlinedTextField(
                    value = addAllowlistInput,
                    onValueChange = {
                        addAllowlistInput = it
                        addAllowlistError = null
                    },
                    label = { Text(localizedText("域名")) },
                    placeholder = { Text("example.com") },
                    supportingText = {
                        Text(localizedText(addAllowlistError ?: "例如 example.com，将自动放行该域名及其所有子域名"))
                    },
                    isError = addAllowlistError != null,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(
                        onDone = { submit() }
                    ),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { submit() }) {
                Text(localizedText("确定"))
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
internal fun AddDnsRuleDialog(
    app: InstalledApp,
    isAllow: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (pattern: String, isAllow: Boolean, important: Boolean, isWildcard: Boolean) -> Unit
) {
    var addDialogPattern by remember { mutableStateOf("") }
    var addDialogImportant by remember { mutableStateOf(false) }
    var addDialogError by remember { mutableStateOf<String?>(null) }

    fun submit() {
        val pattern = addDialogPattern.trim()
        if (pattern.isBlank()) {
            addDialogError = "请输入域名或通配符规则"
        } else {
            val isWc = pattern.contains('*')
            onConfirm(pattern, isAllow, addDialogImportant, isWc)
            onDismiss()
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(localizedText(if (isAllow) "添加应用专属白名单" else "添加应用专属拦截规则"))
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = localizedText("目标应用：${app.label} (${app.packageName})"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary
                )
                OutlinedTextField(
                    value = addDialogPattern,
                    onValueChange = {
                        addDialogPattern = it
                        addDialogError = null
                    },
                    label = { Text(localizedText("域名或通配符规则")) },
                    placeholder = { Text(localizedText("如 example.com 或 *-analytics.google.com")) },
                    supportingText = {
                        Text(localizedText(addDialogError ?: "支持通配符模式（如 * 或 *-analytics.google.com）"))
                    },
                    isError = addDialogError != null,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(
                        onDone = { submit() }
                    ),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { addDialogImportant = !addDialogImportant }
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = addDialogImportant,
                        onCheckedChange = { addDialogImportant = it }
                    )
                    Column(modifier = Modifier.padding(start = 8.dp)) {
                        Text(
                            text = localizedText("高优先级 (\$important)"),
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Text(
                            text = localizedText("确保该规则优先于其他常规规则生效"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { submit() }) {
                Text(localizedText("确定"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}
