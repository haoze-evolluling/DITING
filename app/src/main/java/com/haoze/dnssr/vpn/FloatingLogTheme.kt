package com.haoze.dnssr.vpn

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import androidx.compose.ui.graphics.toArgb
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.AppThemeMode
import com.haoze.dnssr.ui.localizedText
import com.haoze.dnssr.ui.theme.ThemeColorStyle

/**
 * Handles theming, color resolution, and styling drawables for the floating log overlay.
 */
object FloatingLogTheme {

    fun roundedBackground(
        color: Int,
        radiusPx: Int,
        strokeColor: Int? = null,
        strokeWidthPx: Int = 1
    ): GradientDrawable = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radiusPx.toFloat()
        if (strokeColor != null) {
            setStroke(strokeWidthPx, strokeColor)
        }
    }

    fun colorWithAlpha(color: Int, alphaFraction: Float): Int {
        val a = (Color.alpha(color) * alphaFraction).toInt().coerceIn(0, 255)
        return Color.argb(a, Color.red(color), Color.green(color), Color.blue(color))
    }

    fun statusColor(status: FloatingLogStatus, palette: OverlayThemePalette): Int = when (status) {
        FloatingLogStatus.PASSED -> palette.passedColor
        FloatingLogStatus.BLOCKED -> palette.blockedColor
        FloatingLogStatus.REWRITTEN -> palette.rewrittenColor
        FloatingLogStatus.BYPASSED -> palette.bypassedColor
        FloatingLogStatus.ERROR -> palette.errorColor
    }

    fun statusLabel(context: Context, status: FloatingLogStatus): String = localizedText(
        context,
        when (status) {
            FloatingLogStatus.PASSED -> "通过"
            FloatingLogStatus.BLOCKED -> "过滤"
            FloatingLogStatus.REWRITTEN -> "覆写"
            FloatingLogStatus.BYPASSED -> "旁路"
            FloatingLogStatus.ERROR -> "失败"
        }
    )

    fun getPrimaryColor(context: Context, isDark: Boolean, colorStyle: ThemeColorStyle): Int {
        if (colorStyle == ThemeColorStyle.SYSTEM && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val colorRes = if (isDark) android.R.color.system_accent1_200 else android.R.color.system_accent1_600
            runCatching { return context.getColor(colorRes) }
        }
        return if (isDark) colorStyle.darkPrimary.toArgb() else colorStyle.lightPrimary.toArgb()
    }

    fun getTertiaryColor(context: Context, isDark: Boolean, colorStyle: ThemeColorStyle): Int {
        if (colorStyle == ThemeColorStyle.SYSTEM && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val colorRes = if (isDark) android.R.color.system_accent3_200 else android.R.color.system_accent3_600
            runCatching { return context.getColor(colorRes) }
        }
        return if (isDark) colorStyle.darkTertiary.toArgb() else colorStyle.lightTertiary.toArgb()
    }

    fun getPalette(context: Context): OverlayThemePalette {
        val themeMode = AppSettings.getAppThemeMode(context)
        val isDark = when (themeMode) {
            AppThemeMode.LIGHT -> false
            AppThemeMode.DARK -> true
            AppThemeMode.SYSTEM -> {
                val nightModeFlags = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
                nightModeFlags == Configuration.UI_MODE_NIGHT_YES
            }
        }
        val colorStyle = AppSettings.getThemeColorStyle(context)
        val primaryColor = getPrimaryColor(context, isDark, colorStyle)
        val tertiaryColor = getTertiaryColor(context, isDark, colorStyle)

        return if (isDark) {
            OverlayThemePalette(
                isDark = true,
                panelBg = 0xF21C2128.toInt(),
                panelBorder = 0x33FFFFFF,
                headerTitleColor = 0xFFF0F3F8.toInt(),
                headerButtonBg = 0x1AFFFFFF,
                headerButtonTint = 0xFFDCE2EC.toInt(),
                dividerColor = 0x1FFFFFFF,
                cardBg = 0x3D2F3A4A.toInt(),
                cardBorder = 0x26FFFFFF,
                cardTitleColor = 0xFFF0F3F8.toInt(),
                cardSubtitleColor = 0xFF9AA0A6.toInt(),
                cardDetailColor = 0xFF80868B.toInt(),
                emptyTextColor = 0xFF9AA0A6.toInt(),
                passedColor = primaryColor,
                blockedColor = 0xFFFFB4AB.toInt(),
                rewrittenColor = tertiaryColor,
                bypassedColor = 0xFFB0B7C3.toInt(),
                errorColor = 0xFFFFB4AB.toInt()
            )
        } else {
            OverlayThemePalette(
                isDark = false,
                panelBg = 0xF8FFFFFF.toInt(),
                panelBorder = 0x24000000,
                headerTitleColor = 0xFF1C1B1F.toInt(),
                headerButtonBg = 0x0D000000,
                headerButtonTint = 0xFF44474E.toInt(),
                dividerColor = 0x12000000,
                cardBg = 0xFFF0F4F8.toInt(),
                cardBorder = 0x1A000000,
                cardTitleColor = 0xFF1C1B1F.toInt(),
                cardSubtitleColor = 0xFF44474E.toInt(),
                cardDetailColor = 0xFF74777F.toInt(),
                emptyTextColor = 0xFF74777F.toInt(),
                passedColor = primaryColor,
                blockedColor = 0xFFBA1A1A.toInt(),
                rewrittenColor = tertiaryColor,
                bypassedColor = 0xFF5F6368.toInt(),
                errorColor = 0xFFBA1A1A.toInt()
            )
        }
    }
}
