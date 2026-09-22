package com.haoze.diting.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.DataUsage
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.Settings
import androidx.compose.ui.graphics.vector.ImageVector
import org.json.JSONArray

/**
 * Available destinations that can be placed on the floating bottom navigation bar.
 */
enum class BottomBarDestination(
    val id: String,
    val title: String,
    val tabLabel: String,
    val description: String,
    val icon: ImageVector
) {
    HOME(
        id = "home",
        title = "谛听",
        tabLabel = "首页",
        description = "核心服务开关与实时解析详情",
        icon = Icons.Default.Home
    ),
    FEATURE_HUB(
        id = "feature_hub",
        title = "功能中心",
        tabLabel = "功能中心",
        description = "规则、工具与各功能统一入口",
        icon = Icons.Default.Apps
    ),
    LOG_DASHBOARD(
        id = "log_dashboard",
        title = "日志仪表盘",
        tabLabel = "日志仪表盘",
        description = "实时请求统计与规则拦截详情",
        icon = Icons.Filled.History
    ),
    APP_TRAFFIC_STATS(
        id = "app_traffic_stats",
        title = "应用流量统计",
        tabLabel = "流量统计",
        description = "各应用流量消耗与实时速率统计",
        icon = Icons.Filled.DataUsage
    ),
    NETWORK_TOOLS(
        id = "network_tools",
        title = "网络诊断",
        tabLabel = "网络诊断",
        description = "DNS 测速、Ping 与网络诊断工具",
        icon = Icons.Filled.NetworkCheck
    ),
    SETTINGS(
        id = "settings",
        title = "更多设置",
        tabLabel = "设置",
        description = "系统常规偏好与其它高级设置",
        icon = Icons.Filled.Settings
    );

    companion object {
        const val MIN_COUNT = 2
        const val MAX_COUNT = 4

        val DEFAULT_DESTINATIONS: List<BottomBarDestination> = listOf(HOME, FEATURE_HUB, LOG_DASHBOARD)

        fun fromId(id: String): BottomBarDestination? = entries.firstOrNull { it.id == id }

        fun parseJsonList(jsonStr: String?): List<BottomBarDestination> {
            if (jsonStr.isNullOrBlank()) return DEFAULT_DESTINATIONS
            return try {
                val array = JSONArray(jsonStr)
                val items = mutableListOf<BottomBarDestination>()
                for (i in 0 until array.length()) {
                    val id = array.optString(i)
                    val destination = fromId(id)
                    if (destination != null && destination !in items) {
                        items.add(destination)
                    }
                }
                if (items.size < MIN_COUNT) {
                    DEFAULT_DESTINATIONS
                } else {
                    items.take(MAX_COUNT)
                }
            } catch (_: Exception) {
                DEFAULT_DESTINATIONS
            }
        }

        fun toJsonList(destinations: List<BottomBarDestination>): String {
            val validItems = destinations.distinct().take(MAX_COUNT)
            val finalItems = if (validItems.size < MIN_COUNT) DEFAULT_DESTINATIONS else validItems
            val array = JSONArray()
            finalItems.forEach { array.put(it.id) }
            return array.toString()
        }
    }
}
