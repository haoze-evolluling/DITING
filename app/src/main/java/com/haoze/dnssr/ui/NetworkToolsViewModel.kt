package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.vpn.DnsLookupTool
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.NetworkInfoProbe
import com.haoze.dnssr.vpn.NetworkPingTool
import com.haoze.dnssr.vpn.NetworkSnapshot
import com.haoze.dnssr.vpn.NetworkTraceRouteTool
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetAddress

enum class NetworkToolMode(val label: String) {
    SPEED_TEST("测速"),
    PING("Ping 测试"),
    DNS_LOOKUP("DNS 解析"),
    TRACEROUTE("路由追踪")
}

enum class DnsServerMode(val label: String) {
    SYSTEM("跟随系统"),
    CUSTOM("自定义")
}

class NetworkToolsViewModel(application: Application) : AndroidViewModel(application) {

    private val _toolMode = MutableStateFlow(NetworkToolMode.PING)
    val toolMode: StateFlow<NetworkToolMode> = _toolMode.asStateFlow()

    private val _networkSnapshot = MutableStateFlow<NetworkSnapshot?>(null)
    val networkSnapshot: StateFlow<NetworkSnapshot?> = _networkSnapshot.asStateFlow()

    private val _pingTarget = MutableStateFlow("")
    val pingTarget: StateFlow<String> = _pingTarget.asStateFlow()

    private val _pingCount = MutableStateFlow(DEFAULT_PING_COUNT)
    val pingCount: StateFlow<Int> = _pingCount.asStateFlow()

    private val _isPinging = MutableStateFlow(false)
    val isPinging: StateFlow<Boolean> = _isPinging.asStateFlow()

    private val _pingResult = MutableStateFlow<NetworkPingTool.Summary?>(null)
    val pingResult: StateFlow<NetworkPingTool.Summary?> = _pingResult.asStateFlow()

    private val _dnsHost = MutableStateFlow("")
    val dnsHost: StateFlow<String> = _dnsHost.asStateFlow()

    private val _dnsRecordType = MutableStateFlow(DnsLookupTool.RecordType.A)
    val dnsRecordType: StateFlow<DnsLookupTool.RecordType> = _dnsRecordType.asStateFlow()

    private val _dnsServerMode = MutableStateFlow(DnsServerMode.SYSTEM)
    val dnsServerMode: StateFlow<DnsServerMode> = _dnsServerMode.asStateFlow()

    private val _customDnsServer = MutableStateFlow("")
    val customDnsServer: StateFlow<String> = _customDnsServer.asStateFlow()

    private val _isDnsLookingUp = MutableStateFlow(false)
    val isDnsLookingUp: StateFlow<Boolean> = _isDnsLookingUp.asStateFlow()

    private val _dnsResult = MutableStateFlow<DnsLookupTool.Result?>(null)
    val dnsResult: StateFlow<DnsLookupTool.Result?> = _dnsResult.asStateFlow()

    private val _traceTarget = MutableStateFlow("")
    val traceTarget: StateFlow<String> = _traceTarget.asStateFlow()

    private val _traceMaxHops = MutableStateFlow(DEFAULT_MAX_HOPS)
    val traceMaxHops: StateFlow<Int> = _traceMaxHops.asStateFlow()

    private val _isTracing = MutableStateFlow(false)
    val isTracing: StateFlow<Boolean> = _isTracing.asStateFlow()

    private val _traceHops = MutableStateFlow<List<NetworkTraceRouteTool.Hop>>(emptyList())
    val traceHops: StateFlow<List<NetworkTraceRouteTool.Hop>> = _traceHops.asStateFlow()

    private val _traceResult = MutableStateFlow<NetworkTraceRouteTool.Progress?>(null)
    val traceResult: StateFlow<NetworkTraceRouteTool.Progress?> = _traceResult.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private var activated = false

    fun activate() {
        if (!activated) {
            activated = true
            refreshNetworkInfo()
        }
    }

    fun refreshNetworkInfo() {
        viewModelScope.launch(Dispatchers.IO) {
            val snapshot = NetworkInfoProbe.probe(getApplication())
            withContext(Dispatchers.Main) { _networkSnapshot.value = snapshot }
        }
    }

    fun setToolMode(mode: NetworkToolMode) {
        _toolMode.value = mode
    }

    fun setPingTarget(target: String) {
        _pingTarget.value = target
    }

    fun setPingCount(count: Int) {
        _pingCount.value = count
    }

    fun setDnsHost(host: String) {
        _dnsHost.value = host.filter { !it.isWhitespace() }
    }

    fun setDnsRecordType(type: DnsLookupTool.RecordType) {
        _dnsRecordType.value = type
    }

    fun setDnsServerMode(mode: DnsServerMode) {
        _dnsServerMode.value = mode
    }

    fun setCustomDnsServer(server: String) {
        _customDnsServer.value = server.filter { !it.isWhitespace() }
    }

    fun setTraceTarget(target: String) {
        _traceTarget.value = target
    }

    fun setTraceMaxHops(hops: Int) {
        _traceMaxHops.value = hops
    }

    fun runPing() {
        val target = _pingTarget.value.trim()
        if (target.isEmpty()) {
            _message.value = "请输入 Ping 目标"
            return
        }
        if (_isPinging.value) return
        val count = _pingCount.value

        viewModelScope.launch {
            _isPinging.value = true
            _pingResult.value = null
            val result = NetworkPingTool.ping(target, count)
            _pingResult.value = result
            _isPinging.value = false
        }
    }

    fun runDnsLookup() {
        val host = _dnsHost.value.trim()
        if (host.isEmpty()) {
            _message.value = "请输入要解析的域名"
            return
        }
        if (_isDnsLookingUp.value) return
        val recordType = _dnsRecordType.value
        val serverMode = _dnsServerMode.value
        val customServer = _customDnsServer.value.trim()

        viewModelScope.launch(Dispatchers.IO) {
            val servers: List<InetAddress> = when (serverMode) {
                DnsServerMode.SYSTEM -> {
                    val snapshot = _networkSnapshot.value ?: NetworkInfoProbe.probe(getApplication())
                    val addresses = snapshot?.dnsServers.orEmpty()
                        .mapNotNull { runCatching { InetAddress.getByName(it) }.getOrNull() }
                    if (addresses.isEmpty()) {
                        withContext(Dispatchers.Main) {
                            _message.value = "无法获取当前网络的 DNS 服务器，可改用自定义服务器"
                        }
                        return@launch
                    }
                    addresses
                }
                DnsServerMode.CUSTOM -> {
                    if (!DnsProvider.isIpLiteral(customServer)) {
                        withContext(Dispatchers.Main) {
                            _message.value = "自定义 DNS 服务器须为有效 IP 地址"
                        }
                        return@launch
                    }
                    listOf(InetAddress.getByName(customServer))
                }
            }

            withContext(Dispatchers.Main) {
                _isDnsLookingUp.value = true
                _dnsResult.value = null
            }
            val result = DnsLookupTool.lookup(host, recordType, servers)
            withContext(Dispatchers.Main) {
                _dnsResult.value = result
                _isDnsLookingUp.value = false
            }
        }
    }

    fun runTraceRoute() {
        val target = _traceTarget.value.trim()
        if (target.isEmpty()) {
            _message.value = "请输入追踪目标"
            return
        }
        if (_isTracing.value) return
        val maxHops = _traceMaxHops.value

        viewModelScope.launch {
            _isTracing.value = true
            _traceHops.value = emptyList()
            _traceResult.value = null
            val result = NetworkTraceRouteTool.trace(target, maxHops) { hop ->
                withContext(Dispatchers.Main) {
                    _traceHops.value = _traceHops.value + hop
                }
            }
            _traceResult.value = result
            _isTracing.value = false
        }
    }

    fun clearMessage() {
        _message.value = null
    }

    private companion object {
        const val DEFAULT_PING_COUNT = 4
        const val DEFAULT_MAX_HOPS = 15
    }
}
