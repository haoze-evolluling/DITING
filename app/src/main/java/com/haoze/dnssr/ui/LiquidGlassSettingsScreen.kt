package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem

@Composable
fun LiquidGlassSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var bottomBarGlassEnabled by remember {
        mutableStateOf(AppSettings.isLiquidGlassBottomBarEnabled(context))
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("液态流体效果")) }
            item {
                SettingsSurfaceGroup(content = listOf {
                    SettingsSwitchItem(
                        title = localizedText("启用液态流体效果底栏"),
                        subtitle = localizedText("为软件底部悬浮栏启用液态流体质感、磨砂光泽与流动光晕效果"),
                        checked = bottomBarGlassEnabled,
                        onCheckedChange = {
                            bottomBarGlassEnabled = it
                            AppSettings.setLiquidGlassBottomBarEnabled(context, it)
                        }
                    )
                })
            }
            item {
                SettingsInfoText(localizedText("特别致谢开源项目 KernelSU (tiann/KernelSU) 及其优秀的液态流体与动态悬浮底栏交互设计与代码启发。"))
            }
        }
    }
}
