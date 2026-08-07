package com.haoze.dnssr.vpn

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.setPadding
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.DnsLogEntity
import com.haoze.dnssr.data.entity.HttpRequestLogEntity
import com.haoze.dnssr.data.repository.RequestLogRepository
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.localizedText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs

private data class FloatingLogItem(
    val timestamp: Long,
    val title: String,
    val subtitle: String,
    val status: String
)

private data class FloatingPanelDimensions(
    val width: Int,
    val height: Int,
    val contentWidth: Int,
    val contentHeight: Int
)

/** Owns the small overlay used to inspect recent DNS and HTTPS requests. */
class FloatingLogOverlayController(context: Context) {
    private val appContext = context.applicationContext
    private val windowManager = appContext.getSystemService(WindowManager::class.java)
    private val repository = AppDatabase.getInstance(appContext).let { database ->
        RequestLogRepository(database.dnsLogDao(), database.httpRequestLogDao())
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val timeFormatter = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    private val density = appContext.resources.displayMetrics.density

    private var root: LinearLayout? = null
    private var ball: ImageView? = null
    private var logContainer: LinearLayout? = null
    private var windowParams: WindowManager.LayoutParams? = null
    private var refreshJob: Job? = null
    private var appInForeground = AppSettings.isMainActivityForeground(appContext)
    private var vpnRunning = false
    private var hiddenForCurrentBackground = false
    private var expanded = false
    private var panelSize = AppSettings.getFloatingLogPanelSize(appContext)
    private var downRawX = 0f
    private var downRawY = 0f
    private var downWindowX = 0
    private var downWindowY = 0

    fun setVpnRunning(running: Boolean) {
        vpnRunning = running
        syncVisibility()
    }

    fun setAppInForeground(foreground: Boolean) {
        appInForeground = foreground
        hiddenForCurrentBackground = false
        syncVisibility()
    }

    fun refreshSettings() {
        syncVisibility()
    }

    fun destroy() {
        refreshJob?.cancel()
        scope.cancel()
        removeWindow()
    }

    private fun syncVisibility() {
        if (!vpnRunning || appInForeground || hiddenForCurrentBackground || !AppSettings.isFloatingLogEnabled(appContext)) {
            refreshJob?.cancel()
            removeWindow()
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(appContext)) {
            refreshJob?.cancel()
            removeWindow()
            return
        }
        ensureWindow()
    }

    private fun ensureWindow() {
        if (root != null) return
        val container = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        val floatingBall = ImageView(appContext).apply {
        contentDescription = localizedText(appContext, "打开最近请求")
            setImageResource(com.haoze.dnssr.R.drawable.ic_launcher_dnssr)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        container.addView(floatingBall, LinearLayout.LayoutParams(dp(48), dp(48)))
        root = container
        ball = floatingBall
        installDragHandler(floatingBall)
        updateWindowSize()
        runCatching {
            windowManager.addView(container, windowParams)
        }.onFailure {
            root = null
            ball = null
            windowParams = null
        Toast.makeText(appContext, localizedText(appContext, "悬浮窗日志启动失败"), Toast.LENGTH_SHORT).show()
        }
    }

    private fun installDragHandler(view: View) {
        view.setOnTouchListener { _, event ->
            val params = windowParams ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    downWindowX = params.x
                    downWindowY = params.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = downWindowX + (event.rawX - downRawX).toInt()
                    params.y = downWindowY + (event.rawY - downRawY).toInt()
                    root?.let { windowManager.updateViewLayout(it, params) }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val moved = abs(event.rawX - downRawX) > dp(10) || abs(event.rawY - downRawY) > dp(10)
                    if (!moved) toggleExpanded()
                    true
                }
                else -> true
            }
        }
    }

    private fun toggleExpanded() {
        expanded = !expanded
        if (expanded) {
            showPanel()
            startRefreshing()
        } else {
            stopRefreshing()
            removePanel()
        }
        updateWindowSize()
    }

    private fun showPanel() {
        val container = root ?: return
        if (logContainer != null) return
        val dimensions = panelDimensions()
        val panel = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedBackground(0xf02a2f35.toInt(), 12)
            elevation = dp(10).toFloat()
        }
        val header = LinearLayout(appContext).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(6), dp(8), dp(6))
        }
        header.addView(TextView(appContext).apply {
        text = localizedText(appContext, "最近请求")
            textSize = 17f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER_VERTICAL
            includeFontPadding = false
        }, LinearLayout.LayoutParams(0, dp(40), 1f))
        header.addView(createHeaderButton(
            icon = com.haoze.dnssr.R.drawable.ic_overlay_minimize,
        description = localizedText(appContext, "最小化悬浮窗日志"),
            onClick = ::minimizePanel
        ))
        header.addView(createHeaderButton(
            icon = com.haoze.dnssr.R.drawable.ic_overlay_resize,
        description = localizedText(appContext, "调整悬浮窗大小，当前${panelSizeName()}"),
            onClick = ::cyclePanelSize
        ))
        header.addView(createHeaderButton(
            icon = com.haoze.dnssr.R.drawable.ic_overlay_close,
        description = localizedText(appContext, "关闭悬浮窗日志"),
            onClick = ::hideForCurrentBackground
        ))
        panel.addView(header)

        val scroll = ScrollView(appContext)
        val logs = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(2), dp(10), dp(10))
        }
        scroll.addView(logs)
        panel.addView(scroll, LinearLayout.LayoutParams(dp(dimensions.contentWidth), dp(dimensions.contentHeight)))
        container.addView(panel, LinearLayout.LayoutParams(dp(dimensions.width), dp(dimensions.height)))
        ball?.visibility = View.GONE
        installPanelDragHandler(panel)
        logContainer = logs
        renderLoading()
    }

    private fun createHeaderButton(icon: Int, description: String, onClick: () -> Unit): ImageButton {
        return ImageButton(appContext).apply {
            contentDescription = description
            setImageResource(icon)
            setColorFilter(0xffe2e6ed.toInt())
            background = roundedBackground(0x1affffff, 20)
            setPadding(dp(8))
            setOnClickListener { onClick() }
        }.also { button ->
            button.layoutParams = LinearLayout.LayoutParams(dp(40), dp(40)).apply {
                leftMargin = dp(2)
            }
        }
    }

    private fun cyclePanelSize() {
        panelSize = (panelSize + 1) % 3
        AppSettings.setFloatingLogPanelSize(appContext, panelSize)
        applyPanelSize()
        Toast.makeText(appContext, localizedText(appContext, "悬浮窗：${panelSizeName()}"), Toast.LENGTH_SHORT).show()
    }

    private fun applyPanelSize() {
        val dimensions = panelDimensions()
        val panel = logContainer?.parent?.parent as? View ?: return
        panel.layoutParams = (panel.layoutParams as LinearLayout.LayoutParams).apply {
            width = dp(dimensions.width)
            height = dp(dimensions.height)
        }
        val scroll = logContainer?.parent as? View ?: return
        scroll.layoutParams = (scroll.layoutParams as LinearLayout.LayoutParams).apply {
            width = dp(dimensions.contentWidth)
            height = dp(dimensions.contentHeight)
        }
        panel.requestLayout()
        updateWindowSize()
    }

    private fun installPanelDragHandler(panel: View) {
        panel.setOnTouchListener { _, event ->
            handleDrag(event, toggleOnClick = false)
        }
    }

    private fun handleDrag(event: MotionEvent, toggleOnClick: Boolean): Boolean {
        val params = windowParams ?: return false
        return when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downRawX = event.rawX
                downRawY = event.rawY
                downWindowX = params.x
                downWindowY = params.y
                true
            }
            MotionEvent.ACTION_MOVE -> {
                params.x = downWindowX + (event.rawX - downRawX).toInt()
                params.y = downWindowY + (event.rawY - downRawY).toInt()
                root?.let { windowManager.updateViewLayout(it, params) }
                true
            }
            MotionEvent.ACTION_UP -> {
                if (toggleOnClick) {
                    val moved = abs(event.rawX - downRawX) > dp(10) || abs(event.rawY - downRawY) > dp(10)
                    if (!moved) toggleExpanded()
                }
                true
            }
            else -> true
        }
    }

    private fun minimizePanel() {
        stopRefreshing()
        removePanel()
        expanded = false
        ball?.visibility = View.VISIBLE
        updateWindowSize()
    }

    private fun removePanel() {
        logContainer?.let { logs ->
            (logs.parent?.parent as? View)?.let { scroll ->
                root?.removeView(scroll)
            }
        }
        logContainer = null
        ball?.visibility = View.VISIBLE
    }

    private fun hideForCurrentBackground() {
        hiddenForCurrentBackground = true
        expanded = false
        stopRefreshing()
        removeWindow()
    }

    private fun updateWindowSize() {
        val rootView = root ?: return
        val params = windowParams ?: WindowManager.LayoutParams(
            dp(48),
            dp(56),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16)
            y = dp(220)
        }.also { windowParams = it }
        val dimensions = panelDimensions()
        params.width = if (expanded) dp(dimensions.width) else dp(48)
        params.height = if (expanded) dp(dimensions.height) else dp(48)
        runCatching { windowManager.updateViewLayout(rootView, params) }
    }

    private fun panelDimensions(): FloatingPanelDimensions {
        return when (panelSize) {
            0 -> FloatingPanelDimensions(280, 350, 264, 298)
            2 -> FloatingPanelDimensions(360, 520, 344, 468)
            else -> FloatingPanelDimensions(320, 410, 304, 358)
        }
    }

    private fun panelSizeName(): String = when (panelSize) {
        0 -> "小"
        2 -> "大"
        else -> "中"
    }

    private fun removeWindow() {
        root?.let { runCatching { windowManager.removeView(it) } }
        root = null
        ball = null
        logContainer = null
        windowParams = null
        expanded = false
    }

    private fun startRefreshing() {
        if (refreshJob?.isActive == true) return
        refreshJob = scope.launch {
            while (isActive) {
                loadLogs()
                delay(2_000)
            }
        }
    }

    private fun stopRefreshing() {
        refreshJob?.cancel()
        refreshJob = null
    }

    private suspend fun loadLogs() {
        val items = runCatching {
            withContext(Dispatchers.IO) {
                val batch = repository.load(30)
                (batch.dns.map(::dnsItem) + batch.http.map(::httpItem))
                    .sortedByDescending { it.timestamp }
                    .take(30)
            }
        }.getOrElse { emptyList() }
        if (logContainer != null) renderLogs(items)
    }

    private fun renderLoading() {
        logContainer?.let { logs ->
            logs.removeAllViews()
            logs.addView(TextView(appContext).apply {
        text = localizedText(appContext, "正在加载日志…")
                textSize = 13f
                setTextColor(0xffd7dce5.toInt())
                setPadding(dp(8))
            })
        }
    }

    private fun renderLogs(items: List<FloatingLogItem>) {
        logContainer?.let { logs ->
            logs.removeAllViews()
            if (items.isEmpty()) {
                logs.addView(TextView(appContext).apply {
        text = localizedText(appContext, "暂无请求日志")
                    textSize = 13f
                    setTextColor(0xffd7dce5.toInt())
                    setPadding(dp(8))
                })
                return
            }
            items.forEach { item ->
                logs.addView(LinearLayout(appContext).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(8), dp(7), dp(8), dp(7))
                    background = roundedBackground(0x332f3948, 8)
                    addView(TextView(appContext).apply {
                        text = item.title
                        textSize = 14f
                        maxLines = 2
                        setTextColor(Color.WHITE)
                    })
                    addView(TextView(appContext).apply {
                        text = "${timeFormatter.format(Date(item.timestamp))} · ${item.subtitle}"
                        textSize = 11f
                        setTextColor(0xffb9c1ce.toInt())
                        maxLines = 2
                    })
                    addView(TextView(appContext).apply {
                        text = item.status
                        textSize = 11f
                        setTextColor(0xff8fc5ff.toInt())
                    })
                }, LinearLayout.LayoutParams(-1, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    bottomMargin = dp(6)
                })
            }
        }
    }

    private fun dnsItem(log: DnsLogEntity): FloatingLogItem {
        val status = when (log.result) {
        LogResult.PASSED.value -> localizedText(appContext, "通过")
        LogResult.BLOCKED.value -> localizedText(appContext, "拦截")
        else -> localizedText(appContext, "错误")
        }
        return FloatingLogItem(
            log.timestamp,
            log.queryName,
            localizedText(appContext, "DNS · ${dnsType(log.queryType)}${if (log.cached) " · 命中缓存" else ""}"),
            status
        )
    }

    private fun httpItem(log: HttpRequestLogEntity): FloatingLogItem {
        val status = when (log.outcome) {
            "allowed" -> localizedText(appContext, "通过")
            "rewritten" -> localizedText(appContext, "重写")
            "blocked", "invalid" -> localizedText(appContext, "拦截")
            "decryption_failed", "unsupported_protocol", "resource_bypass" -> localizedText(appContext, "绕过")
            else -> localizedText(appContext, "错误")
        }
        return FloatingLogItem(
            log.timestamp,
            log.authority ?: localizedText(appContext, "未取得请求地址"),
            "HTTPS · ${log.protocol} · ${log.packageName}",
            status
        )
    }

    private fun dnsType(type: Int): String = when (type) {
        1 -> "A"
        28 -> "AAAA"
        5 -> "CNAME"
        15 -> "MX"
        16 -> "TXT"
        2 -> "NS"
        12 -> "PTR"
        255 -> "ANY"
        else -> "TYPE$type"
    }

    private fun roundedBackground(color: Int, radiusDp: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp).toFloat()
    }

    private fun dp(value: Int): Int = (value * density).toInt()
}
