package com.haoze.diting.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.ui.settings.ResolutionSettingsStore
import com.haoze.diting.vpn.BootstrapHealthEngine
import com.haoze.diting.vpn.BootstrapLogger
import com.haoze.diting.vpn.BootstrapSelector
import com.haoze.diting.vpn.DnsLatencyTester
import com.haoze.diting.vpn.DnsProvider
import com.haoze.diting.vpn.DnsProtocol
import com.haoze.diting.vpn.ProviderHealthEngine
import com.haoze.diting.vpn.ProviderHealthSnapshot
import com.haoze.diting.vpn.ProviderHealthStore
import com.haoze.diting.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.RuleDatabases

class RaceModeSettingsViewModel @JvmOverloads constructor(
    application: Application,
    val dataset: RuleDataset = RuleDataset.NORMAL
) : AndroidViewModel(application) {

    class Factory(
        private val application: Application,
        private val dataset: RuleDataset = RuleDataset.NORMAL
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return RaceModeSettingsViewModel(application, dataset) as T
        }
    }

    private val bootstrapHealthEngine = BootstrapHealthEngine(application, viewModelScope)
    private val bootstrapLogger = BootstrapLogger(
        RuleDatabases.runtimeForDataset(application, dataset).bootstrapLogDao()
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

    private val _latencyTestSelectedIds = MutableStateFlow<Set<String>>(emptySet())
    val latencyTestSelectedIds: StateFlow<Set<String>> = _latencyTestSelectedIds.asStateFlow()

    private val _resolutionMode = MutableStateFlow(DnsResolutionMode.SINGLE)
    val resolutionMode: StateFlow<DnsResolutionMode> = _resolutionMode.asStateFlow()

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
            val all = DnsProvider.loadRuntimeProviders(context, dataset)
            val health = ProviderHealthStore.loadAll(context)
            val latencyIds = DnsProvider.loadLatencyTestProviderIds(context, dataset)
            val domain = ResolutionSettingsStore.getRaceTestDomain(context, dataset)
            val resolutionMode = ResolutionSettingsStore.getDnsResolutionMode(context, dataset)
            val presetDnsService = ResolutionSettingsStore.getPresetDnsService(context, dataset)
            val primaryBackupIds = ResolutionSettingsStore.getPrimaryBackupProviderIds(context, dataset)
                .filter { id -> all.any { it.id == id } }
            val smartIds = ResolutionSettingsStore.getSmartPredictionProviderIds(context, dataset).filterTo(mutableSetOf()) { id -> all.any { it.id == id } }
            val parallelIds = ResolutionSettingsStore.getParallelRaceProviderIds(context, dataset).filterTo(mutableSetOf()) { id -> all.any { it.id == id } }
            withContext(Dispatchers.Main) {
                _providers.value = all
                _healthByProvider.value = health
                _latencyTestSelectedIds.value = latencyIds
                _resolutionMode.value = resolutionMode
                _presetDnsService.value = presetDnsService
                _primaryBackupIds.value = primaryBackupIds
                _smartPredictionIds.value = smartIds
                _parallelRaceIds.value = parallelIds
                _singleProviderId.value = DnsProvider.loadSelected(context, dataset).id
                _testDomain.value = domain
                _results.value = emptyList()
                _initialLoading.value = false
            }
        }
    }

    fun toggleLatencyTestProvider(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val updated = _latencyTestSelectedIds.value.toMutableSet().apply {
                if (contains(id)) remove(id) else add(id)
            }
            DnsProvider.saveLatencyTestProviderIds(context, updated, dataset)
            withContext(Dispatchers.Main) {
                _latencyTestSelectedIds.value = updated
            }
        }
    }

    fun setResolutionMode(mode: DnsResolutionMode): Boolean {
        if (_resolutionMode.value == mode) return false
        if (!isModeValid(mode)) {
            _message.value = getApplication<Application>().getString(R.string.resolution_mode_requires_two_providers)
            if (mode == DnsResolutionMode.PRIMARY_BACKUP) _message.value = getApplication<Application>().getString(R.string.primary_backup_requires_two_providers)
            return false
        }
        val context = getApplication<Application>()
        ResolutionSettingsStore.setDnsResolutionMode(context, mode, dataset)
        _resolutionMode.value = mode
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, "resolution_mode_changed", dataset = dataset)
        _message.value = getApplication<Application>().getString(
            R.string.resolution_mode_changed,
            localizedText(getApplication<Application>(), mode.displayName)
        )
        return true
    }

    fun isModeEnabled(mode: DnsResolutionMode): Boolean = true

    fun isModeValid(mode: DnsResolutionMode): Boolean = when (mode) {
        DnsResolutionMode.SINGLE -> _providers.value.any { it.id == _singleProviderId.value }
        DnsResolutionMode.SMART_PREDICTION -> _smartPredictionIds.value.size >= 2
        DnsResolutionMode.PARALLEL_RACE -> _parallelRaceIds.value.size >= 2
        DnsResolutionMode.PRIMARY_BACKUP -> _primaryBackupIds.value.size >= 2
    }

    fun selectSingleProvider(id: String) {
        if (_providers.value.none { it.id == id }) return
        val context = getApplication<Application>()
        DnsProvider.saveSelected(context, id, dataset)
        _singleProviderId.value = id
        if (_resolutionMode.value == DnsResolutionMode.SINGLE) RuntimeDnsSettingsRefresher.refreshIfRunning(context, "single_provider_changed", dataset = dataset)
    }

    fun toggleModeProvider(mode: DnsResolutionMode, id: String) {
        val context = getApplication<Application>()
        when (mode) {
            DnsResolutionMode.SMART_PREDICTION -> {
                val updated = toggle(_smartPredictionIds.value, id)
                ResolutionSettingsStore.setSmartPredictionProviderIds(context, updated, dataset)
                _smartPredictionIds.value = updated
            }
            DnsResolutionMode.PARALLEL_RACE -> {
                val updated = toggle(_parallelRaceIds.value, id)
                ResolutionSettingsStore.setParallelRaceProviderIds(context, updated, dataset)
                _parallelRaceIds.value = updated
            }
            DnsResolutionMode.PRIMARY_BACKUP -> {
                val updated = _primaryBackupIds.value.toMutableList().apply { if (!remove(id)) add(id) }
                ResolutionSettingsStore.setPrimaryBackupProviderIds(context, updated, dataset)
                _primaryBackupIds.value = updated
            }
            DnsResolutionMode.SINGLE -> return
        }
        if (_resolutionMode.value == mode) RuntimeDnsSettingsRefresher.refreshIfRunning(context, "resolution_mode_providers_changed", dataset = dataset)
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

        DnsProvider.saveSelected(context, remap(_singleProviderId.value), dataset)
        val smartIds = _smartPredictionIds.value.mapTo(linkedSetOf(), ::remap)
        ResolutionSettingsStore.setSmartPredictionProviderIds(context, smartIds, dataset)
        val parallelIds = _parallelRaceIds.value.mapTo(linkedSetOf(), ::remap)
        ResolutionSettingsStore.setParallelRaceProviderIds(context, parallelIds, dataset)
        val primaryBackupIds = _primaryBackupIds.value.map(::remap).distinct()
        ResolutionSettingsStore.setPrimaryBackupProviderIds(context, primaryBackupIds, dataset)
        ResolutionSettingsStore.setPresetDnsService(context, service, dataset)

        _singleProviderId.value = remap(_singleProviderId.value)
        _smartPredictionIds.value = smartIds
        _parallelRaceIds.value = parallelIds
        _primaryBackupIds.value = primaryBackupIds
        _presetDnsService.value = service
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, "preset_dns_service_changed", dataset = dataset)
    }

    fun reorderPrimaryBackupProvider(id: String, targetIndex: Int) {
        val current = _primaryBackupIds.value.toMutableList()
        val from = current.indexOf(id)
        if (from < 0 || targetIndex !in current.indices || from == targetIndex) return
        current.add(targetIndex, current.removeAt(from))
        val context = getApplication<Application>()
        ResolutionSettingsStore.setPrimaryBackupProviderIds(context, current, dataset)
        _primaryBackupIds.value = current
        if (_resolutionMode.value == DnsResolutionMode.PRIMARY_BACKUP) RuntimeDnsSettingsRefresher.refreshIfRunning(context, "primary_backup_order_changed", dataset = dataset)
    }

    fun setTestDomain(domain: String) {
        _testDomain.value = domain
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            ResolutionSettingsStore.setRaceTestDomain(context, domain, dataset)
        }
    }

    fun runLatencyTest() {
        val context = getApplication<Application>()
        val domain = _testDomain.value.trim().takeIf { it.isNotEmpty() }
            ?: ResolutionSettingsStore.getRaceTestDomain(context, dataset)
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
