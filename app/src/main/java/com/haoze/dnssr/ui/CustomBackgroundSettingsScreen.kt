package com.haoze.dnssr.ui

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            item { SettingsGroupTitle(localizedText("自定义背景")) }
            item {
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
            item { SettingsInfoText(localizedText("软件背景与服务动态光影不可同时启用。")) }
            if (wallpaperUris.isNotEmpty()) {
                item { SettingsGroupTitle(localizedText("已添加壁纸")) }
                val chunkedUris = wallpaperUris.chunked(3)
                items(chunkedUris.size) { rowIndex ->
                    val rowUris = chunkedUris[rowIndex]
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp)
                            .padding(bottom = 8.dp),
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
            .clip(SettingsCornerShape)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .background(MaterialTheme.colorScheme.surfaceVariant, SettingsCornerShape)
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
