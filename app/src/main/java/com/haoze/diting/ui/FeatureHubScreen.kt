package com.haoze.diting.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Rule
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.DataUsage
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.ImportExport
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Javascript
import androidx.compose.material.icons.filled.Lan
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material.icons.filled.Troubleshoot
import androidx.compose.material.icons.filled.Update
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.diting.R
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.settings.OptionalFeature
import com.haoze.diting.ui.settings.OptionalFeaturesStore
import com.haoze.diting.ui.settings.SystemSettingsStore

internal data class FeatureHubItem(
    val title: String,
    val icon: ImageVector,
    val onClick: () -> Unit,
    val onLongClick: (() -> Unit)? = null
)

internal data class FeatureHubCategory(
    val title: String,
    val items: List<FeatureHubItem>
)

@Composable
internal fun FeatureHubScreen(
    onNavigateToProviderManagement: () -> Unit,
    onNavigateToBootstrapSettings: () -> Unit,
    onNavigateToBlockedApps: () -> Unit,
    onNavigateToAppAllowlist: () -> Unit,
    onNavigateToExcludedApps: () -> Unit,
    onNavigateToAppearanceSettings: () -> Unit,
    onNavigateToRuleControl: () -> Unit,
    onNavigateToBlacklist: () -> Unit,
    onNavigateToWhitelist: () -> Unit,
    onNavigateToRewriteList: () -> Unit,
    onNavigateToAppRules: () -> Unit,
    onNavigateToHttpInspection: () -> Unit,
    onNavigateToLogs: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToLogRetentionSettings: () -> Unit,
    onNavigateToNetworkTools: () -> Unit,
    onNavigateToHomeProviderVisibility: () -> Unit,
    onNavigateToAbout: () -> Unit,
    onNavigateToSponsor: () -> Unit,
    onNavigateToSponsorList: () -> Unit,
    onNavigateToCoBuilderList: () -> Unit,
    onNavigateToAppUpdate: () -> Unit,
    onNavigateToDataManagement: () -> Unit,
    onNavigateToTrafficStats: () -> Unit,
    onNavigateToOptionalFeatures: () -> Unit,
    onNavigateToOutboundProxy: () -> Unit,
    onNavigateToRaceModeSettings: () -> Unit,
    onNavigateToDataCleanup: () -> Unit,
    onNavigateToAgentApiSettings: () -> Unit
) {
    val context = LocalContext.current
    var showLogLongPressHint by remember {
        mutableStateOf(!SystemSettingsStore.isSettingsGuideAcknowledged(context, SettingsGuides.HOME_LOG_LONG_PRESS_ID))
    }
    val logLongPressHint = remember(context) {
        context.getString(R.string.feature_hub_long_press_hint)
    }
    val visibleFeatures by remember(context) {
        OptionalFeaturesStore.init(context)
        OptionalFeaturesStore.visibleFeaturesFlow
    }.collectAsState()

    val categories = remember(visibleFeatures, context) {
        listOf(
            FeatureHubCategory(
                context.getString(R.string.feature_hub_dns_services),
                buildList {
                    add(FeatureHubItem(context.getString(R.string.feature_hub_provider_management), Icons.Filled.Dns, onNavigateToProviderManagement))
                    add(FeatureHubItem(context.getString(R.string.feature_hub_bootstrap_settings), Icons.Filled.Public, onNavigateToBootstrapSettings))
                    if (OptionalFeature.RESOLUTION_MODE.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_resolution_mode), Icons.AutoMirrored.Filled.AltRoute, onNavigateToRaceModeSettings))
                    }
                }
            ),
            FeatureHubCategory(
                context.getString(R.string.feature_hub_policies_rules),
                listOf(
                    FeatureHubItem(context.getString(R.string.feature_hub_rule_control), Icons.AutoMirrored.Filled.Rule, onNavigateToRuleControl),
                    FeatureHubItem(context.getString(R.string.feature_hub_blacklist), Icons.Filled.Block, onNavigateToBlacklist),
                    FeatureHubItem(context.getString(R.string.feature_hub_whitelist), Icons.Filled.VerifiedUser, onNavigateToWhitelist),
                    FeatureHubItem(context.getString(R.string.feature_hub_rewrite_list), Icons.AutoMirrored.Filled.AltRoute, onNavigateToRewriteList)
                )
            ),
            FeatureHubCategory(
                context.getString(R.string.feature_hub_network_control),
                buildList {
                    if (OptionalFeature.TRAFFIC_STATS.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_traffic_stats), Icons.Filled.DataUsage, onNavigateToTrafficStats))
                    }
                    if (OptionalFeature.APP_RULES.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_app_rules), Icons.Filled.Android, onNavigateToAppRules))
                    }
                    add(FeatureHubItem(context.getString(R.string.feature_hub_blocked_apps), Icons.Filled.WifiOff, onNavigateToBlockedApps))
                    add(FeatureHubItem(context.getString(R.string.feature_hub_excluded_apps), Icons.Filled.Apps, onNavigateToExcludedApps))
                    if (OptionalFeature.OUTBOUND_PROXY.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_outbound_proxy), Icons.Filled.Lan, onNavigateToOutboundProxy))
                    }
                }
            ),
            FeatureHubCategory(
                context.getString(R.string.feature_hub_advanced_tools),
                buildList {
                    if (OptionalFeature.HTTPS_INSPECTION.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_https_inspection), Icons.Filled.Troubleshoot, onNavigateToHttpInspection))
                    }
                    if (OptionalFeature.NETWORK_TOOLS.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_network_tools), Icons.Filled.NetworkCheck, onNavigateToNetworkTools))
                    }
                    if (OptionalFeature.AGENT_API.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_agent_api), Icons.Filled.SmartToy, onNavigateToAgentApiSettings))
                    }
                }
            ),
            FeatureHubCategory(
                context.getString(R.string.feature_hub_interface_management),
                buildList {
                    if (OptionalFeature.APPEARANCE.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_appearance), Icons.Filled.Palette, onNavigateToAppearanceSettings))
                    }
                    if (OptionalFeature.SERVICE_DISPLAY.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_service_display), Icons.Filled.Visibility, onNavigateToHomeProviderVisibility))
                    }
                    add(FeatureHubItem(context.getString(R.string.feature_hub_optional_features), Icons.Filled.Extension, onNavigateToOptionalFeatures))
                    add(
                        FeatureHubItem(
                            title = context.getString(R.string.feature_hub_logs),
                            icon = Icons.Filled.History,
                            onClick = onNavigateToLogs,
                            onLongClick = {
                                SystemSettingsStore.acknowledgeSettingsGuide(context, SettingsGuides.HOME_LOG_LONG_PRESS_ID)
                                showLogLongPressHint = false
                                onNavigateToLogRetentionSettings()
                            }
                        )
                    )
                    add(FeatureHubItem(context.getString(R.string.feature_hub_other_settings), Icons.Filled.Settings, onNavigateToSettings))
                }
            ),
            FeatureHubCategory(
                context.getString(R.string.feature_hub_data_and_updates),
                buildList {
                    add(FeatureHubItem(context.getString(R.string.feature_hub_data_management), Icons.Filled.ImportExport, onNavigateToDataManagement))
                    if (OptionalFeature.DATA_CLEANUP.key in visibleFeatures) {
                        add(FeatureHubItem(context.getString(R.string.feature_hub_data_cleanup), Icons.Filled.DeleteSweep, onNavigateToDataCleanup))
                    }
                    add(FeatureHubItem(context.getString(R.string.feature_hub_updates_support), Icons.Filled.Update, onNavigateToAppUpdate))
                }
            ),
            FeatureHubCategory(
                context.getString(R.string.feature_hub_about_app),
                listOf(
                    FeatureHubItem(context.getString(R.string.feature_hub_app_info), Icons.Filled.Info, onNavigateToAbout),
                    FeatureHubItem(context.getString(R.string.feature_hub_sponsor), Icons.Filled.Favorite, onNavigateToSponsor),
                    FeatureHubItem(context.getString(R.string.feature_hub_sponsor_list), Icons.Filled.WorkspacePremium, onNavigateToSponsorList),
                    FeatureHubItem(context.getString(R.string.feature_hub_contributors), Icons.Filled.Groups, onNavigateToCoBuilderList)
                )
            )
        )
    }

    val visibleCategories = remember(categories) {
        categories.filter { it.items.isNotEmpty() }
    }

    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 24.dp, top = 20.dp, end = 24.dp, bottom = 108.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        visibleCategories.forEach { category ->
            item(
                key = "cat_${category.title}",
                span = { GridItemSpan(maxLineSpan) },
                contentType = "header"
            ) {
                Text(
                    text = category.title,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp)
                )
            }
            items(
                items = category.items,
                key = { it.title },
                contentType = { "card" }
            ) { hubItem ->
                FeatureHubCard(
                    item = hubItem,
                    showLogLongPressHint = showLogLongPressHint,
                    logLongPressHint = logLongPressHint,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

@Composable
private fun FeatureHubCard(
    item: FeatureHubItem,
    showLogLongPressHint: Boolean,
    logLongPressHint: String,
    modifier: Modifier = Modifier
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.90f else 1.0f,
        animationSpec = if (isPressed) {
            spring(
                dampingRatio = Spring.DampingRatioNoBouncy,
                stiffness = Spring.StiffnessMedium
            )
        } else {
            spring(
                dampingRatio = 0.38f,
                stiffness = Spring.StiffnessMediumLow
            )
        },
        label = "feature_card_bounce"
    )

    val hasLongClick = item.onLongClick != null
    val clickModifier = if (hasLongClick) {
        Modifier.combinedClickable(
            interactionSource = interactionSource,
            indication = null,
            onClick = item.onClick,
            onLongClick = item.onLongClick
        )
    } else {
        Modifier.clickable(
            interactionSource = interactionSource,
            indication = null,
            onClick = item.onClick
        )
    }

    Card(
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        modifier = modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clip(SettingsCornerShape)
            .then(clickModifier)
            .height(84.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Box(modifier = Modifier.fillMaxWidth()) {
                Icon(
                    imageVector = item.icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp)
                )
                if (hasLongClick && showLogLongPressHint) {
                    Text(
                        text = logLongPressHint,
                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .combinedClickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                onClick = {},
                                onLongClick = item.onLongClick
                            )
                    )
                }
            }
            Text(
                text = item.title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
