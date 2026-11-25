package com.haoze.diting.platform

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.OutputStream
import java.security.MessageDigest

class PlatformBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/platform"

        private const val REQUEST_EXPORT_DOCUMENT = 0x5701
        private const val REQUEST_IMPORT_DOCUMENT = 0x5702

        private const val REQUEST_PICK_TEXT_FILE = 0x5703

        private const val REQUEST_PICK_FONT_FILE = 0x5704

        private const val REQUEST_IGNORE_BATTERY = 0x5706

        private const val FONT_DIR = "fonts"

        private const val MIN_FONT_BYTES = 1024

        private const val EXPORT_DIR = "exports"

        private const val HIDE_FROM_RECENTS_KEY = "hide_from_recents_enabled"

        private const val UI_PREFS = "dns_vpn_prefs"
    }

    private val context: Context get() = activity

    private val storage = AppStorageCleaner(activity)

    private val ruleCache = RuleFileCache(activity)

    private val wifi = WifiSsidReader(activity)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    fun reapplyRecentsPrivacy() {
        runCatching {
            val hide = context
                .getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
                .getBoolean(HIDE_FROM_RECENTS_KEY, false)
            applyRecentsPrivacyInternal(hide)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "applyRecentsPrivacy" -> applyRecentsPrivacy(call, result)
            "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
            "requestIgnoreBatteryOptimizations" -> requestIgnoreBatteryOptimizations(result)
            "crashLogCount" -> result.success(storage.crashLogCount())
            "readCrashLogs" -> result.success(storage.readCrashLogs())
            "clearCrashLogs" -> result.success(storage.clearCrashLogs())
            "exportText" -> exportText(call, result)
            "memoryInfo" -> result.success(memoryInfo())
            "currentSsid" -> result.success(wifi.currentSsid())
            "clearUpdateCache" -> result.success(storage.clearUpdateCache(call.argument<Boolean>("includeTemp") ?: true))
            "clearCustomBackgroundCache" -> result.success(storage.clearCustomBackgroundCache())
            "beginExportDocument" -> beginExportDocument(call, result)
            "appendExportChunk" -> appendExportChunk(call, result)
            "endExportDocument" -> endExportDocument(call, result)
            "abortExportDocument" -> abortExportDocument(result)
            "importDocument" -> importDocument(result)
            "pickPersistableTextFile" -> pickPersistableTextFile(result)
            "pickFontFile" -> pickFontFile(result)
            "deleteFontFile" -> deleteFontFile(call, result)
            "readPersistedText" -> readPersistedText(call, result)
            "releasePersistedText" -> releasePersistedText(call, result)
            else -> result.notImplemented()
        }
    }

    private fun startPicker(
        result: MethodChannel.Result,
        pending: MethodChannel.Result?,
        requestCode: Int,
        intent: Intent,
        setPending: (MethodChannel.Result?) -> Unit,
    ) {
        if (pending != null) {
            result.error("picker_busy", "另一个文件选择器仍在打开", null)
            return
        }
        setPending(result)
        runCatching { activity.startActivityForResult(intent, requestCode) }
            .onFailure {
                setPending(null)
                result.error("picker_failed", it.message, null)
            }
    }

    private fun beginExportDocument(call: MethodCall, result: MethodChannel.Result) {
        val suggested = call.argument<String>("name")?.takeIf { it.isNotBlank() }
            ?: "diting-backup.json"
        val mimeType = call.argument<String>("mimeType")?.takeIf { it.isNotBlank() }
            ?: "application/json"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, suggested)
        }
        startPicker(result, pendingExportResult, REQUEST_EXPORT_DOCUMENT, intent) {
            pendingExportResult = it
        }
    }

    private fun appendExportChunk(call: MethodCall, result: MethodChannel.Result) {
        val session = exportSession
        if (session == null || call.argument<Int>("handle") != session.handle) {
            result.error("export_closed", "导出文件已关闭", null)
            return
        }
        try {
            session.stream.write(call.argument<String>("chunk").orEmpty().toByteArray(Charsets.UTF_8))
            session.stream.flush()
            result.success(true)
        } catch (error: Throwable) {
            closeExportSession(delete = true)
            result.error("export_failed", error.message ?: "写入失败", null)
        }
    }

    private fun endExportDocument(call: MethodCall, result: MethodChannel.Result) {
        val session = exportSession
        if (session == null || call.argument<Int>("handle") != session.handle) {
            result.error("export_closed", "导出文件已关闭", null)
            return
        }
        exportSession = null
        result.success(
            runCatching {
                session.stream.flush()
                session.stream.close()
                mapOf(
                    "saved" to true,
                    "name" to (displayNameOf(session.uri) ?: session.uri.lastPathSegment ?: ""),
                    "cancelled" to false,
                )
            }.getOrElse { error ->
                mapOf(
                    "saved" to false,
                    "name" to null,
                    "cancelled" to false,
                    "error" to error.reason(),
                )
            },
        )
    }

    private fun abortExportDocument(result: MethodChannel.Result) {
        closeExportSession(delete = true)
        result.success(true)
    }

    private fun closeExportSession(delete: Boolean) {
        val session = exportSession ?: return
        exportSession = null
        runCatching { session.stream.close() }
        if (delete) runCatching { activity.contentResolver.delete(session.uri, null, null) }
    }

    private fun importDocument(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        startPicker(result, pendingImportResult, REQUEST_IMPORT_DOCUMENT, intent) {
            pendingImportResult = it
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        when (requestCode) {
            REQUEST_PICK_TEXT_FILE -> finishPickTextFile(resultCode, data)
            REQUEST_PICK_FONT_FILE -> finishPickFontFile(resultCode, data)
            REQUEST_EXPORT_DOCUMENT -> finishExportDocument(resultCode, data)
            REQUEST_IMPORT_DOCUMENT -> finishImportDocument(resultCode, data)
            REQUEST_IGNORE_BATTERY -> finishIgnoreBatteryOptimizations()
            else -> false
        }

    private fun finishExportDocument(resultCode: Int, data: Intent?): Boolean {
        val pending = pendingExportResult ?: return false
        pendingExportResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(mapOf("saved" to false, "name" to null, "cancelled" to true))
            return true
        }
        pending.success(
            runCatching {
                val stream = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: error("无法打开导出文件")
                closeExportSession(delete = false)
                exportHandle += 1
                exportSession = ExportSession(exportHandle, uri, stream)
                mapOf(
                    "saved" to true,
                    "name" to (displayNameOf(uri) ?: uri.lastPathSegment ?: ""),
                    "cancelled" to false,
                    "handle" to exportHandle,
                )
            }.getOrElse { error ->
                mapOf(
                    "saved" to false,
                    "name" to null,
                    "cancelled" to false,
                    "error" to error.reason(),
                )
            },
        )
        return true
    }

    private fun finishImportDocument(resultCode: Int, data: Intent?): Boolean {
        val pending = pendingImportResult ?: return false
        pendingImportResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(mapOf("saved" to false, "name" to null, "cancelled" to true))
            return true
        }
        pending.success(
            runCatching {
                val text = activity.contentResolver.openInputStream(uri)?.use {
                    it.readBytes().toString(Charsets.UTF_8)
                } ?: error("无法读取该文件")
                mapOf(
                    "text" to text,
                    "name" to (displayNameOf(uri) ?: uri.lastPathSegment ?: ""),
                    "cancelled" to false,
                )
            }.getOrElse { error ->
                mapOf(
                    "text" to null,
                    "name" to null,
                    "cancelled" to false,
                    "error" to error.reason(),
                )
            },
        )
        return true
    }

    private fun pickPersistableTextFile(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/*"
        }
        startPicker(result, pendingTextResult, REQUEST_PICK_TEXT_FILE, intent) {
            pendingTextResult = it
        }
    }

    private fun finishPickTextFile(resultCode: Int, data: Intent?): Boolean {
        val pending = pendingTextResult ?: return false
        pendingTextResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(mapOf("cancelled" to true))
            return true
        }
        val granted = runCatching {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }.isSuccess
        pending.success(
            runCatching {
                val text = readUriText(uri) ?: error("无法读取该文件")
                if (!granted) ruleCache.write(uri, text)
                mapOf(
                    "uri" to uri.toString(),
                    "name" to (displayNameOf(uri) ?: uri.lastPathSegment ?: ""),
                    "text" to text,
                    "persisted" to granted,
                    "cancelled" to false,
                )
            }.getOrElse { error ->
                mapOf(
                    "cancelled" to false,
                    "error" to error.reason(),
                )
            },
        )
        return true
    }

    private fun pickFontFile(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        startPicker(result, pendingFontResult, REQUEST_PICK_FONT_FILE, intent) {
            pendingFontResult = it
        }
    }

    private fun finishPickFontFile(resultCode: Int, data: Intent?): Boolean {
        val pending = pendingFontResult ?: return false
        pendingFontResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(mapOf("cancelled" to true))
            return true
        }
        pending.success(
            runCatching {
                val bytes = activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("无法读取该文件")
                require(bytes.size >= MIN_FONT_BYTES) { "这不是有效的字体文件" }
                val magic = bytes.copyOfRange(0, 4)
                val sfnt = (magic[0].toInt() == 0 && magic[1].toInt() == 1) ||
                    (magic[0] == 'O'.code.toByte() && magic[1] == 'T'.code.toByte()) ||
                    (magic[0] == 't'.code.toByte() && magic[1] == 'r'.code.toByte()) ||
                    (magic[0] == 't'.code.toByte() && magic[1] == 't'.code.toByte() &&
                        magic[2] == 'c'.code.toByte())
                require(sfnt) { "只支持 TTF / OTF 字体文件" }
                val dir = File(context.filesDir, FONT_DIR).apply { mkdirs() }
                val digest = MessageDigest.getInstance("SHA-1")
                    .digest(bytes)
                    .joinToString("") { "%02x".format(it) }
                    .take(20)
                val file = File(dir, "$digest.ttf")
                file.writeBytes(bytes)
                mapOf(
                    "path" to file.absolutePath,
                    "name" to (displayNameOf(uri) ?: uri.lastPathSegment ?: "字体"),
                    "bytes" to bytes.size,
                    "cancelled" to false,
                )
            }.getOrElse { error ->
                mapOf(
                    "cancelled" to false,
                    "error" to error.reason(),
                )
            },
        )
        return true
    }

    private fun deleteFontFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (!path.isNullOrBlank()) {
            runCatching {
                val dir = File(context.filesDir, FONT_DIR)
                val target = File(path)
                if (target.parentFile?.canonicalPath == dir.canonicalPath) {
                    target.delete()
                }
            }
        }
        result.success(null)
    }

    private fun readPersistedText(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("uri")
        if (raw.isNullOrBlank()) {
            result.error("invalid_uri", "缺少文件地址", null)
            return
        }
        val uri = Uri.parse(raw)
        result.success(
            runCatching {
                val text = runCatching { readUriText(uri) }.getOrNull()
                    ?: ruleCache.read(uri)
                    ?: error("无法读取该文件")
                mapOf("text" to text, "error" to null)
            }.getOrElse { error ->
                mapOf("text" to null, "error" to error.reason())
            },
        )
    }

    private fun releasePersistedText(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("uri")
        if (!raw.isNullOrBlank()) {
            val uri = Uri.parse(raw)
            runCatching {
                activity.contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            ruleCache.delete(uri)
        }
        result.success(null)
    }

    private fun readUriText(uri: Uri): String? = activity.contentResolver
        .openInputStream(uri)
        ?.use { it.readBytes().toString(Charsets.UTF_8) }

    private fun displayNameOf(uri: Uri): String? = runCatching {
        activity.contentResolver.query(
            uri,
            arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getString(0)
            } else {
                null
            }
        }
    }.getOrNull()

    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingBatteryResult: MethodChannel.Result? = null
    private var pendingTextResult: MethodChannel.Result? = null
    private var pendingFontResult: MethodChannel.Result? = null

    private var exportSession: ExportSession? = null

    private var exportHandle = 0

    private class ExportSession(val handle: Int, val uri: Uri, val stream: OutputStream)

    private fun applyRecentsPrivacy(call: MethodCall, result: MethodChannel.Result) {
        val hide = call.argument<Boolean>("hide") ?: false
        result.success(applyRecentsPrivacyInternal(hide))
    }

    private fun applyRecentsPrivacyInternal(hide: Boolean): Boolean = runCatching {
        val manager = context.getSystemService(ActivityManager::class.java) ?: return false
        manager.appTasks.forEach { task ->
            runCatching { task.setExcludeFromRecents(hide) }
        }
        true
    }.getOrDefault(false)

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        if (pendingBatteryResult != null) {
            result.error("request_busy", "另一个电池优化请求仍在等待", null)
            return
        }
        if (isIgnoringBatteryOptimizations()) {
            result.success(true)
            return
        }
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${context.packageName}"))
        val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        val intent = if (direct.resolveActivity(context.packageManager) != null) direct else fallback
        pendingBatteryResult = result
        runCatching { activity.startActivityForResult(intent, REQUEST_IGNORE_BATTERY) }
            .onFailure {
                pendingBatteryResult = null
                result.success(false)
            }
    }

    private fun finishIgnoreBatteryOptimizations(): Boolean {
        val pending = pendingBatteryResult ?: return false
        pendingBatteryResult = null
        pending.success(isIgnoringBatteryOptimizations())
        return true
    }

    private fun memoryInfo(): Map<String, Any> {
        val self = android.os.Debug.MemoryInfo()
        val hasSelf = runCatching { android.os.Debug.getMemoryInfo(self) }.isSuccess
        val totalPss = if (hasSelf) self.totalPss else 0
        val runtime = Runtime.getRuntime()
        val javaHeap = runtime.totalMemory() - runtime.freeMemory()
        val nativeHeap = android.os.Debug.getNativeHeapAllocatedSize()
        val system = ActivityManager.MemoryInfo()
        val hasSystem = runCatching {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager.getMemoryInfo(system)
        }.isSuccess
        return mapOf(
            "available" to (hasSelf && totalPss > 0),
            "totalPss" to totalPss,
            "javaHeap" to javaHeap / 1024,
            "nativeHeap" to nativeHeap / 1024,
            "systemTotal" to if (hasSystem) system.totalMem / 1024 else 0L,
            "systemAvail" to if (hasSystem) system.availMem / 1024 else 0L,
        )
    }

    private fun exportText(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name")
            ?.takeIf { it.isNotBlank() }
            ?.replace(Regex("[^A-Za-z0-9._-]"), "_")
            ?: "diting-export.txt"
        val content = call.argument<String>("content").orEmpty()
        val root = context.getExternalFilesDir(null) ?: context.filesDir
        val dir = File(root, EXPORT_DIR).apply { mkdirs() }
        val file = File(dir, name)
        runCatching { file.writeText(content) }.fold(
            onSuccess = { result.success(file.absolutePath) },
            onFailure = { result.error("export_failed", it.message, null) },
        )
    }
}

private fun Throwable.reason(): String = message ?: javaClass.simpleName
