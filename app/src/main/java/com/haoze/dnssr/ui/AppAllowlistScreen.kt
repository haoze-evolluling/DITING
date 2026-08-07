package com.haoze.dnssr.ui

import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.vpn.AdGuardRuleParser
import com.haoze.dnssr.ui.components.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Locale

@Composable
fun AppAllowlistSettingsScreen(onBack: () -> Unit, onSelectApps: () -> Unit) {
    val context = LocalContext.current
    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    var enabled by remember { mutableStateOf(AppSettings.isAppAllowlistEnabled(context) && supported) }
    var domains by remember { mutableStateOf(AppSettings.getAppAllowlistDomains(context)) }
    var newDomain by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    val packages = AppSettings.getAppAllowlistPackages(context)
    SettingsScaffold(title = localizedText("应用白名单访问"), onBack = onBack) { padding ->
        Column(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsInfoText(localizedText(if (supported) "所选应用只能连接其白名单域名解析出的 IP。直连 IP、局域网、加密 DNS 和其他连接会被阻止；共享 CDN IP 在 DNS TTL 内可能承载其他站点。" else "此功能需要 Android 10 或更高版本。"), Modifier.padding(top = 8.dp))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsSwitchItem(title = localizedText("启用应用白名单访问"), subtitle = localizedText(if (domains.isEmpty()) "请先添加至少一个白名单域名" else "已选择 ${packages.size} 个应用，${domains.size} 个域名"), checked = enabled, enabled = supported && domains.isNotEmpty(), onCheckedChange = {
                        enabled = it; AppSettings.setAppAllowlistEnabled(context, it); RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                    })
                },
                {
                    SettingsNavigationItem(
                        title = localizedText("选择受限应用"),
                        subtitle = localizedText("这些应用仅可访问白名单域名"),
                        value = localizedText("${packages.size} 个"),
                        enabled = supported,
                        onClick = onSelectApps
                    )
                }
            ))
            SettingsGroupTitle(localizedText("白名单域名"))
            OutlinedTextField(newDomain, { newDomain = it; error = null }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), label = { Text(localizedText("域名，如 example.com")) }, singleLine = true, isError = error != null)
            error?.let { SettingsInfoText(localizedText(it), Modifier.padding(horizontal = 16.dp)) }
            SettingsActionButton(onClick = {
                val domain = AdGuardRuleParser.parseAllowLine(newDomain)?.pattern
                if (domain == null) error = "请输入有效域名" else {
                    domains += domain
                    AppSettings.setAppAllowlistDomains(context, domains)
                    RuntimeDnsSettingsRefresher.refreshAppAllowlistIfRunning(context)
                    newDomain = ""
                }
            }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), enabled = supported) { Text(localizedText("添加域名")) }
            LazyColumn(Modifier.fillMaxWidth().weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(domains.sorted(), key = { it }) { domain ->
                    val removeDomain = {
                        domains -= domain
                        AppSettings.setAppAllowlistDomains(context, domains)
                        if (domains.isEmpty()) {
                            enabled = false
                            AppSettings.setAppAllowlistEnabled(context, false)
                        }
                        RuntimeDnsSettingsRefresher.refreshAppAllowlistIfRunning(context)
                    }
                    SettingsSurfaceGroup(content = listOf {
                        SettingsItem(title = domain, subtitle = localizedText("包含所有子域名"), trailing = {
                            IconButton(onClick = removeDomain) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = localizedText("删除 $domain")
                                )
                            }
                        })
                    })
                }
            }
        }
    }
}

@Composable
fun AppAllowlistAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    var selected by remember { mutableStateOf(AppSettings.getAppAllowlistPackages(context)) }
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(AppListFilter.entries.firstOrNull { it.name == AppSettings.getAppAllowlistFilter(context) } ?: AppListFilter.USER) }
    var sort by remember { mutableStateOf(AppListSort.entries.firstOrNull { it.name == AppSettings.getAppAllowlistSort(context) } ?: AppListSort.LABEL_ASC) }
    val access = rememberAppListAccessState { loadInstalledApps(context) }
    AppListDisclosureDialog(access)
    if (access.unavailable) {
        return SettingsScaffold(title = localizedText("选择受限应用"), onBack = onBack) {
            AppListUnavailableContent(Modifier.padding(it), access.retry)
        }
    }
    val apps = access.apps ?: return SettingsScaffold(localizedText("选择受限应用"), onBack) { AppListLoadingContent(Modifier.padding(it)) }
    var debounced by remember { mutableStateOf("") }
    var visible by remember { mutableStateOf(emptyList<InstalledApp>()) }
    LaunchedEffect(query) { delay(250); debounced = query }
    LaunchedEffect(apps, filter, sort, debounced, selected) {
        val normalized = debounced.trim().lowercase(Locale.ROOT)
        visible = withContext(Dispatchers.Default) { apps.filter { app -> app.packageName != context.packageName &&
            (filter == AppListFilter.ALL || filter == AppListFilter.USER && !app.isSystem || filter == AppListFilter.SYSTEM && app.isSystem || filter == AppListFilter.SELECTED && app.packageName in selected) &&
            (normalized.isEmpty() || app.normalizedLabel.contains(normalized) || app.normalizedPackageName.contains(normalized)) }.sortedWith(sort.comparator) }
    }
    SettingsScaffold(localizedText("选择受限应用"), onBack, actions = {
        AppListOverflowMenu(filter, sort, { selected += apps.filter { it.packageName != context.packageName }.map { it.packageName } }, { selected = emptySet() }, { selected = apps.filter { it.packageName != context.packageName }.map { it.packageName }.toSet() - selected + (selected - apps.map { it.packageName }.toSet()) }, { filter = it; AppSettings.setAppAllowlistFilter(context, it.name) }, { sort = it; AppSettings.setAppAllowlistSort(context, it.name) })
    }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsInfoText(localizedText("保存后会自动从禁止联网应用、HTTPS 流量检查和排除 VPN 应用中移除。"), Modifier.padding(top = 8.dp))
            OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), label = { Text(localizedText("搜索应用或包名")) }, singleLine = true)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                itemsIndexed(visible, key = { _, app -> app.packageName }) { index, app ->
                    SettingsSurfaceItem(
                        index = index,
                        itemCount = visible.size,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    ) {
                        InstalledAppCheckboxItem(
                            app = app,
                            checked = app.packageName in selected,
                            onCheckedChange = { checked -> selected = if (checked) selected + app.packageName else selected - app.packageName }
                        )
                    }
                }
            }
            SettingsActionButton(onClick = {
                AppSettings.setAppAllowlistPackages(context, selected)
                AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - selected)
                AppSettings.removeHttpInspectionAppPackages(context, selected)
                AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - selected)
                RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                Toast.makeText(context, localizedText(context, "已保存"), Toast.LENGTH_SHORT).show(); onBack()
            }, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) { Text(localizedText("保存")) }
        }
    }
}
