package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Link
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold

@Composable
fun DomainRuleHomeScreen(
    onBack: () -> Unit,
    onDomain: () -> Unit,
    onAddress: () -> Unit,
    onAppRule: () -> Unit = {}
) {
    val context = LocalContext.current
    val domainRulesEnabled = AppSettings.isDomainRulesEnabled(context)
    val addressRulesEnabled = AppSettings.isAddressRulesEnabled(context)
    val isAddressOperational = AppSettings.isAddressRulesFullyOperational(context)
    SettingsScaffold(title = localizedText("规则"), onBack = onBack) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsGroupTitle(localizedText("规则类型"))
                val addressSubtitle = when {
                    !addressRulesEnabled -> "已禁用 · 管理 HTTPS 检查的地址规则总开关"
                    !isAddressOperational -> "未就绪 · 需配置 CA 证书与 HTTPS 流量检查"
                    else -> "管理 HTTPS 检查的地址规则总开关"
                }
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                            title = localizedText("域名规则"),
                            subtitle = localizedText(if (domainRulesEnabled) "统一管理拦截策略及订阅规则，DNS 与 HTTPS 检查共用" else "已禁用 · 统一管理拦截策略及订阅规则"),
                            leadingIcon = Icons.Filled.Language,
                            onClick = onDomain
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("应用独立规则"),
                            subtitle = localizedText("针对特定应用配置网络域名放行、专属黑白名单或默认全拦截模式"),
                            leadingIcon = Icons.Filled.Android,
                            onClick = onAppRule
                        ),
                        SettingsNavigationItemData(
                            title = localizedText("地址规则"),
                            subtitle = localizedText(addressSubtitle),
                            leadingIcon = Icons.Filled.Link,
                            onClick = onAddress
                        )
                    )
                )
            }
        }
    }
}
