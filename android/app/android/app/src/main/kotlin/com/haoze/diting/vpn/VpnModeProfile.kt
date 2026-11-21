package com.haoze.diting.vpn

import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.platform.NotificationMode

/**
 * 一种工作模式与「全隧道数据面」之间的全部差异。
 *
 * 除这里的字段外，普通模式与极速模式的行为完全一致：同一套路由、同一套引擎配置、
 * 同一套通知与同一套启停流程；数据通过 [dataset] 与偏好容器名保持隔离。
 *
 * 必须用 class 而不是 data class：其中的 [runtime] 是有状态引用。
 */
internal class VpnModeProfile(
    /** 交给 VpnWatchdogNative 的模式标识，取值必须是 "normal" / "express"。 */
    val workMode: String,
    /** RuntimeEventLog 的事件域，普通模式沿用历史值 "vpn"。 */
    val eventDomain: String,
    /** 规则库、日志库与偏好容器。 */
    val dataset: RuleDataset,
    val serviceClass: Class<out FullTunnelVpnService>,
    val runtime: VpnRuntime,
    val channelId: String,
    val channelName: String,
    val channelDescription: String,
    val notificationId: Int,
    /** 通知标题与 VpnWatchNotification 里显示的模式名。 */
    val modeTitle: String,
    val notificationMode: NotificationMode,
    val startAction: String,
    val stopAction: String,
    val reloadAction: String,
    /** 运行标记与 last_* 起始配置的偏好容器。 */
    val statePrefs: String,
    /** dns_log_mode / https_bypass_rules 等设置项所在的偏好容器。 */
    val settingsPrefs: String,
    val logTag: String,
    val tunnelThreadName: String,
    val teardownThreadName: String,
    val reloadThreadName: String,
    /** Rust 路由计划模式：两种模式都走全隧道，保留常量便于将来单侧调整。 */
    val routeMode: String = ROUTE_MODE_FULL_TUNNEL,
    val showSpeedLine: Boolean = true,
    val pauseAction: Boolean = true,
) {
    val startConfig = VpnStartConfigStore(statePrefs)

    companion object {
        const val ROUTE_MODE_FULL_TUNNEL = "normal"

        val NORMAL = VpnModeProfile(
            workMode = "normal",
            eventDomain = "vpn",
            dataset = RuleDataset.NORMAL,
            serviceClass = DitingVpnService::class.java,
            runtime = VpnRuntime.NORMAL,
            channelId = "diting_vpn",
            channelName = "VPN 服务",
            channelDescription = "保持 VPN 隧道运行",
            notificationId = 1001,
            modeTitle = "普通模式",
            notificationMode = NotificationMode.NORMAL,
            startAction = "com.haoze.diting.START_VPN",
            stopAction = "com.haoze.diting.STOP_VPN",
            reloadAction = "com.haoze.diting.RELOAD_RULES",
            statePrefs = VpnRuntime.NORMAL_PREFS,
            settingsPrefs = VpnRuntime.NORMAL_PREFS,
            logTag = "DitingVpnService",
            tunnelThreadName = "diting-tunnel",
            teardownThreadName = "diting-teardown",
            reloadThreadName = "diting-rule-reload",
        )

        val EXPRESS = VpnModeProfile(
            workMode = "express",
            eventDomain = "express",
            dataset = RuleDataset.EXPRESS,
            serviceClass = ExpressVpnService::class.java,
            runtime = VpnRuntime.EXPRESS,
            channelId = "channel_express",
            channelName = "极速模式",
            channelDescription = "保持 VPN 隧道运行",
            notificationId = 2003,
            modeTitle = "极速模式",
            notificationMode = NotificationMode.EXPRESS,
            startAction = "com.haoze.diting.express.START_VPN",
            stopAction = "com.haoze.diting.express.STOP_VPN",
            reloadAction = "com.haoze.diting.express.RELOAD_RULES",
            statePrefs = VpnRuntime.EXPRESS_PREFS,
            settingsPrefs = RuleDataset.EXPRESS.prefsName(),
            logTag = "ExpressVpnService",
            tunnelThreadName = "diting-express-tunnel",
            teardownThreadName = "diting-express-teardown",
            reloadThreadName = "diting-express-rule-reload",
        )
    }
}
