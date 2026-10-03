package com.haoze.diting.ui.settings

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.ui.graphics.vector.ImageVector
import kotlinx.coroutines.flow.StateFlow

/**
 * Backward compatibility layer for [HiddenFeature].
 */
enum class OptionalFeature(
    val key: String,
    @get:StringRes val titleRes: Int,
    val description: String,
    val icon: ImageVector
) {
    HTTPS_INSPECTION(
        key = HiddenFeature.HTTPS_INSPECTION.key,
        titleRes = HiddenFeature.HTTPS_INSPECTION.titleRes,
        description = HiddenFeature.HTTPS_INSPECTION.description,
        icon = HiddenFeature.HTTPS_INSPECTION.icon
    ),
    APPEARANCE(
        key = HiddenFeature.APPEARANCE.key,
        titleRes = HiddenFeature.APPEARANCE.titleRes,
        description = HiddenFeature.APPEARANCE.description,
        icon = HiddenFeature.APPEARANCE.icon
    ),
    SERVICE_DISPLAY(
        key = HiddenFeature.SERVICE_DISPLAY.key,
        titleRes = HiddenFeature.SERVICE_DISPLAY.titleRes,
        description = HiddenFeature.SERVICE_DISPLAY.description,
        icon = HiddenFeature.SERVICE_DISPLAY.icon
    ),
    APP_RULES(
        key = HiddenFeature.APP_RULES.key,
        titleRes = HiddenFeature.APP_RULES.titleRes,
        description = HiddenFeature.APP_RULES.description,
        icon = HiddenFeature.APP_RULES.icon
    ),
    NETWORK_TOOLS(
        key = HiddenFeature.NETWORK_TOOLS.key,
        titleRes = HiddenFeature.NETWORK_TOOLS.titleRes,
        description = HiddenFeature.NETWORK_TOOLS.description,
        icon = HiddenFeature.NETWORK_TOOLS.icon
    ),
    OUTBOUND_PROXY(
        key = HiddenFeature.OUTBOUND_PROXY.key,
        titleRes = HiddenFeature.OUTBOUND_PROXY.titleRes,
        description = HiddenFeature.OUTBOUND_PROXY.description,
        icon = HiddenFeature.OUTBOUND_PROXY.icon
    ),
    TRAFFIC_STATS(
        key = HiddenFeature.TRAFFIC_STATS.key,
        titleRes = HiddenFeature.TRAFFIC_STATS.titleRes,
        description = HiddenFeature.TRAFFIC_STATS.description,
        icon = HiddenFeature.TRAFFIC_STATS.icon
    ),
    RESOLUTION_MODE(
        key = HiddenFeature.RESOLUTION_MODE.key,
        titleRes = HiddenFeature.RESOLUTION_MODE.titleRes,
        description = HiddenFeature.RESOLUTION_MODE.description,
        icon = HiddenFeature.RESOLUTION_MODE.icon
    ),
    DATA_CLEANUP(
        key = HiddenFeature.DATA_CLEANUP.key,
        titleRes = HiddenFeature.DATA_CLEANUP.titleRes,
        description = HiddenFeature.DATA_CLEANUP.description,
        icon = HiddenFeature.DATA_CLEANUP.icon
    ),
    AGENT_API(
        key = HiddenFeature.AGENT_API.key,
        titleRes = HiddenFeature.AGENT_API.titleRes,
        description = HiddenFeature.AGENT_API.description,
        icon = HiddenFeature.AGENT_API.icon
    );

    companion object {
        fun fromKey(key: String): OptionalFeature? = entries.firstOrNull { it.key == key }
    }
}

/**
 * Backward compatibility wrapper forwarding to [HiddenFeaturesStore].
 */
object OptionalFeaturesStore {
    val visibleFeaturesFlow: StateFlow<Set<String>>
        get() = HiddenFeaturesStore.hiddenFeaturesFlow

    fun init(context: Context) {
        HiddenFeaturesStore.init(context)
    }

    fun getVisibleFeatures(context: Context): Set<String> {
        val hidden = HiddenFeaturesStore.getHiddenFeatures(context)
        return HiddenFeature.entries.map { it.key }.filter { it !in hidden }.toSet()
    }

    fun isFeatureVisible(context: Context, feature: OptionalFeature): Boolean {
        return HiddenFeaturesStore.isFeatureVisible(context, feature.key)
    }

    fun isFeatureVisible(context: Context, key: String): Boolean {
        return HiddenFeaturesStore.isFeatureVisible(context, key)
    }

    fun setFeatureVisible(context: Context, feature: OptionalFeature, visible: Boolean) {
        HiddenFeaturesStore.setFeatureVisible(context, feature.key, visible)
    }

    fun setVisibleFeatures(context: Context, features: Set<String>) {
        val allKeys = HiddenFeature.entries.map { it.key }.toSet()
        val hidden = allKeys - features
        HiddenFeaturesStore.setHiddenFeatures(context, hidden)
    }
}
