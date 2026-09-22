package com.haoze.diting.ui.settings

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.DataUsage
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Lan
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material.icons.filled.Troubleshoot
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.ui.graphics.vector.ImageVector
import com.haoze.diting.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class OptionalFeature(
    val key: String,
    @get:StringRes val titleRes: Int,
    val description: String,
    val icon: ImageVector
) {
    HTTPS_INSPECTION(
        key = "https_inspection",
        titleRes = R.string.feature_hub_https_inspection,
        description = "解密并检查特定应用的 HTTP(S) 流量，支持域名与 URL 过滤",
        icon = Icons.Filled.Troubleshoot
    ),
    APPEARANCE(
        key = "appearance",
        titleRes = R.string.feature_hub_appearance,
        description = "自定义日夜模式、主题色彩、组件透明度与软件壁纸背景",
        icon = Icons.Filled.Palette
    ),
    SERVICE_DISPLAY(
        key = "service_display",
        titleRes = R.string.feature_hub_service_display,
        description = "自定义在首页解析服务下拉列表中显示的服务商",
        icon = Icons.Filled.Visibility
    ),
    APP_RULES(
        key = "app_rules",
        titleRes = R.string.feature_hub_app_rules,
        description = "为特定应用单独指定 DNS 服务商或放行规则",
        icon = Icons.Filled.Android
    ),
    NETWORK_TOOLS(
        key = "network_tools",
        titleRes = R.string.feature_hub_network_tools,
        description = "提供 DNS 查询、Ping 延迟测试与网络连通性诊断工具",
        icon = Icons.Filled.NetworkCheck
    ),
    OUTBOUND_PROXY(
        key = "outbound_proxy",
        titleRes = R.string.feature_hub_outbound_proxy,
        description = "将过滤后的流量转发到本地 SOCKS5 或 HTTP 代理",
        icon = Icons.Filled.Lan
    ),
    TRAFFIC_STATS(
        key = "traffic_stats",
        titleRes = R.string.feature_hub_traffic_stats,
        description = "统计各应用的网络连接数、上传与下载流量明细",
        icon = Icons.Filled.DataUsage
    ),
    RESOLUTION_MODE(
        key = "resolution_mode",
        titleRes = R.string.feature_hub_resolution_mode,
        description = "选择单一服务、智能选择、最快响应或依次尝试策略",
        icon = Icons.AutoMirrored.Filled.AltRoute
    ),
    DATA_CLEANUP(
        key = "data_cleanup",
        titleRes = R.string.feature_hub_data_cleanup,
        description = "删除缓存、日志或域名与地址过滤规则",
        icon = Icons.Filled.DeleteSweep
    ),
    AGENT_API(
        key = "agent_api",
        titleRes = R.string.feature_hub_agent_api,
        description = "配置大语言模型接口与密钥，用于日志和网络流量分析",
        icon = Icons.Filled.SmartToy
    );

    companion object {
        fun fromKey(key: String): OptionalFeature? = entries.firstOrNull { it.key == key }
    }
}

object OptionalFeaturesStore {
    private const val KEY_OPTIONAL_FEATURES_VISIBLE = "optional_features_visible"

    private val _visibleFeaturesFlow = MutableStateFlow<Set<String>>(emptySet())
    val visibleFeaturesFlow: StateFlow<Set<String>> = _visibleFeaturesFlow.asStateFlow()

    @Volatile
    private var initialized = false

    fun init(context: Context) {
        if (!initialized) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val saved = prefs.getStringSet(KEY_OPTIONAL_FEATURES_VISIBLE, null)
            _visibleFeaturesFlow.value = saved?.toSet() ?: emptySet()
            initialized = true
        }
    }

    fun getVisibleFeatures(context: Context): Set<String> {
        init(context)
        return _visibleFeaturesFlow.value
    }

    fun isFeatureVisible(context: Context, feature: OptionalFeature): Boolean {
        return feature.key in getVisibleFeatures(context)
    }

    fun isFeatureVisible(context: Context, key: String): Boolean {
        return key in getVisibleFeatures(context)
    }

    fun setFeatureVisible(context: Context, feature: OptionalFeature, visible: Boolean) {
        val current = getVisibleFeatures(context).toMutableSet()
        if (visible) {
            current.add(feature.key)
        } else {
            current.remove(feature.key)
        }
        setVisibleFeatures(context, current)
    }

    fun setVisibleFeatures(context: Context, features: Set<String>) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_OPTIONAL_FEATURES_VISIBLE, features)
            .apply()
        _visibleFeaturesFlow.value = features
        initialized = true
    }
}
