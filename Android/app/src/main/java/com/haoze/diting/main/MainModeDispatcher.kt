package com.haoze.diting.main

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.express.ui.ExpressMainScreen
import com.haoze.diting.normal.ui.MainScreen
import com.haoze.diting.server.ui.DnsModeHost
import com.haoze.diting.ui.MainViewModel
import com.haoze.diting.ui.Routes
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * Dispatches the main screen content based on the active [AppWorkMode].
 *
 * Encapsulates the routing callbacks and mode-specific UI hosts to keep
 * MainActivity decoupled from individual mode presentation layers.
 */
@Composable
fun MainModeDispatcher(
    currentWorkMode: AppWorkMode,
    mainViewModel: MainViewModel,
    onToggleVpn: (Boolean) -> Unit,
    onNavigateToSettings: (String, RuleDataset?) -> Unit,
    onNavigateToLogs: (RuleDataset?) -> Unit,
    onNavigateToLogRoute: (String, RuleDataset?) -> Unit,
    onNavigateToModeSelection: () -> Unit,
    onSwitchToNormalMode: () -> Unit,
    resetToHomeTrigger: Long,
    bottomBarRefreshRequested: Boolean,
    onBottomBarRefreshConsumed: () -> Unit,
    modifier: Modifier = Modifier
) {
    when (currentWorkMode) {
        AppWorkMode.EXPRESS -> {
            ExpressMainScreen(
                onToggle = onToggleVpn,
                onNavigateToSettings = { onNavigateToSettings(Routes.SETTINGS, RuleDataset.EXPRESS) },
                onNavigateToLogs = { onNavigateToLogs(RuleDataset.EXPRESS) },
                onNavigateToProviderManagement = { onNavigateToSettings(Routes.PROVIDER_MANAGEMENT, RuleDataset.EXPRESS) },
                onNavigateToBootstrapSettings = { onNavigateToSettings(Routes.BOOTSTRAP_SETTINGS, RuleDataset.EXPRESS) },
                onNavigateToHomeProviderVisibility = { onNavigateToSettings(Routes.HOME_PROVIDER_VISIBILITY, RuleDataset.EXPRESS) },
                onNavigateToRaceModeSettings = { onNavigateToSettings(Routes.RACE_MODE_PROVIDERS, RuleDataset.EXPRESS) },
                onNavigateToAppearanceSettings = { onNavigateToSettings(Routes.APPEARANCE_SETTINGS, null) },
                onNavigateToRuleControl = { onNavigateToSettings(Routes.RULE_CONTROL, RuleDataset.EXPRESS) },
                onNavigateToBlacklist = { onNavigateToSettings(Routes.BLACKLIST_MANAGEMENT, RuleDataset.EXPRESS) },
                onNavigateToWhitelist = { onNavigateToSettings(Routes.WHITELIST_MANAGEMENT, RuleDataset.EXPRESS) },
                onNavigateToLogRetentionSettings = { onNavigateToSettings(Routes.LOG_RETENTION_SETTINGS, RuleDataset.EXPRESS) },
                onNavigateToHomeProviderVisibilityFromFeatureHub = { onNavigateToSettings(Routes.HOME_PROVIDER_VISIBILITY, RuleDataset.EXPRESS) },
                onNavigateToAbout = { onNavigateToSettings(Routes.ABOUT, null) },
                onNavigateToSponsor = { onNavigateToSettings(Routes.SPONSOR, null) },
                onNavigateToSponsorList = { onNavigateToSettings(Routes.SPONSOR_LIST, null) },
                onNavigateToCoBuilderList = { onNavigateToSettings(Routes.CO_BUILDER_LIST, null) },
                onNavigateToAppUpdate = { onNavigateToSettings(Routes.APP_UPDATE, null) },
                onNavigateToDataManagement = { onNavigateToSettings(Routes.CONFIG_TRANSFER, RuleDataset.EXPRESS) },
                onNavigateToHiddenFeatures = { onNavigateToSettings(Routes.HIDDEN_FEATURES, null) },
                onNavigateToCacheSettings = { onNavigateToSettings(Routes.CACHE_SETTINGS, RuleDataset.EXPRESS) },
                onNavigateToDataCleanup = { onNavigateToSettings(Routes.DATA_CLEANUP, RuleDataset.EXPRESS) },
                onNavigateToLogRoute = { r -> onNavigateToLogRoute(r, RuleDataset.EXPRESS) },
                onNavigateToSettingsRoute = { r -> onNavigateToSettings(r, RuleDataset.EXPRESS) },
                onNavigateToModeSelection = onNavigateToModeSelection,
                resetToHomeTrigger = resetToHomeTrigger,
                bottomBarRefreshRequested = bottomBarRefreshRequested,
                onBottomBarRefreshConsumed = onBottomBarRefreshConsumed,
                viewModel = mainViewModel
            )
        }
        AppWorkMode.DNS -> {
            DnsModeHost(
                onSelectMode = onNavigateToModeSelection,
                resetToHomeTrigger = resetToHomeTrigger,
                onSwitchToNormalMode = onSwitchToNormalMode,
                modifier = modifier.fillMaxSize()
            )
        }
        else -> {
            MainScreen(
                onToggle = onToggleVpn,
                onNavigateToSettings = { onNavigateToSettings(Routes.SETTINGS, null) },
                onNavigateToLogs = { onNavigateToLogs(null) },
                onNavigateToProviderManagement = { onNavigateToSettings(Routes.PROVIDER_MANAGEMENT, null) },
                onNavigateToBootstrapSettings = { onNavigateToSettings(Routes.BOOTSTRAP_SETTINGS, null) },
                onNavigateToHomeProviderVisibility = { onNavigateToSettings(Routes.HOME_PROVIDER_VISIBILITY, null) },
                onNavigateToRaceModeSettings = { onNavigateToSettings(Routes.RACE_MODE_PROVIDERS, null) },
                onNavigateToBlockedApps = { onNavigateToSettings(Routes.BLOCKED_APPS, null) },
                onNavigateToAppAllowlist = { onNavigateToSettings(Routes.APP_ALLOWLIST, null) },
                onNavigateToExcludedApps = { onNavigateToSettings(Routes.EXCLUDED_APPS, null) },
                onNavigateToAppearanceSettings = { onNavigateToSettings(Routes.APPEARANCE_SETTINGS, null) },
                onNavigateToRuleControl = { onNavigateToSettings(Routes.RULE_CONTROL, null) },
                onNavigateToBlacklist = { onNavigateToSettings(Routes.BLACKLIST_MANAGEMENT, null) },
                onNavigateToWhitelist = { onNavigateToSettings(Routes.WHITELIST_MANAGEMENT, null) },
                onNavigateToRewriteList = { onNavigateToSettings(Routes.REWRITELIST_MANAGEMENT, null) },
                onNavigateToAppRules = { onNavigateToSettings(Routes.APP_RULE_MANAGEMENT, null) },
                onNavigateToHttpInspection = { onNavigateToSettings(Routes.HTTP_INSPECTION_SETTINGS, null) },
                onNavigateToLogRetentionSettings = { onNavigateToSettings(Routes.LOG_RETENTION_SETTINGS, null) },
                onNavigateToNetworkTools = { onNavigateToSettings(Routes.NETWORK_TOOLS, null) },
                onNavigateToHomeProviderVisibilityFromFeatureHub = { onNavigateToSettings(Routes.HOME_PROVIDER_VISIBILITY, null) },
                onNavigateToAbout = { onNavigateToSettings(Routes.ABOUT, null) },
                onNavigateToSponsor = { onNavigateToSettings(Routes.SPONSOR, null) },
                onNavigateToSponsorList = { onNavigateToSettings(Routes.SPONSOR_LIST, null) },
                onNavigateToCoBuilderList = { onNavigateToSettings(Routes.CO_BUILDER_LIST, null) },
                onNavigateToAppUpdate = { onNavigateToSettings(Routes.APP_UPDATE, null) },
                onNavigateToDataManagement = { onNavigateToSettings(Routes.CONFIG_TRANSFER, null) },
                onNavigateToTrafficStats = { onNavigateToSettings(Routes.APP_TRAFFIC_STATS, null) },
                onNavigateToHiddenFeatures = { onNavigateToSettings(Routes.HIDDEN_FEATURES, null) },
                onNavigateToCacheSettings = { onNavigateToSettings(Routes.CACHE_SETTINGS, null) },
                onNavigateToOutboundProxy = { onNavigateToSettings(Routes.OUTBOUND_PROXY_SETTINGS, null) },
                onNavigateToDataCleanup = { onNavigateToSettings(Routes.DATA_CLEANUP, null) },
                onNavigateToAgentApiSettings = { onNavigateToSettings(Routes.AGENT_API_SETTINGS, null) },
                onNavigateToLogRoute = { r -> onNavigateToLogRoute(r, null) },
                onNavigateToSettingsRoute = { r -> onNavigateToSettings(r, null) },
                onNavigateToModeSelection = onNavigateToModeSelection,
                resetToHomeTrigger = resetToHomeTrigger,
                bottomBarRefreshRequested = bottomBarRefreshRequested,
                onBottomBarRefreshConsumed = onBottomBarRefreshConsumed
            )
        }
    }
}
