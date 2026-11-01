# 谛听桌面端 Flutter UI 说明与迁移约束

> 当前状态：**入口/主题、外壳与导航、首页仪表盘、`logs` 整支（24 小时汇总 + 三列排行 + 实时查询流 + 查询历史检索 + 留存策略）、`hub` 的上游解析子页（调度模式 + 上游节点 + Bootstrap + 条件分流 + 独立回退链）、解析缓存子页（引擎总控 + 遥测 + 热点排行 + TTL 策略 + 排除规则 + 落盘持久化 + 缓存明细表）、自定义重写子页（引擎开关 + 默认 TTL + 规则检索 + 快捷目标/自定义记录编辑器 + 本地权威区 zone 文件）、DNS64 子页（合成开关 + RFC 6052 前缀列表 + 内置保护说明）、防护组的订阅子页（拦截总览 + 规则库增删改查 + 健康度 + 全部更新）、自定义规则子页（语法速查 + 整表编辑与热重载）、拦截方式子页（总开关 + 三种应答模式 + 阻断地址与更新周期 + 临时暂停 + 高级拦截）、时间计划子页（分时开关 + 窗口编辑 + 生效状态）、应用拦截子页（内置目录 + 检索/分组 + 整组拦截 + 逐服务周计划）、安全隐私子页（协议加固 + ECS + 重绑定/hosts + 强制安全搜索 + 声誉查询/家长控制）与加密 DNS 服务子页（DoT/DoH/DoQ 监听 + 服务端证书 + DDR + 反向代理 + 移动端描述文件）已完成；`traffic` 的设备子页（客户端识别与别名 + ACL + 令牌桶限流）与客户端分组子页（网段分组 + 组级拦截方式/白名单/时间计划 + 订阅与上游绑定）已完成，`traffic` 整支迁移完成（缓存热点与 Top 域名/客户端由既有 `hub` 缓存页与 `logs` 排行页承担，不重复实现）；`tools` 的诊断子页（53 端口探测 + 一键修复）与规则检测子页（域名/记录类型模拟 + 命中规则与重写应答）已完成，`tools` 整支迁移完成（上游连通性探测与区域文件自检已分别在 `hub` 上游页与重写页的编辑器内实现，不重复造页）；`settings` 的外观子页（配色方案 + 深浅模式）、服务连接子页（IPC 地址/端口/令牌 + 核心服务与自启只读状态）与局域网控制台子页（远程管理开关/端口/地址/防火墙/管理员凭据）已完成，六个分支全部迁移完成；Wails 窗口已改为嵌入 Flutter Web 产物（`Desktop/build_frontend.py`），旧 Vue 源码保留备查但不再参与构建。**
> Windows 桌面窗口由 Wails 宿主加载 `Desktop/frontend/dist`，该目录现在由 Flutter 桌面入口构建（见第 6 节）；Vue 源码仅作对照。

## 1. 三层分工（唯一规范）

| 层 | 来源 | 约束 |
|---|---|---|
| UI 框架 | FlClash 0.9.2（GPL-3.0） | **已定型**：侧栏/浮条壳、桌面仪表盘栅格、`DashboardCard` 家族、`AppShape` / `AppTextStyle` / `AppGlyphs`。不再新增移植 |
| 信息架构 | 移动端 `lib/pages/**`（六分支） | 分支路径与顺序只来自 `lib/routes/branches.dart`；分区顺序与文案键沿用移动端同名页面 |
| 功能与后端 | 旧版桌面端 `Desktop/` | Vue 页面（`frontend/src/views`、`components`、`api`）与 Go 服务（`internal/ipc`）是功能蓝本：字段含义、状态机、接口、默认值、校验与边界情况一律以它为准 |

判定规则：

- 旧版桌面有的功能 → 照它的语义实现（同一接口、同一字段、同一失败提示）。
- 移动端有、旧版桌面没有的（sqflite、VPN/悬浮窗、原生通道、按应用流量）→ 桌面端不做，也不伪造。
- 旧版桌面有、移动端分支没有的 → 归入对应分支（见第 2 节），排布仍按移动端习惯。
- 后端缺能力 → 在 `Desktop/internal` 补 Go 接口（含 Go 测试），不在 Dart 侧推演。

## 2. 分支与旧版桌面对照

| 分支 | 旧版桌面来源（Vue） | 主要接口 |
|---|---|---|
| `home` 首页 | 总览·状态总览（`OverviewPanel`、`OverviewQuickCards`） | `/status`、`/service/status` |
| `logs` 日志仪表盘 | 总览·实时查询 / 查询历史 / 统计中心（`LiveQueryPanel`、`QueryHistoryPanel`、`QueryStatsPanel`、`QueryLogConfigCard`） | `/querylog/search`、`/querylog/stats`、`/querylog/config` |
| `hub` 功能中心 | 解析（`UpstreamPanel` ✅、`CachePanel`、`RewritePanel`、`DNS64Panel`）+ 防护（`RulesPanel`、`ServicesPanel`、`SchedulePanel`）+ 设备·加密 DNS / 安全隐私 | `/upstream/*`、`/cache/*`、`/dns/rewrite/*`、`/dns/dns64/*`、`/filter/*`、`/encrypted/*`、`/dns/privacy/*` |
| `traffic` 应用流量 | 设备·设备管理（`ClientsPanel` ✅、`ClientGroupsCard` ✅）+ 缓存热点与统计中心 Top 域名/客户端 | `/clients`、`/clients/groups`、`/cache/top`、`/querylog/stats` |
| `tools` 网络工具 | 系统·诊断与修复（`DiagnosticsPanel` ✅ 端口部分）+ 防护·规则检测（`RuleTestPanel` ✅）+ 上游/区域测试（已在上游页/重写页编辑器内实现） | `/portcheck`、`/filter/check`、`/upstream/test`、`/dns/zone/test` |
| `settings` 设置 | 系统·外观主题 / 服务与连接 / 局域网控制台 | `/status`、`/service/status`、`/web/*`、`/auth/*` |

> 旧版桌面没有按应用流量统计：`traffic` 只用设备与缓存维度，不画「按应用排行」。

## 3. 迁移一个页面（或子页）的顺序

1. **读旧版桌面**：`frontend/src/components` 对应面板与 `frontend/src/api` 调用，记下字段、默认值、校验与失败提示。
2. **读后端**：`Desktop/internal/ipc/routes.go` 与对应 `server_*.go` / `types.go`，确认返回结构与错误语义。
3. **读移动端**：`lib/pages/**` 同名页面，只取分区顺序与文案键（不取数据来源）。
4. **选容器**：整页 `CommonScaffold` + `PageBody`；概览用仪表盘栅格 + `DashboardCard`；设置用共享设置行；列表用表格/列表行。宽窗并列、窄窗单列，不新增指标。
5. **补测试与文档**：widget 测试用真实模型 + `FakeDesktopBackend`，然后回写第 6、7 节。

## 4. 硬约束（验收项）

| 维度 | 必须 | 禁止 |
|---|---|---|
| 主题 | `buildAppTheme(AppThemeSpec(...))` + `AppThemeCache`，明暗成对 | 自写 `ThemeData`、`ColorScheme.fromSeed`、局部改色 |
| 配色 | `seededColorScheme(style: ColorStyle.vivid)` 的 `Variant.content`、`SurfaceLevel`、`colorScheme.success/warning` | 页面内硬编码品牌色、`Colors.*` |
| 形状 | `AppShape` / `AppRadius`、`DashboardCorner` | `BorderRadius.circular(n)` |
| 排版 | `AppTextStyle.xxx.of(context)`、`DashboardText` | `fontSize:`、`height:` 之类的硬编码 |
| 字体 | `fontFamilyFallback: appFontFamilyFallback(...)` | 依赖系统默认字体链 |
| 图标 | `GlyphIcon(AppGlyphs.xxx)` | `Icons.*` |
| 文案 | ARB + `context.l10n`（先加 `app_zh.arb` / `app_en.arb` 再两端共用） | 页面内硬编码中文/英文、写死 `Locale` |
| 骨架 | `CommonScaffold`（浮条顶栏）；其余分支 `AppBarClearance` + `NullStatus` | 自造顶栏 + `SingleChildScrollView` 一把梭 |
| 导航 | 宽窗 `NavigationSidebar`、窄窗共享 `DockShell`，分支只来自 `branches.dart` | 另立一级页面结构或自管选中状态 |
| 仪表盘 | FlClash 桌面网格（四列、列宽上限 440、密度行高、余量给查询列表） | 自造卡片、自选栅格、假数据 |
| 数据 | 只读/只写本机 HTTP API，失败即明说（离线 / 需令牌 / 过期快照） | 本地推演服务端状态、把未知画成「运行正常」 |
| 作用域 | `AppScopes`（`ViewScope` + `MeasureScope` + `textScaler` 钳制）位于 `MaterialApp.builder` | 缺 `ViewScope` 直接用 `lib/ui` 组件 |

**可直接复用**：`lib/ui/**`、`lib/app/theme/**`、`lib/app/l10n/**`、`lib/routes/**`、`lib/shell/dock_shell.dart`、`lib/pages/home/dashboard/**`（卡片框架与文字角色）、`lib/widgets/stat_strip.dart`。
**不可直接复用**：`lib/pages/**` 页面本体（依赖原生通道、sqflite、VPN provider）。

## 5. 数据层

`lib/desktop/data/api/` 是桌面端唯一数据层，不承载视觉决策：

- `desktop_api_client.dart`：`/status`、`/service/status`、`/upstream/configure`（`GET` 读、`POST` 整表提交）、`/upstream/test`、`/upstream/stamp`、`/querylog/search`（首页 `limit=N&includeFile=0`；日志页 `limit/offset/includeFile=1` 加可选 `domain`/`client`/`qtype`/`status`）、`/querylog/stats`、`/querylog/clear`、`/querylog/config`（`GET` 读、`POST` 整表提交并由服务合并）、`/dns/start|stop`、`/takeover/enable|disable`、`/filter/pause`、`/dns/rewrite/rules`（`GET` 列表、`POST` 单条新增/覆盖、`DELETE ?domain=`）、`/dns/rewrite/configure`（部分字段提交，服务合并）、`/dns/zone/config`（`GET` 读、`POST` 部分字段并回传重建后的整表）、`/dns/zone/test`（保存前预演）。信封 `{success, data, error}`，`401` 标记为鉴权问题。
- `desktop_api_models.dart`：不可变模型（状态、缓存、过滤、查询行、`DesktopQueryStats`、`DesktopLogStatus`），缺字段按零值解析、不抛异常。
- `desktop_api_providers.dart`：`desktopStatusProvider`（2 s）、`desktopServiceStatusProvider`（10 s）、`desktopRecentQueriesProvider`（5 s）、`desktopControlProvider`（写操作串行化，失败保留错误）。
- `desktop_upstream_models.dart` / `desktop_upstream_providers.dart`：上游配置整表模型（模式、节点、Bootstrap、条件分流、独立回退链）与写路径；保存后回读服务端值，失败保留原表单并标过期；`desktopUpstreamProbeProvider` 只记录单节点测速结果，不把节点失败当服务离线。
- `desktop_log_providers.dart`：`desktopQueryStatsProvider`（10 s，失败保留上一份并标过期）、`desktopLogQueryProvider`（域名 + 客户端 + `qtype` + `status` + offset）、`desktopLogFeedProvider`（随条件重读）、`desktopLogClearProvider`（清空历史，成功后重读汇总与表格）、`desktopLogConfigProvider`（留存策略：开关即时写、数字随保存按钮、写后回读服务端值，失败保留原配置）。与首页快照分文件：一次日志失败不该清空首页。
- `desktop_rewrite_models.dart` / `desktop_rewrite_providers.dart`：重写引擎整表（开关、默认 TTL、规则列表）与单条规则（域名、快捷地址/别名/TXT、`records`、`rcode`、`ttl`）模型；`desktopRewriteProvider` 启动即读 `GET /api/v1/status`（取 `rewrite` 摘要）与 `GET /api/v1/dns/rewrite/rules`（取规则列表），四个写路径（开关、TTL、保存规则、删除规则）串行化并回读服务端；写被拒只把原因返回给页面，不改写屏幕上的值。错误码与记录类型清单与 Go 侧 `REWRITE_RCODES` / `rewriteRecordTypes` 同名同序。
- `desktop_zone_models.dart` / `desktop_zone_providers.dart`：本地权威区整表（引擎开关、默认 TTL、区列表、逐区构建结果、条数与长度上限）与预演结果模型；`desktopZoneProvider` 启动即读 `/dns/zone/config`，开关、TTL、整份区列表三个写路径串行化并直接采用服务回传的重建结果（含解析失败的区），被拒时保留上一份。区文本只在本地草稿里编辑，保存全部才提交。
- `desktop_dns64_models.dart` / `desktop_dns64_providers.dart`：DNS64 合成整表（开关 + RFC 6052 前缀列表，空列表按知名前缀 `64:ff9b::/96` 展示）与单一写路径；`desktopDns64Provider` 启动即读 `/status` 的 `dns64` 摘要，保存提交整表并回读服务端值，被拒时保留原配置。前缀文本按行去空行，是否为合法前缀由服务判定。
- `desktop_filter_config_models.dart` / `desktop_filter_config_providers.dart`：拦截引擎整表（总开关、应答模式、阻断地址、同步周期、响应侧复检、仅白名单、伪应答纠正及地址清单）与暂停状态（剩余时长、总开关）；`desktopFilterConfigProvider` 启动读 `/filter/stats` + `/filter/config`，每次写入后重读两份；`desktopFilterPauseProvider` 读 `/filter/pause`，暂停按所选时长提交、恢复不带时长。`POST /filter/config` 由服务合并，故整表只提交页面负责的字段。
- `desktop_privacy_models.dart` / `desktop_reputation_providers.dart`：强制安全搜索整表（开关、服务商黑名单、TTL）与声誉查询整表（恶意网址库/家长控制开关、超时/缓存容量/有效期、查询/命中/失败计数与拦截方式）；`desktopSafeSearchProvider` 读 `/safesearch/config`、写后回读；`desktopReputationProvider` 读 `/filter/safebrowsing` 并直接采用写回状态（服务会归一化越界参数）。
- `desktop_rule_check_models.dart` / `desktop_rule_check_providers.dart`：单次模拟结果（是否拦截、`block`/`allow`/`rewrite`/`pass` 动作、命中规则、来源库、判定原因、`$dnsrewrite` 应答码与记录摘要）与记录类型选项；`desktopRuleCheckProvider` 每次运行清空上一次判定，只保留本次域名/类型与服务返回的结论。
- `desktop_tools_models.dart` / `desktop_tools_providers.dart`：53 端口探测结果（可用性、冲突进程列表含 PID/进程名/服务名/ICS 与自身标记/逐条处置建议、系统级占用与可修复标志、综合诊断文本）；`desktopPortCheckProvider` 只在用户点击时探测（不轮询），修复提交 `startDNS:false` 并采用服务返回的复检结果。
- `desktop_client_groups_models.dart` / `desktop_client_groups_providers.dart`：分组整份文档（开关、组名/启用、成员 IP 或 CIDR、拦截方式覆盖、仅白名单、组级时间计划、订阅与上游绑定）以及可绑定项（订阅 id/名称/启用、上游 id/协议/服务器）；`desktopClientGroupsProvider` 读 `/clients/groups`，保存提交整份文档后回读，服务会丢弃无成员分组，被拒时保留草稿。
- `desktop_traffic_models.dart` / `desktop_traffic_providers.dart`：客户端识别列表（IP、rDNS/别名、累计查询、最近活跃）与 `/status` 的 `access`/`rateLimit` 两块（黑白名单、令牌桶速率/突发/聚合掩码/豁免清单）；`desktopTrafficProvider` 启动并行读 `/clients` 与 `/status`，别名、ACL、限流三条写路径各自回读所改状态，被拒时保留原值并回传原因。
- `desktop_encrypted_models.dart` / `desktop_encrypted_providers.dart`：加密 DNS 整表（总开关、DoT/DoH/DoQ 开关与端口、监听地址、服务器名、DoH 路径、证书参数、DDR、反向代理可信来源与转发头）与状态摘要（已配置端口对实际监听地址、DoH 客户端地址、证书主体/签发者/到期/剩余天数/指纹、证书目录、默认端口）；`desktopEncryptedProvider` 读 `/encrypted/dns/status`，配置、签发与导入证书三条写路径都直接采用服务返回的整份状态，被拒时保留原状态。
- `desktop_privacy_models.dart` / `desktop_privacy_providers.dart`：安全隐私整表（从 `/status` 的 `dns`/`ecs`/`rebind`/`hosts` 读取：EDE、私有 PTR、单标签、ECH、IPv6、ANY 与应答形式、EDNS 填充、ECS、重绑定白名单、hosts）；`desktopPrivacyProvider` 有五条写路径（隐私子集、单标签、ECS、重绑定、hosts），各自只提交自己那组字段并回读 `/status`，被拒时保留原配置。
- `desktop_services_models.dart` / `desktop_services_providers.dart`：内置服务目录整表（服务与分组、已勾选 id/分组、生效规则数、逐服务周计划与计划状态）；`desktopServicesProvider` 读 `/filter/services`，单个/整组/全部取消/逐服务计划四条写路径都直接采用服务回传的完整状态（省略字段保持原值，空数组清空）；整组拦截时清掉组内单独勾选，被拒时保留上一份并回传原因。
- `desktop_schedule_models.dart` / `desktop_schedule_providers.dart`：时间计划整表（开关、窗口列表、当前是否生效与命中的窗口 id）与逐服务的计划状态；窗口含名称、开关、`HH:MM` 起止（早于开始即跨夜）与星期键（空表示每天），空时刻的窗口不算完整。`desktopScheduleProvider` 读 `/filter/schedule`，保存提交开关与整份窗口列表后回读；被拒时保留原配置。
- `desktop_custom_rules_providers.dart`：自定义规则整表（`GET /filter/rules` 的字符串数组）与唯一写路径（`POST` 整表替换后回读）；被拒时保留服务端列表，页面草稿由脏标记保护，不会被回读覆盖。
- `desktop_filter_models.dart` / `desktop_filter_providers.dart`：规则拦截总览（拦截量、比例、规则数、启用库数、暂停剩余）与订阅列表整表（名称、URL、开关、条数、最近更新、`lastStatus`/`lastError` 健康度）；`desktopFilterListsProvider` 启动即读 `/filter/stats` + `/filter/lists`，新增、开关、删除、单个/全部更新四条写路径都重读两份答案，被拒时保留原行并回传原因。
- `desktop_cache_models.dart` / `desktop_cache_providers.dart`：缓存统计、条目、热点排行、落盘状态与整表配置模型；`desktopCacheSnapshotProvider`（4 s 轮询统计 + 排行 + 落盘状态，失败保留上一份并标过期）、`desktopCacheSearchProvider` + `desktopCacheEntriesProvider`（检索变化即重读，`query` 交给服务）、`desktopCacheConfigProvider`（开关即时写、策略表单随保存按钮、写后回读服务端值）、`desktopCacheActionProvider`（清空 / 立即落盘 / 从文件恢复，串行化并返回服务端结果）。
- `desktop_event_client.dart`：`/api/v1/events` 的 WebSocket 客户端（`web_socket_channel`，Web 与 IO 同一份代码）。令牌走查询串（浏览器握手不能带 header），断线 3 s 后重连；只把 `type: "query"` 事件转成 `DesktopLiveQuery`，并按 `errorMessage`/`success` → `blocked` → `cacheHit` 的顺序分类；`DesktopChannelEvent` 汇报通道通断。
- `desktop_live_providers.dart`：`desktopEventStreamProvider`（唯一套接字入口，测试用 `StreamController` 覆写）、`desktopLiveProvider`（500 条滚动缓冲、暂停即丢弃、清空只清缓冲）、`desktopLiveEnabledProvider`（widget 测试关闭，避免开套接字）。实时流不轮询：socket 断即明说未连接。
- 连接配置来自 `diting_desktop` 容器（`ipc_host`/`ipc_port`/`ipc_token`），默认 `127.0.0.1:15353` 且免密。
- 失败语义：从未成功 → 说明「连不上本机服务 / 需要访问令牌」并给重试；曾经成功 → **保留上一份快照**并标过期。

## 6. 当前仓库状态与构建方式

- Android 入口 `lib/main.dart`；桌面预览入口 `lib/desktop/main.dart`，`web/` 仅作 Wails/WebView 编译宿主。
- 路由 `lib/desktop/router.dart`：`StatefulShellRoute.indexedStack` 六分支；壳为 `lib/desktop/shell/desktop_shell.dart`（宽窗 `NavigationSidebar` + 内容区，窄窗共享 `DockShell`，折叠状态不落盘）。
- 首页 `lib/desktop/pages/home/`：`desktop_home_page.dart`（三种诚实状态 + 过期提示）、`desktop_dashboard.dart`（四列网格）、`widgets/*`（DNS 服务、查询指标、系统接管、暂停拦截、后台服务、缓存、规则拦截、性能、运行信息、最近查询）、`desktop_format.dart`。
- 日志 `lib/desktop/pages/logs/`：`desktop_logs_page.dart`（汇总 + 三列排行 + 实时流 + 表格 + 留存策略）、`widgets/log_summary_card.dart`（24 小时七项指标）、`widgets/log_rankings_card.dart`（高频域名 / 拦截排行 / 活跃客户端，顺序与截断由服务给定）、`widgets/log_live_panel.dart`（`/events` 实时流：连接状态、暂停/继续、清空、域名/客户端检索、类型与响应码筛选、仅看已拦截、缓冲计数）、`widgets/log_filters.dart`（域名/客户端两个检索框、记录类型与状态两个选择器、清空历史，`LogPicker` 与实时流共用）、`widgets/log_query_table.dart`（250 ms 防抖搜索、offset 翻页、空态区分无记录/筛选为空、读失败重试）、`widgets/log_config_card.dart`（留存策略：记录开关、内存缓冲条数、落盘开关与留存天数、客户端信息开关、落盘目录只读）、`log_format.dart`。**已覆盖旧版桌面 `QueryHistoryPanel` + `QueryStatsPanel` + `LiveQueryPanel` + `QueryLogConfigCard`**，`logs` 分支迁移完成。
- 功能中心 `lib/desktop/pages/hub/`：`desktop_hub_page.dart`（按解析/防护分组的共享列表行，只列已迁移入口）、`desktop_upstream_page.dart`（`/hub/upstream` 子路由，宽窗并排 Bootstrap 与回退链）、`widgets/upstream_mode_card.dart`、`widgets/upstream_nodes_card.dart`、`widgets/upstream_editor_dialog.dart`（预设 + sdns:// 印章 + 证书指纹校验）、`widgets/bootstrap_card.dart`、`widgets/conditional_routes_card.dart`、`widgets/fallback_chain_card.dart`、`widgets/upstream_common.dart`（协议名、模式文案）。**已覆盖旧版桌面 `UpstreamPanel` + `BootstrapConfigCard` + `ConditionalRoutesCard` + `FallbackUpstreamCard` + `UpstreamEditModal`**，`hub` 的上游子页迁移完成。
- 功能中心缓存 `lib/desktop/pages/hub/desktop_cache_page.dart`（`/hub/cache` 子路由，宽窗两列卡片、窄窗单列）、`widgets/cache_overview_cards.dart`（引擎总控 + 命中率 + 遥测指标 + 容量条）、`widgets/cache_top_card.dart`（Top 10 热点域名）、`widgets/cache_config_card.dart`（TTL 模式、最长/最短有效期、弱网兜底、极速响应、无效网址记忆、热点预取）、`widgets/cache_persist_card.dart`（落盘开关、间隔、文件路径、失败原因、立即落盘/从文件恢复）、`widgets/cache_exclude_card.dart`（Go RE2 排除正则、三条预设、条数与长度上限）、`widgets/cache_entries_card.dart`（服务端检索 + 四态筛选 + TTL/IP 明细表）、`widgets/cache_common.dart`（模式名、状态徽标、开关行与容量条）。**已覆盖旧版桌面 `CachePanel` + `CacheConfigCard` + `CachePersistCard` + `CacheExcludeCard` + `CacheTopDomains` + `CacheEntriesTable`**，`hub` 的缓存子页迁移完成。
- 功能中心重写 `lib/desktop/pages/hub/desktop_rewrite_page.dart`（`/hub/rewrite` 子路由）、`widgets/rewrite_engine_card.dart`（引擎开关 + 默认 TTL 即时保存）、`widgets/rewrite_rules_card.dart`（本地检索五列规则表、空态区分无规则/无匹配、行内编辑与删除确认）、`widgets/rewrite_editor_dialog.dart`（快捷目标与自定义记录两种模式、记录类型/取值、应答码覆盖、规则 TTL、服务端同款校验）、`widgets/rewrite_common.dart`（类型徽标文案与配色、TTL 回退）、`widgets/zone_file_card.dart`（本地权威区：引擎开关、默认 TTL、逐区构建状态徽标与失败原因、可展开的 RFC 1035 文本、预演解析、增删与「保存全部」、删除失败回滚、窄窗徽标换行）。**已覆盖旧版桌面 `RewritePanel` + `RewriteEditModal` + `ZoneFileCard`**，`hub` 的重写子页迁移完成。
- 功能中心 DNS64 `lib/desktop/pages/hub/desktop_dns64_page.dart`（`/hub/dns64` 子路由）、`widgets/dns64_card.dart`（合成开关携带已输入前缀即时保存、前缀多行编辑与「填入标准前缀」、内置排除网段说明、保存按钮与失败提示）。**已覆盖旧版桌面 `DNS64Panel`**，`hub` 的 DNS64 子页迁移完成。
- 防护·规则订阅 `lib/desktop/pages/hub/desktop_filter_lists_page.dart`（`/hub/filter-lists` 子路由）、`widgets/filter_lists_card.dart`（拦截总览指标、规则库两列网格、空态、添加/全部更新、逐行开关/立即更新/删除确认、健康度徽标与失败原因）、`widgets/filter_list_dialog.dart`（名称可留空、URL 必填）、`widgets/filter_common.dart`（健康度文案、`MM-DD HH:mm` 时间、暂停剩余时长）。**已覆盖旧版桌面 `RulesPanel` 的订阅页签与 `RuleListsPanel`**，`hub` 的订阅子页迁移完成。
- 防护·自定义规则 `lib/desktop/pages/hub/desktop_filter_rules_page.dart`（`/hub/filter-rules` 子路由）、`widgets/filter_custom_rules_card.dart`（宽窗左右并排的 AdGuard 语法速查与整表编辑器、非空行计数、脏标记草稿、保存后回读；保存失败保留草稿并说明原因）。**已覆盖旧版桌面 `RulesPanel` 的自定义规则页签**，`hub` 的自定义规则子页迁移完成。
- 防护·拦截方式 `lib/desktop/pages/hub/desktop_filter_config_page.dart`（`/hub/filter-config` 子路由）、`widgets/filter_mode_card.dart`（三种应答模式选择、阻断 IPv4/IPv6 与同步周期、脏标记草稿、非法值不提交）、`widgets/filter_pause_card.dart`（时长选择、暂停/立即恢复、剩余时长）、`widgets/filter_advanced_card.dart`（响应侧复检、仅白名单与警示、伪应答纠正开关与地址清单、可疑格式提示、快捷预设与撤销）；`FilterSummaryCard` 增加可选总开关。**已覆盖旧版桌面 `RulesPanel` 的拦截方式与高级拦截页签**，`hub` 的拦截方式子页迁移完成。
- 防护·时间计划 `lib/desktop/pages/hub/desktop_schedule_page.dart`（`/hub/filter-schedule` 子路由）、`widgets/schedule_editor.dart`（可复用的窗口编辑器：名称、开关、起止时刻、七个星期开关、每天、增删与删除确认；只有「保存计划」提交，未填时刻的行被丢弃）。**已覆盖旧版桌面 `SchedulePanel` + `ScheduleEditor`**，`hub` 的时间计划子页迁移完成。
- 防护·应用拦截 `lib/desktop/pages/hub/desktop_services_page.dart`（`/hub/filter-services` 子路由）、`widgets/blocked_services_card.dart`（已拦截计数、名称/域名/规则检索、分组选择与分组快捷开关、全部取消、服务网格与规则展开、随分组/计划内/计划外徽标）、`widgets/service_schedule_dialog.dart`（复用窗口编辑器编辑单个服务的周计划）。**已覆盖旧版桌面 `ServicesPanel` + `ServiceScheduleModal`**，`hub` 的应用拦截子页迁移完成。
- 设备·安全隐私 `lib/desktop/pages/hub/desktop_privacy_page.dart`（`/hub/privacy` 子路由）、`widgets/privacy_protocol_card.dart`（六个协议开关、ANY 应答形式、EDNS 填充选择器）、`widgets/privacy_ecs_card.dart`（ECS 开关、剥离真实子网、自定义子网草稿与保存）、`widgets/privacy_defence_card.dart`（重绑定开关与白名单弹窗、hosts 开关与联动系统 hosts）。**已覆盖旧版桌面 `PrivacyPanel` 的协议隐私、ECS 与内置防御部分**。
- 安全隐私续 `widgets/privacy_safe_search_card.dart`（总开关、七个服务商勾选、TTL 草稿与保存）、`widgets/privacy_reputation_card.dart`（恶意网址库开关与五项统计、超时/容量/有效期草稿、家长控制独立开关与未启用提示）。**已覆盖旧版桌面 `SafeSearchCard` + `SafeBrowsingCard` + `ParentalControlCard`**，`hub` 的安全隐私子页迁移完成。
- 设备·加密 DNS `lib/desktop/pages/hub/desktop_encrypted_page.dart`（`/hub/encrypted-dns` 子路由）、`widgets/encrypted_listeners_card.dart`（总开关、三种协议各自的配置端口与实际监听地址、DoH 客户端地址复制/打开、监听参数草稿与非法端口拦截）、`widgets/encrypted_cert_card.dart`（证书摘要与指纹、过期/临期告警、自签签发与 PEM 导入弹窗）、`widgets/encrypted_extras_card.dart`（DDR 确认后开启、反向代理透传与可信来源草稿、移动端描述文件链接）。**已覆盖旧版桌面 `EncryptedDNSPanel` 的监听/证书/DDR/反代/描述文件部分**，`hub` 的加密 DNS 子页迁移完成。
- 设备 `lib/desktop/pages/traffic/desktop_traffic_page.dart`（`traffic` 分支根页，替代占位页）、`widgets/client_list_card.dart`（客户端块列表、状态徽标、别名弹窗、逐客户端白名单/阻断）、`widgets/client_access_card.dart`（允许/阻断名单草稿、撤销与保存）、`widgets/client_rate_limit_card.dart`（总开关、速率/突发/聚合掩码、豁免清单、非法值不提交）。**已覆盖旧版桌面 `ClientsPanel`**，`traffic` 的客户端管理迁移完成。
- 客户端分组 `lib/desktop/pages/traffic/desktop_client_groups_page.dart`（`/traffic/groups` 子路由，设备页列表卡右上角进入）、`widgets/client_groups_card.dart`（总开关、稳定行键的分组草稿列表、新增/删除确认、整份保存、无成员分组不提交）、`widgets/client_group_editor.dart`（组名与启用、成员多行编辑、拦截方式选择、仅白名单、组级时间计划复用 `ScheduleEditor`、订阅/上游可切换绑定与继承说明）。**已覆盖旧版桌面 `ClientGroupsCard`**，`traffic` 的客户端分组迁移完成。
- 诊断 `lib/desktop/pages/tools/desktop_tools_page.dart`（`tools` 分支根页，替代占位页）、`widgets/port_diagnosis_card.dart`（按需探测、诊断文本原样展示、冲突进程块、系统/自身徽标、确认后一键修复）。**已覆盖旧版桌面 `DiagnosticsPanel` 的端口排查与自动修复部分**；其应急网络恢复是原生调用、没有 HTTP 接口，故未实现。
- 规则检测 `lib/desktop/pages/tools/desktop_rule_check_page.dart`（`/tools/rule-test` 子路由，工具页入口进入；左卡域名 + A/AAAA/ANY 选择 + 示例填充，右卡判定徽标、命中规则/来源库/原因、重写应答或权威 NODATA 说明）。**已覆盖旧版桌面 `RuleTestPanel`**，`tools` 的规则检测迁移完成。
- 设置 `lib/desktop/pages/settings/desktop_settings_page.dart`（`settings` 分支根页，按 hub 同款入口列表）与 `desktop_appearance_page.dart`（`/settings/appearance` 子路由）、`widgets/appearance_theme_card.dart`（九种配色缩略图 + 跟随系统/浅色/深色，直接读写共享的 `paletteProvider` / `themeModeProvider`，与移动端同一组偏好键）。**已覆盖旧版桌面 `AppearancePanel`**，`settings` 的外观迁移完成。
- 服务与连接 `lib/desktop/pages/settings/desktop_service_page.dart`（`/settings/service` 子路由）、`widgets/service_connection_card.dart`（读写 `ipc_host`/`ipc_port`/`ipc_token`，保存后重建客户端，测试连接走 `/health`，非法端口不写入）、`widgets/core_service_card.dart`（`/service/status` 的安装/运行/状态文本/开机自启只读展示；安装与自启由宿主机托管，与旧版 Web 模式一致）。**已覆盖旧版桌面 `ServicePanel` 的连接与核心服务部分**。
- 局域网控制台 `lib/desktop/pages/settings/desktop_lan_web_page.dart`（`/settings/lan-web` 子路由）、`widgets/lan_web_card.dart`（开关按 `configureFirewall:true` 提交、局域网地址复制/打开、端口草稿与非法值拦截、防火墙放行开关与 `none` 后端说明、管理员用户名/初始化状态与改密/初始化弹窗）。**已覆盖旧版桌面 `LanWebCard` 的开关、地址、防火墙与凭据部分**（二维码未实现：未引入二维码依赖）。
- `lib/desktop/pages/desktop_pages.dart` 只剩未知路由兜底页：`CommonScaffold` + 居中 `NullStatus`。
- 外观偏好复用 Android 的容器与键（`SharedPreferencesLegacyPrefsStore`）。
- 实时流依赖 `web_socket_channel`（`pubspec.yaml` 固定 3.0.3）；Wails/WebView 宿主与 `flutter run -d chrome` 都走浏览器 WebSocket。

```bash
cd DITING-Flutter
flutter run -d chrome -t lib/desktop/main.dart
flutter build web -t lib/desktop/main.dart
flutter test test/desktop_app_test.dart test/desktop_shell_test.dart \
  test/desktop_home_test.dart test/desktop_logs_test.dart \
  test/desktop_upstream_test.dart test/desktop_cache_test.dart \
  test/desktop_rewrite_test.dart test/desktop_zone_test.dart \
  test/desktop_dns64_test.dart test/desktop_filter_lists_test.dart \
  test/desktop_filter_rules_test.dart test/desktop_filter_config_test.dart \
  test/desktop_schedule_test.dart test/desktop_services_test.dart \
  test/desktop_privacy_test.dart test/desktop_encrypted_test.dart \
  test/desktop_traffic_test.dart \
  test/desktop_client_groups_test.dart \
  test/desktop_tools_test.dart \
  test/desktop_rule_check_test.dart \
  test/desktop_settings_appearance_test.dart \
  test/desktop_settings_service_test.dart \
  test/desktop_settings_lan_web_test.dart \
  test/desktop_wails_switch_test.dart \
  test/desktop_api_test.dart test/desktop_preferences_test.dart

# 应用自截图（写到 build/screenshots/，不提交）：
DITING_SCREENSHOTS=1 flutter test test/screenshot/app_screenshot_test.dart --update-goldens
```

- `test/screenshot/` 的桌面用例用 `FakeDesktopBackend` 渲染真实入口，不打开套接字；默认 `flutter test` 跳过。
- Windows 窗口由 Wails 嵌入 `frontend/dist`（`frontend/embed.go` 的 `//go:embed all:dist`）；`wails.json` 的 `frontend:install` 只做 `flutter pub get`、`frontend:build` 调用 `Desktop/build_frontend.py`，脚本先清空 `dist` 再用 `flutter build web -t lib/desktop/main.dart` 写入，避免旧 Vue 产物混入；`1280×720` 最小尺寸与 16:9 锁定不变。
- `Desktop/build.bat` → `maintenance/core/build_manager.py`，只构建 Vue 前端 + Go 服务/安装包。

## 7. 剩余顺序

按第 3 节逐分支推进；分支内子页可用 `StatefulShellRoute` 内的嵌套 `GoRoute`。顺序：

1. **无**：六个分支与 Wails 构建切换均已完成；后续为 Windows 实机验证（WebView2 下的 Flutter 渲染、窗口尺寸、安装包）与细节打磨。

## 8. 验收与守卫

`test/desktop_shell_test.dart`、`test/desktop_home_test.dart`、`test/desktop_logs_test.dart`、`test/desktop_upstream_test.dart`、`test/desktop_cache_test.dart`、`test/desktop_rewrite_test.dart`、`test/desktop_zone_test.dart`、`test/desktop_dns64_test.dart`、`test/desktop_filter_lists_test.dart`、`test/desktop_filter_rules_test.dart`、`test/desktop_filter_config_test.dart`、`test/desktop_schedule_test.dart`、`test/desktop_services_test.dart`、`test/desktop_privacy_test.dart`、`test/desktop_api_test.dart`、`test/desktop_event_client_test.dart` 覆盖：

1. **骨架**：桌面一级路由集合与 `branchOrder` 一致，每分支由 `CommonScaffold` 承载；已接入分支不再出现占位空态。
2. **视觉语言**：源码扫描 `lib/desktop`，不得出现 `Icons.`、`BorderRadius.circular(`、`ColorScheme.fromSeed`、`ThemeData(`、`fontSize:`、`Colors.`、硬编码中文。
3. **响应式**：1280 宽出现 `NavigationSidebar` 且无 `NavigationDock`/`NavigationBar`；390 宽出现 `NavigationDock`；侧栏可切换、可折叠；放大字号不溢出。
4. **数据**：卡片/表格显示服务返回的数字；离线、401、过期三种状态各自的文案与重试；写操作发出正确请求。
5. **解析与内容**：缺字段按零值、401 标记鉴权、错误信封透出 `error`、令牌随请求发送；页面标题与列名使用与旧版桌面/移动端同一批 ARB 键。
6. **实时流**：只有 `type: "query"` 事件成为查询行；暂停后不收录、继续后恢复、清空只清缓冲；通道断开显示未连接而非「监听中」（测试用 `StreamController` 覆写，不开套接字）。
7. **留存策略**：开关即时提交、被拒后回到服务端当前值、非法数字不提交、落盘目录只读。
8. **上游解析**：四种调度模式、节点/Bootstrap/分流/回退都显示服务返回值；切换模式提交整份配置；增删节点、Bootstrap 开关、分流规则、回退链、超时与响应码各自发出正确请求；保存被拒时说明服务错误并保留原表单；测速只影响节点徽标；印章解析回填协议、地址与 URL。
9. **缓存**：命中率、遥测、容量与 Top 10 都显示服务返回值；开关与策略保存提交整份配置、非法秒数不提交；检索把关键字发给服务、四态筛选只收窄已返回条目；清空与恢复先确认，落盘间隔按 30–86400 钳制；排除规则一行一条并丢弃空行；写被拒时说明原因且开关回到服务端值；窄窗收起初始 TTL 与地址列。
10. **重写**：规则名、类型徽标、目标行与 TTL 都显示服务返回值，失败应答码替换全部类型徽标；开关与 TTL 各自只提交自己那一个字段，非法 TTL 不提交；添加/编辑按快捷字段或记录列表组装整条规则、域名统一小写、失败应答码不再要求目标；删除先确认再发 `DELETE`；写被拒时说明原因且开关保持服务端值；检索只过滤已返回规则、不重发请求；无规则与无匹配空态分开；窄窗收起 TTL 列。
11. **本地权威区**：区数量/名字数与逐区构建状态都显示服务返回值，停用区标「已停用」、未加载区同时给出服务端原因；新增与文本编辑只改本地草稿，「保存全部」才提交整份列表；区引擎开关与默认 TTL 各自只提交一个字段、非法 TTL 不提交；删除立即提交，被拒后回滚到服务端仍持有的区；预演把顶点、文本与 TTL 发给 `/dns/zone/test` 并显示记录或失败原因；窄窗把状态徽标换到下一行。
12. **DNS64**：开关、生效状态与前缀列表都显示 `/status` 返回值，空前缀按知名前缀展示；切换开关提交整份配置并携带已输入前缀；保存按钮提交按行去空行后的列表并回显服务端值；「填入标准前缀」只改草稿不提交；写被拒时说明原因且开关保持服务端值；窄窗不横向溢出。
13. **规则订阅**：拦截量、比例、规则数、启用库数与每个规则库的条数/时间/健康度都显示服务返回值；开关提交整条记录（含 URL），单个与全部更新分别发出对应 id，添加先校验 URL 再提交名称与地址（名称留空按位置命名），删除先确认；写被拒时说明原因且开关保持服务端值；无订阅显示空态；窄窗单列不横向溢出。
14. **自定义规则**：语法速查与编辑器显示服务返回的规则；非空行计数随输入变化；保存提交去空行后的整表并回显服务端值；保存被拒时说明原因并保留草稿；窄窗单列不横向溢出。
15. **拦截方式**：总开关、三种应答模式、阻断地址、同步周期与指标都显示服务返回值；切换总开关提交整份表单，模式与地址/周期由保存按钮提交，非法周期或空地址不提交；暂停按所选时长提交 `durationSec`、恢复不带时长，暂停态显示剩余时间；高级开关各自提交一个字段，伪应答地址按行去空行保存并提示可疑格式；写被拒时说明原因且开关保持服务端值；窄窗单列不横向溢出。
16. **时间计划**：状态徽标区分未启用 / 生效中 / 计划外，均来自服务返回值；启用后显示窗口编辑器，新增/删除/改名/开关/起止/星期都只改草稿，「保存计划」才提交整份列表并回读；未填时刻的行不提交；保存被拒时说明原因；窄窗不横向溢出。
17. **应用拦截**：已拦截计数、分组、生效规则数与服务规则都显示服务返回值；检索按名称/域名/规则收窄已返回条目且不重发请求；单个开关提交整份选择，整组拦截清掉组内单独勾选，全部取消提交空选择；逐服务周计划保存提交到该服务并回读计划状态；写被拒时说明原因且选择保持服务端状态；窄窗单列不横向溢出。
18. **安全隐私（协议部分）**：六个协议开关、ANY 应答形式、EDNS 填充、ECS、重绑定与 hosts 都显示服务返回值；各开关提交自己那组字段（隐私子集 / 单标签 / ECS / 重绑定 / hosts），ECS 子网与重绑定白名单按草稿保存，白名单去空行；写被拒时说明原因且开关保持服务端值；窄窗单列不横向溢出。
19. **安全隐私（安全搜索与声誉查询）**：安全搜索总开关、服务商勾选与 TTL 都显示服务返回值，服务商开关只提交黑名单、TTL 非法不提交；声誉查询显示查询/拦截/命中率/失败/拦截方式，开关与家长控制各自只提交一个字段，超时/容量/有效期草稿随保存提交且非法值不提交；窄窗不横向溢出。
20. **加密 DNS**：总开关、三种协议开关与配置端口、实际监听地址、DoH 客户端地址、证书摘要/指纹/剩余天数、DDR 与反向代理状态都显示服务返回值；总开关与各协议开关各自提交一个字段，监听参数由保存按钮整份提交且端口非法不提交，可信来源按行去空行保存；DDR 需确认后才提交，取消不写；签发证书提交 CN/密钥类型/SAN/有效期，导入必须同时给出证书与私钥；证书过期时给出显著告警；窄窗单列不横向溢出。
21. **客户端分组**：组名、启用状态、成员、拦截方式、仅白名单、组级时间计划与订阅/上游绑定都显示服务返回值；改名/改成员/切换绑定进入同一次保存，无成员分组与不完整窗口不提交，新增与删除分组（删除需确认）都只改草稿，保存后回读；写被拒时说明原因并保留草稿；窄窗单列不横向溢出。
28. **Wails 构建切换**：`wails.json` 的 `frontend:build` 指向 `python build_frontend.py`、`frontend:install` 只解析依赖且不再有 Vue 开发服务器键；脚本把 `lib/desktop/main.dart` 构建到 `frontend/dist`；Wails 宿主仍 `//go:embed all:dist`。
27. **局域网控制台**：开关显示仅本地/对外开放，开启提交端口与 `configureFirewall:true` 并显示局域网地址；端口非法不提交、合法则保存；防火墙开关提交 `enable` 并在 `none` 后端时说明无需放行；改密提交旧/新密码、未初始化走 setup，两次不一致不提交；设置分支可进入该子页；窄窗单列不横向溢出。
26. **服务与连接**：连接卡显示当前 host/port/token，保存写入 `ipc_host`/`ipc_port`/`ipc_token` 并重建客户端，非法端口不写入；测试连接报告可达/不可达；核心服务卡显示安装、运行、状态文本与开机自启，未安装时如实标注；设置分支可进入该子页；窄窗单列不横向溢出。
25. **外观主题**：设置分支列出外观入口并可进入；九种配色与三种深浅模式都按当前偏好高亮，点选后立即切换（与移动端共用偏好键）；窄窗单列不横向溢出。
24. **规则检测**：未检测时只给提示；运行提交域名与记录类型（A/AAAA/ANY），示例标签直接填充并运行；判定徽标、命中规则、来源库、原因与 `$dnsrewrite` 应答码/记录都显示服务返回值，重写为 NODATA 时说明不返回记录；检测失败时说明原因且不显示旧判定；窄窗单列不横向溢出。
23. **端口诊断**：未探测时只给提示；探测后可用性与诊断文本、冲突进程（PID/进程名/服务名/地址）与系统/自身徽标都显示服务返回值；仅在不可用且可修复时给出修复按钮，修复需确认、提交 `startDNS:false` 并采用复检结果；写被拒时说明原因并保留冲突信息；窄窗不横向溢出。
22. **设备（traffic 根页）**：客户端 IP/名称/累计查询/最近活跃与 ACL 状态都显示服务返回值；别名保存提交 `{ip,name}` 且留空即清除，白名单与阻断互斥并提交整份名单，ACL 按行去空行保存、撤销恢复服务端值，限流开关与保存提交整份表单且非法数值不提交；写被拒时说明原因且开关保持服务端值；窄窗单列不横向溢出。

## 9. 明确禁止

1. 为桌面单独写 `ThemeData`，或在 `lib/desktop` 内自造卡片、状态标签、指标块、按钮等基础组件。
2. 用 `BorderRadius.circular`、`Icons.*`、硬编码中文、写死 `locale`、`fontSize:`、`Colors.*` 绕过设计系统。
3. 为桌面另立导航信息架构或外观偏好键。
4. 在 Dart 侧复制 Go 的 DNS 业务规则，或把未知状态画成「运行正常」。
5. 照搬移动端的原生通道、sqflite、Android 启动流程。
6. 后端缺接口时用本地推演补数——应先在 `Desktop/internal` 补 Go 接口。
7. 再从 `LearningObjects/FlClash-0.9.2` 拷页面级代码：设计语言以它为准，功能以旧版桌面端为准。
