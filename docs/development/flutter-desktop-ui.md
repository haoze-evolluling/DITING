# 谛听桌面端 Flutter UI 说明与迁移约束

> 当前状态：**入口/主题、外壳与导航、首页仪表盘、日志分支（24 小时汇总 + 三列排行 + 实时查询流 + 查询历史检索）已完成；日志留存配置与 hub / traffic / tools / settings 待迁移，Wails 切换尚未开始。**
> Windows 桌面窗口目前仍由 `Desktop/frontend`（Vue）提供；Flutter 桌面入口可独立构建预览。

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
| `hub` 功能中心 | 解析（`UpstreamPanel`、`CachePanel`、`RewritePanel`、`DNS64Panel`）+ 防护（`RulesPanel`、`ServicesPanel`、`SchedulePanel`）+ 设备·加密 DNS / 安全隐私 | `/upstream/*`、`/cache/*`、`/dns/rewrite/*`、`/dns/dns64/*`、`/filter/*`、`/encrypted/*`、`/dns/privacy/*` |
| `traffic` 应用流量 | 设备·设备管理（`ClientsPanel`、`ClientGroupsCard`）+ 缓存热点与统计中心 Top 域名/客户端 | `/clients`、`/clients/groups`、`/cache/top`、`/querylog/stats` |
| `tools` 网络工具 | 系统·诊断与修复（`DiagnosticsPanel`）+ 防护·规则检测 + 上游/区域测试 | `/portcheck`、`/filter/check`、`/upstream/test`、`/dns/zone/test` |
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

- `desktop_api_client.dart`：`/status`、`/service/status`、`/querylog/search`（首页 `limit=N&includeFile=0`；日志页 `limit/offset/includeFile=1` 加可选 `domain`/`client`/`qtype`/`status`）、`/querylog/stats`、`/querylog/clear`、`/dns/start|stop`、`/takeover/enable|disable`、`/filter/pause`。信封 `{success, data, error}`，`401` 标记为鉴权问题。
- `desktop_api_models.dart`：不可变模型（状态、缓存、过滤、查询行、`DesktopQueryStats`、`DesktopLogStatus`），缺字段按零值解析、不抛异常。
- `desktop_api_providers.dart`：`desktopStatusProvider`（2 s）、`desktopServiceStatusProvider`（10 s）、`desktopRecentQueriesProvider`（5 s）、`desktopControlProvider`（写操作串行化，失败保留错误）。
- `desktop_log_providers.dart`：`desktopQueryStatsProvider`（10 s，失败保留上一份并标过期）、`desktopLogQueryProvider`（域名 + 客户端 + `qtype` + `status` + offset）、`desktopLogFeedProvider`（随条件重读）、`desktopLogClearProvider`（清空历史，成功后重读汇总与表格）。与首页快照分文件：一次日志失败不该清空首页。
- `desktop_event_client.dart`：`/api/v1/events` 的 WebSocket 客户端（`web_socket_channel`，Web 与 IO 同一份代码）。令牌走查询串（浏览器握手不能带 header），断线 3 s 后重连；只把 `type: "query"` 事件转成 `DesktopLiveQuery`，并按 `errorMessage`/`success` → `blocked` → `cacheHit` 的顺序分类；`DesktopChannelEvent` 汇报通道通断。
- `desktop_live_providers.dart`：`desktopEventStreamProvider`（唯一套接字入口，测试用 `StreamController` 覆写）、`desktopLiveProvider`（500 条滚动缓冲、暂停即丢弃、清空只清缓冲）、`desktopLiveEnabledProvider`（widget 测试关闭，避免开套接字）。实时流不轮询：socket 断即明说未连接。
- 连接配置来自 `diting_desktop` 容器（`ipc_host`/`ipc_port`/`ipc_token`），默认 `127.0.0.1:15353` 且免密。
- 失败语义：从未成功 → 说明「连不上本机服务 / 需要访问令牌」并给重试；曾经成功 → **保留上一份快照**并标过期。

## 6. 当前仓库状态与构建方式

- Android 入口 `lib/main.dart`；桌面预览入口 `lib/desktop/main.dart`，`web/` 仅作 Wails/WebView 编译宿主。
- 路由 `lib/desktop/router.dart`：`StatefulShellRoute.indexedStack` 六分支；壳为 `lib/desktop/shell/desktop_shell.dart`（宽窗 `NavigationSidebar` + 内容区，窄窗共享 `DockShell`，折叠状态不落盘）。
- 首页 `lib/desktop/pages/home/`：`desktop_home_page.dart`（三种诚实状态 + 过期提示）、`desktop_dashboard.dart`（四列网格）、`widgets/*`（DNS 服务、查询指标、系统接管、暂停拦截、后台服务、缓存、规则拦截、性能、运行信息、最近查询）、`desktop_format.dart`。
- 日志 `lib/desktop/pages/logs/`：`desktop_logs_page.dart`（汇总 + 三列排行 + 实时流 + 表格）、`widgets/log_summary_card.dart`（24 小时七项指标）、`widgets/log_rankings_card.dart`（高频域名 / 拦截排行 / 活跃客户端，顺序与截断由服务给定）、`widgets/log_live_panel.dart`（`/events` 实时流：连接状态、暂停/继续、清空、域名/客户端检索、类型与响应码筛选、仅看已拦截、缓冲计数）、`widgets/log_filters.dart`（域名/客户端两个检索框、记录类型与状态两个选择器、清空历史，`LogPicker` 与实时流共用）、`widgets/log_query_table.dart`（250 ms 防抖搜索、offset 翻页、空态区分无记录/筛选为空、读失败重试）、`log_format.dart`。**已覆盖旧版桌面 `QueryHistoryPanel` + `QueryStatsPanel` + `LiveQueryPanel`**；日志留存配置（`QueryLogConfigCard`）尚未搬。
- 其余四个分支在 `lib/desktop/pages/desktop_pages.dart`：`CommonScaffold` + 居中 `NullStatus`（`commonPendingTitle` / `commonPendingBody`）。
- 外观偏好复用 Android 的容器与键（`SharedPreferencesLegacyPrefsStore`）。
- 实时流依赖 `web_socket_channel`（`pubspec.yaml` 固定 3.0.3）；Wails/WebView 宿主与 `flutter run -d chrome` 都走浏览器 WebSocket。

```bash
cd DITING-Flutter
flutter run -d chrome -t lib/desktop/main.dart
flutter build web -t lib/desktop/main.dart
flutter test test/desktop_app_test.dart test/desktop_shell_test.dart \
  test/desktop_home_test.dart test/desktop_logs_test.dart \
  test/desktop_api_test.dart test/desktop_preferences_test.dart

# 应用自截图（写到 build/screenshots/，不提交）：
DITING_SCREENSHOTS=1 flutter test test/screenshot/app_screenshot_test.dart --update-goldens
```

- `test/screenshot/` 的桌面用例用 `FakeDesktopBackend` 渲染真实入口，不打开套接字；默认 `flutter test` 跳过。
- Windows 窗口仍加载 `Desktop/frontend`（Vue 3），`wails.json` 用 `npm install` / `npm run build`，`1280×720` 最小尺寸与 16:9 锁定。
- `Desktop/build.bat` → `maintenance/core/build_manager.py`，只构建 Vue 前端 + Go 服务/安装包。

## 7. 剩余顺序

按第 3 节逐分支推进；分支内子页可用 `StatefulShellRoute` 内的嵌套 `GoRoute`。顺序：

1. **`logs` 补齐**：`QueryLogConfigCard`（日志留存配置：内存缓冲条数、落盘留存天数、落盘开关、客户端信息开关、落盘目录）。
2. **`hub`**：解析 + 防护两组子页（上游、缓存、重写、DNS64、订阅、应用拦截、自定义规则、拦截方式、时间计划）。
3. **`traffic`**：设备管理 + 缓存热点/Top 域名与客户端（不做按应用流量）。
4. **`tools`**：诊断与修复、规则检测、上游/区域测试。
5. **`settings`**：外观主题（复用 `lib/pages/appearance` 的组件与语义）、服务与连接、局域网控制台。

## 8. 验收与守卫

`test/desktop_shell_test.dart`、`test/desktop_home_test.dart`、`test/desktop_logs_test.dart`、`test/desktop_api_test.dart` 覆盖：

1. **骨架**：桌面一级路由集合与 `branchOrder` 一致，每分支由 `CommonScaffold` 承载；已接入分支不再出现占位空态。
2. **视觉语言**：源码扫描 `lib/desktop`，不得出现 `Icons.`、`BorderRadius.circular(`、`ColorScheme.fromSeed`、`ThemeData(`、`fontSize:`、`Colors.`、硬编码中文。
3. **响应式**：1280 宽出现 `NavigationSidebar` 且无 `NavigationDock`/`NavigationBar`；390 宽出现 `NavigationDock`；侧栏可切换、可折叠；放大字号不溢出。
4. **数据**：卡片/表格显示服务返回的数字；离线、401、过期三种状态各自的文案与重试；写操作发出正确请求。
5. **解析与内容**：缺字段按零值、401 标记鉴权、错误信封透出 `error`、令牌随请求发送；页面标题与列名使用与旧版桌面/移动端同一批 ARB 键。

## 9. 明确禁止

1. 为桌面单独写 `ThemeData`，或在 `lib/desktop` 内自造卡片、状态标签、指标块、按钮等基础组件。
2. 用 `BorderRadius.circular`、`Icons.*`、硬编码中文、写死 `locale`、`fontSize:`、`Colors.*` 绕过设计系统。
3. 为桌面另立导航信息架构或外观偏好键。
4. 在 Dart 侧复制 Go 的 DNS 业务规则，或把未知状态画成「运行正常」。
5. 照搬移动端的原生通道、sqflite、Android 启动流程。
6. 后端缺接口时用本地推演补数——应先在 `Desktop/internal` 补 Go 接口。
7. 再从 `LearningObjects/FlClash-0.9.2` 拷页面级代码：设计语言以它为准，功能以旧版桌面端为准。
