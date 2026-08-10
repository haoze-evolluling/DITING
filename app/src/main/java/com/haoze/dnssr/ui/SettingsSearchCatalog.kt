package com.haoze.dnssr.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.FlipToBack
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.ImportExport
import androidx.compose.material.icons.filled.Policy
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Lan
import androidx.compose.ui.graphics.vector.ImageVector

enum class SettingsSection(val title: String, val order: Int) {
    RESOLUTION("解析设置", 0), PERFORMANCE("性能优化", 1), BEHAVIOR("运行行为", 2),
    APPEARANCE("外观", 3), DATA("数据管理", 4), OTHER("其他设置", 5)
}

data class SettingsSearchItem(
    val title: String,
    val description: String,
    val keywords: List<String> = emptyList(),
    val targetRoute: String? = null
)

data class SettingsDestination(
    val route: String,
    val title: String,
    val description: String,
    val icon: ImageVector,
    val parentRoute: String? = null,
    val mainSection: SettingsSection? = null,
    val keywords: List<String> = emptyList(),
    val searchable: Boolean = true,
    val searchItems: List<SettingsSearchItem> = emptyList()
)

internal data class SettingsSearchEntry(
    val title: String,
    val description: String,
    val breadcrumb: List<String>,
    val route: String,
    val icon: ImageVector,
    val keywords: List<String> = emptyList()
) {
    val resultSubtitle: String
        get() = (listOf("应用设置") + breadcrumb).joinToString(" · ") +
            description.takeIf { it.isNotBlank() }?.let { " · $it" }.orEmpty()

    fun matches(query: String): Boolean =
        (listOf(title, description) + breadcrumb + keywords).any { it.contains(query, ignoreCase = true) }
}

internal object SettingsSearchCatalog {
    private fun page(title: String, description: String, section: String, route: String, icon: ImageVector, vararg keywords: String) =
        SettingsSearchEntry(title, description, listOf(section, title), route, icon, keywords.toList())

    private fun option(title: String, description: String, section: String, page: String, route: String, icon: ImageVector, vararg keywords: String) =
        SettingsSearchEntry(title, description, listOf(section, page), route, icon, keywords.toList())

    private fun nestedPage(title: String, description: String, section: String, parent: String, route: String, icon: ImageVector, vararg keywords: String) =
        SettingsSearchEntry(title, description, listOf(section, parent, title), route, icon, keywords.toList())

    private fun nestedOption(title: String, description: String, section: String, parent: String, page: String, route: String, icon: ImageVector, vararg keywords: String) =
        SettingsSearchEntry(title, description, listOf(section, parent, page), route, icon, keywords.toList())

    val entries: List<SettingsSearchEntry> = listOf(
        page("服务商管理", "选择、添加或编辑 DoH/DoT 服务", "解析设置", Routes.PROVIDER_MANAGEMENT, Icons.Filled.Dns, "DNS", "服务地址", "协议"),
        option("新增 DNS 服务商", "添加自定义解析服务", "解析设置", "服务商管理", Routes.PROVIDER_MANAGEMENT, Icons.Filled.Dns, "添加", "DoH", "DoT"),
        option("服务商名称", "设置自定义 DNS 服务的名称", "解析设置", "服务商管理", Routes.PROVIDER_MANAGEMENT, Icons.Filled.Dns),
        option("解析地址", "设置 DoH 请求地址", "解析设置", "服务商管理", Routes.PROVIDER_MANAGEMENT, Icons.Filled.Dns, "URL"),
        option("服务器地址", "设置 DoT 服务器地址", "解析设置", "服务商管理", Routes.PROVIDER_MANAGEMENT, Icons.Filled.Dns, "主机名"),
        option("端口", "设置 DoT 服务端口", "解析设置", "服务商管理", Routes.PROVIDER_MANAGEMENT, Icons.Filled.Dns),
        page("Bootstrap 设置", "配置全局 Bootstrap DNS 与智慧权重", "解析设置", Routes.BOOTSTRAP_SETTINGS, Icons.Filled.Public, "IP", "递归 DNS"),
        option("启用 Bootstrap IP", "使用独立递归 DNS 解析服务商域名", "解析设置", "Bootstrap 设置", Routes.BOOTSTRAP_SETTINGS, Icons.Filled.Public, "全局开关"),
        option("内置 Bootstrap IP", "管理内置解析 IP", "解析设置", "Bootstrap 设置", Routes.BOOTSTRAP_SETTINGS, Icons.Filled.Public),
        option("自定义 Bootstrap IP", "添加和管理自定义解析 IP", "解析设置", "Bootstrap 设置", Routes.BOOTSTRAP_SETTINGS, Icons.Filled.Public, "添加 IP"),
        option("名称（可选）", "设置自定义 Bootstrap IP 名称", "解析设置", "Bootstrap 设置", Routes.BOOTSTRAP_SETTINGS, Icons.Filled.Public),
        option("IP 地址", "填写自定义 Bootstrap IP", "解析设置", "Bootstrap 设置", Routes.BOOTSTRAP_SETTINGS, Icons.Filled.Public),
        page("缓存设置", "缓存已解析的域名，减少重复查询", "性能优化", Routes.CACHE_SETTINGS, Icons.Filled.Storage, "DNS 缓存"),
        option("本地 DNS 缓存", "启用或关闭本地响应缓存", "性能优化", "缓存设置", Routes.CACHE_SETTINGS, Icons.Filled.Storage, "缓存策略", "预设"),
        option("保守", "跟随上游 TTL", "性能优化", "缓存设置", Routes.CACHE_SETTINGS, Icons.Filled.Storage),
        option("标准", "最长 1 小时，短 TTL 至少 1 分钟", "性能优化", "缓存设置", Routes.CACHE_SETTINGS, Icons.Filled.Storage),
        option("高命中", "最长 6 小时，短 TTL 至少 2 分钟", "性能优化", "缓存设置", Routes.CACHE_SETTINGS, Icons.Filled.Storage),
        page("解析模式", "选择单一服务、智能选择、最快响应或依次尝试策略", "性能优化", Routes.RACE_MODE_PROVIDERS, Icons.AutoMirrored.Filled.AltRoute, "DNS 策略"),
        option("内置服务协议", "仅切换阿里云和 DNSPod 内置服务的 DNS、DoT 或 DoH 协议", "性能优化", "解析模式", Routes.RACE_MODE_PROVIDERS, Icons.AutoMirrored.Filled.AltRoute, "阿里云", "DNSPod"),
        nestedPage("单一服务", "选择一个 DNS 服务商进行查询", "性能优化", "解析模式", Routes.RESOLUTION_SINGLE, Icons.AutoMirrored.Filled.AltRoute),
        nestedPage("智能选择", "配置候选服务，按近期成功率和延迟优先选择", "性能优化", "解析模式", Routes.RESOLUTION_SMART, Icons.AutoMirrored.Filled.AltRoute),
        nestedPage("最快响应", "配置同时查询并采用最先成功结果的服务", "性能优化", "解析模式", Routes.RESOLUTION_PARALLEL, Icons.AutoMirrored.Filled.AltRoute),
        nestedPage("依次尝试", "配置失败后依次尝试的服务顺序", "性能优化", "解析模式", Routes.RESOLUTION_BACKUP, Icons.AutoMirrored.Filled.AltRoute, "查询顺序"),
        page("日志模式", "选择 DNS 请求日志的记录范围", "性能优化", Routes.LOG_RETENTION_SETTINGS, Icons.Filled.History, "保留时间", "自动清理"),
        option("DNS 请求日志", "设置日志记录范围", "性能优化", "日志模式", Routes.LOG_RETENTION_SETTINGS, Icons.Filled.History),
        option("自动清理时间", "设置日志保留天数", "性能优化", "日志模式", Routes.LOG_RETENTION_SETTINGS, Icons.Filled.History, "保留天数"),
        option("悬浮窗日志", "后台显示悬浮球并查看最近请求", "性能优化", "日志模式", Routes.LOG_RETENTION_SETTINGS, Icons.Filled.History, "悬浮窗"),

        page("前后台行为", "后台隐藏、通知常驻和电池设置", "运行行为", Routes.FOREGROUND_BACKGROUND_SETTINGS, Icons.Filled.FlipToBack),
        option("后台隐藏", "隐藏最近任务卡片并禁用任务截图", "运行行为", "前后台行为", Routes.FOREGROUND_BACKGROUND_SETTINGS, Icons.Filled.FlipToBack, "最近任务"),
        option("通知常驻", "VPN 未运行时在通知栏常驻提醒", "运行行为", "前后台行为", Routes.FOREGROUND_BACKGROUND_SETTINGS, Icons.Filled.FlipToBack),
        option("忽略电池优化", "前往系统电池优化设置", "运行行为", "前后台行为", Routes.FOREGROUND_BACKGROUND_SETTINGS, Icons.Filled.FlipToBack, "后台运行"),
        page("排除应用", "指定使用系统 DNS 的应用", "运行行为", Routes.EXCLUDED_APPS, Icons.Filled.Apps, "应用列表", "系统 DNS"),
        page("导入与导出", "备份或恢复自定义服务与规则订阅", "数据管理", Routes.CONFIG_TRANSFER, Icons.Filled.ImportExport, "备份", "恢复"),
        nestedPage("设置配置", "选择配置内容并导入或导出", "数据管理", "导入与导出", Routes.CONFIG_IMPORT_EXPORT, Icons.Filled.ImportExport, "JSON"),
        option("自定义 DNS 服务商", "导入或导出名称、协议和解析地址", "数据管理", "设置配置", Routes.CONFIG_IMPORT_EXPORT, Icons.Filled.ImportExport),
        option("自定义 Bootstrap IP", "导入或导出名称、IP 和启用状态", "数据管理", "设置配置", Routes.CONFIG_IMPORT_EXPORT, Icons.Filled.ImportExport),
        option("网络规则订阅", "导入或导出订阅名称和链接", "数据管理", "设置配置", Routes.CONFIG_IMPORT_EXPORT, Icons.Filled.ImportExport),
        option("排除应用", "导入或导出使用系统 DNS 的应用包名", "数据管理", "设置配置", Routes.CONFIG_IMPORT_EXPORT, Icons.Filled.ImportExport),
        option("导出配置", "将勾选内容保存为 JSON 配置文件", "数据管理", "设置配置", Routes.CONFIG_IMPORT_EXPORT, Icons.Filled.ImportExport),
        option("导入配置", "合并配置并跳过本机已有项目", "数据管理", "设置配置", Routes.CONFIG_IMPORT_EXPORT, Icons.Filled.ImportExport),
        nestedPage("规则导出", "将当前生效规则导出为 TXT 文件", "数据管理", "导入与导出", Routes.RULE_EXPORT, Icons.Filled.ImportExport, "订阅文件"),
        nestedPage("规则导入", "从本地文件导入域名和地址规则", "数据管理", "导入与导出", Routes.RULE_IMPORT, Icons.Filled.ImportExport, "订阅文件", "hosts", "地址", "备份"),
        page("数据清理", "删除缓存、日志或域名规则", "数据管理", Routes.DATA_CLEANUP, Icons.Filled.DeleteSweep, "清空数据"),
        option("删除请求日志", "清除 DNS 和 HTTP 的历史请求记录", "数据管理", "数据清理", Routes.DATA_CLEANUP, Icons.Filled.DeleteSweep),
        option("删除 DNS 缓存", "移除已缓存的解析结果", "数据管理", "数据清理", Routes.DATA_CLEANUP, Icons.Filled.DeleteSweep),
        option("恢复 DNS 默认权重", "清除竞速模式的健康样本", "数据管理", "数据清理", Routes.DATA_CLEANUP, Icons.Filled.DeleteSweep),
        option("恢复 Bootstrap 权重", "清除 Bootstrap DNS 解析健康样本", "数据管理", "数据清理", Routes.DATA_CLEANUP, Icons.Filled.DeleteSweep),
        option("删除全部规则", "清除手动添加和订阅导入的所有域名规则", "数据管理", "数据清理", Routes.DATA_CLEANUP, Icons.Filled.DeleteSweep),
        option("重置所有新手引导", "让所有首次进入说明再次显示", "数据管理", "数据清理", Routes.DATA_CLEANUP, Icons.Filled.DeleteSweep),
        // 更新与支持从应用设置移动到首页功能中心，不再作为设置搜索项。
    )
}

object ScreenDestinations {
    private fun main(route: String, title: String, description: String, icon: ImageVector, section: SettingsSection, vararg keywords: String) =
        SettingsDestination(route, title, description, icon, mainSection = section, keywords = keywords.toList())
    private fun child(route: String, title: String, description: String, icon: ImageVector, parent: SettingsDestination, searchable: Boolean = true, vararg keywords: String) =
        SettingsDestination(route, title, description, icon, parentRoute = parent.route, searchable = searchable, keywords = keywords.toList())

    val providerManagement = main(Routes.PROVIDER_MANAGEMENT, "服务商管理", "选择、添加或编辑 DoH/DoT 服务", Icons.Filled.Dns, SettingsSection.RESOLUTION, "DNS", "服务地址", "协议")
    val bootstrapSettings = main(Routes.BOOTSTRAP_SETTINGS, "Bootstrap 设置", "配置全局 Bootstrap DNS 与智慧权重", Icons.Filled.Public, SettingsSection.RESOLUTION, "IP", "递归 DNS")
    val cacheSettings = main(Routes.CACHE_SETTINGS, "缓存设置", "缓存已解析的域名，减少重复查询", Icons.Filled.Storage, SettingsSection.PERFORMANCE, "DNS 缓存")
    val raceModeProviders = main(Routes.RACE_MODE_PROVIDERS, "解析模式", "选择单一服务、智能选择、最快响应或依次尝试策略", Icons.AutoMirrored.Filled.AltRoute, SettingsSection.PERFORMANCE, "DNS 策略")
    val logRetentionSettings = main(Routes.LOG_RETENTION_SETTINGS, "日志模式", "选择 DNS 请求日志的记录范围", Icons.Filled.History, SettingsSection.PERFORMANCE)
    val foregroundBackgroundSettings = main(Routes.FOREGROUND_BACKGROUND_SETTINGS, "前后台行为", "后台隐藏、通知常驻", Icons.Filled.FlipToBack, SettingsSection.BEHAVIOR)
    val excludedApps = main(Routes.EXCLUDED_APPS, "排除应用", "指定使用系统 DNS 的应用", Icons.Filled.Apps, SettingsSection.BEHAVIOR)
    val outboundProxy = main(Routes.OUTBOUND_PROXY_SETTINGS, "出站代理", "将过滤后的流量转发到本地 SOCKS5 或 HTTP 代理", Icons.Filled.Lan, SettingsSection.BEHAVIOR, "Clash", "SOCKS5", "HTTP CONNECT")
    val languageSettings = main(Routes.LANGUAGE_SETTINGS, "语言设置", "选择应用界面语言", Icons.Filled.Public, SettingsSection.DATA, "中文", "English", "系统语言")
    val configTransfer = main(Routes.CONFIG_TRANSFER, "导入与导出", "备份或恢复自定义服务与规则订阅", Icons.Filled.ImportExport, SettingsSection.DATA)
    val dataCleanup = main(Routes.DATA_CLEANUP, "数据清理", "删除缓存、日志或域名规则", Icons.Filled.DeleteSweep, SettingsSection.DATA)
    val configImportExport = child(Routes.CONFIG_IMPORT_EXPORT, "设置配置", "选择配置内容并导入或导出", Icons.Filled.ImportExport, configTransfer)
    val ruleExport = child(Routes.RULE_EXPORT, "规则导出", "将当前生效规则导出为 TXT 文件", Icons.Filled.ImportExport, configTransfer)
    val ruleImport = child(Routes.RULE_IMPORT, "规则导入", "从本地文件导入域名和地址规则", Icons.Filled.ImportExport, configTransfer)
    val resolutionSingle = child(Routes.RESOLUTION_SINGLE, "单一服务", "选择一个 DNS 服务商进行查询", Icons.AutoMirrored.Filled.AltRoute, raceModeProviders)
    val resolutionSmart = child(Routes.RESOLUTION_SMART, "智能选择", "配置候选服务，按近期成功率和延迟优先选择", Icons.AutoMirrored.Filled.AltRoute, raceModeProviders)
    val resolutionParallel = child(Routes.RESOLUTION_PARALLEL, "最快响应", "配置同时查询并采用最先成功结果的服务", Icons.AutoMirrored.Filled.AltRoute, raceModeProviders)
    val resolutionBackup = child(Routes.RESOLUTION_BACKUP, "依次尝试", "配置失败后依次尝试的服务顺序", Icons.AutoMirrored.Filled.AltRoute, raceModeProviders)
    val all = listOf(providerManagement, bootstrapSettings, cacheSettings, raceModeProviders, logRetentionSettings,
        foregroundBackgroundSettings, excludedApps, outboundProxy, languageSettings,
        configTransfer, dataCleanup, configImportExport,
        ruleExport, ruleImport, resolutionSingle, resolutionSmart, resolutionParallel, resolutionBackup)
    val mainEntries = all.filter { it.mainSection != null }
        .sortedWith(compareBy({ it.mainSection!!.order }, { all.indexOf(it) }))
    private val byRoute = all.associateBy { it.route }

    fun breadcrumbFor(destination: SettingsDestination): List<String> {
        val parents = generateSequence(destination.parentRoute?.let(byRoute::get)) { it.parentRoute?.let(byRoute::get) }.toList().asReversed()
        val section = (destination.mainSection ?: parents.firstOrNull()?.mainSection)?.title
        return listOfNotNull(section) + parents.map { it.title } + destination.title
    }

    internal val searchEntries: List<SettingsSearchEntry> = (all.filter { it.searchable }.flatMap { destination ->
        listOf(SettingsSearchEntry(destination.title, destination.description, breadcrumbFor(destination), destination.route, destination.icon, destination.keywords)) +
            destination.searchItems.map { item -> SettingsSearchEntry(item.title, item.description, breadcrumbFor(destination), item.targetRoute ?: destination.route, destination.icon, item.keywords) }
    } + SettingsSearchCatalog.entries.filter { it.breadcrumb.lastOrNull() != it.title })

    init {
        require(byRoute.size == all.size) { "设置路由不得重复" }
        all.forEach { destination ->
            require((destination.mainSection != null) xor (destination.parentRoute != null)) { "设置页面必须是一级入口或具有父路由: ${destination.route}" }
            require(destination.parentRoute == null || byRoute.containsKey(destination.parentRoute)) { "无效父路由: ${destination.parentRoute}" }
            destination.searchItems.mapNotNull { it.targetRoute }.forEach { require(byRoute.containsKey(it)) { "搜索目标不是设置路由: $it" } }
        }
    }
}
