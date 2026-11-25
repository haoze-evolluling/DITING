package com.haoze.diting.automation

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.Executors

/** 默认网络类型变化时触发 network 类型自动化规则。 */
object AutomationNetworkObserver {
    private const val TAG = "AutomationNetworkObserver"
    private const val KEY_LAST_NETWORK_TYPE = "network_last_type"
    private const val LOST_DEBOUNCE_MS = 500L

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "diting-automation-network").apply { isDaemon = true }
    }

    fun start(context: Context) {
        val appContext: Context = context.applicationContext
        val manager: ConnectivityManager =
            appContext.getSystemService(ConnectivityManager::class.java) ?: return
        val handler = Handler(Looper.getMainLooper())
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = refresh()

            override fun onLost(network: Network) {
                handler.postDelayed({ refresh() }, LOST_DEBOUNCE_MS)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) = refresh()

            private fun refresh() {
                handler.post {
                    val type: String = currentType(manager)
                    val prefs = AutomationContract.prefs(appContext)
                    if (prefs.getString(KEY_LAST_NETWORK_TYPE, null) == type) return@post
                    prefs.edit().putString(KEY_LAST_NETWORK_TYPE, type).apply()
                    executor.execute {
                        runCatching { AutomationEngine.evaluate(appContext, "network") }
                            .onFailure { Log.w(TAG, "求值网络自动化失败", it) }
                    }
                }
            }
        }
        runCatching { manager.registerDefaultNetworkCallback(callback) }
            .onFailure { Log.w(TAG, "注册网络变化监听失败", it) }
    }

    private fun currentType(manager: ConnectivityManager): String {
        val network: Network = manager.activeNetwork ?: return "offline"
        val caps: NetworkCapabilities =
            manager.getNetworkCapabilities(network) ?: return "offline"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
    }
}
