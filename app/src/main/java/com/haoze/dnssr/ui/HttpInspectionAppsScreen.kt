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
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Locale

@Composable
fun HttpInspectionAppsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val initialPackages = remember { AppSettings.getHttpInspectionAppPackages(context) }
    var selectedPackages by remember { mutableStateOf(initialPackages) }
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(AppListFilter.entries.firstOrNull { it.name == AppSettings.getHttpInspectionAppsFilter(context) } ?: AppListFilter.USER) }
    var sort by remember { mutableStateOf(AppListSort.entries.firstOrNull { it.name == AppSettings.getHttpInspectionAppsSort(context) } ?: AppListSort.LABEL_ASC) }

    val appListAccess = rememberAppListAccessState { loadInstalledApps(context) }
    AppListDisclosureDialog(appListAccess)
    val loadedApps = appListAccess.apps
    if (loadedApps == null) {
        SettingsScaffold(title = localizedText("选择检查应用"), onBack = onBack) { AppListLoadingContent(Modifier.padding(it)) }
        return
    }
    if (appListAccess.unavailable) {
        SettingsScaffold(title = localizedText("选择检查应用"), onBack = onBack) {
            AppListUnavailableContent(Modifier.padding(it), appListAccess.retry)
        }
        return
    }
    var debouncedQuery by remember { mutableStateOf("") }
    var visibleApps by remember { mutableStateOf(emptyList<InstalledApp>()) }
    LaunchedEffect(query) { delay(250); debouncedQuery = query }
    LaunchedEffect(loadedApps, filter, sort, debouncedQuery, selectedPackages) {
        val normalizedQuery = debouncedQuery.trim().lowercase(Locale.ROOT)
        visibleApps = withContext(Dispatchers.Default) {
            loadedApps.filter { app ->
                (filter == AppListFilter.ALL ||
                    filter == AppListFilter.USER && !app.isSystem ||
                    filter == AppListFilter.SYSTEM && app.isSystem ||
                    filter == AppListFilter.SELECTED && app.packageName in selectedPackages) &&
                    (normalizedQuery.isEmpty() || app.normalizedLabel.contains(normalizedQuery) || app.normalizedPackageName.contains(normalizedQuery))
            }.sortedWith(sort.comparator)
        }
    }

    fun saveHttpInspectionApps(showToast: Boolean) {
        AppSettings.setHttpInspectionAppPackages(context, selectedPackages)
        AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - selectedPackages)
        AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - selectedPackages)
        AppSettings.setAppAllowlistPackages(context, AppSettings.getAppAllowlistPackages(context) - selectedPackages)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        if (showToast) {
            Toast.makeText(context, localizedText(context, "已保存检查应用"), Toast.LENGTH_SHORT).show()
        }
    }

    val handleBackAndSave = {
        if (selectedPackages != initialPackages) {
            saveHttpInspectionApps(showToast = true)
        }
        onBack()
    }

    BackHandler {
        handleBackAndSave()
    }

    SettingsScaffold(
        title = localizedText("选择检查应用"),
        onBack = handleBackAndSave,
        actions = {
            AppListOverflowMenu(
                filter = filter,
                sort = sort,
                onSelectAll = { selectedPackages = selectedPackages + visibleApps.mapTo(mutableSetOf()) { it.packageName } },
                onClear = { selectedPackages = emptySet() },
                onInvert = {
                    val visiblePackageNames = visibleApps.mapTo(mutableSetOf()) { it.packageName }
                    selectedPackages = selectedPackages - visiblePackageNames + (visiblePackageNames - selectedPackages)
                },
                onFilterChange = { filter = it; AppSettings.setHttpInspectionAppsFilter(context, it.name) },
                onSortChange = { sort = it; AppSettings.setHttpInspectionAppsSort(context, it.name) }
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
                    localizedText("Go 隧道接管流量后，HTTPS 流量检查仅检查所选应用的 HTTP(S) 请求，其他应用直接转发。选择应用会取消其“排除应用”状态。"),
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
            }

            FloatingActionButton(
                onClick = {
                    saveHttpInspectionApps(showToast = true)
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
