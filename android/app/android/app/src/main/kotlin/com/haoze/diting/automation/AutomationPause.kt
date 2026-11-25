package com.haoze.diting.automation

import android.content.Context
import com.haoze.diting.control.BlockPauseLink

/** 暂停状态读写：供外部控制与通知栏动作共用。 */
internal object AutomationPause {
    fun pause(context: Context, minutes: Int): Long {
        val untilMs: Long =
            System.currentTimeMillis() + minutes.coerceAtLeast(0).toLong() * 60_000L
        set(context, untilMs)
        return untilMs
    }

    fun resume(context: Context) = set(context, 0L)

    private fun set(context: Context, untilMs: Long) {
        AutomationContract.prefs(context).edit()
            .putLong(AutomationContract.KEY_PAUSED_UNTIL_MS, untilMs)
            .apply()
        BlockPauseLink.apply(context)
    }
}
