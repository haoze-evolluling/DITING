# 谛听（DITING）安卓端 · 规则管理方向开源借鉴调研

> 范围：`android/app`（Flutter · Riverpod · sqflite）、`rust/`（Rust 内核，重点是 `diting-rule-core`、
> `diting-policy-core`、`diting-filter-core`、`diting-rule-store-core`、`diting-subscription-core`、
> `diting-hosts-core`、`diting-cosmetic-core`、`diting-allowlist-core`、`diting-rewrite-core`、`diting-engine`）、
> `desktop/`（Go 服务已实现的规则能力）、`LearningObjects/`（`AdGuardHome-0.107.80`、`blockads-android-7.1.1`、
> `FlClash-0.9.3` 三份本地参照源码）。
> 基线：谛听已有「黑/白名单、AdGuard 语法（通配符/正则/Cosmetic）、域名覆写（A/AAAA/CNAME/NS/PTR）、
> 阻断响应（空 IP/NXDOMAIN/REFUSED + 按域名动态升级）、远程订阅 + 分组 + 镜像 + 定时更新、批量编辑、规则搜索」
> 这些**已有能力本文不再重复推荐**；桌面端已具备而安卓缺失的（规则测试模拟器、订阅健康状态、临时暂停、
> 仅白名单、响应侧别名链复检、伪应答纠正、自定义规则编辑器 + 语法速查、blocked services 预设）在第三节作为
> “补齐项”列出。
> 本文只写一个文件，不改任何代码。时间：2026-11。优先级：`P0` 立即 / `P1` 近期 / `P2` 中期。
> 难度统一记作「Flutter / Rust」。

---

## 0. 方法与核实状态

- **已联网核实（`web_fetch` 返回 HTTP 200）**：
  - AdGuard DNS 过滤规则语法 <https://adguard-dns.io/kb/general/dns-filtering-syntax/>（`denyallow` / `dnstype` /
    `dnsrewrite` / `important` / `badfilter` / `ctag` / `client` / `respgeo` 语义齐全）；
  - AdGuard「如何编写自定义过滤规则」<https://adguard.com/kb/general/ad-filtering/create-own-filters/>
    （ABP 同源语法、`$app` / `$domain` / `$denyallow` / `$to` 与各平台支持矩阵）；
  - AdGuard「跟踪过滤规则统计」<https://adguard.com/kb/general/ad-filtering/tracking-filter-statistics/>
    （**按 filter ID + rule 文本归集命中**的遥测模型）；
  - AdGuard Home 概览 <https://adguard-dns.io/kb/adguard-home/overview/>；
  - sing-box 规则集目录 <https://sing-box.sagernet.org/configuration/rule-set/>、AdGuard DNS Filter 转换
    <https://sing-box.sagernet.org/configuration/rule-set/adguard/>、Headless Rule 字段表
    <https://sing-box.sagernet.org/configuration/rule-set/headless-rule/>；
  - AdGuard Filters Compiler README（`raw.githubusercontent.com/AdguardTeam/FiltersCompiler/master/README.md`，
    含**按命中统计优化规则**、AdGuard↔uBO 格式互转、按平台裁剪能力）。
- **未能联网核实**：`github.com` 网页与 `raw.githubusercontent.com` 在本环境间歇不可达（`fetch failed` / 404）。
  因此 uBlock Origin、AdAway、StevenBlack/hosts、OISD、hagezi、RethinkDNS、Clash Meta/mihomo、Pi-hole、blocky、
  Technitium 的**仓库级实现细节与许可证**主要基于既有知识。落地前须以各仓库 `LICENSE` 与源码为准；相应位置标注
  「未能联网核实」。
- **本地一手证据（本仓库 `LearningObjects/`，已核对源码）**：`AdGuardHome-0.107.80` 的
  `internal/filtering/reason.go`（`Reason` 枚举）、`internal/filtering/filtering.go`（`makeResult`）、
  `internal/filtering/filter.go`（每库 `RulesCount`）、`internal/querylog/*`（逐条 `Rules[]{FilterListID,Text}`）、
  `internal/stats/*`（`top_blocked_domains` / `top_queried_domains`）；`FlClash-0.9.3` 的
  `lib/enum/enum.dart`（`RuleProviderBehavior{domain,ipcidr,classical}`）、`lib/database/clash_providers.dart`
  （`behavior/format/order` 落库）；三份本地副本 `LICENSE` 均为 **GPL-3.0**。
- 机制描述只讲「设计与交互范式」，实现一律回到谛听自己的 Rust 内核，不引入第二套 Dart/Kotlin 判定语义。

### 0.1 本文增量边界（已有能力不重复）

按 crate 梳理既有职责，本文只在“缺口”上做增量，**不重复**注解语法、订阅增删改、搜索与批量编辑：

- `diting-rule-core`：单行解析（adblock / hosts / dnsmasq / cosmetic / URL / `$badfilter`）、`.dtri` 订阅索引写入与校验、
  规则搜索索引、快照文档构建。
- `diting-policy-core`：快照表、七级优先级判定、通配索引、`Decision{action, reason, rule}`、分片决策缓存。
- `diting-filter-core`：四层 Trie + Bloom 预筛、`$dnsrewrite` 选择、`Reason` 六码（桌面 Go 面唯一实现）。
- `diting-rule-store-core`：行↔规则映射、去重键、导入与源清扫的语句计划（SQLite 留在 Dart）。
- `diting-subscription-core`：URL/镜像规则、抓取策略与状态、自动更新调度、行模型与表单。
- `diting-hosts-core` / `diting-cosmetic-core` / `diting-rewrite-core` / `diting-allowlist-core`：hosts、元素隐藏、域名覆写、应用白名单。
- **本文增量** = ①可解释性与命中统计 ②规则测试/冲突/排序 ③订阅治理 ④时间/场景/预设 ⑤响应侧/健壮性 ⑥格式识别与转换。

---

## 一、结论摘要

1. **规则管理的“下一步”不是加语法，而是加“可解释 + 可治理”**：谛听已能拦截，但用户答不出“是哪条规则、
   来自哪个订阅、为什么是它赢”。AdGuard Home 的 `Result{rules[],reason}` 归因模型、逐库 `RulesCount`、
   `top_blocked_domains` 统计，是投入产出比最高的一层，**安卓端几乎可零新语法地补齐**。
2. **规则测试模拟器应作为 P0 落地**：桌面端 `POST /api/v1/filter/check` 已返回 `action/matchedRule/listName/
   reason/rewritten`；安卓只需把 `policy-core::Snapshot::answer`（现有七级判定）经 JNI 暴露成 `checkHost`，
   前端做一个输入域名+qtype 的页面即可，**复用度接近 100%**。
3. **“命中统计”要有边界**：全量逐查询计数会抢 DNS 热路径的原子操作。建议**按 rule-id 分片原子计数 + 定时
   落库 + 采样开关**，并与现有请求日志的 `matchedRule` 字段（安卓已有）打通，避免两套口径。
4. **订阅治理是安卓最大缺口**：`diting-subscription-core` 已有 `ruleCount/httpEtag/httpLastModified/
   importState/consecutiveFailureCount/ruleSetHash` 等字段，但缺“ok/304/cached/failed”状态聚合、
   “失败保留旧规则（cached）”语义与逐库健康/版本 diff UI——正是桌面端与 blocky `downloaded_cache` 的做法。
5. **二进制规则集是 Rust 内核的天然落点**：谛听已有 `.dtri`（mmap 订阅规则索引，`diting-rule-core::dtri`），
   与 sing-box 的 `.srs`、mihomo 的 `.mrs`（zstd 二进制规则集）在思想上完全同构。只需补**版本戳 + 校验和 +
   格式标记**，就能把“编译一次、分发多处、mmap 直读”的能力对齐，且无需新 `.so`。
6. **规则组织模型值得对齐 sing-box headless 字段集**：`domain / domain_suffix / domain_keyword / domain_regex /
   ip_cidr / package_name / invert` 与逻辑组合，正好覆盖谛听“域名 + 应用 + 类型”的规则维度，可作为快照
   schema 的命名参照，避免自造词。
7. **优先级/冲突需要“可见化”而非“可编程”**：谛听七级判定顺序（`$dnsrewrite` > `$important` allow >
   `$important` block > `@@` allow > block trie > wildcard/regex block）已经稳定，新增的是**只读的解释视图
   + 被遮蔽规则提示 + 订阅级拖拽排序**，不建议让用户任意改判定树。
8. **格式导入已相当完整**：`diting-rule-core::line/hosts/document` 已解析 adblock、hosts、dnsmasq、cosmetic、
   URL 规则、`$badfilter`。缺的是**显式格式探测 + 导出/转换**与（可选）geosite/yaml；ABP 专有修饰符可继续旁路。
9. **正则安全**：谛听运行时若走 Rust `regex`（线性时间、无回溯）则先天抗 ReDoS；风险主要在**导入期**接受
   任意 `/.../` 源码与 Go-compat 路径。应加“长度/构造预算 + 编译超时 + 危险量词拒绝”，并把拒绝原因回显。
10. **时间/场景化与 preset 是补齐项**：桌面端 `BlockingSchedule` / `ServiceSchedules`（分时、服务级周计划）、
    `BlockedServices`（内置服务目录 `services.json`）、`AllowlistOnly`、`PauseFor` 均已实现，安卓可照搬语义，
    用注入时钟的纯 Rust 内核实现（便于测试）。
11. **响应侧与伪应答属“深链绕过”补全**：桌面端 `MatchResponse`（CNAME 别名链复检，`MaxResponseAliasDepth=8`）
    与 `BogusNXDomainMatcher`（伪应答改写 NXDOMAIN）已有成熟实现，安卓缺，建议移植为独立内核。
12. **geoip/geosite 不建议作为核心引入**：DNS 过滤在域名维度收益有限、体积与更新成本高；仅建议以“域名分类
    preset（可下载、可关闭）”形式提供，不进入默认规则路径。
13. **许可证**：谛听为 GPL-3.0；GPL-3.0 项目（AdGuard Home/Android/FiltersCompiler/HostlistCompiler、uBO、
    AdAway、sing-box、mihomo、FlClash、hagezi〔待核实〕）可借鉴并合并代码但须整体开源署名；MIT/Apache-2.0/
    BSD（StevenBlack、blocky、Pi-hole 的 GPL-2.0 亦可并入 GPL-3.0）单向兼容；MPL-2.0（RethinkDNS）须文件级
    隔离；专有服务（AdGuard DNS 服务、NextDNS）只借鉴设计。
14. **优先级建议**：P0「规则测试模拟器、命中统计与归因面板、订阅健康状态、临时暂停/仅白名单」；P1「冲突
    检测与优先级视图、订阅版本 diff/回滚、时间/场景规则、blocked services 预设、响应侧别名链复检」；
    P2「格式转换/导出、正则预算、伪应答纠正、二进制规则集版本化、geosite 可选 preset」。

---

## 二、借鉴表

> 列说明：**难度 = Flutter / Rust**；`P0` 核心补齐、`P1` 重要增强、`P2` 锦上添花。许可证列标「未核实」表示
> 本轮无法读取 LICENSE 文件，落地前须复核；标「本地已核对」表示已读本仓库 `LearningObjects/` 下 `LICENSE`。

### 2.0 现有内核能力 → 规则管理增强落点

| 内核 crate | 现有职责 | 本方向可扩展点（只读/低风险优先） |
|---|---|---|
| `diting-policy-core` | 快照表、七级判定、`Decision{action,reason,rule}` | 扩 payload `rule→source/raw` 映射；`check_host` 只读入口；命中计数；`allowlist_only` 门控；冲突分析 pass |
| `diting-filter-core` | 四层 Trie + Bloom + rewrite 选择（桌面 Go 面） | 复用 `match_domain` 做模拟器；暴露 `uncompiled_patterns`；与 `policy-core` 语义对齐 |
| `diting-rule-core` | 解析 + `.dtri` 写入 + 搜索 + 快照文档 | 加 `format_detect` / `convert` 子模块；正则预算；`.dtri` 版本头 |
| `diting-rule-store-core` | 行映射/去重/导入语句 | 落命中计数表；版本快照与 diff 的语句计划 |
| `diting-subscription-core` | URL/抓取/调度/行模型 | 派生 `lastStatus`（ok/unchanged/cached/failed）；`behavior/format/interval` 扩展 |
| `diting-engine`（JNI） | 隧道数据面 + DNS 管线 | 暴露 `checkHost`、暂停/仅白名单开关、统计查询 |

### 2.1 规则归因 / 命中统计 / 可解释性

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| AdGuard Home | GPL-3.0（本地已核对） | `Result{rules[], reason}`；`ResultRule{FilterListID, Text}`；`Reason` 枚举（FilteredBlackList / FilteredSafeBrowsing / FilteredParental / FilteredBlockedService / RewrittenRule / NotFilteredAllowList…）；querylog 逐条存 `Rules[]{filter_list_id, text}`；`top_blocked_domains`/`top_queried_domains` | `policy-core::Decision` 已有 `rule:Option<u32>`+`Reason`；快照 payload 增补 `rule_id→{source/list_name, raw_text}` 映射；JNI 暴露完整 Decision；请求日志与“规则命中榜”共用同一 rule-id | 中 / 中 | P0 | https://github.com/AdguardTeam/AdGuardHome |
| AdGuard「过滤规则统计」 | 专有产品 / 公开 KB | 以 `filter ID + rule 文本` 归集“哪条规则在哪些域被触发”，用于删除失效规则 | “规则命中榜 + 订阅命中榜”，并标“近 N 天未命中”候选清理（本地统计，不上传） | 低 / 低 | P1 | https://adguard.com/kb/general/ad-filtering/tracking-filter-statistics/ |
| AdGuard Filters Compiler | GPL-3.0 | 用 **hit-count 统计**判断可优化规则并压缩；AdGuard↔uBO 互转；按平台 `removeRulePatterns` 裁剪 | 对齐“基于本地命中统计的规则瘦身”与“导入时按引擎能力裁剪不支持规则并计数回显” | 中 / 中 | P2 | https://github.com/AdguardTeam/FiltersCompiler |
| uBlock Origin（Logger） | GPL-3.0（未能联网核实） | 过滤日志逐请求显示“命中哪条静态/动态规则、哪个过滤器、结果色块” | 请求明细页 `matchedRule` 升级为“规则原文 + 来源 + 原因 + 命中优先级层” | 中 / 中 | P1 | https://github.com/gorhill/uBlock/wiki/The-logger |

### 2.2 规则测试 / 冲突检测 / 优先级排序

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| 谛听桌面端（自研，参照） | GPL-3.0 | `POST /api/v1/filter/check` 返回 `action/matchedRule/listName/reason/rewritten`；`CheckHost` 只读不计数 | 抽为共享能力：`policy-core` 暴露 `answer()`/`match_domain()` 经 JNI 成 `checkHost`；安卓新增“规则测试”页 | 低 / 低 | P0 | 本仓库 `desktop/service/internal/ipc/server_filter.go` |
| uBlock Origin（动态过滤矩阵） | GPL-3.0（未能联网核实） | 全局 / 站点 / 上下文三级 × block/noop/allow 的防火墙矩阵；动态规则优先级高于静态 | 仅借鉴“优先级可视化矩阵”思路：把谛听七级判定画成“谁压过谁”的只读矩阵 + 单域裁决路径 | 中 / 中 | P2 | https://github.com/gorhill/uBlock/wiki/Dynamic-filtering |
| Clash Meta / mihomo + FlClash | GPL-3.0（FlClash 本地已核对） | 规则顺序敏感、可增删排序；rule-provider 作为可复用规则块被规则引用；rule 编辑器带 schema 补全 | “订阅/规则块拖拽排序 + 引用”；排序结果直接作为 `policy-core` 快照构建顺序（同层 first-hit） | 中 / 中 | P1 | https://github.com/MetaCubeX/mihomo · https://github.com/chen08209/FlClash |
| sing-box（Headless Rule） | GPL-3.0 | `domain/domain_suffix/domain_keyword/domain_regex/ip_cidr/package_name/invert` + 逻辑 `type(rules)` 组合 | 规则快照 schema 的字段命名与组合范式参照；`package_name` 对齐安卓 `appScope` | 低 / 低 | P1 | https://sing-box.sagernet.org/configuration/rule-set/headless-rule/ |

### 2.3 订阅 / 规则集治理 · 版本化 · 健康检查

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| AdGuard Home（Filters） | GPL-3.0（本地已核对） | 每库 `RulesCount/LastUpdated/checksum/Enabled`；`/control/filtering/status` 汇总；刷新失败保留旧库并记录错误 | 订阅列表卡片显示“规则数 / 更新时间 / 状态灯 / 错误”；状态由现有 `importState+lastError+etag` 聚合 | 低 / 低 | P0 | https://github.com/AdguardTeam/AdGuardHome/wiki/Hosts-Blocklists |
| blocky（downloaded cache） | Apache-2.0（未能联网核实） | 条件请求 ETag/304 增量；传输失败→保留旧缓存并标 `cached`；状态机 `ok/unchanged/cached/failed` | 与桌面端一致：`subscription-core` 增 `lastStatus` 派生 + “临时失败不清空规则”；Dart 侧展示四态 | 低 / 低 | P0 | https://0xerr0r.github.io/blocky/ |
| sing-box（Rule Set 源码/二进制） | GPL-3.0 | 文本 JSON `source` → `sing-box rule-set compile` → 二进制 `.srs`；发布端编译一次、客户端 mmap 直读 | `.dtri` 增加 `format_version + checksum + behavior` 头；订阅“下载即编译/校验”，不一致拒绝加载 | 中 / 中 | P1 | https://sing-box.sagernet.org/configuration/rule-set/source-format/ |
| mihomo（rule-provider） | GPL-3.0（未能联网核实） | provider `type=http/file/inline`、`behavior=domain/ipcidr/classical`、`format=yaml/text/mrs`、`interval` 自动更新、可被多条规则引用 | 订阅模型扩展 `behavior/format/interval`；“同一规则块被多个策略复用”避免重复存储 | 中 / 中 | P2 | https://wiki.metacubex.one/en/config/rule-providers/ |
| AdGuard Hostlist Compiler | GPL-3.0（未能联网核实） | 多源 compile、`include/exclude`、去重、压缩、`!#include` 组合 | 订阅“镜像/聚合/去重”管线；为“多源合成一个本地库”提供范式 | 中 / 中 | P2 | https://github.com/AdguardTeam/HostlistCompiler |

### 2.4 多格式导入 / 自动识别 / 转换

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| AdGuard DNS 过滤语法（三形态） | 文档（产品） | Adblock 风格 / `/etc/hosts` / 纯域名三形态；未知修饰符整条忽略（防误用 EasyList） | 导入器已有三形态；补“格式探测 + 未知修饰符统计回显（unsupported）” | 低 / 低 | P1 | https://adguard-dns.io/kb/general/dns-filtering-syntax/ |
| Adblock Plus（语法/速查） | GPL-3.0（ABP 项目，未能联网核实） | `||`/`@@`/`$`/元素隐藏；基础修饰符全集，AdGuard 语法的母本 | 自定义规则编辑器“语法速查”页 + 校验；ABP 专有修饰符旁路并标注 | 低 / 低 | P1 | https://adblockplus.org/filters |
| AdAway（hosts 管理） | GPL-3.0（未能联网核实） | hosts 源在线/离线；允许/重定向/屏蔽三列表；DNS 日志“一键加入黑/白名单”；更新调度；本地 Web 服务器 | “从日志加规则/加例外”闭环；hosts 源与域名单源分型管理 | 中 / 中 | P1 | https://github.com/AdAway/AdAway |
| 谛听 `diting-rule-core`（现有） | GPL-3.0 | `line/hosts/document` 已解析 adblock/hosts/dnsmasq/cosmetic/URL/`$badfilter` | 作为转换/导出的唯一实现，新增 `format_detect` 与 `to_hosts/to_adblock`（新子模块，非新 crate） | 低 / 中 | P2 | 本仓库 `rust/diting-rule-core/src/{line,hosts,document}.rs` |

### 2.5 例外 / 白名单优先级 / 正则安全 / 规模性能

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| blocky（allowlistOnly） | Apache-2.0（未能联网核实） | 每分组“仅白名单”模式：未命中放行规则即阻断；与 schedule 门控组合（窗口外整体放行优先） | `policy-core` 快照增 `allowlist_only` 标志 + `applyAllowlistOnly`（rewrite 放行）；Dart 全局/分组开关 | 低 / 低 | P0 | https://0xerr0r.github.io/blocky/ |
| AdGuard（`important` / `denyallow` / `$to`） | 文档（产品） | `$important` 压过普通例外；`denyallow`/`to` 做“黑名单内挖洞”避免例外爆炸 | 已支持；补充“例外与 important 的优先级说明/可视化”，降低用户误配 | 低 / 低 | P1 | https://adguard.com/kb/general/ad-filtering/create-own-filters/ |
| Rust `regex`（引擎约束） | MIT/Apache-2.0（依赖库） | 线性时间、无回溯，天然抗 ReDoS；有 size limit | 运行时统一走 Rust `regex`；导入期加“规则长度/构造预算 + 编译超时 + 嵌套量词拒绝”，拒绝原因回显 | 低 / 低 | P1 | https://docs.rs/regex |
| 谛听 `diting-filter-core`（现有） | GPL-3.0 | 四层 Trie + Bloom 预筛；`uncompiled_patterns` 统计“引擎拒绝编译的规则永不命中” | 沿用并暴露 `uncompiled_patterns` 到 UI，作为“无效规则”提示；规模性能以 mmap 索引兜底 | 低 / 低 | P1 | 本仓库 `rust/diting-filter-core/src/index.rs` |

### 2.6 时间 / 场景 / preset / 应用模板

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| 谛听桌面端（分时/服务级计划） | GPL-3.0 | `BlockingSchedule` 周计划；`ServiceSchedules` 单服务周计划；注入时钟便于测试；窗口外整体放行优先于仅白名单 | 移植为纯 Rust `diting-schedule-core`（周窗口 + 时钟注入），`policy-core` 判定前先过门控 | 中 / 中 | P1 | 本仓库 `desktop/service/internal/core/rule_engine_group_policy.go` |
| AdGuard Home（Blocked services / Access） | GPL-3.0（本地已核对） | “屏蔽服务”预设（按 `services.json` 展开整组域名）；客户端访问计划 | `diting-services-core` + 内置服务目录（ID→域名组），勾选即展开为规则，不进订阅 | 低 / 中 | P1 | https://github.com/AdguardTeam/AdGuardHome |
| NextDNS（Recreation Time / Profiles） | 专有服务 | 配置档案 + 时间策略（娱乐时间）；家长控制档位 | “场景/时段档案”交互范式；仅借鉴设计 | 中 / 中 | P2 | https://nextdns.io |
| RethinkDNS（per-app 规则） | MPL-2.0（另有资料记 Apache-2.0，未核实） | 按应用自定义规则 + 事件（屏幕/计费网络）触发 | 安卓“按应用规则模板”：`appScope` 升级为可保存模板并复用 | 中 / 中 | P2 | https://github.com/celzero/rethink-app |
| Technitium DNS（临时暂停） | GPL-3.0（未能联网核实） | `TemporaryDisableBlocking` 定时暂停语义 | 桌面端 `PauseFor`（运行时态、重启恢复、上限 10 年）照搬；Dart 倒计时 UI | 低 / 低 | P1 | https://github.com/TechnitiumSoftware/DnsServer |

### 2.7 hosts 生态 / 免费列表（preset 与分层）

| 开源项目 | 许可证 | 可借鉴机制 | 对谛听的具体设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| StevenBlack/hosts | MIT（未能联网核实） | 统一 hosts + 扩展分类（fake-news/gambling/porn/social）；merge/flatten 生成变体 | “推荐订阅”按分类预设；订阅新增时可选“合并生成单库” | 低 / 低 | P2 | https://github.com/StevenBlack/hosts |
| OISD | 自定义使用条款（未核实，非标准 OSS） | 单一精选库分 small/big/nsfw 档；强调低误杀 | “精选 tier 预设 + 误杀说明”；默认仅展示，不预置强拦截档 | 低 / 低 | P2 | https://oisd.nl |
| hagezi/dns-blocklists | 待核实（未能联网核实） | 分层 Light/Normal/Pro/Pro++/Ultimate；按厂商/类别细分；多格式（domains/wildcard/ABP）变体 | “层级 + 类别 + 格式”三维 preset；按格式选择对应导入器 | 低 / 低 | P2 | https://github.com/hagezi/dns-blocklists |

### 2.8 geoip / geosite 规则集 —— 是否值得引入

| 开源项目 | 许可证 | 可借鉴机制 | 结论 / 对谛听设计 | 落地难度 Flutter/Rust | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| sing-box GeoIP / Geosite | GPL-3.0 | `geoip` / `geosite`（分类域名库，二进制 rule-set 承载） | **不建议进核心判定**：DNS 层按域名分类收益小于体积/更新成本；仅以“可选、可下载、可关闭的域名分类 preset”存在 | 高 / 高 | P2（观察） | https://sing-box.sagernet.org/configuration/route/geosite/ |
| v2fly/domain-list-community | MIT（未能联网核实） | `geosite` 分类源社区维护，定期生成 | 同上的数据来源候选；若做 preset，优先取它的分类子集而非全量 | 中 / 中 | P2（观察） | https://github.com/v2fly/domain-list-community |

### 2.9 待挖掘机制 → 最佳来源 → 落点 覆盖矩阵

| 需要的机制 | 最佳参照 | 谛听落点（现有 / 新增 crate） |
|---|---|---|
| 规则命中统计与“为什么被拦截”归因 | AdGuard Home `Result.rules[]`+`Reason`；AdGuard 规则统计 | `diting-policy-core`（现有，扩 `Decision`→payload 映射）+ `diting-rule-store-core`（现有，落计数） |
| 规则测试/模拟器、冲突检测、优先级可视化/拖拽 | 桌面 `/filter/check`；uBO 矩阵；Clash/FlClash 排序 | `diting-policy-core`/`diting-filter-core`（现有）+ 新 `checkHost` JNI；冲突分析做快照构建期附加 pass |
| 多格式导入/自动识别/转换 | AdGuard 三形态；ABP；Hostlist/FiltersCompiler | `diting-rule-core`（现有，加 `format_detect`/`convert` 子模块） |
| 订阅版本化/diff/回滚/健康检查/逐库开关 | blocky `downloaded_cache`；AdGuard Home Filters；mihomo provider | `diting-subscription-core`（现有，扩 `lastStatus`）+ 新 `diting-rule-version-core`（可选） |
| 例外/白名单优先级、仅白名单、正则安全、规模性能 | blocky `allowlistOnly`；AdGuard `important`；Rust `regex` | `diting-policy-core`/`diting-filter-core`/`diting-rule-core`（现有，加预算校验） |
| 时间/场景规则、按应用模板、blocked services 预设 | 桌面 schedule/services；AdGuard Blocked services；RethinkDNS per-app | 新 `diting-schedule-core`、`diting-services-core`；`appScope` 升级模板 |
| 响应侧别名链复检、伪应答纠正 | 桌面 `MatchResponse` / `BogusNXDomainMatcher` | 新 `diting-bogus-core` / `diting-response-core`（或并入 policy-core） |
| geoip/geosite 引入评估 | sing-box / v2fly geosite | 仅可选 preset，不进核心（见 2.8） |
| 与 Rust 内核结合的可行落点 | 全部按“并入现有 `.so` 的普通依赖” | 优先扩展 `policy-core`/`rule-core`/`subscription-core`，避免新增 `.so` |

---

## 三、新功能 / 增强清单（规则管理）

> 每条给出：**价值 / 技术方案（标明现有或新增 Rust crate）/ 风险**，并标 `优先级 · 难度`。
> 已排除仓库中已有能力（黑/白名单、AdGuard 语法、域名覆写、阻断响应与动态升级、订阅分组/镜像/定时更新、
> 批量编辑、规则搜索、请求日志 `matchedRule`、DNS 缓存 `hitCount`）。

### A. 可解释性与命中统计

**A1. 规则测试模拟器（Rule Tester）** — `P0` · 低/低 · Rust：复用 `diting-policy-core`（现有）
- 价值：输入域名+qtype，立即显示“是否拦截 / 命中规则原文 / 来源订阅 / 原因（Reason）/ 若命中 rewrite 的最终应答”，
  把“为什么被拦/没被拦”变成可自助排查；对齐桌面 `/filter/check`。
- 技术方案：在 `diting-engine` 或 `diting-policy-core` 暴露 `check_host(domain,qtype) -> {action,rule,source,reason,rewrite}`；
  仅读不计数（与 A2 正式统计分离）；Flutter 新增“规则测试”页，支持从请求日志/订阅条目跳入预填。
- 风险：必须用“当前生效快照”而非重建索引，避免测试与真实不一致；rewrite 构造仍在引擎侧以复用应答逻辑。

**A2. 规则命中统计（per-rule hit count + 订阅榜）** — `P0` · 中/中 · Rust：`diting-policy-core`（现有）+ `diting-rule-store-core`（现有）
- 价值：找出“常命中的规则 / 从不命中的规则 / 各订阅贡献的拦截量”，支撑规则瘦身与订阅取舍，呼应 AdGuard 的
  规则统计与 `top_blocked_domains`。
- 技术方案：`policy-core` 命中路径以 `rule_id` 分片原子计数（`AtomicU64` 数组，分片降低争用），定时批量写回
  SQLite（`rule-store-core` 生成语句）；`rule_id→source/list/raw` 映射放快照 payload；提供“近 7/30 天、
  采样比”查询。
- 风险：热路径原子操作与计数膨胀；需采样开关、上限与后台落库；统计口径必须与请求日志 `matchedRule` 统一。

**A3. “为什么被拦截” 归因面板** — `P1` · 中/中 · Rust：`diting-policy-core`（现有）
- 价值：请求明细从“显示一条规则字符串”升级为“规则原文 + 来源订阅 + 命中层级（important/@@/blacklist/wildcard/
  regex/rewrite）+ 原因码 + 被覆盖的候选”，显著降低误杀申诉成本。
- 技术方案：`Decision` 已带 `reason:Option<Reason>`+`rule`；JNI 补齐 `list_name` 与 `raw_text`；Dart 请求明细页
  分块展示，并提供“加白名单/加黑名单”一键动作（写回 rule-store）。
- 风险：快照需保留规则原文，内存/序列化成本上升；对超大订阅改为“按需查询原文”。

**A4. 规则冲突检测与“被遮蔽规则”提示** — `P1` · 中/中 · Rust：`diting-policy-core`（新增分析 pass）
- 价值：指出“某条黑名单其实永远被更高优先级的 `@@`/`$important` 覆盖”“同一域多条 rewrite 冲突”，帮助用户修规则。
- 技术方案：快照构建期对同后缀桶/通配候选做有限两两比较，标出被更高层截获的 rule；只读报告，不改判定。
- 风险：大库两两比较可能 O(n²)；限定在同 suffix 桶与通配候选范围内，设条数上限与耗时预算。

### B. 优先级与顺序

**B1. 订阅/规则块优先级可视化与拖拽排序** — `P1` · 中/中 · Rust：`diting-policy-core`（现有）
- 价值：让“同层 first-hit”可被用户理解与调整（订阅顺序影响命中来源），对齐 Clash/FlClash 的规则排序体验。
- 技术方案：订阅顺序作为快照构建的 tie-break（写入 payload 的顺序）；Flutter 拖拽排序 → 重发快照；保留固定
  七级语义不变，仅影响同层来源归属。
- 风险：改变“来源归属”可能与历史日志对不上；需在规则测试页显示“当前排序下的实际归属”。

**B2. 例外/白名单优先级只读矩阵** — `P2` · 低/低 · Rust：无（前端 + 文档）
- 价值：把 `$dnsrewrite > $important allow > $important block > @@ > block > wildcard/regex` 画成矩阵，
  降低用户对“为什么例外没生效”的困惑。
- 技术方案：静态说明页 + 结合 A1 的实测结果高亮路径。
- 风险：文案需与内核实现严格一致，避免文档漂移。

### C. 导入 / 格式 / 转换

**C1. 多格式自动识别** — `P1` · 低/中 · Rust：`diting-rule-core`（现有，加 `format_detect`）
- 价值：用户粘贴任意文本/URL，自动判定 hosts / ABP / AdGuard / dnsmasq / 纯域名 / Clash-yaml，减少“导错格式”。
- 技术方案：在 `document` 前加“抽样打分探测”（统计 `||`/`@@`/`$`/IP+域名/`server=`/`payload:` 特征）；
  yaml/mrs 仅识别并提示“需转换”，不直接解析。
- 风险：混合格式/注释干扰误判；提供“识别结果可手动覆盖”。

**C2. 规则导出与格式转换（hosts ↔ ABP ↔ dnsmasq）** — `P2` · 中/中 · Rust：`diting-rule-core`（新增子模块）
- 价值：把当前规则/订阅导出为其它引擎可用格式，便于分享与迁移（FiltersCompiler/HostlistCompiler 思路）。
- 技术方案：新增 `to_hosts/to_adblock/to_dnsmasq`；标注不可无损转换项（正则、`$denyallow`）。
- 风险：转换有损；须显式提示“哪些规则未导出”。

**C3. 正则安全预算（ReDoS 防护）** — `P1` · 低/低 · Rust：`diting-rule-core`（现有 `is_valid_regex` 扩展）
- 价值：防止用户/订阅塞入超长或灾难性正则拖垮导入与匹配。
- 技术方案：运行时统一 Rust `regex`（线性）；导入期加长度上限、嵌套量词/回溯构造拒绝、编译耗时预算；
  拒绝条目计入 `unsupported` 并回显。
- 风险：误伤少量合法复杂正则；提供“高级：仍要导入”白名单开关并记录。

### D. 订阅治理

**D1. 订阅健康状态（ok / 304 unchanged / cached / failed）** — `P0` · 低/低 · Rust：`diting-subscription-core`（现有）
- 价值：一眼看清每个订阅“是否成功、有没有 304、失败是否在用旧缓存”，这是当前安卓最痛的运维盲区。
- 技术方案：复用现有 `importState/httpEtag/httpLastModified/consecutiveFailureCount/importError`，
  派生 `lastStatus`；对齐桌面语义：304→只刷时间戳；传输类失败且本地有缓存→`cached` 保留旧规则；4xx/5xx 或首次→`failed`。
- 风险：需明确“cached 时规则仍是旧的”并在 UI 标注，避免误以为已更新。

**D2. 订阅版本化 / diff / 回滚** — `P1` · 中/中 · Rust：新增 `diting-rule-version-core`（或并入 `rule-store-core`）
- 价值：展示“本次更新新增/删除 N 条、规则数变化曲线”，并支持回滚到上一可用版本，防止坏订阅一夜之间放行/误杀。
- 技术方案：每次成功导入保留规则集 hash 与增量快照（可存压缩 diff）；diff 用集合差；回滚=切换到历史 `.dtri`
  与对应 DB 版本；复用 `ruleSetHash`。
- 风险：存储增长；采用“保留最近 K 版 + 手动 pin”策略与清理任务。

**D3. 逐库单独开关 + 规则数 + 分组贡献** — `P1` · 低/低 · Rust：`diting-subscription-core`（现有）
- 价值：已有 `enabled` 与 `ruleCount`，补齐“单库开关即时生效 + 规则数 + 该库当前拦截贡献”，支持“临时只留必要库”。
- 技术方案：开关 → 重发快照（`setSourceEnabled` 已有）；贡献数据复用 A2 统计按 source 聚合。
- 风险：频繁切换导致重建抖动；合并/节流重建。

**D4. 多源去重合并（合成单库）** — `P2` · 中/中 · Rust：`diting-rule-store-core`（现有）+ `diting-rule-core`（现有）
- 价值：把多个同类订阅（如多个 hosts 源）去重后合成为一个本地库，减少重复判定与存储（HostlistCompiler 思路）。
- 技术方案：导入时按去重键归并（`identity` 已有），输出“合并视图”与来源映射；原始源仍可单独刷新。
- 风险：合并后难以追溯单源；保留 source 映射与“按源回滚”。

### E. 时间 / 场景 / preset

**E1. 时间/分时拦截（Schedule）** — `P1` · 中/中 · Rust：新增 `diting-schedule-core`（纯 Rust + 时钟注入）
- 价值：如“工作时间阻断娱乐、夜间全拦”，是家长/办公场景刚需，桌面端已实现。
- 技术方案：周窗口模型 + 注入时钟；`policy-core` 判定前先过门控（窗口外整体放行，优先于仅白名单）；
  支持组/全局与服务级两档（对齐桌面 `BlockingSchedule`/`ServiceSchedules`）。
- 风险：跨日窗口/时区/夏令时；沿用桌面“注入时钟”做可重放测试。

**E2. blocked services 预设分组** — `P1` · 低/中 · Rust：新增 `diting-services-core` + 内置目录
- 价值：一键“屏蔽全部短视频/社交通讯”，无需用户自己找域名；对齐 AdGuard Blocked services。
- 技术方案：内置 `services.json`（服务 ID→域名组，可含分组），勾选即展开为规则并随包离线；与订阅独立。
- 风险：目录需持续维护；版本升级时丢弃失效服务而非报错（桌面端已如此处理）。

**E3. 按应用规则模板** — `P2` · 中/中 · Rust：`diting-rule-core`（现有 `appScope` 升级）
- 价值：把“某应用专用规则集”保存为模板复用（RethinkDNS per-app 思路），减少重复录入。
- 技术方案：`appScope` 规则支持命名模板与批量套用；快照规则携带 `package_name` 维度（对齐 sing-box）。
- 风险：应用包名变更/多用户；需容错与“未知包名”提示。

**E4. 网络场景联动（按网络/SSID 切换规则集）** — `P2` · 中/中 · Rust：`diting-schedule-core`（与网络 profile 联动）
- 价值：“公司 Wi-Fi 严格拦截、家庭放宽”这类场景自动切换，减少手动操作；呼应 sing-box 的 `wifi_ssid` 维度。
- 技术方案：网络 profile（SSID/计费/漫游，来自 Kotlin `ConnectivityManager`）映射到一个具名规则集/开关组合，
  切换时重发快照；不新增判定语义，只切换输入。
- 风险：网络抖动导致频繁切换；去抖 + 仅在稳定网络时应用。

### F. 响应侧与健壮性（桌面已有，安卓缺）

**F1. 响应侧别名链复检（CNAME 深链拦截）** — `P1` · 中/中 · Rust：新增 `diting-response-core`（或并入 policy-core）
- 价值：拦截“QNAME 合法但 CNAME 指向黑名单域”的深链绕过（CDN 换域/跳转器），是桌面已验证的有效补强。
- 技术方案：抽取应答 Answer 中 CNAME 目标与 A/AAAA 记录名（去重去点、排除 QNAME、深度上限 8），二次匹配；
  不重复计统计（一次查询只计一次）；返回原因码 `RESPONSE_CNAME_BLOCKED`。
- 风险：误伤合法 CDN 链；默认关闭、可开关并限深度（桌面默认关闭亦是此因）。

**F2. 伪应答（劫持）纠正** — `P2` · 低/中 · Rust：新增 `diting-bogus-core`
- 价值：上游返回“私网/已知劫持地址”时就地改写为 NXDOMAIN 并标记，改善日志与 EDE 归类。
- 技术方案：A/AAAA 命中 `bogus_networks`（IP/CIDR）→ 改写 NXDOMAIN；总开关优先；全部非法条目清空而非沿用旧集，
  避免界面与实际不一致。
- 风险：企业内网私网地址普遍，默认关闭（桌面端亦默认关闭）。

**F3. 临时暂停拦截 / 仅白名单模式** — `P0`/`P1` · 低/低 · Rust：`diting-policy-core`（现有）+ 前端
- 价值：临时暂停是“排障/放行一次”的高频动作；仅白名单是严格管控场景（儿童/合规）。
- 技术方案：暂停=纯运行时态（重启恢复、`PauseFor` 上限），前端倒计时；仅白名单=快照 `allowlist_only` 标志，
  未命中放行即阻断、rewrite 放行（对齐桌面 `applyAllowlistOnly`）。
- 风险：暂停被误当“永久关闭”；用显式倒计时与状态徽标提示。

### G. 内核落点与工程纪律

**G1. 统一“谁判定”的唯一实现** — `P0` · 低/低 · Rust：`diting-policy-core`/`diting-rule-core`（现有）
- 价值：避免安卓出现第二套 Dart/Kotlin 判定；测试/统计/请求日志共用同一 `Decision`。
- 技术方案：所有新增能力（A1/A3/A4/F1/F3）都返回 `policy-core::Decision`（或扩展结构），Dart 只做展示与编排；
  埋点口径一致。
- 风险：JNI 结构体扩展需同步 ABI 版本与 `RustRuleStoreCore` 的“缺库即报错”契约。

**G2. 二进制规则集版本化（`.dtri` 对齐 `.srs`/`.mrs`）** — `P2` · 中/中 · Rust：`diting-rule-core::dtri`（现有）
- 价值：订阅“发布端编译一次、客户端 mmap 直读”，降低首启解析成本，为大规模规则铺路。
- 技术方案：`.dtri` 增加 `format_version/checksum/behavior` 头；下载后校验，不匹配拒绝加载（缺索引即报错，不降级）；
  与 `ruleSetHash` 关联。
- 风险：格式演进兼容；需版本握手与迁移。

### H. 数据模型与接口草案（供实现对齐，非最终 schema）

把 A1/A2/D1 落成一致口径，避免 Dart 与 Rust 各算一套；字段名为建议，最终以 crate payload 为准。

- 命中计数表 `rule_hit_stat(rule_id, day, hits, source_tag)`：`rule_id` 与快照序号稳定绑定；`source_tag` 冗余以便订阅榜聚合；按日分区、滚动保留，采样比写入元数据。
- 订阅状态派生 `last_status ∈ {ok, unchanged, cached, failed}`：由 `importState + httpEtag/304 + consecutiveFailureCount + importError` 计算；`cached` 必须同时保证旧规则仍生效。
- 快照 payload 增补 `rules[] -> {id, source_tag, list_name, raw_text}` 与 `allowlist_only: bool`；`check_host` 返回 `{action, reason_code, rule_id, source_tag, rewrite?}`。
- `.dtri` 头：`magic | format_version | behavior(domain/ipcidr/classical) | checksum | rule_count`。

> **落地路线图（建议）**：先 P0 `A1 规则测试模拟器 → A2 规则命中统计 → D1 订阅健康状态 → F3 暂停/仅白名单`；
> 再 P1 `A3/A4 归因与冲突 → B1 排序 → E1 时间规则 → E2 服务预设 → F1 响应侧复检 → C3 正则预算`；
> 最后 P2 `C1/C2 格式识别与转换 → D2 版本回滚 → F2 伪应答 → G2 二进制版本化 → 2.8 geosite 可选 preset`。

---

## 四、许可证提示

谛听整体为 **GNU GPL-3.0**（`LICENSE` 已核对）。在此基础上按项目许可证分档：

- **GPL-3.0（与谛听同协议，代码可借鉴/合并，但衍生整体仍为 GPL-3.0，须保留版权与署名）**：
  AdGuard Home（本地 `LICENSE` 已核对）、AdGuard for Android（专有客户端条目另论，其 GPL 组件按 GPL）、
  AdGuard Filters Compiler、AdGuard Hostlist Compiler、uBlock Origin、AdAway、sing-box、Clash Meta/mihomo、
  FlClash（本地已核对；谛听 `shared/lib/ui/color.dart` 已声明部分派生自 FlClash）、Pi-hole（GPL-2.0，可并入 GPL-3.0）。
- **宽松许可（MIT / Apache-2.0 / BSD，可单向并入 GPL-3.0，须保留 NOTICE/版权声明）**：
  StevenBlack/hosts（MIT，待核实）、blocky（Apache-2.0，待核实）、Rust `regex`（MIT/Apache-2.0）、
  v2fly/domain-list-community（MIT，待核实）、Tailscale/Flutter 等（如需引用）。
- **MPL-2.0（弱 copyleft，文件级隔离）**：RethinkDNS（资料记为 MPL-2.0，另有记为 Apache-2.0，**未能联网核实**）。
  若借鉴其**代码**，须把改动文件继续以 MPL 发布并公开，建议**只借鉴设计、独立重写**以避免文件级义务扩散。
- **专有 / 商业服务（只借鉴交互与文档，不复制代码、图标、文案、规则数据）**：AdGuard DNS 服务、NextDNS、
  AdGuard 部分云能力。其公开 KB 的**规则语法**可作为规范参考，但实现须自研。
- **过滤列表数据本身另有许可**：StevenBlack(MIT)、OISD（自定义使用条款）、hagezi（待核实）等**列表数据**的
  再分发/预置条款各不相同；**内置 preset 前须逐一核对列表 LICENSE/使用条款**，只内置允许再分发的源，
  默认以“可关闭的推荐订阅（运行时拉取）”而非“随包内置”方式提供更稳妥。
- **待核实清单（落地前必须复核 LICENSE 文件）**：uBlock Origin、AdAway、StevenBlack/hosts、OISD、hagezi、
  RethinkDNS、mihomo、Pi-hole、blocky、Technitium、v2fly。本轮因 `github.com` 不可达未能逐一抓取。

---

## 五、来源清单

- AdGuard DNS 过滤规则语法：<https://adguard-dns.io/kb/general/dns-filtering-syntax/>
- AdGuard 自定义过滤规则：<https://adguard.com/kb/general/ad-filtering/create-own-filters/>
- AdGuard 跟踪过滤规则统计：<https://adguard.com/kb/general/ad-filtering/tracking-filter-statistics/>
- AdGuard Home 概览：<https://adguard-dns.io/kb/adguard-home/overview/>
- AdGuard Home 仓库 / Hosts-Blocklists：<https://github.com/AdguardTeam/AdGuardHome> · <https://github.com/AdguardTeam/AdGuardHome/wiki/Hosts-Blocklists>
- AdGuard DNS filter：<https://github.com/AdguardTeam/AdGuardSDNSFilter> · HostlistsRegistry：<https://github.com/AdguardTeam/HostlistsRegistry>
- AdGuard Filters Compiler：<https://github.com/AdguardTeam/FiltersCompiler>
- AdGuard Hostlist Compiler：<https://github.com/AdguardTeam/HostlistCompiler>
- uBlock Origin / Logger / Dynamic filtering：<https://github.com/gorhill/uBlock> · <https://github.com/gorhill/uBlock/wiki/The-logger> · <https://github.com/gorhill/uBlock/wiki/Dynamic-filtering>
- AdAway：<https://github.com/AdAway/AdAway>
- StevenBlack/hosts：<https://github.com/StevenBlack/hosts>
- OISD：<https://oisd.nl>
- hagezi/dns-blocklists：<https://github.com/hagezi/dns-blocklists>
- Adblock Plus 语法 / 速查：<https://adblockplus.org/filters> · <https://adblockplus.org/filter-cheatsheet>
- RethinkDNS：<https://github.com/celzero/rethink-app>
- sing-box 规则集：<https://sing-box.sagernet.org/configuration/rule-set/> · 源码格式：<https://sing-box.sagernet.org/configuration/rule-set/source-format/> · AdGuard 转换：<https://sing-box.sagernet.org/configuration/rule-set/adguard/> · Headless Rule：<https://sing-box.sagernet.org/configuration/rule-set/headless-rule/> · Geosite：<https://sing-box.sagernet.org/configuration/route/geosite/>
- Clash Meta / mihomo / rule-providers：<https://github.com/MetaCubeX/mihomo> · <https://wiki.metacubex.one/en/config/rule-providers/>
- FlClash：<https://github.com/chen08209/FlClash>
- Pi-hole：<https://github.com/pi-hole/pi-hole>
- blocky：<https://github.com/0xERR0R/blocky>
- Technitium DNS Server：<https://github.com/TechnitiumSoftware/DnsServer>
- v2fly/domain-list-community（geosite）：<https://github.com/v2fly/domain-list-community>
- NextDNS（专有，仅设计参考）：<https://nextdns.io>
- Rust `regex`（线性时间/大小限制）：<https://docs.rs/regex>
- 本仓库内部证据：`rust/diting-{rule,policy,filter,rule-store,subscription,hosts,cosmetic,allowlist,rewrite}-core/`、
  `desktop/service/internal/core/rule_*.go`、`desktop/service/internal/ipc/server_filter.go`、
  `LearningObjects/AdGuardHome-0.107.80/internal/{filtering,querylog,stats}/`、`LearningObjects/FlClash-0.9.3/lib/`。
