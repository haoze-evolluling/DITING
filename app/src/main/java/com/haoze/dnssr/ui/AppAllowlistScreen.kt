package com.haoze.dnssr.ui

import androidx.compose.runtime.Composable

/**
 * 保持向后兼容的代理界面，自动导向整合后的“应用独立规则”统一管理页面。
 */
@Composable
fun AppAllowlistScreen(
    onBack: () -> Unit
) {
    AppRuleManagementScreen(onBack = onBack)
}

@Composable
fun AppAllowlistSettingsScreen(onBack: () -> Unit, onSelectApps: () -> Unit = {}) {
    AppRuleManagementScreen(onBack = onBack)
}

@Composable
fun AppAllowlistAppsScreen(onBack: () -> Unit) {
    AppRuleManagementScreen(onBack = onBack)
}


