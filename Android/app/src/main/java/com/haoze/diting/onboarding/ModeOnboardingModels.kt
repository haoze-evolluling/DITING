package com.haoze.diting.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.FilterAlt
import androidx.compose.material.icons.outlined.Lan
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.ui.graphics.vector.ImageVector
import com.haoze.diting.permission.AppPermission
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * 模式特性卡片模型
 */
data class ModeFeatureItem(
    val title: String,
    val description: String,
    val icon: ImageVector
)

/**
 * 快速上手提示项模型
 */
data class QuickGuideTip(
    val title: String,
    val description: String,
    val icon: ImageVector = Icons.Outlined.CheckCircle
)

/**
 * 模式专属新手引导全量配置
 */
data class ModeOnboardingConfig(
    val mode: AppWorkMode,
    val step1Title: String,
    val step1Subtitle: String,
    val features: List<ModeFeatureItem>,
    val step2Title: String,
    val step2Subtitle: String,
    val permissions: List<AppPermission>,
    val step3Title: String,
    val step3Subtitle: String,
    val guideTips: List<QuickGuideTip>
)

object ModeOnboardingRegistry {

    fun getConfig(mode: AppWorkMode): ModeOnboardingConfig {
        return when (mode) {
            AppWorkMode.NORMAL -> ModeOnboardingConfig(
                mode = mode,
                step1Title = "普通模式特性与架构",
                step1Subtitle = "全隧道 Go 用户态网络栈，提供最全方位的流量控制与深度防护",
                features = listOf(
                    ModeFeatureItem(
                        title = "全隧道 Go 网络栈接管",
                        description = "基于 gVisor netstack 用户态网络协议栈，在本地构建完整的虚拟网络通道，接管并精细过滤进出流量。",
                        icon = Icons.Outlined.Layers
                    ),
                    ModeFeatureItem(
                        title = "全功能规则过滤与分流",
                        description = "支持 AdGuard 兼容规则、Hosts 覆写、按应用排除/白名单/禁止联网分流以及出站 SOCKS5 代理联动。",
                        icon = Icons.Outlined.FilterAlt
                    ),
                    ModeFeatureItem(
                        title = "可选 HTTPS 流量检查与监控",
                        description = "按需解密指定目标应用 HTTPS 流量并进行 URL 级过滤，支持应用流量排行与悬浮窗实时监控。",
                        icon = Icons.Outlined.Security
                    )
                ),
                step2Title = "运行环境与权限就绪",
                step2Subtitle = "为了让普通模式正常运行，请完成必要权限与保活配置",
                permissions = listOf(
                    AppPermission.VPN,
                    AppPermission.NOTIFICATION,
                    AppPermission.PACKAGE_QUERY,
                    AppPermission.BATTERY_OPTIMIZATION
                ),
                step3Title = "快速上手指南",
                step3Subtitle = "完成基础设置后即可一键开启服务",
                guideTips = listOf(
                    QuickGuideTip(
                        title = "选择优质上游 DNS",
                        description = "主页支持切换阿里云、腾讯 DNSPod、Cloudflare 等主流安全加密上游，或自定义 DoH/DoT 节点。",
                        icon = Icons.Outlined.Dns
                    ),
                    QuickGuideTip(
                        title = "按需配置应用管控",
                        description = "若有银行或特定应用不需要经过过滤，可在“应用管理”中一键加入“排除列表”。",
                        icon = Icons.Outlined.Tune
                    ),
                    QuickGuideTip(
                        title = "随时开启与停止",
                        description = "轻触主页中央电源按钮即可启动全隧道保护；亦可通过系统快捷设置磁贴快速开关。",
                        icon = Icons.Outlined.Speed
                    )
                )
            )

            AppWorkMode.EXPRESS -> ModeOnboardingConfig(
                mode = mode,
                step1Title = "极速模式特性与架构",
                step1Subtitle = "纯 Kotlin 原生轻量实现，专为纯净加速与极低功耗而生",
                features = listOf(
                    ModeFeatureItem(
                        title = "纯 Kotlin 原生窄路由",
                        description = "零 Go 内核依赖，窄路由仅捕获 DNS 流量（UDP/TCP 53）与劫持列表，其余全部流量直连物理网络，极低功耗。",
                        icon = Icons.Outlined.Bolt
                    ),
                    ModeFeatureItem(
                        title = "4 种智能上游调度策略",
                        description = "支持单一服务、EWMA 智能优选、并发最快竞速以及备援依次尝试，确保最快最稳的解析响应。",
                        icon = Icons.Outlined.Speed
                    ),
                    ModeFeatureItem(
                        title = "轻量并发安全缓存与规则",
                        description = "采用 64 分片并发安全 LRU 缓存，完整支持黑白名单规则过滤与乐观容灾解析。",
                        icon = Icons.Outlined.Memory
                    )
                ),
                step2Title = "运行环境与权限就绪",
                step2Subtitle = "极速模式仅需极简权限即可顺畅运行",
                permissions = listOf(
                    AppPermission.VPN,
                    AppPermission.NOTIFICATION,
                    AppPermission.BATTERY_OPTIMIZATION
                ),
                step3Title = "快速上手指南",
                step3Subtitle = "极速模式即开即用，享受丝滑轻快的解析体验",
                guideTips = listOf(
                    QuickGuideTip(
                        title = "窄路由极速通行",
                        description = "除 DNS 请求外所有网络流量均直接通行，不消耗多余内存与 CPU，适合追求极致续航与老旧设备。",
                        icon = Icons.Outlined.Bolt
                    ),
                    QuickGuideTip(
                        title = "最快响应竞速模式",
                        description = "推荐在主页将解析模式设为“最快响应”，多上游并发竞速，自动采用最快返回的结果。",
                        icon = Icons.Outlined.Speed
                    ),
                    QuickGuideTip(
                        title = "一键开启运行",
                        description = "点击电源按钮即可建立窄路由 VPN 保护；支持通过快捷设置磁贴随时开关。",
                        icon = Icons.Outlined.CheckCircle
                    )
                )
            )

            AppWorkMode.DNS -> ModeOnboardingConfig(
                mode = mode,
                step1Title = "独立服务器模式特性与架构",
                step1Subtitle = "在局域网内提供独立 DNS 解析服务，供其他设备接入，免占 VPN 槽位",
                features = listOf(
                    ModeFeatureItem(
                        title = "局域网独立 DNS 监听",
                        description = "本机直接监听 0.0.0.0:1053（UDP/TCP），供局域网内的路由器、电脑、电视与手机作为 DNS 上游使用。",
                        icon = Icons.Outlined.Lan
                    ),
                    ModeFeatureItem(
                        title = "完全不占用 VPN 槽位",
                        description = "不创建任何 Android VPN 接口，不拦截本机应用流量，不与手机上其他 VPN 或代理工具冲突。",
                        icon = Icons.Outlined.Dns
                    ),
                    ModeFeatureItem(
                        title = "共享规则库与缓存加速",
                        description = "接入设备全部享受本地 64 分片并发缓存与黑白名单拦截，一人配置，全家共享净化。",
                        icon = Icons.Outlined.Security
                    )
                ),
                step2Title = "运行保障与权限就绪",
                step2Subtitle = "提示：服务器模式无需 VPN 权限！请授权前台通知与保活以保证服务存活",
                permissions = listOf(
                    AppPermission.NOTIFICATION,
                    AppPermission.BATTERY_OPTIMIZATION
                ),
                step3Title = "局域网接入指南",
                step3Subtitle = "启动服务后，将其他设备的 DNS 服务器地址指向本机 IP 即可",
                guideTips = listOf(
                    QuickGuideTip(
                        title = "查看本机局域网 IP 与端口",
                        description = "服务默认在端口 1053 监听。向导下方已自动探测到本机当前局域网 IP 地址。",
                        icon = Icons.Outlined.Lan
                    ),
                    QuickGuideTip(
                        title = "配置外部设备或路由器",
                        description = "在电脑、电视或手机 Wi-Fi 设置中将 DNS 服务器设为本机 IP；或在路由器 DHCP 中统一下发。",
                        icon = Icons.Outlined.Tune
                    ),
                    QuickGuideTip(
                        title = "保持后台稳定运行",
                        description = "务必允许忽略电池优化，并保持 Wi-Fi 连接稳定，以便持续为局域网设备提供解析服务。",
                        icon = Icons.Outlined.CheckCircle
                    )
                )
            )
        }
    }
}
