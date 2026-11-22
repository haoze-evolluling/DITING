package com.haoze.diting.server

import android.content.Context
import java.io.File
import java.util.concurrent.CopyOnWriteArraySet

object ServerProcessState {
    private val lock = Any()
    private val listeners = CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()

    @Volatile private var runningFlag = false
    @Volatile private var startingFlag = false
    @Volatile private var stoppingFlag = false
    @Volatile private var rootFlag = false
    @Volatile private var portValue = 1053
    @Volatile private var addressesValue = listOf<String>()
    @Volatile private var startedAtValue = 0L
    @Volatile private var errorValue: String? = null
    @Volatile private var pidValue = 0L

    val running: Boolean get() = runningFlag
    val starting: Boolean get() = startingFlag
    val stopping: Boolean get() = stoppingFlag
    val active: Boolean get() = runningFlag || startingFlag || stoppingFlag
    val pid: Long get() = pidValue

    fun addListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.remove(listener)
    }

    fun begin(preferRoot: Boolean) {
        val current = synchronized(lock) {
            runningFlag = false
            startingFlag = true
            stoppingFlag = false
            rootFlag = preferRoot
            portValue = if (preferRoot) 53 else 1053
            addressesValue = emptyList()
            startedAtValue = 0L
            errorValue = null
            pidValue = 0L
            snapshotLocked()
        }
        notifyListeners(current)
    }

    fun ready(root: Boolean, port: Int, addresses: List<String>, pid: Long) {
        val current = synchronized(lock) {
            runningFlag = true
            startingFlag = false
            stoppingFlag = false
            rootFlag = root
            portValue = port
            addressesValue = addresses
            startedAtValue = System.currentTimeMillis()
            errorValue = null
            pidValue = pid
            snapshotLocked()
        }
        notifyListeners(current)
    }

    fun stopping() {
        val current = synchronized(lock) {
            runningFlag = false
            startingFlag = false
            stoppingFlag = true
            snapshotLocked()
        }
        notifyListeners(current)
    }

    fun failed(message: String, root: Boolean = rootFlag, port: Int = portValue) {
        val current = synchronized(lock) {
            runningFlag = false
            startingFlag = false
            stoppingFlag = false
            rootFlag = root
            portValue = port
            addressesValue = emptyList()
            startedAtValue = 0L
            errorValue = message
            pidValue = 0L
            snapshotLocked()
        }
        notifyListeners(current)
    }

    fun stopped() {
        val current = synchronized(lock) {
            runningFlag = false
            startingFlag = false
            stoppingFlag = false
            addressesValue = emptyList()
            startedAtValue = 0L
            pidValue = 0L
            snapshotLocked()
        }
        notifyListeners(current)
    }

    fun snapshot(): Map<String, Any?> = synchronized(lock) { snapshotLocked() }

    private fun snapshotLocked(): Map<String, Any?> = mapOf(
        "running" to runningFlag,
        "starting" to startingFlag,
        "stopping" to stoppingFlag,
        "root" to rootFlag,
        "port" to portValue,
        "bindAddress" to "0.0.0.0",
        "addresses" to addressesValue,
        "startedAt" to startedAtValue,
        "error" to errorValue,
    )

    private fun notifyListeners(state: Map<String, Any?>) {
        for (listener in listeners) {
            runCatching { listener(state) }
        }
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
