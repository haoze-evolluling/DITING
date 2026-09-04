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

@Composable
fun HttpInspectionAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val initialPackages = remember { AppSettings.getHttpInspectionAppPackages(context) }
    var selectedPackages by remember { mutableStateOf(initialPackages) }

    val appListAccess = rememberAppListAccessState { loadInstalledApps(context) }
    AppListDisclosureDialog(appListAccess)

    val loadedApps = appListAccess.apps
    if (loadedApps == null) {
        SettingsScaffold(title = localizedText("选择检查应用"), onBack = onBack) { innerPadding ->
            AppListLoadingContent(Modifier.padding(innerPadding))
        }
        return
    }
    if (appListAccess.unavailable) {
        SettingsScaffold(title = localizedText("选择检查应用"), onBack = onBack) { innerPadding ->
            AppListUnavailableContent(Modifier.padding(innerPadding), appListAccess.retry)
        }
        return
    }

    fun saveHttpInspectionApps() {
        AppSettings.setHttpInspectionAppPackages(context, selectedPackages)
        AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - selectedPackages)
        AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - selectedPackages)
        AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - selectedPackages)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        context.showToast("已保存检查应用")
    }

    AppPickerScreen(
        title = localizedText("选择检查应用"),
        infoText = localizedText("Go 隧道接管流量后，HTTPS 流量检查仅检查所选应用的 HTTP(S) 请求，其他应用直接转发。选择应用会取消其“排除应用”状态。"),
        apps = loadedApps,
        selectedPackages = selectedPackages,
        onSelectedPackagesChange = { selectedPackages = it },
        initialFilter = AppListFilter.entries.firstOrNull {
            it.name == AppSettings.getHttpInspectionAppsFilter(context)
        } ?: AppListFilter.USER,
        initialSort = AppListSort.entries.firstOrNull {
            it.name == AppSettings.getHttpInspectionAppsSort(context)
        } ?: AppListSort.LABEL_ASC,
        onFilterChanged = { AppSettings.setHttpInspectionAppsFilter(context, it.name) },
        onSortChanged = { AppSettings.setHttpInspectionAppsSort(context, it.name) },
        showSelectionActions = true,
        isDirty = selectedPackages != initialPackages,
        onSave = { saveHttpInspectionApps() },
        onBack = onBack
    )
}
