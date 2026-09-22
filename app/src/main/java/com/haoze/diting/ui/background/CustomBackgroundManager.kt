package com.haoze.diting.ui.background

import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.haoze.diting.R
import com.haoze.diting.ui.AppThemeMode
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.max

/**
 * 全局自定义背景管理器。
 * 提供多级内存缓存（Bitmap / Compose ImageBitmap / 缩略图 LRU）、
 * 本地私有磁盘预采样持久化文件、基于屏幕尺寸的智能降采样解码、
 * Window 窗口背景预加载与即时同步，彻底消除二级页面及冷启动首页的
 * 背景重复 IO 解码与白/黑屏闪烁。
 */
object CustomBackgroundManager {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var activeUri: String? = null

    @Volatile
    private var activeBitmap: Bitmap? = null

    @Volatile
    private var activeImageBitmap: ImageBitmap? = null

    private val _backgroundUpdateFlow = MutableStateFlow(0L)
    val backgroundUpdateFlow: StateFlow<Long> = _backgroundUpdateFlow.asStateFlow()

    // 缩略图 LRU 缓存，最多缓存 12 张缩略图
    private val thumbnailCache = object : LruCache<String, ImageBitmap>(12) {}

    private fun getLocalCacheFile(context: Context): File {
        return File(context.filesDir, "custom_background_cached.png")
    }

    private fun getLocalUriMarkerFile(context: Context): File {
        return File(context.filesDir, "custom_background_uri.txt")
    }

    /**
     * 判断当前是否处于深色模式
     */
    fun isDarkThemeActive(context: Context): Boolean {
        val themeMode = AppearanceSettingsStore.getAppThemeMode(context)
        val isSystemDark = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        return when (themeMode) {
            AppThemeMode.SYSTEM -> isSystemDark
            AppThemeMode.LIGHT -> false
            AppThemeMode.DARK -> true
        }
    }

    /**
     * 同步获取当前缓存的 Compose ImageBitmap。
     * 若 URI 与已缓存一致且 Bitmap 未被回收，可在首帧 0ms 内直接返回。
     */
    fun getCachedImageBitmap(uri: String?): ImageBitmap? {
        if (uri.isNullOrBlank()) return null
        val bmp = activeBitmap
        if (activeUri == uri && bmp != null && !bmp.isRecycled) {
            return activeImageBitmap
        }
        return null
    }

    /**
     * 同步获取当前缓存的系统 Bitmap。
     */
    fun getCachedBitmap(uri: String?): Bitmap? {
        if (uri.isNullOrBlank()) return null
        val bmp = activeBitmap
        if (activeUri == uri && bmp != null && !bmp.isRecycled) {
            return bmp
        }
        return null
    }

    /**
     * 同步确保当前激活的背景图已加载至内存（主要用于冷启动，避免主页首帧白屏闪烁）。
     * 优先直接读取本地预采样的本地私有文件（耗时仅数毫秒，无 Binder IPC）。
     */
    @Synchronized
    fun ensureLoaded(context: Context) {
        if (!AppearanceSettingsStore.isCustomBackgroundEnabled(context)) return
        val uri = AppearanceSettingsStore.getCustomBackgroundUri(context) ?: return
        val currentBmp = activeBitmap
        if (activeUri == uri && currentBmp != null && !currentBmp.isRecycled) return

        val appContext = context.applicationContext
        val cacheFile = getLocalCacheFile(appContext)
        val uriMarkerFile = getLocalUriMarkerFile(appContext)

        if (cacheFile.exists() && uriMarkerFile.exists()) {
            val savedUri = runCatching { uriMarkerFile.readText() }.getOrNull()
            if (savedUri == uri) {
                val cachedBmp = runCatching {
                    BitmapFactory.decodeFile(cacheFile.absolutePath)
                }.getOrNull()
                if (cachedBmp != null) {
                    activeUri = uri
                    activeBitmap = cachedBmp
                    activeImageBitmap = cachedBmp.asImageBitmap()
                    _backgroundUpdateFlow.value = System.currentTimeMillis()
                    return
                }
            }
        }

        // 本地缓存不存在或失效，从原 URI 执行智能降采样解码
        val decoded = decodeSampledBitmapFromUri(appContext, Uri.parse(uri))
        if (decoded != null) {
            activeUri = uri
            activeBitmap = decoded
            activeImageBitmap = decoded.asImageBitmap()
            _backgroundUpdateFlow.value = System.currentTimeMillis()
            saveToLocalCacheAsync(appContext, uri, decoded)
        }
    }

    /**
     * 预加载当前配置的自定义背景图（例如在 Application.onCreate 时调用）。
     */
    fun preload(context: Context) {
        ensureLoaded(context)
    }

    /**
     * 异步加载背景图，如果已在缓存中则直接回调，否则在 IO 线程降采样解码后缓存并通知。
     */
    fun loadBackground(
        context: Context,
        uri: String?,
        onLoaded: ((ImageBitmap?) -> Unit)? = null
    ) {
        if (uri.isNullOrBlank()) {
            clearActiveCache(context)
            onLoaded?.invoke(null)
            return
        }

        val cached = getCachedImageBitmap(uri)
        if (cached != null) {
            onLoaded?.invoke(cached)
            return
        }

        val appContext = context.applicationContext
        scope.launch {
            val result = loadBackgroundInternal(appContext, uri)
            withContext(Dispatchers.Main) {
                onLoaded?.invoke(result)
            }
        }
    }

    /**
     * 内部解码与缓存方法
     */
    @Synchronized
    private fun loadBackgroundInternal(context: Context, uri: String): ImageBitmap? {
        val currentBmp = activeBitmap
        if (activeUri == uri && currentBmp != null && !currentBmp.isRecycled) {
            return activeImageBitmap
        }

        val cacheFile = getLocalCacheFile(context)
        val uriMarkerFile = getLocalUriMarkerFile(context)

        if (cacheFile.exists() && uriMarkerFile.exists()) {
            val savedUri = runCatching { uriMarkerFile.readText() }.getOrNull()
            if (savedUri == uri) {
                val cachedBmp = runCatching {
                    BitmapFactory.decodeFile(cacheFile.absolutePath)
                }.getOrNull()
                if (cachedBmp != null) {
                    activeUri = uri
                    activeBitmap = cachedBmp
                    val imgBmp = cachedBmp.asImageBitmap()
                    activeImageBitmap = imgBmp
                    _backgroundUpdateFlow.value = System.currentTimeMillis()
                    return imgBmp
                }
            }
        }

        val decoded = decodeSampledBitmapFromUri(context, Uri.parse(uri))
        if (decoded != null) {
            activeUri = uri
            activeBitmap = decoded
            val imgBmp = decoded.asImageBitmap()
            activeImageBitmap = imgBmp
            _backgroundUpdateFlow.value = System.currentTimeMillis()
            saveToLocalCacheAsync(context, uri, decoded)
            return imgBmp
        }
        return null
    }

    private fun saveToLocalCacheAsync(context: Context, uri: String, bitmap: Bitmap) {
        val appContext = context.applicationContext
        scope.launch {
            runCatching {
                val cacheFile = getLocalCacheFile(appContext)
                val tempFile = File(appContext.filesDir, "custom_background_cached.tmp")
                tempFile.outputStream().use { fos ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, fos)
                }
                if (tempFile.renameTo(cacheFile) || (cacheFile.delete() && tempFile.renameTo(cacheFile))) {
                    getLocalUriMarkerFile(appContext).writeText(uri)
                }
            }
        }
    }

    /**
     * 清理当前激活的背景缓存及本地持久化文件
     */
    fun clearActiveCache(context: Context? = null) {
        activeUri = null
        activeBitmap = null
        activeImageBitmap = null
        _backgroundUpdateFlow.value = System.currentTimeMillis()

        context?.let { ctx ->
            val appContext = ctx.applicationContext
            scope.launch {
                runCatching {
                    getLocalCacheFile(appContext).delete()
                    getLocalUriMarkerFile(appContext).delete()
                }
            }
        }
    }

    /**
     * 当自定义背景设置被修改时调用，同步刷新缓存和所有状态
     */
    fun onBackgroundSettingsChanged(context: Context, enabled: Boolean, uri: String?) {
        if (enabled && !uri.isNullOrBlank()) {
            ensureLoaded(context)
        } else {
            clearActiveCache(context)
        }
    }

    /**
     * 为 Activity 窗口设置即时背景 Drawable。
     * 当开启自定义背景且有缓存时，将窗口背景设为 CustomBackgroundDrawable，
     * 消除 Activity 启动动画过程中的默认白底/黑底闪烁。
     */
    fun applyWindowBackground(activity: Activity) {
        val enabled = AppearanceSettingsStore.isCustomBackgroundEnabled(activity)
        val uri = AppearanceSettingsStore.getCustomBackgroundUri(activity)
        val isDark = isDarkThemeActive(activity)

        if (enabled && !uri.isNullOrBlank()) {
            var bmp = getCachedBitmap(uri)
            if (bmp == null) {
                ensureLoaded(activity)
                bmp = getCachedBitmap(uri)
            }
            if (bmp != null) {
                activity.window.setBackgroundDrawable(CustomBackgroundDrawable(bmp, isDark))
            } else {
                activity.window.setBackgroundDrawableResource(R.color.diting_window_background)
            }
        } else {
            activity.window.setBackgroundDrawableResource(R.color.diting_window_background)
        }
    }

    /**
     * 获取或解码壁纸缩略图（供设置列表使用）
     */
    suspend fun getOrLoadThumbnail(context: Context, uri: String): ImageBitmap? {
        thumbnailCache.get(uri)?.let { return it }

        val active = getCachedImageBitmap(uri)
        if (active != null) {
            thumbnailCache.put(uri, active)
            return active
        }

        return withContext(Dispatchers.IO) {
            runCatching {
                val targetDim = 480
                val decoded = decodeSampledBitmapFromUri(context, Uri.parse(uri), targetDim, targetDim)
                decoded?.asImageBitmap()?.also {
                    thumbnailCache.put(uri, it)
                }
            }.getOrNull()
        }
    }

    /**
     * 响应系统低内存通知
     */
    fun onTrimMemory(level: Int) {
        @Suppress("DEPRECATION")
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            thumbnailCache.evictAll()
        }
    }

    /**
     * 智能降采样解码：根据目标宽高计算最佳 inSampleSize，避免大图引发 OOM 和耗时
     */
    private fun decodeSampledBitmapFromUri(
        context: Context,
        uri: Uri,
        reqWidth: Int = 0,
        reqHeight: Int = 0
    ): Bitmap? {
        return runCatching {
            val dm = context.resources.displayMetrics
            val maxScreenDim = max(dm.widthPixels, dm.heightPixels).coerceAtLeast(1080)
            val targetW = if (reqWidth > 0) reqWidth else maxScreenDim
            val targetH = if (reqHeight > 0) reqHeight else maxScreenDim

            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            context.contentResolver.openInputStream(uri).use { stream ->
                if (stream == null) return null
                BitmapFactory.decodeStream(stream, null, options)
            }

            options.inSampleSize = calculateInSampleSize(options, targetW, targetH)
            options.inJustDecodeBounds = false
            options.inPreferredConfig = Bitmap.Config.ARGB_8888

            context.contentResolver.openInputStream(uri).use { stream ->
                if (stream == null) return null
                BitmapFactory.decodeStream(stream, null, options)
            }
        }.getOrNull()
    }

    private fun calculateInSampleSize(
        options: BitmapFactory.Options,
        reqWidth: Int,
        reqHeight: Int
    ): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }
}

/**
 * 专用于 Activity 窗口背景的 Drawable。
 * 实现与 Compose `ContentScale.Crop` 100% 像素级对齐的居中裁剪矩阵算法，
 * 并叠加与 Compose 一致的深色/浅色遮罩层（深色 0.34f，浅色 0.16f）。
 */
class CustomBackgroundDrawable(
    private val bitmap: Bitmap,
    private val isDarkTheme: Boolean
) : Drawable() {

    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val overlayPaint = Paint().apply {
        // 深色 0.34f -> 0x57000000; 浅色 0.16f -> 0x29000000
        color = if (isDarkTheme) 0x57000000 else 0x29000000
    }
    private val drawMatrix = Matrix()

    override fun draw(canvas: Canvas) {
        val b = bounds
        if (b.width() <= 0 || b.height() <= 0 || bitmap.isRecycled) return

        val bWidth = bitmap.width.toFloat()
        val bHeight = bitmap.height.toFloat()
        val vWidth = b.width().toFloat()
        val vHeight = b.height().toFloat()

        val scale = max(vWidth / bWidth, vHeight / bHeight)
        val dx = (vWidth - bWidth * scale) * 0.5f
        val dy = (vHeight - bHeight * scale) * 0.5f

        drawMatrix.setScale(scale, scale)
        drawMatrix.postTranslate(b.left + dx, b.top + dy)

        canvas.drawBitmap(bitmap, drawMatrix, bitmapPaint)
        canvas.drawRect(b, overlayPaint)
    }

    override fun setAlpha(alpha: Int) {
        bitmapPaint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        bitmapPaint.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.OPAQUE
}
