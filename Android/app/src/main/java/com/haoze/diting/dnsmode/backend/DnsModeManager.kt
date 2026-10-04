package com.haoze.diting.dnsmode.backend

import android.content.Context
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.diting.dnsmode.model.DnsModeConfig
import com.haoze.diting.dnsmode.model.DnsModeProtocol
import com.haoze.diting.dnsmode.model.DnsModeStats
import com.haoze.diting.dnsmode.model.DnsServiceStatus
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID

object DnsModeManager {
    private const val TAG = "DnsModeManager"

    private val scope = CoroutineScope(Dispatchers.Default)
    private var statsJob: Job? = null

    private val _status = MutableStateFlow(DnsServiceStatus.STOPPED)
    val status: StateFlow<DnsServiceStatus> = _status.asStateFlow()

    private val _errorReason = MutableStateFlow<String?>(null)
    val errorReason: StateFlow<String?> = _errorReason.asStateFlow()

    private val _config = MutableStateFlow(DnsModeConfig())
    val config: StateFlow<DnsModeConfig> = _config.asStateFlow()

    private val _stats = MutableStateFlow(DnsModeStats())
    val stats: StateFlow<DnsModeStats> = _stats.asStateFlow()

    private val _upstreams = MutableStateFlow(DnsUpstreamServer.PRESETS)
    val upstreams: StateFlow<List<DnsUpstreamServer>> = _upstreams.asStateFlow()

    private var customUpstreams: List<DnsUpstreamServer> = emptyList()
    private var appContext: Context? = null
    private var initialized = false

    fun initialize(context: Context) {
        appContext = context.applicationContext
        if (initialized) return
        initialized = true
        val loadedConfig = DnsModePreferences.loadConfig(context)
        _config.value = loadedConfig
        _stats.value = DnsModePreferences.loadStats(context)
        customUpstreams = DnsModePreferences.loadCustomUpstreams(context)
        _upstreams.value = DnsUpstreamServer.PRESETS + customUpstreams
        if (DnsModeService.isServiceAlive) {
            _status.value = DnsServiceStatus.RUNNING
            startStatsTicker()
        }
    }

    fun getActiveUpstream(): DnsUpstreamServer {
        val currentId = _config.value.selectedUpstreamId
        return _upstreams.value.firstOrNull { it.id == currentId } ?: DnsUpstreamServer.PRESETS.first()
    }

    fun startService(context: Context) {
        if (_status.value == DnsServiceStatus.RUNNING || _status.value == DnsServiceStatus.STARTING) return
        _status.value = DnsServiceStatus.STARTING
        DnsModePreferences.setServiceActive(context, true)
        try {
            ContextCompat.startForegroundService(context, DnsModeService.startIntent(context))
        } catch (e: Exception) {
            _status.value = DnsServiceStatus.ERROR
            _errorReason.value = "DNS 服务启动失败"
            DnsModePreferences.setServiceActive(context, false)
        }
    }

    fun stopService(context: Context) {
        flushStats(context)
        if (_status.value == DnsServiceStatus.STOPPED || _status.value == DnsServiceStatus.STOPPING) return
        _status.value = DnsServiceStatus.STOPPING
        try {
            context.startService(DnsModeService.stopIntent(context))
            // Only clear the flag once the stop intent was actually queued;
            // otherwise a failed send would leave the service running while
            // persisted state claims it is stopped.
            DnsModePreferences.setServiceActive(context, false)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send stop intent to DnsModeService", e)
            _status.value = DnsServiceStatus.ERROR
            _errorReason.value = "DNS 服务停止失败，请重试"
        }
    }

    fun toggleService(context: Context) {
        when (_status.value) {
            DnsServiceStatus.RUNNING -> stopService(context)
            DnsServiceStatus.STOPPED, DnsServiceStatus.ERROR -> startService(context)
            DnsServiceStatus.STARTING, DnsServiceStatus.STOPPING -> {
                // Ignore clicks during transitional states to prevent duplicate intents
            }
        }
    }

    fun onServiceStarted() {
        _status.value = DnsServiceStatus.RUNNING
        _errorReason.value = null
        startStatsTicker()
    }

    fun onServiceStopped() {
        // Keep ERROR visible when startup failed; onDestroy must not mask it with STOPPED.
        if (_status.value != DnsServiceStatus.ERROR) {
            _status.value = DnsServiceStatus.STOPPED
        }
        stopStatsTicker()
        flushStats()
    }

    fun onServiceError(reason: String? = null) {
        _status.value = DnsServiceStatus.ERROR
        _errorReason.value = reason
        stopStatsTicker()
        flushStats()
    }

    fun selectUpstream(context: Context, serverId: String) {
        val updated = _config.value.copy(selectedUpstreamId = serverId)
        _config.value = updated
        DnsModePreferences.saveConfig(context, updated)
        refreshEngineIfRunning(context)
    }

    fun addCustomUpstream(
        context: Context,
        name: String,
        protocol: DnsModeProtocol,
        address: String,
        port: Int
    ): DnsUpstreamServer {
        val server = DnsUpstreamServer(
            id = "custom_" + UUID.randomUUID().toString(),
            name = name.trim(),
            address = address.trim(),
            port = port,
            protocol = protocol,
            isCustom = true
        )
        customUpstreams = customUpstreams + server
        _upstreams.value = DnsUpstreamServer.PRESETS + customUpstreams
        DnsModePreferences.saveCustomUpstreams(context, customUpstreams)
        return server
    }

    fun updateCustomUpstream(context: Context, server: DnsUpstreamServer) {
        if (!server.isCustom) return
        customUpstreams = customUpstreams.map { if (it.id == server.id) server else it }
        _upstreams.value = DnsUpstreamServer.PRESETS + customUpstreams
        DnsModePreferences.saveCustomUpstreams(context, customUpstreams)
        if (_config.value.selectedUpstreamId == server.id) {
            refreshEngineIfRunning(context)
        }
    }

    fun removeCustomUpstream(context: Context, serverId: String) {
        customUpstreams = customUpstreams.filterNot { it.id == serverId }
        _upstreams.value = DnsUpstreamServer.PRESETS + customUpstreams
        DnsModePreferences.saveCustomUpstreams(context, customUpstreams)
        // Deleting the selected custom server falls back to the first preset.
        if (_config.value.selectedUpstreamId == serverId) {
            selectUpstream(context, DnsUpstreamServer.PRESETS.first().id)
        }
    }

    fun updateConfig(context: Context, newConfig: DnsModeConfig) {
        _config.value = newConfig
        DnsModePreferences.saveConfig(context, newConfig)
        refreshEngineIfRunning(context)
    }

    private fun refreshEngineIfRunning(context: Context) {
        if (!_status.value.isRunning) return
        try {
            context.startService(DnsModeService.refreshIntent(context))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to deliver config refresh to DnsModeService", e)
        }
    }

    fun resetStats(context: Context? = appContext) {
        _stats.value = DnsModeStats()
        val targetContext = context ?: appContext
        if (targetContext != null) {
            DnsModePreferences.clearStats(targetContext)
        }
    }

    fun flushStats(context: Context? = null) {
        val targetContext = context ?: appContext ?: return
        DnsModePreferences.saveStats(targetContext, _stats.value)
    }

    fun recordQuery(cacheHit: Boolean, blocked: Boolean, failed: Boolean, latencyMs: Long) {
        _stats.update { current ->
            val newCount = current.queryCount + 1
            val newFailed = if (failed) current.failedCount + 1 else current.failedCount
            // SERVFAIL timeouts (up to 10s) would dominate the average, so the
            // reported latency only covers queries that produced an answer.
            val newTotal = if (failed) current.latencyTotalMs else current.latencyTotalMs + latencyMs
            val resolvedCount = (newCount - newFailed).coerceAtLeast(1L)
            current.copy(
                queryCount = newCount,
                cacheHitCount = if (cacheHit) current.cacheHitCount + 1 else current.cacheHitCount,
                blockedCount = if (blocked) current.blockedCount + 1 else current.blockedCount,
                failedCount = newFailed,
                latencyTotalMs = newTotal,
                latencyMs = newTotal / resolvedCount
            )
        }
    }

    private fun startStatsTicker() {
        statsJob?.cancel()
        statsJob = scope.launch {
            var ticks = 0
            while (isActive) {
                delay(1000L)
                // Atomic update: a read-then-write here would clobber counts
                // recorded by recordQuery between the two steps.
                _stats.update { it.copy(uptimeSeconds = it.uptimeSeconds + 1) }
                ticks++
                if (ticks % 5 == 0) {
                    flushStats()
                }
            }
        }
    }

    private fun stopStatsTicker() {
        statsJob?.cancel()
        statsJob = null
    }
}
