package com.haoze.diting.express.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.haoze.diting.R
import com.haoze.diting.ui.components.SettingsCheckboxItem
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.settings.FeatureCategory
import com.haoze.diting.ui.settings.HiddenFeature
import com.haoze.diting.ui.settings.HiddenFeaturesStore

/**
 * Set of features supported in Express Mode.
 *
 * Physically omits full-tunnel features:
 * - REWRITE_LIST (under POLICIES_RULES)
 * - All of NETWORK_CONTROL (TRAFFIC_STATS, APP_RULES, BLOCKED_APPS, EXCLUDED_APPS)
 * - All of ADVANCED_TOOLS (HTTPS_INSPECTION, OUTBOUND_PROXY, NETWORK_TOOLS, AGENT_API)
 */
val EXPRESS_SUPPORTED_FEATURES: Set<HiddenFeature> = setOf(
    // 1. DNS 服务 (4 项)
    HiddenFeature.PROVIDER_MANAGEMENT,
    HiddenFeature.BOOTSTRAP_SETTINGS,
    HiddenFeature.RESOLUTION_MODE,
    HiddenFeature.CACHE_SETTINGS,

    // 2. 策略与规则 (3 项)
    HiddenFeature.RULE_CONTROL,
    HiddenFeature.BLACKLIST,
    HiddenFeature.WHITELIST,

    // 3. 界面与设置 (3 项)
    HiddenFeature.APPEARANCE,
    HiddenFeature.SERVICE_DISPLAY,
    HiddenFeature.OTHER_SETTINGS,

    // 4. 数据与维护 (4 项)
    HiddenFeature.LOGS,
    HiddenFeature.DATA_MANAGEMENT,
    HiddenFeature.DATA_CLEANUP,
    HiddenFeature.APP_UPDATE,

    // 5. 关于软件 (4 项)
    HiddenFeature.APP_INFO,
    HiddenFeature.SPONSOR,
    HiddenFeature.SPONSOR_LIST,
    HiddenFeature.CONTRIBUTORS
)

val EXPRESS_SUPPORTED_FEATURE_KEYS: Set<String> =
    EXPRESS_SUPPORTED_FEATURES.map { it.key }.toSet()

/**
 * Dedicated Hidden Features Management Screen for Express Mode.
 */
@Composable
fun ExpressHiddenFeaturesScreen(
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val hiddenFeatures by remember(context) {
        HiddenFeaturesStore.init(context)
        HiddenFeaturesStore.hiddenFeaturesFlow
    }.collectAsState()

    val hasHiddenFeatures = remember(hiddenFeatures) {
        hiddenFeatures.any { it in EXPRESS_SUPPORTED_FEATURE_KEYS }
    }

    SettingsScaffold(
        title = localizedText(stringResource(R.string.feature_hub_hidden_features)),
        onBack = onBack,
        actions = {
            if (hasHiddenFeatures) {
                TextButton(
                    onClick = {
                        val current = HiddenFeaturesStore.getHiddenFeatures(context).toMutableSet()
                        current.removeAll(EXPRESS_SUPPORTED_FEATURE_KEYS)
                        HiddenFeaturesStore.setHiddenFeatures(context, current)
                    },
                    shape = SettingsCornerShape
                ) {
                    Text(
                        text = localizedText(stringResource(R.string.hidden_features_restore_all))
                    )
                }
            }
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsInfoText(
                    localizedText(stringResource(R.string.hidden_features_info)),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            FeatureCategory.entries.forEach { category ->
                val categoryFeatures = HiddenFeature.entries.filter {
                    it.category == category && it in EXPRESS_SUPPORTED_FEATURES
                }
                if (categoryFeatures.isNotEmpty()) {
                    item(key = "title_${category.id}") {
                        SettingsGroupTitle(localizedText(stringResource(category.titleRes)))
                    }
                    item(key = "group_${category.id}") {
                        val surfaceItems = categoryFeatures.map { feature ->
                            @Composable {
                                val isVisible = feature.key !in hiddenFeatures
                                val statusPrefix = if (isVisible) "" else "${localizedText("已在功能中心隐藏")} · "
                                SettingsCheckboxItem(
                                    title = localizedText(stringResource(feature.titleRes)),
                                    subtitle = "$statusPrefix${localizedText(feature.description)}",
                                    leadingIcon = feature.icon,
                                    checked = isVisible,
                                    onCheckedChange = { visible ->
                                        HiddenFeaturesStore.setFeatureVisible(context, feature, visible)
                                    }
                                )
                            }
                        }
                        SettingsSurfaceGroup(content = surfaceItems)
                    }
                }
            }
        }
    }
}
