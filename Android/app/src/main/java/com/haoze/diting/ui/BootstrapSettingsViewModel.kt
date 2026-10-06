package com.haoze.diting.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.settings.BootstrapDnsSettingsStore
import com.haoze.diting.core.diagnostic.BootstrapHealthEngine
import com.haoze.diting.core.diagnostic.BootstrapHealthSnapshot
import com.haoze.diting.core.diagnostic.BootstrapHealthStore
import com.haoze.diting.core.diagnostic.BootstrapIpEntry
import com.haoze.diting.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BootstrapSettingsViewModel(
    application: Application,
    val dataset: RuleDataset = RuleDataset.NORMAL
) : AndroidViewModel(application) {

    class Factory(
        private val application: Application,
        private val dataset: RuleDataset = RuleDataset.NORMAL
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return BootstrapSettingsViewModel(application, dataset) as T
        }
    }

    private val _enabled = MutableStateFlow(true)
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    private val _entries = MutableStateFlow<List<BootstrapIpEntry>>(emptyList())
    val entries: StateFlow<List<BootstrapIpEntry>> = _entries.asStateFlow()

    private val _healthByIp = MutableStateFlow<Map<String, BootstrapHealthSnapshot>>(emptyMap())
    val healthByIp: StateFlow<Map<String, BootstrapHealthSnapshot>> = _healthByIp.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

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
            BootstrapHealthEngine.flushActive(commit = true)
            val enabled = BootstrapDnsSettingsStore.isBootstrapEnabled(context, dataset)
            val entries = BootstrapDnsSettingsStore.loadBootstrapIpEntries(context, dataset)
            val health = BootstrapHealthStore.loadAll(context)
            withContext(Dispatchers.Main) {
                _enabled.value = enabled
                _entries.value = entries
                _healthByIp.value = health
            }
        }
    }

    fun setEnabled(enabled: Boolean) {
        val context = getApplication<Application>()
        BootstrapDnsSettingsStore.setBootstrapEnabled(context, enabled, dataset)
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, "bootstrap_toggled", dataset = dataset)
        _enabled.value = enabled
    }

    fun setEntryEnabled(id: String, enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            BootstrapDnsSettingsStore.setBootstrapIpEnabled(context, id, enabled, dataset)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "bootstrap_ip_toggled", dataset = dataset)
            val entries = BootstrapDnsSettingsStore.loadBootstrapIpEntries(context, dataset)
            withContext(Dispatchers.Main) {
                _entries.value = entries
            }
        }
    }

    fun addCustom(name: String, ip: String): Boolean {
        if (!BootstrapDnsSettingsStore.isValidBootstrapIp(ip)) {
            _message.value = getApplication<Application>().getString(R.string.bootstrap_ip_invalid)
            return false
        }
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            BootstrapDnsSettingsStore.addCustomBootstrapIp(context, name, ip, dataset)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "bootstrap_ip_added", dataset = dataset)
            val entries = BootstrapDnsSettingsStore.loadBootstrapIpEntries(context, dataset)
            withContext(Dispatchers.Main) {
                _entries.value = entries
                _message.value = context.getString(R.string.bootstrap_ip_added)
            }
        }
        return true
    }

    fun deleteCustom(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            BootstrapDnsSettingsStore.deleteCustomBootstrapIp(context, id, dataset)
            BootstrapHealthStore.remove(context, id)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "bootstrap_ip_deleted", dataset = dataset)
            val entries = BootstrapDnsSettingsStore.loadBootstrapIpEntries(context, dataset)
            val health = BootstrapHealthStore.loadAll(context)
            withContext(Dispatchers.Main) {
                _entries.value = entries
                _healthByIp.value = health
                _message.value = context.getString(R.string.bootstrap_ip_deleted)
            }
        }
    }

    fun clearMessage() {
        _message.value = null
    }
}
