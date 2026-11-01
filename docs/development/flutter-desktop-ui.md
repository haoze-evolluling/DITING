# 谛听桌面端 Flutter UI 说明与重建约束

> 当前状态：**入口/主题、外壳与导航、首页仪表盘（含本机 HTTP API 数据接入）已完成；下一步按移动端页面迁移其余五个分支，Wails 切换尚未开始**
> Windows 桌面窗口仍由 `Desktop/frontend`（Vue）提供；Flutter 桌面入口可独立构建预览。

## 1. 目标（已修订）

桌面端由三层组成，职责不重叠：

| 层 | 来源 | 状态 |
|---|---|---|
| UI 框架 | FlClash（`LearningObjects/FlClash-0.9.2`，同为 GPL-3.0） | **已定型**：侧栏壳、浮条底栏、桌面仪表盘栅格、`DashboardCard` 家族。不再从 FlClash 新增移植 |
| 页面内容 | 谛听移动端 `lib/pages/**` | **迁移中**：信息层级、文案键、卡片与列表结构与移动端一致，只按窗口宽度重排 |
| 数据 | 本机 HTTP API（`127.0.0.1:15353`） | **进行中**：`lib/desktop/data/api/` 逐分支补齐 |

- 框架只回答"怎么摆"：`NavigationSidebar` / `DockShell`、`CommonScaffold`、仪表盘栅格与 `DashboardCard` 家族、`AppShape` / `AppTextStyle` / `AppGlyphs`。
- 内容只回答"摆什么"：每个页面读移动端同名页面（`FeatureHubPage`、`LogsPage`、`TrafficPage`、`ToolsPage`、`SettingsPage` 及其子页）的分区、字段与文案键。
- 数据只回答"数值从哪来"：桌面端没有 Android 原生通道与 sqflite，一律走本机 HTTP API。

**从 FlClash 拷贝代码的阶段到此结束，FlClash 的设计语言仍是唯一规范。** 谛听移动端与 FlClash 移动端用的是同一套设计语言（同一份 `lib/ui` 家族：`CommonScaffold`、`DashboardCard`、`NavigationDock`、超椭圆、Glyph 图标、`SurfaceLevel` 分级），所以"按移动端页面迁移"不是换一套视觉规范，而是继续用 FlClash 的设计语言去摆谛听的信息架构：设计规则以 FlClash 为准，页面级实现以 `lib/pages/**` 为蓝本。两者只在两处不同：信息架构（谛听的六个分支与分区）与页面级代码来源（`lib/pages/**` 而非 `FlClash/lib/views/**`）。

### 1.1 迁移一个移动端页面的顺序

1. **读移动端**：`lib/pages/<分支>/**.dart` 与 `lib/state/*_providers.dart`，记下分区顺序、标题与文案键。
2. **找本机接口**：查 `Desktop/internal/ipc/routes.go` 的路由表，必要时在 `lib/desktop/data/api/` 补模型与客户端方法。接口缺失时页面显示"尚未接入"，不伪造数据。
3. **选框架容器**：整页用 `CommonScaffold`；列表用 `PageBody` + `DockSpacer`；概览用仪表盘栅格 + `DashboardCard`；设置项用共享的 `SettingTextCard` / 列表行。
4. **只改排布，不改语义**：同一份 ARB 键、同一套图标与状态色（移动端与 FlClash 同源，照搬即合规）；桌面多出来的宽度用于并列（宽窗两列）而不是新增功能或指标。
5. **补测试并回写文档**：该分支的 widget 测试（真实模型 + `FakeDesktopBackend`），然后更新本文档第 6、7 节的状态。

## 2. 已移除的内容与原因

提交 `6dbda50`（`feat(desktop): 搭建 Flutter 自适应 UI 基础骨架`）建立了一套与 Android、FlClash 都无关的平行实现，已整体回退：

| 已移除 | 原因 |
|---|---|
| 自建主题 `_desktopTheme`（`ColorScheme.fromSeed`）、自研组件 `DesktopCard`/`StatusPill`/`MetricTile`、五段式侧栏导航、硬编码中文文案 | 与共享设计系统无关，等于第三套视觉规范 |
| `DITING-Flutter/web/**`、`Desktop/flutter_frontend/**`、`Desktop/build_flutter_frontend.ps1` | 仅为该实现编译 Web 产物而添加 |
| `Desktop/platform_windows.go`、`Desktop/wails.json` 中的 Flutter 集成改动 | 已恢复为 Vue 前端资源与原有窗口行为（16:9 比例锁定、`1280×720` 最小尺寸） |

本次改造替换的是提交 `348cee1`/`bdd2c88`/`13988b3` 建立的"桌面复用安卓骨架"实现：`lib/desktop/pages/home/**` 的安卓仪表盘复刻被 FlClash 桌面网格取代，壳由共享 `DockShell` 改为 FlClash 侧栏壳。

## 3. 一致性硬约束

以下条目是**验收项**，不是建议：

| 维度 | 必须 | 禁止 |
|---|---|---|
| 主题装配 | `buildAppTheme(AppThemeSpec(...))`，经 `AppThemeCache` 缓存，明暗成对（`AppThemePair`） | 自己写 `ThemeData`、`ColorScheme.fromSeed`、局部 `copyWith` 改色 |
| 配色 | `seededColorScheme(style: ColorStyle.vivid)` 的 `Variant.content` 结果、`SurfaceLevel` 分级、`colorScheme.success/warning` | 页面内硬编码品牌色、用 `Colors.*` 调状态色 |
| 形状 | `AppShape` / `AppRadius`（超椭圆）、`DashboardCorner` | 手写 `BorderRadius.circular(n)` |
| 排版 | `AppTextStyle.xxx.of(context)`、`DashboardText` | 页面里写 `fontSize: 26`、`height: 1.5` |
| 字体 | `fontFamilyFallback: appFontFamilyFallback(...)`（Windows 中文为 `Microsoft YaHei UI`） | 依赖系统默认字体链 |
| 外观偏好 | 复用 `lib/state/appearance_providers.dart` 与 `appearance_extra_providers.dart` 的键与语义 | 另立 `desktop_*` 外观键 |
| 图标 | `GlyphIcon(AppGlyphs.xxx)` | `Icons.*`（Material 图标字体） |
| 文案 | ARB + `context.l10n`（含 `AppUiLocalizations.delegate`） | 页面内硬编码中文/英文字符串，或硬编码 `Locale('zh','CN')` |
| 页面骨架 | `CommonScaffold`（浮条顶栏 + 预留 inset），其余分支用 `AppBarClearance` + `NullStatus` | 自造顶栏 + `SingleChildScrollView` 一把梭 |
| 导航 | 宽窗 `NavigationSidebar`（`lib/ui/sidebar.dart`，移植自 FlClash），窄窗共享 `DockShell`；分支路径与顺序只来自 `lib/routes/branches.dart` | 另立一级页面结构或自管选中状态 |
| 仪表盘 | FlClash 桌面网格：四列、列宽上限 440、按密度缩放行高、余量给查询列表 | 自造卡片、自选栅格、假数据 |
| 页面内容 | 以移动端同名页面为蓝本：分区、字段、文案键一致，仅排布随窗口变化 | 自创分区、自加指标、把桌面做成另一套信息架构 |
| 数据 | 只读/只写本机 HTTP API，失败即明说（离线 / 需令牌 / 过期快照） | 本地推演服务端状态、把未知画成"运行正常" |
| 作用域 | `AppScopes`（`ViewScope` + `MeasureScope` + `textScaler` 钳制）必须位于 `MaterialApp.builder` | 缺 `ViewScope` 直接使用 `lib/ui` 组件（会命中 assert） |

## 4. 可复用与不可复用的层

**可直接复用：**

- `lib/ui/**`：设计系统全量（`CommonScaffold`、`DashboardCard` 家族在 `lib/pages/home/dashboard/`、`NavigationDock`、`NavigationSidebar`、`AppShape`、`AppTextStyle`、`GlyphIcon`、`NullStatus` 等）。
- `lib/app/theme/**`、`lib/app/bootstrap.dart` 的 `AppScopes`、`lib/app/l10n/**`、`lib/l10n/*.arb`。
- `lib/routes/**`、`lib/shell/dock_shell.dart`（含 `destinationOfBranch`）、`lib/pages/home/dashboard/dashboard_*.dart`（卡片框架、密度、配色、文字角色）。
- `lib/widgets/stat_strip.dart`（`PageBody`、`StatStrip`、`DockSpacer`）。

**不可直接复用：**

- `lib/pages/**` 的页面本体：依赖 Android 原生通道、`sqflite`、VPN/悬浮窗 provider 与 Android 启动流程。桌面端按 FlClash 布局重建页面内容。

## 5. 数据层边界

`lib/desktop/data/api/` 是桌面端唯一的数据层，不承载任何视觉决策：

- `desktop_api_client.dart`：`GET /api/v1/status`、`GET /api/v1/service/status`、`GET /api/v1/querylog/search?limit=N&includeFile=0`、`POST /api/v1/dns/start|stop`、`POST /api/v1/takeover/enable|disable`、`POST /api/v1/filter/pause`。响应信封为 `{success, data, error}`，`401` 单独标记为鉴权问题。
- `desktop_api_models.dart`：不可变的 `DesktopStatus` / `DnsServiceState` / `QueryMetrics` / `CacheStats` / `FilterStats` / `CoreServiceState` / `QueryLogEntry`，缺字段按零值解析，不抛异常。
- `desktop_api_providers.dart`：`desktopStatusProvider`（2 s 轮询）、`desktopServiceStatusProvider`（10 s）、`desktopRecentQueriesProvider`（5 s）、`desktopControlProvider`（三个写操作，串行化，失败保留错误供 UI 提示）。轮询由 `desktopPollingEnabledProvider` 控制，测试中关闭。
- 连接配置来自 `diting_desktop` 容器（`ipc_host` / `ipc_port` / `ipc_token`），默认 `127.0.0.1:15353` 且免密（服务端对本机回环放行）。
- 失败语义：从未成功过 → 整页说明"连不上本机服务 / 需要访问令牌"并给出重试；曾经成功过但当前轮询失败 → **保留上一份快照**并显示过期提示。不显示伪造的成功状态。

## 6. 当前仓库状态与构建方式

- Android 入口仍为 `lib/main.dart`；桌面预览入口为 `lib/desktop/main.dart`，`web/` 仅作为 Wails/WebView 的编译宿主。
- 桌面路由 `lib/desktop/router.dart`：`StatefulShellRoute.indexedStack` 六分支，壳为 `lib/desktop/shell/desktop_shell.dart` 的 `DesktopShell`——宽窗（`ViewScope.isMobileOf == false`）左侧 `NavigationSidebar` + 内容区，窄窗直接复用共享 `DockShell`。侧栏折叠状态是会话内的，不落盘。
- 侧栏本身在 `lib/ui/sidebar.dart`，逐行移植自 FlClash `lib/ui/sidebar.dart`（含折叠动画、悬浮展开、选中指示条），仅替换包名与本地化入口。
- 首页在 `lib/desktop/pages/home/`：
  - `desktop_home_page.dart`：`CommonScaffold` + 顶栏电源按钮（启动/停止 DNS，二次确认）+ 三种状态（首次加载 / 离线或需令牌 / 仪表盘）+ 过期提示条。
  - `desktop_dashboard.dart`：FlClash 桌面网格（四列、列宽上限 440 dp、居中、`top/control/middle` 三档行高、余量给查询列表），窄于四列时退化为单列自然高度。
  - `widgets/dashboard_cards.dart`、`dashboard_tiles.dart`、`recent_queries_card.dart`、`desktop_power_button.dart`：DNS 服务、查询指标、系统接管、暂停拦截、后台服务、缓存、规则拦截、性能、运行信息、最近查询。
  - `desktop_format.dart`：运行时长、百分比、时延、QPS 的文本格式；未知值统一显示 `—`。
- 其余五个分支位于 `lib/desktop/pages/desktop_pages.dart`：`CommonScaffold` + 居中 `NullStatus`，文案为 ARB 的 `commonPendingTitle` / `commonPendingBody`。
- 桌面外观偏好通过 `SharedPreferencesLegacyPrefsStore` 使用与 Android 相同的容器和键；Android 仍走原生 MethodChannel。

```bash
cd DITING-Flutter
flutter run -d chrome -t lib/desktop/main.dart
flutter build web -t lib/desktop/main.dart
flutter test test/desktop_app_test.dart test/desktop_shell_test.dart \
  test/desktop_home_test.dart test/desktop_api_test.dart test/desktop_preferences_test.dart

# 应用自截图（写到 build/screenshots/，不提交）：
DITING_SCREENSHOTS=1 flutter test test/screenshot/app_screenshot_test.dart --update-goldens
```

- `test/screenshot/` 的桌面用例使用 `FakeDesktopBackend` 渲染真实入口，不打开套接字；默认的 `flutter test` 会跳过这些用例。
- Windows 桌面窗口仍加载 `Desktop/frontend`（Vue 3），`wails.json` 使用 `npm install` / `npm run build`，窗口为 `1280×720` 最小尺寸与 16:9 比例锁定（有原生标题栏，故侧栏不预留窗口按钮区域）。
- `Desktop/build.bat` → `maintenance/core/build_manager.py`，仅构建 Vue 前端 + Go 服务/安装包。

## 7. 重建顺序

1. **入口与主题（已完成）**：`buildAppTheme` + `AppThemeCache` + `ThemeCrossFade` + `AppScopes` + `AppUiLocalizations.delegate`。
2. **外壳与导航（已完成）**：宽窗 FlClash 侧栏、窄窗共享浮条；分支路径唯一来源 `lib/routes/branches.dart`。
3. **首页仪表盘（已完成）**：FlClash 桌面网格 + 共享卡片框架；数据来自本机 HTTP API，含离线/鉴权/过期三种诚实状态。
4. **页面内容迁移（进行中）**：按移动端同名页面逐分支替换 `NullStatus` 占位，方法见 1.1。
   - `hub` ← `lib/pages/hub/feature_hub_page.dart`（分组入口；宽窗可两列）
   - `logs` ← `lib/pages/logs/logs_page.dart` 与 `log_dashboard_board.dart`（统计卡片 + 查询表）
   - `traffic` ← `lib/pages/traffic/traffic_page.dart`（筛选 + 明细行）
   - `tools` ← `lib/pages/tools/tools_page.dart`（DNS / ping / trace / speed 面板）
   - `settings` ← `lib/pages/settings/settings_page.dart`（分组设置行，外观复用 `lib/pages/appearance`）

   移动端页面本身不改；桌面端只换数据来源（`lib/desktop/data/api/`）与排布。
5. **外观设置（未开始）**：复用 `lib/pages/appearance` 的组件与预览语义，不另做一套。

## 8. 验收与守卫

`test/desktop_shell_test.dart`、`test/desktop_home_test.dart`、`test/desktop_api_test.dart` 覆盖：

1. **骨架守卫**：桌面一级路由集合与 `branchOrder` 一致；每个分支由 `CommonScaffold` 承载。
2. **视觉语言守卫**：`lib/desktop` 内不出现 `Icons.`、`BorderRadius.circular(`、`ColorScheme.fromSeed`、`ThemeData(`、`fontSize:`、`Colors.`、硬编码中文（源码扫描）。
3. **响应式守卫**：1280 宽出现 `NavigationSidebar` 且无 `NavigationDock`/`NavigationBar`；390 宽出现 `NavigationDock`；侧栏可切换分支、可折叠；放大字号不溢出。
4. **数据守卫**：卡片显示服务返回的数字（版本、PID、运行时长、计数、命中率、监听地址）；离线/401/过期三种状态各自的文案与重试；电源按钮确认后发出 `/dns/stop`，取消则不发；接管开关发出 `/takeover/enable`。
5. **解析守卫**：缺字段按零值解析、401 标记为鉴权、错误信封透出 `error`、非 JSON 与连接失败都转成 `DesktopApiException`、令牌随请求发送。
6. **内容守卫**（迁移分支时逐条补）：桌面页面出现的分区标题与移动端同名页面使用同一批 ARB 键；新增键必须先加进 `app_zh.arb` / `app_en.arb` 再由两端共用。

## 9. 明确禁止的做法

1. 为桌面单独写 `ThemeData`（哪怕只是"微调字号"）。
2. 在 `lib/desktop` 内自造卡片、状态标签、指标块、按钮等基础组件（卡片框架来自 `lib/pages/home/dashboard`）。
3. 用 `BorderRadius.circular` 代替 `AppShape` 的超椭圆。
4. 用 Material `Icons.*` 代替 `AppGlyphs`。
5. 在页面里硬编码中文文案，或把 `locale` 写死。
6. 为桌面另立导航信息架构或外观偏好键。
7. 在 Dart 侧复制 DNS 业务规则，或把未知状态画成"运行正常"。
8. 再从 `LearningObjects/FlClash-0.9.2` 拷贝页面级代码：设计语言仍以它为准，但页面级蓝本是移动端（两者本就同源）。
