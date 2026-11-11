package com.haoze.diting.platform

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Avatar disk cache outside the APK; Dart has no path_provider, writes use a `.part` file.

class RecognitionAvatarBridge(private val context: android.content.Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/recognition"

        private const val DIR = "recognition_avatars"
        private const val MAX_BYTES = 1024 * 1024

        /// Whitelist only; anything else is treated as missing
        private val NAME_PATTERN = Regex("^[a-z0-9_]+_avatar\\.jpg$")
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "read" -> read(call, result)
            "write" -> write(call, result)
            "remove" -> remove(call, result)
            "clear" -> clear(result)
            else -> result.notImplemented()
        }
    }

    private fun read(call: MethodCall, result: MethodChannel.Result) {
        val file = fileFor(call.argument<String>("name"))
        if (file == null || !file.isFile || file.length() <= 0L) {
            result.success(null)
            return
        }
        Thread {
            val bytes = runCatching { file.readBytes() }.getOrNull()
            ChannelResults.success(result, bytes)
        }.start()
    }

    private fun write(call: MethodCall, result: MethodChannel.Result) {
        val file = fileFor(call.argument<String>("name"))
        val bytes = call.argument<ByteArray>("bytes")
        if (file == null || bytes == null || bytes.isEmpty() || bytes.size > MAX_BYTES) {
            result.success(null)
            return
        }
        Thread {
            val path = runCatching { writeAtomically(file, bytes) }.getOrNull()
            ChannelResults.success(result, path)
        }.start()
    }

    private fun remove(call: MethodCall, result: MethodChannel.Result) {
        val file = fileFor(call.argument<String>("name"))
        result.success(file != null && runCatching { file.delete() }.getOrDefault(false))
    }

    private fun clear(result: MethodChannel.Result) {
        Thread {
            val removed = runCatching {
                cacheDir().listFiles()?.count { it.isFile && it.delete() } ?: 0
            }.getOrDefault(0)
            ChannelResults.success(result, removed)
        }.start()
    }

    private fun cacheDir(): File = File(context.filesDir, DIR).apply { mkdirs() }

    private fun fileFor(name: String?): File? {
        val trimmed = name?.trim().orEmpty()
        if (!NAME_PATTERN.matches(trimmed)) return null
        return File(cacheDir(), trimmed)
    }

    private fun writeAtomically(target: File, bytes: ByteArray): String? {
        val temp = File(target.parentFile, target.name + ".part")
        val ok = runCatching { temp.outputStream().use { it.write(bytes) } }.isSuccess
        if (!ok) {
            temp.delete()
            return null
        }
        if (target.exists()) target.delete()
        return if (temp.renameTo(target)) target.absolutePath else null
    }
}
