package com.haoze.diting.control

import android.content.Context
import android.content.SharedPreferences
import com.haoze.diting.automation.AutomationContract
import com.haoze.diting.net.EngineAccess

/// R4: push the pause deadline and allowlist-only flag from the shared automation prefs onto the
/// engine that currently backs a mode.
///
/// Centralised so the notification action, the control receiver and the Dart bridge all take effect
/// immediately on the live engine without knowing which service is up. `EngineAccess.current()` is
/// null when no mode is running, in which case the values are simply persisted and replayed by each
/// service at startup (`BlockPauseLink.apply` is called right after it starts its engine).
internal object BlockPauseLink {

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(AutomationContract.PREFS_NAME, Context.MODE_PRIVATE)

    fun apply(context: Context) {
        val engine = EngineAccess.current() ?: return
        val prefs = prefs(context)
        engine.setBlockPause(prefs.getLong(AutomationContract.KEY_PAUSED_UNTIL_MS, 0L))
        engine.setAllowlistOnly(prefs.getBoolean(AutomationContract.KEY_ALLOWLIST_ONLY, false))
    }
}
