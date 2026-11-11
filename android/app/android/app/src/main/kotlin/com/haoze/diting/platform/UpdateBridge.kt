package com.haoze.diting.platform

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/// Native download and install: Dart cannot share its private files or start the installer.
class UpdateBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/update"

        /// Must match the directory the cleanup logic deletes
        private const val UPDATE_DIR = "app-update"

        private const val CONNECT_TIMEOUT_MS = 20_000
        private const val READ_TIMEOUT_MS = 30_000
    }

    private val context: Activity get() = activity
    private var channel: MethodChannel? = null

    /// Only one download at a time, so two threads never write the same `.part`
    @Volatile
    private var downloading = false

    fun register(messenger: BinaryMessenger) {
        val methodChannel = MethodChannel(messenger, CHANNEL)
        channel = methodChannel
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "download" -> download(call, result)
            "install" -> install(call, result)
            else -> result.notImplemented()
        }
    }

    /// Downloads via a `.part` file, so an interruption leaves no truncated APK in place.
    private fun download(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val version = call.argument<String>("version")?.trim().orEmpty()
        if (url.isEmpty()) {
            result.error("invalid_url", "下载地址为空", null)
            return
        }
        if (downloading) {
            result.error("busy", "另一个更新正在下载", null)
            return
        }
        downloading = true
        val dir = File(context.filesDir, UPDATE_DIR).apply { mkdirs() }
        val safeVersion = version.ifEmpty { "latest" }.replace(Regex("[^0-9A-Za-z._-]"), "_")
        val finalFile = File(dir, "update-$safeVersion.apk")
        val tempFile = File(dir, ".update-$safeVersion.apk.part")
        finalFile.delete()
        tempFile.delete()

        Thread {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    instanceFollowRedirects = true
                    connectTimeout = CONNECT_TIMEOUT_MS
                    readTimeout = READ_TIMEOUT_MS
                    setRequestProperty("User-Agent", "DITING-Android")
                }
                val code = connection.responseCode
                if (code !in 200..299) {
                    failDownload(result, "下载更新失败：服务器返回 $code")
                    return@Thread
                }
                val total = connection.contentLengthLong.takeIf { it > 0L } ?: -1L
                var downloaded = 0L
                connection.inputStream.use { input ->
                    tempFile.outputStream().buffered().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var lastReported = 0L
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                            downloaded += read
                            // Throttle to ~256KB: a message per read would flood the main thread.
                            if (downloaded - lastReported >= 256 * 1024) {
                                lastReported = downloaded
                                emitProgress(downloaded, total)
                            }
                        }
                    }
                }
                if (!tempFile.renameTo(finalFile)) {
                    // Some devices fail a cross-directory rename; fall back to a copy.
                    tempFile.copyTo(finalFile, overwrite = true)
                    tempFile.delete()
                }
                emitProgress(downloaded, total)
                downloading = false
                activity.runOnUiThread { result.success(finalFile.absolutePath) }
            } catch (error: Exception) {
                runCatching { tempFile.delete() }
                failDownload(result, "下载更新失败：${error.message ?: error.javaClass.simpleName}")
            } finally {
                runCatching { connection?.disconnect() }
            }
        }.start()
    }

    private fun failDownload(result: MethodChannel.Result, message: String) {
        downloading = false
        activity.runOnUiThread { result.error("download_failed", message, null) }
    }

    private fun emitProgress(downloaded: Long, total: Long) {
        activity.runOnUiThread {
            channel?.invokeMethod(
                "progress",
                mapOf("downloaded" to downloaded, "total" to total),
            )
        }
    }

    /// Takes a path, not a URI: the FileProvider authority embeds the package name
    private fun install(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")?.trim().orEmpty()
        if (path.isEmpty()) {
            result.error("invalid_path", "安装包路径为空", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "安装包不存在，请重新下载", null)
            return
        }
        val ok = runCatching {
            val uri: Uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }.isSuccess
        if (ok) {
            result.success(true)
        } else {
            result.error("install_failed", "无法调起系统安装器", null)
        }
    }

    /// Unknown-sources entrypoint; the manifest declares the activity
    @Suppress("unused")
    private fun needsInstallPermission(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
}
