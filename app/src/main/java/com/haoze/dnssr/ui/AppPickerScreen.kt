package com.haoze.dnssr.ui

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
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Locale

/**
 * 安装应用选择页的公共骨架：防抖搜索 + 过滤/排序菜单 + 过滤流水线 + 列表 + 保存 FAB。
 * 单选场景把选中集约定为 0 或 1 个包名，由调用方换算为单个包名。
 */
@Composable
internal fun AppPickerScreen(
    title: String,
    infoText: String,
    apps: List<InstalledApp>,
    selectedPackages: Set<String>,
    onSelectedPackagesChange: (Set<String>) -> Unit,
    initialFilter: AppListFilter,
    initialSort: AppListSort,
    onFilterChanged: (AppListFilter) -> Unit,
    onSortChanged: (AppListSort) -> Unit,
    showSelectionActions: Boolean,
    isDirty: Boolean,
    onSave: () -> Unit,
    onBack: () -> Unit,
    singleSelect: Boolean = false,
    headerContent: @Composable () -> Unit = {},
) {
    var filter by remember { mutableStateOf(initialFilter) }
    var sort by remember { mutableStateOf(initialSort) }
    var query by remember { mutableStateOf("") }
    var debouncedQuery by remember { mutableStateOf("") }
    var visibleApps by remember { mutableStateOf(emptyList<InstalledApp>()) }

    LaunchedEffect(query) { delay(250); debouncedQuery = query }

    LaunchedEffect(apps, filter, sort, debouncedQuery, selectedPackages) {
        val normalizedQuery = debouncedQuery.trim().lowercase(Locale.ROOT)
        visibleApps = withContext(Dispatchers.Default) {
            apps.filter { app ->
                (filter == AppListFilter.ALL ||
                    (filter == AppListFilter.USER && !app.isSystem) ||
                    (filter == AppListFilter.SYSTEM && app.isSystem) ||
                    (filter == AppListFilter.SELECTED && app.packageName in selectedPackages)) &&
                    (normalizedQuery.isEmpty() || app.normalizedLabel.contains(normalizedQuery) ||
                        app.normalizedPackageName.contains(normalizedQuery))
            }.sortedWith(sort.comparator)
        }
    }

    val saveAndBack = {
        if (isDirty) {
            onSave()
        }
        onBack()
    }

    BackHandler {
        saveAndBack()
    }

    SettingsScaffold(
        title = title,
        onBack = saveAndBack,
        actions = {
            AppListOverflowMenu(
                filter = filter,
                sort = sort,
                onSelectAll = { onSelectedPackagesChange(selectedPackages + visibleApps.mapTo(mutableSetOf()) { it.packageName }) },
                onClear = { onSelectedPackagesChange(emptySet()) },
                onInvert = {
                    val visiblePackageNames = visibleApps.mapTo(mutableSetOf()) { it.packageName }
                    onSelectedPackagesChange(selectedPackages - visiblePackageNames + (visiblePackageNames - selectedPackages))
                },
                onFilterChange = {
                    filter = it
                    onFilterChanged(it)
                },
                onSortChange = {
                    sort = it
                    onSortChanged(it)
                },
                showSelectionActions = showSelectionActions
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
                    text = infoText,
                    modifier = Modifier.padding(top = 8.dp)
                )
                headerContent()
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
                            if (singleSelect) {
                                InstalledAppRadioItem(
                                    app = app,
                                    selected = app.packageName in selectedPackages,
                                    onSelected = { onSelectedPackagesChange(setOf(app.packageName)) }
                                )
                            } else {
                                InstalledAppCheckboxItem(
                                    app = app,
                                    checked = app.packageName in selectedPackages,
                                    onCheckedChange = { checked ->
                                        onSelectedPackagesChange(
                                            if (checked) selectedPackages + app.packageName
                                            else selectedPackages - app.packageName
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
            }

            FloatingActionButton(
                onClick = {
                    onSave()
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
