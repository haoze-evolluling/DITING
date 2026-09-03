package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.haoze.dnssr.ui.components.SettingsActionButton
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.DnsVpnService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OutboundProxySettingsScreen(
    onBack: () -> Unit,
    onSelectApp: () -> Unit,
    selectedAppOverride: Pair<Boolean, String?>? = null
) {
    val context = LocalContext.current
    var draft by remember { mutableStateOf(AppSettings.getOutboundProxyConfig(context)) }
    var portText by remember { mutableStateOf(draft.port.toString()) }
    var proxyStatus by remember { mutableStateOf(AppSettings.getOutboundProxyStatus(context)) }

    LaunchedEffect(selectedAppOverride) {
        selectedAppOverride?.let { (_, packageName) ->
            draft = draft.copy(proxyAppPackage = packageName.orEmpty())
        }
    }
    LaunchedEffect(draft.enabled) {
        while (draft.enabled) {
            proxyStatus = AppSettings.getOutboundProxyStatus(context)
            delay(1000)
        }
    }

    var selectedLabel by remember { mutableStateOf(draft.proxyAppPackage.ifBlank { "未选择" }) }
    LaunchedEffect(draft.proxyAppPackage) {
        selectedLabel = if (draft.proxyAppPackage.isBlank()) {
            "未选择"
        } else {
            runCatching {
                context.packageManager.getApplicationInfo(draft.proxyAppPackage, 0)
                    .loadLabel(context.packageManager).toString()
            }.getOrDefault(draft.proxyAppPackage)
        }
    }
    fun setProxyEnabled(enabled: Boolean) {
        if (draft.enabled == enabled) return
        draft = draft.copy(enabled = enabled)
        val persistedConfig = AppSettings.getOutboundProxyConfig(context)
        AppSettings.setOutboundProxyConfig(context, persistedConfig.copy(enabled = enabled))
        AppSettings.setOutboundProxyStatus(context, if (enabled) "connecting" else "disabled", "")
        if (enabled && !DnsVpnService.isRunning(context)) {
            ContextCompat.startForegroundService(context, DnsVpnService.startIntent(context))
        } else {
            RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        }
    }
    val statusText = localizedText(when (proxyStatus.first) {
        "connecting" -> "正在连接"
        "ready" -> "代理可用"
        "error" -> proxyStatus.second.ifBlank { "代理不可用" }
        else -> "未运行"
    })

    SettingsScaffold(title = localizedText("出站代理"), onBack = onBack) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsItem(
            title = localizedText("启用出站代理功能"),
                        subtitle = statusText,
                        onClick = { setProxyEnabled(!draft.enabled) }
                    ) {
                        Switch(
                            checked = draft.enabled,
                            onCheckedChange = ::setProxyEnabled
                        )
                    }
                },
                {
                    SettingsItem(
            title = localizedText("代理应用"),
                        subtitle = if (draft.proxyAppPackage.isBlank()) localizedText("未选择") else selectedLabel,
                        onClick = onSelectApp
                    ) { Icon(Icons.Default.Apps, contentDescription = null) }
                }
            ))

            Column(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    OutboundProxyProtocol.entries.forEachIndexed { index, protocol ->
                        SegmentedButton(
                            selected = draft.protocol == protocol,
                            onClick = { draft = draft.copy(protocol = protocol) },
                            shape = SegmentedButtonDefaults.itemShape(index, OutboundProxyProtocol.entries.size),
                            label = { Text(protocol.displayName) }
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = draft.host,
                        onValueChange = { draft = draft.copy(host = it.trim()) },
                        modifier = Modifier.weight(1f),
                        label = { Text(localizedText("地址")) },
                        singleLine = true,
                        shape = SettingsCornerShape
                    )
                    OutlinedTextField(
                        value = portText,
                        onValueChange = { value -> if (value.all(Char::isDigit)) portText = value },
                        modifier = Modifier.weight(0.65f),
                        label = { Text(localizedText("端口")) },
                        singleLine = true,
                        shape = SettingsCornerShape
                    )
                }
                OutlinedTextField(
                    value = draft.username,
                    onValueChange = { draft = draft.copy(username = it) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(localizedText("账号（可选）")) },
                    singleLine = true,
                    shape = SettingsCornerShape
                )
                OutlinedTextField(
                    value = draft.password,
                    onValueChange = { draft = draft.copy(password = it) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(localizedText("密码（可选）")) },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    shape = SettingsCornerShape
                )
            }

            SettingsInfoText(
                if (draft.protocol == OutboundProxyProtocol.HTTP) {
                    localizedText("HTTP CONNECT 不支持 UDP；UDP 会被严格阻断，QUIC 可回退到 TCP。代理应用本身将绕过 DNSSR。")
                } else {
                    localizedText("SOCKS5 通过 UDP ASSOCIATE 转发 UDP。代理应用本身将绕过 DNSSR，防止流量环路。")
                }
            )
            SettingsActionButton(
                onClick = {
                    val savedConfig = draft.copy(port = portText.toIntOrNull() ?: 0)
                    val error = if (savedConfig.enabled) savedConfig.validationError(context) else null
                    if (error != null) {
                        Toast.makeText(context, localizedText(context, error), Toast.LENGTH_LONG).show()
                    } else {
                        draft = savedConfig
                        AppSettings.setOutboundProxyConfig(context, savedConfig)
                        AppSettings.setOutboundProxyStatus(context, if (savedConfig.enabled) "connecting" else "disabled", "")
                        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                        Toast.makeText(context, localizedText(context, "出站代理设置已保存"), Toast.LENGTH_SHORT).show()
                    }
                },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
            ) {
                Icon(Icons.Default.Save, contentDescription = null)
                Text(localizedText("保存"), Modifier.padding(start = 8.dp))
            }
        }
    }

}

@Composable
fun OutboundProxyAppsScreen(onBack: () -> Unit, onSave: (String) -> Unit) {
    val context = LocalContext.current
    val initialPackage = remember { AppSettings.getOutboundProxyConfig(context).proxyAppPackage }
    var selectedPackage by remember { mutableStateOf(initialPackage) }
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(AppListFilter.USER) }
    var sort by remember { mutableStateOf(AppListSort.LABEL_ASC) }
    val access = rememberAppListAccessState { loadInstalledApps(context) }
    AppListDisclosureDialog(access)
    val apps = access.apps
    if (access.unavailable) {
        return SettingsScaffold(title = localizedText("选择代理应用"), onBack = onBack) {
            AppListUnavailableContent(Modifier.padding(it), access.retry)
        }
    }
    if (apps == null) {
        return SettingsScaffold(title = localizedText("选择代理应用"), onBack = onBack) {
            AppListLoadingContent(Modifier.padding(it))
        }
    }

    var debouncedQuery by remember { mutableStateOf("") }
    var visibleApps by remember { mutableStateOf(emptyList<InstalledApp>()) }
    LaunchedEffect(query) { delay(250); debouncedQuery = query }
    LaunchedEffect(apps, filter, sort, debouncedQuery, selectedPackage) {
        val normalized = debouncedQuery.trim().lowercase(Locale.ROOT)
        visibleApps = withContext(Dispatchers.Default) {
            apps.filter { app ->
                (filter == AppListFilter.ALL ||
                    filter == AppListFilter.USER && !app.isSystem ||
                    filter == AppListFilter.SYSTEM && app.isSystem ||
                    filter == AppListFilter.SELECTED && app.packageName == selectedPackage) &&
                    (normalized.isEmpty() || app.normalizedLabel.contains(normalized) || app.normalizedPackageName.contains(normalized))
            }.sortedWith(sort.comparator)
        }
    }

    val handleBackAndSave = {
        if (selectedPackage != initialPackage) {
            onSave(selectedPackage)
        }
        onBack()
    }

    BackHandler {
        handleBackAndSave()
    }

    SettingsScaffold(
        title = localizedText("选择代理应用"),
        onBack = handleBackAndSave,
        actions = {
            AppListOverflowMenu(
                filter = filter,
                sort = sort,
                onSelectAll = {},
                onClear = { selectedPackage = "" },
                onInvert = {},
                onFilterChange = { filter = it },
                onSortChange = { sort = it },
                showSelectionActions = false
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                SettingsInfoText(
                    localizedText("选择提供本地代理端口的应用。代理应用本身会绕过 DNSSR。"),
                    Modifier.padding(top = 8.dp)
                )
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    label = { Text(localizedText("搜索应用或包名")) },
                    singleLine = true,
                    shape = RoundedCornerShape(28.dp)
                )
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentPadding = PaddingValues(bottom = 80.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    itemsIndexed(visibleApps, key = { _, app -> app.packageName }) { index, app ->
                        SettingsSurfaceItem(index = index, itemCount = visibleApps.size, modifier = Modifier.padding(horizontal = 16.dp)) {
                            InstalledAppRadioItem(
                                app = app,
                                selected = app.packageName == selectedPackage,
                                onSelected = { selectedPackage = app.packageName }
                            )
                        }
                    }
                }
            }

            FloatingActionButton(
                onClick = {
                    onSave(selectedPackage)
                    onBack()
                },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp),
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary
            ) {
                Icon(Icons.Filled.Save, contentDescription = localizedText("保存"))
            }
        }
    }
}
