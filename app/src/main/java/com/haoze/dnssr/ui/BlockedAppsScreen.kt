package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import androidx.compose.ui.unit.dp

@Composable
fun BlockedAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val initialEnabled = remember { AppSettings.isBlockedAppsEnabled(context) }
    var enabled by remember { mutableStateOf(initialEnabled) }
    val initialPackages = remember { AppSettings.getBlockedAppPackages(context) }
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
        AppSettings.setBlockedAppsEnabled(context, enabled)
        AppSettings.setBlockedAppPackages(context, selectedPackages)
        AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - selectedPackages)
        AppSettings.removeHttpInspectionAppPackages(context, selectedPackages)
        AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - selectedPackages)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        val vpnRunning = com.haoze.dnssr.vpn.DnsVpnService.isRunning(context)
        context.showToast(if (vpnRunning) "已保存，DNS VPN 正在重连" else "已保存，下次启动 DNS VPN 时生效")
    }

    AppPickerScreen(
        title = localizedText("禁止联网应用"),
        infoText = localizedText("通过本机 VPN 按 UID 阻止所选应用的全部网络连接。共享同一 UID 的应用会一并受影响。"),
        apps = loadedApps,
        selectedPackages = selectedPackages,
        onSelectedPackagesChange = { selectedPackages = it },
        initialFilter = AppListFilter.entries.firstOrNull {
            it.name == AppSettings.getBlockedAppsFilter(context)
        } ?: AppListFilter.USER,
        initialSort = AppListSort.entries.firstOrNull {
            it.name == AppSettings.getBlockedAppsSort(context)
        } ?: AppListSort.LABEL_ASC,
        onFilterChanged = { AppSettings.setBlockedAppsFilter(context, it.name) },
        onSortChanged = { AppSettings.setBlockedAppsSort(context, it.name) },
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
