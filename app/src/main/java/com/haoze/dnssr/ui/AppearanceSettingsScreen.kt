package com.haoze.dnssr.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.produceState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.ui.components.SettingsActionButton
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.theme.ThemeColorStyle
import com.haoze.dnssr.vpn.DnsVpnService
import com.haoze.dnssr.vpn.VpnMonitorService

@Composable
fun AppearanceSettingsScreen(
    onBack: () -> Unit,
    title: String,
    onNavigateToDayNightMode: () -> Unit,
    onNavigateToThemeColorSettings: () -> Unit,
    onNavigateToHomeComponentOpacity: () -> Unit,
    onNavigateToHomeSentence: () -> Unit,
    onNavigateToNotificationText: () -> Unit,
    onNavigateToGoTunnelDisableButton: () -> Unit,
    onNavigateToCustomBackground: () -> Unit,
    onNavigateToServiceLightEffect: () -> Unit,
    onNavigateToLegacyIcon: () -> Unit,
    onNavigateToLegacyLogPage: () -> Unit
) {
    val context = LocalContext.current
    val mode = AppSettings.getAppThemeMode(context)
    val colorStyle = AppSettings.getThemeColorStyle(context)

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("界面显示")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("日夜模式"),
                        subtitle = localizedText("选择应用使用的浅色或深色外观"),
                        value = localizedText(mode.displayName),
                        onClick = onNavigateToDayNightMode
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("主题色配置"),
                        subtitle = localizedText("选择应用界面的强调色"),
                        value = localizedText(colorStyle.displayName),
                        onClick = onNavigateToThemeColorSettings
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("首页透明度"),
                        subtitle = localizedText("分别调整首页按钮、选择框与文字的透明度"),
                        onClick = onNavigateToHomeComponentOpacity
                        )
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("首页内容")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("首页句子"),
                        subtitle = localizedText("分别设置 DNS 服务开启和关闭时的句子"),
                        onClick = onNavigateToHomeSentence
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("通知栏文案"),
                        subtitle = localizedText("分别设置 DNS 服务开启和关闭时的通知栏文案"),
                        onClick = onNavigateToNotificationText
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("Go 隧道关闭按钮"),
                        subtitle = localizedText("Go 隧道未启用时隐藏首页关闭按钮"),
                        onClick = onNavigateToGoTunnelDisableButton
                        )
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("背景与动效")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("软件背景"),
                        subtitle = localizedText("选取手机图片作为应用背景"),
                        onClick = onNavigateToCustomBackground
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("服务动态光影"),
                        subtitle = localizedText("设置服务启动和关闭时的动态光影效果"),
                        onClick = onNavigateToServiceLightEffect
                        )
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("兼容功能")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("旧版图标"),
                        subtitle = localizedText("切换桌面入口图标的样式"),
                        onClick = onNavigateToLegacyIcon
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("旧版日志页面"),
                        subtitle = localizedText("选择首页日志按钮打开的页面"),
                        onClick = onNavigateToLegacyLogPage
                        )
                    )
                )
            }
        }
    }
}

@Composable
fun LegacyIconSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(AppSettings.isLegacyIconEnabled(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText(title)) }
            item {
                SettingsSurfaceGroup(content = listOf {
                    SettingsSwitchItem(
                        title = localizedText("使用旧版图标"),
                        subtitle = localizedText("开启后仅将桌面入口图标切换为旧版样式"),
                        checked = enabled,
                        onCheckedChange = {
                            enabled = it
                            AppSettings.setLegacyIconEnabled(context, it)
                            LauncherIconManager.setLegacyIconEnabled(context, it)
                        }
                    )
                })
            }
            item { SettingsInfoText(localizedText("桌面图标可能需要等待启动器刷新；如果未立即变化，可回到桌面稍等片刻。")) }
        }
    }
}

@Composable
fun LegacyLogPageSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(AppSettings.isLegacyLogPageEnabled(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText(title)) }
            item {
                SettingsSurfaceGroup(content = listOf {
                    SettingsSwitchItem(
                        title = localizedText("使用旧版日志页面"),
                        subtitle = localizedText("开启后首页日志按钮显示当前的日志分组页；关闭后显示新版日志仪表盘"),
                        checked = enabled,
                        onCheckedChange = {
                            enabled = it
                            AppSettings.setLegacyLogPageEnabled(context, it)
                        }
                    )
                })
            }
        }
    }
}

@Composable
fun GoTunnelDisableButtonSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var hideWhenInactive by remember {
        mutableStateOf(AppSettings.shouldHideGoTunnelDisableButtonWhenInactive(context))
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText(title)) }
            item {
                SettingsSurfaceGroup(content = listOf {
                    SettingsSwitchItem(
                        title = localizedText("Go 隧道未启用时隐藏"),
                        subtitle = localizedText("关闭后，首页始终显示 Go 隧道关闭按钮"),
                        checked = hideWhenInactive,
                        onCheckedChange = {
                            hideWhenInactive = it
                            AppSettings.setHideGoTunnelDisableButtonWhenInactive(context, it)
                        }
                    )
                })
            }
        }
    }
}

@Composable
fun ServiceLightEffectSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    val customBackgroundEnabled = AppSettings.isCustomBackgroundEnabled(context)
    var enabled by remember { mutableStateOf(AppSettings.isServiceLightEffectEnabled(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            item { SettingsGroupTitle(localizedText("服务动态光影")) }
            item {
                SettingsSurfaceGroup(content = listOf {
                    SettingsSwitchItem(
                        title = localizedText("启用服务动态光影"),
                        subtitle = localizedText(when {
                            customBackgroundEnabled -> "软件背景已启用，服务动态光影不可同时使用"
                            supported -> "启动和关闭服务时，光影从电源按钮向整个页面展开或收回"
                            else -> "需要 Android 13 或更高版本"
                        }),
                        checked = enabled,
                        enabled = supported && !customBackgroundEnabled,
                        onCheckedChange = {
                            enabled = it
                            AppSettings.setServiceLightEffectEnabled(context, it)
                        }
                    )
                })
            }
            if (supported && !customBackgroundEnabled) {
                item {
                    SettingsInfoText(localizedText("光影效果代码来源于开源项目:\nhttps://github.com/badnng/Hyper-pick-up-code/"))
                }
            }
        }
    }
}

@Composable
fun CustomBackgroundSettingsScreen(
    onBack: () -> Unit,
    title: String,
    onBackgroundChanged: () -> Unit
) {
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(AppSettings.isCustomBackgroundEnabled(context)) }
    var selectedUri by remember { mutableStateOf(AppSettings.getCustomBackgroundUri(context)) }
    var wallpaperUris by remember { mutableStateOf(AppSettings.getCustomBackgroundUris(context)) }
    var pendingDeletionUri by remember { mutableStateOf<String?>(null) }
    var pendingBackgroundChange by remember { mutableStateOf<PendingBackgroundChange?>(null) }

    fun refreshBackgroundState() {
        enabled = AppSettings.isCustomBackgroundEnabled(context)
        selectedUri = AppSettings.getCustomBackgroundUri(context)
        wallpaperUris = AppSettings.getCustomBackgroundUris(context)
    }

    fun applyBackgroundChange(change: PendingBackgroundChange, enableServiceLightEffect: Boolean = false) {
        AppSettings.setCustomBackground(context, change.enabled, change.uri)
        if (enableServiceLightEffect) {
            AppSettings.setServiceLightEffectEnabled(context, true)
        }
        refreshBackgroundState()
        onBackgroundChanged()
    }

    fun requestBackgroundChange(requestedEnabled: Boolean, uri: String?) {
        val change = PendingBackgroundChange(requestedEnabled, uri)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            applyBackgroundChange(change)
        } else if (requestedEnabled && !enabled) {
            pendingBackgroundChange = change
        } else if (!requestedEnabled && enabled) {
            pendingBackgroundChange = change
        } else {
            applyBackgroundChange(change)
        }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { selected ->
        if (selected != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(selected, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            AppSettings.addCustomBackgroundUri(context, selected.toString())
            requestBackgroundChange(requestedEnabled = true, uri = selected.toString())
        }
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(horizontal = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) { SettingsGroupTitle(localizedText("自定义背景")) }
            item(span = { GridItemSpan(maxLineSpan) }) {
                SettingsSurfaceGroup(content = listOf(
                    {
                        SettingsSwitchItem(
                            title = localizedText("启用软件背景"),
                            subtitle = localizedText(if (selectedUri == null) "请先添加一张图片" else "启用后服务动态光影将自动关闭"),
                            checked = enabled,
                            enabled = selectedUri != null,
                            onCheckedChange = {
                                requestBackgroundChange(requestedEnabled = it, uri = selectedUri)
                            }
                        )
                    },
                    {
                        SettingsItem(title = localizedText("添加图片")) {
                            TextButton(onClick = { picker.launch(arrayOf("image/*")) }, shape = SettingsCornerShape) { Text(localizedText("添加")) }
                        }
                    }
                ))
            }
            item(span = { GridItemSpan(maxLineSpan) }) { SettingsInfoText(localizedText("软件背景与服务动态光影不可同时启用。")) }
            if (wallpaperUris.isNotEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) { SettingsGroupTitle(localizedText("已添加壁纸")) }
                wallpaperUris.chunked(3).forEach { rowUris ->
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 32.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            rowUris.forEach { uri ->
                                WallpaperThumbnail(
                                    modifier = Modifier.weight(1f),
                                    uri = uri,
                                    selected = uri == selectedUri,
                                    onClick = {
                                        requestBackgroundChange(requestedEnabled = true, uri = uri)
                                    },
                                    onLongClick = { pendingDeletionUri = uri }
                                )
                            }
                            repeat(3 - rowUris.size) {
                                Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        }

        pendingDeletionUri?.let { uri ->
            AlertDialog(
                onDismissRequest = { pendingDeletionUri = null },
                title = { Text(localizedText("删除壁纸")) },
                text = { Text(localizedText("确定删除这张已添加的壁纸吗？")) },
                confirmButton = {
                    TextButton(onClick = {
                        AppSettings.removeCustomBackgroundUri(context, uri)
                        pendingDeletionUri = null
                        refreshBackgroundState()
                        onBackgroundChanged()
                    }) { Text(localizedText("删除")) }
                },
                dismissButton = {
                    TextButton(onClick = { pendingDeletionUri = null }) { Text(localizedText("取消")) }
                }
            )
        }

        pendingBackgroundChange?.let { change ->
            val enablingBackground = change.enabled
            AlertDialog(
                onDismissRequest = { pendingBackgroundChange = null },
                title = {
                    Text(localizedText(if (enablingBackground) "开启软件背景" else "关闭软件背景"))
                },
                text = {
                    Text(
                        localizedText(if (enablingBackground) {
                            "开启软件背景会关闭服务动态光影。是否继续？"
                        } else {
                            "关闭软件背景后，是否开启服务动态光影？"
                        })
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        applyBackgroundChange(change, enableServiceLightEffect = !enablingBackground)
                        pendingBackgroundChange = null
                    }) {
                        Text(localizedText(if (enablingBackground) "继续开启" else "开启"))
                    }
                },
                dismissButton = {
                    TextButton(onClick = {
                        if (!enablingBackground) applyBackgroundChange(change)
                        pendingBackgroundChange = null
                    }) {
                        Text(localizedText(if (enablingBackground) "取消" else "不开启"))
                    }
                }
            )
        }
    }
}

private data class PendingBackgroundChange(
    val enabled: Boolean,
    val uri: String?
)

@Composable
private fun WallpaperThumbnail(
    modifier: Modifier = Modifier,
    uri: String,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val screenAspectRatio = configuration.screenWidthDp.toFloat() /
        configuration.screenHeightDp.coerceAtLeast(1).toFloat()
    val bitmap by produceState<androidx.compose.ui.graphics.ImageBitmap?>(initialValue = null, uri) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                context.contentResolver.openInputStream(Uri.parse(uri)).use { stream ->
                    BitmapFactory.decodeStream(stream)?.asImageBitmap()
                }
            }.getOrNull()
        }
    }

    Box(
        modifier = modifier
            .aspectRatio(screenAspectRatio)
            .clip(RoundedCornerShape(8.dp))
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp))
    ) {
        bitmap?.let {
            Image(
                bitmap = it,
                contentDescription = localizedText("软件背景"),
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
        if (selected) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.2f))
            )
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .background(MaterialTheme.colorScheme.primary, CircleShape)
                    .padding(4.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = localizedText("当前背景"),
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}

@Composable
fun HomeSentenceSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var runningSentence by remember { mutableStateOf(AppSettings.getHomeSentenceRunning(context)) }
    var stoppedSentence by remember { mutableStateOf(AppSettings.getHomeSentenceStopped(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("首页句子")) }
            item {
                SettingsGroup {
                    OutlinedTextField(
                        value = runningSentence,
                        onValueChange = { runningSentence = it },
                        label = { Text(localizedText("DNS 服务开启时")) },
                        minLines = 2,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 16.dp, top = 16.dp, end = 16.dp)
                    )
                    OutlinedTextField(
                        value = stoppedSentence,
                        onValueChange = { stoppedSentence = it },
                        label = { Text(localizedText("DNS 服务关闭时")) },
                        minLines = 2,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp)
                    )
                    SettingsActionButton(
                        onClick = {
                            AppSettings.setHomeSentences(context, runningSentence, stoppedSentence)
                            onBack()
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
                    ) {
                        Text(localizedText("确定"))
                    }
                }
            }
            item { SettingsInfoText(localizedText("两项内容均可留空；留空后对应状态下首页不显示句子。")) }
        }
    }
}

@Composable
fun NotificationTextSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var runningText by remember { mutableStateOf(AppSettings.getNotificationTextRunning(context)) }
    var stoppedText by remember { mutableStateOf(AppSettings.getNotificationTextStopped(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            item { SettingsGroupTitle(localizedText("通知栏文案")) }
            item {
                SettingsGroup {
                    OutlinedTextField(
                        value = runningText,
                        onValueChange = { runningText = it },
                        label = { Text(localizedText("DNS 服务开启时")) },
                        minLines = 2,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 16.dp, top = 16.dp, end = 16.dp)
                    )
                    OutlinedTextField(
                        value = stoppedText,
                        onValueChange = { stoppedText = it },
                        label = { Text(localizedText("DNS 服务关闭时")) },
                        minLines = 2,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp)
                    )
                    SettingsActionButton(
                        onClick = {
                            AppSettings.setNotificationTexts(context, runningText, stoppedText)
                            refreshNotificationText(context)
                            onBack()
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
                    ) {
                        Text(localizedText("确定"))
                    }
                }
            }
            item { SettingsInfoText(localizedText("两项内容均可留空；留空后对应通知栏会使用默认状态文案。")) }
        }
    }
}

private fun refreshNotificationText(context: Context) {
    val appContext = context.applicationContext
    if (DnsVpnService.isRunning(appContext)) {
        appContext.startService(DnsVpnService.refreshNotificationIntent(appContext))
        return
    }
    if (!AppSettings.isPersistentNotificationEnabled(appContext) ||
        !hasNotificationPermission(appContext)
    ) {
        return
    }
    ContextCompat.startForegroundService(appContext, VpnMonitorService.startIntent(appContext))
}

private fun hasNotificationPermission(context: Context): Boolean {
    return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
}

@Composable
fun HomeComponentOpacityScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var powerButton by remember { mutableStateOf(AppSettings.getHomePowerButtonOpacity(context)) }
    var providerSelector by remember { mutableStateOf(AppSettings.getHomeProviderSelectorOpacity(context)) }
    var modeButton by remember { mutableStateOf(AppSettings.getHomeModeButtonOpacity(context)) }
    var poem by remember { mutableStateOf(AppSettings.getHomePoemOpacity(context)) }
    var dnsDetail by remember { mutableStateOf(AppSettings.getHomeDnsDetailOpacity(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            item { SettingsGroupTitle(localizedText("交互组件")) }
            item {
                SettingsGroup {
                    OpacitySlider(localizedText("启动按钮"), powerButton, { powerButton = it }) {
                        AppSettings.setHomePowerButtonOpacity(context, powerButton)
                    }
                    SettingsDivider()
                    OpacitySlider(localizedText("解析服务选择框"), providerSelector, { providerSelector = it }) {
                        AppSettings.setHomeProviderSelectorOpacity(context, providerSelector)
                    }
                    SettingsDivider()
                    OpacitySlider(localizedText("模式切换按钮"), modeButton, { modeButton = it }) {
                        AppSettings.setHomeModeButtonOpacity(context, modeButton)
                    }
                }
            }
            item { SettingsGroupTitle(localizedText("文字")) }
            item {
                SettingsGroup {
                    OpacitySlider(localizedText("首页古诗"), poem, { poem = it }) {
                        AppSettings.setHomePoemOpacity(context, poem)
                    }
                    SettingsDivider()
                    OpacitySlider(localizedText("DNS 服务详情"), dnsDetail, { dnsDetail = it }) {
                        AppSettings.setHomeDnsDetailOpacity(context, dnsDetail)
                    }
                }
            }
        }
    }
}

@Composable
private fun OpacitySlider(
    title: String,
    value: Float,
    onValueChange: (Float) -> Unit,
    onValueChangeFinished: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Text("${localizedText(title)} · ${(value * 100).roundToInt()}%")
        Slider(
            value = value,
            onValueChange = onValueChange,
            onValueChangeFinished = onValueChangeFinished,
            valueRange = 0.1f..1f,
            steps = 8,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
fun ThemeColorSettingsScreen(
    onBack: () -> Unit,
    title: String,
    onThemeColorStyleChanged: (ThemeColorStyle) -> Unit
) {
    val context = LocalContext.current
    var selectedStyle by remember { mutableStateOf(AppSettings.getThemeColorStyle(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            item { SettingsGroupTitle(localizedText("主题色")) }
            item {
                SettingsSurfaceGroup(
                    content = ThemeColorStyle.entries.map { style ->
                        {
                            SettingsItem(
                                title = localizedText(style.displayName),
                                subtitle = if (style == ThemeColorStyle.SYSTEM) localizedText("使用系统壁纸的动态取色") else null,
                                onClick = {
                                    selectedStyle = style
                                    AppSettings.setThemeColorStyle(context, style)
                                    onThemeColorStyleChanged(style)
                                }
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(28.dp)
                                        .background(style.lightPrimary, CircleShape),
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (selectedStyle == style) {
                                        Icon(
                                            imageVector = Icons.Filled.CheckCircle,
                                            contentDescription = localizedText("已选中"),
                                            tint = Color.White,
                                            modifier = Modifier.size(18.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                )
            }
        }
    }
}

@Composable
fun DayNightModeScreen(
    onBack: () -> Unit,
    title: String,
    onThemeModeChanged: (AppThemeMode) -> Unit
) {
    val context = LocalContext.current
    var selectedMode by remember { mutableStateOf(AppSettings.getAppThemeMode(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("主题")) }
            item {
                SettingsSurfaceGroup(
                    content = AppThemeMode.entries.map { mode ->
                        {
                            SettingsRadioItem(
                                title = localizedText(mode.displayName),
                                selected = selectedMode == mode,
                                onClick = {
                                    selectedMode = mode
                                    AppSettings.setAppThemeMode(context, mode)
                                    onThemeModeChanged(mode)
                                }
                            )
                        }
                    }
                )
            }
        }
    }
}
