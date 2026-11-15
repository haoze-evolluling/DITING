package com.haoze.diting.platform

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/// Outcome of dropping one file into the user-visible Download folder.
internal data class DownloadWrite(
    val saved: Boolean,
    val path: String?,
    val error: String?,
) {
    /// Channel payload; every bridge answers with the same three keys so Dart parses one shape.
    fun toMap(): Map<String, Any?> =
        mapOf("saved" to saved, "path" to path, "error" to error)

    companion object {
        fun failed(error: String? = null) = DownloadWrite(false, null, error)
    }
}

/// Writes bytes into the shared Download folder, where a file manager or a USB cable can reach
/// them. MediaStore needs no storage permission on Android 10+; older releases and MediaStore
/// failures fall back to the app-private Downloads directory, matching `CaInspectionBridge`.
internal object DownloadFolderWriter {

    fun write(context: Context, name: String, mime: String, bytes: ByteArray): DownloadWrite =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            writePrivate(context, name, bytes)
        } else {
            runCatching { writeShared(context, name, mime, bytes) }
                .getOrElse { writePrivate(context, name, bytes) }
        }

    /// Public Download: insert a pending row, stream into it, then publish it. Publishing last
    /// keeps a half-written file out of the gallery-style listings until it is complete.
    private fun writeShared(
        context: Context,
        name: String,
        mime: String,
        bytes: ByteArray,
    ): DownloadWrite {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return DownloadWrite.failed()
        val stream = resolver.openOutputStream(uri)
        if (stream == null) {
            runCatching { resolver.delete(uri, null, null) }
            return DownloadWrite.failed()
        }
        stream.use { it.write(bytes) }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        // A duplicate name is renamed by MediaStore (`name (1).log`); report what actually landed.
        val written = displayName(resolver, uri) ?: name
        return DownloadWrite(true, "${Environment.DIRECTORY_DOWNLOADS}/$written", null)
    }

    private fun displayName(resolver: ContentResolver, uri: Uri): String? = runCatching {
        resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
    }.getOrNull()

    /// Fallback for API < 29 and MediaStore failures: app-private Downloads, no permission needed.
    private fun writePrivate(context: Context, name: String, bytes: ByteArray): DownloadWrite {
        val root = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: File(context.filesDir, "downloads")
        if (!root.exists() && !root.mkdirs()) return DownloadWrite.failed()
        return runCatching {
            val file = File(root, name)
            file.writeBytes(bytes)
            DownloadWrite(true, file.absolutePath, null)
        }.getOrElse { DownloadWrite.failed(it.message) }
    }
}
