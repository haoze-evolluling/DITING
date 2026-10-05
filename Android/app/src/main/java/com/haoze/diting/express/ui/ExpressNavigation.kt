package com.haoze.diting.express.ui

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.ui.graphics.vector.ImageVector
import com.haoze.diting.ui.BottomBarDestination
import com.haoze.diting.ui.FloatingBottomBarTabItem
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import org.json.JSONArray

/**
 * Bottom navigation destinations exclusively available in Express Mode.
 *
 * Full-tunnel destinations (such as APP_TRAFFIC_STATS and NETWORK_TOOLS)
 * are physically excluded from this model.
 */
enum class ExpressBottomBarDestination(
    val id: String,
    val title: String,
    override val tabLabel: String,
    val description: String,
    override val icon: ImageVector
) : FloatingBottomBarTabItem {
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

        val DEFAULT_DESTINATIONS: List<ExpressBottomBarDestination> =
            listOf(HOME, FEATURE_HUB, LOG_DASHBOARD)

        fun fromId(id: String): ExpressBottomBarDestination? =
            entries.firstOrNull { it.id == id }

        fun fromLegacy(destination: BottomBarDestination): ExpressBottomBarDestination? = when (destination) {
            BottomBarDestination.HOME -> HOME
            BottomBarDestination.FEATURE_HUB -> FEATURE_HUB
            BottomBarDestination.LOG_DASHBOARD -> LOG_DASHBOARD
            BottomBarDestination.SETTINGS -> SETTINGS
            else -> null
        }

        fun getDestinations(context: Context): List<ExpressBottomBarDestination> {
            val legacy = AppearanceSettingsStore.getBottomBarDestinations(context)
            val mapped = legacy.mapNotNull { fromLegacy(it) }
            return if (mapped.size >= MIN_COUNT) {
                mapped.take(MAX_COUNT)
            } else {
                DEFAULT_DESTINATIONS
            }
        }

        fun parseJsonList(jsonStr: String?): List<ExpressBottomBarDestination> {
            if (jsonStr.isNullOrBlank()) return DEFAULT_DESTINATIONS
            return try {
                val array = JSONArray(jsonStr)
                val items = mutableListOf<ExpressBottomBarDestination>()
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

        fun toJsonList(destinations: List<ExpressBottomBarDestination>): String {
            val validItems = destinations.distinct().take(MAX_COUNT)
            val finalItems = if (validItems.size < MIN_COUNT) DEFAULT_DESTINATIONS else validItems
            val array = JSONArray()
            finalItems.forEach { array.put(it.id) }
            return array.toString()
        }
    }
}
