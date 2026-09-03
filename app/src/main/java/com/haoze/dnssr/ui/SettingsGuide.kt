package com.haoze.dnssr.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsCheckboxItem

data class SettingsGuide(
    val id: String,
    val title: String,
    val message: String,
    val warning: String? = null,
    val acknowledgement: String? = null
)

private fun englishGuide(guide: SettingsGuide): SettingsGuide = when (guide.id) {
    "provider_management" -> guide.copy(
        title = "Provider management",
        message = "Providers determine which upstream DNS services DNSSR uses for domain queries. You can add, edit, enable, disable, and reorder DoH or DoT services, as well as configure their addresses and connection parameters.\n\nMultiple reliable providers can improve availability, but an incorrect address, protocol, or certificate configuration may cause resolution failures.\n\nAfter changes, return to the home screen to check service status and run a latency test to confirm connectivity on the current network."
    )
    "bootstrap" -> guide.copy(
        title = "Bootstrap settings",
        message = "Bootstrap DNS resolves a provider's own domain before connecting to an encrypted DNS service, avoiding a circular dependency. You can configure global Bootstrap addresses and their weight policy.\n\nIf a server is unreachable, too slow, or returns an error, DoH or DoT providers that depend on that domain may not work.\n\nKeep the reliable defaults unless you have a specific need. After changing them, confirm the result using service status and real DNS queries."
    )
    "latency_test" -> guide.copy(
        title = "Speed test",
        message = "The speed test sends real queries for the chosen domain to selected DNS providers and compares their resolution time on the current network.\n\nResults are affected by network conditions, cache state, the target domain, and provider load, so one result does not represent long-term performance. Test a stable, frequently used domain several times before drawing conclusions.\n\nThe test only helps choose providers; it does not change the enabled providers or resolution policy automatically."
    )
    "cache" -> guide.copy(
        title = "Cache settings",
        message = "DNS cache stores recent resolution results and reuses them during their validity period, reducing repeated requests and improving access speed. You can adjust cache capacity, expiration, and fallback behavior.\n\nA larger cache or longer retention can improve the hit rate but may delay address changes. Aggressive cleanup increases queries and battery use.\n\nExisting entries may remain after a configuration change. Open Data cleanup when you need to clear them manually."
    )
    "resolution_mode" -> guide.copy(
        title = "Resolution mode",
        message = "Resolution mode controls how enabled providers are selected for each DNS request.\n\nSingle provider queries one service. Smart selection prefers providers with better recent success rates and latency, then falls back automatically. Fastest response queries all selected providers and uses the first successful result. Primary-backup mode follows the configured order.\n\nSmart selection, fastest response, and primary-backup mode require at least two providers. Changing the mode does not delete provider settings."
    )
    "log_mode" -> guide.copy(
        title = "Log mode",
        message = "Log mode controls which DNS requests DNSSR records and how much troubleshooting detail is retained. More complete logs can identify the requesting app, matched rule, and responding provider, but use more storage and leave more local access records.\n\nLong-press the Logs card in the home feature menu to open these settings directly.\n\nUse a less detailed range when you only need service status, and increase detail temporarily when investigating a rule or resolution issue. Logs stay on this device and can be deleted from Data cleanup."
    )
    "config_transfer" -> guide.copy(
        title = "Import and export",
        message = "Import and export lets you move DNSSR custom configuration and custom rules between devices, including providers, custom rules, app settings, and rule subscriptions. Exported files may contain service addresses or other personal settings, so store them carefully.\n\nImport will merge corresponding local data and skip existing items. Export a backup first and confirm that the file source is trusted and compatible.\n\nReview important settings after the operation and restart the service when necessary."
    )
    "domain_rules" -> guide.copy(
        title = "Domain rules guide",
        warning = "This tool is intended only for filtering illegal, harassing, or malicious content. Do not use it to block lawful commercial advertising.",
        message = "Domain rules decide whether a domain is blocked, allowed, rewritten, or handled by a subscription. They directly affect whether websites and apps can connect. You can manage manual rules, allowlists, rewrite rules, subscriptions, and mirror templates.\n\nMore rules are not always better. Conflicting or overly broad entries can cause unintended blocking.\n\nAfter adding a rule, verify the target domain and check DNS logs to confirm which rule matched.",
        acknowledgement = "I have read and understood these terms and will use this tool only lawfully. I accept responsibility for improper use."
    )
    "data_cleanup" -> guide.copy(
        title = "Data cleanup",
        message = "Data cleanup can remove DNS cache, request logs, statistics, rule data, and other local content.\n\nThe impact differs by item. Some data cannot be recovered and historical statistics or troubleshooting clues may be permanently lost. Review each selection carefully and export important configuration first.\n\nResetting onboarding guides clears first-use explanations and agreement records but does not delete configuration, rules, cache, logs, or certificates. The app exits after the operation and will ask for the agreement again next time."
    )
    "service_display" -> guide.copy(
        title = "Service display",
        message = "Service display controls which protocols and providers appear in the home resolution-service list, keeping the status view focused.\n\nThese options only affect presentation. They do not enable, disable, or delete providers and do not change the DNS resolution strategy. Open Provider management or Resolution mode to change services that actually participate in queries.\n\nHidden items can be shown again at any time without losing their configuration."
    )
    "appearance" -> guide.copy(
        title = "Appearance settings",
        message = "Appearance settings manage the theme, accent color, home component transparency, home messages, notification text, custom background, and service animation.\n\nThese options mainly affect the interface and notifications, not DNS, rules, or network behavior. Custom backgrounds and visual effects may use additional resources on lower-end devices.\n\nIf readability decreases, open the relevant subpage and restore its default values."
    )
    "foreground_background" -> guide.copy(
        title = "Foreground and background behavior",
        message = "These settings control how DNSSR presents and maintains its operation after leaving the foreground, including persistent notifications, recent-task visibility, and related system interactions.\n\nSome options affect how the system manages background services. Hiding the interface does not mean that the service has stopped, especially on devices with aggressive battery policies.\n\nDecide whether you want to hide the app, reduce notifications, or keep DNS service stable. Test the result by locking the screen or switching apps."
    )
    "excluded_apps" -> guide.copy(
        title = "Excluded apps",
        message = "Excluded apps continue using the system DNS instead of DNSSR's DNS resolver.\n\nTheir domain requests usually do not match DNSSR block, allow, or rewrite rules, and their logs and statistics may be incomplete. This is useful for apps that are incompatible with the local VPN, a particular network, or a specific resolver.\n\nFiltering not working after adding an app is expected. Remove it from the list to restore DNSSR processing."
    )
    "blocked_apps" -> guide.copy(
        title = "Blocked apps",
        message = "Blocked apps cannot connect through the local VPN created by DNSSR. Use this to temporarily restrict apps that should not access the network.\n\nWhen enabled, network requests, background sync, notifications, and account verification for selected apps may fail. Remove an app from the list to restore normal forwarding."
    )
    "app_allowlist" -> guide.copy(
        title = "Per-app rules",
        message = "Per-app rules allow customizing network access and domain filtering for selected apps.\n\nSupports network-level domain allowlist isolation: restricted apps can only connect to IP addresses resolved from their allowed domains. Direct IPs, LAN probes, and unauthorized connections are blocked.\n\nAlso supports per-app DNS block/allow rules and the 'Block all outbound by default' wizard mode."
    )
    "http_inspection" -> guide.copy(
        title = "HTTPS traffic inspection",
        message = "DNS rules always apply during DNS resolution. HTTPS inspection can only be enabled after DNSSR's HTTPS inspection root certificate is installed and verified. It checks HTTP(S) requests only for explicitly selected apps that can be decrypted; other apps are forwarded directly by the Go tunnel. HTTPS domain and URL-path rules require decryption.\n\nCertificate pinning, custom validation, or incompatible connections are bypassed and forwarded directly. Install, remove, or reinstall the certificate carefully because some apps may otherwise lose connectivity.\n\nHTTP/3 is direct by default. When inspection fallback is enabled, UDP 443 is blocked for selected apps so compatible clients can fall back to TCP."
    )
    else -> guide
}

object SettingsGuides {
    const val HOME_LOG_LONG_PRESS_ID = "home_log_long_press"

    val PROVIDER_MANAGEMENT = SettingsGuide("provider_management", "服务商管理", "服务商决定谛听实际通过哪些上游 DNS 完成域名查询。你可以在这里添加、编辑、启用、停用或调整 DoH、DoT 等服务的顺序，并为不同服务填写地址与连接参数。\n\n启用多个可靠服务通常能提高可用性，但错误的地址、协议或证书配置可能导致解析失败。\n\n修改后建议回到首页观察服务状态，并通过查询测速确认当前网络下的连接效果。")
    val BOOTSTRAP = SettingsGuide("bootstrap", "Bootstrap 设置", "Bootstrap DNS 用于在连接加密 DNS 服务商之前，先解析该服务商自身的域名，从而避免解析过程形成循环依赖。你可以配置全局 Bootstrap 地址以及相关权重策略。\n\n若填写的服务器不可访问、响应过慢或返回错误结果，依赖域名连接的 DoH、DoT 服务可能无法正常工作。\n\n没有明确需求时建议保留可靠的默认配置，修改后应结合服务状态和实际解析结果进行确认。")
    val LATENCY_TEST = SettingsGuide("latency_test", "查询测速", "查询测速会使用你指定的测试域名，向选中的 DNS 服务商发起真实查询，并比较各服务商在当前网络环境中的解析耗时。\n\n测试结果会受到网络波动、缓存状态、目标域名和服务商负载影响，因此单次结果不代表长期表现。建议使用经常访问且稳定的域名，多执行几次后综合判断。\n\n测速只用于辅助选择服务商，不会自动替你修改当前启用状态或解析策略。")
    val CACHE = SettingsGuide("cache", "缓存设置", "DNS 缓存会保存近期的解析结果，在有效期内复用响应，从而减少重复网络请求并提升访问速度。你可以在这里调整缓存容量、有效期以及相关容错行为。\n\n更大的缓存或更长的保留时间能够提高命中率，但也可能让地址变更较慢生效；过于激进的清理则会增加查询次数和耗电。\n\n修改配置后已有缓存可能仍然存在，需要时可前往数据清理页面手动清除。")
    val RESOLUTION_MODE = SettingsGuide("resolution_mode", "解析模式", "解析模式决定一次 DNS 请求如何选择和调度已启用的服务商。\n\n单一服务仅查询一个服务商。智能选择会根据近期成功率和延迟优先选择服务，失败或超时时自动兜底。最快响应会同时查询所有选中服务，采用最先成功的结果。依次尝试会按设置顺序查询，前一个失败后切换下一个服务。\n\n智能选择、最快响应和依次尝试至少需要选择两个服务商；依次尝试可拖动调整查询顺序。修改模式不会删除服务商配置。")
    val LOG_MODE = SettingsGuide("log_mode", "日志模式", "日志模式决定谛听会记录哪些 DNS 请求以及保留多少排查信息。较完整的日志有助于确认请求来自哪个应用、命中了什么规则、由哪个服务商响应，但也会占用更多存储空间，并在本机留下更多访问记录。\n\n首页功能菜单中的“日志”卡片支持长按，可直接打开日志模式设置。\n\n若只关注运行状态，可以选择较精简的记录范围；需要定位规则或解析问题时再临时提高详细程度。\n\n日志只保存在设备本地，可随时通过数据清理页面删除。")
    val CONFIG_TRANSFER = SettingsGuide("config_transfer", "备份与迁移", "备份与迁移用于在设备之间流转谛听的自定义配置及自定义规则数据。\n\n导出前请留意文件中可能包含的服务地址或其他个人配置，并妥善保存。\n\n导入时系统会自动合并本机数据并跳过已存在的项目，因此建议先导出现有配置作为备份，并确认文件来源可信、版本兼容。\n\n操作完成后请检查关键设置，必要时重新启动服务使配置生效。")
    val DOMAIN_RULES = SettingsGuide(
        id = "domain_rules",
        title = "域名规则使用说明",
        warning = "本工具仅用于过滤非法骚扰，恶意代码等信息。请勿用于屏蔽合法商业广告。",
        message = "域名规则用于决定特定域名应被拦截、放行、重写，或交由订阅规则处理，会直接影响相关网站和应用能否正常联网。你可以管理手动规则、白名单、重写规则、订阅以及镜像模板。\n\n规则越多并不一定越好，冲突或范围过宽的条目可能造成误拦截。\n\n新增规则后建议立即验证目标域名，并通过 DNS 日志查看实际命中情况，以便快速发现优先级或格式问题。",
        acknowledgement = "我已阅知全部条款，承诺仅将本工具用于合法用途，违规使用责任自负。"
    )
    val DATA_CLEANUP = SettingsGuide("data_cleanup", "数据清理", "数据清理可以集中删除设备上的 DNS 缓存、请求日志、统计记录、规则数据或其他本地内容。\n\n不同清理项的影响范围并不相同，有些数据删除后无法恢复，也可能让历史统计和排查线索永久丢失。执行前请逐项核对选择内容，重要配置应先通过导出功能备份。\n\n重置新手引导会清除所有首次进入说明和首次使用协议记录，不会删除配置、规则、缓存、日志或证书。操作完成后应用将退出；下次打开时需要重新同意使用协议。")
    val SERVICE_DISPLAY = SettingsGuide("service_display", "服务显示", "服务显示用于控制首页解析服务列表中展示哪些协议和具体服务商，方便你隐藏暂时不关心的项目，让首页状态更加简洁。\n\n这里的选项只影响界面呈现，不会启用、停用、删除服务商，也不会改变 DNS 请求实际采用的解析策略。若要调整真正参与查询的服务，请前往服务商管理或解析模式页面。\n\n隐藏项目后仍可随时返回本页恢复显示，不会丢失原有配置。")
    val APPEARANCE = SettingsGuide("appearance", "外观设置", "外观设置集中管理应用的主题模式、主题颜色、首页组件透明度、首页语句、通知文字、自定义背景和服务灯光效果等显示选项。\n\n这里的调整主要影响界面与通知的呈现方式，不会改变 DNS 服务、规则或网络行为。部分自定义背景和视觉效果可能增加资源占用，在低性能设备上可适当减少效果。\n\n若修改后内容辨识度下降，可分别进入对应子页面恢复默认值。")
    val FOREGROUND_BACKGROUND = SettingsGuide("foreground_background", "前后台行为", "前后台行为决定谛听在应用离开前台后如何展示和维持运行，包括常驻通知、最近任务显示以及相关系统交互。\n\n部分选项可能影响系统对后台服务的管理方式，尤其在启用了严格节能策略的设备上，隐藏界面并不等于服务已经停止。\n\n调整前请确认自己希望的是隐藏应用、减少通知，还是保持解析服务稳定运行；修改后建议锁屏或切换应用测试实际效果。")
    val EXCLUDED_APPS = SettingsGuide("excluded_apps", "排除应用", "排除应用用于指定哪些应用不经过谛听的 DNS 解析，而是继续使用系统提供的 DNS。\n\n被排除后，该应用的域名请求通常不会命中谛听中配置的屏蔽、放行或重写规则，其日志和统计也可能不再完整显示。此功能适合处理与本地 VPN、特殊网络或特定解析方式不兼容的应用。\n\n添加后若发现过滤失效属于预期行为，移出排除列表即可恢复。")
    val BLOCKED_APPS = SettingsGuide("blocked_apps", "禁止联网应用", "禁止联网应用用于阻止选中的应用通过谛听所建立的本地 VPN 连接网络，适合临时限制不希望联网的应用。\n\n启用后，所选应用的网络请求、后台同步、消息通知和账号验证都可能失败；取消选择后即可恢复正常转发。")
    val APP_ALLOWLIST = SettingsGuide("app_allowlist", "应用独立规则", "应用独立规则可为选中的应用单独定制网络访问与域名过滤策略。\n\n支持配置网络层专属域名放行（白名单隔离）：应用只能连接其放行域名解析出的 IP，直连 IP、局域网探测及未授权连接均会被底层全流量隧道阻止。\n\n同时支持配置 DNS 专属屏蔽规则、专属白名单规则，以及“默认拦截全部外联”向导模式。")
    val HTTP_INSPECTION = SettingsGuide("http_inspection", "HTTPS 流量检查", "DNS 规则始终在 DNS 解析阶段生效。HTTPS 流量检查仅在已安装并验证谛听 HTTPS 检查根证书后才能启用；启用后，它只检查明确选择且可解密的应用 HTTP(S) 请求，其他应用会由 Go 隧道直接转发。HTTPS 域名和 URL 路径规则需要解密后才能匹配。\n\n证书固定、自定义校验或不兼容的连接无法解密时会作为 HTTPS 检查自动旁路直接转发。安装、卸载或重新安装证书均需谨慎操作，否则部分应用可能无法联网。\n\nHTTP/3 默认直连；启用尝试检查后会阻断所选应用的 UDP 443，以促使支持回退的客户端改用 TCP。")
}

@Composable
fun SettingsGuideHost(
    guide: SettingsGuide,
    content: @Composable () -> Unit
) {
    val context = LocalContext.current
    val displayGuide = if (androidx.compose.ui.platform.LocalConfiguration.current.locales[0].language == "en") {
        englishGuide(guide)
    } else {
        guide
    }
    var showGuide by remember(guide.id) {
        mutableStateOf(!AppSettings.isSettingsGuideAcknowledged(context, guide.id))
    }
    var acknowledged by remember(guide.id) { mutableStateOf(false) }

    content()

    if (showGuide) {
        BackHandler(enabled = true) {}
        AlertDialog(
            onDismissRequest = {},
            title = { Text(displayGuide.title) },
            text = {
                Column {
                    displayGuide.warning?.let { warning ->
                        Text(
                            text = warning,
                            color = MaterialTheme.colorScheme.error
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                    }
                    Text(displayGuide.message)
                    displayGuide.acknowledgement?.let { acknowledgement ->
                        Spacer(modifier = Modifier.height(16.dp))
                        Spacer(modifier = Modifier.height(8.dp))
                        SettingsCheckboxItem(
                            title = acknowledgement,
                            checked = acknowledged,
                            onCheckedChange = { acknowledged = it },
                            contentPadding = PaddingValues(vertical = 12.dp)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        AppSettings.acknowledgeSettingsGuide(context, guide.id)
                        showGuide = false
                    },
                    enabled = guide.acknowledgement == null || acknowledged
                ) {
                    Text(localizedText(if (guide.acknowledgement == null) "我知道了" else "确认并继续"))
                }
            }
        )
    }
}
