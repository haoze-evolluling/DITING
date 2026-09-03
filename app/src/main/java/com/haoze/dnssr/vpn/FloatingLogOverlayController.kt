package com.haoze.dnssr.vpn

import android.content.Context
import android.graphics.PixelFormat
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
import com.haoze.dnssr.data.AppDatabase
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
import java.text.SimpleDateFormat
import java.util.Locale
import kotlin.math.abs

/**
 * Owns the floating overlay window used to inspect recent DNS and HTTPS requests.
 * Manages overlay lifecycle, window manager parameters, touch dragging, and refresh loops.
 */
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
    // 上次实际渲染的日志列表：无新增日志时跳过整树重建
    private var lastRenderedLogs: List<FloatingLogItem>? = null
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
        panelSize = AppSettings.getFloatingLogPanelSize(appContext)
        syncVisibility()
        if (expanded && logContainer != null) {
            val panel = logContainer?.parent?.parent as? View
            panel?.let { root?.removeView(it) }
            logContainer = null
            lastRenderedLogs = null
            showPanel()
            scope.launch { loadLogs() }
        }
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
        if (!Settings.canDrawOverlays(appContext)) {
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
        val floatingBall = FloatingLogViewFactory.createBallView(appContext, density)
        container.addView(floatingBall, LinearLayout.LayoutParams(dp(48), dp(48)))
        root = container
        ball = floatingBall
        installDragHandler(floatingBall, toggleOnClick = true)
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

    private fun installDragHandler(view: View, toggleOnClick: Boolean) {
        view.setOnTouchListener { _, event ->
            handleDrag(event, toggleOnClick)
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
        val palette = FloatingLogTheme.getPalette(appContext)

        val components = FloatingLogViewFactory.createPanelView(
            context = appContext,
            density = density,
            palette = palette,
            dimensions = dimensions,
            currentSizeName = ::panelSizeName,
            onMinimize = ::minimizePanel,
            onCycleSize = ::cyclePanelSize,
            onClose = ::hideForCurrentBackground
        )

        container.addView(components.panel, LinearLayout.LayoutParams(dp(dimensions.width), dp(dimensions.height)))
        ball?.visibility = View.GONE
        installDragHandler(components.panel, toggleOnClick = false)
        logContainer = components.logContainer
        FloatingLogViewFactory.renderLoading(appContext, density, components.logContainer, palette)
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
        panel.requestLayout()
        updateWindowSize()
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
            (logs.parent?.parent as? View)?.let { panel ->
                root?.removeView(panel)
            }
        }
        logContainer = null
        lastRenderedLogs = null
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
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
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
            0 -> FloatingPanelDimensions(290, 360)
            2 -> FloatingPanelDimensions(360, 520)
            else -> FloatingPanelDimensions(330, 430)
        }
    }

    private fun panelSizeName(): String = when (panelSize) {
        0 -> localizedText(appContext, "小")
        2 -> localizedText(appContext, "大")
        else -> localizedText(appContext, "中")
    }

    private fun removeWindow() {
        root?.let { runCatching { windowManager.removeView(it) } }
        root = null
        ball = null
        logContainer = null
        windowParams = null
        // 窗口重建后面板重新从加载占位开始，必须连同渲染缓存一起清掉，
        // 否则日志无变化时 loadLogs 会跳过渲染、面板卡在"正在加载日志…"
        lastRenderedLogs = null
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
        val items = FloatingLogMapper.loadRecentLogs(repository, appContext, timeFormatter, limit = 30)
        val container = logContainer ?: return
        // 无新增日志：跳过 View 树整体重建，消除主线程无效布局/绘制与 View 分配
        if (items == lastRenderedLogs) return
        lastRenderedLogs = items
        val palette = FloatingLogTheme.getPalette(appContext)
        FloatingLogViewFactory.renderLogs(appContext, density, container, items, palette)
    }

    private fun dp(value: Int): Int = (value * density).toInt()
}
