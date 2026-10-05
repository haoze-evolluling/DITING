package com.haoze.diting.express.ui

import android.app.Application
import android.widget.Toast
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.showToast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.diting.ui.ConfigDashboardStats
import com.haoze.diting.ui.ConfigExportSelection
import com.haoze.diting.ui.ConfigImportProgress
import com.haoze.diting.ui.ConfigImportResult
import com.haoze.diting.ui.ConfigTransferOperation
import com.haoze.diting.ui.ConfigTransferViewModel
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.SettingsCardMargin
import com.haoze.diting.ui.components.SettingsCheckboxItem
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSectionSpacing
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsTextItem
import com.haoze.diting.ui.localizedText
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Dedicated Configuration Backup & Migration Screen for Express Mode.
 *
 * Physically omits full-tunnel features from the export checklist and dashboard:
 * - Outbound Proxy (出站代理)
 * - Rewrite rules (域名与 CNAME 覆写)
 * - URL path address rules (URL 规则)
 * - App network controls (排除应用、禁止联网、应用放行、HTTPS 抓包)
 * - Managed apps count card
 */
@Composable
fun ExpressConfigTransferScreen(
    onBack: () -> Unit,
    title: String = "备份与迁移",
    configViewModel: ConfigTransferViewModel = viewModel(
        key = "ExpressConfigTransferViewModel",
        factory = ConfigTransferViewModel.factory(
            LocalContext.current.applicationContext as Application,
            RuleDataset.EXPRESS
        )
    )
) {
    val context = LocalContext.current

    val configOperation by configViewModel.operation.collectAsState()
    val isBusy = configOperation != ConfigTransferOperation.IDLE
    val stats by configViewModel.stats.collectAsState()
    val configMessage by configViewModel.message.collectAsState()
    val showImportDialog by configViewModel.showImportDialog.collectAsState()
    val isImportFinished by configViewModel.isImportFinished.collectAsState()
    val importResult by configViewModel.importResult.collectAsState()
    val importError by configViewModel.importError.collectAsState()
    val importLogs by configViewModel.importLogs.collectAsState()
    val importProgress by configViewModel.importProgress.collectAsState()

    var providers by remember { mutableStateOf(true) }
    var bootstrapIps by remember { mutableStateOf(true) }
    var dnsCache by remember { mutableStateOf(true) }
    var subscriptions by remember { mutableStateOf(true) }
    var customDomainRules by remember { mutableStateOf(true) }
    var appearance by remember { mutableStateOf(true) }
    var systemSettings by remember { mutableStateOf(true) }

    val allSelected = providers && bootstrapIps && dnsCache && subscriptions &&
        customDomainRules && appearance && systemSettings
    val noneSelected = !providers && !bootstrapIps && !dnsCache && !subscriptions &&
        !customDomainRules && !appearance && !systemSettings

    val selection = ConfigExportSelection(
        providers = providers,
        bootstrapIps = bootstrapIps,
        dnsCache = dnsCache,
        outboundProxy = false,
        subscriptions = subscriptions,
        customDomainRules = customDomainRules,
        customRewriteDomainRules = false,
        customRewriteCnameRules = false,
        customAddressRules = false,
        excludedApps = false,
        blockedApps = false,
        appAllowlist = false,
        httpInspection = false,
        appearance = appearance,
        systemSettings = systemSettings
    )

    val configExportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri -> uri?.let { configViewModel.export(it, selection) } }

    val configImportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri -> uri?.let(configViewModel::import) }

    LaunchedEffect(Unit) {
        configViewModel.loadStats()
    }

    LaunchedEffect(configMessage) {
        configMessage?.let {
            context.showToast(it, Toast.LENGTH_LONG)
            configViewModel.clearMessage()
        }
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(SettingsSectionSpacing)
        ) {
            ExpressBackupMigrationDashboard(stats = stats)

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 24.dp, top = 12.dp, bottom = 4.dp, end = 24.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = localizedText("应用配置备份"),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                TextButton(
                    onClick = {
                        val target = !allSelected
                        providers = target
                        bootstrapIps = target
                        dnsCache = target
                        subscriptions = target
                        customDomainRules = target
                        appearance = target
                        systemSettings = target
                    },
                    enabled = !isBusy,
                    shape = SettingsCornerShape
                ) {
                    Text(
                        text = localizedText(if (allSelected) "全不选" else "全选"),
                        style = MaterialTheme.typography.labelMedium
                    )
                }
            }

            SettingsGroupTitle(localizedText("DNS 服务与解析策略"))
            SettingsSurfaceGroup(
                content = listOf(
                    { SettingsCheckboxItem(localizedText("自定义 DNS 服务商"), providers, { providers = it }, subtitle = localizedText("DoH、DoT 服务商与解析配置"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("自定义 Bootstrap IP"), bootstrapIps, { bootstrapIps = it }, subtitle = localizedText("引导 DNS 节点与启用状态"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("DNS 缓存策略"), dnsCache, { dnsCache = it }, subtitle = localizedText("DNS 缓存开关、预设与 TTL 控制"), enabled = !isBusy) }
                )
            )

            SettingsGroupTitle(localizedText("规则与订阅配置"))
            SettingsSurfaceGroup(
                content = listOf(
                    { SettingsCheckboxItem(localizedText("网络规则订阅"), subscriptions, { subscriptions = it }, subtitle = localizedText("订阅源链接、镜像加速与自动更新"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("自定义屏蔽域名规则"), customDomainRules, { customDomainRules = it }, subtitle = localizedText("手动添加的域名屏蔽规则及状态"), enabled = !isBusy) }
                )
            )

            SettingsGroupTitle(localizedText("个性化与通用设置"))
            SettingsSurfaceGroup(
                content = listOf(
                    { SettingsCheckboxItem(localizedText("外观与界面个性化"), appearance, { appearance = it }, subtitle = localizedText("主题风格、组件透明度与标语"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("系统与通用设置"), systemSettings, { systemSettings = it }, subtitle = localizedText("日志模式、语言与通知偏好"), enabled = !isBusy) }
                )
            )

            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsTextItem(
                            title = localizedText("导出应用配置 (JSON)"),
                            subtitle = localizedText("将勾选的极速模式自定义配置打包保存为 JSON 文件"),
                            leadingIcon = Icons.Filled.Settings,
                            enabled = !isBusy && !noneSelected,
                            onClick = {
                                val date = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
                                configExportLauncher.launch("DITING-express-config-$date.json")
                            }
                        )
                    },
                    {
                        SettingsTextItem(
                            title = localizedText("导入应用配置 (JSON)"),
                            subtitle = localizedText("从备份文件合并配置，自动跳过本机已存在项目"),
                            leadingIcon = Icons.Filled.FolderOpen,
                            enabled = !isBusy,
                            onClick = { configImportLauncher.launch(arrayOf("application/json", "text/plain")) }
                        )
                    }
                )
            )

            SettingsInfoText(
                text = localizedText("导出的配置文件包含个人自定义设置，请妥善保管；导入时将合并配置并自动跳过已存在的条目。"),
                modifier = Modifier.padding(top = 4.dp, bottom = 24.dp)
            )
        }
    }

    if (showImportDialog) {
        ExpressConfigImportDialog(
            isFinished = isImportFinished,
            progress = importProgress,
            logs = importLogs,
            result = importResult,
            error = importError,
            onDismiss = configViewModel::dismissImportDialog,
            onCancel = configViewModel::cancelImport
        )
    }
}

@Composable
private fun ExpressBackupMigrationDashboard(stats: ConfigDashboardStats) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = SettingsCardMargin, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ExpressMetricCard(
                label = localizedText("DNS 服务商"),
                value = stats.customProvidersCount.toString(),
                valueColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f)
            )
            ExpressMetricCard(
                label = localizedText("规则订阅"),
                value = stats.subscriptionsCount.toString(),
                valueColor = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.weight(1f)
            )
            ExpressMetricCard(
                label = localizedText("自定义规则"),
                value = stats.customRulesCount.toString(),
                valueColor = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun ExpressMetricCard(
    label: String,
    value: String,
    valueColor: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = valueColor
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ExpressConfigImportDialog(
    isFinished: Boolean,
    progress: ConfigImportProgress,
    logs: List<String>,
    result: ConfigImportResult?,
    error: String?,
    onDismiss: () -> Unit,
    onCancel: () -> Unit = {}
) {
    AppAlertDialog(
        onDismissRequest = { if (isFinished) onDismiss() else onCancel() },
        properties = DialogProperties(
            dismissOnBackPress = true,
            dismissOnClickOutside = isFinished
        ),
        title = {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = localizedText("导入应用配置"),
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Surface(
                    shape = CircleShape,
                    color = when {
                        error != null -> MaterialTheme.colorScheme.errorContainer
                        isFinished -> MaterialTheme.colorScheme.primaryContainer
                        else -> MaterialTheme.colorScheme.secondaryContainer
                    }
                ) {
                    Text(
                        text = localizedText(
                            when {
                                error != null -> "导入失败"
                                isFinished -> "导入完成"
                                else -> "正在导入"
                            }
                        ),
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = when {
                            error != null -> MaterialTheme.colorScheme.onErrorContainer
                            isFinished -> MaterialTheme.colorScheme.onPrimaryContainer
                            else -> MaterialTheme.colorScheme.onSecondaryContainer
                        }
                    )
                }
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val messageText = when {
                    error != null -> localizedText("导入失败：$error")
                    isFinished -> result?.let {
                        localizedText("导入汇总：新增 ${it.added} 项，跳过 ${it.skipped} 项${if (it.failed > 0) "，失败 ${it.failed} 项" else ""}")
                    } ?: localizedText("导入完成")
                    else -> localizedText(progress.currentItem.ifBlank { "正在导入..." })
                }
                Text(
                    text = messageText,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        },
        confirmButton = {
            if (isFinished) {
                TextButton(onClick = onDismiss, shape = SettingsCornerShape) {
                    Text(localizedText("完成"))
                }
            } else {
                TextButton(onClick = onCancel, shape = SettingsCornerShape) {
                    Text(localizedText("取消"))
                }
            }
        }
    )
}
