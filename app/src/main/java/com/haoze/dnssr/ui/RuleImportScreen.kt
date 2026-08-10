package com.haoze.dnssr.ui

import android.net.Uri
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.ui.components.AppAlertDialog
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import kotlinx.coroutines.delay

private data class LocalImportRequest(
    val uri: Uri,
    val title: String,
    val kind: String,
    val scope: RuleScope
)

@Composable
fun RuleImportScreen(
    onBack: () -> Unit,
    title: String = "规则导入",
    viewModel: RuleImportViewModel = viewModel()
) {
    val context = LocalContext.current
    val message by viewModel.message.collectAsStateWithLifecycle()
    val importing by viewModel.importing.collectAsStateWithLifecycle()
    val progress by viewModel.progress.collectAsStateWithLifecycle()
    var pendingRequest by remember { mutableStateOf<LocalImportRequest?>(null) }
    var selectedAction by remember { mutableStateOf<((Uri) -> Unit)?>(null) }
    val documentLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { selectedAction?.invoke(it) }
        selectedAction = null
    }

    message?.let { result ->
        androidx.compose.runtime.LaunchedEffect(result) {
            Toast.makeText(context, localizedText(context, result), Toast.LENGTH_LONG).show()
            delay(3000)
            viewModel.clearMessage()
        }
    }

    fun selectLocalSubscription(titleText: String, kind: String, scope: RuleScope) {
        selectedAction = { uri -> pendingRequest = LocalImportRequest(uri, titleText, kind, scope) }
        documentLauncher.launch(arrayOf("text/plain", "text/*", "application/octet-stream"))
    }

    fun selectAddressBackup() {
        selectedAction = viewModel::restoreAddressBackup
        documentLauncher.launch(arrayOf("application/json", "text/json", "text/plain", "application/octet-stream"))
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (importing) {
                val (current, total) = progress
                SettingsInfoText(
                    text = localizedText(if (total > 0) "正在导入规则... $current / $total" else "正在导入规则..."),
                    modifier = Modifier.padding(top = 8.dp)
                )
                LinearProgressIndicator(
                    progress = { if (total > 0) current.toFloat() / total else 0f },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
            SettingsGroupTitle(localizedText("域名规则 · TXT 订阅文件"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                        title = localizedText("导入 DNS 过滤和白名单 TXT"),
                        subtitle = localizedText("导入 DNS 过滤规则和白名单，创建不可更新的本地订阅"),
                        leadingIcon = Icons.Default.FolderOpen,
                        enabled = !importing,
                        onClick = { selectLocalSubscription("导入 DNS 过滤和白名单 TXT", SubscriptionKind.BLOCK, RuleScope.DNS) }
                    )
                )
            )
            SettingsGroupTitle(localizedText("外部 hosts 文件"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                        title = localizedText("导入 hosts 覆写 TXT"),
                        subtitle = localizedText("导入 IP 地址映射规则，创建不可更新的本地覆写订阅"),
                        leadingIcon = Icons.Default.FolderOpen,
                        enabled = !importing,
                        onClick = { selectLocalSubscription("导入 hosts 覆写 TXT", SubscriptionKind.REWRITE, RuleScope.DNS) }
                    )
                )
            )
            SettingsGroupTitle(localizedText("地址规则"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                        title = localizedText("导入地址规则 JSON 备份"),
                        subtitle = localizedText("恢复手动添加的 URL 屏蔽和放行规则，不创建订阅"),
                        leadingIcon = Icons.Default.FolderOpen,
                        enabled = !importing,
                        onClick = ::selectAddressBackup
                    )
                )
            )
            SettingsInfoText(
                text = localizedText("DNS 规则和 hosts 规则导入后均为不可更新的本地订阅；地址 JSON 备份会恢复为手动 URL 规则。"),
                modifier = Modifier.padding(top = 8.dp)
            )
        }
    }

    pendingRequest?.let { request ->
        LocalRuleSubscriptionNameDialog(
            title = request.title,
            initialName = remember(request.uri) { context.displayNameForRuleImport(request.uri) },
            onDismiss = { pendingRequest = null },
            onConfirm = { name ->
                viewModel.importLocalSubscription(request.uri, name, request.kind, request.scope)
                pendingRequest = null
            }
        )
    }
}

@Composable
private fun LocalRuleSubscriptionNameDialog(
    title: String,
    initialName: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var name by remember(initialName) { mutableStateOf(initialName) }
    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText(title)) },
        text = {
            Column {
                Text(localizedText("本地订阅导入后无法更新。"), style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(localizedText("订阅名称")) },
                    singleLine = true,
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(name.trim()) }, enabled = name.isNotBlank()) { Text(localizedText("导入规则")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(localizedText("取消")) } }
    )
}

private fun android.content.Context.displayNameForRuleImport(uri: Uri): String {
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (nameIndex >= 0 && cursor.moveToFirst()) {
            cursor.getString(nameIndex)?.takeIf { it.isNotBlank() }?.let { return it }
        }
    }
    return localizedText(this, "本地规则")
}
