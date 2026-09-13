package com.haoze.dnssr.vpn

import android.content.Context
import android.graphics.Outline
import android.graphics.Typeface
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.setPadding
import com.haoze.dnssr.ui.localizedText

/**
 * Encapsulates view creation and rendering for the floating log overlay.
 */
object FloatingLogViewFactory {

    data class PanelComponents(
        val panel: LinearLayout,
        val logContainer: LinearLayout
    )

    fun dp(value: Int, density: Float): Int = (value * density).toInt()

    fun createBallView(context: Context, density: Float): ImageView {
        return ImageView(context).apply {
            contentDescription = localizedText(context, "打开最近请求")
            setImageResource(com.haoze.dnssr.R.drawable.ic_launcher_dnssr)
            scaleType = ImageView.ScaleType.FIT_CENTER
            elevation = dp(6, density).toFloat()
        }
    }

    fun createPanelView(
        context: Context,
        density: Float,
        palette: OverlayThemePalette,
        dimensions: FloatingPanelDimensions,
        currentSizeName: () -> String,
        onMinimize: () -> Unit,
        onCycleSize: () -> Unit,
        onClose: () -> Unit
    ): PanelComponents {
        val panel = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = FloatingLogTheme.roundedBackground(
                color = palette.panelBg,
                radiusPx = dp(16, density),
                strokeColor = palette.panelBorder,
                strokeWidthPx = dp(1, density)
            )
            elevation = dp(10, density).toFloat()
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, dp(16, density).toFloat())
                }
            }
            clipToOutline = true
        }

        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14, density), dp(8, density), dp(10, density), dp(8, density))
        }

        header.addView(TextView(context).apply {
            text = localizedText(context, "最近请求")
            textSize = 15f
            setTextColor(palette.headerTitleColor)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            gravity = Gravity.CENTER_VERTICAL
            includeFontPadding = false
        }, LinearLayout.LayoutParams(0, dp(34, density), 1f))

        header.addView(createHeaderButton(
            context = context,
            density = density,
            icon = com.haoze.dnssr.R.drawable.ic_overlay_minimize,
            description = localizedText(context, "最小化悬浮窗日志"),
            palette = palette,
            onClick = onMinimize
        ))
        header.addView(createHeaderButton(
            context = context,
            density = density,
            icon = com.haoze.dnssr.R.drawable.ic_overlay_resize,
            description = localizedText(context, "调整悬浮窗大小，当前${currentSizeName()}"),
            palette = palette,
            onClick = onCycleSize
        ))
        header.addView(createHeaderButton(
            context = context,
            density = density,
            icon = com.haoze.dnssr.R.drawable.ic_overlay_close,
            description = localizedText(context, "关闭悬浮窗日志"),
            palette = palette,
            onClick = onClose
        ))
        panel.addView(header, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        val divider = View(context).apply {
            setBackgroundColor(palette.dividerColor)
        }
        panel.addView(divider, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(1, density)
        ))

        val scroll = ScrollView(context).apply {
            isVerticalScrollBarEnabled = true
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
            isVerticalFadingEdgeEnabled = true
            setFadingEdgeLength(dp(12, density))
            clipToPadding = false
        }
        val logs = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10, density), dp(8, density), dp(10, density), dp(6, density))
        }
        scroll.addView(logs, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))
        panel.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1f
        ).apply {
            bottomMargin = dp(8, density)
            leftMargin = dp(2, density)
            rightMargin = dp(2, density)
        })

        return PanelComponents(panel = panel, logContainer = logs)
    }

    fun createHeaderButton(
        context: Context,
        density: Float,
        icon: Int,
        description: String,
        palette: OverlayThemePalette,
        onClick: () -> Unit
    ): ImageButton {
        return ImageButton(context).apply {
            contentDescription = description
            setImageResource(icon)
            setColorFilter(palette.headerButtonTint)
            background = FloatingLogTheme.roundedBackground(palette.headerButtonBg, dp(16, density))
            setPadding(dp(7, density))
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setOnClickListener { onClick() }
        }.also { button ->
            button.layoutParams = LinearLayout.LayoutParams(dp(32, density), dp(32, density)).apply {
                leftMargin = dp(4, density)
            }
        }
    }

    fun createLogCardView(
        context: Context,
        density: Float,
        item: FloatingLogItem,
        palette: OverlayThemePalette
    ): View {
        val sColor = FloatingLogTheme.statusColor(item.status, palette)
        val sLabel = FloatingLogTheme.statusLabel(context, item.status)

        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = FloatingLogTheme.roundedBackground(
                color = palette.cardBg,
                radiusPx = dp(10, density),
                strokeColor = palette.cardBorder,
                strokeWidthPx = dp(1, density)
            )
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, dp(10, density).toFloat())
                }
            }
            clipToOutline = true
            setPadding(dp(12, density), dp(9, density), dp(12, density), dp(9, density))
        }

        // Header row: Title on left, Status badge pill on right
        val headerRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val titleView = TextView(context).apply {
            text = item.title
            textSize = 13.5f
            setTextColor(palette.cardTitleColor)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
        }
        headerRow.addView(titleView, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
            rightMargin = dp(8, density)
        })

        val badgeBg = FloatingLogTheme.roundedBackground(
            color = FloatingLogTheme.colorWithAlpha(sColor, if (palette.isDark) 0.18f else 0.12f),
            radiusPx = dp(4, density)
        )
        val statusBadge = TextView(context).apply {
            text = sLabel
            textSize = 10.5f
            setTextColor(sColor)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            background = badgeBg
            setPadding(dp(6, density), dp(2, density), dp(6, density), dp(2, density))
            gravity = Gravity.CENTER
            includeFontPadding = false
        }
        headerRow.addView(statusBadge, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        card.addView(headerRow, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        // Subtitle row: time · protocol · type · cache · app
        val subtitleView = TextView(context).apply {
            text = item.subtitle
            textSize = 11f
            setTextColor(palette.cardSubtitleColor)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
        }
        card.addView(subtitleView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = dp(3, density)
        })

        // Detail row (if any)
        item.detail?.takeIf { it.isNotBlank() }?.let { detailText ->
            val detailView = TextView(context).apply {
                text = detailText
                textSize = 10.5f
                setTextColor(palette.cardDetailColor)
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            }
            card.addView(detailView, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(2, density)
            })
        }

        return card
    }

    fun renderLoading(
        context: Context,
        density: Float,
        logContainer: LinearLayout,
        palette: OverlayThemePalette
    ) {
        logContainer.removeAllViews()
        logContainer.addView(TextView(context).apply {
            text = localizedText(context, "正在加载日志…")
            textSize = 12.5f
            setTextColor(palette.emptyTextColor)
            gravity = Gravity.CENTER
            setPadding(dp(16, density))
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))
    }

    fun renderLogs(
        context: Context,
        density: Float,
        logContainer: LinearLayout,
        items: List<FloatingLogItem>,
        palette: OverlayThemePalette
    ) {
        logContainer.removeAllViews()
        if (items.isEmpty()) {
            logContainer.addView(TextView(context).apply {
                text = localizedText(context, "暂无请求日志")
                textSize = 12.5f
                setTextColor(palette.emptyTextColor)
                gravity = Gravity.CENTER
                setPadding(dp(16, density))
            }, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ))
            return
        }
        items.forEach { item ->
            val card = createLogCardView(context, density, item, palette)
            logContainer.addView(card, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dp(6, density)
            })
        }
    }
}
