package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.vpn.BootstrapHealthEngine
import com.haoze.dnssr.vpn.BootstrapLogger
import com.haoze.dnssr.vpn.BootstrapSelector
import com.haoze.dnssr.vpn.DnsLatencyTester
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.ProviderHealthEngine
import com.haoze.dnssr.vpn.ProviderHealthSnapshot
import com.haoze.dnssr.vpn.ProviderHealthStore
import com.haoze.dnssr.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

class RaceModeSettingsViewModel(application: Application) : AndroidViewModel(application) {
    private val bootstrapHealthEngine = BootstrapHealthEngine(application, viewModelScope)
    private val bootstrapLogger = BootstrapLogger(
        AppDatabase.getInstance(application).bootstrapLogDao(),
        AppSettings.logRetentionDays(application)
    )
    private val bootstrapSelector = BootstrapSelector(
        context = application,
        healthEngine = bootstrapHealthEngine,
        logger = bootstrapLogger
    )

    private val _providers = MutableStateFlow<List<DnsProvider>>(emptyList())
    val providers: StateFlow<List<DnsProvider>> = _providers.asStateFlow()

    private val _healthByProvider = MutableStateFlow<Map<String, ProviderHealthSnapshot>>(emptyMap())
    val healthByProvider: StateFlow<Map<String, ProviderHealthSnapshot>> = _healthByProvider.asStateFlow()

    private val _selectedIds = MutableStateFlow<Set<String>>(emptySet())
    val selectedIds: StateFlow<Set<String>> = _selectedIds.asStateFlow()

    private val _latencyTestSelectedIds = MutableStateFlow<Set<String>>(emptySet())
    val latencyTestSelectedIds: StateFlow<Set<String>> = _latencyTestSelectedIds.asStateFlow()

    private val _raceModeEnabled = MutableStateFlow(false)
    val raceModeEnabled: StateFlow<Boolean> = _raceModeEnabled.asStateFlow()

    private val _raceModeStrategy = MutableStateFlow(RaceModeStrategy.SMART_PREDICTION)
    val raceModeStrategy: StateFlow<RaceModeStrategy> = _raceModeStrategy.asStateFlow()

    private val _resolutionMode = MutableStateFlow(DnsResolutionMode.SINGLE)
    val resolutionMode: StateFlow<DnsResolutionMode> = _resolutionMode.asStateFlow()

    private val _goTunnelRequired = MutableStateFlow(false)
    val goTunnelRequired: StateFlow<Boolean> = _goTunnelRequired.asStateFlow()

    private val _presetDnsService = MutableStateFlow(PresetDnsService.DNS)
    val presetDnsService: StateFlow<PresetDnsService> = _presetDnsService.asStateFlow()

    private val _primaryBackupIds = MutableStateFlow<List<String>>(emptyList())
    val primaryBackupIds: StateFlow<List<String>> = _primaryBackupIds.asStateFlow()

    private val _smartPredictionIds = MutableStateFlow<Set<String>>(emptySet())
    val smartPredictionIds: StateFlow<Set<String>> = _smartPredictionIds.asStateFlow()

    private val _parallelRaceIds = MutableStateFlow<Set<String>>(emptySet())
    val parallelRaceIds: StateFlow<Set<String>> = _parallelRaceIds.asStateFlow()

    private val _singleProviderId = MutableStateFlow("")
    val singleProviderId: StateFlow<String> = _singleProviderId.asStateFlow()

    private val _testDomain = MutableStateFlow("")
    val testDomain: StateFlow<String> = _testDomain.asStateFlow()

    private val _isTesting = MutableStateFlow(false)
    val isTesting: StateFlow<Boolean> = _isTesting.asStateFlow()

    private val _results = MutableStateFlow<List<DnsLatencyTester.Result>>(emptyList())
    val results: StateFlow<List<DnsLatencyTester.Result>> = _results.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _initialLoading = MutableStateFlow(true)
    val initialLoading: StateFlow<Boolean> = _initialLoading.asStateFlow()

    private var activated = false

    fun activate() {
        if (!activated) {
            activated = true
            load()
        }
    }

    fun load() {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            ProviderHealthEngine.flushActive(commit = true)
            val all = DnsProvider.loadRuntimeProviders(context)
            val health = ProviderHealthStore.loadAll(context)
            val ids = DnsProvider.loadRaceProviderIds(context)
            val latencyIds = DnsProvider.loadLatencyTestProviderIds(context)
            val domain = AppSettings.getRaceTestDomain(context)
            val raceModeEnabled = AppSettings.isRaceModeEnabled(context)
            val strategy = AppSettings.getRaceModeStrategy(context)
            val resolutionMode = AppSettings.getDnsResolutionMode(context)
            val presetDnsService = AppSettings.getPresetDnsService(context)
            val primaryBackupIds = AppSettings.getPrimaryBackupProviderIds(context)
                .filter { id -> all.any { it.id == id } }
            val smartIds = AppSettings.getSmartPredictionProviderIds(context).filterTo(mutableSetOf()) { id -> all.any { it.id == id } }
            val parallelIds = AppSettings.getParallelRaceProviderIds(context).filterTo(mutableSetOf()) { id -> all.any { it.id == id } }
            withContext(Dispatchers.Main) {
                _providers.value = all
                _healthByProvider.value = health
                _selectedIds.value = ids
                _latencyTestSelectedIds.value = latencyIds
                _raceModeEnabled.value = raceModeEnabled
                _raceModeStrategy.value = strategy
                _resolutionMode.value = resolutionMode
                _goTunnelRequired.value = AppSettings.isGoTunnelRequired(context)
                _presetDnsService.value = presetDnsService
                _primaryBackupIds.value = primaryBackupIds
                _smartPredictionIds.value = smartIds
                _parallelRaceIds.value = parallelIds
                _singleProviderId.value = DnsProvider.loadSelected(context).id
                _testDomain.value = domain
                _results.value = emptyList()
                _initialLoading.value = false
            }
        }
    }

    fun toggleProvider(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val updated = _selectedIds.value.toMutableSet().apply {
                if (contains(id)) remove(id) else add(id)
            }
            DnsProvider.saveRaceProviderIds(context, updated)
            val ordered = _primaryBackupIds.value.toMutableList().apply {
                if (id in updated && id !in this) add(id) else if (id !in updated) remove(id)
            }
            AppSettings.setPrimaryBackupProviderIds(context, ordered)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "race_providers_changed")
            withContext(Dispatchers.Main) {
                _selectedIds.value = updated
                _primaryBackupIds.value = ordered
            }
        }
    }

    fun toggleLatencyTestProvider(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val updated = _latencyTestSelectedIds.value.toMutableSet().apply {
                if (contains(id)) remove(id) else add(id)
            }
            DnsProvider.saveLatencyTestProviderIds(context, updated)
            withContext(Dispatchers.Main) {
                _latencyTestSelectedIds.value = updated
            }
        }
    }

    fun setRaceModeStrategy(strategy: RaceModeStrategy): Boolean {
        if (_raceModeStrategy.value == strategy) return false
        val context = getApplication<Application>()
        AppSettings.setRaceModeStrategy(context, strategy)
        _raceModeStrategy.value = strategy
        return true
    }

    fun setResolutionMode(mode: DnsResolutionMode): Boolean {
        if (_resolutionMode.value == mode) return false
        if (_goTunnelRequired.value && !isGoTunnelCompatible(mode)) {
            _message.value = getApplication<Application>().getString(R.string.go_tunnel_mode_restriction)
            return false
        }
        if (!isModeValid(mode)) {
            _message.value = getApplication<Application>().getString(R.string.resolution_mode_requires_two_providers)
            if (mode == DnsResolutionMode.PRIMARY_BACKUP) _message.value = getApplication<Application>().getString(R.string.primary_backup_requires_two_providers)
            return false
        }
        val context = getApplication<Application>()
        AppSettings.setDnsResolutionMode(context, mode)
        _resolutionMode.value = mode
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, "resolution_mode_changed")
        _message.value = getApplication<Application>().getString(
            R.string.resolution_mode_changed,
            localizedText(getApplication<Application>(), mode.displayName)
        )
        return true
    }

    fun isModeEnabled(mode: DnsResolutionMode): Boolean =
        !_goTunnelRequired.value || isGoTunnelCompatible(mode)

    private fun isGoTunnelCompatible(mode: DnsResolutionMode): Boolean =
        mode == DnsResolutionMode.SINGLE || mode == DnsResolutionMode.PRIMARY_BACKUP

    fun isModeValid(mode: DnsResolutionMode): Boolean = when (mode) {
        DnsResolutionMode.SINGLE -> _providers.value.any { it.id == _singleProviderId.value }
        DnsResolutionMode.SMART_PREDICTION -> _smartPredictionIds.value.size >= 2
        DnsResolutionMode.PARALLEL_RACE -> _parallelRaceIds.value.size >= 2
        DnsResolutionMode.PRIMARY_BACKUP -> _primaryBackupIds.value.size >= 2
    }

    fun selectSingleProvider(id: String) {
        if (_providers.value.none { it.id == id }) return
        val context = getApplication<Application>()
        DnsProvider.saveSelected(context, id)
        _singleProviderId.value = id
        if (_resolutionMode.value == DnsResolutionMode.SINGLE) RuntimeDnsSettingsRefresher.refreshIfRunning(context, "single_provider_changed")
    }

    fun toggleModeProvider(mode: DnsResolutionMode, id: String) {
        val context = getApplication<Application>()
        when (mode) {
            DnsResolutionMode.SMART_PREDICTION -> {
                val updated = toggle(_smartPredictionIds.value, id)
                AppSettings.setSmartPredictionProviderIds(context, updated)
                _smartPredictionIds.value = updated
            }
            DnsResolutionMode.PARALLEL_RACE -> {
                val updated = toggle(_parallelRaceIds.value, id)
                AppSettings.setParallelRaceProviderIds(context, updated)
                _parallelRaceIds.value = updated
            }
            DnsResolutionMode.PRIMARY_BACKUP -> {
                val updated = _primaryBackupIds.value.toMutableList().apply { if (!remove(id)) add(id) }
                AppSettings.setPrimaryBackupProviderIds(context, updated)
                _primaryBackupIds.value = updated
            }
            DnsResolutionMode.SINGLE -> return
        }
        if (_resolutionMode.value == mode) RuntimeDnsSettingsRefresher.refreshIfRunning(context, "resolution_mode_providers_changed")
    }

    private fun toggle(ids: Set<String>, id: String): Set<String> = ids.toMutableSet().apply {
        if (!remove(id)) add(id)
    }

    fun movePrimaryBackupProvider(id: String, direction: Int) {
        val from = _primaryBackupIds.value.indexOf(id)
        if (from < 0) return
        reorderPrimaryBackupProvider(id, from + direction)
    }

    fun setPresetDnsService(service: PresetDnsService) {
        if (_presetDnsService.value == service) return
        val context = getApplication<Application>()
        val targetProtocol = when (service) {
            PresetDnsService.DNS -> DnsProtocol.DNS
            PresetDnsService.DOT -> DnsProtocol.DOT
            PresetDnsService.DOH -> DnsProtocol.DOH
        }
        fun remap(id: String): String = DnsProvider.presetIdForProtocol(id, targetProtocol) ?: id

        DnsProvider.saveSelected(context, remap(_singleProviderId.value))
        val smartIds = _smartPredictionIds.value.mapTo(linkedSetOf(), ::remap)
        AppSettings.setSmartPredictionProviderIds(context, smartIds)
        val parallelIds = _parallelRaceIds.value.mapTo(linkedSetOf(), ::remap)
        AppSettings.setParallelRaceProviderIds(context, parallelIds)
        val primaryBackupIds = _primaryBackupIds.value.map(::remap).distinct()
        AppSettings.setPrimaryBackupProviderIds(context, primaryBackupIds)
        AppSettings.setPresetDnsService(context, service)

        _singleProviderId.value = remap(_singleProviderId.value)
        _smartPredictionIds.value = smartIds
        _parallelRaceIds.value = parallelIds
        _primaryBackupIds.value = primaryBackupIds
        _presetDnsService.value = service
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, "preset_dns_service_changed")
    }

    fun reorderPrimaryBackupProvider(id: String, targetIndex: Int) {
        val current = _primaryBackupIds.value.toMutableList()
        val from = current.indexOf(id)
        if (from < 0 || targetIndex !in current.indices || from == targetIndex) return
        current.add(targetIndex, current.removeAt(from))
        val context = getApplication<Application>()
        AppSettings.setPrimaryBackupProviderIds(context, current)
        _primaryBackupIds.value = current
        if (_resolutionMode.value == DnsResolutionMode.PRIMARY_BACKUP) RuntimeDnsSettingsRefresher.refreshIfRunning(context, "primary_backup_order_changed")
    }

    fun setTestDomain(domain: String) {
        _testDomain.value = domain
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            AppSettings.setRaceTestDomain(context, domain)
        }
    }

    fun setRaceModeEnabled(enabled: Boolean): Boolean {
        val context = getApplication<Application>()
        if (enabled && _selectedIds.value.size < 2) {
            _message.value = getApplication<Application>().getString(R.string.race_mode_requires_two_providers)
            return false
        }
        AppSettings.setRaceModeEnabled(context, enabled)
        _raceModeEnabled.value = enabled
        _message.value = getApplication<Application>().getString(if (enabled) R.string.race_mode_enabled else R.string.race_mode_disabled)
        return true
    }

    fun runLatencyTest() {
        val context = getApplication<Application>()
        val domain = _testDomain.value.trim().takeIf { it.isNotEmpty() }
            ?: AppSettings.getRaceTestDomain(context)
        val selected = _providers.value.filter { it.id in _latencyTestSelectedIds.value }
        if (selected.isEmpty()) {
            _message.value = getApplication<Application>().getString(R.string.select_latency_test_providers)
            return
        }

        viewModelScope.launch(Dispatchers.IO) {
            _isTesting.value = true
            _results.value = emptyList()
            val deferreds = selected.map { provider ->
                async {
                    DnsLatencyTester.testAverage(
                        context = context,
                        provider = provider,
                        domain = domain,
                        attempts = LATENCY_TEST_ATTEMPTS,
                        bootstrapSelector = bootstrapSelector
                    )
                }
            }
            val testResults = deferreds.map { it.await() }
                .sortedWith(
                    compareBy<DnsLatencyTester.Result> { if (it.success) 0 else 1 }
                        .thenBy { if (it.success) it.elapsedMs else Long.MAX_VALUE }
                        .thenByDescending { it.successCount }
                        .thenBy { it.providerName }
                )
            bootstrapLogger.flush()
            withContext(Dispatchers.Main) {
                _results.value = testResults
                _isTesting.value = false
            }
        }
    }

    fun resetSelectedProviderWeights() {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val providerIds = _selectedIds.value.ifEmpty {
                _providers.value.map { it.id }.toSet()
            }
            ProviderHealthStore.reset(context, providerIds)
            ProviderHealthEngine.flushActive(commit = true)
            val health = ProviderHealthStore.loadAll(context)
            withContext(Dispatchers.Main) {
                _healthByProvider.value = health
        _message.value = getApplication<Application>().getString(R.string.health_weights_reset)
            }
        }
    }

    fun clearMessage() {
        _message.value = null
    }

    override fun onCleared() {
        bootstrapHealthEngine.close()
        runBlocking {
            bootstrapLogger.flush()
        }
        super.onCleared()
    }

    private companion object {
        const val LATENCY_TEST_ATTEMPTS = 3
    }
}
