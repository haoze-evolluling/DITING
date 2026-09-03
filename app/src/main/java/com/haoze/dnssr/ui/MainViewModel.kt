package com.haoze.dnssr.ui

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.DnsVpnService
import com.haoze.dnssr.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class MainUiState(
    val isRunning: Boolean = false,
    val isBusy: Boolean = false
)

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(MainUiState())
    val uiState: StateFlow<MainUiState> = _uiState.asStateFlow()

    private val _providers = MutableStateFlow<List<DnsProvider>>(emptyList())
    val providers: StateFlow<List<DnsProvider>> = _providers.asStateFlow()

    private val _selectedProvider = MutableStateFlow<DnsProvider?>(null)
    val selectedProvider: StateFlow<DnsProvider?> = _selectedProvider.asStateFlow()

    private val _raceProviderIds = MutableStateFlow<Set<String>>(emptySet())
    val raceProviderIds: StateFlow<Set<String>> = _raceProviderIds.asStateFlow()

    private val _resolutionMode = MutableStateFlow(DnsResolutionMode.SINGLE)
    val resolutionMode: StateFlow<DnsResolutionMode> = _resolutionMode.asStateFlow()

    private val _homeProviderVisibility = MutableStateFlow(HomeProviderVisibility())
    val homeProviderVisibility: StateFlow<HomeProviderVisibility> = _homeProviderVisibility.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == DnsVpnService.ACTION_VPN_STATUS_CHANGED) {
                val running = intent.getBooleanExtra(DnsVpnService.EXTRA_VPN_RUNNING, false)
                _uiState.value = _uiState.value.copy(isRunning = running, isBusy = false)
            }
        }
    }

    init {
        refreshStatus()
        loadProviders()
        ContextCompat.registerReceiver(
            application,
            statusReceiver,
            IntentFilter(DnsVpnService.ACTION_VPN_STATUS_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    fun refreshStatus(onComplete: ((Boolean) -> Unit)? = null) {
        val context = getApplication<Application>()
        val isAlive = DnsVpnService.isRunning(context)
        DnsVpnService.setRunningFlag(context, isAlive)
        _uiState.value = _uiState.value.copy(isRunning = isAlive, isBusy = false)
        onComplete?.invoke(isAlive)
    }

    fun loadProviders() {
        val context = getApplication<Application>()
        _providers.value = DnsProvider.loadRuntimeProviders(context)
        _selectedProvider.value = DnsProvider.loadSelected(context)
        val mode = AppSettings.getDnsResolutionMode(context)
        _resolutionMode.value = mode
        _raceProviderIds.value = when (mode) {
            DnsResolutionMode.SINGLE -> emptySet()
            DnsResolutionMode.SMART_PREDICTION -> AppSettings.getSmartPredictionProviderIds(context)
            DnsResolutionMode.PARALLEL_RACE -> AppSettings.getParallelRaceProviderIds(context)
            DnsResolutionMode.PRIMARY_BACKUP -> AppSettings.getPrimaryBackupProviderIds(context).toSet()
        }.intersect(_providers.value.map { it.id }.toSet())
        _homeProviderVisibility.value = AppSettings.getHomeProviderVisibility(context)
    }

    fun selectProvider(id: String) {
        val context = getApplication<Application>()
        DnsProvider.saveSelected(context, id)
        _selectedProvider.value = DnsProvider.loadSelected(context)
        refreshRuntimeConfigIfRunning("main_provider_changed")
    }

    fun restartVpnAfterSettingsChange() {
        refreshRuntimeConfigIfRunning("settings_changed")
    }

    fun refreshRuntimeConfigIfRunning(reason: String = "settings_changed") {
        val context = getApplication<Application>()
        refreshStatus { isRunning ->
            if (isRunning) {
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, reason)
            }
        }
    }

    fun clearMessage() {
        _message.value = null
    }

    private fun startVpnWithSelectedProvider() {
        val context = getApplication<Application>()
        // 由 DnsVpnService 自行读取当前选中的单个 provider 或竞速列表
        androidx.core.content.ContextCompat.startForegroundService(
            context,
            DnsVpnService.startIntent(context)
        )
    }

    fun toggleVpn() {
        val context = getApplication<Application>()
        val currentlyRunning = _uiState.value.isRunning
        _uiState.value = _uiState.value.copy(isBusy = true)

        if (currentlyRunning) {
            context.startService(DnsVpnService.stopIntent(context))
        } else {
            androidx.core.content.ContextCompat.startForegroundService(
                context,
                DnsVpnService.startIntent(context)
            )
            viewModelScope.launch {
                delay(3000)
                refreshStatus()
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        getApplication<Application>().unregisterReceiver(statusReceiver)
    }
}
