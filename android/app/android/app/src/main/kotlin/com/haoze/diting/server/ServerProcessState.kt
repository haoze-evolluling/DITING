package com.haoze.diting.server

import android.content.Context
import java.io.File

/// The last observed state of the standalone server process.
///
/// The service and the MethodChannel bridge live in the same app process, so a synchronized
/// singleton is the source of truth for both. Flutter polls it instead of duplicating lifecycle
/// state in Dart.
object ServerProcessState {
    private val lock = Any()

    @Volatile private var runningFlag = false
    @Volatile private var startingFlag = false
    @Volatile private var rootFlag = false
    @Volatile private var portValue = 1053
    @Volatile private var addressesValue = listOf<String>()
    @Volatile private var startedAtValue = 0L
    @Volatile private var errorValue: String? = null
    @Volatile private var pidValue = 0L

    val running: Boolean get() = runningFlag
    val starting: Boolean get() = startingFlag
    val pid: Long get() = pidValue

    fun begin(preferRoot: Boolean) = synchronized(lock) {
        runningFlag = false
        startingFlag = true
        rootFlag = preferRoot
        portValue = if (preferRoot) 53 else 1053
        addressesValue = emptyList()
        startedAtValue = 0L
        errorValue = null
        pidValue = 0L
    }

    fun ready(root: Boolean, port: Int, addresses: List<String>, pid: Long) =
        synchronized(lock) {
            runningFlag = true
            startingFlag = false
            rootFlag = root
            portValue = port
            addressesValue = addresses
            startedAtValue = System.currentTimeMillis()
            errorValue = null
            pidValue = pid
        }

    fun failed(message: String, root: Boolean = rootFlag, port: Int = portValue) =
        synchronized(lock) {
            runningFlag = false
            startingFlag = false
            rootFlag = root
            portValue = port
            addressesValue = emptyList()
            startedAtValue = 0L
            errorValue = message
            pidValue = 0L
        }

    fun stopped() = synchronized(lock) {
        runningFlag = false
        startingFlag = false
        addressesValue = emptyList()
        startedAtValue = 0L
        pidValue = 0L
    }

    fun snapshot(): Map<String, Any?> = synchronized(lock) {
        mapOf(
            "running" to runningFlag,
            "starting" to startingFlag,
            "root" to rootFlag,
            "port" to portValue,
            "bindAddress" to "0.0.0.0",
            "addresses" to addressesValue,
            "startedAt" to startedAtValue,
            "error" to errorValue,
        )
    }
}

object ServerPaths {
    private const val DIR = "server"

    fun dataDir(context: Context): File = File(context.filesDir, DIR)
    fun configFile(context: Context): File = File(dataDir(context), "config.json")
    fun socketFile(context: Context): File = File(dataDir(context), "control.sock")
    fun logFile(context: Context): File = File(dataDir(context), "server.log")
}

object ServerPreference {
    private const val PREFS = "server_mode_prefs"
    private const val KEY_PREFER_ROOT = "prefer_root"

    fun preferRoot(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_PREFER_ROOT, true)

    fun setPreferRoot(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_PREFER_ROOT, value)
            .apply()
    }
}
