package com.haoze.diting.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.diting.ui.settings.NetworkToolsSettingsStore
import com.haoze.diting.vpn.DnsLookupTool
import com.haoze.diting.vpn.DnsProvider
import com.haoze.diting.vpn.NetworkInfoProbe
import com.haoze.diting.vpn.NetworkPingTool
import com.haoze.diting.vpn.NetworkSnapshot
import com.haoze.diting.vpn.NetworkTraceRouteTool
import com.haoze.diting.vpn.TunnelDiagnosticsResolver
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

    private val _pingViaTunnel = MutableStateFlow(NetworkToolsSettingsStore.isPingViaTunnel(application))
    val pingViaTunnel: StateFlow<Boolean> = _pingViaTunnel.asStateFlow()

    private val _pingCount = MutableStateFlow(DEFAULT_PING_COUNT)
    val pingCount: StateFlow<Int> = _pingCount.asStateFlow()

    private val _isPinging = MutableStateFlow(false)
    val isPinging: StateFlow<Boolean> = _isPinging.asStateFlow()

    private val _pingResult = MutableStateFlow<NetworkPingTool.Summary?>(null)
    val pingResult: StateFlow<NetworkPingTool.Summary?> = _pingResult.asStateFlow()

    private val _dnsHost = MutableStateFlow("")
    val dnsHost: StateFlow<String> = _dnsHost.asStateFlow()

    private val _dnsLookupViaTunnel = MutableStateFlow(NetworkToolsSettingsStore.isDnsLookupViaTunnel(application))
    val dnsLookupViaTunnel: StateFlow<Boolean> = _dnsLookupViaTunnel.asStateFlow()

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

    private val _traceViaTunnel = MutableStateFlow(NetworkToolsSettingsStore.isTracerouteViaTunnel(application))
    val traceViaTunnel: StateFlow<Boolean> = _traceViaTunnel.asStateFlow()

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

    fun setPingViaTunnel(enabled: Boolean) {
        _pingViaTunnel.value = enabled
        NetworkToolsSettingsStore.setPingViaTunnel(getApplication(), enabled)
    }

    fun setPingCount(count: Int) {
        _pingCount.value = count
    }

    fun setDnsHost(host: String) {
        _dnsHost.value = host.filter { !it.isWhitespace() }
    }

    fun setDnsLookupViaTunnel(enabled: Boolean) {
        _dnsLookupViaTunnel.value = enabled
        NetworkToolsSettingsStore.setDnsLookupViaTunnel(getApplication(), enabled)
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

    fun setTraceViaTunnel(enabled: Boolean) {
        _traceViaTunnel.value = enabled
        NetworkToolsSettingsStore.setTracerouteViaTunnel(getApplication(), enabled)
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
        val viaTunnel = _pingViaTunnel.value

        viewModelScope.launch {
            _isPinging.value = true
            _pingResult.value = null
            val tunnelResolution = resolveTargetForProbe(target, viaTunnel)
            if (tunnelResolution is TunnelProbeResolution.Failed) {
                _message.value = tunnelResolution.message
                _isPinging.value = false
                return@launch
            }
            val resolved = tunnelResolution as? TunnelProbeResolution.Resolved
            val result = NetworkPingTool.ping(target, count, addressOverride = resolved?.ip)
            _pingResult.value = result.withTunnelNote(resolved?.sourceLabel)
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
        val viaTunnel = _dnsLookupViaTunnel.value

        viewModelScope.launch(Dispatchers.IO) {
            if (viaTunnel) {
                withContext(Dispatchers.Main) {
                    _isDnsLookingUp.value = true
                    _dnsResult.value = null
                }
                val start = System.currentTimeMillis()
                val tunnelResult = TunnelDiagnosticsResolver.resolve(host, recordType == DnsLookupTool.RecordType.A)
                val result = tunnelResult?.let {
                    DnsLookupTool.tunnelLookup(host, recordType, it, System.currentTimeMillis() - start)
                }
                withContext(Dispatchers.Main) {
                    if (result == null) {
                        _message.value = "VPN 未运行，无法通过 Go 隧道解析"
                    } else {
                        _dnsResult.value = result
                    }
                    _isDnsLookingUp.value = false
                }
                return@launch
            }

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
        val viaTunnel = _traceViaTunnel.value

        viewModelScope.launch {
            _isTracing.value = true
            _traceHops.value = emptyList()
            _traceResult.value = null
            val tunnelResolution = resolveTargetForProbe(target, viaTunnel)
            if (tunnelResolution is TunnelProbeResolution.Failed) {
                _message.value = tunnelResolution.message
                _isTracing.value = false
                return@launch
            }
            val resolved = tunnelResolution as? TunnelProbeResolution.Resolved
            val result = NetworkTraceRouteTool.trace(target, maxHops, addressOverride = resolved?.ip) { hop ->
                withContext(Dispatchers.Main) {
                    _traceHops.value = _traceHops.value + hop
                }
            }
            _traceResult.value = result.withTunnelNote(resolved?.sourceLabel)
            _isTracing.value = false
        }
    }

    fun clearMessage() {
        _message.value = null
    }

    /** Resolves a probe target through the Go tunnel; null means the tunnel is not in use for this run. */
    private suspend fun resolveTargetForProbe(target: String, viaTunnel: Boolean): TunnelProbeResolution? {
        if (!viaTunnel || DnsProvider.isIpLiteral(target)) return null
        return withContext(Dispatchers.IO) {
            val result = TunnelDiagnosticsResolver.resolveAutoFamily(target)
                ?: return@withContext TunnelProbeResolution.Failed("VPN 未运行，无法通过 Go 隧道解析")
            when (result.source) {
                TunnelDiagnosticsResolver.Source.BLOCKED ->
                    TunnelProbeResolution.Failed("域名已被拦截规则拦截${result.reason?.let { "：$it" }.orEmpty()}")
                TunnelDiagnosticsResolver.Source.ERROR ->
                    TunnelProbeResolution.Failed(result.errorLabel())
                TunnelDiagnosticsResolver.Source.NODATA ->
                    TunnelProbeResolution.Failed("隧道解析未返回地址${result.reason?.let { "（$it）" }.orEmpty()}")
                else -> result.ips.firstOrNull()
                    ?.let { TunnelProbeResolution.Resolved(it, result.sourceLabel()) }
                    ?: TunnelProbeResolution.Failed("隧道解析未返回地址")
            }
        }
    }

    private companion object {
        const val DEFAULT_PING_COUNT = 4
        const val DEFAULT_MAX_HOPS = 15
    }
}

private sealed interface TunnelProbeResolution {
    data class Resolved(val ip: String, val sourceLabel: String) : TunnelProbeResolution
    data class Failed(val message: String) : TunnelProbeResolution
}

private fun NetworkPingTool.Summary.withTunnelNote(sourceLabel: String?): NetworkPingTool.Summary {
    if (sourceLabel.isNullOrEmpty()) return this
    val note = "已通过 Go 隧道解析 · 来源：$sourceLabel"
    return copy(message = listOfNotNull(message, note).joinToString("；"))
}

private fun NetworkTraceRouteTool.Progress.withTunnelNote(sourceLabel: String?): NetworkTraceRouteTool.Progress {
    if (sourceLabel.isNullOrEmpty()) return this
    val note = "已通过 Go 隧道解析 · 来源：$sourceLabel"
    return copy(message = listOfNotNull(message, note).joinToString("；"))
}
