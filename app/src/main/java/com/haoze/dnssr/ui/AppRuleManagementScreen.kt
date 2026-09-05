package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.accompanist.drawablepainter.rememberDrawablePainter
import com.haoze.dnssr.data.entity.AllowRuleEntity
import com.haoze.dnssr.data.entity.BlockRuleEntity
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.RuleConfirmDialog
import com.haoze.dnssr.ui.components.RuleSearchField
import com.haoze.dnssr.ui.components.RuleTagChip
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItemSpacing
import com.haoze.dnssr.ui.components.SettingsNavigationItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSectionSpacing
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
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
            // 顶部总控开关
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

            // 搜索框
            RuleSearchField(
                value = query,
                onValueChange = { query = it },
                placeholder = localizedText("搜索应用或包名"),
                modifier = Modifier.padding(horizontal = 16.dp)
            )

            // 应用列表区
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
        RuleConfirmDialog(
            title = localizedText("清空全部放行规则？"),
            message = localizedText("此操作将清空所有已配置的单应用域名放行规则，清空后各应用将恢复全部放行状态。"),
            confirmText = localizedText("清空"),
            onConfirm = {
                viewModel.clearAllAllowlistRules()
                context.showToast("已清空放行规则", Toast.LENGTH_SHORT)
            },
            onDismiss = { showClearAllAllowlistDialog = false }
        )
    }
}

@Composable
private fun UnifiedAppItemRow(
    app: InstalledApp,
    ruleCount: Int,
    allowlistDomainCount: Int,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 68.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center
        ) {
            app.icon?.let { icon ->
                Image(
                    painter = rememberDrawablePainter(drawable = icon),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize().scale(1.06f)
                )
            } ?: Icon(
                imageVector = Icons.Default.Android,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(26.dp)
            )
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp, end = 8.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = app.label,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = app.packageName,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            if (allowlistDomainCount > 0) {
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = MaterialTheme.colorScheme.primaryContainer
                ) {
                    Text(
                        text = localizedText("放行 $allowlistDomainCount 域名"),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }
            if (ruleCount > 0) {
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = MaterialTheme.colorScheme.secondaryContainer
                ) {
                    Text(
                        text = localizedText("DNS $ruleCount 条"),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }
            if (allowlistDomainCount == 0 && ruleCount == 0) {
                Text(
                    text = localizedText("未配置"),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    modifier = Modifier.padding(end = 2.dp)
                )
            }
        }

        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            modifier = Modifier.padding(start = 4.dp)
        )
    }
}

@Composable
private fun AppSectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    onAddClick: (() -> Unit)? = null,
    addText: String? = null
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 24.dp, end = 16.dp, top = 20.dp, bottom = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = localizedText(title),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f)
        )
        if (onAddClick != null) {
            TextButton(
                onClick = onAddClick,
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    text = localizedText(addText ?: "添加"),
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }
    }
}

@Composable
private fun SingleAppRulePanel(
    app: InstalledApp,
    allowlistDomains: Set<String>,
    fullBlockEnabled: Boolean,
    blockRules: List<BlockRuleEntity>,
    allowRules: List<AllowRuleEntity>,
    onBack: () -> Unit,
    onAddAllowlistDomain: (String) -> Unit,
    onRemoveAllowlistDomain: (String) -> Unit,
    onClearAllowlistDomains: () -> Unit,
    onToggleFullBlock: (Boolean) -> Unit,
    onAddRule: (pattern: String, isAllow: Boolean, important: Boolean, isWildcard: Boolean) -> Unit,
    onToggleRule: (id: Long, isAllow: Boolean, enabled: Boolean) -> Unit,
    onDeleteRule: (id: Long, isAllow: Boolean) -> Unit
) {
    var showFullBlockConfirmDialog by remember { mutableStateOf(false) }
    var showAddAllowlistDialog by remember { mutableStateOf(false) }
    var addAllowlistInput by remember { mutableStateOf("") }
    var addAllowlistError by remember { mutableStateOf<String?>(null) }
    var showClearAllowlistConfirmDialog by remember { mutableStateOf(false) }

    var showAddDnsDialog by remember { mutableStateOf(false) }
    var addDialogIsAllow by remember { mutableStateOf(false) }
    var addDialogPattern by remember { mutableStateOf("") }
    var addDialogImportant by remember { mutableStateOf(false) }
    var addDialogError by remember { mutableStateOf<String?>(null) }

    fun openAddDnsDialog(isAllow: Boolean, defaultImportant: Boolean = false) {
        addDialogIsAllow = isAllow
        addDialogPattern = ""
        addDialogImportant = defaultImportant
        addDialogError = null
        showAddDnsDialog = true
    }

    SettingsScaffold(
        titleContent = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(vertical = 4.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(RoundedCornerShape(11.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest),
                    contentAlignment = Alignment.Center
                ) {
                    app.icon?.let { icon ->
                        Image(
                            painter = rememberDrawablePainter(drawable = icon),
                            contentDescription = null,
                            modifier = Modifier.fillMaxSize().scale(1.06f)
                        )
                    } ?: Icon(
                        imageVector = Icons.Default.Android,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(22.dp)
                    )
                }
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f, fill = false)) {
                    Text(
                        text = app.label,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = app.packageName,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        },
        onBack = onBack
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
        ) {
            // 模块 1：外联与隔离模式
            item(key = "strategy_title") {
                AppSectionHeader(title = "外联与隔离模式")
            }

            item(key = "strategy_group") {
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("默认拦截全部外联"),
                            subtitle = localizedText("开启后阻断该应用的所有网络连接，仅放行白名单"),
                            checked = fullBlockEnabled,
                            onCheckedChange = { next ->
                                if (next) {
                                    showFullBlockConfirmDialog = true
                                } else {
                                    onToggleFullBlock(false)
                                }
                            }
                        )
                    }
                )
            }

            if (fullBlockEnabled) {
                item(key = "fullblock_warning") {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        shape = SettingsCornerShape,
                        color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.65f)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Security,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error,
                                modifier = Modifier.size(20.dp)
                            )
                            Text(
                                text = localizedText("已开启全阻断模式：请确保已添加必要的放行白名单，否则应用可能无法联网。"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onErrorContainer
                            )
                        }
                    }
                }
            }

            // 模块 2：网络层专属放行 (白名单隔离)
            item(key = "allowlist_title") {
                AppSectionHeader(
                    title = "专属放行域名（网络层） (${allowlistDomains.size})",
                    onAddClick = {
                        addAllowlistInput = ""
                        addAllowlistError = null
                        showAddAllowlistDialog = true
                    },
                    addText = "添加放行域名"
                )
            }

            if (allowlistDomains.isEmpty()) {
                item(key = "allowlist_empty") {
                    SettingsSurfaceGroup(
                        content = listOf {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 24.dp, vertical = 16.dp),
                                contentAlignment = Alignment.CenterStart
                            ) {
                                Text(
                                    text = localizedText("未配置网络放行域名"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                )
                            }
                        }
                    )
                }
            } else {
                itemsIndexed(allowlistDomains.sorted(), key = { _, domain -> "domain_$domain" }) { index, domain ->
                    SettingsSurfaceItem(
                        index = index,
                        itemCount = allowlistDomains.size + 1,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 24.dp, end = 16.dp, top = 12.dp, bottom = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Text(
                                    text = domain,
                                    style = MaterialTheme.typography.bodyLarge,
                                    fontWeight = FontWeight.Medium
                                )
                                Text(
                                    text = localizedText("包含子域名"),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                                )
                            }
                            IconButton(
                                onClick = { onRemoveAllowlistDomain(domain) }
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Close,
                                    contentDescription = localizedText("删除 $domain"),
                                    modifier = Modifier.size(20.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }

                item(key = "allowlist_clear_action") {
                    SettingsSurfaceItem(
                        index = allowlistDomains.size,
                        itemCount = allowlistDomains.size + 1,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable(onClick = { showClearAllowlistConfirmDialog = true })
                                .padding(horizontal = 24.dp, vertical = 14.dp),
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = localizedText("清空放行域名"),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.error,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    }
                }
            }

            // 模块 3：DNS 专属白名单规则
            item(key = "allow_rules_title") {
                AppSectionHeader(
                    title = "DNS 专属白名单 (${allowRules.size})",
                    onAddClick = { openAddDnsDialog(isAllow = true) },
                    addText = "添加 DNS 白名单"
                )
            }

            if (allowRules.isEmpty()) {
                item(key = "allow_rules_empty") {
                    SettingsSurfaceGroup(
                        content = listOf {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 24.dp, vertical = 16.dp),
                                contentAlignment = Alignment.CenterStart
                            ) {
                                Text(
                                    text = localizedText("未配置 DNS 白名单"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                )
                            }
                        }
                    )
                }
            } else {
                itemsIndexed(allowRules, key = { _, r -> "allow_${r.id}" }) { index, rule ->
                    SettingsSurfaceItem(
                        index = index,
                        itemCount = allowRules.size,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    ) {
                        RuleEntityRow(
                            pattern = rule.pattern,
                            rawLine = rule.rawLine,
                            enabled = rule.enabled,
                            important = rule.important,
                            isWildcard = rule.isWildcard,
                            onToggle = { onToggleRule(rule.id, true, it) },
                            onDelete = { onDeleteRule(rule.id, true) }
                        )
                    }
                }
            }

            // 模块 4：DNS 专属拦截规则
            item(key = "block_rules_title") {
                AppSectionHeader(
                    title = "DNS 专属拦截 (${blockRules.size})",
                    onAddClick = { openAddDnsDialog(isAllow = false) },
                    addText = "添加 DNS 拦截"
                )
            }

            if (blockRules.isEmpty()) {
                item(key = "block_rules_empty") {
                    SettingsSurfaceGroup(
                        content = listOf {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 24.dp, vertical = 16.dp),
                                contentAlignment = Alignment.CenterStart
                            ) {
                                Text(
                                    text = localizedText("未配置 DNS 拦截规则"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                )
                            }
                        }
                    )
                }
            } else {
                itemsIndexed(blockRules, key = { _, r -> "block_${r.id}" }) { index, rule ->
                    SettingsSurfaceItem(
                        index = index,
                        itemCount = blockRules.size,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    ) {
                        RuleEntityRow(
                            pattern = rule.pattern,
                            rawLine = rule.rawLine,
                            enabled = rule.enabled,
                            important = rule.important,
                            isWildcard = rule.isWildcard,
                            onToggle = { onToggleRule(rule.id, false, it) },
                            onDelete = { onDeleteRule(rule.id, false) }
                        )
                    }
                }
            }
        }
    }

    // 开启全外联拦截的风险确认弹窗
    if (showFullBlockConfirmDialog) {
        RuleConfirmDialog(
            title = localizedText("开启全外联拦截？"),
            message = localizedText("开启后该应用的所有常规网络连接都将被阻断，仅白名单域名可通行。若未添加放行白名单，可能导致应用无法使用。"),
            confirmText = localizedText("确定开启"),
            onConfirm = { onToggleFullBlock(true) },
            onDismiss = { showFullBlockConfirmDialog = false }
        )
    }

    // 添加放行域名弹窗
    if (showAddAllowlistDialog) {
        AlertDialog(
            onDismissRequest = { showAddAllowlistDialog = false },
            title = { Text(localizedText("添加放行域名")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = localizedText("目标应用：${app.label} (${app.packageName})"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                    OutlinedTextField(
                        value = addAllowlistInput,
                        onValueChange = {
                            addAllowlistInput = it
                            addAllowlistError = null
                        },
                        label = { Text(localizedText("域名")) },
                        placeholder = { Text("example.com") },
                        supportingText = {
                            Text(localizedText(addAllowlistError ?: "例如 example.com，将自动放行该域名及其所有子域名"))
                        },
                        isError = addAllowlistError != null,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(
                            onDone = {
                                val d = addAllowlistInput.trim()
                                if (d.isBlank()) {
                                    addAllowlistError = "请输入有效的域名"
                                } else {
                                    onAddAllowlistDomain(d)
                                    showAddAllowlistDialog = false
                                }
                            }
                        ),
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val d = addAllowlistInput.trim()
                        if (d.isBlank()) {
                            addAllowlistError = "请输入有效的域名"
                            return@TextButton
                        }
                        onAddAllowlistDomain(d)
                        showAddAllowlistDialog = false
                    }
                ) {
                    Text(localizedText("确定"))
                }
            },
            dismissButton = {
                TextButton(onClick = { showAddAllowlistDialog = false }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

    // 清空放行域名确认弹窗
    if (showClearAllowlistConfirmDialog) {
        RuleConfirmDialog(
            title = localizedText("清空放行域名？"),
            message = localizedText("此操作将移除该应用配置的所有网络层放行域名。"),
            confirmText = localizedText("清空"),
            onConfirm = { onClearAllowlistDomains() },
            onDismiss = { showClearAllowlistConfirmDialog = false }
        )
    }

    // 添加 DNS 规则弹窗
    if (showAddDnsDialog) {
        AlertDialog(
            onDismissRequest = { showAddDnsDialog = false },
            title = {
                Text(localizedText(if (addDialogIsAllow) "添加应用专属白名单" else "添加应用专属拦截规则"))
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = localizedText("目标应用：${app.label} (${app.packageName})"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                    OutlinedTextField(
                        value = addDialogPattern,
                        onValueChange = {
                            addDialogPattern = it
                            addDialogError = null
                        },
                        label = { Text(localizedText("域名或通配符规则")) },
                        placeholder = { Text(localizedText("如 example.com 或 *-analytics.google.com")) },
                        supportingText = {
                            Text(localizedText(addDialogError ?: "支持通配符模式（如 * 或 *-analytics.google.com）"))
                        },
                        isError = addDialogError != null,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(
                            onDone = {
                                val pattern = addDialogPattern.trim()
                                if (pattern.isBlank()) {
                                    addDialogError = "请输入域名或通配符规则"
                                } else {
                                    val isWc = pattern.contains('*')
                                    onAddRule(pattern, addDialogIsAllow, addDialogImportant, isWc)
                                    showAddDnsDialog = false
                                }
                            }
                        ),
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { addDialogImportant = !addDialogImportant }
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(
                            checked = addDialogImportant,
                            onCheckedChange = { addDialogImportant = it }
                        )
                        Column(modifier = Modifier.padding(start = 8.dp)) {
                            Text(
                                text = localizedText("高优先级 (\$important)"),
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Text(
                                text = localizedText("确保该规则优先于其他常规规则生效"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val pattern = addDialogPattern.trim()
                        if (pattern.isBlank()) {
                            addDialogError = "请输入域名或通配符规则"
                            return@TextButton
                        }
                        val isWc = pattern.contains('*')
                        onAddRule(pattern, addDialogIsAllow, addDialogImportant, isWc)
                        showAddDnsDialog = false
                    }
                ) {
                    Text(localizedText("确定"))
                }
            },
            dismissButton = {
                TextButton(onClick = { showAddDnsDialog = false }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }
}

@Composable
private fun RuleEntityRow(
    pattern: String,
    rawLine: String,
    enabled: Boolean,
    important: Boolean,
    isWildcard: Boolean,
    onToggle: (Boolean) -> Unit,
    onDelete: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 24.dp, end = 12.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(end = 8.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = pattern,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (important) {
                    RuleTagChip(
                        text = localizedText("重要"),
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
                if (isWildcard) {
                    RuleTagChip(
                        text = localizedText("通配符"),
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                    )
                }
            }
            if (rawLine != pattern) {
                Text(
                    text = rawLine,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        Switch(
            checked = enabled,
            onCheckedChange = onToggle
        )
        IconButton(onClick = onDelete) {
            Icon(
                imageVector = Icons.Default.Delete,
                contentDescription = localizedText("删除"),
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}
