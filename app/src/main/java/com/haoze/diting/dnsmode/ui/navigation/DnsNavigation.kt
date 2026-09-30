package com.haoze.diting.dnsmode.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.ui.graphics.vector.ImageVector

enum class DnsNavTab(
    val route: String,
    val title: String,
    val icon: ImageVector
) {
    HOME("dns_home", "概览", Icons.Outlined.Home),
    SERVERS("dns_servers", "上游服务器", Icons.Outlined.Dns),
    SETTINGS("dns_settings", "模式设置", Icons.Outlined.Settings);
}
