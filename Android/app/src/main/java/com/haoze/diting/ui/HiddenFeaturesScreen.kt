package com.haoze.diting.ui

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
import com.haoze.diting.ui.settings.FeatureCategory
import com.haoze.diting.ui.settings.HiddenFeature
import com.haoze.diting.ui.settings.HiddenFeaturesStore

@Composable
fun HiddenFeaturesScreen(
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val hiddenFeatures by remember(context) {
        HiddenFeaturesStore.init(context)
        HiddenFeaturesStore.hiddenFeaturesFlow
    }.collectAsState()

    val hasHiddenFeatures = hiddenFeatures.isNotEmpty()

    SettingsScaffold(
        title = localizedText(stringResource(R.string.feature_hub_hidden_features)),
        onBack = onBack,
        actions = {
            if (hasHiddenFeatures) {
                TextButton(
                    onClick = {
                        HiddenFeaturesStore.resetToDefault(context)
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
                val categoryFeatures = HiddenFeature.entries.filter { it.category == category }
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
