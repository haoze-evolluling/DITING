# 谛听（DITING）安卓端 · 使用体验（UX）与 Rust 内核 leverage 功能扩展调研

> 范围：`android/app`（Flutter · Riverpod · go_router · sqflite · Material3 · `diting_shared/ui`）+ `rust/diting-engine`（JNI 隧道引擎）。
> 方法：先做仓库源码勘察（以真实存在的页面/状态/内核为准，避免与已有功能重复），再用 `web_fetch` 查阅官方仓库与文档；GitHub 网页版抓取间歇失败，README/LICENSE 走 `raw.githubusercontent.com` 与官方站点抓取。
> 时间：2026-11。优先级：`P0` 立即 / `P1` 近期 / `P2` 中期 / `P3` 观察。难度：低 / 中 / 高。

---

## ① 结论摘要

1. **谛听的功能面已经很宽**：三模式（极速/普通/服务器）、可编辑仪表盘（状态/网速/内存/流量结构/站点延迟/内网 IP/Provider/解析/日志卡片）、日志仪表盘与请求明细、应用流量、诊断工具（DNS/Ping/测速/Trace）、功能中心与隐藏项、外观（HCT 种子色 4 风格/字体字号/图标/日夜）、通知统计、备份与 WebDAV 迁移、数据清理、黑匣子运行事件、订阅管理与自动更新、按 SSID 的 On-Demand、HTTP 检查（MITM/CA/出站代理/镜像模板）、快捷设置磁贴、**桌面小组件（保护状态 + 今日拦截 + 一键开关）**、Tab 切换触感、引导与权限向导。因此本报告的增量必须落在“**信息架构、健康顾问、检索、可视化、自适应、可达性**”这些**尚未补齐的体验层**，而不是再加一个并列的功能入口。
2. **最大的体验空白是“解释与引导”，不是“功能”**：安卓端已有一个 AI 日志洞察（`diting-agent-core` + `ai_insight_card.dart` + `agent_analysis_sheet.dart`），但它停留在“日志解释”层面；缺一个贯穿全局的**保护健康评分 / 顾问（Advisor）**把权限、DNS 可达性、过滤器健康、缓存命中、拦截率、异常请求组织成“下一步该做什么”。这是投入产出比最高的方向（NextDNS 的 Security/Privacy/Parental 三支柱 + AdGuard 的 Protection 分区是成熟参照）。
3. **“找得到”比“放得下”更痛**：全仓库只有一个日志浮层的搜索框，**没有全局搜索 / 命令面板**。功能中心已经有很多可隐藏卡片与二级页，随着内核能力增加，入口只会更多，搜索与命令面板是必须补的“横向能力”。
4. **Rust 内核是现成的护城河**：`diting-safebrowsing-core`、`diting-dns64-core`、`diting-ratelimit-core`、`diting-filter-core`、`diting-rewrite-core` 在桌面侧已成熟却未进安卓引擎；安卓引擎的依赖表已明确显示它们缺席（引擎仅链接 config/dns-cache/dns/dns-wire/go-compat/policy/resolver/telemetry/upstream/bootstrap/gate/connlog/proxy/cert/mitm/cosmetic/sniffer/request）。**它们都能以“普通 Rust 依赖”方式静态并入 `libditing_engine.so`，不需要新增 dlopen/C ABI**，边际包体成本低。
5. **“服务端模式”是内核 leverage 的最佳落点**：`diting-ratelimit-core`（限速/CIDR 豁免）与 `diting-filter-core`（Bloom + Decision）天然适配服务器模式的局域网 DNS 服务，既补安全又提性能；`diting-dns64-core` 则在 IPv6-only 蜂窝网（NAT64）场景决定“能不能上网”。
6. **建议新增的内核集中在“可观测 + 自动化 + 协议演进”**：规则命中计数、flow/连接聚合、时间/场景自动化调度、DoH3（`quinn` 已在引擎依赖内）、DNS 泄漏检测、DNSSEC 校验、缓存预取/持久化、订阅库健康、SafeSearch/隐私策略、服务器模式客户端分组。它们都对应一个明确的 UI 诉求，避免“为做内核而做内核”。
7. **落地纪律**：仓库规定单文件 ≤ 600 行，新内核与 UI 必须拆模块；优先并入既有 `libditing_engine.so` / `libditing_kernels.so`，避免新增 `.so` 造成重复 std 与包体膨胀；UI 侧内核走 `diting-kernels` 伞库的 C ABI / JNI，引擎侧内核走直接 Rust 依赖 + JNI 方法（参考 `nativeSetFilterHttp3` 的既有范式）。
8. **许可证是硬约束**：项目为 GPL-3.0，且 `diting_shared/ui/color.dart` 已注明部分派生自 FlClash（GPL-3.0-or-later）。RethinkDNS（Apache-2.0）、M3（Apache-2.0）可借鉴代码但须保留 NOTICE；PCAPdroid/FlClash/mihomo（GPL-3.0）一旦并入必须整体开源并署名；AdGuard/NextDNS/1.1.1.1 为**专有产品**，只能借鉴交互，**不得复制代码、图标、文案**。

---

## ② 借鉴表

> 说明：“许可证/文档”列区分 **代码许可** 与 **可参考文档**；未能抓取到 LICENSE 文件的按公开资料标注并注明“未逐一核实”。URL 为官方仓库或文档首页。

| # | 项目/来源 | 许可证/文档 | 可借鉴点 | 对谛听设计 | 难度 | 优先级 | URL |
|---|---|---|---|---|---|---|---|
| 1 | AdGuard for Android | 专有软件；公开 KB | Protection 分区式开关组（广告拦截/跟踪保护/烦扰拦截/DNS 保护/防火墙/浏览安全）+ Statistics + App management + Filtering log | 首页增设“保护域”分组：把散落的策略开关收拢成 4–6 个有状态语义的域 | 中 | P1 | https://adguard.com/kb/adguard-for-android/features/ |
| 2 | AdGuard Statistics | 专有；公开 KB | 拦截数/流量/时间维度的多层统计 | 统计页图表选型与“今日/7 日/30 日”时间轴 | 中 | P1 | https://adguard.com/kb/adguard-for-android/features/statistics/ |
| 3 | AdGuard DNS KB | 商业服务；公开 KB | DNS 过滤原理、DoH/DoT/DoQ、私有 vs 公共配置 | 上游协议说明文案与“加密 DNS”状态语义 | 低 | P2 | https://adguard-dns.io/kb/ |
| 4 | AdGuard Assistant / 低层设置 | 专有；公开 KB | 悬浮助手快速改设置；低层设置分层与“渐进披露” | 渐进式披露高级项；通知/磁贴里做轻量快捷操作 | 低 | P2 | https://adguard.com/kb/adguard-for-android/features/low-level-settings/ |
| 5 | RethinkDNS + Firewall + VPN | **Apache-2.0** | VPN/DNS/Firewall 三模式；per-app 连接监控（何时/多少/去哪）；split-tunnel；DNS 日志含端到端延迟/时间/问答 | 首页“保护域”模型 + 应用连接地图 + 延迟列；分应用策略 | 高 | P1 | https://github.com/celzero/rethink-app |
| 6 | RethinkDNS 网络监控 | Apache-2.0 | per-app “成绩单”式报告卡 | 应用流量页升级为“报告卡 + 时间线 + 目的地址” | 中 | P1 | https://github.com/celzero/rethink-app |
| 7 | RethinkDNS 防火墙规则 | Apache-2.0 | 按事件（屏幕开/关、前后台、计费网络）或商店分类阻断 | 时间/场景自动化与“按人群/场景”引导 | 中 | P2 | https://github.com/celzero/rethink-app |
| 8 | Blokada | Blokada 5 端侧开源（GPL-3.0，未逐一核实 LICENSE 文件）；6 为闭源订阅 | 极简首屏：一个主开关 + 一行状态 + 订阅入口 | 提供“极简守护态”首屏变体给小白用户 | 低 | P2 | https://blokada.org |
| 9 | NextDNS | 闭源服务；官网产品说明 | Security / Privacy / Parental 三支柱；威胁情报清单；DNSSEC；Recreation Time；analytics/logs | **健康评分/顾问的信息架构母本**；家长控制与时间规则 | 中 | P1 | https://nextdns.io/ |
| 10 | FlClash | **GPL-3.0** | Material You 动态色 + Apple 式交互；手机到桌面自适应；profile 编辑/覆盖脚本/自定义规则；连接/请求/DNS 实时视图；QS 磁贴；per-app 代理 | 图表与动效语言、profile/模式的快速切换；本项目 UI 设计系统部分派生自 FlClash | 中 | P1 | https://github.com/chen08209/FlClash |
| 11 | Clash / mihomo 内核 | GPL-3.0 | 规则路由、proxy group、延迟测试 | 规则测试器 UI 与“命中延迟”展示 | 中 | P2 | https://github.com/MetaCubeX/mihomo |
| 12 | Tailscale Android | BSD-3-Clause | 状态优先首页（连接/账户/节点一行看清）；极简登录流；exit node 选择 | 状态卡“少而准”的信息密度参照 | 低 | P2 | https://github.com/tailscale/tailscale-android |
| 13 | 1.1.1.1 / WARP | 闭源；公开文档 | 一键开关 + 极简首页；Families；DoH/DoT/Oblivious DoH | 极简模式与隐私承诺文案；Oblivious DoH 可作远期 | 低 | P3 | https://developers.cloudflare.com/1.1.1.1/ |
| 14 | PCAPdroid | GPL-3.0（F-Droid 标注，未逐一核实 LICENSE） | 连接列表可视化（应用/域名/国家 ASN）、实时流、HTTP 解密与 HAR 导出 | 请求明细可视化：应用→域名→目的地；ASN/国家归属列 | 中 | P1 | https://github.com/emanuele-f/PCAPdroid |
| 15 | Material 3 / M3 Expressive | Apache-2.0 | Adaptive design、dynamic color、组件动效与形状 | 自适应布局与取色系统升级 | 中 | P1 | https://m3.material.io/foundations/adaptive-design/overview |
| 16 | Material Color Utilities | Apache-2.0 | HCT / DynamicColor / SchemeTonalSpot 等 | 谛听已在用（`shared/lib/ui/color.dart`），补“系统壁纸取色”通道 | 低 | P2 | https://github.com/material-foundation/material-color-utilities |
| 17 | Flutter 自适应文档 | BSD-3-Clause | large screens & foldables、NavigationRail、双栏 | 平板/折叠屏断点与双栏 | 中 | P1 | https://docs.flutter.dev/ui/adaptive-responsive |
| 18 | Flutter 无障碍文档 | BSD-3-Clause | Semantics、焦点、对比度、TalkBack | 补齐语义标签与可达性 | 低 | P1 | https://docs.flutter.dev/ui/accessibility |
| 19 | Flutter 国际化文档 | BSD-3-Clause | ARB + gen-l10n、按 locale 排版 | 多语言（当前仅 en/zh） | 低 | P1 | https://docs.flutter.dev/ui/internationalization |
| 20 | Pi-hole | GPL-2.0 | 查询类型分布、Top blocked、时间热力 | 统计图表选型（环形/堆叠/热力） | 低 | P2 | https://github.com/pi-hole/pi-hole |
| 21 | nDPI | LGPL-3.0 | 协议/应用识别 | 应用识别增强（远期，注意 LGPL 动态链接义务） | 高 | P3 | https://github.com/ntop/nDPI |
| 22 | super_sliver_list / prism_ui | MIT / GPL-3.0（FlClash vendored） | 高性能大列表（滚动条远跳 O(1)） | 谛听已采用 `super_sliver_list`，日志/请求列表继续受益 | 低 | 已完成 | https://pub.dev/packages/super_sliver_list |
| 23 | Weblate（社区翻译平台） | 平台服务 | 社区化翻译协作流程 | i18n 落地与共建者运营 | 低 | P2 | https://weblate.org/ |
| 24 | DNSCrypt / DoH 客户端生态 | 多许可 | 加密 DNS 的配置与上游选择 UX | 上游选择器的“可用性/延迟/隐私”三列 | 低 | P2 | https://dnscrypt.info/ |

### ②.1 竞品定位矩阵（用于确定谛听的差异化位置）

| 维度 | AdGuard | RethinkDNS | Blokada | NextDNS | FlClash | Tailscale | 谛听现状 / 目标 |
|---|---|---|---|---|---|---|---|
| 核心心智 | 系统级广告拦截 | DNS+防火墙+VPN 三合一 | 极简一键守护 | 云端 DNS 防火墙 | 代理/规则客户端 | 私有网络 | **本地优先 DNS 加速 + 拦截**（已成立） |
| 首页形态 | Protection 六域分区 | 三模式开关 + 监控 | 大开关 + 一行状态 | 云控制台 + 三支柱 | 状态 + 实时视图 | 连接状态 + 节点 | 可编辑仪表盘（偏“信息密集”）→ 补“健康一瞥” |
| 端侧过滤 | 强（多语言规则） | 中（Bloom/清单） | 强（端侧） | 无（云端） | 规则路由 | 无 | 规则解析已具备，**端侧匹配内核待接入** |
| 监控可视化 | 统计 + 过滤日志 | per-app 报告卡 | 基础 | analytics/logs | 连接/请求/DNS 实时 | 用量 | 日志/请求/流量已有 → 补“关系视图/聚合” |
| 家长控制 | 有 | 有（分类阻断） | 付费 | 强（SafeSearch/时间） | 无 | 无 | 待补（SafeBrowsing + Rewrite 可承载） |
| 开源/许可 | 闭源 | Apache-2.0 | 5 开源 / 6 闭源 | 闭源 | GPL-3.0 | BSD-3 | **GPL-3.0 开源**（差异化优势） |
| 谛听差异化 | — | — | — | — | — | — | **Rust 内核 + 本地优先 + 桌面级隐私套件下沉安卓** |

---

## ③ 体验改进清单（每条含 价值 / 方案 / 风险）

> 分组：A 首页与保护态、B 引导与健康、C 检索与信息架构、D 可视化、E 自适应与可达性（含多语言）、F 通知与快捷操作、G 状态/动效与触觉、H 数据与隐私体验。**均已排除仓库中已存在的项**（小组件、QS 磁贴、动态种子色、Tab 触感、AI 日志洞察、按 SSID 的 On-Demand 均已有）。

### 设计原则（贯穿以下所有条目）

1. **状态优先于设置**：首页先回答“我现在被保护得怎么样”，再回答“我可以改什么”。
2. **可解释**：任何“拦截/异常/分数”都能一键看到“为什么”，拒绝玄学与恐吓式文案。
3. **渐进披露**：常用项前置，高级项折叠，低层项二次确认；但永远可被全局搜索直达。
4. **少而准**：每屏新增元素有明确职责，不为“看起来丰富”堆卡片。
5. **本地优先可证明**：凡涉及数据出网的功能，都要有可见的去向说明与开关。

### A. 首页与保护态

**A1. 保护域开关组（Protection Domains）** — `P1`/中
- 价值：把当前分散在功能中心与各二级页的策略，收拢为“广告与跟踪 / 恶意与钓鱼 / 家长控制 / DNS 加密 / 分应用 / 服务器防护”6 个语义域，首页一屏看清“哪块在守、哪块没守”。
- 方案：新增 `ProtectionDomain` 模型（`id/状态/受管子开关/健康摘要`），首页顶部做一排可展开的域卡片；点击展开为“子开关 + 一句话解释 + 关联日志过滤入口”。数据源复用现有 provider，不新增后端。
- 风险：域太多会变成“另一张设置表”；需限制每域 ≤ 4 个子项，并提供“全部默认”一键恢复。

**A2. 极简守护态首屏变体（Calm Mode）** — `P2`/低
- 价值：面向“只想开/关”的小白用户，降低首屏认知负荷（Blokada/1.1.1.1 的成功点）。
- 方案：外观里增加“布局：标准 / 极简”，极简模式仅保留一个大开关、一行状态（今日拦截数 + 已保护时长）、一个“查看详情”入口。
- 风险：与现有可编辑仪表盘并存会带来两套布局维护成本；建议以“预设”而非新代码路径实现。

**A3. 首页状态卡“健康一瞥”** — `P1`/低
- 价值：现有状态卡偏“是否运行”，缺“是否有效”。
- 方案：状态卡追加三个小徽标：`上游可达`、`过滤器已加载`、`缓存命中率`；异常时变琥珀色并可点进诊断。数据来自引擎 telemetry 与 `/diagnostics`。
- 风险：徽标语义要统一，避免“多而杂”；异常态必须可解释（点击给出原因与修复动作）。

### B. 引导与健康顾问

**B1. 保护健康评分 + 顾问（Advisor）** — `P0`/中
- 价值：把 AI 日志洞察从“解释单条日志”升级为“**诊断全局并给下一步**”，是留存与口碑的关键（NextDNS 三支柱参照）。
- 方案：新增 `health_score` 聚合器（Dart 侧先做，后续可下沉 Rust）：输入 = 权限状态、VPN 存活、上游 RTT/成功率、过滤器规则数与最后更新、缓存命中率、近 1h 拦截率、异常请求（NXDOMAIN 暴增/明文 53 出网）。输出 = 0–100 分 + 分项 + “建议动作”（如“DNS 明文泄漏，切换 DoH”“过滤器 7 天未更新”）。复用现有 `agent_analysis_sheet` 作为“追问”入口。
- 风险：评分口径必须透明（可展开“为什么扣分”），否则成为“玄学分数”；避免“恐吓式”文案（RethinkDNS 明确反对 scareware）。

**B2. 权限健康检查（持续式）** — `P1`/低
- 价值：现有权限向导只在引导期执行一次；系统升级/电池优化/厂商清理会悄悄破坏保护。
- 方案：顾问定时（或前台每次启动）复核：VPN 授权、通知权限、电池白名单、始终在线 VPN、精确网络状态；失败即首页横幅 + 一键修复深链。
- 风险：Android 厂商差异大，需按 OEM 做深链兜底与“无法自动修复则给图文步骤”。

**B3. 分场景/分人群推荐配置** — `P1`/中
- 价值：首启动“选择你的场景”比“选模式”更能命中需求（游戏加速 / 家长守护 / 省电常驻 / 极客透明 / 隐私优先）。
- 方案：在现有 `mode_onboarding` 后追加一屏“场景选择”，每场景映射一组域开关 + 参数预设 + 一句“之后可改”。与 A1 共用模型。
- 风险：预设过多导致选择困难；限制 4–5 个场景并允许“跳过（用默认）”。

**B4. 空/错/加载态的“教学式空状态”** — `P2`/低
- 价值：空数据（无日志/无请求/无订阅）是新手最容易流失的地方。
- 方案：定义 `EmptyState` 组件规范：插画 + 一句“为什么这里是空的” + 一个主行动按钮（如“去开启日志”“导入订阅”）；错误态给“重试 / 看诊断 / 复制错误码”。
- 风险：插画与文案需 i18n，否则多语言下布局易溢出。

### C. 检索与信息架构

**C1. 全局搜索 / 命令面板** — `P0`/中
- 价值：功能面变宽后，“找不到入口”是最大摩擦；命令面板还能承载“跳转 + 执行动作”（如“暂停 15 分钟”“切换到普通模式”）。
- 方案：顶栏搜索入口 → `CommandPalette`（Flutter `SearchAnchor`/自绘）：索引 `功能中心项 + 设置项 + 页面路由 + 应用名 + 域名历史`；结果分组“页面 / 设置 / 动作 / 域名”。动作直接调用既有 provider 方法。
- 风险：索引构建在主 isolate 可能卡顿；须异步构建 + 防抖；域名历史检索要限流并尊重隐私开关。

**C2. 渐进式披露（Advanced gating）** — `P2`/低
- 价值：高级项（低层设置、脚本、镜像模板）直接暴露会吓退普通用户。
- 方案：设置页分“常用 / 高级（默认折叠）/ 低层（二次确认）”三级；用 `collapsible_section` 已经具备的组件承载。
- 风险：隐藏过深会让极客找不到；提供全局搜索直达（与 C1 联动）。

**C3. Profile / 模式快速切换** — `P1`/低
- 价值：极速/普通/服务器切换与“订阅配置切换”是高频动作。
- 方案：AppBar 常驻模式切换器（长按看差异），磁贴长按/小组件点击进入“模式轮盘”；切换前给出“本次切换会重置缓存/重连”的轻提示。
- 风险：切换涉及 VPN 重连，需处理“切换中”禁用态与失败回滚。

### D. 可视化

**D1. 统计图表选型升级** — `P1`/中
- 价值：现有 `line_chart.dart` 以折线为主；拦截/流量/请求需要更贴切图形。
- 方案：确立图表语言：拦截占比用环形、流量结构用堆叠面积、查询类型（A/AAAA/HTTPS/其他）用横向条形、活跃时段用**小时热力条**、Top 域名用带 sparkline 的排行。统一到 `diting_shared/ui` 的图表 token。
- 风险：自绘图表性能与深色主题对比度；大数据量需降采样（引擎侧 flow 聚合可减轻）。

**D2. 请求明细“应用→域名→目的地”可视化** — `P1`/中
- 价值：PCAPdroid/RethinkDNS 式的“谁在连哪”是最有说服力的隐私叙事。
- 方案：在 `requests_*` 之上加可选“关系视图”（按应用聚合的桑基/分组列表）与“目的地列（国家/ASN，来自离线库或引擎 ipcache）”。
- 风险：ASN/国家库增大包体；建议按需下载或复用现有 `diting-ip-quality-core`。

**D3. 过滤日志“一键解释”** — `P2`/低
- 价值：用户看到“被拦截”最想知道“为什么拦、谁拦的、要不要放行”。
- 方案：日志行长按 → “解释这条”：命中规则/列表/域、是否可放行、加入白名单动作；底层依赖“规则命中计数”内核（见 ④-新增 1）。
- 风险：解释依赖命中元数据，若无计数内核则只能给“规则来源”级解释。

### E. 自适应与可达性

**E1. 平板/折叠屏自适应** — `P1`/中
- 价值：当前无 `LayoutBuilder` 断点体系，大屏体验割裂。
- 方案：引入断点（compact <600 / medium 600–840 / expanded ≥840）；宽屏用 `NavigationRail` + 双栏（列表 + 详情），折叠屏适配 `MediaQuery` 折叠姿态。
- 风险：需重排路由与 `app_shell`，回归面较大；建议按“首页/日志/设置”三处先做。

**E2. 无障碍（a11y）补齐** — `P1`/低
- 价值：仓库内 `Semantics(`/显式语义极少，TalkBack 用户基本不可用；也是合规与口碑项。
- 方案：为交互控件补 `Semantics(label/hint/button)`、保证点击目标 ≥48dp、支持系统字体放大（当前有字号设置，需验证极端值不溢出）、校验前景/背景对比度、支持“减少动态效果”。
- 风险：语义粒度不当会造成重复朗读；需 TalkBack 实测。

**E3. 系统壁纸动态取色（Material You）** — `P2`/低
- 价值：已有 HCT 种子色（4 风格），但缺“跟随系统壁纸”这一最受 Android 用户欢迎的选项。
- 方案：Android 12+ 读取 `system_accent1_*` / 通过 platform channel 或 `dynamic_color` 方案取系统色作为第五种 ColorStyle；桌面端不受影响。
- 风险：跨端一致性（桌面无壁纸色）；需提供“关闭”开关。

**E4. 多语言 i18n** — `P1`/低
- 价值：当前仅 `app_en.arb` / `app_zh.arb`，限制国际用户与共建者。
- 方案：抽离字符串、接入 Weblate；先补 ja/ko/es/pt-BR/ru/zh-TW 等；CI 校验 ARB 键对齐；注意 RTL 布局。
- 风险：翻译质量与布局溢出；需截图回归与伪本地化（pseudo-locale）测试。

### F. 通知与快捷操作

**F1. 通知信息再设计** — `P2`/中
- 价值：现有通知偏“状态”，可升级为“可行动”。
- 方案：常驻通知分“保护中（含今日拦截数）/ 已暂停（含剩余时间 + 恢复按钮）/ 异常（含修复深链）”；支持静默通道与“每日摘要”合并；通知动作映射到既有 provider。
- 风险：Android 13+ 通知权限与渠道治理；过度通知会被关闭权限。

**F2. 临时暂停（5/15/30 分钟 / 到下次解锁）** — `P2`/低
- 价值：桌面端已有“临时暂停”心智，安卓缺失；“某网站打不开先暂停 5 分钟”是高频诉求。
- 方案：首页开关长按 → 暂停菜单；暂停期间状态卡显示倒计时与“立即恢复”；由引擎侧定时器/前台服务保证准时恢复（见 ④-新增 3）。
- 风险：暂停期若被系统杀进程，恢复可能延迟；需前台服务 + 启动补算。

**F3. 小组件与磁贴的信息升级** — `P3`/低
- 价值：小组件/磁贴已存在，可承载更多“一瞥信息”。
- 方案：小组件增加“今日拦截 + 保护时长 + 健康点”三选二可配置；磁贴长按快捷进“模式轮盘”。
- 风险：RemoteViews 能力有限，复杂交互需 Activity 承接。

### G. 状态、动效与触觉

**G1. 动效 token 与“减少动态效果”** — `P2`/低
- 价值：当前动效零散、时长与缓动不统一，观感“不够贵”且不可控。
- 方案：在 `shared/lib/ui/effect.dart` 建立 motion token（时长 150/250/400ms，缓动标准/强调/减速）；读取系统“移除动画”无障碍开关，低端机自动降级为淡入淡出。
- 风险：过度动画影响帧率与眩晕；默认克制，并提供全局开关。

**G2. 触觉反馈体系** — `P2`/低
- 价值：现在只有 Tab 切换的 `selectionClick`；开关、拦截提示、错误可用触觉强化“确认感”。
- 方案：定义三级（light/medium/heavy）：切换保护开关用 medium、拦截提示用 light、错误用 heavy；跟随系统触觉设置，可整体关闭。
- 风险：部分 ROM 触觉弱；关键信息不得仅靠触觉传达（a11y 兼容）。

**G3. 骨架屏与乐观更新** — `P1`/低
- 价值：首屏与统计加载时的白屏是观感硬伤；开关操作的“等待感”伤体验。
- 方案：列表/卡片统一 skeleton（复用 `loading.dart`）；开关类操作乐观更新 + 失败回滚 toast，并在状态卡给出“同步中”轻提示。
- 风险：乐观更新与真实状态不一致会“闪回”；需明确回滚动画与错误提示。

**G4. 密度模式（紧凑 / 舒适）** — `P2`/低
- 价值：日志/请求列表信息密集，用户对行高与信息量偏好差异大。
- 方案：外观增加密度选项，影响列表行高、内边距与次级信息显隐（token 化）。
- 风险：布局回归面广；需与字号设置叠加做组合测试。

### H. 数据与隐私体验

**H1. 隐私仪表盘（Tracker Insights）** — `P2`/中
- 价值：NextDNS 的 Tracker Insights 是最有说服力的隐私叙事；谛听有请求明细但缺“谁在追踪我”的聚合。
- 方案：基于 flow 聚合（④-N2）与域名分类，统计第三方追踪器数量、占比、趋势；作为可选卡片加入首页或“隐私”页。
- 风险：分类准确性与误标；措辞须“仅供参考”，并允许纠正/忽略。

**H2. 日志留存与隐私影响说明** — `P2`/低
- 价值：已有 `log_retention` 配置，但用户不理解“留得越久 = 隐私代价越高”。
- 方案：每个留存档位旁标注“隐私影响 / 可追溯性”，并提供“无日志模式”快捷开关；诊断/黑匣子模式单列并说明例外。
- 风险：与故障排查（运行事件黑匣子）存在张力；需明确“诊断模式除外”的边界。

**H3. 导出与分享（含脱敏）** — `P2`/低
- 价值：用户/共建者需要把请求、统计、错误发给维护者或社区。
- 方案：请求明细导出 HAR/CSV、统计卡片生成可分享图；导出前默认脱敏（域名可打码、IP 可截断），并二次确认。
- 风险：隐私泄露是硬风险；默认脱敏 + 可预览 + 明确告知。

**H4. 数据流向引导页** — `P3`/低
- 价值：本地优先产品需要“数据不出设备”的可视化证明。
- 方案：首次进入“服务器模式/日志”时给一页数据流向图（设备 → 引擎 → 上游；哪些本地处理、哪些出网），可折叠为“了解更多”。
- 风险：增加引导长度；须可跳过并可从关于页复看。

---

## ④ Rust 内核 leverage 清单

### 4.1 现状与接入原则

- **引擎侧（`rust/diting-engine`）**：内核以**普通 Rust 依赖**静态并入同一个 `libditing_engine.so`（`Cargo.toml` 注释明确“linked directly instead of being dlopen'd through a C ABI: one `libditing_engine.so`, no payload codec, no runtime handle table”）。对 Flutter 的边界是 **JNI**（如 `Java_com_haoze_diting_engine_Engine_nativeSetFilterHttp3`）。**新引擎内核沿用此范式最省成本**。
- **UI 侧内核（`rust/diting-kernels`）**：伞形 cdylib，一个 `libditing_kernels.so` 链接 16 个 UI 侧内核，保留各自 C ABI（Dart `lookupFunction`）与 `Java_...` JNI 入口。`diting-rule-core`（含 `jni_bridge.rs`/`search_ffi.rs`/`snapshot.rs`）与 `diting-rule-store-core` 已在此伞库内——**规则解析/编译/搜索在安卓已可用**，这是接入 filter/rewrite 的良好前提。
- **当前引擎已链接**：config、dns-cache、dns、dns-wire、go-compat、policy、resolver、telemetry、upstream、bootstrap、gate、connlog、proxy、cert、mitm、cosmetic、sniffer、request。
- **桌面在用、安卓引擎未链接**：`diting-safebrowsing-core`、`diting-dns64-core`、`diting-ratelimit-core`、`diting-filter-core`、`diting-rewrite-core`。它们都已有 `ffi.rs`/`payload.rs`（C ABI + JSON/裸字节编解码），**并入引擎时可直接复用其 `Engine` 结构，不必走 C ABI**。
- **纪律**：单文件 ≤ 600 行；新增 `.rs` 模块拆分为 `mod.rs + submodule`；不新增独立 `.so`（避免重复 std 与包体膨胀）。

### 4.1.1 三种接入形态对比（选型依据）

| 形态 | 适用内核 | 边界 | 优点 | 代价 |
|---|---|---|---|---|
| 引擎侧 · 直接 Rust 依赖 | dns64 / ratelimit / filter / rewrite / safebrowsing / flow / 调度 | JNI 方法（`Engine.nativeXxx`） | 同进程、零序列化、可共享 `rustls/quinn/tokio` | 与引擎同生共死，需随引擎重建 |
| UI 侧 · `diting-kernels` 伞库 | 命中计数、订阅健康、统计/搜索类 | C ABI（Dart `lookupFunction`）+ JNI | 与 UI 生命周期贴合，独立演进 | 多一层 payload 编解码 |
| 独立 cdylib（不推荐） | — | dlopen | 隔离 | 重复 std、包体膨胀、句柄表维护 |

> 选型原则：**决策类/数据面内核走引擎侧直接依赖；纯统计与展示类走 UI 侧伞库**；不新增独立 `.so`。

**引擎侧新增内核的 JNI 范式（示意，沿用 `nativeSetFilterHttp3` 风格）：**

```rust
// rust/diting-engine/src/jni/mod.rs（新增方法，保持与既有命名一致）
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetSafeBrowsing(
    env: JNIEnv, _this: JObject, config_json: JString,
) -> jint {
    // 1) 解析 JSON → Engine::configure(...)
    // 2) 失败返回非 0 并在 logs 记录可读原因
    // 3) 查询路径全程异步，不阻塞解析主循环
    0
}
```

```dart
// lib/data/native/engine_bridge.dart（Flutter 侧只做薄封装）
int setSafeBrowsing(Map<String, Object?> cfg) =>
    _engine.nativeSetSafeBrowsing(jsonEncode(cfg));
```

### 4.2 现有可接入内核（按收益排序）

**L1. `diting-safebrowsing-core`（浏览安全/家长控制哈希前缀）** — `P1`/中
- 收益：端侧信誉查询（Google Safe Browsing / 家长控制哈希前缀），把安卓从“广告拦截”升级为“恶意与钓鱼防护 + 家长控制”，补齐桌面隐私套件的核心能力；`CacheLookup/HashCache` 已实现本地前缀缓存与 TTL，隐私上只上传 4 字节前缀。
- 做法：作为 `diting-engine` 依赖；在 resolver 收到应答后（或独立 `upstream.rs` 旁路）对 `plan(service, host, now_ms)` 命中的域名发起异步前缀查询，`apply(...)` 回写判定；结果写入 `telemetry` 供 UI 展示。
- FFI/JNI 设想：`Engine.nativeSafeBrowsingConfigure(json)`、`Engine.nativeSafeBrowsingSnapshot() -> json`（命中/缓存条目/最近判定）；查询复用引擎既有 hyper/rustls 上游通道。
- 成本/风险：需配置服务端 URL、隐私开关与“失败降级为放行”；查询延迟必须异步，不能阻塞主解析路径。

**L2. `diting-ratelimit-core`（令牌桶 + CIDR 豁免）** — `P1`/低-中
- 收益：**服务器模式**的局域网 DNS 服务与 DoH 端点最直接的防护（防滥用/放大攻击），并为“客户端分组”提供按 IP 维度限速基础；`allow(address, now_ns, max_buckets)` 语义清晰。
- 做法：并入 `standalone.rs` 的 UDP/TCP/DoH 入口，按 `SrcAddr` 维度限速；`cleanup_idle` 周期清理。
- FFI 设想：`Engine.nativeSetRateLimit(json{enabled,bucket,refill,exemptCidrs})`、`nativeRateLimitInfo() -> json`。
- 成本/风险：低；注意 IPv4/IPv6 双栈的一致性与豁免网段（局域网段默认豁免）。

**L3. `diting-dns64-core`（NAT64/DNS64 前缀合成）** — `P2`/中
- 收益：IPv6-only 蜂窝网（部分运营商）下，纯 A 记录站点可用性由“是否实现 DNS64”决定；`map/synthesize/excluded/has_valid_aaaa` 已完整，含 well-known prefix 与自定义前缀。
- 做法：在 resolver 应答阶段对“仅有 A、无 AAAA”做合成；前缀来自配置；排除私有地址段。
- FFI 设想：`Engine.nativeDns64Configure(json{enabled,prefixes})`、`nativeDns64Snapshot()`。
- 成本/风险：中；错误前缀会导致不可达，需“自动探测 + 手动覆盖 + 一键关闭”。

**L4. `diting-filter-core`（Bloom + Decision 本地匹配）** — `P2`/中-高
- 收益：端侧 O(1) 否定判定 + 精确决策（allow/deny/rewrite），减少对“快照全量匹配”和大内存索引的依赖；`DomainBloomFilter::might_contain_domain_or_parent` 天然支持后缀匹配。
- 做法：把 `rule-core` 已编译的规则快照喂给 `FilterIndex::build`，引擎在解析前先 Bloom 否定、命中再精确判定；与 `diting-rule-store-core` 的语句计划对接。
- FFI 设想：`Engine.nativeLoadFilterIndex(bytes)`（复用 `encode/decode` payload）、`nativeFilterDecision(domain,qtype) -> json`。
- 成本/风险：中-高；需保证 Bloom 参数（`optimal_params`）与规则量匹配、误判率可接受；规则热更新需原子替换。

**L5. `diting-rewrite-core`（DNS 重写/PTR）** — `P2`/低-中
- 收益：与桌面“重写”能力对齐（自定义 A/AAAA/CNAME、反向解析），也是 **SafeSearch 强制**（把 `*.google.com` 重写指向 `forcesafesearch`）与“家长控制”的落地手段。
- 做法：在解析前 `lookup(domain, qtype)`，命中即返回 `RewriteAnswer`；PTR 用 `lookup_ptr`。
- FFI 设想：`Engine.nativeRewriteSet(json rules)`、`nativeRewriteLookup(domain,qtype) -> json`。
- 成本/风险：低-中；重写规则冲突需明确优先级与“停用/测试”。

### 4.3 建议新增内核（对应明确 UI 诉求）

**N1. 规则命中计数（Rule Hit Counters）** — `P1`/中
- UI 诉求：日志“一键解释”、Top 拦截排行、顾问评分输入（D3/B1）。
- 接口设想：`record(rule_id: u32, list_id: u16, ts_ms)`；分片 `AtomicU32` + 周期 flush 到 sqlite；`snapshot(window) -> [(rule_id,count)]`。放 `diting-kernels`（UI 侧）以贴近统计页，或引擎侧随解析路径计数。
- 收益：可解释性从“规则来源”升到“具体规则 + 命中次数”；性能上原子计数开销可忽略。
- 风险：内存有界（Top-K 或哈希分片）；高频写库需批量。

**N2. flow / 连接聚合（Flow Aggregator）** — `P1`/中
- UI 诉求：应用报告卡、延迟分位、异常检测（D2/B1）；现有 `connlog` 只做去重，缺滚动聚合。
- 接口设想：`aggregate(flowEvent)`（uid/domain/bytes/rtt/err），维护滑动窗口的 `p50/p95`、conn 数、错误率；`snapshot(window) -> json`。
- 收益：图表降采样在 Rust 完成，Flutter 侧只拿聚合结果，降低主 isolate 压力。
- 风险：窗口内存与精度权衡；需按 uid/domain 设上限。

**N3. 自动化调度（Automation Scheduler）** — `P2`/中
- UI 诉求：**时间计划**（按时间段启停）与**临时暂停**的可靠执行（F2）；桌面已有时间计划，安卓缺失。
- 接口设想：`scheduler_set(json{plans:[{cronOrWindow, action}]})`、`tick(now_ms) -> action`；由前台服务驱动 `tick`，进程被杀后下次启动补算“当前应处状态”。
- 收益：把“规则”从静态配置变为“随时间/场景生效”，且不依赖 Dart 定时器存活。
- 风险：与时区/DST、系统休眠的边界；需要“下次生效时间”可视化。

**N4. DoH3（HTTP/3 over QUIC）** — `P2`/中
- UI 诉求：更低延迟、抗丢包的上游；`quinn 0.11` **已在引擎依赖内**，`doq.rs` 已证明 QUIC 通道可用。
- 接口设想：在 `doh.rs` 增加 h3 分支（ALPN `h3`），复用 `quinn`；`nativeSetUpstreamProtocol("doh3")`。
- 收益：弱网/移动网络下比 DoH(h2)/DoT 更快；与既有 DoQ 共享 rustls 配置。
- 风险：部分上游不支持 h3 需回退；实现与测试成本中等。

**N5. ECH（Encrypted Client Hello）** — `P3`/高
- UI 诉求：抗审查、防 SNI 泄露（RethinkDNS 明确把 ECH 视作开放互联网关键）。
- 接口设想：依赖 rustls 的 ECH 能力（当前仍在演进），读取 ECHConfigList（HTTPS RR）；`nativeSetEch(enabled)`。
- 收益：与 DoH/DoT 组合显著提升抗干扰；但生态与库支持尚不成熟。
- 风险：高；rustls ECH 支持有限，先做“探测 + 能力展示”，实现放观察期。

**N6. DNS 泄漏检测（Leak Detector）** — `P1`/低-中
- UI 诉求：顾问评分与“信任”叙事（B1）。
- 接口设想：`probe() -> json{plain53_egress, systemResolver, canaryResolved}`；用一组 canary 域名 + 检测 53 端口出网/系统解析器是否绕过隧道。
- 收益：把“是否真的加密”从口号变成可验证状态；低实现成本、高用户信任。
- 风险：不同 ROM 的探测噪声；结论需“建议性”而非绝对断言。

**N7. DNSSEC 验证** — `P3`/高
- UI 诉求：“DNSSEC 已校验”徽标（NextDNS 有此能力）。
- 接口设想：先做**低成本版**——读取上游 `AD` 位并展示“上游声称已校验”；再做**完整版**——`dns-wire` 扩展 RRSIG/DS，内置根信任锚，链式校验。
- 收益：完整性保证；但完整校验实现复杂、易误判（大量域名未签名）。
- 风险：高；建议先 AD 位展示，完整验证单独立项。

**N8. 缓存预取 / 持久化（Prefetch & Warm）** — `P2`/低-中
- UI 诉求：首屏更快、切换网络后不“冷启动”。
- 接口设想：基于历史热门域名在“网络切换/解锁”时预取；`dns-cache-core` + `cache.rs` 增加磁盘持久化与预热名单；`nativePrefetch(domains)`。
- 收益：直接改善“站点延迟”与“解析卡片”观感；复用现有缓存内核。
- 风险：预取过度会增加流量与隐私暴露；需白名单与开关。

**N9. 订阅库健康（Subscription Health）** — `P1`/低
- UI 诉求：桌面“过滤订阅库健康”在安卓缺失；用户需要知道“规则是否更新、是否失效”。
- 接口设想：`diting-subscription-core` 扩展 `validate(list) -> {ruleCount, parseErrors, lastModified, stale}`；与 `rule-store-core` 的导入校验复用。
- 收益：顾问可给出“订阅 7 天未更新/解析失败 3 条”的可行动建议。
- 风险：低；注意大列表解析的性能（异步 + 进度）。

**N10. SafeSearch / 隐私策略内核（Privacy Policy）** — `P2`/中
- UI 诉求：桌面隐私套件里的 SafeSearch 强制、记录类型阻断、重绑定防护、hosts 防护、ECS 策略，安卓缺位。
- 接口设想：轻量内核（或扩展 `policy-core`）：`decide(domain, qtype, clientIp) -> {forceSafeSearch, blockType, rebindGuard, ecsPolicy}`；重写用 L5，阻断用 L4。
- 收益：以最小新增代码补齐“隐私套件”心智，形成与 AdGuard/NextDNS 对标的差异化。
- 风险：策略组合复杂，需清晰文档与“一键回到推荐”。

**N11. 服务器模式客户端分组（Client Grouping）** — `P3`/中
- UI 诉求：桌面独有“客户端分组”，服务器模式下按 IP/设备应用不同策略。
- 接口设想：`groupFor(clientIp) -> groupId`，策略解析时携带 group；配 `ratelimit`（L2）的 CIDR 维度。
- 收益：把“服务器模式”从“能用”提升到“可管理”（家庭/小型办公）。
- 风险：分组配置 UI 复杂；先做“按 IP 段→策略模板”。

### 4.4 性能 / 内存 / 包体约束

- **包体**：优先并入 `libditing_engine.so` 或 `libditing_kernels.so`；新增内核尽量复用现有 `rustls`/`hyper`/`quinn`/`smoltcp`，不引入第二套 TLS/QUIC 栈。SafeBrowsing/DNS64/RateLimit/Filter/Rewrite 均无重依赖（`sha2`/`psl`/`serde_json` 已可复用）。
- **内存**：命中计数用有界分片 + Top-K；flow 聚合按 uid/domain 设上限；Bloom 参数由 `optimal_params` 按规则量计算，避免误判率与内存失控。
- **线程/延迟**：SafeBrowsing 前缀查询、订阅校验必须异步（`tokio` 已在引擎），不得阻塞 DNS 主路径；缓存预取限速。
- **代码组织**：每个新内核单文件 ≤ 600 行，按 `mod.rs + 子模块 + tests.rs` 拆分；新增 JNI 方法集中在引擎 `jni` 模块，命名沿用 `nativeXxx`。
- **可观测**：新内核统一上报 telemetry（命中数、缓存条目、拒绝数），供 B1 顾问消费，避免“沉默的后台逻辑”。

### 4.5 分阶段落地路线图

- **阶段一（0–4 周，P0）**：C1 全局搜索骨架、B1 健康评分 v1（先 Dart 聚合）、L2 ratelimit 接入服务器模式、N6 DNS 泄漏探测。目标：做到“**找得到 + 可信**”，无需大改架构。
- **阶段二（4–10 周，P1）**：A1 保护域模型、B2 权限健康检查、L1 SafeBrowsing、N1 规则命中计数、D3 日志一键解释、E2 无障碍、E4 多语言起步。目标：形成“**可解释 + 可达成**”闭环。
- **阶段三（10–18 周，P2）**：E1 平板适配、D1/D2 可视化、L4 filter、L5 rewrite、N2 flow 聚合、N9 订阅健康、F2 暂停 + N3 调度。目标：补齐“桌面独有能力下沉”。
- **阶段四（观察，P3）**：N4 DoH3、N5 ECH、N7 完整 DNSSEC、N10 隐私策略全量、N11 客户端分组。目标：协议演进与高级玩法，按上游库成熟度推进。

### 4.6 度量指标（KPI）

- **体验**：首屏可交互时间、搜索成功率、空状态→下一步转化率、a11y 扫描违规数、崩溃/ANR 率。
- **保护**：健康分分布、权限异常发现率、DNS 泄漏检出率、拦截率、规则命中解释覆盖率。
- **性能**：引擎常驻内存、**包体增量（目标 < 2MB / 新内核）**、DNS p95 延迟、缓存命中率。
- **留存**：新手 3 日留存、顾问建议采纳率、订阅健康告警处理率。

---

## ⑤ 许可证提示

- **本项目许可**：DITING 为 **GPL-3.0**（本地优先、开源）。任何并入的代码最终受 GPL-3.0 约束；分发须提供对应源码。
- **既有派生关系**：`shared/lib/ui/color.dart` 头部已注明“Portions derived from FlClash（GPL-3.0-or-later）”，与项目许可兼容；后续沿用该设计系统时保留声明。
- **可借鉴的宽松许可（Apache-2.0）**：RethinkDNS（Apache-2.0）、Material Color Utilities / M3（Apache-2.0）。可参考实现与接口，但若**复制代码**须保留版权与 NOTICE，且不得暗示背书；与 GPL-3.0 单向兼容（Apache-2.0 代码可进 GPL 项目）。
- **强 copyleft（GPL-3.0 / GPL-2.0 / LGPL-3.0）**：FlClash、PCAPdroid、mihomo（GPL-3.0）、Pi-hole（GPL-2.0）、nDPI（LGPL-3.0）。**借鉴交互不受限，但复制代码/资源即触发开源义务**；nDPI 若动态链接需满足 LGPL 的反向工程与替换条款；LGPL/GPL 混用须整体合规。
- **专有产品（只借鉴交互，不复制资产）**：AdGuard for Android、AdGuard DNS、NextDNS、1.1.1.1/WARP、Blokada 6 均为**闭源商业产品**；其 UI 布局、图标、插画、文案、配色**不得直接复制**，只能提炼抽象交互模式并自行实现。
- **文档版权**：AdGuard KB、NextDNS、Cloudflare 文档受各自版权保护；引用请改写并注明来源链接，勿整段翻译/搬运。
- **第三方数据/服务条款**：Google Safe Browsing API（若使用官方前缀服务）受其 API 使用条款约束，需处理配额、隐私声明与“仅前缀、不传完整 URL”的设计；家长控制清单来源需核实再分发许可。
- **商标**：WireGuard®、AdGuard®、Tailscale® 等为注册商标，不得在谛听内以暗示官方关联的方式使用。
- **署名与共建**：引入社区翻译（Weblate）与外部贡献者时，保留贡献者名单（项目已有 `docs/development/recognition-members.md` 机制）。

---

## 附录：调研方法与“未能联网核实”记录

- **仓库勘察（已实测）**：`rust/diting-engine/Cargo.toml` 依赖表 → 确认引擎已链接/未链接内核清单；`rust/diting-kernels/src/lib.rs` → 确认 16 个 UI 侧内核伞库（含 `rule-core`/`rule-store-core`）；`rust/diting-{safebrowsing,dns64,ratelimit,filter,rewrite}-core/src/*.rs` → 确认 `pub fn` 接口与 `ffi.rs`/`payload.rs` 存在。
- **安卓端现状（已实测）**：`android/app/lib/pages/**` 与 `state/**` → 页面与 provider 清单；`AndroidManifest.xml` → 已有 `DitingWidgetProvider`（桌面小组件）、`DitingTileService`（QS 磁贴）、`DnsModeBootReceiver`；`shared/lib/ui/color.dart` → HCT 种子色 4 风格；`shared/lib/l10n/` → 仅 `app_en.arb`、`app_zh.arb`；全库无全局搜索（仅 `floating_log_panel.dart` 内部搜索）；无健康评分/顾问（仅 `db_health_providers.dart` 的写库健康）；存在按 SSID 的 On-Demand 与订阅自动更新调度，但**无时间计划/临时暂停**。
- **联网核实成功**：AdGuard for Android / AdGuard DNS / AdGuard KB（features、statistics、low-level）、RethinkDNS README（Apache-2.0 徽标）、FlClash README（GPL-3.0）、PCAPdroid README、Tailscale Android README、NextDNS 官网、Cloudflare 1.1.1.1 文档、M3 adaptive design、Flutter adaptive/UI 文档。
- **未能完整核实**：`github.com` 网页版与部分 `raw` 的 `LICENSE` 文件抓取间歇失败（Blokada、PCAPdroid、RethinkDNS、FlClash 的 LICENSE 正文未逐字获取）。表中许可标注基于 README/徽标与公开资料（F-Droid/项目页），**标注为“未逐一核实”者请在落地前二次确认**。如后续可稳定联网，建议补抓各仓库 `LICENSE` 与 `NOTICE` 归档。
