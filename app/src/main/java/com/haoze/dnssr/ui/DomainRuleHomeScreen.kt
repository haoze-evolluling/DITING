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
fun DomainRuleHomeScreen(onBack: () -> Unit, onDns: () -> Unit, onHttps: () -> Unit) {
    SettingsScaffold(title = localizedText("域名规则"), onBack = onBack) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsGroupTitle(localizedText("规则范围"))
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("DNS 域名规则"),
                        subtitle = localizedText("用于普通 DNS 请求的屏蔽、放行及 IPv4/IPv6 覆写"),
                        leadingIcon = Icons.AutoMirrored.Filled.Rule,
                        onClick = onDns
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("HTTPS 域名规则"),
                        subtitle = localizedText("仅在 HTTPS 流量检查可解密的请求中生效，包含屏蔽、放行及 CNAME 覆写"),
                        leadingIcon = Icons.AutoMirrored.Filled.Rule,
                        onClick = onHttps
                        )
                    )
                )
            }
        }
    }
}
