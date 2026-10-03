package com.haoze.diting.ui

import android.content.Context
import com.haoze.diting.ui.settings.StartupSelfCheck

/**
 * Entry point for the startup self-check and config repair orchestration, which
 * composes multiple setting stores under [com.haoze.diting.ui.settings].
 *
 * The former pass-through facade members were dismantled: call sites now use the
 * individual store objects ([com.haoze.diting.ui.settings.AppearanceSettingsStore],
 * [com.haoze.diting.ui.settings.SystemSettingsStore],
 * [com.haoze.diting.ui.settings.AppRulesSettingsStore],
 * [com.haoze.diting.ui.settings.ResolutionSettingsStore],
 * [com.haoze.diting.ui.settings.BootstrapDnsSettingsStore],
 * [com.haoze.diting.ui.settings.DnsCacheSettingsStore],
 * [com.haoze.diting.ui.settings.OutboundProxySettingsStore],
 * [com.haoze.diting.ui.settings.AgentApiSettingsStore]) directly.
 */
object AppSettings {
    fun performStartupSelfCheck(context: Context) = StartupSelfCheck.performStartupSelfCheck(context)
}
