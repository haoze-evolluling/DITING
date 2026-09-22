package com.haoze.diting.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import com.haoze.diting.ui.background.CustomBackgroundManager
import com.haoze.diting.ui.theme.DITINGTheme
import com.haoze.diting.ui.theme.ThemeColorStyle

@Composable
fun AppThemeSurface(
    themeMode: AppThemeMode,
    colorStyle: ThemeColorStyle,
    backgroundEnabled: Boolean,
    backgroundUri: String?,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val context = LocalContext.current
    val isCustomBackground = backgroundEnabled && !backgroundUri.isNullOrBlank()

    // 观察全局背景变更通知（当用户在设置中切换/删除背景时，所有页面同步触发刷新）
    val backgroundUpdateVersion by CustomBackgroundManager.backgroundUpdateFlow.collectAsState()

    // 首帧尝试直接从 CustomBackgroundManager 获取已在内存中的 ImageBitmap，若未载入则通过 ensureLoaded 同步直出
    var backgroundBitmap by remember(backgroundUri, backgroundEnabled, backgroundUpdateVersion) {
        mutableStateOf(
            if (isCustomBackground) {
                CustomBackgroundManager.getCachedImageBitmap(backgroundUri)
                    ?: run {
                        CustomBackgroundManager.ensureLoaded(context)
                        CustomBackgroundManager.getCachedImageBitmap(backgroundUri)
                    }
            } else null
        )
    }

    // 若当前未缓存（如初次设置），发起异步加载并在完成后更新
    LaunchedEffect(backgroundEnabled, backgroundUri, backgroundUpdateVersion) {
        if (isCustomBackground) {
            val cached = CustomBackgroundManager.getCachedImageBitmap(backgroundUri)
            if (cached != null) {
                backgroundBitmap = cached
            } else {
                CustomBackgroundManager.loadBackground(context, backgroundUri) { loaded ->
                    backgroundBitmap = loaded
                }
            }
        } else {
            backgroundBitmap = null
        }
    }

    val darkTheme = when (themeMode) {
        AppThemeMode.SYSTEM -> isSystemInDarkTheme()
        AppThemeMode.LIGHT -> false
        AppThemeMode.DARK -> true
    }

    DITINGTheme(
        darkTheme = darkTheme,
        colorStyle = colorStyle,
        transparentBackground = isCustomBackground && backgroundBitmap != null
    ) {
        Surface(
            modifier = modifier,
            color = if (isCustomBackground && backgroundBitmap != null) Color.Transparent else MaterialTheme.colorScheme.background
        ) {
            Box(Modifier.fillMaxSize()) {
                if (isCustomBackground) {
                    backgroundBitmap?.let { bitmap ->
                        Image(
                            bitmap = bitmap,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                        Box(
                            Modifier
                                .fillMaxSize()
                                .background(Color.Black.copy(alpha = if (darkTheme) 0.34f else 0.16f))
                        )
                    }
                }
                content()
            }
        }
    }
}
