# 谛听安卓端 · 网络管理方向开源借鉴调研

> 调研范围：`android/app`（Flutter/Riverpod）、`rust/`（Rust 内核）、`shared/`、`desktop/`。
> 基线：`docs/planning/01-现状与架构分析.md` 的「4.1 网络管理」能力矩阵——其中标注为 ✅ 的已有能力
> （DoH/DoT/DoQ/UDP/TCP、四策略调度、bootstrap、分片 LRU 缓存、DDR、伪应答纠正、应用分流/白名单/
> 禁止联网、HTTPS 检查、出站代理、按需启动、Ping/Traceroute/DNS 诊断、应用流量统计、悬浮窗）本文**不再重复推荐**。
> 本文只写一个文件，不改任何代码。

## 0. 方法与核实状态

- **已联网核实（HTTP 200）**：sing-box 官方文档（路由规则、DNS 规则动作、GeoIP、Wi-Fi State、端点/规则集目录）、
  NetGuard 官网、NextDNS 官网、Blokada 官网、TrackerControl 官网、AdGuard DNS 知识库、Cloudflare 1.1.1.1 文档、
  PCAPdroid 用户指南、Tailscale exit node 文档。对应 URL 见第二节表格与文末来源清单。
- **未能联网核实**：`github.com` / `raw.githubusercontent.com` / `rethinkdns.com` / `privacyguides.org` /
  `blokada.org/docs` 在本环境不可达（`fetch failed` 或 404）。因此 RethinkDNS、Clash Meta/FlClash、DNSCloak、
  personalDNSfilter 的**仓库级实现细节与许可证**主要基于既有知识，文中相应位置标注「未能联网核实」，
  落地前须以各仓库 `LICENSE` 与源码为准。
- 机制描述只讲「设计与交互范式」，代码落地一律回到谛听自己的 Rust 内核，不引入第二套 Dart/Kotlin 判定语义。

---

## 一、结论摘要

1. **网络管理性价比最高的三件事**：①按网络差异化 profile；②每应用/域名 → 上游的条件路由；③实时连接视图。
   三者都能复用现有 `policy-core / filter-core / resolver-core / connlog-core / sniffer-core / ipcache-core /
   telemetry-core`，真正新增的是「配置文档 + 决策输出 + UI」，而不是重写数据面。
2. **条件路由应做成 `policy-core` 的「第二输出」**：现有七级判定输出「允许/阻断」，扩展为同时输出
   `upstream_tag` / `outbound_tag` / `fallback_chain`。sing-box 的 route rule 字段集
   （`wifi_ssid`、`wifi_bssid`、`network_type`、`network_is_expensive`、`package_name`、`geosite`、`geoip`、
   `rule_set`、`dns_server_address`）是目前最完整的字段参照，可直接映射为谛听的规则模型。
3. **回退链 = `resolver-core` 的调度策略再加「链」与「健康门槛」**；Clash Meta/FlClash 的
   proxy-group（select / url-test / fallback / load-balance）提供了成熟的用户交互范式。
4. **实时连接视图的原料已经齐备**：`connlog-core`（去重）、`sniffer-core`（TLS SNI / HTTP Host）、
   `ipcache-core`（IP→域名）、`telemetry-core`（按 UID 计数）。缺的是一个 **flow 会话表内核** 与 Dart 页面；
   PCAPdroid 与 NetGuard 是最好的信息架构参照。
5. **网络状态必须来自 Kotlin `ConnectivityManager`**（transport / metered / roaming / validated / SSID / BSSID），
   Rust 只消费归一化后的 profile；sing-box 的 `network_type / network_is_expensive / network_is_constrained /
   wifi_ssid` 是标准字段命名，可避免自造词。
6. **DNS 泄漏检测与 Captive Portal 是「信任链」补全**：泄漏检测用「域名指纹探测 + 对照配置上游」；
   Captive Portal 用 RFC 8910 + `generate_204`，关键是**与拦截冲突时临时放行并提示登录**。
7. **DoH3/HTTP3 与 DoT/DoQ 连接复用**：已有 `quinn` 与 DoT idle pool，扩展面小，但需处理 H3 framing 与
   连接复用生命周期；**ECH 优先级最低**（rustls 的 ECH 支持仍受限、bootstrap 取 ECHConfig 复杂）。
8. **IPv6-only / DNS64 是「直接链接 `diting-dns64-core`」的低风险高确定性收益**，配合 CLAT 探测决定是否合成 AAAA。
9. **Kill switch 分两层**：系统级 always-on + block-without-VPN（跳系统设置引导）；应用级
   `setBlocking(true)` + `setUnderlyingNetworks(null)` + 看门狗退避重启。**防绕过**重点拦截 DoH canary /
   iCloud Private Relay / 明文 53 / 自定义 DoH——AdGuard DNS 的「block Firefox canary / block iCloud Private Relay」可直接借鉴。
10. **局域网客户端管理 = 服务器模式的 `ratelimit-core` + neighbor 解析 + 客户端表**（每客户端 profile / 限速 / 阻断）。
11. **许可证**：GPL-3.0 项目（NetGuard / AdGuard / TrackerControl / PCAPdroid / sing-box / Clash Meta）可借鉴代码
    思路且与谛听同协议；MPL-2.0（RethinkDNS）需**文件级隔离**；Apache-2.0 / MIT / BSD 单向兼容进 GPL-3.0；
    闭源/云服务（NextDNS 服务、DNSCloak、Blokada 云）**只借鉴设计，不复制实现**。
12. **优先级建议**：P0 五项（网络 Profile、条件路由+回退链、Flow 视图、Kill switch/重连、DNS 泄漏检测+Captive Portal）；
    P1 四项（DoH3、连接复用、DNS64、LAN 客户端管理）；P2 四项（ECH、PCAP 导出、geoip/geosite 规则集、每应用限速）。
    （逐条见第三节。）

---

## 二、借鉴表

> 列说明：**难度** = Flutter 侧 / Rust 侧；**优先级** P0=核心补齐、P1=重要增强、P2=锦上添花。
> 许可证列若标「未核实」表示本轮无法读取仓库 LICENSE，落地前须复核。

### 2.1 防火墙 / 分流 / 路由类

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| RethinkDNS（celzero/rethink-app） | MPL-2.0（未能联网核实） | 应用防火墙 + DNS 双栏；blocklists 分组；每应用自定义规则；网络监视（DNS/连接）视图 | 在「应用分流」页增加「网络策略」二级：允许 / 阻断 / 仅 DNS 三态；规则可引用 blocklist 组；数据落 `policy-core` 快照 | 中 / 中 | P0 | https://github.com/celzero/rethink-app |
| NetGuard（M66B/NetGuard） | GPL-3.0（未能联网核实） | 每应用 Wi-Fi / 移动网络分别开关；「仅屏幕开启时允许」；「漫游时阻断」；按地址过滤；流量日志 + PCAP 导出；速度通知 | 每应用规则升级为「网络类型 × 计费/漫游」矩阵；连接日志支持 PCAP 导出；速度曲线复用 `telemetry-core` | 中 / 中 | P0 / P1 | https://netguard.me/ |
| AdGuard for Android | GPL-3.0（未能联网核实） | 「应用管理」三态（走代理 / 阻断 / 绕过）；过滤日志逐请求显示应用；DNS 保护；预过滤（prefiltering） | 应用分流三态 + 「过滤日志按应用/域名分组」；复用 `outbound-proxy-core` 与 `mitm-core` | 中 / 中 | P0 | https://adguard.com/en/adguard-android/overview.html |
| TrackerControl | GPL-3.0（未能联网核实） | 按应用追踪器视图 + 目的地国家地图；三档阻断模式（minimal / comprehensive / …）；代码证据 + 网络证据双栏 | Flow 视图增加「目的地国家 / 公司」聚合；阻断模式映射到 `policy-core` 优先级档 | 低 / 低 | P1 | https://trackercontrol.org/ |
| sing-box（SagerNet） | GPL-3.0（以其 LICENSE 为准） | route rule 字段全集（`wifi_ssid`/`network_type`/`package_name`/`geosite`/`geoip`/`rule_set`）；DNS rule action（route/evaluate/respond/reject、`race`、`rewrite_ttl`、`speculative`）；rule-set 支持 AdGuard 语法 | 条件路由内核字段直接参照；DNS 侧 action 模型映射到 `dns-core` 决策；rule-set 加载参照其 source-format | 高 / 高 | P0 | https://sing-box.sagernet.org/configuration/route/rule/ · https://sing-box.sagernet.org/configuration/dns/rule_action/ |
| Clash Meta / mihomo、FlClash | GPL-3.0（未能联网核实） | proxy-group（select / url-test / fallback / load-balance）；rule-provider；fake-ip；sniffer；TUN 模式 | 「策略组 / 回退链」抽象与 UI；复用并扩展 `resolver-core` 的调度与健康统计 | 中 / 中 | P1 | https://github.com/MetaCubeX/mihomo |
| Tailscale exit node | BSD-3-Clause（客户端）（未能联网核实） | 出口节点选择器；「允许 LAN 访问」；子网路由；MagicDNS | 「出口 / 上游切换器」概念；LAN 直连例外清单（本地网段直连不走上游） | 中 / 中 | P2 | https://tailscale.com/docs/features/exit-nodes |

### 2.2 DNS / 监控 / 网络感知 / 防绕过类

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| AdGuard DNS（知识库） | 服务闭源；客户端 GPL-3.0 | 查询日志与统计；DoH 带认证；阻断响应模式（零 IP / NXDOMAIN / REFUSED / 自定义 IP）；TTL 设置；允许/拒绝客户端；**block iCloud Private Relay / block Firefox canary** | 阻断响应模式谛听已有，补「防 DoH 绕过」开关；客户端 ACL 复用 `ratelimit-core` 的 CIDR 豁免模型 | 低 / 低 | P0 | https://adguard-dns.io/kb/private-dns/overview/ |
| NextDNS | 服务闭源（CLI 开源 MIT，未核实） | 多配置档案（profiles）；查询分析；Native Tracking Protection；rewrites；DNSSEC；block page；日志留存档位（1h–2y / 不留） | 「网络 profile / 配置档案」交互；日志留存档位；改写复用 `rewrite-core` | 低 / 低 | P1 | https://nextdns.io/ |
| Blokada（v5 客户端 / 云） | 客户端 GPL-3.0（未核实）；云闭源 | 云 DNS + WireGuard；blocklists；Family 家长控制；多设备；按应用选择 | 家庭分组 + 家长控制分层；**不建议**引入云依赖，只借鉴分组与家长档位 | 低 / 低 | P2 | https://blokada.org/ |
| personalDNSfilter（Zenz） | GPL（具体版本需核实） | 极轻量；网络切换自动重载；按网络选 DNS；过滤列表 + 自定义 DNS | 「网络切换热重载上游」的轻量范式；Java 实现仅作交互参考 | 低 / 低 | P2 | https://www.zenz-solutions.de/ |
| PCAPdroid | GPL-3.0（未能联网核实） | 每连接（应用 / 主机 / SNI）flow 列表；过滤器；多种导出（PCAP / pcapng / UDP / TCP）；TLS 解密经 mitmproxy；扩展 / HTTP API；防火墙 | Flow 视图信息架构与 PCAP 导出标准；「扩展 API」启发本地 HTTP API（P2） | 中 / 中 | P1 | https://emanuele-f.github.io/PCAPdroid/ |
| Intra / 1.1.1.1 | Intra 为 Apache-2.0（未核实）；1.1.1.1 服务专有 | DoH 服务器选择；按应用绕过；查询统计；DoH/DoT；Oblivious DoH；IPv6-only 支持 | DoH 服务器选择器 + 绕过清单；Oblivious DoH 作为 P2 隐私选项 | 低 / 低 | P2 | https://developers.cloudflare.com/1.1.1.1/ |

> 补充证据：sing-box 的 Wi-Fi State 文档明确了 `wifi_ssid` / `wifi_bssid` / `network_is_expensive` /
> `network_is_constrained` 的语义（https://sing-box.sagernet.org/configuration/shared/wifi-state/），
> 这是「网络感知」字段命名与判定的最佳参照；其 DNS 服务器类型含 `http3`、`quic`、`fakeip`、`tailscale` 等
> （https://sing-box.sagernet.org/），端点含 WireGuard / Tailscale / MASQUE，可作为上游与出口能力的路线图参考。

### 2.3 待挖掘机制覆盖矩阵

> 对照任务「需要挖掘的机制」清单逐项落点，确保无遗漏。

| 待挖掘机制 | 代表开源实例 | 谛听落点（现有 / 新 crate） | 覆盖状态 |
|---|---|---|---|
| 每应用分流/路由粒度与交互 | RethinkDNS、AdGuard、NetGuard | `policy-core` + `route-core`（新）+ 应用分流页三态 | 待建 |
| 按网络（SSID/蜂窝/漫游）差异化与网络感知 | NetGuard、sing-box、personalDNSfilter | `netprofile-core`（新）+ Kotlin ConnectivityManager | 待建 |
| 实时连接/流量监控与可视化 | PCAPdroid、NetGuard、TrackerControl | `flow-core`（新）+ `pages/network/flow` | 待建 |
| 每应用指定上游/策略 | AdGuard for Android、sing-box | `route-core`（新）扩展 `policy-core` 决策输出 | 待建 |
| 域名→上游分流（geosite/geoip/条件路由） | sing-box、Clash Meta | `ruleset-core`（新）+ `route-core` | 待建 |
| 回退链与故障切换 | Clash proxy-group、sing-box | `chaingroup-core`（新）/ 扩 `resolver-core` | 待建 |
| DNS 泄漏检测 | NextDNS test、1.1.1.1 | `leak-core`（新）+ `probe-core` | 待建 |
| Captive Portal 处理 | 系统 CaptivePortal、各 VPN | `captive-core`（新）+ NetworkCapabilities | 待建 |
| DoH3 / HTTP3 | sing-box `http3` DNS server | 扩 `upstream-core` + `quinn` | 待建 |
| ECH | sing-box TLS / rustls | `rustls` ECH + `bootstrap-core` | P2 实验 |
| IPv6-only / DNS64 | `diting-dns64-core`（桌面已有） | 链接进 `libditing_engine.so` | 待链接 |
| DoT / DoQ 连接复用 | sing-box `multiplex` | 扩 `upstream-core` 连接池 | 待建 |
| kill switch / 始终开启 / 防绕过 | NetGuard、AdGuard、AdGuard DNS canary | `vpn-config-core` + 内置阻断组 | 待建 |
| 带宽/限速/QoS | `diting-ratelimit-core`（桌面已有） | `ratelimit-core` + `lanclient-core`（新） | 待链接 |
| 流量统计口径 | NetGuard、PCAPdroid | `telemetry-core` / `connlog-core` / `log-core` | 部分已有 |
| 局域网客户端管理 | AdGuard Home 思路、sing-box `neighbor` | `lanclient-core`（新） | 待建 |
| 与 Rust 内核结合可行实现点 | — | 见第四节映射表 | 已梳理 |

---

## 三、建议引入的新功能 / 增强（归属「网络管理」）

> 每条含：用户价值 / 技术方案（明确现有 crate 与建议新增 crate）/ 风险。

### A. 网络感知与按网络差异化策略

#### A1. 网络 Profile（Wi-Fi / 蜂窝 / 漫游 / 计费 / 受限）与差异化策略 — P0
- **用户价值**：地铁/漫游时自动切到更省流、更低延迟的上游或更严拦截；家庭 Wi-Fi 与公司 Wi-Fi 用不同规则集。
- **技术方案**：
  - Kotlin `ConnectivityManager` + `NetworkCallback` 采集 `transportType`、`isMetered`、`isRoaming`、
    `NetworkCapabilities.NET_CAPABILITY_VALIDATED`、`NOT_METERED`、SSID/BSSID（需定位权限）。
  - 归一化进新 crate **`diting-netprofile-core`**（建议）：定义 `NetworkProfile { kind, metered, roaming,
    constrained, ssid, bssid }` 与「匹配 → 差异化设置」映射，产出可校验的配置文档；与
    `diting-vpn-config-core` / `diting-config-core` 同构。
  - 字段命名对齐 sing-box：`network_type`、`network_is_expensive`、`network_is_constrained`、`wifi_ssid`。
  - 差异化项：上游集合、拦截档位、是否启用 MITM、缓存 TTL 档、是否启用 DoH3。
- **风险**：SSID 读取需定位权限且 Android 10+ 有额外限制；profile 过多会让 UI/排查复杂，需「默认 + 显式覆盖」两级。

#### A2. 网络切换热重载（不重启隧道换上游/规则）— P0
- **用户价值**：切 Wi-Fi/蜂窝时不掉线、不闪断，静默切换到该网络对应的上游与规则。
- **技术方案**：`NetworkCallback` 触发 → `diting-netprofile-core` 计算新配置 → 通过 `diting-config-core`
  生成引擎配置文档 → 引擎侧「软应用」（复用 `diting-resolver-core` 上游切换 + `policy-core` 快照热替换），
  尽量不重建 TUN。参考 personalDNSfilter 的网络切换自动重载思路。
- **风险**：DNS 缓存跨网络复用可能命中旧上游结果，需按网络维度分区缓存或切换时清关键前缀。

#### A3. Captive Portal 与「网络已认证」门控 — P0
- **用户价值**：连酒店/机场 Wi-Fi 时，先完成门户登录再启用拦截，避免「上不了网」的误解。
- **技术方案**：新 crate **`diting-captive-core`**（建议）：解析 RFC 8910 `Captive-Portal` DHCP/RA 选项、
  处理 `generate_204` 探测结果与重定向目标；Kotlin 侧用 `NetworkCapabilities` 的
  `CAPTURE_PORTAL`/`NET_CAPABILITY_VALIDATED` 交叉校验；检测到门户时**临时放行门户域名 + 暂停阻断**并弹提示。
- **风险**：某些门户依赖系统 WebView/CaptivePortal app，第三方 VpnService 无法完全接管，需回退「一键跳系统门户」。

### B. 每应用 / 域名路由与上游

#### B1. 每应用指定上游 / 策略 — P0
- **用户价值**：工作 App 走公司 DNS、流媒体 App 走无过滤上游、游戏 App 走低延迟上游。
- **技术方案**：扩展 `diting-policy-core` 判定输出为 `Decision { allow|block, upstream_tag, outbound_tag }`；
  新增 **`diting-route-core`**（建议）编译「应用(UID/包名) → 策略」规则表，复用 `diting-filter-core` 的
  反向标签 trie + bloom 思路；UI 在应用分流页加「上游选择」下拉（下拉项来自现有 provider 列表）。
- **风险**：每应用上游会放大并发连接数与缓存分片压力，需给「每上游最大并发」与缓存 key 加 upstream 维度。

#### B2. 域名 → 上游分流（geosite / geoip / rule_set）— P0/P1
- **用户价值**：按域名/地区智能分流（国内直连、境外走代理上游），减少无谓跨境查询与污染。
- **技术方案**：新增 **`diting-ruleset-core`**（建议）：加载 sing-box `.srs` 与 Clash `rule-provider`、
  AdGuard 语法名单（`diting-rule-core` 已支持 AdGuard 语法导入），构建「域名后缀 trie + IP CIDR 集」；
  `diting-route-core` 在解析阶段先匹配域名（命中即定 upstream），未命中再按 IP 归属（geoip）二次判定。
- **风险**：geoip 数据体积与更新频率；`.srs` 二进制格式需严格对齐，建议只做「只读加载 + 校验和」，
  不做在线自动更新以防供应链风险。

#### B3. 条件路由 + 回退链 / 故障切换 — P0
- **用户价值**：主上游故障自动降级到备用链，且可对「某类域名」单独定义回退顺序。
- **技术方案**：扩 `diting-resolver-core`：把「四策略调度」提升为「策略组（chain）」，
  每组有序 provider 列表 + 健康门槛（连续失败 N 次 / SRTT 超阈值 → 降级）；新增 **`diting-chaingroup-core`**
  （建议，若 `resolver-core` 已足够可合并）。UI 参照 Clash proxy-group 的 fallback / url-test / load-balance。
- **风险**：回退链与「并行竞速」策略语义叠加会产生组合爆炸，需限定「每规则最多一条链、链长 ≤ 4」。

#### B4. 自定义 DNS stamp 导入（sdns://）— P1
- **用户价值**：一键导入第三方 DoH/DoT/DoQ 配置，降低手填门槛。
- **技术方案**：把已有 `diting-stamp-core`（桌面已成熟、安卓未链接）链接进 `libditing_kernels.so`，
  Dart 经 FFI 调用解析 → 转成 `diting-config-core` 的 provider 行。
- **风险**：stamp 校验需容错（坏 stamp 不能崩 UI）；需维护 `ABI_VERSION`。

### C. 实时连接 / 流量监控与可视化

#### C1. Flow 会话视图（5 元组 + UID + 域名 + SNI + 字节 + 判定）— P0
- **用户价值**：像 PCAPdroid / NetGuard 一样看到「哪个 App 连了哪个域名/IP、走了哪条上游、是否被阻断」。
- **技术方案**：新增 **`diting-flow-core`**（建议）：环形缓冲维护会话表，字段 `{proto, src, dst, uid, app,
  domain(from ipcache), sni(from sniffer), bytes_in/out, verdict, upstream_tag, first_seen, last_seen}`；
  数据源全部现成：`connlog-core`（去重）、`sniffer-core`（SNI/Host）、`ipcache-core`（IP→域名）、
  `telemetry-core`（UID 计数）。引擎侧写环形缓冲，Kotlin 侧按页导出给 Dart（`pages/network/flow`）。
- **风险**：高频连接下内存与锁竞争；需采样与容量上限（如 2000 条滚动），并做「暂停刷新」。

#### C2. 可视化聚合（按应用 / 域名 / 国家 / 公司 treemap、时间线）— P1
- **用户价值**：一眼看出流量分布与被追踪情况，替代纯列表。
- **技术方案**：Dart 侧对 `diting-flow-core` 快照做聚合（应用、域名后缀、目的地国家/公司）；
  Flutter 用 `fl_chart` / 自绘 treemap；国家/公司归属可离线库（如本地 GeoLite 精简集，只读）。
- **风险**：离线 GeoIP 库体积与许可证（GeoLite2 需署名，CC BY-SA 4.0）；聚合计算放 UI 线程会卡，需 isolate。

#### C3. 可选 PCAP 导出 — P2
- **用户价值**：高级用户导出抓包做深度分析（NetGuard / PCAPdroid 均有）。
- **技术方案**：新增 **`diting-pcap-core`**（建议，或复用现成 pcap 写入 crate）：把 flow 报文按 PCAP/pcapng
  落盘；默认关闭，需显式授权（隐私）。
- **风险**：导出文件可能含敏感信息；存储与耗电；需「导出前脱敏提示」。

### D. DNS 健壮性与保密

#### D1. DNS 泄漏检测 — P0
- **用户价值**：确认查询真的走了配置的加密上游，而不是被系统/路由器劫持到明文 53。
- **技术方案**：新增 **`diting-leak-core`**（建议，复用 `diting-probe-core` 的解析能力）：对
  `whoami.cloudflare`（TXT）、`o-o.myaddr.l.google.com` 等指纹域名发起查询，比对「出口解析器身份」与
  「配置上游」是否一致；同时监听是否有 53/853 明文出站。结果给「通过 / 泄漏 / 无法判定」三态。
- **风险**：指纹域名依赖第三方服务可用性；双栈/多上游时「一致性」判定复杂，需仅作提示不作硬阻断。

#### D2. DoH3 / HTTP3 上游 — P1
- **用户价值**：弱网/高丢包下 QUIC 的 0-RTT 与无队头阻塞优于 DoH/TCP。
- **技术方案**：扩 `diting-upstream-core`（新增 `h3` 传输常量 + DoH3 分帧/状态分类），复用已有 `quinn`；
  配置文档经 `diting-config-core` 校验。sing-box 的 `https`/`http3` DNS server 类型可作参照。
- **风险**：H3 与现有 DoH 状态机（`upstream-core` 的 DoH 状态分类）需统一；部分网络封 UDP 443，需自动回退 DoH。

#### D3. DoT / DoQ / DoH 连接复用与多路复用 — P1
- **用户价值**：降低握手开销与尾延迟，提升高频查询吞吐。
- **技术方案**：`diting-upstream-core` 已有 DoT 空闲池，扩展为：DoT 连接池化、DoQ（QUIC 连接复用 +
  stream 并发）、DoH 用 HTTP/2 多路复用（sing-box 的 `multiplex` 字段思路）；空闲超时与健康探测复用
  `resolver-core` 统计。
- **风险**：连接复用会把「单连接故障」放大为「多查询失败」，需配合 B3 的健康门槛快速切换。

#### D4. IPv6-only / DNS64 接入 — P1
- **用户价值**：纯 IPv6 蜂窝/Wi-Fi（无 CLAT）下仍能访问 IPv4-only 站点。
- **技术方案**：把桌面已成熟的 `diting-dns64-core`（RFC 6052/6147）**链接进 `libditing_engine.so`**；
  用 `ConnectivityManager` 判断是否具备 IPv6 且无 IPv4，决定是否对 A 记录合成 AAAA；配置开关进
  `diting-config-core`。
- **风险**：合成前缀与运营商 NAT64 前缀不一致会导致不可达，需支持「自动探测 + 手动前缀」。

#### D5. ECH（Encrypted Client Hello）— P2
- **用户价值**：隐藏 SNI，补足「DNS 已加密但 SNI 泄露」的隐私缺口。
- **技术方案**：依赖 `rustls` 的 ECH 能力（受版本限制）+ 通过 DoH 拉取 `ECHConfigList` 写入 TLS 客户端；
  需与 `bootstrap-core` 协作解析 ECH 域名。
- **风险**：生态支持不完整、易碎；建议只做「实验开关 + 能力探测」，不设为默认。

### E. Kill switch / 始终开启 / 防绕过 / 重连

#### E1. 应用级 Kill switch + 系统 always-on 引导 — P0
- **用户价值**：隧道异常时不泄露真实 IP/DNS（NetGuard/AdGuard 的「始终开启 VPN + 无 VPN 时阻断」）。
- **技术方案**：Kotlin `VpnService`：`Builder.setBlocking(true)`、`setUnderlyingNetworks(null)` 防止绕过；
  引导用户开启系统「始终开启 VPN / 阻止无 VPN 连接」（`Settings.ACTION_VPN_SETTINGS`）；状态机扩展
  `diting-vpn-config-core` 的 watchdog。
- **风险**：`setBlocking` 行为随厂商 ROM 差异；系统 always-on 只能引导不能代设。

#### E2. 防绕过清单（DoH canary / 私有中继 / 明文 53 / 自定义 DoH）— P1
- **用户价值**：防止 App 用自带 DoH 或 iCloud Private Relay 绕过谛听拦截。
- **技术方案**：参照 AdGuard DNS 的「block Firefox canary domain / block iCloud Private Relay」：
  在 `policy-core` 加内置阻断组（canary 域名、`mask.icloud.com` 等）；对明文 53/853 出站做「强制劫持到本地解析」
  或阻断，策略进 `diting-netprofile-core`。
- **风险**：过度阻断会影响依赖私有 DoH 的正常 App；需分级（提示 / 阻断）与白名单。

#### E3. 断线重连与看门狗增强 — P0
- **用户价值**：移动网络抖动后自动恢复，不出现「表面开着实际没生效」。
- **技术方案**：`NetworkCallback` 驱动重连（而非定时盲轮询）；`diting-vpn-config-core` 的 watchdog 状态机
  增加指数退避 + 最大重试 + 用户可见状态；与 E1 的 blocking 联动。
- **风险**：频繁重连耗电；退避参数需注入时钟以便单测重放（遵守架构约束「时间注入」）。

### F. 带宽 / 限速 / QoS / LAN 客户端管理

#### F1. LAN 客户端表 + 每客户端限速 / 分组 — P1
- **用户价值**：服务器模式下，管理家里每台设备（谁在用、限速多少、是否放行）。
- **技术方案**：服务器模式接入 `diting-ratelimit-core`（令牌桶 + CIDR 豁免）→ 新增 **`diting-lanclient-core`**
  （建议）：客户端表 `{ip, mac(neighbor 解析), hostname, profile, rate_limit, blocked}`；
  邻接解析参照 sing-box `neighbor` 字段思路。
- **风险**：MAC 获取在部分网络需 ARP/NDP 权限；NAT 后多设备同 IP 难区分。

#### F2. 每应用带宽监控与可选限速 — P2
- **用户价值**：找出偷跑流量的 App，必要时限速。
- **技术方案**：监控用 `telemetry-core` 现有按 UID 计数 + `TrafficStats`；限速在引擎侧对每 UID 令牌桶
  （复用 `ratelimit-core` 的桶实现，按 UID 维度）。
- **风险**：Android 上对已建立连接做整形需在数据面逐包节流，CPU 成本高；建议先「监控 + 提示」，限速为实验。

#### F3. 流量统计口径统一 — P1
- **用户价值**：避免「DNS 查询数 / 请求数 / 字节数」三套数字互相矛盾。
- **技术方案**：明确三层口径：DNS 查询（`resolver-core` 计数）、请求（`connlog-core`）、字节
  （`telemetry-core` + 引擎字节计数）；MITM 场景标记「解密字节」避免与「原始字节」双算；口径定义进
  `diting-log-core` / `diting-notification-core` 的统一格式化。
- **风险**：历史数据与新口径对不上，需迁移说明或按版本分列。

---

### 三·附A 关键数据结构草案（示意，落地时以 `diting-*-config-core` 方式实现）

```rust
// diting-netprofile-core：网络状态 → 差异化设置（由 Kotlin 填充，Rust 只读消费）
pub enum Transport { Wifi, Cellular, Ethernet, Vpn, Other }
pub struct NetworkProfile {
    pub transport: Transport,
    pub metered: bool,
    pub roaming: bool,
    pub constrained: bool,          // 低数据/省电模式，对应 sing-box network_is_constrained
    pub ssid: Option<String>,       // 需定位权限，缺省即不参与匹配
    pub bssid: Option<String>,
    pub validated: bool,            // NET_CAPABILITY_VALIDATED
}

// diting-route-core：条件路由规则（字段对齐 sing-box route rule）
pub struct RouteRule {
    pub app: Option<AppMatch>,      // UID / package_name / package_name_regex
    pub domain: Option<DomainSet>,  // suffix / keyword / regex / geosite / rule_set
    pub ip_cidr: Option<Vec<String>>,   // geoip / rule_set 展开后
    pub network: Option<NetworkMatch>,  // transport / metered / roaming / wifi_ssid
    pub action: RouteAction,
}
pub enum RouteAction { Block, Reject, Direct, Upstream(String), Chain(String) }

// diting-policy-core 的决策输出扩展（保持向后兼容，新增字段默认 None）
pub struct Decision {
    pub verdict: Verdict,           // Allow / Block（现有）
    pub upstream_tag: Option<String>,   // 新增：走哪个上游
    pub outbound_tag: Option<String>,   // 新增：走哪个出站/出口
    pub chain: Option<String>,          // 新增：回退链 / 策略组名
}

// diting-flow-core：一次性会话快照（环形缓冲投影给 UI）
pub struct FlowSession {
    pub proto: Proto, pub src: SocketAddr, pub dst: SocketAddr,
    pub uid: u32, pub app: Option<String>, pub domain: Option<String>,
    pub sni: Option<String>, pub bytes_in: u64, pub bytes_out: u64,
    pub verdict: Verdict, pub upstream_tag: Option<String>,
    pub first_seen_ms: i64, pub last_seen_ms: i64,
}
```

### 三·附B 实施顺序与验收要点

| 阶段 | 交付 | 依赖 | 验收要点 |
|---|---|---|---|
| 里程碑 1（P0 上半） | 网络 Profile + 热重载 + Captive Portal | Kotlin ConnectivityManager、`netprofile-core`、`captive-core` | 切换 Wi-Fi/蜂窝后 3s 内上游切换且不重建 TUN；门户场景可完成登录 |
| 里程碑 2（P0 下半） | 条件路由 + 回退链 + 每应用上游 | `route-core`、`chaingroup-core`、`policy-core` 决策扩展 | 按规则命中正确上游；主上游断连续失败 N 次自动降级；规则测试器可复现判定 |
| 里程碑 3（P0 收尾） | Flow 视图 + Kill switch + 重连 + DNS 泄漏检测 | `flow-core`、`vpn-config-core`、`leak-core` | Flow 字段齐全（应用/域名/SNI/字节/判定）；隧道异常时 blocking 生效；泄漏检测三态可判 |
| 里程碑 4（P1） | DoH3、连接复用、DNS64、LAN 客户端管理 | `upstream-core`、`quinn`、`dns64-core`、`ratelimit-core`、`lanclient-core` | doh3 可连且回退 doh；DoQ/DoT 复用连接；纯 IPv6 可解析 AAAA；LAN 客户端限速生效 |
| 里程碑 5（P2） | ECH、PCAP 导出、ruleset 在线更新、每应用限速 | `rustls`、`pcap-core`、`ruleset-core` | 实验开关默认关；导出文件脱敏提示；规则集校验和通过 |

**跨里程碑测试要点**：所有含时间的判定（退避、冷却、限速、缓存过期）注入时钟以便重放；
新增 FFI/JNI 维护 `ABI_VERSION`；每个新内核附最小单测（规则命中、profile 切换、flow 聚合、泄漏判定）。

---

## 四、与 Rust 内核结合的可行实现点（映射表）

| 功能 | 复用现有 crate | 建议新增 crate | FFI / JNI 边界 |
|---|---|---|---|
| 网络 Profile（A1/A2） | `diting-vpn-config-core`、`diting-config-core` | `diting-netprofile-core` | Dart FFI 读配置；Kotlin 经 JNI 推给 engine |
| 条件路由（B1/B2/B3） | `diting-policy-core`、`diting-filter-core`(桌面)、`diting-rule-core` | `diting-route-core`、`diting-ruleset-core` | engine JNI（解析期决策） |
| 回退链 / 策略组（B3） | `diting-resolver-core` | `diting-chaingroup-core`（或并入 resolver） | engine |
| Flow 会话视图（C1） | `diting-connlog-core`、`diting-sniffer-core`、`diting-ipcache-core`、`diting-telemetry-core` | `diting-flow-core` | engine 写环形缓冲；Kotlin 导出给 Dart |
| PCAP 导出（C3） | — | `diting-pcap-core` | Dart FFI |
| DNS 泄漏检测（D1） | `diting-probe-core` | `diting-leak-core` | Dart FFI |
| Captive Portal（A3） | — | `diting-captive-core`（RFC 8910 解析） | Dart FFI + Kotlin NetworkCapabilities |
| DoH3 / 连接复用（D2/D3） | `diting-upstream-core`、`quinn`、`rustls` | 无（扩展） | engine |
| DNS64（D4） | **`diting-dns64-core`（已有，安卓未链接）** | — | engine（链接进 `.so`） |
| Kill switch / 重连（E1/E3） | `diting-vpn-config-core`(watchdog) | 无（扩展） | Kotlin `VpnService` / `ConnectivityManager` |
| 防绕过（E2） | `diting-policy-core`、`diting-dns-core` | 无（内置阻断组） | engine |
| LAN 客户端限速（F1） | **`diting-ratelimit-core`（已有，安卓未链接）** | `diting-lanclient-core` | server 模式 JNI |
| stamp 导入（B4） | **`diting-stamp-core`（已有，安卓未链接）** | — | Dart FFI（`libditing_kernels.so`） |
| 域名/地址规则集（B2） | `diting-rule-core`、`diting-rule-store-core` | `diting-ruleset-core` | 两侧 |

**原则复述**（来自 `01-现状与架构分析.md` 第 6 节）：判定逻辑一律落 Rust；新增配置进 `diting-*-config-core`；
UI 内核走 C ABI（`dart:ffi`），数据面走 JNI；新内核维护 `ABI_VERSION`；含时间判定必须注入时钟。

---

## 五、许可证兼容性提示

> 谛听整体为 **GPL-3.0**。以下为通用原则 + 逐项目边界。**所有许可证结论在落地前须以仓库 `LICENSE`
> 实际文本复核**（本轮 GitHub 不可达，多为知识推断）。

### 5.1 总原则
1. **GPL-3.0 项目**（NetGuard、AdGuard for Android、TrackerControl、PCAPdroid、sing-box、Clash Meta/mihomo）：
   与谛听同为 GPL-3.0，**可以借鉴代码思路、也可在保留版权与来源声明前提下复用代码**；但「把对方源码整体
   翻译成 Rust」仍属派生作品，须继续 GPL-3.0 并注明来源。
2. **MPL-2.0（RethinkDNS）**：文件级 copyleft。**只借鉴设计**，若复用其单个源文件需保持该文件 MPL-2.0 并公开
   修改；建议**干净重写**，避免把 MPL 代码混入 GPL 文件造成边界模糊。
3. **Apache-2.0 / MIT / BSD-3-Clause**（Intra、Tailscale 客户端、多数 Rust crate）：与 GPL-3.0 **单向兼容**
   （可并入 GPL-3.0 作品）；Apache-2.0 需保留 `NOTICE` 与专利授权条款，BSD-3 需保留署名与禁止背书条款。
4. **闭源 / 云服务**（NextDNS 服务、DNSCloak、Blokada 云、AdGuard DNS 服务）：**只借鉴 UI/交互/协议设计**，
   不复制实现、不逆向其私有协议；可参考其公开知识库描述的机制。
5. **规则/名单数据**：AdGuard DNS filter、EasyList、GeoLite2 等**数据本身有独立许可证**
   （EasyList 多为 CC BY-SA / GPL 混合，GeoLite2 为 CC BY-SA 4.0 需署名），与代码许可证分开处理，导入前逐一核对。

### 5.2 逐项目可用边界

| 项目 | 许可证（待复核） | 可用于谛听的边界 |
|---|---|---|
| NetGuard | GPL-3.0 | 可借鉴/复用，保留来源；数据面思路可直接参考 |
| AdGuard for Android | GPL-3.0 | 可借鉴/复用，保留来源与版权 |
| TrackerControl | GPL-3.0 | 可借鉴/复用（其底层源自 NetGuard 思路） |
| PCAPdroid | GPL-3.0 | 可借鉴/复用；PCAP 导出实现注意来源声明 |
| sing-box | GPL-3.0 | 可借鉴字段模型与规则语义；整体翻译属派生，须 GPL |
| Clash Meta / mihomo、FlClash | GPL-3.0 | 可借鉴策略组/规则提供者设计 |
| RethinkDNS | MPL-2.0 | **仅借鉴设计**；如需复用文件须文件级隔离并公开修改 |
| Intra | Apache-2.0 | 可并入，保留 NOTICE；DoH 选择器设计可参考 |
| Tailscale（客户端） | BSD-3-Clause | 出口节点概念可参考；保留署名、禁背书 |
| NextDNS（服务/客户端） | 服务专有 / CLI 或 MIT | 仅借鉴「配置档案/日志留存」产品设计 |
| DNSCloak | 专有（未核实） | 仅借鉴 DoH 服务器选择等交互 |
| Blokada | 客户端 GPL-3.0 / 云专有 | 客户端可借鉴；云与 Family 仅借鉴分组/家长设计 |
| personalDNSfilter | GPL（版本待核实） | 可借鉴轻量网络切换逻辑；复用前核对版本 |

### 5.3 具体风险点
- **别把「借鉴」写成「翻译」**：对 sing-box / Clash 这类 GPL 项目，逐行翻译的 Rust 代码仍受 GPL 约束；
  谛听本身是 GPL-3.0 故兼容，但必须保留原始版权与出处，不能声称完全原创。
- **MPL 文件隔离**：若确需复用 RethinkDNS 的某个 Kotlin 文件，务必单独目录 + 单独 LICENSE 头，
  不与被 GPL 覆盖的文件互相 import。
- **数据许可 ≠ 代码许可**：即使代码是 GPL，其内置 blocklist 也可能来自 CC BY-SA 名单，需分别署名。
- **专利条款**：Apache-2.0（Intra 等）含专利授权，并入时保留 NOTICE，避免专利纠纷时失去授权。
- **第三方服务条款**：DoH 指纹探测域名（D1）与 GeoIP 下载（C2/B2）受服务方 ToS 约束，需读条款再内置。

---

## 六、参考来源与核实状态

**已联网核实（本轮 HTTP 200）**
- sing-box 路由规则：https://sing-box.sagernet.org/configuration/route/rule/
- sing-box DNS 规则动作：https://sing-box.sagernet.org/configuration/dns/rule_action/
- sing-box Wi-Fi State：https://sing-box.sagernet.org/configuration/shared/wifi-state/
- sing-box GeoIP：https://sing-box.sagernet.org/configuration/route/geoip/
- sing-box 首页/目录：https://sing-box.sagernet.org/
- NetGuard 官网：https://netguard.me/
- NextDNS 官网：https://nextdns.io/
- Blokada 官网：https://blokada.org/
- TrackerControl 官网：https://trackercontrol.org/
- AdGuard DNS 知识库（总览）：https://adguard-dns.io/kb/
- AdGuard DNS 私有 DNS 概览：https://adguard-dns.io/kb/private-dns/overview/
- AdGuard for Android 概览：https://adguard.com/en/adguard-android/overview.html
- Cloudflare 1.1.1.1 文档：https://developers.cloudflare.com/1.1.1.1/
- PCAPdroid 用户指南：https://emanuele-f.github.io/PCAPdroid/
- Tailscale exit node：https://tailscale.com/docs/features/exit-nodes
- personalDNSfilter 作者站：https://www.zenz-solutions.de/

**未能联网核实（GitHub / 部分站点不可达，结论基于既有知识）**
- RethinkDNS 仓库：https://github.com/celzero/rethink-app
- NetGuard 仓库：https://github.com/M66B/NetGuard
- TrackerControl 仓库：https://github.com/TrackerControl/tracker-control-android
- PCAPdroid 仓库：https://github.com/emanuele-f/PCAPdroid
- sing-box 仓库：https://github.com/SagerNet/sing-box
- Clash Meta / mihomo：https://github.com/MetaCubeX/mihomo
- Blokada 源码入口：https://go.blokada.org/dev_home
- Intra：https://github.com/Jigsaw-Code/intra-android

> 落地建议：进入实现阶段前，先用可联网环境复核上表「许可证（待复核）」项，并优先核对
> `diting-dns64-core`、`diting-ratelimit-core`、`diting-stamp-core`、`diting-filter-core` 的真实接口，
> 确认「链接进安卓 `.so`」的改动量（`01-现状与架构分析.md` 已提示部分 crate 可能为历史保留，需核对依赖路径）。
