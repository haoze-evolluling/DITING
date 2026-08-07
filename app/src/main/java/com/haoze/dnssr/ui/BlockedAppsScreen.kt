package com.haoze.dnssr.ui

import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Locale

@Composable
fun BlockedAppsSettingsScreen(onBack: () -> Unit, onSelectApps: () -> Unit) {
    val context = LocalContext.current
    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    var enabled by remember { mutableStateOf(AppSettings.isBlockedAppsEnabled(context) && supported) }
    var selectedCount by remember { mutableIntStateOf(AppSettings.getBlockedAppPackages(context).size) }
    val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                selectedCount = AppSettings.getBlockedAppPackages(context).size
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    SettingsScaffold(title = localizedText("禁止联网应用"), onBack = onBack) { padding ->
        Column(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsInfoText(
                localizedText(if (supported) {
                    "通过本机 VPN 按 UID 阻止所选应用的全部网络连接。共享同一 UID 的应用会一并受影响。"
                } else {
                    "此功能需要 Android 10 或更高版本，当前设备不满足运行条件，因此无法启用。"
                }),
                Modifier.padding(top = 8.dp)
            )
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsSwitchItem(
                        title = localizedText("启用禁止联网"),
                        subtitle = localizedText(if (selectedCount == 0) "尚未选择应用；开启后不会阻断流量" else "已选择 $selectedCount 个应用"),
                        checked = enabled,
                        enabled = supported,
                        onCheckedChange = {
                            enabled = it
                            AppSettings.setBlockedAppsEnabled(context, it)
                            RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                        }
                    )
                },
                {
                    SettingsNavigationItem(
                        title = localizedText("选择禁止联网应用"),
                        subtitle = localizedText("选择需要阻止联网的应用"),
                        value = localizedText("$selectedCount 个"),
                        enabled = supported,
                        onClick = onSelectApps
                    )
                }
            ))
            SettingsInfoText(
                localizedText(if (supported) {
                    "关闭后名单会保留，但不会阻断流量或启用 Go 隧道。"
                } else {
                    "DNS 解析、域名规则和其他基础功能不会受到影响。"
                })
            )
        }
    }
}

@Composable
fun BlockedAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        SettingsScaffold(title = localizedText("选择禁止联网应用"), onBack = onBack) { padding ->
            SettingsInfoText(localizedText("此功能需要 Android 10 或更高版本。"), Modifier.padding(padding).padding(top = 16.dp))
        }
        return
    }
    var selectedPackages by remember { mutableStateOf(AppSettings.getBlockedAppPackages(context)) }
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(AppListFilter.entries.firstOrNull { it.name == AppSettings.getBlockedAppsFilter(context) } ?: AppListFilter.USER) }
    var sort by remember { mutableStateOf(AppListSort.entries.firstOrNull { it.name == AppSettings.getBlockedAppsSort(context) } ?: AppListSort.LABEL_ASC) }
    val access = rememberAppListAccessState { loadInstalledApps(context) }
    AppListDisclosureDialog(access)
    val loadedApps = access.apps
    if (loadedApps == null) {
        SettingsScaffold(title = localizedText("选择禁止联网应用"), onBack = onBack) { AppListLoadingContent(Modifier.padding(it)) }
        return
    }
    if (access.unavailable) {
        SettingsScaffold(title = localizedText("选择禁止联网应用"), onBack = onBack) {
            AppListUnavailableContent(Modifier.padding(it), access.retry)
        }
        return
    }
    val selectableApps = remember(loadedApps, context.packageName) { loadedApps.filter { it.packageName != context.packageName } }
    var debouncedQuery by remember { mutableStateOf("") }
    var visibleApps by remember { mutableStateOf(emptyList<InstalledApp>()) }
    LaunchedEffect(query) { delay(250); debouncedQuery = query }
    LaunchedEffect(selectableApps, filter, sort, debouncedQuery, selectedPackages) {
        val normalized = debouncedQuery.trim().lowercase(Locale.ROOT)
        visibleApps = withContext(Dispatchers.Default) {
            selectableApps.filter { app ->
                (filter == AppListFilter.ALL || filter == AppListFilter.USER && !app.isSystem ||
                    filter == AppListFilter.SYSTEM && app.isSystem ||
                    filter == AppListFilter.SELECTED && app.packageName in selectedPackages) &&
                    (normalized.isEmpty() || app.normalizedLabel.contains(normalized) || app.normalizedPackageName.contains(normalized))
            }.sortedWith(sort.comparator)
        }
    }
    SettingsScaffold(title = localizedText("选择禁止联网应用"), onBack = onBack, actions = {
        val packageNames = selectableApps.mapTo(mutableSetOf()) { it.packageName }
        AppListOverflowMenu(filter, sort,
            onSelectAll = { selectedPackages += packageNames },
            onClear = { selectedPackages = emptySet() },
            onInvert = { selectedPackages = selectedPackages - packageNames + (packageNames - selectedPackages) },
            onFilterChange = { filter = it; AppSettings.setBlockedAppsFilter(context, it.name) },
            onSortChange = { sort = it; AppSettings.setBlockedAppsSort(context, it.name) })
    }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsInfoText(localizedText("服务开启时，所选应用的全部网络连接将被阻止。共享同一 UID 的应用会一并受影响。"), Modifier.padding(top = 8.dp))
            OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), label = { Text(localizedText("搜索应用或包名")) }, singleLine = true)
            LazyColumn(Modifier.fillMaxWidth().weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                itemsIndexed(visibleApps, key = { _, app -> app.packageName }) { index, app ->
                    SettingsSurfaceItem(
                        index = index,
                        itemCount = visibleApps.size,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    ) {
                        InstalledAppCheckboxItem(
                            app = app,
                            checked = app.packageName in selectedPackages,
                            onCheckedChange = { checked ->
                                selectedPackages = if (checked) selectedPackages + app.packageName else selectedPackages - app.packageName
                            }
                        )
                    }
                }
            }
            SettingsActionButton(onClick = {
                AppSettings.setBlockedAppPackages(context, selectedPackages)
                AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - selectedPackages)
                AppSettings.removeHttpInspectionAppPackages(context, selectedPackages)
                AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - selectedPackages)
                RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                Toast.makeText(context, localizedText(context, if (com.haoze.dnssr.vpn.DnsVpnService.isRunning(context)) "已保存，DNS VPN 正在重连" else "已保存，下次启动 DNS VPN 时生效"), Toast.LENGTH_SHORT).show()
                onBack()
            }, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) { Text(localizedText("保存")) }
        }
    }
}
