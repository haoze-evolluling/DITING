package com.haoze.dnssr

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.haoze.dnssr.ui.*
import com.haoze.dnssr.vpn.DnsVpnService

class LogRouteActivity : AppLocalizedActivity() {
    private var childLaunchInProgress = false

    private val route: String
        get() = intent.getStringExtra(EXTRA_ROUTE) ?: Routes.LOG_DASHBOARD

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val themeMode = remember { AppSettings.getAppThemeMode(this) }
            val colorStyle = remember { AppSettings.getThemeColorStyle(this) }
            val backgroundEnabled = remember { AppSettings.isCustomBackgroundEnabled(this) }
            val backgroundUri = remember { AppSettings.getCustomBackgroundUri(this) }

            AppThemeSurface(
                themeMode = themeMode,
                colorStyle = colorStyle,
                backgroundEnabled = backgroundEnabled,
                backgroundUri = backgroundUri,
                modifier = Modifier.fillMaxSize()
            ) {
                LogRouteContent(
                    route = route,
                    onBack = ::finish,
                    onNavigate = ::openRoute,
                    onRuntimeDnsSettingsChanged = {
                        RuntimeDnsSettingsRefresher.refreshIfRunning(this@LogRouteActivity)
                    }
                )
            }
        }
    }

    override fun onStart() {
        super.onStart()
        DnsVpnService.updateFloatingLogAppState(this, true)
    }

    override fun onResume() {
        super.onResume()
        childLaunchInProgress = false
    }

    override fun onStop() {
        DnsVpnService.updateFloatingLogAppState(this, false)
        super.onStop()
    }

    private fun openRoute(nextRoute: String) {
        if (childLaunchInProgress || nextRoute == route) return
        childLaunchInProgress = true
        startActivity(createIntent(this, nextRoute))
    }

    @androidx.compose.runtime.Composable
    private fun LogRouteContent(
        route: String,
        onBack: () -> Unit,
        onNavigate: (String) -> Unit,
        onRuntimeDnsSettingsChanged: () -> Unit
    ) {
        val onNavigateToDnsLogs = { onNavigate(Routes.DNS_LOGS) }
        val onNavigateToDnsCache = { onNavigate(Routes.DNS_CACHE) }
        val onNavigateToRaceStats = { onNavigate(Routes.RACE_STATS) }
        val onNavigateToBootstrapStats = { onNavigate(Routes.BOOTSTRAP_STATS) }
        val onNavigateToSubscriptionInterceptionStats = {
            onNavigate(Routes.SUBSCRIPTION_INTERCEPTION_STATS)
        }
        val onNavigateToTrafficStats = { onNavigate(Routes.APP_TRAFFIC_STATS) }

        when (route) {
            Routes.DNS_LOGS -> RequestLogScreen(
                onBack = onBack,
                onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged
            )
            Routes.DNS_CACHE -> DnsCacheScreen(onBack = onBack)
            Routes.RACE_STATS -> RaceStatsScreen(onBack = onBack)
            Routes.BOOTSTRAP_STATS -> BootstrapStatsScreen(onBack = onBack)
            Routes.SUBSCRIPTION_INTERCEPTION_STATS -> SubscriptionInterceptionStatsScreen(onBack = onBack)
            Routes.PROVIDER_HEALTH -> ProviderHealthScreen(onBack = onBack)
            Routes.APP_TRAFFIC_STATS -> com.haoze.dnssr.ui.traffic.AppTrafficStatsScreen(onBack = onBack)
            else -> ModernLogDashboardScreen(
                onBack = onBack,
                onNavigateToDnsLogs = onNavigateToDnsLogs,
                onNavigateToDnsCache = onNavigateToDnsCache,
                onNavigateToRaceStats = onNavigateToRaceStats,
                onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                onNavigateToSubscriptionInterceptionStats = onNavigateToSubscriptionInterceptionStats,
                onNavigateToTrafficStats = onNavigateToTrafficStats
            )
        }
    }

    companion object {
        const val EXTRA_ROUTE = "log_route"

        fun createIntent(context: android.content.Context, route: String): Intent =
            Intent(context, LogRouteActivity::class.java)
                .putExtra(EXTRA_ROUTE, route)
    }
}
