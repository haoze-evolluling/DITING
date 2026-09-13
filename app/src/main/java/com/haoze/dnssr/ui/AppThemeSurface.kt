package com.haoze.dnssr.ui

import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import com.haoze.dnssr.ui.theme.DNSSRTheme
import com.haoze.dnssr.ui.theme.ThemeColorStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
    var backgroundBitmap by remember { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    LaunchedEffect(backgroundEnabled, backgroundUri) {
        backgroundBitmap = if (backgroundEnabled && backgroundUri != null) {
            withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openInputStream(Uri.parse(backgroundUri)).use { stream ->
                        BitmapFactory.decodeStream(stream)?.asImageBitmap()
                    }
                }.getOrNull()
            }
        } else null
    }

    val darkTheme = when (themeMode) {
        AppThemeMode.SYSTEM -> isSystemInDarkTheme()
        AppThemeMode.LIGHT -> false
        AppThemeMode.DARK -> true
    }
    DNSSRTheme(
        darkTheme = darkTheme,
        colorStyle = colorStyle,
        transparentBackground = backgroundBitmap != null
    ) {
        Surface(
            modifier = modifier,
            color = if (backgroundBitmap != null) Color.Transparent else MaterialTheme.colorScheme.background
        ) {
            Box(Modifier.fillMaxSize()) {
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
                content()
            }
        }
    }
}
