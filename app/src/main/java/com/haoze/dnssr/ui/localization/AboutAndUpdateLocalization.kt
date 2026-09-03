package com.haoze.dnssr.ui.localization

import android.content.Context

/**
 * 关于软件、开源仓库、版本更新、免责协议、赞助与共建者名单本地化词条。
 */
internal fun translateAboutAndUpdateExact(text: String): String? = when (text) {
    "使用前说明" -> "Before you begin"
    "感谢每一位为谛听提出建议、帮助测试的共建者！名单按用户名称的字母顺序排列，中文名称按拼音排序。" -> "Thanks to every DNSSR co-builder who contributed suggestions and testing help. The list is sorted alphabetically by username, with Chinese names sorted by pinyin."
    "支付宝付款码" -> "Alipay payment QR code"
    "微信付款码" -> "WeChat payment QR code"
    "点一个 Star⭐" -> "Star the project ⭐"
    "提交 Issue" -> "Submit an issue"
    "提交 PR" -> "Submit a pull request"
    "分享给更多人" -> "Share it with others"
    "头像均已缓存，无需刷新" -> "All avatars are cached; no refresh needed"
    "刷新头像" -> "Refresh avatars"
    "当前按赞助时间由晚到早排列" -> "Currently sorted from newest to oldest sponsorship"
    "当前按赞助时间由早到晚排列" -> "Currently sorted from oldest to newest sponsorship"
    "当前按赞助时间由晚到早排列，点击切换为由早到晚" -> "Currently newest first; tap to switch to oldest first"
    "当前按赞助时间由早到晚排列，点击切换为由晚到早" -> "Currently oldest first; tap to switch to newest first"
    "暂时还没有赞助者，期待在这里写下你的名字。" -> "No sponsors yet. We look forward to seeing your name here."
    "创建不可更新的本地 DNS 过滤订阅" -> "Create a local DNS filtering subscription that cannot be updated"
    "创建不可更新的本地 hosts 覆写订阅" -> "Create a local hosts override subscription that cannot be updated"
    "创建不可更新的本地 HTTPS 过滤订阅" -> "Create a local HTTPS filtering subscription that cannot be updated"
    "本地订阅文件导入后无法更新，可在规则订阅中重命名、启用、禁用或删除。" -> "Imported local subscription files cannot be updated. Rename, enable, disable, or delete them under Rule subscriptions."
    "导入 DNS 过滤规则和白名单，创建不可更新的本地订阅" -> "Import DNS filtering and allow rules as a non-updatable local subscription."
    "导入 IP 地址映射规则，创建不可更新的本地覆写订阅" -> "Import IP address mappings as a non-updatable local rewrite subscription."
    "DNS 规则和 hosts 规则导入后均为不可更新的本地订阅；地址 JSON 备份会恢复为手动 URL 规则。" -> "DNS and hosts rules become non-updatable local subscriptions after import; address JSON restores manual URL rules."
    "未检测到 QQ，请搜索群号 1090225658 加入。" -> "QQ was not found. Search for group 1090225658 to join."
    "正在检查 GitHub Release" -> "Checking GitHub Releases"
    "检查 GitHub Release 中的最新版本" -> "Check GitHub Releases for the latest version"
    "更新规则" -> "Update rules"
    "订阅与更新" -> "Subscriptions and updates"
    "设置规则订阅的自动更新开关和频率" -> "Configure automatic update and frequency for rule subscriptions"
    "更新失败" -> "Update failed"
    "自定义更新时间" -> "Custom update interval"
    "本地订阅导入后无法更新。" -> "Local subscriptions cannot be updated after import."
    "仅会自动更新已开启的分组中的网络订阅。" -> "Only subscriptions in enabled groups are updated automatically."
    "自动更新设置" -> "Automatic update settings"
    "自动更新" -> "Automatic updates"
    "自动更新规则订阅" -> "Automatically update rule subscriptions"
    "在后台定期更新所有网络订阅，实际执行时间可能受系统调度影响" -> "Periodically update all network subscriptions in the background; actual execution may be affected by system scheduling"
    "自动更新时间" -> "Automatic update interval"
    "分组自动更新" -> "Group automatic updates"
    "输入 1 至 168 小时之间的更新时间" -> "Enter an update interval between 1 and 168 hours"
    "下载更新" -> "Download update"
    "最新版本未提供 Android APK" -> "The latest version does not provide an Android APK"
    "更新包下载地址无效" -> "The update package URL is invalid"
    "更新与支持" -> "Updates and support"
    "当前版本" -> "Current version"
    "检查更新" -> "Check for updates"
    "发现新版本" -> "New version available"
    "关闭启动时检查更新" -> "Disable update checks at startup"
    "应用启动时自动检查新版本" -> "Automatically check for new versions at startup"
    "加入 QQ 群" -> "Join QQ group"
    "共建者名单" -> "Co-builders"
    "暂时还没有共建者，期待在这里写下你的名字。" -> "There are no co-builders yet. We look forward to adding your name here."
    "不支持的配置文件版本" -> "The configuration file version is not supported"
    "不支持的 HTTPS 规则备份版本" -> "The HTTPS rule backup version is not supported"
    "谛听 / RESOLUTION UNDER YOUR CONTROL" -> "DNSSR / RESOLUTION UNDER YOUR CONTROL"
    "一位集美大学人工智能系大三学子" -> "A junior AI student at Jimei University"
    "开源项目仓库" -> "Open-source repository"
    "打开项目仓库" -> "Open project repository"
    "核心能力" -> "Core capabilities"
    "运行边界" -> "Operating boundaries"
    "可观测性" -> "Observability"
    "独立引导" -> "Independent bootstrap"
    "支持自定义服务、规则订阅的导入导出与自动更新。" -> "Supports importing, exporting, and automatically updating custom providers and rule subscriptions."
    "更新所有订阅" -> "Update all subscriptions"
    "本地文件订阅无法更新" -> "Local file subscriptions cannot be updated"
    "更新已取消，已保留原有规则" -> "Update canceled; existing rules were kept"
    "规则订阅自动更新" -> "Automatic rule subscription updates"
    "规则订阅自动更新失败" -> "Automatic rule subscription update failed"
    "规则订阅自动更新完成" -> "Automatic rule subscription update completed"
    "规则订阅已自动更新" -> "Rule subscriptions updated automatically"
    "正在自动更新规则订阅" -> "Automatically updating rule subscriptions"
    "正在重试自动更新规则订阅" -> "Retrying automatic rule subscription updates"
    "正在更新所有规则订阅..." -> "Updating all rule subscriptions..."
    "本次更新暂未提供详细说明。" -> "No detailed release notes are available for this update."
    "更新成功" -> "Update successful"
    "当前已是最新版本。" -> "You are already using the latest version."
    "检查更新失败。" -> "Update check failed."
    "更新包下载失败，请重试。" -> "Update package download failed. Try again."
    "无法开始下载更新。" -> "Unable to start the update download."
    "需要 Android 13 或更高版本" -> "Android 13 or later is required"
    "光影效果代码来源于开源项目:" -> "The light-effect code comes from the open-source project:"
    "修改后，已使用此模板的订阅不会被自动更新。" -> "Subscriptions already using this template will not be updated automatically after changes."
    "已更新镜像站模板" -> "Mirror template updated"
    "正在下载并更新规则..." -> "Downloading and updating rules..."
    "规则文件导入后为不可更新的本地订阅，系统将自动识别黑名单、白名单与覆写规则；地址 JSON 备份会恢复为手动 URL 规则。" -> "Rule files become non-updatable local subscriptions after import; blocklist, allowlist, and override rules are automatically classified. Address JSON restores manual URL rules."
    "请作者喝杯蜜雪 🧋" -> "Buy the author a drink 🧋"
    "如果这个项目帮助到了你，欢迎请作者喝杯蜜雪。" -> "If this project helped you, consider buying the author a drink."
    "付款时请备注您的网名或希望展示的名称，方便将您的名字加入赞助者名单。" -> "Please include your username or preferred display name with your payment so it can be added to the sponsor list."
    // 赞助与致谢
    "在 GitHub 查看 README 中的赞助方式" -> "See sponsorship methods in the GitHub README"
    "打开 GitHub README" -> "Open GitHub README"
    "感谢每一位支持谛听项目的朋友！名单默认按赞助时间由早到晚排列，可通过右上角按钮切换为由晚到早；与赞助金额无关，每一份支持都同样珍贵。" -> "Thanks to everyone who supports the DNSSR project! The list is ordered by sponsorship time (earliest first) by default; tap the button in the top-right corner to reverse it. Regardless of amount, every bit of support is equally precious."
    else -> null
}

internal fun translateAboutAndUpdatePattern(text: String): String? = when {
    text.startsWith("感谢您对谛听项目的赞助支持") -> "Thanks for supporting the DNSSR project"
    text.endsWith("的头像") -> text.removeSuffix("的头像") + "'s avatar"
    text.startsWith("已刷新 ") && text.contains(" 个头像") -> text.replace("已刷新 ", "Refreshed ").replace(" 个头像", " avatars")
    text.startsWith("记录全部请求 · 更新于 ") -> text.replace("记录全部请求 · 更新于 ", "Recording all requests · Updated on ")
    text.startsWith("发现 ") && text.contains(" 新版本，") -> text.replace(" 新版本，", " new version, ")
    text.startsWith("更新于 ") -> text.replace("更新于 ", "Updated on ")
    text.startsWith("更新失败（连续 ") -> text.replace("更新失败（连续 ", "Update failed (").replace(" 次）：", " consecutive failures): ")
    text.startsWith("准确率 ") -> text.replace("准确率 ", "Accuracy ").replace(" · 延迟 ", " · Latency ").replace(" · 样本 ", " · Samples ").replace(" · 更新 ", " · Updated ")
    text.startsWith("正在检查 GitHub Release") -> "Checking GitHub Release"
    text.startsWith("检查 GitHub Release 中") -> "Checking GitHub Release for the latest version"
    text.startsWith("当前版本 ") -> text.replace("当前版本 ", "Current version ")
    text.startsWith("检查更新失败：") -> {
                val inner = text.removePrefix("检查更新失败：")
                "Update check failed: " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("下载更新失败：") -> {
                val inner = text.removePrefix("下载更新失败：")
                "Update download failed: " + (LocalizationEngine.translateExact(inner) ?: inner)
            }
    text.startsWith("已刷新 ") -> text.replace("已刷新 ", "Refreshed ").replace(" 个头像", " avatars").replace("，", ", ").replace("仍未加载", "still not loaded")
    text.startsWith("更新因应用意外终止而中断") -> "The update was interrupted because the app stopped unexpectedly. Existing rules were kept; update again."
    text.startsWith("版本 ") -> text.replace("版本 ", "Version ")
    text.startsWith("成功 ") && text.contains("，失败 ") && text.contains("；更新 ") && !text.contains("，共导入 ") -> text.replace("成功 ", "Success ").replace(" 个，失败 ", ", failed ").replace(" 个；更新 ", "; updated ").replace(" 个，无需更新 ", ", unchanged ").replace(" 个", " items")
    text.startsWith("成功 ") && text.contains("，失败 ") && text.contains("，共导入 ") -> text.replace("成功 ", "Success ").replace(" 个，失败 ", ", failed ").replace(" 个；更新 ", "; updated ").replace(" 个，无需更新 ", ", unchanged ").replace(" 个，共导入 ", ", imported ").replace(" 条规则", " rules")
    text.contains("：黑名单 ") && text.contains("，白名单 ") && text.contains("，覆写 ") && text.contains("，重复 ") && text.contains("，无效/不支持 ") -> text
                .replace("导入成功：", "Import successful: ")
                .replace("更新成功：", "Update successful: ")
                .replace("订阅已保存：", "Subscription saved: ")
                .replace("导入完成：", "Import complete: ")
                .replace("：黑名单 ", ": blocklist ")
                .replace(" 条，白名单 ", " items, allowlist ")
                .replace(" 条，覆写 ", " items, overrides ")
                .replace(" 条，重复 ", " items, duplicates ")
                .replace(" 条，无效/不支持 ", " items, invalid/unsupported ")
                .replace(" 条", " items")
    text.startsWith("更新成功，共导入 ") -> text.replace("更新成功，共导入 ", "Update successful; imported ").replace(" 条规则", " rules")
    text.startsWith("检查完成：") -> text.removePrefix("检查完成：").replace("更新", "updated ").replace("个，已是最新", ", up to date ").replace("个，失败", ", failed ").replace("个，共导入", ", imported ").replace("条规则", " rules")
    text.startsWith("发现 ") && text.endsWith(" 新版本。") -> text.replace("发现 ", "New version available: ").replace(" 新版本。", ".")
    text.startsWith("光影效果代码来源于开源项目:\n") -> "The light-effect code comes from the open-source project:\n" + text.substringAfter(":\n")
    else -> null
}
