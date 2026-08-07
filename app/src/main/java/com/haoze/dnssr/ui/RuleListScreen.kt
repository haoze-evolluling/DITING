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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
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
    var showPageJumpDialog by remember { mutableStateOf(false) }
    var showSourceMenu by remember { mutableStateOf(false) }
    var pageInput by remember { mutableStateOf("") }
    var pageInputError by remember { mutableStateOf<String?>(null) }
    val pageRangeError = localizedText("请输入 1 到 $totalPages 之间的页码")

    NavigationSettledEffect(ruleKind to ruleScope) {
        viewModel.setRuleKind(ruleKind, ruleScope)
        viewModel.activate()
    }

    if (showPageJumpDialog) {
        AlertDialog(
            onDismissRequest = { showPageJumpDialog = false },
            title = { Text(localizedText("跳转到页面")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(localizedText("请输入 1 到 $totalPages 之间的页码"))
                    OutlinedTextField(
                        value = pageInput,
                        onValueChange = {
                            pageInput = it.filter(Char::isDigit)
                            pageInputError = null
                        },
                        label = { Text(localizedText("页码")) },
                        singleLine = true,
                        isError = pageInputError != null,
                        supportingText = pageInputError?.let { message -> { Text(message) } },
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done
                        )
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val page = pageInput.toIntOrNull()
                        if (page == null || page !in 1..totalPages) {
                            pageInputError = pageRangeError
                        } else {
                            viewModel.loadPage(page)
                            showPageJumpDialog = false
                        }
                    }
                ) {
                    Text(localizedText("跳转"))
                }
            },
            dismissButton = {
                TextButton(onClick = { showPageJumpDialog = false }) {
                    Text(localizedText("取消"))
                }
            }
        )
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
                // 搜索栏
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
                    shape = SettingsCornerShape,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                )

                // 统计信息
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
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(rules, key = { it.id }) { rule ->
                        RuleCard(
                            rule = rule,
                            onToggle = { viewModel.toggleRule(rule.id, it) },
                            onDelete = { viewModel.deleteRule(rule.id) }
                        )
                    }
                }
            }

            // 悬浮分页控件
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                contentAlignment = Alignment.Center
            ) {
                Surface(
                    shape = RoundedCornerShape(28.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    tonalElevation = 2.dp,
                    shadowElevation = 4.dp
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(
                            onClick = {
                                if (currentPage > 1) viewModel.loadPage(currentPage - 1)
                            },
                            enabled = currentPage > 1
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                                contentDescription = localizedText("上一页")
                            )
                        }

                        TextButton(
                            onClick = {
                                pageInput = currentPage.toString()
                                pageInputError = null
                                showPageJumpDialog = true
                            },
                            shape = SettingsCornerShape
                        ) {
                            Text(
                                text = "$currentPage / $totalPages",
                                style = MaterialTheme.typography.labelLarge
                            )
                        }

                        IconButton(
                            onClick = {
                                if (currentPage < totalPages) viewModel.loadPage(currentPage + 1)
                            },
                            enabled = currentPage < totalPages
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                contentDescription = localizedText("下一页")
                            )
                        }
                    }
                }
            }
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
private fun RuleCard(
    rule: RuleListItem,
    onToggle: (Boolean) -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(end = 8.dp)
            ) {
                Text(
                    text = rule.pattern,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
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
                checked = rule.enabled,
                onCheckedChange = onToggle
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
}
