package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Rule
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold

@Composable
fun DomainRuleHomeScreen(onBack: () -> Unit, onDomain: () -> Unit, onAddress: () -> Unit) {
    SettingsScaffold(title = localizedText("规则"), onBack = onBack) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsGroupTitle(localizedText("规则类型"))
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("域名规则"),
                        subtitle = localizedText("统一管理域名屏蔽、放行及 IPv4/IPv6 覆写，DNS 与 HTTPS 检查共用"),
                        leadingIcon = Icons.AutoMirrored.Filled.Rule,
                        onClick = onDomain
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("地址规则"),
                        subtitle = localizedText("管理 HTTPS 解密后匹配的 URL 地址和路径前缀屏蔽、放行规则"),
                        leadingIcon = Icons.AutoMirrored.Filled.Rule,
                        onClick = onAddress
                        )
                    )
                )
            }
        }
    }
}
