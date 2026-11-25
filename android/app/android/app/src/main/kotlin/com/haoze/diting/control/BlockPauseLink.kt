package com.haoze.diting.control

import android.content.Context
import android.content.SharedPreferences
import com.haoze.diting.automation.AutomationContract
import com.haoze.diting.engine.TunnelEngine
import com.haoze.diting.net.EngineAccess

internal object BlockPauseLink {

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(AutomationContract.PREFS_NAME, Context.MODE_PRIVATE)

    fun apply(context: Context) {
        val engine = EngineAccess.current(context) ?: return
        applyTo(context, engine)
    }

    fun applyTo(context: Context, engine: TunnelEngine) {
        val prefs = prefs(context)
        engine.setBlockPause(prefs.getLong(AutomationContract.KEY_PAUSED_UNTIL_MS, 0L))
        engine.setAllowlistOnly(prefs.getBoolean(AutomationContract.KEY_ALLOWLIST_ONLY, false))
    }
}
