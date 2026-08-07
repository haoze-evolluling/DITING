package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
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
fun ConfigTransferScreen(
    onBack: () -> Unit,
    title: String = "导入与导出",
    onNavigateToConfigImportExport: () -> Unit,
    onNavigateToRuleExport: () -> Unit,
    onNavigateToRuleImport: () -> Unit
) {
    SettingsScaffold(title = title, onBack = onBack) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsGroupTitle(localizedText("配置"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                    title = localizedText("设置配置"),
                    subtitle = localizedText("备份或恢复自定义服务与规则订阅"),
                    onClick = onNavigateToConfigImportExport
                    )
                )
            )
            SettingsGroupTitle(localizedText("规则"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                    title = localizedText("规则导出"),
                    subtitle = localizedText("将当前生效规则导出为可订阅的 TXT 文件"),
                    onClick = onNavigateToRuleExport
                    ),
                    SettingsNavigationItemData(
                    title = localizedText("规则导入"),
                    subtitle = localizedText("从本地文件导入 DNS、hosts 和 HTTPS 规则"),
                    onClick = onNavigateToRuleImport
                    )
                )
            )
        }
    }
}
