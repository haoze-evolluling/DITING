package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold

@Composable
fun LogHomeScreen(
    onBack: () -> Unit,
    onNavigateToDnsLogs: () -> Unit,
    onNavigateToDnsCache: () -> Unit,
    onNavigateToRaceStats: () -> Unit,
    onNavigateToBootstrapStats: () -> Unit,
    onNavigateToSubscriptionInterceptionStats: () -> Unit,
    onNavigateToAppInterceptionStats: () -> Unit
) {
    val scrollState = rememberScrollState()

    SettingsScaffold(
        title = localizedText("日志"),
        onBack = onBack
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsGroupTitle(localizedText("记录与统计"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                    title = localizedText("请求记录"),
                    subtitle = localizedText("查看 DNS 与 HTTPS 请求和处理结果"),
                    onClick = onNavigateToDnsLogs
                    ),
                    SettingsNavigationItemData(
                    title = localizedText("缓存记录"),
                    subtitle = localizedText("查看、搜索或清理已缓存的 DNS 结果"),
                    onClick = onNavigateToDnsCache
                    ),
                    SettingsNavigationItemData(
                    title = localizedText("竞速解析"),
                    subtitle = localizedText("查看服务商的响应速度和成功情况"),
                    onClick = onNavigateToRaceStats
                    ),
                    SettingsNavigationItemData(
                    title = localizedText("Bootstrap 解析"),
                    subtitle = localizedText("查看 DNS 服务地址的解析情况"),
                    onClick = onNavigateToBootstrapStats
                    ),
                    SettingsNavigationItemData(
                    title = localizedText("规则拦截"),
                    subtitle = localizedText("查看各订阅拦截请求的次数和占比"),
                    onClick = onNavigateToSubscriptionInterceptionStats
                    ),
                    SettingsNavigationItemData(
                    title = localizedText("应用拦截统计"),
                    subtitle = localizedText("按应用查看 HTTP(S) 请求、拦截次数和拦截率"),
                    onClick = onNavigateToAppInterceptionStats
                    )
                )
            )
        }
    }
}
