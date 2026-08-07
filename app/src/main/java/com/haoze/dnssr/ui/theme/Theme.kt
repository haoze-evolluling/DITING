package com.haoze.dnssr.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

enum class ThemeColorStyle(
    val storageValue: String,
    val displayName: String,
    val lightPrimary: Color,
    val darkPrimary: Color,
    val lightPrimaryContainer: Color,
    val darkPrimaryContainer: Color,
    val lightOnPrimaryContainer: Color,
    val darkOnPrimaryContainer: Color,
    val lightSecondary: Color,
    val darkSecondary: Color,
    val lightTertiary: Color,
    val darkTertiary: Color
) {
    SYSTEM("system", "跟随系统", Purple40, Purple80, Color(0xFFEADDFF), Color(0xFF4F378B), Color(0xFF21005D), Color(0xFFEADDFF), PurpleGrey40, PurpleGrey80, Pink40, Pink80),
    PURPLE("purple", "鸢尾紫", Color(0xFF6E4EA1), Color(0xFFD6BAFF), Color(0xFFECDCFF), Color(0xFF553587), Color(0xFF280057), Color(0xFFECDCFF), Color(0xFF645A70), Color(0xFFCEC2DB), Color(0xFF7F525C), Color(0xFFF1B7C3)),
    BLUE("blue", "睡莲蓝", Color(0xFF00639C), Color(0xFF98CBFF), Color(0xFFCFE5FF), Color(0xFF004A77), Color(0xFF001D33), Color(0xFFCFE5FF), Color(0xFF526070), Color(0xFFB9C8DA), Color(0xFF685779), Color(0xFFD4BEE6)),
    CYAN("cyan", "池水青", Color(0xFF006A64), Color(0xFF50DBD0), Color(0xFF71F7EC), Color(0xFF00504B), Color(0xFF00201E), Color(0xFF71F7EC), Color(0xFF4A6360), Color(0xFFB0CCC8), Color(0xFF48617A), Color(0xFFAFC9E7)),
    GREEN("green", "柳叶绿", Color(0xFF416917), Color(0xFFA5D476), Color(0xFFC1F18F), Color(0xFF2B5000), Color(0xFF0E2000), Color(0xFFC1F18F), Color(0xFF57624A), Color(0xFFBFCBAD), Color(0xFF386664), Color(0xFFA0CFCC)),
    ORANGE("orange", "暮光赭", Color(0xFF974813), Color(0xFFFFB68F), Color(0xFFFFDBCA), Color(0xFF773200), Color(0xFF331100), Color(0xFFFFDBCA), Color(0xFF765848), Color(0xFFE6BEAB), Color(0xFF636032), Color(0xFFCEC891)),
    RED("red", "罂粟红", Color(0xFF9C413E), Color(0xFFFFB3AE), Color(0xFFFFDAD7), Color(0xFF7E2A29), Color(0xFF410005), Color(0xFFFFDAD7), Color(0xFF775654), Color(0xFFE7BDB9), Color(0xFF735B2E), Color(0xFFE2C28C)),
    PINK("pink", "暮霞粉", Color(0xFF99405F), Color(0xFFFFB1C6), Color(0xFFFFD9E1), Color(0xFF7B2947), Color(0xFF3F001C), Color(0xFFFFD9E1), Color(0xFF74565E), Color(0xFFE3BDC6), Color(0xFF7C5634), Color(0xFFEEBD93)),
    INDIGO("indigo", "麦穗金", Color(0xFF785A00), Color(0xFFF2BF48), Color(0xFFFFDF9D), Color(0xFF5B4300), Color(0xFF251A00), Color(0xFFFFDF9D), Color(0xFF6B5D3F), Color(0xFFD8C4A0), Color(0xFF4A6547), Color(0xFFB0CFAA));

    companion object {
        fun fromStorageValue(value: String?): ThemeColorStyle =
            entries.firstOrNull { it.storageValue == value } ?: SYSTEM
    }
}

private val DarkColorScheme = darkColorScheme(
    primary = Purple80,
    secondary = PurpleGrey80,
    tertiary = Pink80
)

private val LightColorScheme = lightColorScheme(
    primary = Purple40,
    secondary = PurpleGrey40,
    tertiary = Pink40

    /* Other default colors to override
    background = Color(0xFFFFFBFE),
    surface = Color(0xFFFFFBFE),
    onPrimary = Color.White,
    onSecondary = Color.White,
    onTertiary = Color.White,
    onBackground = Color(0xFF1C1B1F),
    onSurface = Color(0xFF1C1B1F),
    */
)

@Composable
fun DNSSRTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    colorStyle: ThemeColorStyle = ThemeColorStyle.SYSTEM,
    transparentBackground: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        colorStyle == ThemeColorStyle.SYSTEM && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        colorStyle == ThemeColorStyle.SYSTEM -> if (darkTheme) DarkColorScheme else LightColorScheme
        darkTheme -> darkColorScheme(
            primary = colorStyle.darkPrimary,
            onPrimary = Color(0xFF1B1B1F),
            primaryContainer = colorStyle.darkPrimaryContainer,
            onPrimaryContainer = colorStyle.darkOnPrimaryContainer,
            secondary = colorStyle.darkSecondary,
            tertiary = colorStyle.darkTertiary,
            surfaceTint = colorStyle.darkPrimary
        )
        else -> lightColorScheme(
            primary = colorStyle.lightPrimary,
            onPrimary = Color.White,
            primaryContainer = colorStyle.lightPrimaryContainer,
            onPrimaryContainer = colorStyle.lightOnPrimaryContainer,
            secondary = colorStyle.lightSecondary,
            tertiary = colorStyle.lightTertiary,
            surfaceTint = colorStyle.lightPrimary
        )
    }

    MaterialTheme(
        colorScheme = if (transparentBackground) colorScheme.copy(background = Color.Transparent) else colorScheme,
        typography = Typography,
        content = content
    )
}
