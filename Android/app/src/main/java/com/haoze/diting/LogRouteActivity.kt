package com.haoze.diting

import com.haoze.diting.normal.ui.*

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.haoze.diting.data.RequestSource
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.*
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import com.haoze.diting.normal.DnsVpnService

class LogRouteActivity : AppLocalizedActivity() {
    private var childLaunchInProgress = false

    private val route: String
        get() = intent.getStringExtra(EXTRA_ROUTE) ?: Routes.LOG_DASHBOARD

    private val dataset: RuleDataset
        get() = intent.getStringExtra(EXTRA_DATASET)?.let { value ->
            runCatching { RuleDataset.valueOf(value) }.getOrNull()
        } ?: if (com.haoze.diting.ui.mode.WorkModeStore.getAppWorkMode(this) == com.haoze.diting.ui.mode.AppWorkMode.EXPRESS) {
            RuleDataset.EXPRESS
        } else {
            RuleDataset.NORMAL
        }

    private val requestedRequestSource: RequestSource?
        get() = intent.getStringExtra(EXTRA_REQUEST_SOURCE)?.let { value ->
            runCatching { RequestSource.valueOf(value) }.getOrNull()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val themeMode = remember { AppearanceSettingsStore.getAppThemeMode(this) }
            val colorStyle = remember { AppearanceSettingsStore.getThemeColorStyle(this) }
            val backgroundEnabled = remember { AppearanceSettingsStore.isCustomBackgroundEnabled(this) }
            val backgroundUri = remember { AppearanceSettingsStore.getCustomBackgroundUri(this) }

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
                        RuntimeDnsSettingsRefresher.refreshIfRunning(this@LogRouteActivity, dataset = dataset)
                    }
                )
            }
        }
    }

    override fun onStart() {
        super.onStart()
        com.haoze.diting.express.ExpressModeLauncher.updateFloatingLogAppState(this, true)
    }

    override fun onResume() {
        super.onResume()
        childLaunchInProgress = false
    }

    override fun onStop() {
        com.haoze.diting.express.ExpressModeLauncher.updateFloatingLogAppState(this, false)
        super.onStop()
    }

    private fun openRoute(nextRoute: String) {
        if (childLaunchInProgress || nextRoute == route) return
        childLaunchInProgress = true
        startActivity(createIntent(this, nextRoute, dataset = dataset))
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

        val isExpressMode = dataset == RuleDataset.EXPRESS
        when (route) {
            Routes.DNS_LOGS,
            Routes.HTTP_REQUEST_LOGS -> {
                if (isExpressMode) {
                    com.haoze.diting.express.ui.ExpressRequestLogScreen(
                        onBack = onBack,
                        onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged
                    )
                } else {
                    RequestLogScreen(
                        onBack = onBack,
                        initialSource = requestedRequestSource ?: if (route == Routes.HTTP_REQUEST_LOGS) RequestSource.HTTPS else RequestSource.ALL,
                        onRuntimeDnsSettingsChanged = onRuntimeDnsSettingsChanged
                    )
                }
            }
            Routes.DNS_CACHE -> DnsCacheScreen(onBack = onBack, dataset = dataset)
            Routes.RACE_STATS -> RaceStatsScreen(onBack = onBack, dataset = dataset)
            Routes.BOOTSTRAP_STATS -> BootstrapStatsScreen(onBack = onBack, dataset = dataset)
            Routes.SUBSCRIPTION_INTERCEPTION_STATS -> SubscriptionInterceptionStatsScreen(onBack = onBack, dataset = dataset)
            Routes.PROVIDER_HEALTH -> ProviderHealthScreen(onBack = onBack, dataset = dataset)
            Routes.APP_TRAFFIC_STATS -> com.haoze.diting.normal.ui.AppTrafficStatsScreen(onBack = onBack)
            else -> {
                if (isExpressMode) {
                    com.haoze.diting.express.ui.ExpressLogDashboardScreen(
                        onBack = onBack,
                        onNavigateToDnsLogs = onNavigateToDnsLogs,
                        onNavigateToDnsCache = onNavigateToDnsCache,
                        onNavigateToRaceStats = onNavigateToRaceStats,
                        onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                        onNavigateToSubscriptionInterceptionStats = onNavigateToSubscriptionInterceptionStats,
                        dataset = dataset
                    )
                } else {
                    ModernLogDashboardScreen(
                        onBack = onBack,
                        onNavigateToDnsLogs = onNavigateToDnsLogs,
                        onNavigateToDnsCache = onNavigateToDnsCache,
                        onNavigateToRaceStats = onNavigateToRaceStats,
                        onNavigateToBootstrapStats = onNavigateToBootstrapStats,
                        onNavigateToSubscriptionInterceptionStats = onNavigateToSubscriptionInterceptionStats,
                        onNavigateToTrafficStats = onNavigateToTrafficStats,
                        dataset = dataset
                    )
                }
            }
        }
    }

    companion object {
        const val EXTRA_ROUTE = "log_route"
        const val EXTRA_REQUEST_SOURCE = "log_request_source"
        const val EXTRA_DATASET = "log_dataset"

        fun createIntent(
            context: android.content.Context,
            route: String,
            requestSource: RequestSource? = null,
            dataset: RuleDataset? = null
        ): Intent =
            Intent(context, LogRouteActivity::class.java)
                .putExtra(EXTRA_ROUTE, route)
                .apply {
                    requestSource?.let { putExtra(EXTRA_REQUEST_SOURCE, it.name) }
                    dataset?.let { putExtra(EXTRA_DATASET, it.name) }
                }
    }
}
