package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.RuleListPaginationBar
import com.haoze.dnssr.ui.components.RuleTagChip
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsItemSpacing
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.data.entity.RuleScope

@Composable
fun RuleListScreen(
    onBack: () -> Unit,
    ruleKind: ManagedRuleKind = ManagedRuleKind.BLOCK,
    ruleScope: RuleScope = RuleScope.DNS,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    viewModel: RuleListViewModel = viewModel()
) {
    val rules by viewModel.rules.collectAsStateWithLifecycle()
    val currentPage by viewModel.currentPage.collectAsStateWithLifecycle()
    val totalPages by viewModel.totalPages.collectAsStateWithLifecycle()
    val totalCount by viewModel.totalCount.collectAsStateWithLifecycle()
    val searchQuery by viewModel.searchQuery.collectAsStateWithLifecycle()
    val sourceFilter by viewModel.sourceFilter.collectAsStateWithLifecycle()
    val sourceSubscriptions by viewModel.sourceSubscriptions.collectAsStateWithLifecycle()
    val availableAppScopes by viewModel.availableAppScopes.collectAsStateWithLifecycle()
    var showSourceMenu by remember { mutableStateOf(false) }

    NavigationSettledEffect(ruleKind to ruleScope) {
        viewModel.setRuleKind(ruleKind, ruleScope)
        viewModel.activate()
    }

    SettingsScaffold(
        title = localizedText(ruleKind.title),
        onBack = onBack,
        actions = {
            if (!ruleKind.isUrlRule) {
                IconButton(onClick = { showSourceMenu = true }) {
                    Icon(
                        imageVector = Icons.Default.MoreVert,
                        contentDescription = localizedText("筛选规则来源")
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = viewModel::onSearchQueryChange,
                    placeholder = { Text(localizedText(if (ruleKind.isUrlRule) "搜索 URL 规则" else "搜索域名或规则")) },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Default.Search,
                            contentDescription = null
                        )
                    },
                    shape = RoundedCornerShape(28.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                )

                Text(
                    text = localizedText("共 $totalCount 条${ruleKind.countLabel}"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp)
                )

                SettingsDivider()

                // 规则列表为悬浮分页控件预留底部滚动空间。
                LazyColumn(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentPadding = PaddingValues(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 92.dp),
                    verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
                ) {
                    itemsIndexed(rules, key = { _, rule -> rule.id }) { index, rule ->
                        SettingsSurfaceItem(
                            index = index,
                            itemCount = rules.size
                        ) {
                            RuleRowContent(
                                rule = rule,
                                onToggle = { 
                                    if (rule.masterEnabled) {
                                        viewModel.toggleRule(rule.id, it)
                                        onRuntimeDnsSettingsChanged()
                                    }
                                },
                                onDelete = { viewModel.deleteRule(rule.id) }
                            )
                        }
                    }
                }
            }

            // 悬浮分页控件
            RuleListPaginationBar(
                currentPage = currentPage,
                totalPages = totalPages,
                onLoadPage = viewModel::loadPage,
                alwaysShow = true
            )
        }
    }

    if (showSourceMenu) {
        AlertDialog(
            onDismissRequest = { showSourceMenu = false },
            title = { Text(localizedText("筛选规则来源")) },
            text = {
                SettingsSurfaceGroup(
                    groupContentPadding = PaddingValues.Zero,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    content = buildList {
                        add {
                            RuleSourceFilterMenuItem(
                                text = localizedText("全部规则"),
                                selected = sourceFilter == RuleSourceFilter.All,
                                onClick = {
                                    viewModel.selectSourceFilter(RuleSourceFilter.All)
                                    showSourceMenu = false
                                }
                            )
                        }
                        add {
                            RuleSourceFilterMenuItem(
                                text = localizedText("手动添加"),
                                selected = sourceFilter == RuleSourceFilter.Manual,
                                onClick = {
                                    viewModel.selectSourceFilter(RuleSourceFilter.Manual)
                                    showSourceMenu = false
                                }
                            )
                        }
                        sourceSubscriptions.forEach { subscription ->
                            add {
                                RuleSourceFilterMenuItem(
                                    text = subscription.name,
                                    selected = sourceFilter == RuleSourceFilter.Subscription(subscription.id),
                                    onClick = {
                                        viewModel.selectSourceFilter(RuleSourceFilter.Subscription(subscription.id))
                                        showSourceMenu = false
                                    }
                                )
                            }
                        }
                        availableAppScopes.forEach { appScope ->
                            add {
                                RuleSourceFilterMenuItem(
                                    text = "应用: $appScope",
                                    selected = sourceFilter is RuleSourceFilter.AppScope && (sourceFilter as RuleSourceFilter.AppScope).targetApp == appScope,
                                    onClick = {
                                        viewModel.selectSourceFilter(RuleSourceFilter.AppScope(appScope))
                                        showSourceMenu = false
                                    }
                                )
                            }
                        }
                    }
                )
            },
            confirmButton = {
                TextButton(onClick = { showSourceMenu = false }) { Text(localizedText("取消")) }
            }
        )
    }
}

@Composable
private fun RuleSourceFilterMenuItem(
    text: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    SettingsItem(title = text, onClick = onClick) {
        if (selected) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = localizedText("已选中"),
                tint = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@Composable
private fun RuleRowContent(
    rule: RuleListItem,
    onToggle: (Boolean) -> Unit,
    onDelete: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(end = 8.dp)
                .alpha(if (!rule.effectiveEnabled) 0.5f else 1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = rule.pattern,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (rule.important) {
                    RuleTagChip(
                        text = "重要",
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
                if (rule.isWildcard) {
                    RuleTagChip(
                        text = "通配符",
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                    )
                }
            }

            if (!rule.appScope.isNullOrEmpty()) {
                Surface(
                    shape = RoundedCornerShape(4.dp),
                    color = MaterialTheme.colorScheme.tertiaryContainer
                ) {
                    val label = (if (rule.appInverted) "~" else "") + rule.appScope
                    Text(
                        text = "App: $label",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onTertiaryContainer,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }

            rule.targetType?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary) }
            if (rule.rawLine != rule.pattern) {
                Text(
                    text = rule.rawLine,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        Switch(
            checked = rule.effectiveEnabled,
            onCheckedChange = onToggle,
            enabled = rule.masterEnabled,
            modifier = Modifier.alpha(if (!rule.masterEnabled) 0.5f else 1f)
        )
        IconButton(onClick = onDelete) {
            Icon(
                imageVector = Icons.Default.Delete,
                contentDescription = localizedText("删除"),
                tint = MaterialTheme.colorScheme.error
            )
        }
    }
}
