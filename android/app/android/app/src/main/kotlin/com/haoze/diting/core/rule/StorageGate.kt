package com.haoze.diting.core.rule

import android.content.Context
import java.io.File

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
