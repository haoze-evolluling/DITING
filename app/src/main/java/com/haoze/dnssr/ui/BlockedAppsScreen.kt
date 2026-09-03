package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Locale

@Composable
fun BlockedAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val initialEnabled = remember { AppSettings.isBlockedAppsEnabled(context) }
    var enabled by remember { mutableStateOf(initialEnabled) }
    val initialPackages = remember { AppSettings.getBlockedAppPackages(context) }
    var selectedPackages by remember { mutableStateOf(initialPackages) }
    var query by remember { mutableStateOf("") }
    var filter by remember {
        mutableStateOf(
            AppListFilter.entries.firstOrNull {
                it.name == AppSettings.getBlockedAppsFilter(context)
            } ?: AppListFilter.USER
        )
    }
    var sort by remember {
        mutableStateOf(
            AppListSort.entries.firstOrNull {
                it.name == AppSettings.getBlockedAppsSort(context)
            } ?: AppListSort.LABEL_ASC
        )
    }

    val appListAccess = rememberAppListAccessState { loadInstalledApps(context) }
    AppListDisclosureDialog(appListAccess)

    val loadedApps = appListAccess.apps
    if (loadedApps == null) {
        SettingsScaffold(title = localizedText("禁止联网应用"), onBack = onBack) { innerPadding ->
            AppListLoadingContent(Modifier.padding(innerPadding))
        }
        return
    }
    if (appListAccess.unavailable) {
        SettingsScaffold(title = localizedText("禁止联网应用"), onBack = onBack) { innerPadding ->
            AppListUnavailableContent(
                modifier = Modifier.padding(innerPadding),
                onRetry = appListAccess.retry
            )
        }
        return
    }

    val selectableApps = remember(loadedApps, context.packageName) {
        loadedApps.filter { it.packageName != context.packageName }
    }
    var debouncedQuery by remember { mutableStateOf("") }
    var visibleApps by remember { mutableStateOf(emptyList<InstalledApp>()) }

    LaunchedEffect(query) {
        delay(250)
        debouncedQuery = query
    }

    LaunchedEffect(selectableApps, filter, sort, debouncedQuery, selectedPackages) {
        val normalizedQuery = debouncedQuery.trim().lowercase(Locale.ROOT)
        visibleApps = withContext(Dispatchers.Default) {
            selectableApps.filter { app ->
                (filter == AppListFilter.ALL ||
                    (filter == AppListFilter.USER && !app.isSystem) ||
                    (filter == AppListFilter.SYSTEM && app.isSystem) ||
                    (filter == AppListFilter.SELECTED && app.packageName in selectedPackages)) &&
                    (normalizedQuery.isEmpty() || app.normalizedLabel.contains(normalizedQuery) ||
                        app.normalizedPackageName.contains(normalizedQuery))
            }.sortedWith(sort.comparator)
        }
    }

    fun saveBlockedApps(showToast: Boolean) {
        AppSettings.setBlockedAppsEnabled(context, enabled)
        AppSettings.setBlockedAppPackages(context, selectedPackages)
        AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - selectedPackages)
        AppSettings.removeHttpInspectionAppPackages(context, selectedPackages)
        AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - selectedPackages)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        if (showToast) {
            val vpnRunning = com.haoze.dnssr.vpn.DnsVpnService.isRunning(context)
            Toast.makeText(
                context,
                localizedText(context, if (vpnRunning) "已保存，DNS VPN 正在重连" else "已保存，下次启动 DNS VPN 时生效"),
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    val handleBackAndSave = {
        if (selectedPackages != initialPackages || enabled != initialEnabled) {
            saveBlockedApps(showToast = true)
        }
        onBack()
    }

    BackHandler {
        handleBackAndSave()
    }

    SettingsScaffold(
        title = localizedText("禁止联网应用"),
        onBack = handleBackAndSave,
        actions = {
            val selectablePackageNames = selectableApps.mapTo(mutableSetOf()) { it.packageName }
            AppListOverflowMenu(
                filter = filter,
                sort = sort,
                onSelectAll = { selectedPackages = selectedPackages + selectablePackageNames },
                onClear = { selectedPackages = emptySet() },
                onInvert = { selectedPackages = selectedPackages - selectablePackageNames + (selectablePackageNames - selectedPackages) },
                onFilterChange = {
                    filter = it
                    AppSettings.setBlockedAppsFilter(context, it.name)
                },
                onSortChange = {
                    sort = it
                    AppSettings.setBlockedAppsSort(context, it.name)
                }
            )
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                SettingsInfoText(
                    text = localizedText("通过本机 VPN 按 UID 阻止所选应用的全部网络连接。共享同一 UID 的应用会一并受影响。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("启用禁止联网"),
                            subtitle = localizedText(
                                if (selectedPackages.isEmpty()) "尚未选择应用；开启后不会阻断流量"
                                else "已选择 ${selectedPackages.size} 个应用"
                            ),
                            checked = enabled,
                            onCheckedChange = { enabled = it }
                        )
                    }
                )
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text(localizedText("搜索应用或包名")) },
                    singleLine = true,
                    shape = RoundedCornerShape(28.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                )
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentPadding = PaddingValues(bottom = 80.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
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
                                    selectedPackages = if (checked) {
                                        selectedPackages + app.packageName
                                    } else {
                                        selectedPackages - app.packageName
                                    }
                                }
                            )
                        }
                    }
                }
            }

            FloatingActionButton(
                onClick = {
                    saveBlockedApps(showToast = true)
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
