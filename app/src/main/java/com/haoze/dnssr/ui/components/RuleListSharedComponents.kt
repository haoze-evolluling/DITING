package com.haoze.dnssr.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.BoxScope
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.localizedText

/**
 * 规则管理类页面共享的通用组件：
 * 搜索框、筛选 Chip 行、列表头、空状态、悬浮分页条（含跳页弹窗）、统计卡、标签 Chip、危险操作确认弹窗。
 */

@Composable
fun RuleSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        placeholder = { Text(placeholder) },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        trailingIcon = {
            if (value.isNotEmpty()) {
                IconButton(onClick = { onValueChange("") }) {
                    Icon(Icons.Filled.Close, contentDescription = localizedText("清除"))
                }
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(28.dp)
    )
}

@Composable
fun <T> RuleFilterChipRow(
    filters: List<T>,
    selectedFilter: T,
    onSelect: (T) -> Unit,
    labelKeyOf: (T) -> String,
    modifier: Modifier = Modifier
) {
    LazyRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(vertical = 2.dp)
    ) {
        items(filters) { f ->
            FilterChip(
                selected = selectedFilter == f,
                onClick = { onSelect(f) },
                label = { Text(localizedText(labelKeyOf(f))) },
                shape = RoundedCornerShape(16.dp)
            )
        }
    }
}

@Composable
fun RuleListCountHeader(totalCount: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 8.dp, end = 8.dp, top = 8.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = localizedText("规则列表"),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = localizedText("共 $totalCount 条"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
fun RuleListEmptyState(message: String) {
    SettingsSurfaceGroup(
        groupContentPadding = PaddingValues.Zero,
        content = listOf {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(32.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    )
}

/**
 * 悬浮分页条（含左右翻页与跳页弹窗）。须置于 Box 作用域内（底部居中悬浮）。
 * [alwaysShow] 为 true 时单页也显示（历史行为），默认仅在多页时显示。
 */
@Composable
fun BoxScope.RuleListPaginationBar(
    currentPage: Int,
    totalPages: Int,
    onLoadPage: (Int) -> Unit,
    modifier: Modifier = Modifier,
    alwaysShow: Boolean = false
) {
    val context = LocalContext.current
    var showPageJumpDialog by remember { mutableStateOf(false) }
    var pageInput by remember { mutableStateOf("") }
    var pageInputError by remember { mutableStateOf<String?>(null) }

    if (totalPages > 1 || alwaysShow) {
        Box(
            modifier = modifier
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
                        onClick = { if (currentPage > 1) onLoadPage(currentPage - 1) },
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
                        onClick = { if (currentPage < totalPages) onLoadPage(currentPage + 1) },
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

    if (showPageJumpDialog) {
        AppAlertDialog(
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
                        supportingText = pageInputError?.let { msg -> { Text(msg) } },
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done
                        ),
                        shape = SettingsCornerShape
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val page = pageInput.toIntOrNull()
                    if (page == null || page !in 1..totalPages) {
                        pageInputError = localizedText(context, "请输入 1 到 $totalPages 之间的页码")
                    } else {
                        onLoadPage(page)
                        showPageJumpDialog = false
                    }
                }) {
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
}

@Composable
fun RuleStatsCard(
    icon: ImageVector,
    title: String,
    activeBadgeText: String,
    stats: List<Pair<String, String>>
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.primaryContainer
                ) {
                    Text(
                        text = activeBadgeText,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }

            SettingsDivider()

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                stats.forEach { (label, value) ->
                    RuleStatItem(label = label, value = value)
                }
            }
        }
    }
}

@Composable
private fun RuleStatItem(label: String, value: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
        Text(
            text = localizedText(label),
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/** 规则行内的小号标签胶囊（来源/类型/重要/通配符等）。 */
@Composable
fun RuleTagChip(
    text: String,
    containerColor: Color,
    contentColor: Color,
    modifier: Modifier = Modifier,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip,
    shape: Shape = RoundedCornerShape(4.dp)
) {
    Surface(
        shape = shape,
        color = containerColor,
        modifier = modifier
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = contentColor,
            maxLines = maxLines,
            overflow = overflow,
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp)
        )
    }
}

/**
 * 危险操作确认弹窗：红色确认按钮 + 取消按钮。
 * 点击确认后依次执行 [onConfirm] 与 [onDismiss]（保持原调用点的关闭弹窗 → Toast → 刷新顺序）。
 */
@Composable
fun RuleConfirmDialog(
    title: String,
    message: String,
    confirmText: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    destructive: Boolean = true
) {
    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(onClick = {
                onConfirm()
                onDismiss()
            }) {
                Text(
                    confirmText,
                    color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}

/** 规则行的"更多操作"下拉菜单（编辑 + 删除）。[enabled] 为 false 时点击触发 [onDisabledClick] 并降低图标不透明度。 */
@Composable
fun RuleItemActionsMenu(
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    enabled: Boolean = true,
    onDisabledClick: () -> Unit = {}
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { if (enabled) expanded = true else onDisabledClick() }) {
            Icon(
                imageVector = Icons.Filled.MoreVert,
                contentDescription = localizedText("更多操作"),
                tint = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant
                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            DropdownMenuItem(
                text = { Text(localizedText("编辑")) },
                leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                onClick = {
                    expanded = false
                    onEdit()
                }
            )
            DropdownMenuItem(
                text = { Text(localizedText("删除"), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                onClick = {
                    expanded = false
                    onDelete()
                }
            )
        }
    }
}

/** 总开关未开启时，按规则类型与当前设置给出应先开启哪一项的提示文案。 */
fun masterDisabledMessage(context: Context, isDomainType: Boolean): String {
    return if (isDomainType) {
        "请先在规则控制中开启【启用域名规则】"
    } else if (!AppSettings.isAddressRulesEnabled(context)) {
        "请先在规则控制中开启【启用地址规则】"
    } else if (!AppSettings.isHttpsInspectionReady(context)) {
        "请先安装并验证 CA 根证书"
    } else if (!AppSettings.isHttpInspectionEnabled(context)) {
        "请先在 HTTPS 流量检查中开启检查"
    } else {
        "请先在 HTTPS 流量检查中选择目标应用"
    }
}
