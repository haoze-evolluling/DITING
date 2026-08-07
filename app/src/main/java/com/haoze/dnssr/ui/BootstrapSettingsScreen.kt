package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.vpn.BootstrapHealthSnapshot
import com.haoze.dnssr.vpn.BootstrapIpEntry
import java.util.Locale

@Composable
fun BootstrapSettingsScreen(
    onBack: () -> Unit,
    title: String = "Bootstrap 设置",
    viewModel: BootstrapSettingsViewModel = viewModel()
) {
    val context = LocalContext.current
    val enabled by viewModel.enabled.collectAsStateWithLifecycle()
    val entries by viewModel.entries.collectAsStateWithLifecycle()
    val healthByIp by viewModel.healthByIp.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    var showAddDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.activate()
    }

    message?.let { msg ->
        Toast.makeText(context, localizedText(context, msg), Toast.LENGTH_SHORT).show()
        viewModel.clearMessage()
    }

    SettingsScaffold(
        title = localizedText(title),
        onBack = onBack,
        actions = {
            TextButton(onClick = { showAddDialog = true }, shape = SettingsCornerShape) {
                Text(localizedText("新增"))
            }
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsGroupTitle(localizedText("全局开关"))
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("启用 Bootstrap IP"),
                            subtitle = localizedText("使用独立递归 DNS 解析 DoH/DoT 服务商域名，失败时自动尝试备用 IP"),
                            checked = enabled,
                            onCheckedChange = viewModel::setEnabled
                        )
                    }
                )
                SettingsInfoText(localizedText("关闭后 DoH 使用系统 DNS，DoT 直接连接服务商域名。"))
            }

            item {
                val presets = entries.filter { it.isPreset }
                SettingsGroupTitle(localizedText("内置 Bootstrap IP"))
                SettingsSurfaceGroup(
                    content = presets.map { entry ->
                        {
                            BootstrapEntryItem(
                                entry = entry,
                                enabled = enabled,
                                health = healthByIp[entry.id],
                                onCheckedChange = { viewModel.setEntryEnabled(entry.id, it) }
                            )
                        }
                    }
                )
            }

            item {
                val customEntries = entries.filterNot { it.isPreset }
                SettingsGroupTitle(localizedText("自定义 Bootstrap IP"))
                if (customEntries.isEmpty()) {
                    SettingsInfoText(localizedText("暂无自定义 Bootstrap IP。点击右上角“新增”添加。"))
                } else {
                    SettingsSurfaceGroup(
                        content = customEntries.map { entry ->
                            {
                                BootstrapEntryItem(
                                    entry = entry,
                                    enabled = enabled,
                                    health = healthByIp[entry.id],
                                    onCheckedChange = { viewModel.setEntryEnabled(entry.id, it) },
                                    onDelete = { viewModel.deleteCustom(entry.id) }
                                )
                            }
                        }
                    )
                }
            }

        }
    }

    if (showAddDialog) {
        AddBootstrapDialog(
            onDismiss = { showAddDialog = false },
            onConfirm = { name, ip ->
                if (viewModel.addCustom(name, ip)) {
                    showAddDialog = false
                }
            }
        )
    }
}

@Composable
private fun BootstrapEntryItem(
    entry: BootstrapIpEntry,
    enabled: Boolean,
    health: BootstrapHealthSnapshot?,
    onCheckedChange: (Boolean) -> Unit,
    onDelete: (() -> Unit)? = null
) {
    SettingsItem(
        title = entry.name,
        subtitle = bootstrapEntrySubtitle(entry, health),
        enabled = enabled,
        onClick = { onCheckedChange(!entry.enabled) }
    ) {
        Checkbox(
            checked = entry.enabled,
            onCheckedChange = onCheckedChange,
            enabled = enabled
        )
        onDelete?.let { onDeleteClick ->
            IconButton(onClick = onDeleteClick, enabled = enabled) {
                Icon(
                    imageVector = Icons.Default.Delete,
                        contentDescription = localizedText("删除")
                )
            }
        }
    }
}

@Composable
private fun AddBootstrapDialog(
    onDismiss: () -> Unit,
    onConfirm: (name: String, ip: String) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var ip by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("新增 Bootstrap IP")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(localizedText("名称（可选）")) },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = ip,
                    onValueChange = { ip = it.trim() },
                    label = { Text(localizedText("IP 地址")) },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(name, ip) },
                enabled = ip.isNotBlank()
            ) {
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
private fun bootstrapEntrySubtitle(entry: BootstrapIpEntry, health: BootstrapHealthSnapshot?): String {
    val status = when {
        health == null || health.attempts == 0 -> localizedText("暂无样本")
        System.currentTimeMillis() < health.cooldownUntil -> localizedText("冷却中")
        health.consecutiveFailures > 0 -> localizedText("连续失败 ${health.consecutiveFailures}")
        else -> localizedText("成功 ${formatPercent(health.successRate)}")
    }
    val weight = health?.predictionWeight ?: 1.0
    val samples = health?.attempts ?: 0
    val latency = health?.takeIf { it.successes > 0 }?.ewmaMs?.let { localizedText(" · 延迟 ${it.toInt()} ms") } ?: ""
    return localizedText("${entry.ip} · 权重 ${String.format(Locale.getDefault(), "%.2f", weight)}$latency · 样本 $samples · $status")
}

private fun formatPercent(value: Double): String {
    return String.format(Locale.getDefault(), "%.1f%%", value * 100.0)
}
