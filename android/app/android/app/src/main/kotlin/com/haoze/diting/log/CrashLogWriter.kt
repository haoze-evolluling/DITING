package com.haoze.diting.log

import android.content.Context
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Writes an uncaught exception into `filesDir/crash`, the folder the troubleshooting page and
/// `AppStorageCleaner` already read and clear.
///
/// That writer did not exist before: the crash list was only ever fed by the system crash buffer,
/// which some devices restrict. This makes the Kotlin crash a file the user can open even when the
/// buffer read fails, and gives `diting_crash_state`'s "consecutive crash" bookkeeping a source.
internal object CrashLogWriter {
    private const val TAG = "CrashLogWriter"
    private const val DIR = "crash"

    fun write(context: Context, thread: Thread?, error: Throwable) {
        runCatching {
            val directory = File(context.filesDir, DIR).apply { mkdirs() }
            val stamp = SimpleDateFormat("yyyyMMdd-HHmmss-SSS", Locale.US).format(Date())
            val file = File(directory, "crash-$stamp.log")
            PrintWriter(file).use { out ->
                out.println("time: ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())}")
                out.println("thread: ${thread?.name ?: "?"}")
                out.println("process: ${android.os.Process.myPid()}")
                error.printStackTrace(out)
            }
        }.onFailure { Log.w(TAG, "crash log write failed", it) }
    }
}
