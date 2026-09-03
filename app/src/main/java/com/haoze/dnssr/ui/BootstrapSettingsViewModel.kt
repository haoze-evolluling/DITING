package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.vpn.BootstrapHealthEngine
import com.haoze.dnssr.vpn.BootstrapHealthSnapshot
import com.haoze.dnssr.vpn.BootstrapHealthStore
import com.haoze.dnssr.vpn.BootstrapIpEntry
import com.haoze.dnssr.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BootstrapSettingsViewModel(application: Application) : AndroidViewModel(application) {
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
            val enabled = AppSettings.isBootstrapEnabled(context)
            val entries = AppSettings.loadBootstrapIpEntries(context)
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
        AppSettings.setBootstrapEnabled(context, enabled)
        RuntimeDnsSettingsRefresher.refreshIfRunning(context, "bootstrap_toggled")
        _enabled.value = enabled
    }

    fun setEntryEnabled(id: String, enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            AppSettings.setBootstrapIpEnabled(context, id, enabled)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "bootstrap_ip_toggled")
            val entries = AppSettings.loadBootstrapIpEntries(context)
            withContext(Dispatchers.Main) {
                _entries.value = entries
            }
        }
    }

    fun addCustom(name: String, ip: String): Boolean {
        if (!AppSettings.isValidBootstrapIp(ip)) {
            _message.value = getApplication<Application>().getString(R.string.bootstrap_ip_invalid)
            return false
        }
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            AppSettings.addCustomBootstrapIp(context, name, ip)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "bootstrap_ip_added")
            val entries = AppSettings.loadBootstrapIpEntries(context)
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
            AppSettings.deleteCustomBootstrapIp(context, id)
            BootstrapHealthStore.remove(context, id)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "bootstrap_ip_deleted")
            val entries = AppSettings.loadBootstrapIpEntries(context)
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
