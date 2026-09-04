package com.haoze.dnssr.ui

import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import com.haoze.dnssr.ui.dashboard.MetricCard
import com.haoze.dnssr.ui.dashboard.formatCount
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsTextItem
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun ConfigTransferScreen(
    onBack: () -> Unit,
    title: String = "备份与迁移",
    configViewModel: ConfigTransferViewModel = viewModel()
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
    var outboundProxy by remember { mutableStateOf(true) }
    var subscriptions by remember { mutableStateOf(true) }
    var customDomainRules by remember { mutableStateOf(true) }
    var customRewriteDomainRules by remember { mutableStateOf(true) }
    var customRewriteCnameRules by remember { mutableStateOf(true) }
    var customAddressRules by remember { mutableStateOf(true) }
    var excludedApps by remember { mutableStateOf(true) }
    var blockedApps by remember { mutableStateOf(true) }
    var appAllowlist by remember { mutableStateOf(true) }
    var httpInspection by remember { mutableStateOf(true) }
    var appearance by remember { mutableStateOf(true) }
    var systemSettings by remember { mutableStateOf(true) }

    val allSelected = providers && bootstrapIps && dnsCache && outboundProxy && subscriptions &&
        customDomainRules && customRewriteDomainRules && customRewriteCnameRules && customAddressRules &&
        excludedApps && blockedApps && appAllowlist && httpInspection && appearance && systemSettings
    val noneSelected = !providers && !bootstrapIps && !dnsCache && !outboundProxy && !subscriptions &&
        !customDomainRules && !customRewriteDomainRules && !customRewriteCnameRules && !customAddressRules &&
        !excludedApps && !blockedApps && !appAllowlist && !httpInspection && !appearance && !systemSettings
    val selection = ConfigExportSelection(
        providers = providers,
        bootstrapIps = bootstrapIps,
        dnsCache = dnsCache,
        outboundProxy = outboundProxy,
        subscriptions = subscriptions,
        customDomainRules = customDomainRules,
        customRewriteDomainRules = customRewriteDomainRules,
        customRewriteCnameRules = customRewriteCnameRules,
        customAddressRules = customAddressRules,
        excludedApps = excludedApps,
        blockedApps = blockedApps,
        appAllowlist = appAllowlist,
        httpInspection = httpInspection,
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
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            BackupMigrationDashboard(stats = stats)

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
                        outboundProxy = target
                        subscriptions = target
                        customDomainRules = target
                        customRewriteDomainRules = target
                        customRewriteCnameRules = target
                        customAddressRules = target
                        excludedApps = target
                        blockedApps = target
                        appAllowlist = target
                        httpInspection = target
                        appearance = target
                        systemSettings = target
                    },
                    enabled = !isBusy
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
                    { SettingsCheckboxItem(localizedText("DNS 缓存策略"), dnsCache, { dnsCache = it }, subtitle = localizedText("DNS 缓存开关、预设与 TTL 控制"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("出站代理配置"), outboundProxy, { outboundProxy = it }, subtitle = localizedText("SOCKS5 / HTTP 代理与代理应用"), enabled = !isBusy) }
                )
            )

            SettingsGroupTitle(localizedText("规则与订阅配置"))
            SettingsSurfaceGroup(
                content = listOf(
                    { SettingsCheckboxItem(localizedText("网络规则订阅"), subscriptions, { subscriptions = it }, subtitle = localizedText("订阅源链接、镜像加速与自动更新"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("自定义屏蔽域名规则"), customDomainRules, { customDomainRules = it }, subtitle = localizedText("手动添加的域名屏蔽规则及状态"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("自定义复写域名规则"), customRewriteDomainRules, { customRewriteDomainRules = it }, subtitle = localizedText("手动添加的 IPv4 / IPv6 域名覆写规则"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("自定义复写 CNAME 规则"), customRewriteCnameRules, { customRewriteCnameRules = it }, subtitle = localizedText("手动添加的 CNAME 域名覆写规则"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("自定义屏蔽地址规则"), customAddressRules, { customAddressRules = it }, subtitle = localizedText("手动添加的 URL 路径屏蔽规则"), enabled = !isBusy) }
                )
            )

            SettingsGroupTitle(localizedText("应用控制与流量管理"))
            SettingsSurfaceGroup(
                content = listOf(
                    { SettingsCheckboxItem(localizedText("排除应用名单"), excludedApps, { excludedApps = it }, subtitle = localizedText("绕过过滤使用系统 DNS 的应用"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("禁止联网名单"), blockedApps, { blockedApps = it }, subtitle = localizedText("服务运行时禁止联网的应用"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("应用独立规则与放行"), appAllowlist, { appAllowlist = it }, subtitle = localizedText("单应用放行规则与域名白名单"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("HTTPS 抓包检测配置"), httpInspection, { httpInspection = it }, subtitle = localizedText("流量抓包开关与目标应用名单"), enabled = !isBusy) }
                )
            )

            SettingsGroupTitle(localizedText("个性化与通用设置"))
            SettingsSurfaceGroup(
                content = listOf(
                    { SettingsCheckboxItem(localizedText("外观与界面个性化"), appearance, { appearance = it }, subtitle = localizedText("主题风格、组件透明度与标语"), enabled = !isBusy) },
                    { SettingsCheckboxItem(localizedText("系统与通用设置"), systemSettings, { systemSettings = it }, subtitle = localizedText("局域网绕行、日志模式、语言与通知"), enabled = !isBusy) }
                )
            )

            SettingsSurfaceGroup(
                content = listOf(
                    {
                        SettingsTextItem(
                            title = localizedText("导出应用配置 (JSON)"),
                            subtitle = localizedText("将勾选的自定义配置打包保存为 JSON 文件"),
                            leadingIcon = Icons.Filled.Settings,
                            enabled = !isBusy && !noneSelected,
                            onClick = {
                                val date = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
                                configExportLauncher.launch("DNSSR-config-$date.json")
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
        ConfigImportDialog(
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
private fun BackupMigrationDashboard(
    stats: ConfigDashboardStats
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            MetricCard(
                label = localizedText("DNS 服务商"),
                value = formatCount(stats.customProvidersCount),
                valueColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f)
            )
            MetricCard(
                label = localizedText("规则订阅"),
                value = formatCount(stats.subscriptionsCount),
                valueColor = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.weight(1f)
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            MetricCard(
                label = localizedText("自定义规则"),
                value = formatCount(stats.customRulesCount),
                valueColor = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.weight(1f)
            )
            MetricCard(
                label = localizedText("名单应用"),
                value = formatCount(stats.managedAppsCount),
                valueColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun ConfigImportDialog(
    isFinished: Boolean,
    progress: ConfigImportProgress,
    logs: List<String>,
    result: ConfigImportResult?,
    error: String?,
    onDismiss: () -> Unit,
    onCancel: () -> Unit = {}
) {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val coroutineScope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    LaunchedEffect(logs.size, isFinished, result) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    Dialog(
        onDismissRequest = { if (isFinished) onDismiss() else onCancel() },
        properties = DialogProperties(
            dismissOnBackPress = true,
            dismissOnClickOutside = isFinished,
            usePlatformDefaultWidth = false
        )
    ) {
        Card(
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .padding(vertical = 24.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp)
            ) {
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
                    androidx.compose.material3.Surface(
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
                            style = MaterialTheme.typography.labelSmall,
                            color = when {
                                error != null -> MaterialTheme.colorScheme.onErrorContainer
                                isFinished -> MaterialTheme.colorScheme.onPrimaryContainer
                                else -> MaterialTheme.colorScheme.onSecondaryContainer
                            },
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                if (progress.total > 0) {
                    val progressFraction = if (isFinished) 1f else (progress.processed.toFloat() / progress.total.coerceAtLeast(1))
                    LinearProgressIndicator(
                        progress = { progressFraction },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(4.dp)),
                        color = if (error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.surfaceVariant
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            text = "${if (isFinished) progress.total else progress.processed} / ${progress.total}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = "${(progressFraction * 100).toInt()}%",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 160.dp, max = 340.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
                        .padding(14.dp)
                        .verticalScroll(scrollState)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (!isFinished) {
                            logs.forEach { logLine ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.Top
                                ) {
                                    Text(
                                        text = "• ",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                    Text(
                                        text = localizedText(logLine),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                }
                            }
                        } else {
                            if (error != null) {
                                Text(
                                    text = localizedText("导入失败：$error"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.error
                                )
                            } else if (result != null) {
                                Text(
                                    text = localizedText("导入汇总：新增 ${result.added} 项，跳过 ${result.skipped} 项${if (result.failed > 0) "，失败 ${result.failed} 项" else ""}"),
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.primary
                                )

                                if (result.addedDetails.isNotEmpty()) {
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        text = localizedText("【新增项目 (${result.addedDetails.size})】"),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                    result.addedDetails.forEach { detail ->
                                        Text(
                                            text = "  + " + localizedText(detail),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                    }
                                }

                                if (result.skippedDetails.isNotEmpty()) {
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        text = localizedText("【跳过项目 (${result.skippedDetails.size})】"),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.outline
                                    )
                                    result.skippedDetails.forEach { detail ->
                                        Text(
                                            text = "  - " + localizedText(detail),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }

                                if (result.updatedSettingsDetails.isNotEmpty()) {
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        text = localizedText("【更新全局设置 (${result.updatedSettingsDetails.size})】"),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.secondary
                                    )
                                    result.updatedSettingsDetails.forEach { detail ->
                                        Text(
                                            text = "  * " + localizedText(detail),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                    }
                                }

                                if (result.subscriptionsAdded > 0) {
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        text = localizedText("包含 ${result.subscriptionsAdded} 个订阅，请进入订阅管理执行规则更新。"),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.tertiary
                                    )
                                }
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (isFinished) {
                        TextButton(
                            onClick = {
                                val reportText = buildString {
                                    appendLine(localizedText(context, "=== 谛听应用配置导入明细 ==="))
                                    if (result != null) {
                                        appendLine(localizedText(context, "汇总：新增 ${result.added} 项，跳过 ${result.skipped} 项，失败 ${result.failed} 项"))
                                        if (result.addedDetails.isNotEmpty()) {
                                            appendLine(localizedText(context, "\n【新增项目】:"))
                                            result.addedDetails.forEach { appendLine("  + " + localizedText(context, it)) }
                                        }
                                        if (result.skippedDetails.isNotEmpty()) {
                                            appendLine(localizedText(context, "\n【跳过项目】:"))
                                            result.skippedDetails.forEach { appendLine("  - " + localizedText(context, it)) }
                                        }
                                        if (result.updatedSettingsDetails.isNotEmpty()) {
                                            appendLine(localizedText(context, "\n【更新全局设置】:"))
                                            result.updatedSettingsDetails.forEach { appendLine("  * " + localizedText(context, it)) }
                                        }
                                    }
                                    appendLine(localizedText(context, "\n=== 执行日志 ==="))
                                    logs.forEach { appendLine(localizedText(context, it)) }
                                }
                                coroutineScope.launch {
                                    context.copyToClipboard("report", reportText)
                                }
                                context.showToast("已复制明细日志", Toast.LENGTH_SHORT)
                            }
                        ) {
                            Text(localizedText("复制明细"))
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Button(onClick = onDismiss) {
                            Text(localizedText("完成"))
                        }
                    } else {
                        Text(
                            text = localizedText("正在处理，请稍候..."),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        TextButton(onClick = onCancel) {
                            Text(localizedText("取消"))
                        }
                    }
                }
            }
        }
    }
}

