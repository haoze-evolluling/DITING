package com.haoze.diting.ui

import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.ui.components.AppAlertDialog as AlertDialog
import com.haoze.diting.ui.components.RuleConfirmDialog
import com.haoze.diting.ui.components.SettingsCornerShape
import kotlinx.coroutines.launch

@Composable
internal fun RewriteAddDialog(
    onDismiss: () -> Unit,
    onConfirm: suspend (domain: String, targetType: String, targetValue: String) -> Result<String>
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var domain by remember { mutableStateOf("") }
    var targetType by remember { mutableStateOf(RewriteTargetType.IPV4) }
    var targetValue by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("添加覆写规则")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = localizedText("将域名解析覆写为指定的 IPv4、IPv6 地址或 CNAME 目标域名。"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    listOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6, RewriteTargetType.CNAME).forEach { type ->
                        FilterChip(
                            selected = targetType == type,
                            onClick = {
                                targetType = type
                                error = null
                            },
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                            label = {
                                Box(
                                    modifier = Modifier.fillMaxWidth(),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(type)
                                }
                            },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                OutlinedTextField(
                    value = domain,
                    onValueChange = {
                        domain = it
                        error = null
                    },
                    label = { Text(localizedText("域名，如 example.com")) },
                    singleLine = true,
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )

                val targetLabel = when (targetType) {
                    RewriteTargetType.CNAME -> "目标域名 (CNAME)"
                    RewriteTargetType.IPV6 -> "IPv6 地址"
                    else -> "IPv4 地址"
                }

                OutlinedTextField(
                    value = targetValue,
                    onValueChange = {
                        targetValue = it
                        error = null
                    },
                    label = { Text(localizedText(targetLabel)) },
                    supportingText = error?.let { msg -> { Text(localizedText(msg)) } },
                    isError = error != null,
                    singleLine = true,
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                scope.launch {
                    val result = onConfirm(domain, targetType, targetValue)
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
internal fun RewriteEditDialog(
    item: RewriteListItem,
    onDismiss: () -> Unit,
    onConfirm: suspend (newPattern: String, newTargetType: String, newTargetValue: String) -> Result<String>
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var domain by remember { mutableStateOf(item.pattern) }
    var targetType by remember { mutableStateOf(item.targetType) }
    var targetValue by remember { mutableStateOf(item.targetValue) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("编辑覆写规则")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    listOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6, RewriteTargetType.CNAME).forEach { type ->
                        FilterChip(
                            selected = targetType == type,
                            onClick = {
                                targetType = type
                                error = null
                            },
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                            label = {
                                Box(
                                    modifier = Modifier.fillMaxWidth(),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(type)
                                }
                            },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                OutlinedTextField(
                    value = domain,
                    onValueChange = {
                        domain = it
                        error = null
                    },
                    label = { Text(localizedText("域名")) },
                    singleLine = true,
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )

                val targetLabel = when (targetType) {
                    RewriteTargetType.CNAME -> "目标域名 (CNAME)"
                    RewriteTargetType.IPV6 -> "IPv6 地址"
                    else -> "IPv4 地址"
                }

                OutlinedTextField(
                    value = targetValue,
                    onValueChange = {
                        targetValue = it
                        error = null
                    },
                    label = { Text(localizedText(targetLabel)) },
                    supportingText = error?.let { msg -> { Text(localizedText(msg)) } },
                    isError = error != null,
                    singleLine = true,
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                scope.launch {
                    val result = onConfirm(domain, targetType, targetValue)
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
internal fun RewriteDeleteConfirmDialog(
    item: RewriteListItem,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    RuleConfirmDialog(
        title = localizedText("删除覆写规则"),
        message = localizedText("确定要删除覆写规则「${item.pattern} -> ${item.targetValue}」吗？"),
        confirmText = localizedText("删除"),
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}

@Composable
internal fun RewriteClearUserConfirmDialog(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    RuleConfirmDialog(
        title = localizedText("清空自定义覆写"),
        message = localizedText("确定要清空所有由您添加的自定义覆写规则吗？规则订阅等内容不受影响。"),
        confirmText = localizedText("确认清空"),
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}
