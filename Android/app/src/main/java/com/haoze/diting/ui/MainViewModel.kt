package com.haoze.diting.ui

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.express.ExpressVpnController
import com.haoze.diting.express.ExpressVpnIntents
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore
import com.haoze.diting.ui.settings.ResolutionSettingsStore
import com.haoze.diting.core.dns.DnsProvider
import com.haoze.diting.normal.DnsVpnService
import com.haoze.diting.R
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
            when (intent?.action) {
                DnsVpnService.ACTION_VPN_STATUS_CHANGED -> {
                    val running = intent.getBooleanExtra(DnsVpnService.EXTRA_VPN_RUNNING, false)
                    _uiState.value = _uiState.value.copy(isRunning = running, isBusy = false)
                }
                ExpressVpnIntents.ACTION_STATUS_CHANGED -> {
                    val running = intent.getBooleanExtra(ExpressVpnIntents.EXTRA_RUNNING, false)
                    _uiState.value = _uiState.value.copy(isRunning = running, isBusy = false)
                }
            }
        }
    }

    init {
        refreshStatus()
        loadProviders()
        val filter = IntentFilter(DnsVpnService.ACTION_VPN_STATUS_CHANGED).apply {
            addAction(ExpressVpnIntents.ACTION_STATUS_CHANGED)
        }
        ContextCompat.registerReceiver(
            application,
            statusReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    private fun currentDataset(): RuleDataset {
        return if (WorkModeStore.getAppWorkMode(getApplication()) == AppWorkMode.EXPRESS) {
            RuleDataset.EXPRESS
        } else {
            RuleDataset.NORMAL
        }
    }

    fun refreshStatus(onComplete: ((Boolean) -> Unit)? = null) {
        val context = getApplication<Application>()
        val isExpress = WorkModeStore.getAppWorkMode(context) == AppWorkMode.EXPRESS
        val isAlive = if (isExpress) {
            ExpressVpnController.isRunning(context)
        } else {
            val alive = DnsVpnService.isRunning(context)
            DnsVpnService.setRunningFlag(context, alive)
            alive
        }
        _uiState.value = _uiState.value.copy(isRunning = isAlive, isBusy = false)
        onComplete?.invoke(isAlive)
    }

    fun loadProviders() {
        val context = getApplication<Application>()
        val dataset = currentDataset()
        _providers.value = DnsProvider.loadRuntimeProviders(context, dataset)
        _selectedProvider.value = DnsProvider.loadSelected(context, dataset)
        val mode = ResolutionSettingsStore.getDnsResolutionMode(context, dataset)
        _resolutionMode.value = mode
        _raceProviderIds.value = when (mode) {
            DnsResolutionMode.SINGLE -> emptySet()
            DnsResolutionMode.SMART_PREDICTION -> ResolutionSettingsStore.getSmartPredictionProviderIds(context, dataset)
            DnsResolutionMode.PARALLEL_RACE -> ResolutionSettingsStore.getParallelRaceProviderIds(context, dataset)
            DnsResolutionMode.PRIMARY_BACKUP -> ResolutionSettingsStore.getPrimaryBackupProviderIds(context, dataset).toSet()
        }.intersect(_providers.value.map { it.id }.toSet())
        _homeProviderVisibility.value = ResolutionSettingsStore.getHomeProviderVisibility(context, dataset)
    }

    fun selectProvider(id: String) {
        val context = getApplication<Application>()
        val dataset = currentDataset()
        DnsProvider.saveSelected(context, id, dataset)
        _selectedProvider.value = DnsProvider.loadSelected(context, dataset)
        refreshRuntimeConfigIfRunning("main_provider_changed")
    }

    /** Toggles participating providers for the home multi-select dialog in non-single modes; shares the same persisted data as the mode config screen. */
    fun toggleModeProvider(mode: DnsResolutionMode, id: String) {
        if (mode == DnsResolutionMode.SINGLE) return
        val context = getApplication<Application>()
        val dataset = currentDataset()
        val current = _raceProviderIds.value
        when (mode) {
            DnsResolutionMode.SINGLE -> return
            DnsResolutionMode.SMART_PREDICTION -> {
                val updated = current.toMutableSet().apply { if (!remove(id)) add(id) }
                ResolutionSettingsStore.setSmartPredictionProviderIds(context, updated, dataset)
                _raceProviderIds.value = updated
            }
            DnsResolutionMode.PARALLEL_RACE -> {
                val updated = current.toMutableSet().apply { if (!remove(id)) add(id) }
                ResolutionSettingsStore.setParallelRaceProviderIds(context, updated, dataset)
                _raceProviderIds.value = updated
            }
            DnsResolutionMode.PRIMARY_BACKUP -> {
                val updated = current.toMutableList().apply { if (!remove(id)) add(id) }
                ResolutionSettingsStore.setPrimaryBackupProviderIds(context, updated, dataset)
                _raceProviderIds.value = updated.toSet()
            }
        }
        if (_resolutionMode.value == mode) {
            refreshRuntimeConfigIfRunning("resolution_mode_providers_changed")
        }
    }

    fun refreshRuntimeConfigIfRunning(reason: String = "settings_changed") {
        val context = getApplication<Application>()
        val dataset = currentDataset()
        refreshStatus { isRunning ->
            if (isRunning) {
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, reason, dataset = dataset)
            }
        }
    }

    fun clearMessage() {
        _message.value = null
    }

    fun toggleVpn() {
        val context = getApplication<Application>()
        val isExpress = WorkModeStore.getAppWorkMode(context) == AppWorkMode.EXPRESS
        if (isExpress) {
            _uiState.value = _uiState.value.copy(isBusy = true)
            ExpressVpnController.toggle(context)
            viewModelScope.launch {
                delay(1000)
                refreshStatus()
            }
            return
        }
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

