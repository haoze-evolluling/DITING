package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsNavigationGroup
import com.haoze.diting.ui.components.SettingsNavigationItemData
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.settings.AppearanceSettingsStore

@Composable
fun AppearanceSettingsScreen(
    onBack: () -> Unit,
    title: String,
    onNavigateToDayNightMode: () -> Unit,
    onNavigateToThemeColorSettings: () -> Unit,
    onNavigateToHomeComponentOpacity: () -> Unit,
    onNavigateToHomeSentence: () -> Unit,
    onNavigateToNotificationSettings: () -> Unit,
    onNavigateToCustomBackground: () -> Unit,
    onNavigateToBottomBarCustomization: () -> Unit
) {
    val context = LocalContext.current
    val mode = AppearanceSettingsStore.getAppThemeMode(context)
    val colorStyle = AppearanceSettingsStore.getThemeColorStyle(context)
    val bottomBarCount = AppearanceSettingsStore.getBottomBarDestinations(context).size

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("界面显示")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("日夜模式"),
                            subtitle = localizedText("选择应用使用的浅色或深色外观"),
                            value = localizedText(mode.displayName),
                            onClick = onNavigateToDayNightMode
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("主题色配置"),
                            subtitle = localizedText("选择应用界面的强调色"),
                            value = localizedText(colorStyle.displayName),
                            onClick = onNavigateToThemeColorSettings
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("首页透明度"),
                            subtitle = localizedText("分别调整首页按钮、选择框与文字的透明度"),
                            onClick = onNavigateToHomeComponentOpacity
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("底栏自定义"),
                            subtitle = localizedText("自定义底栏按钮与显示顺序（2～4个）"),
                            value = "$bottomBarCount " + localizedText("个按钮"),
                            onClick = onNavigateToBottomBarCustomization
                        )
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("首页内容")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("首页句子"),
                            subtitle = localizedText("分别设置 DNS 服务开启和关闭时的句子"),
                            onClick = onNavigateToHomeSentence
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("通知栏设置"),
                            subtitle = localizedText("分别设置 DNS 服务开启和关闭时的通知文案与网速显示"),
                            onClick = onNavigateToNotificationSettings
                        )
                    )
                )
            }
            item { SettingsGroupTitle(localizedText("背景与动效")) }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("软件背景"),
                            subtitle = localizedText("选取手机图片作为应用背景"),
                            onClick = onNavigateToCustomBackground
                        )
                    )
                )
            }
        }
    }
}
