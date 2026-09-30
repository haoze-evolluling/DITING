package com.haoze.diting.dnsmode.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.ui.graphics.vector.ImageVector
import com.haoze.diting.ui.FloatingBottomBarTabItem

enum class DnsNavTab(
    val route: String,
    val title: String,
    override val icon: ImageVector
) : FloatingBottomBarTabItem {
    HOME("dns_home", "概览", Icons.Filled.Home),
    SERVERS("dns_servers", "上游服务器", Icons.Filled.Dns),
    SETTINGS("dns_settings", "模式设置", Icons.Filled.Settings);

    override val tabLabel: String
        get() = title
}

