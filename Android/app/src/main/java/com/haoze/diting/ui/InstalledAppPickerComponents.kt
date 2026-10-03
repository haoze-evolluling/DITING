package com.haoze.diting.ui

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.drawable.Drawable
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.cascade.CascadeDropdownMenu
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsLoadingContent
import com.haoze.diting.ui.components.SettingsDivider
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsActionButton
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.google.accompanist.drawablepainter.rememberDrawablePainter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

internal data class InstalledApp(
    val label: String,
    val packageName: String,
    val icon: Drawable?,
    val isSystem: Boolean,
    val normalizedLabel: String,
    val normalizedPackageName: String
)

internal enum class AppListFilter(val label: String) {
    ALL("全部应用"),
    SYSTEM("系统应用"),
    USER("用户应用"),
    SELECTED("已勾选应用")
}

internal enum class AppListSort(val label: String, val comparator: Comparator<InstalledApp>) {
    LABEL_ASC("应用名称 A-Z", compareBy<InstalledApp> { it.normalizedLabel }.thenBy { it.packageName }),
    LABEL_DESC("应用名称 Z-A", compareByDescending<InstalledApp> { it.normalizedLabel }.thenBy { it.packageName }),
    PACKAGE_ASC("包名 A-Z", compareBy<InstalledApp> { it.normalizedPackageName }),
    PACKAGE_DESC("包名 Z-A", compareByDescending<InstalledApp> { it.normalizedPackageName })
}

@Composable
internal fun AppListOverflowMenu(
    filter: AppListFilter,
    sort: AppListSort,
    onSelectAll: () -> Unit,
    onClear: () -> Unit,
    onInvert: () -> Unit,
    onFilterChange: (AppListFilter) -> Unit,
    onSortChange: (AppListSort) -> Unit,
    showSelectionActions: Boolean = true
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(Icons.Default.MoreVert, contentDescription = localizedText("应用列表菜单"))
        }

        CascadeDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            fixedWidth = 200.dp
        ) {
            if (showSelectionActions) {
                DropdownMenuItem(
                    text = { Text(localizedText("全选")) },
                    onClick = {
                        onSelectAll()
                        expanded = false
                    }
                )
                DropdownMenuItem(
                    text = { Text(localizedText("清除")) },
                    onClick = {
                        onClear()
                        expanded = false
                    }
                )
                DropdownMenuItem(
                    text = { Text(localizedText("反选")) },
                    onClick = {
                        onInvert()
                        expanded = false
                    }
                )
            }
            DropdownMenuItem(
                text = { Text(localizedText("过滤")) },
                childrenHeader = { DropdownMenuHeader(text = { Text(localizedText("过滤应用")) }) },
                children = {
                    AppListFilter.entries.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(localizedText(option.label)) },
                            trailingIcon = {
                                if (filter == option) {
                                    Icon(
                                        Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(20.dp)
                                    )
                                }
                            },
                            onClick = {
                                onFilterChange(option)
                                expanded = false
                            }
                        )
                    }
                }
            )
            DropdownMenuItem(
                text = { Text(localizedText("排序")) },
                childrenHeader = { DropdownMenuHeader(text = { Text(localizedText("排序方式")) }) },
                children = {
                    AppListSort.entries.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(localizedText(option.label)) },
                            trailingIcon = {
                                if (sort == option) {
                                    Icon(
                                        Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(20.dp)
                                    )
                                }
                            },
                            onClick = {
                                onSortChange(option)
                                expanded = false
                            }
                        )
                    }
                }
            )
        }
    }
}

private val AppIconShape = RoundedCornerShape(14.dp)

internal suspend fun loadInstalledApps(context: Context): List<InstalledApp> = withContext(Dispatchers.IO) {
    val packageManager = context.packageManager
    @Suppress("DEPRECATION")
    packageManager.getInstalledApplications(0)
        .asSequence()
        .filter { it.packageName != context.packageName }
        .map { info ->
            val label = info.loadLabel(packageManager).toString()
            InstalledApp(
                label = label,
                packageName = info.packageName,
                icon = runCatching { info.loadIcon(packageManager) }.getOrNull(),
                isSystem = info.flags and ApplicationInfo.FLAG_SYSTEM != 0,
                normalizedLabel = label.lowercase(Locale.ROOT),
                normalizedPackageName = info.packageName.lowercase(Locale.ROOT)
            )
        }
        .sortedWith(compareBy<InstalledApp> { it.normalizedLabel }.thenBy { it.packageName })
        .toList()
}

@Composable
internal fun InstalledAppCheckboxItem(
    app: InstalledApp,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    InstalledAppItem(
        app = app,
        modifier = modifier,
        onClick = { onCheckedChange(!checked) }
    ) {
        Checkbox(
            checked = checked,
            onCheckedChange = onCheckedChange,
            modifier = Modifier.padding(start = 12.dp)
        )
    }
}

@Composable
internal fun InstalledAppRadioItem(
    app: InstalledApp,
    selected: Boolean,
    onSelected: () -> Unit,
    modifier: Modifier = Modifier
) {
    InstalledAppItem(
        app = app,
        modifier = modifier,
        onClick = onSelected
    ) {
        RadioButton(
            selected = selected,
            onClick = onSelected,
            modifier = Modifier.padding(start = 12.dp)
        )
    }
}

@Composable
private fun InstalledAppItem(
    app: InstalledApp,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    trailing: @Composable () -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 68.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(AppIconShape)
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
                modifier = Modifier.size(28.dp)
            )
        }
        Column(
            modifier = Modifier.weight(1f).padding(start = 12.dp),
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
        trailing()
    }
}

internal data class AppListAccessState<T>(
    val apps: List<T>?,
    val unavailable: Boolean,
    val showDisclosure: Boolean,
    val allowAccess: () -> Unit,
    val dismissDisclosure: () -> Unit,
    val retry: () -> Unit
)

@Composable
internal fun <T> rememberAppListAccessState(loader: suspend () -> List<T>): AppListAccessState<T> {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var apps by remember { mutableStateOf<List<T>?>(null) }
    var unavailable by remember { mutableStateOf(false) }
    var showDisclosure by remember {
        mutableStateOf(!PermissionDisclosureSettings.isAppListExplained(context))
    }
    var loadGeneration by remember { mutableIntStateOf(0) }
    var awaitingSystemResult by remember { mutableStateOf(false) }

    fun requestLoad() {
        awaitingSystemResult = true
        unavailable = false
        apps = null
        loadGeneration++
    }

    LaunchedEffect(loadGeneration, showDisclosure) {
        if (showDisclosure) return@LaunchedEffect
        awaitingSystemResult = true
        val loaded = loader()
        if (loaded.isNotEmpty()) {
            awaitingSystemResult = false
            PermissionDisclosureSettings.markAppListAvailable(context)
            apps = loaded
            unavailable = false
        } else {
            apps = emptyList()
            unavailable = true
            if (PermissionDisclosureSettings.wasAppListAvailable(context)) {
                PermissionDisclosureSettings.setAppListExplained(context, false)
                showDisclosure = true
            }
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && awaitingSystemResult) {
                awaitingSystemResult = false
                loadGeneration++
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    return AppListAccessState(
        apps = apps,
        unavailable = unavailable,
        showDisclosure = showDisclosure,
        allowAccess = {
            PermissionDisclosureSettings.setAppListExplained(context, true)
            showDisclosure = false
            requestLoad()
        },
        dismissDisclosure = {
            showDisclosure = false
            unavailable = true
            apps = emptyList()
        },
        retry = {
            if (PermissionDisclosureSettings.isAppListExplained(context)) {
                requestLoad()
            } else {
                showDisclosure = true
            }
        }
    )
}

@Composable
internal fun AppListDisclosureDialog(state: AppListAccessState<*>) {
    if (!state.showDisclosure) return
    AppConfirmDialog(
        onDismissRequest = state.dismissDisclosure,
        title = "应用列表访问",
        message = "为了让你选择需要排除或进行 HTTP(S) 检查的应用，谛听需要读取设备上的应用列表。不会读取应用数据，也不会上传应用列表。",
        confirmLabel = "继续",
        cancelLabel = "暂不允许",
        onConfirm = state.allowAccess
    )
}

@Composable
internal fun AppListUnavailableContent(modifier: Modifier, onRetry: () -> Unit) {
    Column(
        modifier = modifier.fillMaxSize().padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
            SettingsInfoText(localizedText("需要应用列表访问权限才能选择应用。未授权不会影响其他功能。"))
        SettingsActionButton(onClick = onRetry, modifier = Modifier.padding(top = 16.dp)) {
            Text(localizedText("允许访问"))
        }
    }
}

@Composable
internal fun AppListLoadingContent(modifier: Modifier) {
    SettingsLoadingContent(modifier)
}
