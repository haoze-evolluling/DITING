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
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsTextItem
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import com.haoze.dnssr.data.entity.RuleScope

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
    var exportRequest by remember { mutableStateOf(RuleExportRequest(RuleExportType.ALL, RuleScope.DNS)) }
    val textExportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/plain")
    ) { uri -> uri?.let { viewModel.exportRules(it, exportRequest) } }
    val jsonExportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri -> uri?.let { viewModel.exportRules(it, exportRequest) } }

    fun export(request: RuleExportRequest) {
        exportRequest = request
        val date = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
        val fileName = "谛听-${request.fileNameSuffix}-$date.${if (request.scope == RuleScope.DNS) "txt" else "json"}"
        if (request.scope == RuleScope.DNS) textExportLauncher.launch(fileName) else jsonExportLauncher.launch(fileName)
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
                text = localizedText("仅导出当前生效的规则。DNS 使用可订阅的 TXT，HTTPS 使用可完整恢复的备份 JSON。"),
                modifier = Modifier.padding(top = 8.dp)
            )
            SettingsGroupTitle(localizedText("DNS 规则"))
            RuleExportGroup(RuleScope.DNS, operation, exportRequest, exportProgress, exportProgressText, ::export)
            SettingsGroupTitle(localizedText("HTTPS 规则"))
            RuleExportGroup(RuleScope.HTTPS, operation, exportRequest, exportProgress, exportProgressText, ::export)
        }
    }
}

@Composable
private fun RuleExportGroup(
    scope: RuleScope,
    operation: ConfigTransferOperation,
    selectedRequest: RuleExportRequest,
    exportProgress: Float,
    exportProgressText: String,
    onExport: (RuleExportRequest) -> Unit
) {
    val isDns = scope == RuleScope.DNS
    val items = listOf(
        RuleExportType.SUBSCRIPTIONS to "导出所有订阅导入的当前生效规则",
        RuleExportType.MANUAL to "导出所有手动添加的当前生效规则",
        RuleExportType.ALL to "合并订阅导入与手动添加的当前生效规则"
    )
    SettingsSurfaceGroup(
        content = items.map { (type, subtitle) ->
            {
                RuleExportItem(
                    title = localizedText("导出${if (isDns) " DNS" else " HTTPS"}${type.displayName}"),
                    subtitle = localizedText(if (isDns) subtitle else "$subtitle，保存为可恢复的 JSON 备份"),
                    request = RuleExportRequest(type, scope),
                    operation = operation,
                    isSelected = selectedRequest == RuleExportRequest(type, scope),
                    exportProgress = exportProgress,
                    exportProgressText = exportProgressText,
                    onExport = onExport
                )
            }
        }
    )
}

@Composable
private fun RuleExportItem(
    title: String,
    subtitle: String,
    request: RuleExportRequest,
    operation: ConfigTransferOperation,
    isSelected: Boolean,
    exportProgress: Float,
    exportProgressText: String,
    onExport: (RuleExportRequest) -> Unit
) {
    SettingsTextItem(
        title = title,
        subtitle = subtitle,
        subtitleContent = {
            if (operation == ConfigTransferOperation.EXPORTING && isSelected) {
                LinearProgressIndicator(
                    progress = { exportProgress },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp)
                )
                Text(
                    text = localizedText(exportProgressText),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
        },
        enabled = operation == ConfigTransferOperation.IDLE,
        onClick = { onExport(request) }
    )
}
