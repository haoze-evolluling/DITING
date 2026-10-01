package com.haoze.diting.ui.settings

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.automirrored.filled.Rule
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.DataUsage
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.ImportExport
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lan
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Troubleshoot
import androidx.compose.material.icons.filled.Update
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.ui.graphics.vector.ImageVector
import com.haoze.diting.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class FeatureCategory(
    val id: String,
    @get:StringRes val titleRes: Int
) {
    DNS_SERVICES("dns_services", R.string.feature_hub_dns_services),
    POLICIES_RULES("policies_rules", R.string.feature_hub_policies_rules),
    NETWORK_CONTROL("network_control", R.string.feature_hub_network_control),
    ADVANCED_TOOLS("advanced_tools", R.string.feature_hub_advanced_tools),
    INTERFACE_SETTINGS("interface_settings", R.string.feature_hub_interface_management),
    DATA_MAINTENANCE("data_maintenance", R.string.feature_hub_data_and_updates),
    ABOUT_APP("about_app", R.string.feature_hub_about_app);
}

enum class HiddenFeature(
    val key: String,
    @get:StringRes val titleRes: Int,
    val description: String,
    val icon: ImageVector,
    val category: FeatureCategory
) {
    // 1. DNS 服务
    PROVIDER_MANAGEMENT(
        key = "provider_management",
        titleRes = R.string.feature_hub_provider_management,
        description = "配置与管理 DoH、DoT 与传统 DNS 解析服务商",
        icon = Icons.Filled.Dns,
        category = FeatureCategory.DNS_SERVICES
    ),
    BOOTSTRAP_SETTINGS(
        key = "bootstrap_settings",
        titleRes = R.string.feature_hub_bootstrap_settings,
        description = "配置用于首次解析加密上游域名的引导 DNS 节点",
        icon = Icons.Filled.Public,
        category = FeatureCategory.DNS_SERVICES
    ),
    RESOLUTION_MODE(
        key = "resolution_mode",
        titleRes = R.string.feature_hub_resolution_mode,
        description = "选择单一服务、智能选择、最快响应或依次尝试策略",
        icon = Icons.AutoMirrored.Filled.AltRoute,
        category = FeatureCategory.DNS_SERVICES
    ),
    CACHE_SETTINGS(
        key = "cache_settings",
        titleRes = R.string.feature_hub_cache_settings,
        description = "配置 DNS 缓存开关、缓存策略与最大最小生存时间 (TTL)",
        icon = Icons.Filled.Storage,
        category = FeatureCategory.DNS_SERVICES
    ),

    // 2. 策略与规则
    RULE_CONTROL(
        key = "rule_control",
        titleRes = R.string.feature_hub_rule_control,
        description = "统一管理拦截策略开关与在线网络规则订阅",
        icon = Icons.AutoMirrored.Filled.Rule,
        category = FeatureCategory.POLICIES_RULES
    ),
    BLACKLIST(
        key = "blacklist",
        titleRes = R.string.feature_hub_blacklist,
        description = "自定义屏蔽域名列表，匹配时返回拦截响应",
        icon = Icons.Filled.Block,
        category = FeatureCategory.POLICIES_RULES
    ),
    WHITELIST(
        key = "whitelist",
        titleRes = R.string.feature_hub_whitelist,
        description = "自定义放行域名列表，豁免所有规则直接放行",
        icon = Icons.Filled.VerifiedUser,
        category = FeatureCategory.POLICIES_RULES
    ),
    REWRITE_LIST(
        key = "rewrite_list",
        titleRes = R.string.feature_hub_rewrite_list,
        description = "自定义域名覆写指向特定 IPv4/IPv6 或 CNAME",
        icon = Icons.AutoMirrored.Filled.AltRoute,
        category = FeatureCategory.POLICIES_RULES
    ),

    // 3. 网络管控
    TRAFFIC_STATS(
        key = "traffic_stats",
        titleRes = R.string.feature_hub_traffic_stats,
        description = "统计各应用的网络连接数、上传与下载流量明细",
        icon = Icons.Filled.DataUsage,
        category = FeatureCategory.NETWORK_CONTROL
    ),
    APP_RULES(
        key = "app_rules",
        titleRes = R.string.feature_hub_app_rules,
        description = "为特定应用单独指定专属域名放行与网络规则",
        icon = Icons.Filled.Android,
        category = FeatureCategory.NETWORK_CONTROL
    ),
    BLOCKED_APPS(
        key = "blocked_apps",
        titleRes = R.string.feature_hub_blocked_apps,
        description = "在本地隧道层拦截指定应用的全部网络外联",
        icon = Icons.Filled.WifiOff,
        category = FeatureCategory.NETWORK_CONTROL
    ),
    EXCLUDED_APPS(
        key = "excluded_apps",
        titleRes = R.string.feature_hub_excluded_apps,
        description = "允许指定应用绕过本软件直连网络",
        icon = Icons.Filled.Apps,
        category = FeatureCategory.NETWORK_CONTROL
    ),

    // 4. 进阶工具
    HTTPS_INSPECTION(
        key = "https_inspection",
        titleRes = R.string.feature_hub_https_inspection,
        description = "解密并检查特定应用的 HTTP(S) 流量，支持域名与 URL 过滤",
        icon = Icons.Filled.Troubleshoot,
        category = FeatureCategory.ADVANCED_TOOLS
    ),
    OUTBOUND_PROXY(
        key = "outbound_proxy",
        titleRes = R.string.feature_hub_outbound_proxy,
        description = "将过滤后的流量转发到本地 SOCKS5 或 HTTP 代理",
        icon = Icons.Filled.Lan,
        category = FeatureCategory.ADVANCED_TOOLS
    ),
    NETWORK_TOOLS(
        key = "network_tools",
        titleRes = R.string.feature_hub_network_tools,
        description = "提供 DNS 查询、Ping 延迟测试与网络连通性诊断工具",
        icon = Icons.Filled.NetworkCheck,
        category = FeatureCategory.ADVANCED_TOOLS
    ),
    AGENT_API(
        key = "agent_api",
        titleRes = R.string.feature_hub_agent_api,
        description = "配置大语言模型接口与密钥，用于日志研判与网络流量分析",
        icon = Icons.Filled.SmartToy,
        category = FeatureCategory.ADVANCED_TOOLS
    ),

    // 5. 界面与设置
    APPEARANCE(
        key = "appearance",
        titleRes = R.string.feature_hub_appearance,
        description = "自定义日夜模式、主题色彩、组件透明度与软件壁纸背景",
        icon = Icons.Filled.Palette,
        category = FeatureCategory.INTERFACE_SETTINGS
    ),
    SERVICE_DISPLAY(
        key = "service_display",
        titleRes = R.string.feature_hub_service_display,
        description = "自定义在首页解析服务下拉列表中显示的服务商",
        icon = Icons.Filled.Visibility,
        category = FeatureCategory.INTERFACE_SETTINGS
    ),
    OTHER_SETTINGS(
        key = "other_settings",
        titleRes = R.string.feature_hub_other_settings,
        description = "语言切换、前后台行为、通知设置等全局配置",
        icon = Icons.Filled.Settings,
        category = FeatureCategory.INTERFACE_SETTINGS
    ),

    // 6. 数据与维护
    LOGS(
        key = "logs",
        titleRes = R.string.feature_hub_logs,
        description = "实时解析统计、请求明细查询与日志导出",
        icon = Icons.Filled.History,
        category = FeatureCategory.DATA_MAINTENANCE
    ),
    DATA_MANAGEMENT(
        key = "data_management",
        titleRes = R.string.feature_hub_data_management,
        description = "导出与导入服务商、规则订阅及个性化设置",
        icon = Icons.Filled.ImportExport,
        category = FeatureCategory.DATA_MAINTENANCE
    ),
    DATA_CLEANUP(
        key = "data_cleanup",
        titleRes = R.string.feature_hub_data_cleanup,
        description = "删除缓存、日志或域名与地址过滤规则",
        icon = Icons.Filled.DeleteSweep,
        category = FeatureCategory.DATA_MAINTENANCE
    ),
    APP_UPDATE(
        key = "app_update",
        titleRes = R.string.feature_hub_updates_support,
        description = "检查软件新版本发布、查看更新日志",
        icon = Icons.Filled.Update,
        category = FeatureCategory.DATA_MAINTENANCE
    ),

    // 7. 关于软件
    APP_INFO(
        key = "app_info",
        titleRes = R.string.feature_hub_app_info,
        description = "查看软件版本信息、核心技术架构与开源地址",
        icon = Icons.Filled.Info,
        category = FeatureCategory.ABOUT_APP
    ),
    SPONSOR(
        key = "sponsor",
        titleRes = R.string.feature_hub_sponsor,
        description = "支持谛听项目持续维护与开发",
        icon = Icons.Filled.Favorite,
        category = FeatureCategory.ABOUT_APP
    ),
    SPONSOR_LIST(
        key = "sponsor_list",
        titleRes = R.string.feature_hub_sponsor_list,
        description = "鸣谢支持谛听项目的赞助者",
        icon = Icons.Filled.WorkspacePremium,
        category = FeatureCategory.ABOUT_APP
    ),
    CONTRIBUTORS(
        key = "contributors",
        titleRes = R.string.feature_hub_contributors,
        description = "感谢为谛听贡献代码与建议的共建者",
        icon = Icons.Filled.Groups,
        category = FeatureCategory.ABOUT_APP
    );

    companion object {
        fun fromKey(key: String): HiddenFeature? = entries.firstOrNull { it.key == key }
    }
}

object HiddenFeaturesStore {
    private const val KEY_HIDDEN_FEATURES = "hidden_features_set"

    private val _hiddenFeaturesFlow = MutableStateFlow<Set<String>>(emptySet())
    val hiddenFeaturesFlow: StateFlow<Set<String>> = _hiddenFeaturesFlow.asStateFlow()

    @Volatile
    private var initialized = false

    fun init(context: Context) {
        if (!initialized) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val saved = prefs.getStringSet(KEY_HIDDEN_FEATURES, null)
            _hiddenFeaturesFlow.value = saved?.toSet() ?: emptySet()
            initialized = true
        }
    }

    fun getHiddenFeatures(context: Context): Set<String> {
        init(context)
        return _hiddenFeaturesFlow.value
    }

    fun isFeatureVisible(context: Context, key: String): Boolean {
        return key !in getHiddenFeatures(context)
    }

    fun isFeatureVisible(context: Context, feature: HiddenFeature): Boolean {
        return feature.key !in getHiddenFeatures(context)
    }

    fun isFeatureHidden(context: Context, key: String): Boolean {
        return key in getHiddenFeatures(context)
    }

    fun isFeatureHidden(context: Context, feature: HiddenFeature): Boolean {
        return feature.key in getHiddenFeatures(context)
    }

    fun setFeatureHidden(context: Context, key: String, hidden: Boolean) {
        val current = getHiddenFeatures(context).toMutableSet()
        if (hidden) {
            current.add(key)
        } else {
            current.remove(key)
        }
        setHiddenFeatures(context, current)
    }

    fun setFeatureHidden(context: Context, feature: HiddenFeature, hidden: Boolean) {
        setFeatureHidden(context, feature.key, hidden)
    }

    fun setFeatureVisible(context: Context, key: String, visible: Boolean) {
        setFeatureHidden(context, key, !visible)
    }

    fun setFeatureVisible(context: Context, feature: HiddenFeature, visible: Boolean) {
        setFeatureHidden(context, feature.key, !visible)
    }

    fun setHiddenFeatures(context: Context, hiddenFeatures: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_HIDDEN_FEATURES, hiddenFeatures)
            .apply()
        _hiddenFeaturesFlow.value = hiddenFeatures
        initialized = true
    }

    fun resetToDefault(context: Context) {
        setHiddenFeatures(context, emptySet())
    }
}
