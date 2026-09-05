package com.haoze.dnssr.ui.localization

/**
 * DNS 解析模式、内置/自定义服务商、Bootstrap DNS、测速与服务商健康本地化词条。
 */
internal fun translateDnsResolutionExact(text: String): String? = when (text) {
    "清除智能选择的健康样本，让它重新按默认权重分配流量" -> "Clear smart-selection health samples and redistribute traffic using default weights"
    "清除 Bootstrap DNS 解析健康样本，重新按默认权重选择" -> "Clear Bootstrap DNS health samples and select using default weights again"
    "启用智能选择或最快响应并产生真实 DNS 查询后，这里会显示各策略的表现。" -> "Strategy performance appears here after smart selection or fastest response generates real DNS queries."
    "阿里云" -> "Alibaba Cloud"
    "腾讯云 DNSPod" -> "Tencent Cloud DNSPod"
    "仅影响阿里云和 DNSPod 的内置服务；四种解析模式中已选择的对应预设服务会同步切换协议。" -> "Only built-in Alibaba Cloud and DNSPod services are affected; the corresponding preset providers selected in all four resolution modes switch protocol together."
    "未选择服务商" -> "No provider selected"
    "Bootstrap 尝试" -> "Bootstrap attempts"
    "Bootstrap 成功率" -> "Bootstrap success rate"
    "当前不会保存 DNS 或 HTTPS 请求记录，缓存和解析服务仍正常运行。" -> "DNS and HTTPS request records are not currently saved; caching and resolution continue to work."
    "关闭竞速模式时，首页解析服务下拉框仅显示这里选中的服务。当前正在使用的服务会始终保留。" -> "When race mode is disabled, the home provider selector shows only the services selected here. The provider currently in use is always kept."
    "会向已选择的测速服务商查询这个域名，每个服务商连续测 3 次并按成功样本取平均值。" -> "The selected test providers query this domain three times each; the average is calculated from successful samples."
    "可选择 1 个或多个服务商；这里的选择只用于 DNS 查询测速，不影响竞速模式。" -> "Choose one or more providers. This selection is used only for DNS query tests and does not affect race mode."
    "测速结果按成功优先、平均耗时从低到高排序；结果只反映当前网络状态。" -> "Test results are sorted by success first and then by average latency; they reflect only the current network state."
    "编辑 DNS 服务商" -> "Edit DNS provider"
    "查看服务商的响应速度和成功情况" -> "View provider response speeds and success rates"
    "Bootstrap 解析" -> "Bootstrap resolution"
    "内置 DNS 服务商" -> "Built-in DNS providers"
    "权重按当前勾选的竞速服务商归一化为百分制，参与竞速的服务商合计为 100%。" -> "Weights are normalized to a 100-point scale using the currently selected race providers; participating providers total 100%."
    "权重数据" -> "Weight data"
    "自定义 DNS 服务商" -> "Custom DNS providers"
    "自定义 Bootstrap IP" -> "Custom Bootstrap IPs"
    "Bootstrap DNS 解析统计" -> "Bootstrap DNS resolution statistics"
    "产生真实 DNS 查询或 DNS 查询测速后，这里会显示 Bootstrap DNS 的成功率和权重。" -> "Bootstrap DNS success rates and weights appear here after real DNS queries or DNS speed tests are recorded."
    "Bootstrap DNS 使用排行" -> "Bootstrap DNS usage ranking"
    "Bootstrap 设置" -> "Bootstrap settings"
    "启用 Bootstrap IP" -> "Enable Bootstrap IP"
    "内置 Bootstrap IP" -> "Built-in Bootstrap IPs"
    "暂无自定义 Bootstrap IP。点击右上角“新增”添加。" -> "No custom Bootstrap IPs. Tap “Add” above to add one."
    "暂无 Bootstrap 数据" -> "No Bootstrap data"
    "恢复 DNS 默认权重" -> "Restore default DNS weights"
    "恢复 Bootstrap 权重" -> "Restore Bootstrap weights"
    "内置服务协议" -> "Built-in service protocol"
    "候选服务" -> "Candidate providers"
    "同时查询的服务" -> "Providers queried in parallel"
    "依次尝试的服务" -> "Providers tried in order"
    "查询顺序" -> "Query order"
    "提高优先级" -> "Move up"
    "降低优先级" -> "Move down"
    "选择一个 DNS 服务商进行查询" -> "Choose one DNS provider for queries"
    "根据近期成功率和延迟优先选择服务，失败或超时时自动兜底" -> "Prioritize providers by recent success rate and latency, with automatic fallback on failure or timeout"
    "同时查询所有选中服务，采用最先成功的结果" -> "Query all selected providers in parallel and use the first successful result"
    "选择一个服务进行查询。此选择与首页当前 DNS 服务商保持一致。" -> "Choose one provider for queries. This matches the current DNS provider on the home screen."
    "测速域名" -> "Test domain"
    "用于测速的域名" -> "Domain used for testing"
    "测速服务商" -> "Test providers"
    "测速中..." -> "Testing..."
    "服务商健康" -> "Provider health"
    "选择内置服务协议" -> "Choose built-in service protocol"
    "选择解析模式" -> "Choose resolution mode"
    "服务商管理" -> "Provider management"
    "查询测速" -> "Speed test"
    "解析模式" -> "Resolution mode"
    "删除 DNS 服务商" -> "Delete DNS provider"
    "服务商名称" -> "Provider name"
    "配置全局 Bootstrap DNS 与智慧权重" -> "Configure global Bootstrap DNS and smart weights"
    "选择单一服务、智能选择、最快响应或依次尝试策略" -> "Choose single-provider, smart selection, fastest response, or primary-backup mode"
    "新增 Bootstrap IP" -> "Add Bootstrap IP"
    "配置中包含无效的 DNS 服务商" -> "The configuration contains an invalid DNS provider"
    "配置中包含无效的 Bootstrap IP" -> "The configuration contains an invalid Bootstrap IP"
    "通过请求日志、竞速统计、服务商健康和 Bootstrap 数据追踪状态。" -> "Track status through request logs, race statistics, provider health, and Bootstrap data."
    "支持 Bootstrap IP，降低解析加密上游域名时对系统 DNS 的依赖。" -> "Supports Bootstrap IPs to reduce reliance on system DNS when resolving encrypted upstream domains."
    "解析服务" -> "Resolution provider"
    "解析服务（" -> "Resolution provider ("
    "选择解析服务" -> "Choose resolution provider"
    "解析服务选择框" -> "Resolution provider selector"
    "服务商胜出排行" -> "Provider win ranking"
    "智能选择首选" -> "Smart-selection primary wins"
    "暂无智能选择记录" -> "No smart-selection records"
    "智能选择产生查询后，会统计首选服务商的命中情况。" -> "Primary-provider wins are counted after smart selection generates queries."
    "单一服务" -> "Single provider"
    "智能选择" -> "Smart selection"
    "最快响应" -> "Fastest response"
    "依次尝试" -> "Primary and backup"
    "新增 DNS 服务商" -> "Add DNS provider"
    "添加自定义解析服务" -> "Add a custom DNS service"
    "设置 DoH 请求地址" -> "Set the DoH request URL"
    "设置自定义 Bootstrap IP 名称" -> "Set a custom Bootstrap IP name"
    "填写自定义 Bootstrap IP" -> "Enter a custom Bootstrap IP"
    "跟随上游 TTL" -> "Follow upstream TTL"
    "配置候选服务，按近期成功率和延迟优先选择" -> "Configure candidate providers and prioritize recent success rate and latency"
    "配置同时查询并采用最先成功结果的服务" -> "Configure providers queried in parallel and use the first success"
    "配置失败后依次尝试的服务顺序" -> "Configure the provider order used after failures"
    "清除竞速模式的健康样本" -> "Clear race-mode health samples"
    "清除 Bootstrap DNS 解析健康样本" -> "Clear Bootstrap DNS resolution health samples"
    "确定要删除所有 DNS、HTTP 请求日志、竞速统计和 Bootstrap DNS 解析统计吗？" -> "Delete all DNS and HTTP request logs, race statistics, and Bootstrap DNS resolution statistics?"
    "确定要清除所有服务商健康样本并恢复竞速模式默认权重吗？" -> "Clear all provider health samples and restore the default race-mode weights?"
    "确定要清除 Bootstrap DNS 解析健康样本并恢复默认权重吗？" -> "Clear Bootstrap DNS resolution health samples and restore the default weights?"
    "已恢复竞速模式默认权重" -> "Race-mode default weights restored"
    "已恢复 Bootstrap IP 默认权重" -> "Bootstrap IP default weights restored"
    "仅切换阿里云和 DNSPod 内置服务的 DNS、DoT 或 DoH 协议，并同步四种模式中的对应预设服务" -> "Only switches the DNS, DoT, or DoH protocol of the built-in Aliyun and DNSPod services, and syncs the matching preset services across the four modes"
    "已就绪" -> "Ready"
    "待配置" -> "Needs setup"
    "暂无此协议的服务商" -> "No providers for this protocol"
    else -> null
}

internal fun translateDnsResolutionPattern(text: String): String? = when {
    text.contains(" · 成功 ") -> text.replace(" · 成功 ", " · Success ")
                .replace(" · 平均 ", " · Average ")
                .replace(" · 备用 ", " · Fallback ")
                .replace(" · 权重 ", " · Weight ")
                .replace(" · 样本 ", " · Samples ")
    text.startsWith("暂无 ") && text.endsWith(" DNS 服务商。") -> text.replace("暂无 ", "No ").replace(" DNS 服务商。", " DNS providers.")
    text.startsWith("暂无 ") && text.contains(" 自定义服务商。") -> text.replace("暂无 ", "No custom ").replace(" 自定义服务商。点击右上角“新增”添加自己的 DNS 服务。", " providers. Tap “Add” above to add your own DNS service.")
    text.endsWith(" 个服务商") -> text.removeSuffix(" 个服务商") + " providers"
    text.startsWith("仅影响阿里云和 DNSPod") -> "Only built-in Alibaba Cloud and DNSPod services are affected; the corresponding preset providers selected in all four resolution modes will switch protocols together."
    text.startsWith("测速域名") -> "Test domain"
    text.startsWith("会向已选择的测速服务商") -> "The selected test providers query this domain three consecutive times each, and the average of successful samples is used."
    text.startsWith("可选择 1 个或多个服务商") -> "Select one or more providers. This selection is only used for DNS query latency tests and does not affect race mode."
    text.startsWith("测速结果按成功优先") -> "Results are sorted by success first and then by average latency; they only reflect the current network state."
    text.startsWith("已选择 ") && text.contains(" 个候选服务。") -> text.replace("已选择 ", "").replace(" 个候选服务。至少选择 2 个；系统会根据近期成功率和延迟优先选择，并在失败或超时时自动兜底。", " candidate providers selected. Select at least 2; providers are prioritized by recent success rate and latency, with automatic fallback on failure or timeout.")
    text.startsWith("已选择 ") && text.contains(" 个同时查询的服务。") -> text.replace("已选择 ", "").replace(" 个同时查询的服务。至少选择 2 个；查询会同时发送并采用最先成功的结果。", " providers selected for parallel queries. Select at least 2; queries are sent simultaneously and the first success is used.")
    text.startsWith("已选择 ") && text.contains(" 个依次尝试的服务。") -> text.replace("已选择 ", "").replace(" 个依次尝试的服务。至少需要 1 个主服务和 1 个备用服务；长按并拖动可调整查询顺序。", " providers selected for ordered fallback. Select at least one primary and one backup; long-press and drag to reorder.")
    text.startsWith("暂无 ") && text.endsWith(" DNS 服务商。") -> text.replace("暂无 ", "No ").replace(" DNS 服务商。", " DNS providers.")
    text.startsWith("权重按当前勾选") -> "Weights are normalized to percentages among selected race providers; participating providers total 100%."
    text.startsWith("权重 ") -> text.replace("权重 ", "Weight ")
    text.startsWith("确定删除“") -> text.replace("确定删除“", "Delete “").replace("”吗？删除后无法再作为解析服务使用。", "”? It can no longer be used for DNS resolution.")
    text.startsWith("暂无 ") && text.contains(" 自定义服务商。点击右上角") -> text.replace("暂无 ", "No custom ").replace(" 自定义服务商。点击右上角“新增”添加自己的 DNS 服务。", " providers. Tap Add above to add your own DNS service.")
    text.startsWith("已切换为") -> text.replace("已切换为", "Resolution mode changed to ")
                .replace("单一服务", "Single provider")
                .replace("智能选择", "Smart selection")
                .replace("最快响应", "Fastest response")
                .replace("依次尝试", "Primary and backup")
    text.startsWith("Resolution mode changed to ") -> text
                .replace("单一服务", "Single provider")
                .replace("智能选择", "Smart selection")
                .replace("最快响应", "Fastest response")
                .replace("依次尝试", "Primary and backup")
    text.startsWith("已连接 · ") -> text.replace("已连接 · ", "Connected · ")
                .replace(" 个服务商）", " providers)")
                .replace(" 个服务商", " providers")
                .replace("（", "(")
                .replace("单一服务", "Single provider")
                .replace("智能选择", "Smart selection")
                .replace("最快响应", "Fastest response")
                .replace("依次尝试", "Primary and backup")
                .replace("自定义", "Custom")
    text.startsWith("暂无自定义 Bootstrap IP") -> "No custom Bootstrap IPs. Tap Add above to create one."
    text.startsWith("产生真实 DNS 查询") -> "Bootstrap DNS success rates and weights appear here after real DNS queries or DNS latency tests."
    text.contains(" · 权重 ") -> text.replace("成功 ", "Success ").replace(" · 平均 ", " · Average ").replace(" · 权重 ", " · Weight ")
    text.startsWith("备份或恢复自定义服务") -> "Back up or restore custom providers and rule subscriptions"
    else -> null
}
