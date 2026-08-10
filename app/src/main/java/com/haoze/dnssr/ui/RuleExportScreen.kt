package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun RuleExportScreen(
    onBack: () -> Unit,
    title: String = "规则导出",
    viewModel: ConfigTransferViewModel = viewModel()
) {
    val context = LocalContext.current
    val operation by viewModel.operation.collectAsState()
    val exportProgress by viewModel.ruleExportProgress.collectAsState()
    val exportProgressText by viewModel.ruleExportProgressText.collectAsState()
    val message by viewModel.message.collectAsState()
    var exportCategory by remember { mutableStateOf(RuleExportCategory.DOMAIN) }
    val textExportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/plain")
    ) { uri -> uri?.let { viewModel.exportRules(it, exportCategory) } }
    val jsonExportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri -> uri?.let { viewModel.exportRules(it, exportCategory) } }

    fun export(category: RuleExportCategory) {
        exportCategory = category
        val date = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
        val fileName = "谛听-${category.storageValue}-$date.${if (category == RuleExportCategory.DOMAIN) "txt" else "json"}"
        if (category == RuleExportCategory.DOMAIN) textExportLauncher.launch(fileName) else jsonExportLauncher.launch(fileName)
    }

    LaunchedEffect(message) {
        message?.let {
            Toast.makeText(context, localizedText(context, it), Toast.LENGTH_LONG).show()
            viewModel.clearMessage()
        }
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(innerPadding).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsInfoText(
                text = localizedText("域名规则导出当前所有已生效的过滤和放行规则，可作为本地订阅重新导入；地址规则导出手动 URL 规则的 JSON 备份。"),
                modifier = Modifier.padding(top = 8.dp)
            )
            SettingsGroupTitle(localizedText("域名规则 · TXT 订阅文件"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                        title = localizedText("导出当前生效域名规则"),
                        subtitle = localizedText("保存为 TXT 订阅文件，可通过“导入域名规则 TXT 文件”重新导入"),
                        leadingIcon = Icons.Filled.FileDownload,
                        enabled = operation == ConfigTransferOperation.IDLE,
                        onClick = { export(RuleExportCategory.DOMAIN) }
                    )
                )
            )
            ExportProgress(operation, exportCategory, RuleExportCategory.DOMAIN, exportProgress, exportProgressText)
            SettingsGroupTitle(localizedText("地址规则 · JSON 备份文件"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                        title = localizedText("导出地址规则备份"),
                        subtitle = localizedText("保存手动添加的 URL 屏蔽和放行规则，可完整导入恢复"),
                        leadingIcon = Icons.Filled.FileDownload,
                        enabled = operation == ConfigTransferOperation.IDLE,
                        onClick = { export(RuleExportCategory.ADDRESS) }
                    )
                )
            )
            ExportProgress(operation, exportCategory, RuleExportCategory.ADDRESS, exportProgress, exportProgressText)
        }
    }
}

@Composable
private fun ExportProgress(
    operation: ConfigTransferOperation,
    exportCategory: RuleExportCategory,
    category: RuleExportCategory,
    exportProgress: Float,
    exportProgressText: String
) {
    if (operation != ConfigTransferOperation.EXPORTING || exportCategory != category) return
    LinearProgressIndicator(
        progress = { exportProgress },
        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp)
    )
    Text(
        text = localizedText(exportProgressText),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 24.dp)
    )
}
