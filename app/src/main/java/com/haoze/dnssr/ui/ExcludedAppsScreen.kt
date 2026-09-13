package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.haoze.dnssr.ui.components.SettingsScaffold
import androidx.compose.ui.unit.dp

@Composable
fun ExcludedAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val initialPackages = remember { AppSettings.getExcludedAppPackages(context) }
    var selectedPackages by remember { mutableStateOf(initialPackages) }

    val appListAccess = rememberAppListAccessState { loadInstalledApps(context) }
    AppListDisclosureDialog(appListAccess)

    val loadedApps = appListAccess.apps
    if (loadedApps == null) {
        SettingsScaffold(title = localizedText("排除应用"), onBack = onBack) { innerPadding ->
            AppListLoadingContent(Modifier.padding(innerPadding))
        }
        return
    }
    if (appListAccess.unavailable) {
        SettingsScaffold(title = localizedText("排除应用"), onBack = onBack) { innerPadding ->
            AppListUnavailableContent(
                modifier = Modifier.padding(innerPadding),
                onRetry = appListAccess.retry
            )
        }
        return
    }

    fun saveExcludedApps() {
        AppSettings.setExcludedAppPackages(context, selectedPackages)
        AppSettings.removeHttpInspectionAppPackages(context, selectedPackages)
        AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - selectedPackages)
        AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - selectedPackages)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        val vpnRunning = com.haoze.dnssr.vpn.DnsVpnService.isRunning(context)
        context.showToast(if (vpnRunning) "已保存，DNS VPN 正在重连" else "已保存，下次启动 DNS VPN 时生效")
    }

    AppPickerScreen(
        title = localizedText("排除应用"),
        infoText = localizedText("排除后，应用将使用系统 DNS，不参与本应用的过滤、缓存、日志和统计。"),
        apps = loadedApps,
        selectedPackages = selectedPackages,
        onSelectedPackagesChange = { selectedPackages = it },
        initialFilter = AppListFilter.entries.firstOrNull {
            it.name == AppSettings.getExcludedAppsFilter(context)
        } ?: AppListFilter.USER,
        initialSort = AppListSort.entries.firstOrNull {
            it.name == AppSettings.getExcludedAppsSort(context)
        } ?: AppListSort.LABEL_ASC,
        onFilterChanged = { AppSettings.setExcludedAppsFilter(context, it.name) },
        onSortChanged = { AppSettings.setExcludedAppsSort(context, it.name) },
        showSelectionActions = true,
        isDirty = selectedPackages != initialPackages,
        onSave = { saveExcludedApps() },
        onBack = onBack
    )
}
