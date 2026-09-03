package com.haoze.dnssr.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.FlipToBack
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Lan
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Storage
import androidx.compose.ui.graphics.vector.ImageVector

enum class SettingsSection(val title: String, val order: Int) {
    PERFORMANCE("性能优化", 0), BEHAVIOR("运行行为", 1),
    APPEARANCE("外观", 2), DATA("数据管理", 3), OTHER("其他设置", 4)
}

data class SettingsDestination(
    val route: String,
    val title: String,
    val description: String,
    val icon: ImageVector,
    val parentRoute: String? = null,
    val mainSection: SettingsSection? = null
)

object ScreenDestinations {
    private fun main(route: String, title: String, description: String, icon: ImageVector, section: SettingsSection) =
        SettingsDestination(route, title, description, icon, mainSection = section)
    private fun child(route: String, title: String, description: String, icon: ImageVector, parent: SettingsDestination) =
        SettingsDestination(route, title, description, icon, parentRoute = parent.route)

    val cacheSettings = main(Routes.CACHE_SETTINGS, "缓存设置", "缓存已解析的域名，减少重复查询", Icons.Filled.Storage, SettingsSection.PERFORMANCE)
    val raceModeProviders = main(Routes.RACE_MODE_PROVIDERS, "解析模式", "选择单一服务、智能选择、最快响应或依次尝试策略", Icons.AutoMirrored.Filled.AltRoute, SettingsSection.PERFORMANCE)
    val logRetentionSettings = main(Routes.LOG_RETENTION_SETTINGS, "日志模式", "选择 DNS 请求日志的记录范围", Icons.Filled.History, SettingsSection.PERFORMANCE)
    val foregroundBackgroundSettings = main(Routes.FOREGROUND_BACKGROUND_SETTINGS, "前后台行为", "后台隐藏、通知常驻、绕过局域网", Icons.Filled.FlipToBack, SettingsSection.BEHAVIOR)
    val outboundProxy = main(Routes.OUTBOUND_PROXY_SETTINGS, "出站代理", "将过滤后的流量转发到本地 SOCKS5 或 HTTP 代理", Icons.Filled.Lan, SettingsSection.BEHAVIOR)
    val languageSettings = main(Routes.LANGUAGE_SETTINGS, "语言设置", "选择应用界面语言", Icons.Filled.Public, SettingsSection.DATA)
    val dataCleanup = main(Routes.DATA_CLEANUP, "数据清理", "删除缓存、日志或域名规则", Icons.Filled.DeleteSweep, SettingsSection.DATA)
    val resolutionSingle = child(Routes.RESOLUTION_SINGLE, "单一服务", "选择一个 DNS 服务商进行查询", Icons.AutoMirrored.Filled.AltRoute, raceModeProviders)
    val resolutionSmart = child(Routes.RESOLUTION_SMART, "智能选择", "配置候选服务，按近期成功率和延迟优先选择", Icons.AutoMirrored.Filled.AltRoute, raceModeProviders)
    val resolutionParallel = child(Routes.RESOLUTION_PARALLEL, "最快响应", "配置同时查询并采用最先成功结果的服务", Icons.AutoMirrored.Filled.AltRoute, raceModeProviders)
    val resolutionBackup = child(Routes.RESOLUTION_BACKUP, "依次尝试", "配置失败后依次尝试的服务顺序", Icons.AutoMirrored.Filled.AltRoute, raceModeProviders)
    val all = listOf(cacheSettings, raceModeProviders, logRetentionSettings,
        foregroundBackgroundSettings, outboundProxy, languageSettings,
        dataCleanup, resolutionSingle, resolutionSmart, resolutionParallel, resolutionBackup)
    val mainEntries = all.filter { it.mainSection != null }
        .sortedWith(compareBy({ it.mainSection!!.order }, { all.indexOf(it) }))
    private val byRoute = all.associateBy { it.route }

    init {
        require(byRoute.size == all.size) { "设置路由不得重复" }
        all.forEach { destination ->
            require((destination.mainSection != null) xor (destination.parentRoute != null)) { "设置页面必须是一级入口或具有父路由: ${destination.route}" }
            require(destination.parentRoute == null || byRoute.containsKey(destination.parentRoute)) { "无效父路由: ${destination.parentRoute}" }
        }
    }
}
