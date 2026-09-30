package com.haoze.diting.dnsmode.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.dnsmode.model.DnsModeConfig
import com.haoze.diting.dnsmode.model.DnsModeStats
import com.haoze.diting.dnsmode.model.DnsServiceStatus
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

data class DnsModeUiState(
    val status: DnsServiceStatus = DnsServiceStatus.STOPPED,
    val config: DnsModeConfig = DnsModeConfig(),
    val stats: DnsModeStats = DnsModeStats(),
    val upstreams: List<DnsUpstreamServer> = DnsUpstreamServer.PRESETS,
    val activeUpstream: DnsUpstreamServer = DnsUpstreamServer.PRESETS.first()
)

class DnsMainViewModel(application: Application) : AndroidViewModel(application) {

    init {
        DnsModeManager.initialize(application)
    }

    val status: StateFlow<DnsServiceStatus> = DnsModeManager.status
    val config: StateFlow<DnsModeConfig> = DnsModeManager.config
    val stats: StateFlow<DnsModeStats> = DnsModeManager.stats
    val upstreams: StateFlow<List<DnsUpstreamServer>> = DnsModeManager.upstreams

    val uiState: StateFlow<DnsModeUiState> = combine(
        status,
        config,
        stats,
        upstreams
    ) { currentStatus, currentConfig, currentStats, currentUpstreams ->
        val active = currentUpstreams.firstOrNull { it.id == currentConfig.selectedUpstreamId }
            ?: currentUpstreams.firstOrNull()
            ?: DnsUpstreamServer.PRESETS.first()
        DnsModeUiState(
            status = currentStatus,
            config = currentConfig,
            stats = currentStats,
            upstreams = currentUpstreams,
            activeUpstream = active
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = DnsModeUiState()
    )

    fun toggleService() {
        DnsModeManager.toggleService(getApplication())
    }

    fun selectUpstream(serverId: String) {
        DnsModeManager.selectUpstream(getApplication(), serverId)
    }

    fun updateConfig(newConfig: DnsModeConfig) {
        DnsModeManager.updateConfig(getApplication(), newConfig)
    }

    fun resetStats() {
        DnsModeManager.resetStats()
    }
}
