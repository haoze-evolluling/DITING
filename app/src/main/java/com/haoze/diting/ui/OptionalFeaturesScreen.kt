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
import com.haoze.diting.ui.components.SettingsCheckboxItem
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.settings.OptionalFeature
import com.haoze.diting.ui.settings.OptionalFeaturesStore

@Composable
fun OptionalFeaturesScreen(
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val visibleFeatures by remember(context) {
        OptionalFeaturesStore.init(context)
        OptionalFeaturesStore.visibleFeaturesFlow
    }.collectAsState()

    val allFeatures = remember { OptionalFeature.entries }
    val allSelected = allFeatures.isNotEmpty() && allFeatures.all { it.key in visibleFeatures }

    SettingsScaffold(
        title = localizedText("可选功能"),
        onBack = onBack,
        actions = {
            TextButton(
                onClick = {
                    val nextFeatures = if (allSelected) {
                        emptySet()
                    } else {
                        allFeatures.map { it.key }.toSet()
                    }
                    OptionalFeaturesStore.setVisibleFeatures(context, nextFeatures)
                }
            ) {
                Text(
                    text = localizedText(if (allSelected) "取消全选" else "全选")
                )
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
                    localizedText("自定义在功能中心中显示的功能卡片。勾选后即可在功能中心中显示，未勾选的功能将保持隐藏。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
            item {
                SettingsGroupTitle(localizedText("可选功能列表"))
            }
            item {
                val surfaceItems = allFeatures.map { feature ->
                    @Composable {
                        val isChecked = feature.key in visibleFeatures
                        SettingsCheckboxItem(
                            title = localizedText(stringResource(feature.titleRes)),
                            subtitle = localizedText(feature.description),
                            leadingIcon = feature.icon,
                            checked = isChecked,
                            onCheckedChange = { checked ->
                                OptionalFeaturesStore.setFeatureVisible(context, feature, checked)
                            }
                        )
                    }
                }
                SettingsSurfaceGroup(content = surfaceItems)
            }
        }
    }
}
