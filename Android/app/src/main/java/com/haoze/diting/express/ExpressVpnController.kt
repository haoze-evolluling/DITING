package com.haoze.diting.express

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.core.content.ContextCompat
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.vpn.DnsProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Singleton state controller for Express Mode VPN.
 *
 * Exposes reactive [isRunning] StateFlow and management operations (start, stop,
 * refresh, rule sync, cache clear) for Express UI screens.
 * Integrates directly with Room persistence without touching legacy controllers.
 */
object ExpressVpnController {

    private const val PREFS_NAME = "express_vpn_prefs"
    private const val KEY_RUNNING = "express_vpn_running"

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    private val controllerScope = CoroutineScope(Dispatchers.IO)
    private var isReceiverRegistered = false

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ExpressVpnIntents.ACTION_STATUS_CHANGED) {
                val running = intent.getBooleanExtra(ExpressVpnIntents.EXTRA_RUNNING, false)
                _isRunning.value = running
            }
        }
    }

    fun initialize(context: Context) {
        val appCtx = context.applicationContext
        val persisted = getPersistedRunning(appCtx)
        val alive = ExpressVpnService.isServiceAlive
        val effective = persisted && alive
        if (persisted && !alive) {
            setPersistedRunning(appCtx, false)
        }
        _isRunning.value = effective

        if (!isReceiverRegistered) {
            val filter = IntentFilter(ExpressVpnIntents.ACTION_STATUS_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                appCtx.registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                appCtx.registerReceiver(statusReceiver, filter)
            }
            isReceiverRegistered = true
        }
    }

    fun isRunning(context: Context): Boolean {
        val persisted = getPersistedRunning(context)
        val alive = ExpressVpnService.isServiceAlive
        val running = persisted && alive
        if (persisted && !alive) {
            setPersistedRunning(context, false)
        }
        _isRunning.value = running
        return running
    }

    fun start(context: Context, provider: DnsProvider? = null) {
        val intent = ExpressVpnIntents.startIntent(context, provider)
        runCatching { ContextCompat.startForegroundService(context, intent) }
    }

    fun stop(context: Context) {
        if (!ExpressVpnService.isServiceAlive) {
            onServiceStateChanged(context, false)
            return
        }
        val intent = ExpressVpnIntents.stopIntent(context)
        runCatching { context.startService(intent) }
    }

    fun toggle(context: Context, provider: DnsProvider? = null) {
        if (_isRunning.value) {
            stop(context)
        } else {
            start(context, provider)
        }
    }

    fun refreshConfig(context: Context, reason: String = "runtime_config") {
        if (isRunning(context)) {
            runCatching { context.startService(ExpressVpnIntents.refreshConfigIntent(context, reason)) }
        }
    }

    fun syncRules(context: Context) {
        if (isRunning(context)) {
            runCatching { context.startService(ExpressVpnIntents.syncRulesIntent(context)) }
        }
    }

    fun clearCache(context: Context) {
        controllerScope.launch {
            val dao = AppDatabase.getInstance(context).dnsCacheDao()
            dao.clearAll()
            if (isRunning(context)) {
                runCatching { context.startService(ExpressVpnIntents.clearCacheIntent(context)) }
            }
        }
    }

    fun refreshFloatingLogOverlay(context: Context) {
        if (isRunning(context)) {
            runCatching { context.startService(ExpressVpnIntents.refreshFloatingLogIntent(context)) }
        }
    }

    fun updateFloatingLogAppState(context: Context, foreground: Boolean) {
        if (isRunning(context)) {
            runCatching { context.startService(ExpressVpnIntents.floatingLogAppStateIntent(context, foreground)) }
        }
    }

    internal fun onServiceStateChanged(context: Context, running: Boolean) {
        setPersistedRunning(context, running)
        _isRunning.value = running
        context.sendBroadcast(ExpressVpnIntents.statusBroadcastIntent(context, running))
        val legacyIntent = Intent(com.haoze.diting.vpn.DnsVpnService.ACTION_VPN_STATUS_CHANGED).apply {
            `package` = context.packageName
            putExtra(com.haoze.diting.vpn.DnsVpnService.EXTRA_VPN_RUNNING, running)
        }
        context.sendBroadcast(legacyIntent)
        com.haoze.diting.vpn.DitingTileService.requestTileUpdate(context)
    }

    private fun getPersistedRunning(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_RUNNING, false)

    private fun setPersistedRunning(context: Context, running: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_RUNNING, running)
            .apply()
    }
}
