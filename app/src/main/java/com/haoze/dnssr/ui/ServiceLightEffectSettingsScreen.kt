package com.haoze.dnssr.ui

import android.os.Build
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem

@Composable
fun ServiceLightEffectSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    val customBackgroundEnabled = AppSettings.isCustomBackgroundEnabled(context)
    var enabled by remember { mutableStateOf(AppSettings.isServiceLightEffectEnabled(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            item { SettingsGroupTitle(localizedText("服务动态光影")) }
            item {
                SettingsSurfaceGroup(content = listOf {
                    SettingsSwitchItem(
                        title = localizedText("启用服务动态光影"),
                        subtitle = localizedText(when {
                            customBackgroundEnabled -> "软件背景已启用，服务动态光影不可同时使用"
                            supported -> "启动和关闭服务时，光影从电源按钮向整个页面展开或收回"
                            else -> "需要 Android 13 或更高版本"
                        }),
                        checked = enabled,
                        enabled = supported && !customBackgroundEnabled,
                        onCheckedChange = {
                            enabled = it
                            AppSettings.setServiceLightEffectEnabled(context, it)
                        }
                    )
                })
            }
            if (supported && !customBackgroundEnabled) {
                item {
                    SettingsInfoText(localizedText("光影效果代码来源于开源项目:\nhttps://github.com/badnng/Hyper-pick-up-code/"))
                }
            }
        }
    }
}
