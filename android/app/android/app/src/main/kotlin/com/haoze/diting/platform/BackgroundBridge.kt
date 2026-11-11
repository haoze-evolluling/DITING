package com.haoze.diting.platform

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/// Native half of the custom background: picking a `content://` image and caching it locally.
/// Picking needs an Activity round trip; BitmapFactory downsamples without OOM and converts
/// HEIC, which Flutter cannot decode. Caches are named by URI hash.
class BackgroundBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/background"

        /// Distinct from the VPN and document-picker request codes
        private const val REQUEST_PICK_IMAGE = 0x5703

        private const val CACHE_DIR = "background"

        /// Longest decoded edge; larger keeps more detail at a memory cost
        private const val MAX_DIMENSION = 2048
    }

    private val context: Activity get() = activity
    private var pendingPickResult: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "resolve" -> resolve(call, result)
            "release" -> release(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("picker_busy", "另一个图片选择器仍在打开", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        runCatching { activity.startActivityForResult(intent, REQUEST_PICK_IMAGE) }
            .onFailure {
                pendingPickResult = null
                result.error("picker_failed", it.message, null)
            }
    }

    /// Called from `MainActivity.onActivityResult`; true when the request was ours
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_IMAGE) return false
        val pending = pendingPickResult ?: return true
        pendingPickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(mapOf("cancelled" to true))
            return true
        }
        Thread {
            runCatching {
                // Needed to re-read this content:// image when the cache is rebuilt.
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            val path = runCatching { cacheImage(uri) }.getOrNull()
            activity.runOnUiThread {
                if (path == null) {
                    pending.error("decode_failed", "无法读取所选图片", null)
                } else {
                    pending.success(
                        mapOf(
                            "cancelled" to false,
                            "uri" to uri.toString(),
                            "path" to path,
                        ),
                    )
                }
            }
        }.start()
        return true
    }

    /// Local cache path for a URI, decoding it first when missing
    private fun resolve(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")?.trim().orEmpty()
        if (uri.isEmpty()) {
            result.success(null)
            return
        }
        val cached = cacheFileFor(uri)
        if (cached.exists() && cached.length() > 0) {
            result.success(cached.absolutePath)
            return
        }
        Thread {
            val path = runCatching { cacheImage(Uri.parse(uri)) }.getOrNull()
            activity.runOnUiThread { result.success(path) }
        }.start()
    }

    private fun release(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")?.trim().orEmpty()
        if (uri.isEmpty()) {
            result.success(true)
            return
        }
        result.success(runCatching { cacheFileFor(uri).delete() }.getOrDefault(false))
    }

    private fun cacheDir(): File = File(context.filesDir, CACHE_DIR).apply { mkdirs() }

    private fun cacheFileFor(uri: String): File =
        File(cacheDir(), "bg_" + sha1(uri).take(20) + ".png")

    private fun sha1(value: String): String {
        val bytes = MessageDigest.getInstance("SHA-1").digest(value.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /// Downsampled PNG: the wallpaper fills one screen, so more pixels only waste memory.
    private fun cacheImage(uri: Uri): String? {
        val resolver = activity.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, MAX_DIMENSION)
        }
        val bitmap = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, options)
        } ?: return null

        val target = cacheFileFor(uri.toString())
        val temp = File(target.parentFile, target.name + ".part")
        val ok = runCatching {
            temp.outputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
        }.isSuccess
        bitmap.recycle()
        if (!ok) {
            temp.delete()
            return null
        }
        if (target.exists()) target.delete()
        return if (temp.renameTo(target)) target.absolutePath else null
    }

    private fun sampleSize(width: Int, height: Int, max: Int): Int {
        var size = 1
        while (width / (size * 2) >= max && height / (size * 2) >= max) {
            size *= 2
        }
        return size
    }
}
