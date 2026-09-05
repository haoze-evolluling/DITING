package com.haoze.dnssr.ui.localization

/**
 * 网络诊断（当前网络信息、DNS 查询测速、Ping 测试、DNS 解析查询、路由追踪）本地化词条。
 */
internal fun translateNetworkToolsExact(text: String): String? = when (text) {
    "网络诊断" -> "Network diagnostics"
    "测速" -> "Speed test"
    "Ping 测试" -> "Ping test"
    "DNS 解析" -> "DNS lookup"
    "路由追踪" -> "Traceroute"
    "当前网络" -> "Current network"
    "网络类型" -> "Network type"
    "其他网络" -> "Other network"
    "蜂窝网络" -> "Cellular network"
    "以太网" -> "Ethernet"
    "未知网络" -> "Unknown network"
    "接口" -> "Interface"
    "网关" -> "Gateway"
    "IPv4 地址" -> "IPv4 address"
    "IPv6 地址" -> "IPv6 address"
    "DNS 服务器" -> "DNS servers"
    "未获取到当前网络信息" -> "Current network info unavailable"
    "Ping 目标" -> "Ping target"
    "输入 IP 或域名" -> "Enter an IP or domain"
    "Ping 次数" -> "Ping count"
    "开始 Ping" -> "Start ping"
    "Ping 中..." -> "Pinging..."
    "测试结果" -> "Test results"
    "目标地址" -> "Target address"
    "目标" -> "Destination"
    "查询域名" -> "Query domain"
    "输入要解析的域名" -> "Enter a domain to resolve"
    "记录类型" -> "Record type"
    "跟随系统" -> "Follow system"
    "自定义" -> "Custom"
    "自定义 DNS 服务器 IP" -> "Custom DNS server IP"
    "开始查询" -> "Start lookup"
    "查询中..." -> "Looking up..."
    "解析结果" -> "Lookup results"
    "解析 IP" -> "Resolved IPs"
    "耗时" -> "Elapsed"
    "响应状态" -> "Response status"
    "最大跳数" -> "Max hops"
    "开始追踪" -> "Start traceroute"
    "追踪中..." -> "Tracing..."
    "请输入 Ping 目标" -> "Enter a ping target"
    "请输入追踪目标" -> "Enter a traceroute target"
    "Ping 执行超时" -> "Ping timed out"
    "追踪执行超时" -> "Traceroute timed out"
    "无法解析目标地址" -> "Cannot resolve the target address"
    "未收到任何回复" -> "No replies received"
    "超时或无响应" -> "Timeout or no response"
    "目标不可达" -> "Destination unreachable"
    "请输入要解析的域名" -> "Enter a domain to resolve"
    "没有可用的 DNS 服务器" -> "No DNS server available"
    "查询失败" -> "Lookup failed"
    "自定义 DNS 服务器须为有效 IP 地址" -> "The custom DNS server must be a valid IP address"
    "无法获取当前网络的 DNS 服务器，可改用自定义服务器" -> "Cannot obtain the current network's DNS servers. Use a custom server instead."
    "该域名没有 A 记录" -> "No A records for this domain"
    "该域名没有 AAAA 记录" -> "No AAAA records for this domain"
    "系统 Ping 不可用，已用回退方式测量，无 TTL 信息且精度有限" -> "System ping unavailable; used a fallback measurement without TTL and with limited precision"
    "无法执行系统 Ping，无法进行路由追踪" -> "Cannot run the system ping; traceroute is unavailable"
    "系统 Ping 不支持 TTL 探测，无法进行路由追踪" -> "The system ping does not support TTL probing; traceroute is unavailable"
    "网络不可达，无法发送探测" -> "Network unreachable; probes could not be sent"
    "通过 ICMP 测量目标 IP 或域名的连通性，输出时延、丢包率与 TTL 等信息。" -> "Measures reachability of an IP or domain via ICMP and reports latency, packet loss, and TTL."
    "通过递增 TTL 逐跳探测到达目标的路径，展示每一跳路由地址与响应时延。" -> "Traces the path to the target hop by hop with increasing TTL, showing each router's address and response latency."
    "向指定 DNS 服务器查询域名的 A / AAAA 记录，展示解析 IP、TTL 与记录明细。" -> "Queries A / AAAA records from the chosen DNS server and shows resolved IPs, TTL, and record details."
    "结果只反映执行时刻的网络状态；部分目标会限制 ICMP 响应或 DNS 查询。" -> "Results reflect the network state at the time of execution; some targets limit ICMP or DNS responses."
    else -> null
}

internal fun translateNetworkToolsPattern(text: String): String? = when {
    text.startsWith("发送 ") && text.contains("丢包率 ") -> text
        .replace("发送 ", "Sent ")
        .replace(" · 接收 ", " · Received ")
        .replace(" · 丢包率 ", " · Loss ")
    text.startsWith("最小 ") -> text
        .replace("最小 ", "Min ")
        .replace("平均 ", "Avg ")
        .replace("最大 ", "Max ")
        .replace("抖动 ", "Jitter ")
    text.startsWith("耗时 ") -> text.replace("耗时 ", "Elapsed ")
    text.startsWith("解析到 ") -> text.replace("解析到 ", "Resolved to ")
    text.matches(Regex("\\d+ 次")) -> text.replace(" 次", " pings")
    text.matches(Regex("\\d+ 跳")) -> text.replace(" 跳", " hops")
    text.startsWith("到达目标，共 ") && text.endsWith(" 跳") -> text
        .replace("到达目标，共 ", "Destination reached in ")
        .replace(" 跳", " hops")
    text.startsWith("经 ") && text.endsWith(" 跳仍未到达目标") -> text
        .replace("经 ", "")
        .replace(" 跳仍未到达目标", " hops; destination not reached")
    text.startsWith("目标在第 ") && text.endsWith(" 跳不可达") -> text
        .replace("目标在第 ", "Destination unreachable at hop ")
        .replace(" 跳不可达", "")
    text.startsWith("该域名没有 ") && text.endsWith(" 记录") ->
        text.replace("该域名没有 ", "No ").replace(" 记录", " records for this domain")
    text.startsWith("记录明细（") && text.endsWith(" 条）") ->
        text.replace("记录明细（", "Record details (").replace(" 条）", ")")
    else -> null
}
