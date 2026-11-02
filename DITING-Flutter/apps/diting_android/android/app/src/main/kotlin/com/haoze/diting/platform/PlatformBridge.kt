package com.haoze.diting.platform

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.OutputStream
import java.security.MessageDigest

/// OS-level operations with no Dart equivalent; the SAF pickers and task list need an Activity.
class PlatformBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/platform"

        private const val REQUEST_EXPORT_DOCUMENT = 0x5701
        private const val REQUEST_IMPORT_DOCUMENT = 0x5702

        /// Local-file subscriptions keep a long-lived read grant, unlike a one-shot import.
        private const val REQUEST_PICK_TEXT_FILE = 0x5703

        /// User-supplied fonts are copied into app storage, so a one-shot read is enough.
        private const val REQUEST_PICK_FONT_FILE = 0x5704

        private const val FONT_DIR = "fonts"

        /// Anything smaller than this cannot hold a usable TrueType table directory.
        private const val MIN_FONT_BYTES = 1024

        private const val EXPORT_DIR = "exports"

        private const val HIDE_FROM_RECENTS_KEY = "hide_from_recents_enabled"

        private const val UI_PREFS = "dns_vpn_prefs"
    }

    private val context: Context get() = activity

    private val storage = AppStorageCleaner(activity)

    private val wifi = WifiSsidReader(activity)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    /// Re-applies recents hiding on resume, so a cold start needs no push from Dart
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
            // Null means "cannot tell" (no permission); "" means "not on Wi-Fi".
            "currentSsid" -> result.success(wifi.currentSsid())
            // File-system cleanup sqflite cannot reach: it only sees `databases/`.
            "clearUpdateCache" -> result.success(storage.clearUpdateCache(call.argument<Boolean>("includeTemp") ?: true))
            "clearCustomBackgroundCache" -> result.success(storage.clearCustomBackgroundCache())
            // Both are picker round trips; the answer arrives through onActivityResult.
            // The export opens the document and keeps it open, so Dart can stream the JSON in
            // group-sized chunks instead of handing over one string.
            "beginExportDocument" -> beginExportDocument(call, result)
            "appendExportChunk" -> appendExportChunk(call, result)
            "endExportDocument" -> endExportDocument(call, result)
            "abortExportDocument" -> abortExportDocument(result)
            "importDocument" -> importDocument(call, result)
            // Local-file subscriptions: the grant must outlive the picker dialog, so these are
            // separate from importDocument, which only reads the text once.
            "pickPersistableTextFile" -> pickPersistableTextFile(result)
            "pickFontFile" -> pickFontFile(result)
            "deleteFontFile" -> deleteFontFile(call, result)
            "readPersistedText" -> readPersistedText(call, result)
            "releasePersistedText" -> releasePersistedText(call, result)
            else -> result.notImplemented()
        }
    }

    /// Opens the save picker and keeps the chosen document open for [appendExportChunk].
    private fun beginExportDocument(call: MethodCall, result: MethodChannel.Result) {
        val suggested = call.argument<String>("name")?.takeIf { it.isNotBlank() }
            ?: "diting-backup.json"
        if (pendingDocumentResult != null) {
            result.error("picker_busy", "另一个文件选择器仍在打开", null)
            return
        }
        pendingDocumentResult = result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, suggested)
        }
        runCatching { activity.startActivityForResult(intent, REQUEST_EXPORT_DOCUMENT) }
            .onFailure {
                pendingDocumentResult = null
                result.error("picker_failed", it.message, null)
            }
    }

    /// Appends one chunk of the exported document.
    ///
    /// The backup used to travel as a single string: built in the Dart heap, copied across the
    /// channel, turned into a byte array and written in one go, so a big rule list existed four
    /// times at once. Chunks go straight to the file.
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
                    "error" to (error.message ?: error.javaClass.simpleName),
                )
            },
        )
    }

    /// Drops a half-written export: the document is closed and deleted, so a failed or empty export
    /// does not leave a truncated file in the user's folder.
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

    private fun importDocument(call: MethodCall, result: MethodChannel.Result) {
        if (pendingDocumentResult != null) {
            result.error("picker_busy", "另一个文件选择器仍在打开", null)
            return
        }
        pendingDocumentResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // `application/json` alone hides files a file manager labelled `text/plain`.
            type = "*/*"
        }
        runCatching { activity.startActivityForResult(intent, REQUEST_IMPORT_DOCUMENT) }
            .onFailure {
                pendingDocumentResult = null
                result.error("picker_failed", it.message, null)
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_PICK_TEXT_FILE) {
            finishPickTextFile(resultCode, data)
            return true
        }
        if (requestCode == REQUEST_PICK_FONT_FILE) {
            finishPickFontFile(resultCode, data)
            return true
        }
        val isExport = requestCode == REQUEST_EXPORT_DOCUMENT
        val isImport = requestCode == REQUEST_IMPORT_DOCUMENT
        if (!isExport && !isImport) return false
        val pending = pendingDocumentResult
        pendingDocumentResult = null
        if (pending == null) return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(mapOf("saved" to false, "name" to null, "cancelled" to true))
            return true
        }
        if (isExport) {
            pending.success(
                runCatching {
                    // "wt" truncates: a shorter backup would leave the previous tail.
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
                        "error" to (error.message ?: error.javaClass.simpleName),
                    )
                },
            )
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
                    "error" to (error.message ?: error.javaClass.simpleName),
                )
            },
        )
        return true
    }

    /// Opens the document picker and keeps the returned grant, so a local subscription can be
    /// re-imported later without asking the user to pick the file again.
    private fun pickPersistableTextFile(result: MethodChannel.Result) {
        if (pendingDocumentResult != null) {
            result.error("picker_busy", "另一个文件选择器仍在打开", null)
            return
        }
        pendingDocumentResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // Rule files are plain text but file managers label them inconsistently.
            type = "text/*"
        }
        runCatching { activity.startActivityForResult(intent, REQUEST_PICK_TEXT_FILE) }
            .onFailure {
                pendingDocumentResult = null
                result.error("picker_failed", it.message, null)
            }
    }

    private fun finishPickTextFile(resultCode: Int, data: Intent?) {
        val pending = pendingDocumentResult
        pendingDocumentResult = null
        if (pending == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(mapOf("cancelled" to true))
            return
        }
        // takePersistableUriPermission survives a reboot; without it the uri dies with the task.
        val granted = runCatching {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }.isSuccess
        pending.success(
            runCatching {
                val text = readUriText(uri) ?: error("无法读取该文件")
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
                    "error" to (error.message ?: error.javaClass.simpleName),
                )
            },
        )
    }

    /// Opens the document picker for a font file. The bytes are copied into `filesDir/fonts` right
    /// away, so Dart can register them with `loadFontFromList` without holding a URI grant forever.
    private fun pickFontFile(result: MethodChannel.Result) {
        if (pendingDocumentResult != null) {
            result.error("picker_busy", "另一个文件选择器仍在打开", null)
            return
        }
        pendingDocumentResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // `font/*` matches almost nothing on Android, and plenty of file managers label a TTF
            // `application/octet-stream`, so accept anything and validate by content.
            type = "*/*"
        }
        runCatching { activity.startActivityForResult(intent, REQUEST_PICK_FONT_FILE) }
            .onFailure {
                pendingDocumentResult = null
                result.error("picker_failed", it.message, null)
            }
    }

    private fun finishPickFontFile(resultCode: Int, data: Intent?) {
        val pending = pendingDocumentResult
        pendingDocumentResult = null
        if (pending == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(mapOf("cancelled" to true))
            return
        }
        pending.success(
            runCatching {
                val bytes = activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("无法读取该文件")
                require(bytes.size >= MIN_FONT_BYTES) { "这不是有效的字体文件" }
                // `00 01` (TrueType) / `OTTO` (CFF) / `true` / `ttcf` (collection).
                val magic = bytes.copyOfRange(0, 4)
                val sfnt = magic.size == 4 &&
                    (
                        (magic[0].toInt() == 0 && magic[1].toInt() == 1) ||
                            (magic[0] == 'O'.code.toByte() && magic[1] == 'T'.code.toByte()) ||
                            (magic[0] == 't'.code.toByte() && magic[1] == 'r'.code.toByte()) ||
                            (magic[0] == 't'.code.toByte() && magic[1] == 't'.code.toByte() &&
                                magic[2] == 'c'.code.toByte())
                        )
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
                    "error" to (error.message ?: error.javaClass.simpleName),
                )
            },
        )
    }

    /// Deletes a font copied in by [finishPickFontFile]; unknown paths are ignored, so a stale
    /// entry cannot make Dart fail to save.
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

    /// Re-reads a previously picked file; the stored grant is what makes this work after a restart.
    private fun readPersistedText(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("uri")
        if (raw.isNullOrBlank()) {
            result.error("invalid_uri", "缺少文件地址", null)
            return
        }
        result.success(
            runCatching {
                val text = readUriText(Uri.parse(raw)) ?: error("无法读取该文件")
                mapOf("text" to text, "error" to null)
            }.getOrElse { error ->
                mapOf("text" to null, "error" to (error.message ?: error.javaClass.simpleName))
            },
        )
    }

    /// Drops the grant when the subscription is deleted; a stale grant would leak read access.
    private fun releasePersistedText(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("uri")
        if (!raw.isNullOrBlank()) {
            runCatching {
                activity.contentResolver.releasePersistableUriPermission(
                    Uri.parse(raw),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        }
        result.success(null)
    }

    private fun readUriText(uri: Uri): String? = activity.contentResolver
        .openInputStream(uri)
        ?.use { it.readBytes().toString(Charsets.UTF_8) }

    /// Display name for a `content://` URI; `lastPathSegment` is the opaque document id
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

    private var pendingDocumentResult: MethodChannel.Result? = null

    /// The document an export is being streamed into; null when no export is in flight.
    private var exportSession: ExportSession? = null

    private var exportHandle = 0

    private class ExportSession(val handle: Int, val uri: Uri, val stream: OutputStream)

    private fun applyRecentsPrivacy(call: MethodCall, result: MethodChannel.Result) {
        val hide = call.argument<Boolean>("hide") ?: false
        result.success(applyRecentsPrivacyInternal(hide))
    }

    /// Sets `excludeFromRecents` on every task; false when no task list is reachable yet
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
        // Newer Android opens the optimisation list; the settings screen keeps the button useful.
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${context.packageName}"))
        val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            direct.resolveActivity(context.packageManager) != null
        ) {
            direct
        } else {
            fallback
        }
        val ok = runCatching { activity.startActivity(intent) }.isSuccess
        result.success(ok)
    }

    /// Process plus device totals, in KB. Never add `totalPss` to the heaps:
    /// it counts `.so` and `.dex` too
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

    /// Writes `content` to `getExternalFilesDir/exports/<name>`; no SAF picker, USB can read it
    
    
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
