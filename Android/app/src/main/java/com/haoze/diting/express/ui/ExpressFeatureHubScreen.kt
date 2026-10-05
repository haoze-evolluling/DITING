package com.haoze.diting.express.ui

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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.automirrored.filled.Rule
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.ImportExport
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Update
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.diting.R
import com.haoze.diting.ui.SettingsGuides
import com.haoze.diting.ui.components.SettingsCardMargin
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.settings.HiddenFeature
import com.haoze.diting.ui.settings.HiddenFeaturesStore
import com.haoze.diting.ui.settings.SystemSettingsStore

internal data class ExpressFeatureHubItem(
    val title: String,
    val icon: ImageVector,
    val onClick: () -> Unit,
    val onLongClick: (() -> Unit)? = null
)

internal data class ExpressFeatureHubCategory(
    val title: String,
    val items: List<ExpressFeatureHubItem>
)

/**
 * Express Mode Feature Hub Screen.
 *
 * Physically omits full-tunnel features:
 * Rewrite List, Traffic Stats, App Rules, Blocked Apps, Excluded Apps,
 * HTTPS Inspection, Outbound Proxy, Network Tools, and AI Analysis.
 */
@Composable
internal fun ExpressFeatureHubScreen(
    onNavigateToProviderManagement: () -> Unit,
    onNavigateToBootstrapSettings: () -> Unit,
    onNavigateToAppearanceSettings: () -> Unit,
    onNavigateToRuleControl: () -> Unit,
    onNavigateToBlacklist: () -> Unit,
    onNavigateToWhitelist: () -> Unit,
    onNavigateToLogs: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToLogRetentionSettings: () -> Unit,
    onNavigateToHomeProviderVisibility: () -> Unit,
    onNavigateToAbout: () -> Unit,
    onNavigateToSponsor: () -> Unit,
    onNavigateToSponsorList: () -> Unit,
    onNavigateToCoBuilderList: () -> Unit,
    onNavigateToAppUpdate: () -> Unit,
    onNavigateToDataManagement: () -> Unit,
    onNavigateToHiddenFeatures: () -> Unit,
    onNavigateToRaceModeSettings: () -> Unit,
    onNavigateToDataCleanup: () -> Unit,
    onNavigateToCacheSettings: () -> Unit = {}
) {
    val context = LocalContext.current
    var showLogLongPressHint by remember {
        mutableStateOf(!SystemSettingsStore.isSettingsGuideAcknowledged(context, SettingsGuides.HOME_LOG_LONG_PRESS_ID))
    }
    val logLongPressHint = remember(context) {
        context.getString(R.string.feature_hub_long_press_hint)
    }
    val hiddenFeatures by remember(context) {
        HiddenFeaturesStore.init(context)
        HiddenFeaturesStore.hiddenFeaturesFlow
    }.collectAsState()

    val categories = remember(hiddenFeatures, context) {
        fun isVisible(feature: HiddenFeature): Boolean = feature.key !in hiddenFeatures

        listOf(
            // 1. DNS 服务 (4 项)
            ExpressFeatureHubCategory(
                context.getString(R.string.feature_hub_dns_services),
                buildList {
                    if (isVisible(HiddenFeature.PROVIDER_MANAGEMENT)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_provider_management), Icons.Filled.Dns, onNavigateToProviderManagement))
                    }
                    if (isVisible(HiddenFeature.BOOTSTRAP_SETTINGS)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_bootstrap_settings), Icons.Filled.Public, onNavigateToBootstrapSettings))
                    }
                    if (isVisible(HiddenFeature.RESOLUTION_MODE)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_resolution_mode), Icons.AutoMirrored.Filled.AltRoute, onNavigateToRaceModeSettings))
                    }
                    if (isVisible(HiddenFeature.CACHE_SETTINGS)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_cache_settings), Icons.Filled.Storage, onNavigateToCacheSettings))
                    }
                }
            ),

            // 2. 策略与规则 (3 项，覆写名单已在极速模式物理移除)
            ExpressFeatureHubCategory(
                context.getString(R.string.feature_hub_policies_rules),
                buildList {
                    if (isVisible(HiddenFeature.RULE_CONTROL)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_rule_control), Icons.AutoMirrored.Filled.Rule, onNavigateToRuleControl))
                    }
                    if (isVisible(HiddenFeature.BLACKLIST)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_blacklist), Icons.Filled.Block, onNavigateToBlacklist))
                    }
                    if (isVisible(HiddenFeature.WHITELIST)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_whitelist), Icons.Filled.VerifiedUser, onNavigateToWhitelist))
                    }
                }
            ),

            // 3. 界面与设置 (4 项)
            ExpressFeatureHubCategory(
                context.getString(R.string.feature_hub_interface_management),
                buildList {
                    if (isVisible(HiddenFeature.APPEARANCE)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_appearance), Icons.Filled.Palette, onNavigateToAppearanceSettings))
                    }
                    if (isVisible(HiddenFeature.SERVICE_DISPLAY)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_service_display), Icons.Filled.Visibility, onNavigateToHomeProviderVisibility))
                    }
                    add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_hidden_features), Icons.Filled.VisibilityOff, onNavigateToHiddenFeatures))
                    if (isVisible(HiddenFeature.OTHER_SETTINGS)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_other_settings), Icons.Filled.Settings, onNavigateToSettings))
                    }
                }
            ),

            // 4. 数据与维护 (4 项)
            ExpressFeatureHubCategory(
                context.getString(R.string.feature_hub_data_and_updates),
                buildList {
                    if (isVisible(HiddenFeature.LOGS)) {
                        add(
                            ExpressFeatureHubItem(
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
                    }
                    if (isVisible(HiddenFeature.DATA_MANAGEMENT)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_data_management), Icons.Filled.ImportExport, onNavigateToDataManagement))
                    }
                    if (isVisible(HiddenFeature.DATA_CLEANUP)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_data_cleanup), Icons.Filled.DeleteSweep, onNavigateToDataCleanup))
                    }
                    if (isVisible(HiddenFeature.APP_UPDATE)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_updates_support), Icons.Filled.Update, onNavigateToAppUpdate))
                    }
                }
            ),

            // 5. 关于软件 (4 项)
            ExpressFeatureHubCategory(
                context.getString(R.string.feature_hub_about_app),
                buildList {
                    if (isVisible(HiddenFeature.APP_INFO)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_app_info), Icons.Filled.Info, onNavigateToAbout))
                    }
                    if (isVisible(HiddenFeature.SPONSOR)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_sponsor), Icons.Filled.Favorite, onNavigateToSponsor))
                    }
                    if (isVisible(HiddenFeature.SPONSOR_LIST)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_sponsor_list), Icons.Filled.WorkspacePremium, onNavigateToSponsorList))
                    }
                    if (isVisible(HiddenFeature.CONTRIBUTORS)) {
                        add(ExpressFeatureHubItem(context.getString(R.string.feature_hub_contributors), Icons.Filled.Groups, onNavigateToCoBuilderList))
                    }
                }
            )
        )
    }

    val visibleCategories = remember(categories) {
        categories.filter { it.items.isNotEmpty() }
    }

    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = SettingsCardMargin, top = 20.dp, end = SettingsCardMargin, bottom = 108.dp),
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
                ExpressFeatureHubCard(
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
private fun ExpressFeatureHubCard(
    item: ExpressFeatureHubItem,
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
        label = "express_feature_card_bounce"
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
