package com.haoze.dnssr.ui.localization

/**
 * 应用白名单、禁止联网应用、排除应用、应用权限及应用列表排序过滤本地化词条。
 */
internal fun translateAppManagementExact(text: String): String? = when (text) {
    "隐藏系统应用" -> "Hide system apps"
    "需要应用列表访问权限才能选择应用。未授权不会影响其他功能。" -> "App-list access is required to choose apps. Denying it does not affect other features."
    "排除应用" -> "Excluded apps"
    "服务运行时禁止联网的应用包名" -> "Package names of apps blocked from networking while the service runs"
    "受限应用、独立域名放行规则与启用状态" -> "Restricted apps, standalone domain allowlists, and enabled state"
    "受限应用、独立域名白名单与启用状态" -> "Restricted apps, standalone domain allowlists, and enabled state"
    "单应用域名放行" -> "Per-app domain allowlist"
    "启用单应用域名放行" -> "Enable per-app domain allowlist"
    "应用白名单" -> "Per-app domain allowlist"
    "启用应用白名单" -> "Enable per-app domain allowlist"
    "应用白名单访问" -> "Per-app domain allowlist"
    "启用应用白名单访问" -> "Enable per-app domain allowlist"
    "白名单" -> "Whitelist"
    "全部应用" -> "All apps"
    "已配置放行" -> "Configured"
    "已配置白名单" -> "Configured"
    "按名称升序" -> "Name (A-Z)"
    "按名称降序" -> "Name (Z-A)"
    "按域名数量" -> "Domain count"
    "清空全部放行规则" -> "Clear all allowlist rules"
    "清空全部放行规则？" -> "Clear all allowlist rules?"
    "清空全部白名单规则" -> "Clear all allowlist rules"
    "清空全部白名单规则？" -> "Clear all allowlist rules?"
    "未配置任何单应用域名放行规则" -> "No per-app domain allowlist rules configured"
    "未配置任何应用白名单规则" -> "No per-app domain allowlist rules configured"
    "为应用单独配置允许访问的域名。受限应用只能连接其放行域名解析出的 IP，直连 IP、局域网探测和未授权连接会被阻止。未配置的应用不受限制正常放行。" -> "Configure allowed domains for specific apps. Restricted apps can only connect to IPs resolved from their allowed domains. Direct IPs, LAN probes, and unauthorized connections are blocked. Unconfigured apps are not restricted."
    "选择受限应用" -> "Select restricted apps"
    "禁止联网应用" -> "Blocked apps"
    "启用禁止联网" -> "Enable network blocking"
    "选择禁止联网应用" -> "Select blocked apps"
    "应用列表访问" -> "App list access"
    "为了让你选择需要排除或进行 HTTP(S) 检查的应用，谛听需要读取设备上的应用列表。不会读取应用数据，也不会上传应用列表。" -> "DNSSR needs access to the installed app list so you can choose apps to exclude or inspect for HTTP(S) traffic. It does not read app data or upload the app list."
    "应用列表菜单" -> "App list menu"
    "过滤应用" -> "Filter apps"
    "排序方式" -> "Sort order"
    "应用列表操作" -> "App list actions"
    "系统应用" -> "System apps"
    "用户应用" -> "User apps"
    "已勾选应用" -> "Selected apps"
    "应用名称 A-Z" -> "App name A-Z"
    "应用名称 Z-A" -> "App name Z-A"
    "包名 A-Z" -> "Package name A-Z"
    "包名 Z-A" -> "Package name Z-A"
    // 应用独立规则与全外联拦截
    "应用独立规则" -> "Per-app rules"
    "针对特定应用配置黑白名单过滤，或使用“默认全拦截”向导模式" -> "Configure block/allow filtering for specific apps, or use the 'Block all by default' wizard mode"
    "针对特定应用配置网络域名放行、专属黑白名单或默认全拦截模式" -> "Configure network allowlist domains, block/allow rules, or full block mode for specific apps"
    "应用独立过滤规则" -> "Per-app filter rules"
    "网络层域名放行（白名单隔离）" -> "Network domain allowlist (isolation)"
    "限制该应用仅允许连接指定放行域名解析出的 IP。直连 IP、局域网探测及其他域名将被底层全流量隧道阻止。未添加放行域名时不对该应用限制。" -> "Restrict this app to only connect to IPs resolved from allowlisted domains. Direct IPs, LAN probes, and other domains are blocked by the tunnel. Unconfigured apps are not restricted."
    "添加放行域名，如 example.com" -> "Add allowlist domain, e.g. example.com"
    "添加域名" -> "Add domain"
    "包含所有子域名" -> "Includes all subdomains"
    "清空放行域名" -> "Clear allowlist domains"
    "暂无专属放行域名，该应用处于正常放行状态。" -> "No allowlist domains configured; app is unrestricted."
    "暂未配置任何应用独立规则" -> "No per-app rules configured yet"
    "为指定应用深度定制网络与解析控制。支持网络层白名单隔离（仅放行指定域名）、DNS 专属黑白名单及“默认拦截全部外联”向导模式。" -> "Customize network access and DNS filtering for specific apps. Supports network-level domain allowlist isolation, DNS block/allow rules, and 'Block all outbound' wizard mode."
    "未配置" -> "Not configured"
    "应用独立规则与放行" -> "Per-app rules & allowlists"
    "单应用放行规则与域名白名单" -> "Per-app allowlist rules and domain whitelists"
    "已清空该应用放行域名" -> "Cleared allowlist domains for this app"
    "选择要独立配置过滤规则的应用。支持配置应用级黑名单、白名单域名，或开启“默认拦截全部外联，仅放行指定白名单”向导模式。" -> "Choose apps to configure standalone filter rules. Supports per-app blocklists, allowlist domains, or the 'Block all outbound by default, allow only the specified allowlist' wizard mode."
    "一键向导模板：默认拦截全部外联" -> "One-tap wizard template: block all outbound by default"
    "外联与隔离模式" -> "Outbound & isolation mode"
    "默认拦截全部外联" -> "Block all outbound by default"
    "开启后阻断该应用的所有网络连接，仅放行白名单" -> "Blocks all networking for this app, allowing only allowlisted domains"
    "开启全外联拦截？" -> "Enable full outbound blocking?"
    "开启后该应用的所有常规网络连接都将被阻断，仅白名单域名可通行。若未添加放行白名单，可能导致应用无法使用。" -> "All regular network connections for this app will be blocked, allowing only allowlisted domains. If no domains are allowlisted, the app may lose connectivity."
    "确定开启" -> "Enable"
    "已开启全阻断模式：请确保已添加必要的放行白名单，否则应用可能无法联网。" -> "Full block mode active: ensure necessary allowlists are configured to prevent connectivity issues."
    "专属放行域名（网络层）" -> "Network allowlist domains"
    "添加放行域名" -> "Add allowlist domain"
    "未配置网络放行域名" -> "No network allowlist domains configured"
    "包含子域名" -> "Includes subdomains"
    "DNS 专属白名单" -> "DNS allowlist"
    "添加 DNS 白名单" -> "Add DNS allow rule"
    "未配置 DNS 白名单" -> "No DNS allow rules configured"
    "DNS 专属拦截" -> "DNS blocklist"
    "添加 DNS 拦截" -> "Add DNS block rule"
    "未配置 DNS 拦截规则" -> "No DNS block rules configured"
    "添加应用专属白名单" -> "Add app DNS allow rule"
    "添加应用专属拦截规则" -> "Add app DNS block rule"
    "域名或通配符规则" -> "Domain or wildcard rule"
    "如 example.com 或 *-analytics.google.com" -> "e.g. example.com or *-analytics.google.com"
    "支持通配符模式（如 * 或 *-analytics.google.com）" -> "Supports wildcard patterns (e.g. * or *-analytics.google.com)"
    "高优先级 (\$important)" -> "High priority (\$important)"
    "例如 example.com，将自动放行该域名及其所有子域名" -> "e.g. example.com; all subdomains will be included automatically"
    "清空放行域名？" -> "Clear allowlist domains?"
    "此操作将移除该应用配置的所有网络层放行域名。" -> "This will remove all network allowlist domains configured for this app."
    "重要" -> "Important"
    "通配符" -> "Wildcard"
    "已保存规则" -> "Rules saved"
    "已清空白名单规则" -> "Allowlist rules cleared"
    "名单已更新，正在加载头像" -> "List updated; loading avatars"
    "清除 URL 屏蔽、放行和 CNAME 覆写规则" -> "Clear URL block, allow, and CNAME override rules"
    else -> null
}

internal fun translateAppManagementPattern(text: String): String? = when {
    text.startsWith("排除应用：") -> text.replace("排除应用：", "Excluded app: ")
    text.startsWith("禁止联网应用：") -> text.replace("禁止联网应用：", "Blocked app: ")
    text.startsWith("应用白名单：") -> text.replace("应用白名单：", "App allowlist: ")
    text.startsWith("应用白名单访问：") -> text.replace("应用白名单访问：", "App allowlist: ")
    text.startsWith("放行 ") && text.endsWith(" 域名") -> {
        val num = text.removePrefix("放行 ").removeSuffix(" 域名")
        "Allow $num domains"
    }
    text.startsWith("DNS ") && text.endsWith(" 条") -> {
        val num = text.removePrefix("DNS ").removeSuffix(" 条")
        "DNS $num rules"
    }
    text.startsWith("已配置 ") && text.contains(" 个应用 · 放行 ") -> {
        text.replace("已配置 ", "Configured ")
            .replace(" 个应用 · 放行 ", " apps · ")
            .replace(" 个域名 · DNS 规则 ", " allowlisted domains · ")
            .replace(" 条", " DNS rules")
    }
    text.startsWith("删除 ") -> text.replace("删除 ", "Delete ")
    else -> null
}
