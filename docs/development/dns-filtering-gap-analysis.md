# DNS 过滤效果差距排查报告(谛听 vs AdGuard)

> 排查日期:2026-09-19 · 基线:`main` @ `5549546`(versionName 6.13)
>
> 背景:用户反馈在导入相同过滤规则的情况下,AdGuard 的过滤效果优于谛听,谛听仍会出现部分广告。本文记录排查过程、确认的根因(附代码证据)、已排除的疑点,以及分优先级的优化建议路线图,作为后续提升过滤效果的依据。**本文档只记录排查结果,不包含已实施的代码改动。**

## 目录

1. [过滤链路概览](#一过滤链路概览)
2. [根因分析](#二根因分析按影响排序)
3. [已核实与 AdGuard 语义一致、无需修改的点](#三已核实与-adguard-语义一致无需修改的点)
4. [优化建议路线图](#四优化建议路线图)
5. [验证方法](#五验证方法)
6. [附录](#六附录)

---

## 一、过滤链路概览

项目分两层:**Kotlin 壳**(VpnService 建立 TUN、规则下载/解析/存储/索引)+ **Go 数据面**(`tunnel/`,经 gomobile 编译为 AAR,内嵌 gVisor tun2socks 用户态 TCP/IP 栈)。DNS 过滤的判定链全部在 Go 侧执行(其中一步经 DomainChecker 回调落到 Kotlin 兜底)。

VPN 模式下的完整链路:

```
应用 DNS 查询 → 系统 DNS 指向 VPN 虚拟网卡(10.0.0.1 / fd00:abcd::1)
→ gVisor 栈终结 UDP/TCP 53 流量(engine_full_tunnel.go)
→ Engine.serveDNS(engine_standalone.go:28)按序判定:
   ① 应用白名单域(appAllowlistDomainAllowed)
   ② 本地资源域 local.pwhs.app 合成应答
   ③ DDR 抑制(_dns.resolver.arpa → NXDOMAIN)
   ④ 每应用防火墙(firewallChecker)
   ⑤ CNAME/IP 改写(rewriteTarget)
   ⑥ PolicyEngine 7 级规则评估(policy_snapshot.go:58)——订阅规则在评估内第 2/4/6 级完成,大列表走 DTRI mmap Trie(bloom 预筛)
   ⑦ Kotlin DomainChecker 回调兜底(dnsPolicy.evaluate;policyEngine 未激活或评估无结论时)
   ⑧ 全部放行 → 查 Go 内存 DNS 缓存 → 上游解析(DoH/DoT/DoQ/Plain)
→ 拦截:按 BlockResponseMode 合成 NXDOMAIN/0.0.0.0/REFUSED 等
→ 放行:上游应答原样写回客户端
```

> 注:serveDNS 内另有一段独立的 sec/ad bloom+trie 循环(`engine_standalone.go:184-220`),仅在 policyEngine 未激活/无规则时才会到达,且其加载入口 `SetTries`/`SetImportantTries` 当前无 Kotlin 调用方(tries 恒为空),实际不生效。

规则数据流:订阅下载(`SubscriptionDownloader.kt`)→ `AdGuardRuleParser.kt` 逐行分类(block/allow/rewrite)→ Room 存储 → 编译为 DTRI mmap 反转标签 Trie + JSON 快照 → `GoTunnelRuleManager.pushRuleSnapshot()` 推给 Go(`engine.applyRuleSnapshot`)。

---

## 二、根因分析(按影响排序)

### 2.1 【高·主因】CNAME 链不做二次过滤(CNAME Cloaking 未防护)

> **状态:已修复**(2026-09-19 实施,见 P0-A;新增 `tunnel/engine_response_chain.go` + 两处转发路径接入 + 7 个单测)。

**现象**:只对原始查询名(`Question[0].Name`)做规则匹配,上游应答中的 CNAME 链不做任何检查,原样透传给客户端。

**证据**:

- 查询名提取后,整条判定链只使用这一个域名(`engine_standalone.go:34-36`):

  ```go
  domain := strings.ToLower(r.Question[0].Name)
  domain = strings.TrimSuffix(domain, ".")
  ```

- 两处转发路径在应答写回前仅做"上游是否返回全 0.0.0.0"的 sinkhole 识别(仅用于日志归因),不做规则重匹配。

  `standaloneForward`(engine_standalone.go:370-384):

  ```go
  if isUpstreamBlockedMsg(&respMsg) {
      ... // 仅计数/日志
  } else {
      ...
      e.rememberResolvedIPs(r.Question[0].Name, &respMsg)
  }
  respMsg.Id = r.Id
  e.rememberAppAllowlistResponse(uid, &respMsg)
  _ = w.WriteMsg(&respMsg)   // ← 应答中的 CNAME 链未逐级检查
  ```

  `handleForward`(`engine_dns.go:302-333`,legacy 拦截路径)行为相同。
- 全库 `CNAME` 相关代码只有改写功能(`engine_standalone.go:422` 合成 CNAME、`$dnsrewrite=CNAME` 解析),没有链过滤。

**与 AdGuard 的差距**:AdGuard Home / AdGuard DNS 过滤引擎会对 DNS 应答中的每一级 CNAME 重新跑过滤规则(CNAME cloaking 防护,官方文档明确支持)。

**现实影响**:这是"同规则不同效果"的最大单一原因。现代广告/统计 SDK 大量使用 CNAME cloaking——第一方域名 CNAME 指向第三方追踪域,规则列表拦截的是追踪域本身;用户查询的第一方域名不在列表里,谛听放行整个应答,AdGuard 则在链上命中拦截。

### 2.2 【高】规则解析静默丢弃部分规则(同列表下实际生效规则更少)

解析器位于 `app/src/main/java/com/haoze/diting/vpn/AdGuardRuleParser.kt`,被丢弃的规则在导入统计里最多体现为 `unsupportedCount`(正则、`$dnstype` 等走该计数,与 invalid 合并展示为"无效/不支持");`badfilter`/web-only 的 `ignoredCount` 在流式导入路径(`CategorizedRuleStreamImporter`)不累计、完全不可见,用户无感知。逐条证据:

| 被丢弃的语法 | 行号 | 说明 |
|---|---|---|
| 正则规则 `/…/` | :327-329 | 已修复(2026-09-20, P1):支持完整正则与修饰符解析,走 specialRules 列表并按 7 级优先级匹配 |
| `$dnstype=` | :408-410 | 已修复(2026-09-20, P1):支持正向与取反(`~`),结合查询 Qtype 判定 |
| `$denyallow=` | :91-96 | 已修复(2026-09-20, P1):移出 web-only 表,解析排除域并在命中排除域时豁免拦截 |
| `$badfilter` | :397-400 | 已修复(2026-09-19, P0-B):两遍预扫描与归一化 key 对账剔除 |
| `\|x\|` 绝对锚点 | :417 | unsupported |
| `$client=` 等其它修饰符 | :408-410 | 丢弃(对 DNS 场景影响小,可接受) |

关键代码(`parseAdblockOrDomainLine`):

```kotlin
lower == "badfilter" -> {
    // $badfilter disables existing rules. In DNS filtering, ignore it to avoid blocking.
    return CategorizedLine(ignoredCount = 1)
}
isWebOnlyModifier(lower) -> {
    // Web/browser-specific modifiers cannot safely trigger whole-domain DNS blocking.
    return CategorizedLine(ignoredCount = 1)
}
...
else -> return CategorizedLine(unsupportedCount = 1)
```

影响评估:

- 正则 / `$dnstype` / `$denyallow` 被丢弃 → **直接少拦**(这些规则原本要拦的域名放行)。
- `$badfilter` 被忽略 → 语义漂移:列表作者用 badfilter 修正过宽规则,忽略后通常表现为**多拦**(易误伤),且与 AdGuard 行为不一致;随列表迭代漂移会累积。
- web-only 修饰符(`$script`、`$third-party` 等)丢弃是**有意设计**(防止把浏览器规则误放大成整域 DNS 拦截),与 AdGuard DNS 层行为大体一致,不算缺陷;但 `$denyallow` 混在其中属于误伤。

### 2.3 【中】HTTPS/SVCB(type 65)应答不检查

- 全量 grep `tunnel/*.go` 无任何 SVCB/HTTPS(type 65)专门处理。
- 被拦域名的 type 65 查询会因为域名命中而被拦(过滤与查询类型无关),这点没问题;但**放行域名的 HTTPS 记录原样透传**,SVCB/HTTPS 记录里 TargetName 指向被拦域时不拦。
- AdGuard Home 已实现 SVCB/HTTPS 记录的 TargetName 过滤。ECH/加密 SNI 普及后该缺口的影响会增大。

### 2.4 【中】正确性小问题

| 问题 | 位置 | 说明 |
|---|---|---|
| 规则快照更新不清 DNS 缓存 | `tunnel/engine_config.go:40` `ApplyRuleSnapshot` | 换规则后,已放行域名的旧解析在 TTL + stale 窗口内继续命中(`dns_cache.go` stale fallback);运行期各推送路径(单条规则同步/索引刷新/运行时配置刷新)均不清缓存。UI 有手动清理兜底,但"更新规则立即生效"不成立 |
| `ResponseNoData` 语义错误(仅 legacy 路径) | `tunnel/engine_dns.go:230-248` `handleBlockedDomain` | legacy 路径 NODATA 模式落入 default 分支,实际返回 0.0.0.0 而非空 NOERROR(`dns_packet.go` 的 `BuildBlockedResponse` 只合成 A/AAAA 0.0.0.0/::);VPN 主路径 `standaloneBlock` 已正确返回空 NOERROR(`engine_standalone.go:288-289`) |
| 动态 NXDOMAIN 限流未接入 legacy 拦截路径 | `dns_config.go:58-90` `dynamicBlocks.responseFor` | 已接入 `standaloneBlock`(`engine_standalone.go:282`,全隧道 VPN 与独立服务器共用);仅 legacy `Engine.Start` 路径的 `handleBlockedDomain` 未接入,当前主链路不经过 |
| `blockEncryptedDns` 是死标志 | `tunnel/engine.go:93` 只 Store 不 Load(`SetBlockEncryptedDns`,`engine_full_tunnel.go:287`) | 853 端口阻断实际与该 UI 开关无关(永远阻断);Private DNS strict 模式用户会 DNS 全断(可用性问题) |

### 2.5 【架构级】绕过路径(与 AdGuard 的差距边界)

这些是"DNS 过滤天然管不到"的场景,是否处理属于产品决策,列出来界定责任边界:

| 绕过路径 | 位置 | 现状 |
|---|---|---|
| 应用内置 DoH(443 端口硬编码 1.1.1.1/8.8.8.8 等) | `engine_full_tunnel.go:228-233` | 完全绕过 DNS 过滤;QUIC drop 仅对 HTTPS inspection 选中的应用生效,TCP 443 DoH 无拦截。DDR 抑制(`engine_standalone.go:110`)只能挡自动发现,挡不住硬编码 |
| `bypassLan` 默认排除私网段 | `DnsVpnTunnelManager.kt:309-356` | 应用向路由器/局域网 DNS(192.168/16、10/8、172.16/12)的查询不进 TUN、不过滤 |
| 被排除应用 | `DnsVpnTunnelManager.kt:193-200` | `addDisallowedApplication` 的应用 DNS 与流量完全不过滤(设计功能) |
| IPv6 探测失败 | `DnsVpnTunnelManager.kt:140-144` | VPN 不声明 IPv6,配合内置 DoH 可形成 v6 直连绕过(边缘) |

> 附注:若对比基准是开启了"HTTPS 过滤(MITM)"的 AdGuard for Android,则其部分优势来自 MITM 层(按 SNI/Host 二次过滤)。谛听已有 MITM 框架(`mitm_handler.go`),但仅对 inspection 选中的应用生效。

---

## 三、已核实与 AdGuard 语义一致、无需修改的点

以下疑点排查过并排除,避免后续重复排查:

- **大小写 / 结尾点归一化**:查询侧(`policy_snapshot.go:63`)与规则侧(Kotlin 解析时 IDN.toASCII + lowercase,`AdGuardRuleParser.kt:488-502`;Go 快照加载时 lowercase,`policy_engine.go:114-153`)均归一。
- **子域名匹配**:`||ads.example.com^` 能拦 `sub.ads.example.com`。Kotlin 侧 `DomainRuleMatcher.kt:14` 逐级后缀游走;Go 侧 `policy_matcher.go:73-120` 同构;订阅 DTRI mmap Trie(`policy_dtri_reader.go:237` `containsOrParentWithDisabled`,内嵌 bloom 预筛)按"祖先节点 terminal ⇒ 命中"实现。反向(规则是子域、查询是父域)不会误拦,符合 AdGuard 语义。
- **通配符**:`*`、`*.base`(含裸 base)两侧实现一致(Kotlin `AdGuardRuleParser.kt:21-62`,Go `policy_matcher.go:8-71`)。
- **7 级优先级**:每应用 `$important` → 全局 `$important` → 每应用 `@@` → 全局 `@@` → 每应用普通拦截 → 全局普通拦截 → 默认放行(`policy_snapshot.go:50-209`,Kotlin 镜像 `DomainPolicyEngine.kt:73-112`),与 AdGuard 的 `$important` > `@@` > 普通规则一致。
- **注释 / hosts / dnsmasq 解析**:空行、`!`、`#`、`[Adblock Plus 2.0]` 头、cosmetic 标记均正确忽略,不会误入黑名单;hosts sinkhole(0.0.0.0/127.0.0.1/::)归 block,非 sinkhole IP 归改写;`@@` 正确归白名单。
- **数据面 DNS 缓存不会绕过过滤**:缓存键 `域名:qtype:qclass`(`dns_cache.go:126-129`),查询点位于所有过滤步骤之后;被拦域名的合成应答从不进缓存(put 只发生在围绕 `resolver.Resolve` 的 singleFlight 内)。
- **TCP 53**:全隧道模式有 `handleDNSOverTCP`(`engine_full_tunnel.go:266-268`),与 UDP 同路径。仅 legacy `Engine.Start` 路径(非 VPN 模式,`dns_interceptor.go:134-168` 只认 UDP)有缺口,当前主链路不经过。
- **上游失败回退**:stale 缓存 → SERVFAIL,不存在"上游挂了就放行广告"的路径。
- **DDR 抑制**:`_dns.resolver.arpa` 返回 NXDOMAIN,已堵 DoH/DoQ 自动发现。
- **白名单短路语义**:命中 `@@` 返回 `"__ALLOW__"` 直接放行(短路后续 block 判定与 DomainChecker 兜底),`$important` 拦截仍可压过普通白名单,正确。

---

## 四、优化建议路线图

> 均为建议方案,本次排查未实施。P0 收益最大、边界清晰;P1 是解析完整性对齐;P2 是正确性/一致性小修;P3 是产品级决策项。

### P0-A:CNAME/SVCB 应答域二次过滤(Go 侧,建议优先)

> **状态:已实施**(2026-09-19)。helper 落地于 `tunnel/engine_response_chain.go`(`checkResponseChain`),除原方案的两处接入点外,同时覆盖了 `standaloneForward`/`handleForward` 的 stale 缓存回退路径与 `handleDNSQuery` 的缓存命中快速路径(规则更新后旧缓存应答也能被重新判定)。单测见 `tunnel/engine_response_chain_test.go`。

**方案**:

1. 新增 helper(建议放 `tunnel/engine_rules.go` 或新文件):

   ```go
   // checkResponseChain 对上游应答中的 CNAME 链与 SVCB/HTTPS TargetName 逐个重跑规则。
   func (e *Engine) checkResponseChain(msg *dns.Msg, appName string) (blocked bool, reason string)
   ```

   - 遍历 `msg.Answer`:收集 `*dns.CNAME` 的 `Target` 和 `*dns.SVCB` 的 `Target`(miekg/dns 中 HTTPS type 65 同为 `*dns.SVCB`,一并覆盖);
   - 每个目标 `strings.ToLower(strings.TrimSuffix(target, "."))` 后调 `e.policyEngine.evaluate(target, appName)`;
   - `blocked=true` → 返回 `"cname:"+reason`;`"__ALLOW__"` → 跳过该目标继续(白名单只豁免该域,黑名单命中拦整个应答,与 AdGuard Home 语义一致);
   - 仅当 `policyEngine` active 时启用;都未命中 → 放行。

2. 接入点(两处转发路径):
   - `standaloneForward`(`engine_standalone.go:370` 后、`w.WriteMsg` 前):blocked → `e.standaloneBlock(w, r, reason, appName, startTime); return`;
   - `handleForward`(`engine_dns.go:305-330`):blocked → 改走 `handleBlockedDomain` 拦截路径,不再 `BuildForwardedResponse`。

3. 日志:notifyLog 记录实际命中的链上域名,reason 带 `cname:`/`svcb:` 前缀,便于 UI 归因与统计。

**可行性已确认**:

- 缓存安全——过滤发生在 dnsCache 取回之后、写回客户端之前;原始上游应答照常缓存(put 只包 `resolver.Resolve`),无正确性问题。
- 性能——应答通常 1-5 条 RR,`evaluate` 是 map/trie 查询,开销可忽略。
- 覆盖两条转发路径(`standaloneForward`——全隧道 VPN 与独立服务器共用;`handleForward`——legacy 拦截路径)可共享同一 helper。

### P0-B:$badfilter 对账(Kotlin 侧)

> **状态:已修复**(2026-09-19 实施;`AdGuardRuleParser.kt` 规则对账剔除 + `CategorizedRuleStreamImporter.kt` 两遍流式导入与预扫描 + 单元测试覆盖)。

**方案**:

1. `AdGuardRuleParser.kt`:`badfilter` token 不再直接 ignored,产出归一化 badfilter 条目(维度:allow/block + pattern + important + appScope + appInverted);新增 `extractBadfilterKeys(text): Set<String>`(仅扫含 `$badfilter` 的行,开销小);`parseCategorized` 在分类后剔除 key 命中的 block/allow/rewrite 规则,计入新统计 `badfilteredCount`。key 复用现有去重 key 格式,`@@` 与黑名单分开键控(AdGuard 语义:badfilter 文本与目标规则文本一致才剔除)。
2. `CategorizedRuleStreamImporter.kt`:导入改两遍——下载内容已落盘 staging,先跑 `extractBadfilterKeys` 预扫描,再流式分类,命中 key 的行不写库。手动单条添加路径(`parseSingle`)不变。

### P1:解析完整性对齐(可独立分批)
 
> **状态:已全部实现并验证**(2026-09-20)。
> 
> - **$denyallow=**:移出 web-only 表,解析为排除列表;在 Kotlin/Go 两侧评估中,当查询域或其祖先域命中 denyallow 例外时予以豁免;快照 JSON 字段已打通。
> - **正则规则 /.../**:完整解析 `/.../` 正则表达式及修饰符(含编译校验);Kotlin 与 Go 均新增正则匹配引擎,自动绕过 DTRI trie 编译,走内存 specialRules 通道并严格接入 7 级优先级判定。
> - **$dnstype=**:完整支持正向与取反(`~`),Go 数据面根据当前查询的 `Question[0].Qtype` 精确匹配;`checkResponseChain` 与 `serveDNS` 均已透传 Qtype。
> - **单测覆盖**:Kotlin 新增 `SpecialRuleMatcherTest`、扩展 `AdGuardRuleParserTest`;Go 新增 `policy_special_rules_test.go`。
 
| 项 | 改动点 | 要点 | 状态 |
|---|---|---|---|
| `$denyallow=` | `AdGuardRuleParser.kt` 移出 web-only 表;`BlockRuleEntity`/`AllowRuleEntity` 加字段;`policy_snapshot.go` 支持排除域跳过;快照 JSON 打通 | AdGuard DNS 语义:denyallow 域做后缀匹配。对激进型列表(如 `\|\|*^$denyallow=…`)影响大 | 已实现 |
| 正则规则 `/…/` | 解析产出 RegexRule;两侧各加 regex 匹配器;走内存列表通道(绕过 DTRI)并按 7 级优先级匹配 | AdGuard 语义:正则匹配完整域名。Kotlin 侧编译失败计数 invalid,匹配不区分大小写 | 已实现 |
| `$dnstype=` | 解析保留正向与取反(`~`);Go 侧在 `serveDNS` 与 `checkResponseChain` 传递 `qtype` 匹配 | 典型用途 `$dnstype=AAAA` 禁 IPv6 解析,`$dnstype=~AAAA` 仅放行 IPv6 | 已实现 |

### P2:正确性/一致性小修

1. `ApplyRuleSnapshot`(`engine_config.go:40`)应用新快照后清空 dnsCache——规则变更立即生效。
2. legacy 路径 `handleBlockedDomain` 修复 `ResponseNoData` → 新增 `BuildNoDataResponse`(NOERROR 空应答);VPN 主路径 `standaloneBlock` 已正确,无需改动。
3. legacy 路径 `handleBlockedDomain` 接入 `dynamicBlocks.responseFor`(与 `standaloneBlock` 对齐;当前主链路不经过,低优先)。
4. `blockEncryptedDns` 开关接线(声明于 `engine.go:93`,`SetBlockEncryptedDns` 在 `engine_full_tunnel.go:287` Store;在 853 判断处 Load——`engine_full_tunnel.go:218/271` 与 `mitm_handler.go:62` 三处),或从 UI 移除该开关——二者选一,消除死标志。

### P3:产品级决策项(需单独评估)

1. **已知 DoH/DoQ 端点阻断**:内置主流 DoH 提供商(域名 + IP)清单,`filterDNS` 开启时可选阻断,缓解应用内置 DoH 绕过(对照:AdGuard 靠 HTTPS 过滤解决,谛听已有 MITM 框架但仅覆盖 inspection 应用)。
2. **导入统计 UI**:把 `unsupportedCount`/`ignoredCount` 按原因展示,让用户看到"同一列表谛听实际生效的规则为什么变少"。
3. **bypassLan 泄漏路径说明/开关文案**;Go 侧查询域 IDNA 归一(与规则侧一致,边缘情况)。

---

## 五、验证方法

**单元测试**(实施 P0 时补):

- Go(`tunnel` 包):CNAME 链命中 block trie / 链上域名命中 allowlist 仅豁免该域 / SVCB TargetName 命中 / policyEngine 未激活时跳过 / 无 CNAME 应答行为不变;`BuildNoDataResponse` 用例。
- Kotlin:`AdGuardRuleParser` 补 badfilter 用例——badfilter 剔除目标 block 规则、`@@` badfilter 剔除白名单、wildcard/rewrite 规则的 badfilter、流式导入两遍流程、非匹配 badfilter 不影响其它规则。

**手工验证**:

1. 导入 AdGuard DNS Filter,对比导入统计中 badfiltered / unsupported / ignored 计数,确认与 AdGuard 生效规则数对齐。
2. 选取已知使用 CNAME cloaking 的广告/统计域名(第一方域名 CNAME 指向列表中被拦域),验证查询日志出现 `cname:` 命中且客户端被拦。
3. 更新订阅后立即查询"之前放行、新规则拦截"的域名,验证缓存清理后规则即时生效(P2-1 实施后)。

---

## 六、附录

### 附录 A:关键文件清单

| 文件 | 职责 |
|---|---|
| `tunnel/engine_standalone.go` | `serveDNS:28` 判定主入口(VPN 与独立服务器共用)、`standaloneForward:308` 转发(主改动点) |
| `tunnel/engine_dns.go` | legacy VPN 路径 `handleForward:250`、拦截 `handleBlockedDomain:230`、`isUpstreamBlockedMsg:343` |
| `tunnel/engine_full_tunnel.go` | gVisor 流量分发:UDP/TCP 53 → serveDNS,853 阻断,443/80 MITM |
| `tunnel/policy_snapshot.go` | 7 级规则评估 `evaluate:58` |
| `tunnel/policy_matcher.go` | 后缀匹配 `matchDomainOrSuffix:73`、通配符 `wildcardMatcher` |
| `tunnel/policy_dtri_reader.go` | 订阅大列表 DTRI mmap Trie 读取器(bloom 预筛,经规则快照路径加载;`domain_trie.go`/`domain_bloom_filter.go`/`rule_compiler.go` 一族的 `SetTries` 加载机制当前无 Kotlin 调用方) |
| `tunnel/dns_cache.go` | 数据面缓存(键 `cacheKey:126`,singleFlight,stale 回退) |
| `tunnel/dns_packet.go` | 拦截应答合成 `BuildBlockedResponse:172` 等 |
| `tunnel/engine_config.go` | `ApplyRuleSnapshot:40`、`ClearDNSCache:22` |
| `app/.../vpn/AdGuardRuleParser.kt` | 规则逐行分类解析(主改动点) |
| `app/.../vpn/CategorizedRuleStreamImporter.kt` | 流式导入(1000 条/批) |
| `app/.../vpn/DomainPolicyEngine.kt` | Kotlin 侧判定 + Go 快照 JSON 构建(`buildRuleSnapshotJson:118`) |
| `app/.../vpn/GoTunnelRuleManager.kt` | 快照/改写/旁路规则推送 |
| `app/.../vpn/DnsVpnTunnelManager.kt` | TUN 构建、路由与 DNS 指向 |
| `app/.../vpn/MappedSubscriptionRuleIndex.kt` | DTRI mmap 索引编译(wildcard/appScoped/inverted 跳过,走内存兜底) |

### 附录 B:AdGuard DNS 规则语法支持对照表(排查时点)

| 语法 | AdGuard DNS 过滤 | 谛听 | 差距 |
|---|---|---|---|
| hosts / 纯域名 / dnsmasq | 支持 | 支持 | 无 |
| `||domain^`(含子域继承) | 支持 | 支持 | 无 |
| `@@` 例外 + `$important` 优先级 | 支持 | 支持 | 无 |
| 通配符 `*` / `*.base` | 支持 | 支持 | 无 |
| `$dnsrewrite=IP/CNAME/NXDOMAIN/…` | 支持 | 支持 | 无 |
| `$app=`(谛听扩展,对应 AdGuard 客户端维度) | — | 支持 | 无 |
| `$badfilter` | 支持(剔除目标规则) | 支持(已修复 P0-B) | 无 |
| `$denyallow=` | 支持 | 支持(已修复 P1) | 无 |
| 正则 `/…/` | 支持 | 支持(已修复 P1) | 无 |
| `$dnstype=` | 支持 | 支持(已修复 P1) | 无 |
| CNAME 链逐级过滤 | 支持(cloaking 防护) | 支持(已修复 P0-A) | 无 |
| SVCB/HTTPS(65) TargetName 过滤 | 支持 | 支持(已修复 P0-A) | 无 |
| `$client=`(按客户端 IP) | 支持 | 丢弃(可用 `$app=` 部分替代) | 可接受 |
| web-only 修饰符(`$script`/`$third-party` 等) | DNS 层不适用 | 有意丢弃(防误拦) | 设计一致 |
