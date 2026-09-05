package com.haoze.dnssr.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Rule
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.DataUsage
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.ImportExport
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
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
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.components.SettingsCornerShape

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
    onNavigateToTrafficStats: () -> Unit
) {
    val context = LocalContext.current
    var showLogLongPressHint by remember {
        mutableStateOf(!AppSettings.isSettingsGuideAcknowledged(context, SettingsGuides.HOME_LOG_LONG_PRESS_ID))
    }
    val categories = listOf(
        FeatureHubCategory(
            stringResource(R.string.feature_hub_dns_services),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_provider_management), Icons.Filled.Dns, onNavigateToProviderManagement),
                FeatureHubItem(stringResource(R.string.feature_hub_bootstrap_settings), Icons.Filled.Public, onNavigateToBootstrapSettings)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_policies_rules),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_rule_control), Icons.AutoMirrored.Filled.Rule, onNavigateToRuleControl),
                FeatureHubItem(stringResource(R.string.feature_hub_blacklist), Icons.Filled.Block, onNavigateToBlacklist),
                FeatureHubItem(stringResource(R.string.feature_hub_whitelist), Icons.Filled.VerifiedUser, onNavigateToWhitelist),
                FeatureHubItem(stringResource(R.string.feature_hub_rewrite_list), Icons.AutoMirrored.Filled.AltRoute, onNavigateToRewriteList)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_network_control),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_traffic_stats), Icons.Filled.DataUsage, onNavigateToTrafficStats),
                FeatureHubItem(stringResource(R.string.feature_hub_app_rules), Icons.Filled.Android, onNavigateToAppRules),
                FeatureHubItem(stringResource(R.string.feature_hub_blocked_apps), Icons.Filled.WifiOff, onNavigateToBlockedApps),
                FeatureHubItem(stringResource(R.string.feature_hub_excluded_apps), Icons.Filled.Apps, onNavigateToExcludedApps)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_advanced_tools),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_https_inspection), Icons.Filled.Troubleshoot, onNavigateToHttpInspection),
                FeatureHubItem(stringResource(R.string.feature_hub_network_tools), Icons.Filled.NetworkCheck, onNavigateToNetworkTools)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_interface_management),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_appearance), Icons.Filled.Palette, onNavigateToAppearanceSettings),
                FeatureHubItem(stringResource(R.string.feature_hub_service_display), Icons.Filled.Visibility, onNavigateToHomeProviderVisibility),
                FeatureHubItem(
                    title = stringResource(R.string.feature_hub_logs),
                    icon = Icons.Filled.History,
                    onClick = onNavigateToLogs,
                    onLongClick = {
                        AppSettings.acknowledgeSettingsGuide(context, SettingsGuides.HOME_LOG_LONG_PRESS_ID)
                        showLogLongPressHint = false
                        onNavigateToLogRetentionSettings()
                    }
                ),
                FeatureHubItem(stringResource(R.string.feature_hub_other_settings), Icons.Filled.Settings, onNavigateToSettings)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_data_and_updates),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_data_management), Icons.Filled.ImportExport, onNavigateToDataManagement),
                FeatureHubItem(stringResource(R.string.feature_hub_updates_support), Icons.Filled.Update, onNavigateToAppUpdate)
            )
        ),
        FeatureHubCategory(
            stringResource(R.string.feature_hub_about_app),
            listOf(
                FeatureHubItem(stringResource(R.string.feature_hub_app_info), Icons.Filled.Info, onNavigateToAbout),
                FeatureHubItem(stringResource(R.string.feature_hub_sponsor), Icons.Filled.Favorite, onNavigateToSponsor),
                FeatureHubItem(stringResource(R.string.feature_hub_sponsor_list), Icons.Filled.WorkspacePremium, onNavigateToSponsorList),
                FeatureHubItem(stringResource(R.string.feature_hub_contributors), Icons.Filled.Groups, onNavigateToCoBuilderList)
            )
        )
    )

    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 24.dp, top = 20.dp, end = 24.dp, bottom = 108.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        categories.forEach { category ->
            item(span = { GridItemSpan(maxLineSpan) }) {
                Text(
                    text = category.title,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            category.items.chunked(2).forEach { rowItems ->
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        rowItems.forEach { hubItem ->
                            FeatureHubCard(
                                item = hubItem,
                                showLogLongPressHint = showLogLongPressHint,
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight()
                            )
                        }
                        if (rowItems.size == 1) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FeatureHubCard(
    item: FeatureHubItem,
    showLogLongPressHint: Boolean,
    modifier: Modifier = Modifier
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.94f else 1.0f,
        animationSpec = if (isPressed) {
            spring(
                dampingRatio = Spring.DampingRatioNoBouncy,
                stiffness = Spring.StiffnessMedium
            )
        } else {
            spring(
                dampingRatio = Spring.DampingRatioMediumBouncy,
                stiffness = Spring.StiffnessMediumLow
            )
        },
        label = "feature_card_bounce"
    )

    Card(
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        ),
        modifier = modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clip(SettingsCornerShape)
            .combinedClickable(
                interactionSource = interactionSource,
                indication = LocalIndication.current,
                onClick = item.onClick,
                onLongClick = item.onLongClick
            )
            .heightIn(min = 80.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(modifier = Modifier.fillMaxWidth()) {
                Icon(
                    imageVector = item.icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp)
                )
                if (item.title == stringResource(R.string.feature_hub_logs) && showLogLongPressHint) {
                    Text(
                        text = stringResource(R.string.feature_hub_long_press_hint),
                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .combinedClickable(
                                onClick = {},
                                onLongClick = { item.onLongClick?.invoke() }
                            )
                    )
                }
            }
            Text(text = item.title, style = MaterialTheme.typography.titleSmall)
        }
    }
}
