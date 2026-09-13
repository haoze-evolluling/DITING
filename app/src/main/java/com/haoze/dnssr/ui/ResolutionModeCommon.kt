package com.haoze.dnssr.ui

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp

/** Hero card corner radius for the resolution mode screens, matching the settings group outer radius. */
internal val ResolutionModeHeroShape = RoundedCornerShape(28.dp)

internal fun subtitleFor(mode: DnsResolutionMode) = when (mode) {
    DnsResolutionMode.SINGLE -> "选择一个 DNS 服务商进行查询"
    DnsResolutionMode.SMART_PREDICTION -> "根据近期成功率和延迟优先选择服务，失败或超时时自动兜底"
    DnsResolutionMode.PARALLEL_RACE -> "同时查询所有选中服务，采用最先成功的结果"
    DnsResolutionMode.PRIMARY_BACKUP -> "按设置顺序查询，前一个失败后切换下一个服务"
}

internal fun descriptionFor(mode: DnsResolutionMode, count: Int) = when (mode) {
    DnsResolutionMode.SINGLE -> "选择一个服务进行查询。此选择与首页当前 DNS 服务商保持一致。"
    DnsResolutionMode.SMART_PREDICTION -> "已选择 $count 个候选服务。至少选择 2 个；系统会根据近期成功率和延迟优先选择，并在失败或超时时自动兜底。"
    DnsResolutionMode.PARALLEL_RACE -> "已选择 $count 个同时查询的服务。至少选择 2 个；查询会同时发送并采用最先成功的结果。"
    DnsResolutionMode.PRIMARY_BACKUP -> "已选择 $count 个依次尝试的服务。至少需要 1 个主服务和 1 个备用服务；长按并拖动可调整查询顺序。"
}
