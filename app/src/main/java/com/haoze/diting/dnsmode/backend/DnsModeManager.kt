package com.haoze.diting.dnsmode.backend

import android.content.Context
import androidx.core.content.ContextCompat
import com.haoze.diting.dnsmode.model.DnsModeConfig
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
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

object DnsModeManager {
    private val scope = CoroutineScope(Dispatchers.Default)
    private var statsJob: Job? = null

    private val _status = MutableStateFlow(DnsServiceStatus.STOPPED)
    val status: StateFlow<DnsServiceStatus> = _status.asStateFlow()

    private val _config = MutableStateFlow(DnsModeConfig())
    val config: StateFlow<DnsModeConfig> = _config.asStateFlow()

    private val _stats = MutableStateFlow(DnsModeStats())
    val stats: StateFlow<DnsModeStats> = _stats.asStateFlow()

    private val _upstreams = MutableStateFlow(DnsUpstreamServer.PRESETS)
    val upstreams: StateFlow<List<DnsUpstreamServer>> = _upstreams.asStateFlow()

    private var initialized = false

    fun initialize(context: Context) {
        if (initialized) return
        initialized = true
        val loadedConfig = DnsModePreferences.loadConfig(context)
        _config.value = loadedConfig
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
            DnsModePreferences.setServiceActive(context, false)
        }
    }

    fun stopService(context: Context) {
        if (_status.value == DnsServiceStatus.STOPPED || _status.value == DnsServiceStatus.STOPPING) return
        _status.value = DnsServiceStatus.STOPPING
        DnsModePreferences.setServiceActive(context, false)
        try {
            context.startService(DnsModeService.stopIntent(context))
        } catch (e: Exception) {
            _status.value = DnsServiceStatus.STOPPED
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
        startStatsTicker()
    }

    fun onServiceStopped() {
        _status.value = DnsServiceStatus.STOPPED
        stopStatsTicker()
    }

    fun onServiceError() {
        _status.value = DnsServiceStatus.ERROR
        stopStatsTicker()
    }

    fun selectUpstream(context: Context, serverId: String) {
        val updated = _config.value.copy(selectedUpstreamId = serverId)
        _config.value = updated
        DnsModePreferences.saveConfig(context, updated)
        if (_status.value.isRunning) {
            try {
                context.startService(DnsModeService.refreshIntent(context))
            } catch (_: Exception) {}
        }
    }

    fun updateConfig(context: Context, newConfig: DnsModeConfig) {
        _config.value = newConfig
        DnsModePreferences.saveConfig(context, newConfig)
    }

    fun resetStats() {
        _stats.value = DnsModeStats()
    }

    fun recordQuery(cacheHit: Boolean = false, blocked: Boolean = false, latencyMs: Long = 12L) {
        val current = _stats.value
        _stats.value = current.copy(
            queryCount = current.queryCount + 1,
            cacheHitCount = if (cacheHit) current.cacheHitCount + 1 else current.cacheHitCount,
            blockedCount = if (blocked) current.blockedCount + 1 else current.blockedCount,
            latencyMs = latencyMs
        )
    }

    private fun startStatsTicker() {
        statsJob?.cancel()
        statsJob = scope.launch {
            while (isActive) {
                delay(1000L)
                val current = _stats.value
                _stats.value = current.copy(uptimeSeconds = current.uptimeSeconds + 1)
            }
        }
    }

    private fun stopStatsTicker() {
        statsJob?.cancel()
        statsJob = null
    }
}
