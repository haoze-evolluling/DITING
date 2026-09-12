package com.haoze.dnssr.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/**
 * 主题色风格。
 *
 * SYSTEM 在 Android 12+ 上使用 Monet（Material You）动态取色；
 * 低于 Android 12 或其余预设项使用 [PresetPalettes] 中按 M3 规范生成的完整配色。
 */
enum class ThemeColorStyle(
    val storageValue: String,
    val displayName: String,
    val light: M3ColorPalette,
    val dark: M3ColorPalette
) {
    SYSTEM("system", "跟随系统", PURPLE_LIGHT, PURPLE_DARK),
    PURPLE("purple", "鸢尾紫", PURPLE_LIGHT, PURPLE_DARK),
    BLUE("blue", "睡莲蓝", BLUE_LIGHT, BLUE_DARK),
    CYAN("cyan", "池水青", CYAN_LIGHT, CYAN_DARK),
    GREEN("green", "柳叶绿", GREEN_LIGHT, GREEN_DARK),
    ORANGE("orange", "暮光赭", ORANGE_LIGHT, ORANGE_DARK),
    RED("red", "罂粟红", RED_LIGHT, RED_DARK),
    PINK("pink", "暮霞粉", PINK_LIGHT, PINK_DARK),
    GOLD("indigo", "麦穗金", GOLD_LIGHT, GOLD_DARK);

    fun palette(darkTheme: Boolean): M3ColorPalette = if (darkTheme) dark else light

    companion object {
        fun fromStorageValue(value: String?): ThemeColorStyle =
            entries.firstOrNull { it.storageValue == value } ?: SYSTEM
    }
}

/** 设置页色样使用的颜色：SYSTEM 在 Android 12+ 上展示真实的壁纸动态取色。 */
@Composable
fun ThemeColorStyle.swatchColor(darkTheme: Boolean): Color {
    if (this == ThemeColorStyle.SYSTEM && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val context = LocalContext.current
        return if (darkTheme) dynamicDarkColorScheme(context).primary
        else dynamicLightColorScheme(context).primary
    }
    return palette(darkTheme).primary
}

@Composable
fun DNSSRTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    colorStyle: ThemeColorStyle = ThemeColorStyle.SYSTEM,
    transparentBackground: Boolean = false,
    content: @Composable () -> Unit
) {
    val context = LocalContext.current
    val colorScheme = when {
        colorStyle == ThemeColorStyle.SYSTEM && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        else -> colorStyle.palette(darkTheme).toColorScheme(darkTheme)
    }

    MaterialTheme(
        colorScheme = if (transparentBackground) colorScheme.copy(background = Color.Transparent) else colorScheme,
        typography = Typography,
        content = content
    )
}
