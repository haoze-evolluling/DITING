package com.haoze.diting.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.settings.AppRulesSettingsStore

@Composable
fun HttpInspectionAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val initialPackages = remember { AppRulesSettingsStore.getHttpInspectionAppPackages(context) }
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
        AppRulesSettingsStore.setHttpInspectionAppPackages(context, selectedPackages)
        AppRulesSettingsStore.setExcludedAppPackages(context, AppRulesSettingsStore.getExcludedAppPackages(context) - selectedPackages)
        AppRulesSettingsStore.setBlockedAppPackages(context, AppRulesSettingsStore.getBlockedAppPackages(context) - selectedPackages)
        AppRulesSettingsStore.setAppAllowlistPackages(context, AppRulesSettingsStore.getAppAllowlistPackages(context) - selectedPackages)
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
            it.name == AppRulesSettingsStore.getHttpInspectionAppsFilter(context)
        } ?: AppListFilter.USER,
        initialSort = AppListSort.entries.firstOrNull {
            it.name == AppRulesSettingsStore.getHttpInspectionAppsSort(context)
        } ?: AppListSort.LABEL_ASC,
        onFilterChanged = { AppRulesSettingsStore.setHttpInspectionAppsFilter(context, it.name) },
        onSortChanged = { AppRulesSettingsStore.setHttpInspectionAppsSort(context, it.name) },
        showSelectionActions = true,
        isDirty = selectedPackages != initialPackages,
        onSave = { saveHttpInspectionApps() },
        onBack = onBack
    )
}
