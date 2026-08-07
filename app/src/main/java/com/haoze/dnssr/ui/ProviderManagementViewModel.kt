package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ProviderManagementViewModel(application: Application) : AndroidViewModel(application) {

    private val _providers = MutableStateFlow<List<DnsProvider>>(emptyList())
    val providers: StateFlow<List<DnsProvider>> = _providers.asStateFlow()

    private val _selectedId = MutableStateFlow<String>("")
    val selectedId: StateFlow<String> = _selectedId.asStateFlow()

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
            val all = DnsProvider.loadAll(context)
            val selected = DnsProvider.loadSelected(context)
            withContext(Dispatchers.Main) {
                _providers.value = all
                _selectedId.value = selected.id
                _initialLoading.value = false
            }
        }
    }

    fun select(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            DnsProvider.saveSelected(context, id)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "provider_selected")
            withContext(Dispatchers.Main) {
                _selectedId.value = id
            }
        }
    }

    fun addProvider(
        name: String,
        protocol: DnsProtocol,
        url: String,
        host: String,
        portText: String
    ) {
        val port = parsePortOrDefault(protocol, portText) ?: return
        if (!validate(name, protocol, url, host, port)) return
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            DnsProvider.addUserProvider(
                context,
                name.trim(),
                protocol,
                url.trim(),
                host.trim(),
                port
            )
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "provider_added")
            withContext(Dispatchers.Main) {
                _message.value = context.getString(R.string.provider_added)
            }
            load()
        }
    }

    fun updateProvider(
        provider: DnsProvider,
        name: String,
        protocol: DnsProtocol,
        url: String,
        host: String,
        portText: String
    ) {
        val port = parsePortOrDefault(protocol, portText) ?: return
        if (!validate(name, protocol, url, host, port)) return
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val updated = provider.copy(
                name = name.trim(),
                protocol = protocol,
                url = url.trim(),
                host = host.trim(),
                port = port
            )
            DnsProvider.updateUserProvider(context, updated)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "provider_updated")
            withContext(Dispatchers.Main) {
                _message.value = context.getString(R.string.provider_updated)
            }
            load()
        }
    }

    fun deleteProvider(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            DnsProvider.deleteUserProvider(context, id)
            RuntimeDnsSettingsRefresher.refreshIfRunning(context, "provider_deleted")
            withContext(Dispatchers.Main) {
                _message.value = context.getString(R.string.provider_deleted)
            }
            load()
        }
    }

    fun clearMessage() {
        _message.value = null
    }

    private fun validate(
        name: String,
        protocol: DnsProtocol,
        url: String,
        host: String,
        port: Int
    ): Boolean {
        if (name.trim().isEmpty()) {
            _message.value = getApplication<Application>().getString(R.string.provider_name_required)
            return false
        }
        when (protocol) {
            DnsProtocol.DOH -> {
                if (!DnsProvider.isValidDohUrl(url)) {
                    _message.value = getApplication<Application>().getString(R.string.provider_doh_url_invalid, protocol.label)
                    return false
                }
            }
            DnsProtocol.DOT -> {
                if (!DnsProvider.isValidDotHost(host)) {
                    _message.value = getApplication<Application>().getString(R.string.provider_dot_host_invalid, protocol.label)
                    return false
                }
                if (!DnsProvider.isValidDotPort(port)) {
                    _message.value = getApplication<Application>().getString(R.string.provider_port_range, protocol.label)
                    return false
                }
            }
            DnsProtocol.DNS -> {
                if (!DnsProvider.isValidDnsHost(host)) {
                    _message.value = getApplication<Application>().getString(R.string.provider_host_invalid, protocol.label)
                    return false
                }
                if (!DnsProvider.isValidDotPort(port)) {
                    _message.value = getApplication<Application>().getString(R.string.provider_port_range, protocol.label)
                    return false
                }
            }
        }
        return true
    }

    private fun parsePortOrDefault(protocol: DnsProtocol, portText: String): Int? {
        if (protocol == DnsProtocol.DOH) return DnsProvider.DEFAULT_DOT_PORT
        val defaultPort = if (protocol == DnsProtocol.DNS) {
            DnsProvider.DEFAULT_DNS_PORT
        } else {
            DnsProvider.DEFAULT_DOT_PORT
        }
        val port = portText.trim().ifBlank { defaultPort.toString() }.toIntOrNull()
        if (port == null) {
            _message.value = getApplication<Application>().getString(R.string.provider_port_number, protocol.label)
            return null
        }
        return port
    }
}
