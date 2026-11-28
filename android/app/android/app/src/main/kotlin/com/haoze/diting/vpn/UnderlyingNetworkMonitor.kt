package com.haoze.diting.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.haoze.diting.engine.Engine

/**
 * 跟踪 VPN 底层的物理网络：把当前网络下发的 DNS 交给引擎做兜底，
 * 并在切换时告知系统 underlying network，避免沿用手抓网络留下的解析链路。
 */
internal class UnderlyingNetworkMonitor(
    context: Context,
    private val service: VpnService,
    /** 物理网络或下发的 DNS 变化时回调；第二个参数表示物理网络本身是否切换。 */
    private val onChanged: (State, Boolean) -> Unit,
) {
    data class State(
        val networkKey: Long,
        val dnsServers: List<String>,
    )

    private val handler = Handler(Looper.getMainLooper())
    private val connectivity = context.applicationContext
        .getSystemService(ConnectivityManager::class.java)
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var lastNetwork: Network? = null
    private var lastState: State? = null

    fun start() {
        if (callback != null) return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = refresh()

            override fun onLost(network: Network) = refresh()

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) =
                refresh()

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) = refresh()
        }
        val manager = connectivity
        if (manager == null) {
            Log.w(TAG, "ConnectivityManager unavailable; system DNS fallback stays static")
            return
        }
        runCatching { manager.registerNetworkCallback(request, cb, handler) }
            .onSuccess { callback = cb }
            .onFailure { Log.w(TAG, "registerNetworkCallback failed; polling stays off", it) }
        refresh()
    }

    fun stop() {
        callback?.let { cb -> runCatching { connectivity?.unregisterNetworkCallback(cb) } }
        callback = null
        lastNetwork = null
        lastState = null
    }

    private fun refresh() {
        val manager = connectivity ?: return
        val physical = physicalNetwork(manager) ?: return
        val networkChanged = physical != lastNetwork
        if (networkChanged) {
            runCatching { service.setUnderlyingNetworks(arrayOf(physical)) }
                .onFailure { Log.w(TAG, "setUnderlyingNetworks failed", it) }
        }
        // 拿不到链路属性时先不推进 lastNetwork，等下一次回调仍按“网络已切换”处理。
        val link = manager.getLinkProperties(physical) ?: return
        lastNetwork = physical
        // networkKey 参与相等判断：即使新老网络下发的 DNS 相同，切换本身也要通知引擎。
        val state = State(physical.networkHandle, dnsServersOf(link))
        if (state == lastState) return
        lastState = state
        onChanged(state, networkChanged)
    }

    @Suppress("DEPRECATION")
    private fun physicalNetwork(manager: ConnectivityManager): Network? {
        val active = manager.activeNetwork
        if (active != null) {
            val caps = manager.getNetworkCapabilities(active)
            if (caps != null && !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                return active
            }
        }
        val candidates = manager.allNetworks.filter { network ->
            val caps = manager.getNetworkCapabilities(network) ?: return@filter false
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))
        }
        return candidates.firstOrNull { network ->
            manager.getNetworkCapabilities(network)
                ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        } ?: candidates.firstOrNull()
    }

    private fun dnsServersOf(link: LinkProperties): List<String> =
        link.dnsServers.mapNotNull { address ->
            when {
                address.isAnyLocalAddress -> null
                address.isLoopbackAddress -> null
                address.isLinkLocalAddress -> null
                else -> address.hostAddress?.substringBefore('%')?.takeIf { it.isNotBlank() }
            }
        }.distinct()

    companion object {
        private const val TAG = "UnderlyingNetworkMonitor"
    }
}

/**
 * 把当前物理网络状态写入引擎；网络切换后重置上游健康度与加密连接池，
 * 并下线旧链路上的所有数据面连接，避免继续复用已失效的 socket。
 */
internal fun UnderlyingNetworkMonitor.State.applyTo(engine: Engine, networkChanged: Boolean) {
    engine.setSystemDns(dnsServers.joinToString("\n"))
    engine.resetResolverHealth()
    if (networkChanged) engine.resetDataPlane()
}
