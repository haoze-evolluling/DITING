package com.haoze.diting.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import kotlin.math.roundToInt
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup

@Composable
fun HomeComponentOpacityScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var powerButton by remember { mutableStateOf(AppearanceSettingsStore.getHomePowerButtonOpacity(context)) }
    var providerSelector by remember { mutableStateOf(AppearanceSettingsStore.getHomeProviderSelectorOpacity(context)) }
    var modeButton by remember { mutableStateOf(AppearanceSettingsStore.getHomeModeButtonOpacity(context)) }
    var poem by remember { mutableStateOf(AppearanceSettingsStore.getHomePoemOpacity(context)) }
    var dnsDetail by remember { mutableStateOf(AppearanceSettingsStore.getHomeDnsDetailOpacity(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            item { SettingsGroupTitle(localizedText("交互组件")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            OpacitySlider(localizedText("启动按钮"), powerButton, { powerButton = it }) {
                                AppearanceSettingsStore.setHomePowerButtonOpacity(context, powerButton)
                            }
                        },
                        {
                            OpacitySlider(localizedText("解析服务选择框"), providerSelector, { providerSelector = it }) {
                                AppearanceSettingsStore.setHomeProviderSelectorOpacity(context, providerSelector)
                            }
                        },
                        {
                            OpacitySlider(localizedText("模式切换按钮"), modeButton, { modeButton = it }) {
                                AppearanceSettingsStore.setHomeModeButtonOpacity(context, modeButton)
                            }
                        }
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("文字")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            OpacitySlider(localizedText("首页古诗"), poem, { poem = it }) {
                                AppearanceSettingsStore.setHomePoemOpacity(context, poem)
                            }
                        },
                        {
                            OpacitySlider(localizedText("DNS 服务详情"), dnsDetail, { dnsDetail = it }) {
                                AppearanceSettingsStore.setHomeDnsDetailOpacity(context, dnsDetail)
                            }
                        }
                    )
                )
            }
        }
    }
}

@Composable
private fun OpacitySlider(
    title: String,
    value: Float,
    onValueChange: (Float) -> Unit,
    onValueChangeFinished: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Text("${localizedText(title)} · ${(value * 100).roundToInt()}%")
        Slider(
            value = value,
            onValueChange = onValueChange,
            onValueChangeFinished = onValueChangeFinished,
            valueRange = 0.1f..1f,
            steps = 8,
            modifier = Modifier.fillMaxWidth()
        )
    }
}
