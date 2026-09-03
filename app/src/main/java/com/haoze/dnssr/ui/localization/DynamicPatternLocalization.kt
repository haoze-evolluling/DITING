package com.haoze.dnssr.ui.localization

/**
 * 跨模块通用动态模板替换与格式化处理。
 */
internal fun translateDynamicPattern(text: String): String? = when {
    text.contains(" 次；第 N+1 次开始升级") -> text.replace(" 次；第 N+1 次开始升级", " attempts; escalation starts at N+1")
    text.contains(" 秒；首次升级起固定计时") -> text.replace(" 秒；首次升级起固定计时", " seconds; timing starts at the first escalation")
    text.startsWith("已选 ") && text.endsWith(" 个应用，其余直接转发") -> text.replace("已选 ", "Inspecting ").replace(" 个应用，其余直接转发", " selected apps; others forwarded directly")
    text.startsWith("原始 TTL ") -> text
                .replace("原始 TTL ", "Original TTL ")
                .replace(" · 命中 ", " · Hits ")
                .replace(" 次 · ", " times · ")
    text.startsWith("最后命中 ") -> text.replace("最后命中 ", "Last hit ").replace("无", "none")
    text.contains(" · 平均胜出耗时 ") -> text.replace(" · 平均胜出耗时 ", " · Average winning latency ")
    text.startsWith("首选命中 ") -> text.replace("首选命中 ", "Primary wins ").replace(" · 平均首选耗时 ", " · Average primary latency ")
    text.startsWith("成功 ") && text.contains(" · 首选命中 ") -> text
                .replace("成功 ", "Success ")
                .replace(" · 首选命中 ", " · Primary wins ")
                .replace(" · 兜底 ", " · Fallback ")
                .replace(" 次", " times")
    text.contains(" · 样本 ") -> text
                .replace("成功 ", "Success ")
                .replace(" · 平均 ", " · Average ")
                .replace(" · 备用 ", " · Fallback ")
                .replace(" · 样本 ", " · Samples ")
                .replace(" 次", " times")
    text.contains(" 次 · ") -> text.replace(" 次 · ", " attempts · ")
    text.contains(" 次成功") -> text.replace(" 次成功", " successful")
    text.startsWith("全部失败（") -> text.replace("全部失败（", "All failed (").replace(" 次）", " attempts)")
    text.contains(" · ") && text.contains(" 后过期") -> text
                .replace(" 小时", " hours")
                .replace(" 分钟", " minutes")
                .replace(" 秒", " seconds")
                .replace(" 后过期", " until expiry")
    text.startsWith("感谢为谛听提出建议与帮助测试") -> "Thanks for suggestions and testing help for DNSSR"
    text.startsWith("已选 ") && text.contains(" 个：") -> text.replace("已选 ", "Selected ").replace(" 个：", ": ").replace(" 等", " etc.").replace("、", ", ")
    text.startsWith("仅记录拦截与错误 · ") -> text.replace("仅记录拦截与错误 · ", "Recording blocked and failed requests only · ")
    text.startsWith("平均胜出耗时 ") -> text.replace("平均胜出耗时 ", "Average winning latency ")
    text.contains(" · 占全部请求 ") -> text.replace(" · 占全部请求 ", " · Share of all requests ")
    text.startsWith("已选择 ") && text.endsWith(" 个服务") -> text.removePrefix("已选择 ").removeSuffix(" 个服务") + " services selected"
    text.endsWith(" 小时") && text.startsWith("每 ") -> "Every " + text.removePrefix("每 ").removeSuffix(" 小时") + " hours"
    text.startsWith("保留 ") && text.endsWith(" 天") -> text.removePrefix("保留 ").removeSuffix(" 天") + " days"
    text.contains(" 次 / ") && text.contains(" 秒 / 保持 ") -> text.replace(" 次 / ", " requests / ").replace(" 秒 / 保持 ", " seconds / hold ").replace(" 秒", " seconds")
    text.contains(" · ") && text.endsWith(" 后过期") -> text.replace(" 小时", " hours").replace(" 分钟", " minutes").replace(" 秒", " seconds").replace(" 后过期", " until expiration")
    text.endsWith(" 小时") -> text.removeSuffix(" 小时") + " hours"
    text.endsWith(" 分钟") -> text.removeSuffix(" 分钟") + " minutes"
    text.endsWith(" 秒") -> text.removeSuffix(" 秒") + " seconds"
    text.startsWith("收起") -> text.replace("收起", "Collapse ")
    text.startsWith("展开") -> text.replace("展开", "Expand ")
    text.startsWith("导入于 ") -> text.replace("导入于 ", "Imported on ")
    text.startsWith("导入失败：") -> {
                val inner = text.removePrefix("导入失败：")
                "Import failed: " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("当前：") -> text.replace("当前：", "Current: ")
    text.startsWith("已处理 ") -> text.replace("已处理 ", "Processed ")
    text.startsWith("成功 ") && text.contains(" · 平均 ") -> text.replace("成功 ", "Success ").replace(" · 平均 ", " · Average ").replace(" · 备用 ", " · Fallback ").replace(" 次", " times")
    text.startsWith(" · 冷却中") -> text.replace("冷却中", "cooldown")
    text.startsWith(" · 连续失败 ") -> text.replace(" · 连续失败 ", " · Consecutive failures ")
    text.startsWith("暂无样本") -> "No samples"
    text.startsWith("已选择 ") && text.contains(" 个应用，") -> text.replace("已选择 ", "").replace(" 个应用，", " apps, ").replace(" 个域名", " domains")
    text.startsWith("仅检查已选择的 ") -> text.replace("仅检查已选择的 ", "Inspecting only the selected ").replace(" 个应用；其他应用直接转发", " apps; other apps are forwarded directly")
    text.startsWith("请输入 1 到 ") && text.endsWith(" 之间的页码") -> text
                .replace("请输入 1 到 ", "Enter a page from ")
                .replace(" 之间的页码", "")
    text.startsWith("备 ") -> text.replace("备 ", "Backup ")
    text.startsWith("平均 ") && text.contains(" 次成功") -> text.replace("平均 ", "Average ").replace(" 次成功", " successful")
                .replace(" · 样本 ", " · Samples ")
    text.startsWith("全部失败（") -> text.replace("全部失败（", "All failed (").replace(" 次）", " attempts)")
    text.endsWith("\n暂无运行数据") -> text.removeSuffix("\n暂无运行数据") + "\nNo runtime data"
    text.startsWith("“已放行/已拦截”表示") -> "“Allowed/blocked” means DNSSR read the HTTP request authority and matched it against the current domain rules.\n\n“HTTPS inspection bypass” means HTTPS inspection forwarded the connection directly because of certificate pinning, mutual TLS, EV certificates, security-domain policies, or a handshake failure; the HTTP request inside was not read.\n\nRequest records store only the app, authority, protocol, result, matched rule, and time; paths, headers, and bodies are not stored."
    text.startsWith("SHA-256 指纹：") -> text.replace("SHA-256 指纹：", "SHA-256 fingerprint:")
    text.startsWith("当前用于解析 DNS：") -> text.replace("当前用于解析 DNS：", "Currently used for DNS: ")
    text.contains(" 解析地址") -> text.replace(" 解析地址", " resolution URL")
    text.contains(" 服务器地址") -> text.replace(" 服务器地址", " server address")
    text.contains(" 端口") -> text.replace(" 端口", " port")
    text.startsWith("应用设置 · ") -> text.replace("应用设置 · ", "App settings · ")
    text.startsWith("每 ") && text.endsWith(" 小时") -> text.removePrefix("每 ").removeSuffix(" 小时") + " hours"
    text.startsWith("已选择 ") && text.contains(" 个应用，") && text.endsWith(" 个域名") -> {
                text.removePrefix("已选择 ").replace(" 个应用，", " apps selected, ").removeSuffix(" 个域名") + " domains"
            }
    text.startsWith("连续失败 ") -> text.replace("连续失败 ", "Consecutive failures: ")
    text.startsWith("成功 ") && text.contains("%") -> text.replace("成功 ", "Success ").replace(" · 平均 ", " · Average ").replace(" · 备用 ", " · Fallback ").replace(" 次", " times")
    text.startsWith(" · 延迟 ") -> text.replace(" · 延迟 ", " · Latency ").replace(" ms", " ms")
    text.endsWith(" 已完成") -> text.removeSuffix(" 已完成") + " completed"
    text.endsWith(" 失败") -> text.removeSuffix(" 失败") + " failed"
    text.startsWith("服务开启时，所选应用的全部网络连接将被阻止") -> "When the service is enabled, all network connections from selected apps are blocked. Apps sharing the same UID are affected as well."
    text.startsWith("通过本机 VPN 按 UID 阻止") -> "Block all network connections from selected apps by UID through the local VPN. Apps sharing the same UID are affected as well."
    text.startsWith("关闭后名单会保留") -> "The list is retained when disabled, but traffic is not blocked and the Go tunnel is not enabled."
    text.startsWith("建议使用“标准”") -> "Balanced is recommended. The preset automatically configures maximum TTL, minimum TTL, and the fallback duration for failed resolution, so you do not need to enter seconds manually."
    text.startsWith("同一域名的所有记录类型合并计数") -> "Combine all record types for the same domain when counting requests."
    text.startsWith("请求次数需在 ") -> text.replace("请求次数需在 ", "Request count must be between ").replace("之间", ".")
    text.startsWith("统计窗口需在 ") -> text.replace("统计窗口需在 ", "The statistics window must be between ").replace(" 秒之间", " seconds.")
    text.startsWith("保持时长需在 ") -> text.replace("保持时长需在 ", "The hold duration must be between ").replace(" 秒之间", " seconds.")
    text.startsWith("桌面图标可能需要等待") -> "The launcher may need time to refresh the desktop icon. If it does not change immediately, return to the desktop and wait a moment."
    text.startsWith("两项内容均可留空") -> text.replace("两项内容均可留空；留空后", "Both fields may be left blank; when blank,").replace("首页不显示句子", "no home-screen status sentence is shown").replace("对应通知栏会使用默认状态文案", "the notification uses the default status text")
    text.startsWith("通知用于显示 DNS VPN") -> "Notifications show the running and stopped state of the DNS VPN. Denying this permission will not block core features, but you may not receive timely connection status updates."
    text.startsWith("谛听需要建立本地 VPN") -> "DNSSR needs a local VPN to process and filter DNS requests. This permission lets the app handle DNS traffic on the device; it does not send all network traffic to a remote VPN server."
    text.startsWith("已下载 ") -> text.replace("已下载 ", "Downloaded ")
    text.startsWith("交流群：") -> text.replace("交流群：", "Group: ").replace("（入群答案：", " (join answer: ").replace("）", ")")
    text.startsWith("整体表现") -> "Overall performance"
    text.startsWith("成功 ") && text.contains(" · 平均 ") && text.contains(" · 备用 ") -> text.replace("成功 ", "Success ").replace(" · 平均 ", " · Average ").replace(" · 备用 ", " · Fallback ").replace(" 次", " times")
    text.endsWith(" 次") -> text.removeSuffix(" 次") + " times"
    text.contains(" · 冷却中") -> text.replace(" · 冷却中", " · Cooling down").replace(" · 连续失败 ", " · Consecutive failures: ")
    text.startsWith(" · 延迟 ") -> text.replace(" · 延迟 ", " · Latency ")
    text.startsWith("感谢为谛听提出建议") -> "Thanks for suggestions and testing help"
    text.startsWith("感谢每一位为谛听提出建议") -> "Thanks to every co-builder who contributed suggestions and testing help. The list is sorted alphabetically by username, with Chinese names sorted by pinyin."
    text.startsWith("导入完成：新增 ") -> text.replace("导入完成：新增 ", "Import complete: added ").replace(" 项，跳过 ", ", skipped ").replace(" 项，失败 ", ", failed ").replace(" 项", " items")
    text.startsWith("导入汇总：新增 ") -> text.replace("导入汇总：新增 ", "Summary: added ").replace(" 项，跳过 ", ", skipped ").replace(" 项，失败 ", ", failed ").replace(" 项", " items")
    text.startsWith("【新增项目 (") -> text.replace("【新增项目 (", "[Added Items (").replace(")】", ")]")
    text.startsWith("【跳过项目 (") -> text.replace("【跳过项目 (", "[Skipped Items (").replace(")】", ")]")
    text.startsWith("【更新全局设置 (") -> text.replace("【更新全局设置 (", "[Updated Settings (").replace(")】", ")]")
    text.startsWith("单应用域名放行：") -> text.replace("单应用域名放行：", "Per-app domain allowlist: ")
    text.startsWith("应用白名单域名：") -> text.replace("应用白名单域名：", "App allowlist domain: ")
    text.startsWith("操作失败：") -> text.replace("操作失败：", "Operation failed: ").replace("未知错误", "Unknown error")
    text.startsWith("不支持旧版本配置文件") -> "Legacy configuration versions are not supported. Please re-export the latest configuration on the original device."
    text.startsWith("配置缺少 ") -> text.replace("配置缺少 ", "The configuration is missing ")
    text.startsWith("配置字段 ") && text.endsWith(" 格式错误") -> text.removeSuffix(" 格式错误").removePrefix("配置字段 ") + " has an invalid format"
    text.startsWith("备份缺少 ") -> text.replace("备份缺少 ", "The backup is missing ")
    text.startsWith("首次导入因应用意外终止而中断") -> "The initial import was interrupted because the app stopped unexpectedly. Residual rules were cleared; import again."
    text.startsWith("默认通过 Android VpnService") -> "By default, Android VpnService creates a local channel that handles only DNS. When HTTPS inspection or network blocking is enabled, the Go tunnel takes over TCP, UDP, DNS, and HTTP(S) traffic using the Go userspace network stack."
    text.contains(" 后过期") -> text.replace(" 后过期", " until expiry")
    text.startsWith("第 ") && text.contains(" 个") -> text.replace("第 ", "").replace(" 个", "").replace("，正在下载", ", downloading").let { "Item $it" }
    text.startsWith("正在准备") -> text.replace("正在准备", "Preparing").replace("，正在下载", ", downloading")
    text.endsWith("，正在下载") -> text.removeSuffix("，正在下载") + ", downloading"
    text.startsWith("重命名失败：") -> text.replace("重命名失败：", "Rename failed: ")
    text.startsWith("创建分组失败：") -> text.replace("创建分组失败：", "Failed to create group: ")
    text.startsWith("切换失败：") -> text.replace("切换失败：", "Switch failed: ")
    text.startsWith("操作失败：") -> text.replace("操作失败：", "Operation failed: ")
    text.endsWith(" 地址") -> text.removeSuffix(" 地址") + " address"
    text.startsWith("已保存模板（") -> text.replace("已保存模板（", "Saved templates (").replace("）", ")")
    text.endsWith(" 的更多操作") -> text.removeSuffix(" 的更多操作") + " more actions"
    text.startsWith("已处理 ") -> text.replace("已处理 ", "Processed ").replace("正在准备", "Preparing")
    text.startsWith("成功 ") && text.contains(" · 首选命中 ") -> text.replace("成功 ", "Success ").replace(" · 平均 ", " · Average ").replace(" · 首选命中 ", " · Primary wins ").replace(" · 兜底 ", " · Fallback ").replace(" 次", " times")
    text.startsWith("平均胜出耗时 ") -> text.replace("平均胜出耗时 ", "Average win latency ")
    text.startsWith("首选命中 ") -> text.replace("首选命中 ", "Primary wins ").replace(" · 平均首选耗时 ", " · Average primary latency ")
    text.contains(" | 拦截 ") -> text.replace(" | 拦截 ", " | Blocked ").replace(" 次 | ", " times | ")
    text.startsWith("已保存，") -> text.replace("已保存，DNS VPN 正在重连", "Saved; DNS VPN is reconnecting").replace("已保存，下次启动 DNS VPN 时生效", "Saved; it takes effect the next time DNS VPN starts")
    text.startsWith("原始 TTL ") -> text.replace("原始 TTL ", "Original TTL ").replace(" · 命中 ", " · Hits ").replace(" 次 · ", " times · ")
    text.startsWith("最后命中 ") -> text.replace("最后命中 ", "Last hit ").replace("无", "Never")
    text.startsWith("上次尝试于 ") -> text.replace("上次尝试于 ", "Last attempted at ")
    text.startsWith("感谢每一位支持谛听项目") -> "Thanks to everyone who supports Ting! Sponsors are listed from earliest to latest by default; use the button above to reverse the order. The order is unrelated to donation amount, and every contribution is equally appreciated."
    text.startsWith("应用启动时不自动检查") -> "Do not check automatically at startup; you can check manually at any time"
    text.startsWith("应用启动时自动检查") -> "Automatically check for new versions at startup"
    text.startsWith("已选择 ") && text.endsWith(" 个应用") -> "${text.removePrefix("已选择 ").removeSuffix(" 个应用")} apps selected"
    text.startsWith("尚未选择应用") -> "No apps selected; traffic will not be blocked when enabled"
    text.startsWith("当前筛选下") -> text.replace("当前筛选下", "No records for the current filter")
    text.startsWith("成功 ") -> text.replace("成功 ", "Success ")
                .replace(" · 平均 ", " · Average ")
                .replace(" · 备用 ", " · Fallback ")
                .replace(" · 兜底 ", " · Fallback ")
                .replace(" · 样本 ", " · Samples ")
    text.startsWith("安装 ") -> text.replace("安装 ", "Install ")
    text.startsWith("下载 ") -> text.replace("下载 ", "Download ")
    text.startsWith("全部 ") && text.endsWith(" 服务") -> text.removePrefix("全部 ").removeSuffix(" 服务") + " services"
    text.endsWith(" 服务") -> text.removeSuffix(" 服务") + " services"
    text.startsWith("删除 ") -> text.replace("删除 ", "Delete ")
    text.endsWith(" 个") -> text.removeSuffix(" 个")
    text.endsWith(" 条") -> text.removeSuffix(" 条")
    // 名单更新、配置导入日志与汇总
    text.startsWith("名单更新失败：") -> {
                val inner = text.removePrefix("名单更新失败：")
                "List update failed: " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("设置 ") -> {
                val inner = text.removePrefix("设置 ")
                "Set " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("更新 ") -> {
                val inner = text.removePrefix("更新 ")
                "Updated " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("汇总：新增 ") -> text.replace("汇总：新增 ", "Summary: added ").replace(" 项，跳过 ", ", skipped ").replace(" 项，失败 ", ", failed ").replace(" 项", " items")
    text.startsWith("包含 ") && text.endsWith(" 个订阅，请进入订阅管理执行规则更新。") -> text.replace("包含 ", "Includes ").replace(" 个订阅，请进入订阅管理执行规则更新。", " subscriptions; open subscription management to run rule updates.")
    // 配置导入明细：设置项开关与列表类日志
    text.startsWith("DNS 解析模式 -> ") -> {
                val inner = text.removePrefix("DNS 解析模式 -> ")
                "DNS resolution mode -> " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("Bootstrap IP 引导 -> ") -> {
                val inner = text.removePrefix("Bootstrap IP 引导 -> ")
                "Bootstrap IP bootstrap -> " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("禁止联网应用开关 -> ") -> {
                val inner = text.removePrefix("禁止联网应用开关 -> ")
                "Blocked apps switch -> " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("地址规则开关 -> ") -> {
                val inner = text.removePrefix("地址规则开关 -> ")
                "Address rules switch -> " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("加密 DNS 拦截开关 -> ") -> {
                val inner = text.removePrefix("加密 DNS 拦截开关 -> ")
                "Encrypted DNS blocking switch -> " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("拦截响应策略 -> ") -> text.replace("拦截响应策略 -> ", "Block response policy -> ")
    text.startsWith("镜像模板：") -> text.replace("镜像模板：", "Mirror template: ")
    text.startsWith("新增单应用域名放行：") -> text.replace("新增单应用域名放行：", "Added per-app allowlist: ")
    text.startsWith("新增应用白名单：") -> text.replace("新增应用白名单：", "Added app allowlist: ")
    text.startsWith("新增排除应用：") -> text.replace("新增排除应用：", "Added excluded app: ")
    text.startsWith("新增禁止联网应用：") -> text.replace("新增禁止联网应用：", "Added blocked app: ")
    text.startsWith("跳过单应用域名放行：") -> text.replace("跳过单应用域名放行：", "Skipped per-app allowlist: ").replace(" (已存在)", " (already exists)")
    text.startsWith("跳过应用白名单：") -> text.replace("跳过应用白名单：", "Skipped app allowlist: ").replace(" (已存在)", " (already exists)")
    text.startsWith("跳过排除应用：") -> text.replace("跳过排除应用：", "Skipped excluded app: ").replace(" (已存在)", " (already exists)")
    text.startsWith("跳过禁止联网应用：") -> text.replace("跳过禁止联网应用：", "Skipped blocked app: ").replace(" (已存在)", " (already exists)")
    text.startsWith("目标应用：") -> text.replace("目标应用：", "Target apps: ")
    text.startsWith("应用: ") -> text.replace("应用: ", "Apps: ")
    text.startsWith("开启后自动注入全阻断规则 (") && text.endsWith("，拦截该应用的所有常规网络请求，仅允许下方白名单中配置的域名通过。") -> {
                val pkg = text.removePrefix("开启后自动注入全阻断规则 (*\$app=").removeSuffix("，拦截该应用的所有常规网络请求，仅允许下方白名单中配置的域名通过。").removeSuffix(")")
                "When enabled, an all-block rule (*\$app=$pkg) is injected automatically, blocking all regular network requests from that app and allowing only the domains configured in the allowlist below."
            }
    // 仪表盘直连标签（"UDP直连 · pkg" 等组合）
    text.contains("直连") -> text.replace("直连", " Direct")
    else -> null
}
