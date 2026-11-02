package com.haoze.diting.apps

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import com.haoze.diting.platform.ChannelResults
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.Executors

/// Read-only installed-app inventory; selection state lives in SharedPreferences
class AppsBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/apps"

        /// Enumeration takes hundreds of ms, so one serial worker off the platform thread
        private val worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "diting-apps").apply { isDaemon = true }
        }

        /// Launcher icons are drawn at 48dp at mdpi, `* 4` covers a 4x density screen
        private const val DEFAULT_ICON_SIZE = 192

        /// Hard cap per request: a runaway caller would otherwise encode thousands of bitmaps
        private const val MAX_ICON_PACKAGES = 400

        /// Bounded LRU: encoded PNGs are stable for the process lifetime, and 600 entries cover
        /// a large device without letting the cache grow without limit
        private const val MAX_CACHED_ICONS = 600

        private val iconCache = object : LinkedHashMap<String, ByteArray>(64, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ByteArray>) =
                size > MAX_CACHED_ICONS
        }

        /// Bump to drop every icon on disk when the rendering changes
        private const val DISK_CACHE_VERSION = 1
    }

    /// Rendered icons kept across restarts, so a cold start reads files instead of drawing and
    /// encoding every icon again. Files are named `<package>@<lastUpdateTime>.png`: an app update
    /// changes the name, which is what invalidates its entry. Lives in `cacheDir`, so the system
    /// may clear it under storage pressure.
    private val diskCacheRoot by lazy {
        File(context.cacheDir, "app_icons/v$DISK_CACHE_VERSION")
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listInstalled" -> worker.execute { listInstalledChecked().ship(result) }
            "resolveUids" -> {
                val packages = call.argument<List<String>>("packages").orEmpty()
                worker.execute { runCatching { resolveUids(packages) }.ship(result) }
            }
            "loadIcons" -> {
                val packages = call.argument<List<String>>("packages").orEmpty()
                val size = call.argument<Int>("size") ?: DEFAULT_ICON_SIZE
                worker.execute {
                    runCatching { loadIcons(packages, size) }.ship(result)
                }
            }
            // Cheap, and validation paths want it synchronously.
            "isSelf" -> result.success(isSelf(call.argument<String>("packageName").orEmpty()))
            else -> result.notImplemented()
        }
    }

    /// An empty list means a denied runtime permission (MIUI/ColorOS/EMUI), not "no apps"
    private fun listInstalledChecked(): Result<List<Map<String, Any?>>> = runCatching {
        val apps = listInstalled()
        if (apps.isEmpty()) {
            throw IllegalStateException("未能读取已安装应用列表，请在系统权限中允许“读取应用列表”")
        }
        apps
    }

    
    private fun listInstalled(): List<Map<String, Any?>> {
        val packageManager = context.packageManager
        @Suppress("DEPRECATION")
        val installed = packageManager.getInstalledApplications(0)
        val self = context.packageName
        return installed.asSequence()
            .filter { it.packageName != self }
            .map { info ->
                val label = runCatching { info.loadLabel(packageManager).toString() }
                    .getOrNull()?.takeIf { it.isNotBlank() } ?: info.packageName
                mapOf(
                    "packageName" to info.packageName,
                    "label" to label,
                    "isSystem" to isSystemApp(info),
                    "uid" to uidOf(info.packageName),
                )
            }
            .sortedWith(
                compareBy<Map<String, Any?>> {
                    (it["label"] as? String).orEmpty().lowercase(Locale.ROOT)
                }.thenBy { it["packageName"] as? String },
            )
            .toList()
    }

    /// Package name -> UID, omitting uninstalled ones so the engine never sees an invalid UID
    private fun resolveUids(packages: List<String>): Map<String, Int> {
        if (packages.isEmpty()) return emptyMap()
        val output = HashMap<String, Int>(packages.size)
        for (packageName in packages.distinct()) {
            if (packageName.isBlank()) continue
            val uid = uidOf(packageName)
            if (uid >= 0) output[packageName] = uid
        }
        return output
    }

    private fun isSelf(packageName: String): Boolean =
        packageName.isNotEmpty() && packageName == context.packageName

    /// Package name -> PNG bytes of the launcher icon, drawn at [size] px. Encoding happens
    /// off the platform thread; repeats are served from [iconCache] and, after a restart, from
    /// [diskCacheRoot], so only new or updated apps are drawn again.
    private fun loadIcons(packages: List<String>, size: Int): Map<String, ByteArray> {
        if (packages.isEmpty()) return emptyMap()
        val side = size.coerceIn(48, 512)
        val dir = File(diskCacheRoot, side.toString())
        val output = HashMap<String, ByteArray>(packages.size)
        for (packageName in packages.distinct().take(MAX_ICON_PACKAGES)) {
            if (packageName.isBlank() || packageName == context.packageName) continue
            val stamp = lastUpdateOf(packageName) ?: continue
            val key = "$side:$packageName@$stamp"
            val cached = iconCache.get(key)
            if (cached != null) {
                output[packageName] = cached
                continue
            }
            val file = File(dir, "$packageName@$stamp.png")
            val bytes = readCached(file) ?: renderIcon(packageName, side)?.also {
                writeCached(dir, packageName, file, it)
            } ?: continue
            iconCache.put(key, bytes)
            output[packageName] = bytes
        }
        return output
    }

    /// Null when the package is gone, which also skips drawing it
    private fun lastUpdateOf(packageName: String): Long? = runCatching {
        context.packageManager.getPackageInfo(packageName, 0).lastUpdateTime
    }.getOrNull()

    private fun readCached(file: File): ByteArray? = runCatching {
        if (file.isFile && file.length() > 0) file.readBytes() else null
    }.getOrNull()

    /// Best effort: a failed write only costs a redraw next time. Older entries of the package
    /// are removed so updates do not pile up files. The temp file + rename keeps a crash
    /// mid-write from leaving a truncated PNG behind.
    private fun writeCached(dir: File, packageName: String, file: File, bytes: ByteArray) {
        runCatching {
            if (!dir.isDirectory && !dir.mkdirs()) return
            dir.listFiles { _, name -> name.startsWith("$packageName@") }
                ?.forEach { it.delete() }
            val temp = File(dir, "${file.name}.tmp")
            temp.writeBytes(bytes)
            if (!temp.renameTo(file)) temp.delete()
        }
    }

    private fun renderIcon(packageName: String, side: Int): ByteArray? = runCatching {
        val drawable = context.packageManager.getApplicationIcon(packageName)
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).let { canvas ->
            drawable.setBounds(0, 0, side, side)
            drawable.draw(canvas)
        }
        ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            bitmap.recycle()
            stream.toByteArray()
        }
    }.getOrNull()

    /// -1 when the package is gone or the platform refuses to answer
    private fun uidOf(packageName: String): Int = runCatching {
        context.packageManager.getPackageUid(packageName, 0)
    }.getOrDefault(-1)

    private fun isSystemApp(info: ApplicationInfo): Boolean =
        (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
}

/// Result may only be touched on the platform thread

private fun <T> Result<T>.ship(result: MethodChannel.Result) =
    ChannelResults.ship(result, this, "apps_unavailable")
