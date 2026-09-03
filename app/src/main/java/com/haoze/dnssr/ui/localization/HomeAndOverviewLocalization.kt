package com.haoze.dnssr.ui.localization

/**
 * 首页主界面、古诗状态句、服务快捷磁贴、主服务运行状态及概览本地化词条。
 */
internal fun translateHomeAndOverviewExact(text: String): String? = when (text) {
    "今日请求" -> "Today's requests"
    "实时汇总" -> "Live summary"
    "今日拦截" -> "Today's blocked"
    "今日错误" -> "Today's errors"
    "今日旁路" -> "Today's bypassed"
    "解析运行状态" -> "Resolution runtime status"
    "日志记录已暂停" -> "Logging is paused"
    "已连接" -> "Connected"
    "谛听万象，明察清浊" -> "The readiness is all."
    "收耳静眠，归于无声" -> "The rest is silence."
    "连接失败" -> "Connection failed"
    "本地优先" -> "Local first"
    "谛听 本地解析控制台" -> "Ting local resolution console"
    "功能中心" -> "Feature center"
    "主页" -> "Home"
    "首页" -> "Home"
    "正在连接" -> "Connecting"
    "配置与规则库已更新" -> "Configuration and rule database updated"
    "为了提升性能与稳定性，新版本对底层规则引擎进行了精简重构。若发现自定义规则或订阅丢失，请前往「备份与迁移」或「规则」重新添加。" -> "To improve performance and stability, the underlying rule engine has been refactored. If you notice missing custom rules or subscriptions, please re-add them in 'Backup & Migration' or 'Rules'."
    else -> null
}

internal fun translateHomeAndOverviewPattern(text: String): String? = null
