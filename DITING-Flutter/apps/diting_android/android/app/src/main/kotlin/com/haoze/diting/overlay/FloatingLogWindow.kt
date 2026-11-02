package com.haoze.diting.overlay

import android.animation.ValueAnimator
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import com.haoze.diting.LegacyPrefsBridge
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.systemchannels.PlatformChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.roundToInt

/// One overlay window hosting a dedicated Flutter engine that runs `floatingLogMain`.
///
/// The window is resized to the ball or the panel, so touches outside it reach the app below.
/// Dragging is handled here on raw screen coordinates: done in Dart, the pointer's local position
/// would shift as the window moves under it. Flutter keeps taps, scrolls and buttons.
internal class FloatingLogWindow(context: Context) {
    private val context = context.applicationContext
    private val windowManager = this.context.getSystemService(WindowManager::class.java)
    private val prefs = this.context.getSharedPreferences(FloatingLogOverlay.UI_PREFS, Context.MODE_PRIVATE)
    private val density = this.context.resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(this.context).scaledTouchSlop

    private var engine: FlutterEngine? = null
    private var flutterView: FlutterView? = null
    private var root: DragFrame? = null
    private var channel: MethodChannel? = null
    private val params = WindowManager.LayoutParams(
        dp(BALL_DP),
        dp(BALL_DP),
        overlayType(),
        BASE_FLAGS or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN
    }

    private var expanded = false

    /// Height in dp of the panel strip that drags the window; zero in ball mode means "all of it".
    private var dragStripDp = 0

    /// Side edge the open panel rests against: -1 left, 1 right.
    private var panelSide = 1
    private var ballX = 0
    private var ballY = 0
    private var snapAnimator: ValueAnimator? = null
    private var receiverRegistered = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            val lifecycle = engine?.lifecycleChannel ?: return
            // Paused engines draw no frames and Dart stops its polling timers.
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> lifecycle.appIsPaused()
                Intent.ACTION_USER_PRESENT, Intent.ACTION_SCREEN_ON -> lifecycle.appIsResumed()
            }
        }
    }

    fun show(): Boolean = runCatching {
        val flutterEngine = FlutterEngine(context)
        engine = flutterEngine
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Dart reads the same SharedPreferences containers as the app (theme, language, sizes).
        LegacyPrefsBridge(context).register(messenger)
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(::onMethodCall) }
        flutterEngine.platformChannel.setPlatformMessageHandler(platformHandler)

        val textureView = FlutterTextureView(context).apply { isOpaque = false }
        val view = FlutterView(context, textureView)
        flutterView = view
        val frame = DragFrame(context).apply { addView(view) }
        root = frame

        restorePosition()
        windowManager.addView(frame, params)
        view.attachToFlutterEngine(flutterEngine)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                ENTRYPOINT,
            ),
        )
        flutterEngine.lifecycleChannel.appIsResumed()
        registerScreenReceiver()
        true
    }.getOrElse {
        Log.e(TAG, "unable to show floating log window", it)
        destroy()
        false
    }

    fun destroy() {
        snapAnimator?.cancel()
        unregisterScreenReceiver()
        savePosition()
        root?.let { runCatching { windowManager.removeView(it) } }
        root = null
        runCatching { flutterView?.detachFromFlutterEngine() }
        flutterView = null
        channel?.setMethodCallHandler(null)
        channel = null
        runCatching { engine?.destroy() }
        engine = null
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setExpanded" -> {
                setExpanded(
                    expand = call.argument<Boolean>("expanded") == true,
                    widthDp = call.argument<Int>("width") ?: 0,
                    heightDp = call.argument<Int>("height") ?: 0,
                    dragStripDp = call.argument<Int>("dragStrip") ?: 0,
                )
                result.success(null)
            }
            "setFocusable" -> {
                setFocusable(call.argument<Boolean>("value") == true)
                result.success(null)
            }
            "openApp" -> {
                openApp()
                result.success(null)
            }
            "dismiss" -> {
                result.success(null)
                FloatingLogOverlay.dismissForBackground()
            }
            "opacity" -> result.success(prefs.getFloat(KEY_OPACITY, 1f).toDouble())
            else -> result.notImplemented()
        }
    }

    /// Resizes the window to the panel or the ball. Dart draws an empty frame first, so the stale
    /// frame the texture view stretches over the new size shows nothing. The panel opens against
    /// the screen edge the ball rests on.
    private fun setExpanded(expand: Boolean, widthDp: Int, heightDp: Int, dragStripDp: Int) {
        snapAnimator?.cancel()
        val (screenW, screenH) = screenSize()
        if (expand && !expanded) {
            ballX = params.x
            ballY = params.y
        }
        val opening = expand && !expanded
        expanded = expand
        this.dragStripDp = dragStripDp
        if (expand) {
            val oldRight = params.x + params.width
            params.width = dp(widthDp).coerceAtMost(screenW - 2 * dp(EDGE_DP))
            params.height = dp(heightDp).coerceAtMost(screenH - 2 * dp(EDGE_DP))
            if (opening) {
                panelSide = if (ballX + dp(BALL_DP) / 2 < screenW / 2) -1 else 1
                params.x = if (panelSide < 0) dp(EDGE_DP) else screenW - params.width - dp(EDGE_DP)
                params.y = ballY
            } else if (panelSide > 0) {
                // A resize keeps the right edge where it was.
                params.x = oldRight - params.width
            }
            clampInto(screenW, screenH)
            root?.alpha = prefs.getFloat(KEY_OPACITY, 1f).coerceIn(0.3f, 1f)
        } else {
            setFocusable(false)
            params.width = dp(BALL_DP)
            params.height = dp(BALL_DP)
            params.x = ballX
            params.y = ballY
            clampInto(screenW, screenH)
            root?.alpha = 1f
        }
        update()
    }

    /// Only a focused search field needs the keyboard; otherwise the window must not steal focus
    /// (or the back key) from the app underneath.
    private fun setFocusable(value: Boolean) {
        val flags = if (value) BASE_FLAGS else BASE_FLAGS or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        if (params.flags == flags) return
        params.flags = flags
        update()
    }

    private fun openApp() {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        runCatching { context.startActivity(intent) }
            .onFailure { Log.w(TAG, "unable to open the app", it) }
    }

    private fun onDragEnd() {
        val (screenW, screenH) = screenSize()
        clampInto(screenW, screenH)
        if (expanded) {
            update()
            return
        }
        // The ball rests against the nearer side edge, like a system bubble.
        val target = if (params.x + params.width / 2 < screenW / 2) {
            dp(EDGE_DP)
        } else {
            screenW - params.width - dp(EDGE_DP)
        }
        snapAnimator = ValueAnimator.ofInt(params.x, target).apply {
            duration = 220
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                params.x = it.animatedValue as Int
                update()
            }
            start()
        }
        savePosition()
    }

    private fun clampInto(screenW: Int, screenH: Int) {
        params.x = params.x.coerceIn(0, (screenW - params.width).coerceAtLeast(0))
        params.y = params.y.coerceIn(0, (screenH - params.height).coerceAtLeast(0))
    }

    private fun restorePosition() {
        val (screenW, screenH) = screenSize()
        params.x = prefs.getInt(KEY_X, screenW - dp(BALL_DP) - dp(EDGE_DP))
        params.y = prefs.getInt(KEY_Y, (screenH * 0.3f).toInt())
        clampInto(screenW, screenH)
        ballX = params.x
        ballY = params.y
    }

    private fun savePosition() {
        val x = if (expanded) ballX else params.x
        val y = if (expanded) ballY else params.y
        prefs.edit().putInt(KEY_X, x).putInt(KEY_Y, y).apply()
    }

    private fun update() {
        val view = root ?: return
        runCatching { windowManager.updateViewLayout(view, params) }
    }

    private fun screenSize(): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            return bounds.width() to bounds.height()
        }
        val metrics = context.resources.displayMetrics
        return metrics.widthPixels to metrics.heightPixels
    }

    private fun registerScreenReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF).apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        receiverRegistered = runCatching { context.registerReceiver(screenReceiver, filter) }.isSuccess
    }

    private fun unregisterScreenReceiver() {
        if (!receiverRegistered) return
        receiverRegistered = false
        runCatching { context.unregisterReceiver(screenReceiver) }
    }

    private fun dp(value: Int): Int = (value * density).roundToInt()

    /// Intercepts a drag before Flutter sees it: anywhere on the ball, or on the panel's header
    /// strip. A press that stays within the touch slop is left to Flutter as a tap.
    private inner class DragFrame(context: Context) : FrameLayout(context) {
        private var downRawX = 0f
        private var downRawY = 0f
        private var downX = 0
        private var downY = 0
        private var tracking = false
        private var dragging = false

        override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    snapAnimator?.cancel()
                    downRawX = event.rawX
                    downRawY = event.rawY
                    downX = params.x
                    downY = params.y
                    tracking = !expanded || event.y <= dp(dragStripDp)
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> if (tracking && !dragging &&
                    (abs(event.rawX - downRawX) > touchSlop || abs(event.rawY - downRawY) > touchSlop)
                ) {
                    dragging = true
                    return true
                }
            }
            return false
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (!dragging) return super.onTouchEvent(event)
            when (event.actionMasked) {
                MotionEvent.ACTION_MOVE -> {
                    params.x = downX + (event.rawX - downRawX).toInt()
                    params.y = downY + (event.rawY - downRawY).toInt()
                    update()
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    dragging = false
                    onDragEnd()
                }
            }
            return true
        }

        /// Back only arrives while the search field holds focus; Dart clears it.
        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                if (event.action == KeyEvent.ACTION_UP) channel?.invokeMethod("back", null)
                return true
            }
            return super.dispatchKeyEvent(event)
        }
    }

    /// No Activity, so the stock PlatformPlugin is absent; Dart still needs clipboard and haptics.
    private val platformHandler = object : PlatformChannel.PlatformMessageHandler {
        private val clipboard get() = context.getSystemService(ClipboardManager::class.java)

        override fun playSystemSound(soundType: PlatformChannel.SoundType) = Unit
        override fun vibrateHapticFeedback(feedbackType: PlatformChannel.HapticFeedbackType) {
            root?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        }
        override fun setPreferredOrientations(androidOrientation: Int) = Unit
        override fun setApplicationSwitcherDescription(description: PlatformChannel.AppSwitcherDescription) = Unit
        override fun showSystemOverlays(overlays: MutableList<PlatformChannel.SystemUiOverlay>) = Unit
        override fun showSystemUiMode(mode: PlatformChannel.SystemUiMode) = Unit
        override fun setSystemUiChangeListener() = Unit
        override fun restoreSystemUiOverlays() = Unit
        override fun setSystemUiOverlayStyle(systemUiOverlayStyle: PlatformChannel.SystemChromeStyle) = Unit
        override fun popSystemNavigator() = Unit
        override fun getClipboardData(format: PlatformChannel.ClipboardContentFormat?): CharSequence? =
            runCatching { clipboard?.primaryClip?.getItemAt(0)?.coerceToText(context) }.getOrNull()
        override fun setClipboardData(text: String) {
            clipboard?.setPrimaryClip(ClipData.newPlainText("text", text))
        }
        override fun clipboardHasStrings(): Boolean = clipboard?.hasPrimaryClip() == true
        override fun share(text: String) = Unit
    }

    private companion object {
        const val TAG = "FloatingLogWindow"
        const val CHANNEL = "com.haoze.diting/floating_log_window"
        const val ENTRYPOINT = "floatingLogMain"
        const val KEY_X = "floating_log_x"
        const val KEY_Y = "floating_log_y"
        const val KEY_OPACITY = "floating_log_opacity"
        const val BALL_DP = 56
        const val EDGE_DP = 4
        const val BASE_FLAGS = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN

        fun overlayType(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }
}
