package com.haoze.diting.core.rule

import android.content.Context
import java.io.File

/**
 * Native view of the Dart-side V2 migration gate.
 *
 * Services must not open a mode store while the migrator is copying into it, and must not open the
 * seven V2 files before the first launch has created them. A short-lived lock file covers the
 * window where the state preference has not been committed yet.
 */
object StorageGate {
    private const val SETTINGS = "diting_settings"
    private const val STATE_KEY = "storage_v2_state"
    private const val LOCK_FILE = ".storage_v2_migrating"
    private const val STALE_LOCK_MS = 10 * 60 * 1000L

    const val STATE_IDLE = 0
    const val STATE_COPYING = 1
    const val STATE_VERIFIED = 2
    const val STATE_CLEANED = 3

    fun state(context: Context): Int =
        context.getSharedPreferences(SETTINGS, Context.MODE_PRIVATE)
            .getInt(STATE_KEY, STATE_IDLE)

    /** True while a service must refuse to start because the stores are not ready. */
    fun blocksDataPlane(context: Context): Boolean {
        val value = state(context)
        if (value == STATE_IDLE || value == STATE_COPYING) return true
        val lock = lockFile(context)
        if (!lock.exists()) return false
        return System.currentTimeMillis() - lock.lastModified() < STALE_LOCK_MS
    }

    private fun lockFile(context: Context): File =
        File(File(context.applicationInfo.dataDir, "databases"), LOCK_FILE)
}
