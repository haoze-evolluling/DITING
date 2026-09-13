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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.apprule.ClearAllAllowlistDialog
import com.haoze.dnssr.ui.apprule.SingleAppRulePanel
import com.haoze.dnssr.ui.apprule.UnifiedAppItemRow
import com.haoze.dnssr.ui.components.RuleSearchField
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItemSpacing
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

@Composable
internal fun AppRuleManagementScreen(
    onBack: () -> Unit,
    viewModel: AppRuleViewModel = viewModel()
) {
    val context = LocalContext.current
    val selectedApp by viewModel.selectedApp.collectAsStateWithLifecycle()
    val appRuleCounts by viewModel.appRuleCounts.collectAsStateWithLifecycle()
    val appAllowlistMap by viewModel.appAllowlistMap.collectAsStateWithLifecycle()
    val isAppAllowlistMasterEnabled by viewModel.isAppAllowlistMasterEnabled.collectAsStateWithLifecycle()
    val selectedAppAllowlistDomains by viewModel.selectedAppAllowlistDomains.collectAsStateWithLifecycle()
    val fullBlockEnabled by viewModel.fullBlockEnabled.collectAsStateWithLifecycle()
    val blockRules by viewModel.blockRules.collectAsStateWithLifecycle()
    val allowRules by viewModel.allowRules.collectAsStateWithLifecycle()

    var showClearAllAllowlistDialog by remember { mutableStateOf(false) }

    val access = rememberAppListAccessState { loadInstalledApps(context) }
    AppListDisclosureDialog(access)

    if (selectedApp != null) {
        BackHandler { viewModel.selectApp(null) }
        SingleAppRulePanel(
            app = selectedApp!!,
            allowlistDomains = selectedAppAllowlistDomains,
            fullBlockEnabled = fullBlockEnabled,
            blockRules = blockRules,
            allowRules = allowRules,
            onBack = { viewModel.selectApp(null) },
            onAddAllowlistDomain = { domain ->
                viewModel.addAllowlistDomain(domain) { msg, _ ->
                    context.showToast(msg, Toast.LENGTH_SHORT)
                }
            },
            onRemoveAllowlistDomain = { domain ->
                viewModel.removeAllowlistDomain(domain)
            },
            onClearAllowlistDomains = {
                viewModel.clearAllowlistDomainsForSelectedApp()
                context.showToast("已清空该应用放行域名", Toast.LENGTH_SHORT)
            },
            onToggleFullBlock = { enabled ->
                viewModel.toggleFullBlockTemplate(enabled) { msg ->
                    context.showToast(msg, Toast.LENGTH_SHORT)
                }
            },
            onAddRule = { pattern, isAllow, important, isWildcard ->
                viewModel.addAppRule(pattern, isAllow, important, isWildcard) { msg ->
                    context.showToast(msg, Toast.LENGTH_SHORT)
                }
            },
            onToggleRule = { id, isAllow, enabled -> viewModel.toggleRule(id, isAllow, enabled) },
            onDeleteRule = { id, isAllow -> viewModel.deleteRule(id, isAllow) }
        )
        return
    }

    if (access.unavailable) {
        SettingsScaffold(title = localizedText("应用独立规则"), onBack = onBack) {
            AppListUnavailableContent(Modifier.padding(it), access.retry)
        }
        return
    }

    val loadedApps = access.apps
    if (loadedApps == null) {
        SettingsScaffold(title = localizedText("应用独立规则"), onBack = onBack) {
            AppListLoadingContent(Modifier.padding(it))
        }
        return
    }

    var query by remember { mutableStateOf("") }
    val debouncedQuery = rememberDebouncedValue(query)
    var filter by remember { mutableStateOf(AppListFilter.ALL) }
    var sort by remember { mutableStateOf(AppListSort.LABEL_ASC) }
    var visibleApps by remember { mutableStateOf(emptyList<InstalledApp>()) }

    LaunchedEffect(loadedApps, filter, sort, debouncedQuery, appRuleCounts, appAllowlistMap) {
        val normalized = debouncedQuery.trim().lowercase(Locale.ROOT)
        visibleApps = withContext(Dispatchers.Default) {
            loadedApps.filter { app ->
                val hasDnsRules = (appRuleCounts[app.packageName] ?: 0) > 0
                val hasAllowlist = appAllowlistMap[app.packageName]?.isNotEmpty() == true
                val hasAnyConfig = hasDnsRules || hasAllowlist
                (filter == AppListFilter.ALL ||
                    (filter == AppListFilter.USER && !app.isSystem) ||
                    (filter == AppListFilter.SYSTEM && app.isSystem) ||
                    (filter == AppListFilter.SELECTED && hasAnyConfig)) &&
                    (normalized.isEmpty() ||
                        app.normalizedLabel.contains(normalized) ||
                        app.normalizedPackageName.contains(normalized))
            }.sortedWith(
                compareByDescending<InstalledApp> {
                    val hasDns = (appRuleCounts[it.packageName] ?: 0) > 0
                    val hasAllow = appAllowlistMap[it.packageName]?.isNotEmpty() == true
                    if (hasDns || hasAllow) 1 else 0
                }.then(sort.comparator)
            )
        }
    }

    val configuredAppCount = appAllowlistMap.keys.union(appRuleCounts.filter { it.value > 0 }.keys).size
    val totalAllowlistDomains = appAllowlistMap.values.sumOf { it.size }
    val totalDnsRules = appRuleCounts.values.sum()

    SettingsScaffold(
        title = localizedText("应用独立规则"),
        onBack = onBack,
        actions = {
            if (appAllowlistMap.isNotEmpty()) {
                IconButton(onClick = { showClearAllAllowlistDialog = true }) {
                    Icon(
                        imageVector = Icons.Default.DeleteSweep,
                        contentDescription = localizedText("清空全部放行规则")
                    )
                }
            }
            AppListOverflowMenu(
                filter = filter,
                sort = sort,
                onSelectAll = {},
                onClear = {},
                onInvert = {},
                onFilterChange = { filter = it },
                onSortChange = { sort = it },
                showSelectionActions = false
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Master switch at the top
            SettingsSurfaceGroup(
                content = listOf {
                    SettingsSwitchItem(
                        title = localizedText("启用单应用域名放行"),
                        subtitle = localizedText(
                            if (configuredAppCount == 0) "暂未配置任何应用独立规则"
                            else "已配置 $configuredAppCount 个应用 · 放行 $totalAllowlistDomains 个域名 · DNS 规则 $totalDnsRules 条"
                        ),
                        checked = isAppAllowlistMasterEnabled,
                        onCheckedChange = { viewModel.setMasterAllowlistEnabled(it) }
                    )
                }
            )

            SettingsInfoText(
                text = localizedText("为指定应用深度定制网络与解析控制。支持网络层白名单隔离（仅放行指定域名）、DNS 专属黑白名单及“默认拦截全部外联”向导模式。")
            )

            // Search box
            RuleSearchField(
                value = query,
                onValueChange = { query = it },
                placeholder = localizedText("搜索应用或包名"),
                modifier = Modifier.padding(horizontal = 16.dp)
            )

            // App list area
            if (visibleApps.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(vertical = 36.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Security,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                            modifier = Modifier.size(44.dp)
                        )
                        Text(
                            text = localizedText(if (query.isNotEmpty()) "未找到匹配应用" else "暂无符合条件的应用"),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentPadding = PaddingValues(bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
                ) {
                    itemsIndexed(visibleApps, key = { _, app -> app.packageName }) { index, app ->
                        val ruleCount = appRuleCounts[app.packageName] ?: 0
                        val allowlistDomains = appAllowlistMap[app.packageName].orEmpty()
                        SettingsSurfaceItem(
                            index = index,
                            itemCount = visibleApps.size,
                            modifier = Modifier.padding(horizontal = 16.dp)
                        ) {
                            UnifiedAppItemRow(
                                app = app,
                                ruleCount = ruleCount,
                                allowlistDomainCount = allowlistDomains.size,
                                onClick = { viewModel.selectApp(app) }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showClearAllAllowlistDialog) {
        ClearAllAllowlistDialog(
            onConfirm = {
                viewModel.clearAllAllowlistRules()
                context.showToast("已清空放行规则", Toast.LENGTH_SHORT)
            },
            onDismiss = { showClearAllAllowlistDialog = false }
        )
    }
}
