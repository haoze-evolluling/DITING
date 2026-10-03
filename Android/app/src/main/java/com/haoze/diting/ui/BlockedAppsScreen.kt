package com.haoze.diting.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.settings.AppRulesSettingsStore

@Composable
fun BlockedAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val initialEnabled = remember { AppRulesSettingsStore.isBlockedAppsEnabled(context) }
    var enabled by remember { mutableStateOf(initialEnabled) }
    val initialPackages = remember { AppRulesSettingsStore.getBlockedAppPackages(context) }
    var selectedPackages by remember { mutableStateOf(initialPackages) }

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

    fun saveBlockedApps() {
        AppRulesSettingsStore.setBlockedAppsEnabled(context, enabled)
        AppRulesSettingsStore.setBlockedAppPackages(context, selectedPackages)
        AppRulesSettingsStore.setExcludedAppPackages(context, AppRulesSettingsStore.getExcludedAppPackages(context) - selectedPackages)
        AppRulesSettingsStore.removeHttpInspectionAppPackages(context, selectedPackages)
        AppRulesSettingsStore.setAppAllowlistPackages(context, AppRulesSettingsStore.getAppAllowlistPackages(context) - selectedPackages)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        val vpnRunning = com.haoze.diting.vpn.DnsVpnService.isRunning(context)
        context.showToast(if (vpnRunning) "已保存，DNS VPN 正在重连" else "已保存，下次启动 DNS VPN 时生效")
    }

    AppPickerScreen(
        title = localizedText("禁止联网应用"),
        infoText = localizedText("通过本机 VPN 按 UID 阻止所选应用的全部网络连接。共享同一 UID 的应用会一并受影响。"),
        apps = loadedApps,
        selectedPackages = selectedPackages,
        onSelectedPackagesChange = { selectedPackages = it },
        initialFilter = AppListFilter.entries.firstOrNull {
            it.name == AppRulesSettingsStore.getBlockedAppsFilter(context)
        } ?: AppListFilter.USER,
        initialSort = AppListSort.entries.firstOrNull {
            it.name == AppRulesSettingsStore.getBlockedAppsSort(context)
        } ?: AppListSort.LABEL_ASC,
        onFilterChanged = { AppRulesSettingsStore.setBlockedAppsFilter(context, it.name) },
        onSortChanged = { AppRulesSettingsStore.setBlockedAppsSort(context, it.name) },
        showSelectionActions = true,
        isDirty = selectedPackages != initialPackages || enabled != initialEnabled,
        onSave = { saveBlockedApps() },
        onBack = onBack,
        headerContent = {
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
        }
    )
}
