# 谛听桌面端 Flutter UI 说明与重建约束

> 当前状态：**第 1–3 步（入口/主题、壳与导航、页面骨架）已完成；数据接入与 Wails 切换尚未开始**
> Windows 桌面窗口仍由 `Desktop/frontend`（Vue）提供；Flutter 桌面入口可独立构建预览。

## 1. 目标（已修订）

桌面端（Windows Wails 窗口内的 Flutter UI）**必须与 Android 端保持一致**：

- 同一套设计系统（`lib/ui`）、同一套主题装配（`lib/app/theme`）、同一套文案资源（`lib/l10n` 的 ARB）。
- 同一套页面骨架（`CommonScaffold` + `PageBody` + `DockInsetScope`）与同一套导航信息架构（`lib/router.dart` 的六个分支 + `NavigationDock`）。
- 同一套图标语言（`AppGlyphs` + `GlyphIcon`）。

**不做桌面端独立设计语言。** 桌面端与 Android 端的差异只允许来自两点：窗口尺寸（由 `ViewScope` 断点处理）和可用的后端能力（由数据层决定），不允许来自"另一套视觉规范"。

## 2. 已移除的内容与原因

提交 `6dbda50`（`feat(desktop): 搭建 Flutter 自适应 UI 基础骨架`）建立了一套与 Android 无关的平行实现，与上述目标相反，已整体回退：

| 已移除 | 原因 |
|---|---|
| `DITING-Flutter/lib/desktop/**`（`app/`、`shell/`、`pages/`、`widgets/`、`state/`、`data/`、`main.dart`） | 自建主题 `_desktopTheme`（`ColorScheme.fromSeed`）、自研组件 `DesktopCard`/`StatusPill`/`MetricTile`、自建五段式侧栏导航、硬编码中文文案，全部与 Android 设计系统无关 |
| `DITING-Flutter/test/desktop_backend_test.dart`、`test/desktop_ui_test.dart` | 测试断言的是上述平行实现（含硬编码中文文本），会把偏差固化 |
| `DITING-Flutter/web/**` | 仅为该实现编译 Web 产物而添加 |
| `Desktop/flutter_frontend/**`、`Desktop/build_flutter_frontend.ps1` | 承载上述实现的 Wails 资源与构建入口 |
| `Desktop/platform_windows.go`、`Desktop/wails.json`、`maintenance/core/build_manager.py` 中的 Flutter 集成改动 | 已恢复为 Vue 前端资源与原有窗口行为（16:9 比例锁定、`1280×720` 最小尺寸） |
| `DITING-Flutter/pubspec.yaml` 的 `http`、`shared_preferences` 依赖 | 仅该实现使用，已移除 |
| `DITING-Flutter/README.md` | 内容只描述双入口方案，已随实现一起移除 |

未受影响：Go DNS 内核、Windows 服务、`Desktop/frontend` 的 Vue 局域网 Web 控制台、Android 客户端与 `lib/ui` 设计系统本身。

## 3. 一致性硬约束

重建时以下条目是**验收项**，不是建议：

| 维度 | 必须 | 禁止 |
|---|---|---|
| 主题装配 | `buildAppTheme(AppThemeSpec(...))`，经 `AppThemeCache` 缓存，明暗成对（`AppThemePair`） | 自己写 `ThemeData`、`ColorScheme.fromSeed`、局部 `copyWith` 改色 |
| 配色 | `seededColorScheme(style: ColorStyle.vivid)` 的 `Variant.content` 结果 | 页面内硬编码品牌色、用 `Colors.*` 调状态色 |
| 形状 | `AppShape` / `AppRadius`（`RoundedSuperellipseBorder` 超椭圆） | 手写 `BorderRadius.circular(n)` 当卡片/按钮圆角 |
| 表面与层次 | `.withAppSurfaces`（`SurfaceLevel.page/card/floating` 分级 + 焦点环） | 自造"卡片底色 + 半透明描边"配方 |
| 排版 | `.withAppTypography` + `AppTextStyle.xxx.of(context)` | 在页面里写 `fontSize: 26`、`height: 1.5` |
| 字体 | `fontFamilyFallback: appFontFamilyFallback(...)`（Windows 中文为 `Microsoft YaHei UI`） | 依赖系统默认字体链 |
| 外观偏好 | 复用 `lib/state/appearance_providers.dart` 与 `appearance_extra_providers.dart` 的键与语义（明暗、色板、纯黑、文字缩放、字体、自定义背景、底栏样式、标签切换动效） | 另立 `desktop_*` 偏好键，或只实现"明暗 + 色板"两项 |
| 图标 | `GlyphIcon(AppGlyphs.xxx)` | `Icons.*`（Material 图标字体） |
| 文案 | ARB + `context.l10n`（含 `AppUiLocalizations.delegate`） | 页面内硬编码中文/英文字符串，或硬编码 `Locale('zh','CN')` |
| 页面骨架 | `CommonScaffold` + `PageBody`（`context.appBarInset` 进 `ListView.padding`）+ `DockSpacer` | 自造顶栏 + `SingleChildScrollView` |
| 导航 | `StatefulShellRoute.indexedStack` 六分支，路径与 `lib/router.dart` 一致；窄屏 `NavigationDock`，宽屏按 `_wantsFallbackBar` 降级为 `NavigationBar` | 另设五段式一级页面、侧边栏或自定义选中状态 |
| 动效 | `ThemeCrossFade`、`PageTransitionsTheme`（`commonSharedXPageTransitions`）、标签切换过渡 | `NoTransitionPage` 一把梭、常驻装饰动画 |
| 作用域 | `AppScopes`（`ViewScope` + `MeasureScope` + `textScaler` 钳制）必须位于 `MaterialApp.builder`，在 `Navigator` 之上 | 缺 `ViewScope` 直接使用 `lib/ui` 组件（会命中 assert） |

## 4. 可复用与不可复用的层

**可直接复用（零 Android 依赖，已验证）：**

- `lib/ui/**`：设计系统全量（`CommonScaffold`、`CommonCard`、`NavigationDock`、`AppShape`、`AppTextStyle`、`GlyphIcon`、`NullStatus`、`SettingTextCard` 等）。该目录只依赖 `material_ui` 与自身。
- `lib/app/theme/**`（`buildAppTheme`、`AppThemeCache`、`AppThemePair`、`AppPalette`、`AppThemeMode`）。
- `lib/app/bootstrap.dart` 的 `AppScopes`、`lib/app/l10n/**`、`lib/l10n/*.arb`。
- `lib/widgets/stat_strip.dart`（`PageBody`、`StatStrip`、`DockSpacer`）、`lib/routes/**`。

**不可直接复用：**

- `lib/pages/**`：依赖 Android 原生通道、`sqflite` 数据库、VPN/悬浮窗 provider 与 Android 启动流程。桌面端需要**按同一视觉与骨架重建页面内容**，而不是 import 这些页面。

**因此桌面端的正确形态是**：与 Android 共享 `lib/ui` + 主题 + 文案 + 骨架 + 路由结构，仅在页面数据来源（本机 HTTP API / Wails 绑定）与启动流程上分叉。

## 5. 数据层边界

- 数据适配（`GET /api/v1/status`、`POST /api/v1/dns/start`、`/takeover/*`、Wails App 绑定）单独成层，不承载任何视觉决策。
- 先定义 UI 所需的不可变模型，再写页面；不把 JSON `Map` 直接传进组件。
- 不在 Dart 侧复制 DNS 业务规则、不维护第二份核心状态、不显示伪造的成功状态。
- 后台不可达时保留最后一次快照并明确报错，不把未知状态画成"运行正常"。

## 6. 当前仓库状态与构建方式

- `DITING-Flutter` 的 Android 入口仍为 `lib/main.dart`；桌面预览入口为 `lib/desktop/main.dart`，`web/` 仅作为 Wails/WebView 的编译宿主。
- 桌面入口复用 `buildAppTheme`、`AppThemeCache`、`ThemeCrossFade`、`AppScopes`、液态玻璃作用域与全部本地化 delegate。
- 桌面路由 `lib/desktop/router.dart` 用共享的 `branchOrder` 生成六个分支；分支路径与顺序的唯一来源是 `lib/routes/branches.dart`（`lib/router.dart` 重新导出它）。
- 壳与底栏的唯一实现是 `lib/shell/dock_shell.dart` 的 `DockShell`：Android 的 `AppShell` 只在它外面加服务器模式分支，桌面直接使用。`NavigationDock` / 宽屏 `NavigationBar` 降级、`DockInsetScope` 预留、标签切换动效都在这一个文件里。
- 首页在 `lib/desktop/pages/home/desktop_home_page.dart`：`DashboardDensityScopeHost` + `CommonScaffold` + `PageBody`，电源按钮与诗句来自共享的 `buildHomeHeadline`（同一份 `homeOpacityProvider` / `homeSentenceProvider`），卡片板沿用安卓的 `DashboardCard` 卡框、`DashboardCardHeader` 标题、`dashboardCardGap` 间距与 `DashboardCardEntrance` 入场动效，顺序取自共享的 `dashboardWidgetsProvider`。
- 其余五个分支页面位于 `lib/desktop/pages/desktop_pages.dart`：`CommonScaffold` + `PageBody` + `NullStatus`（文案为 ARB 的 `commonPendingTitle` / `commonPendingBody`），标题与 Android 同键。
- 桌面外观偏好通过 `SharedPreferencesLegacyPrefsStore` 使用与 Android 相同的容器和键；Android 仍走原生 MethodChannel。

```bash
cd DITING-Flutter
flutter run -d chrome -t lib/desktop/main.dart
flutter build web -t lib/desktop/main.dart
flutter test test/desktop_app_test.dart test/desktop_shell_test.dart test/desktop_home_test.dart test/desktop_preferences_test.dart
```

- Windows 桌面窗口仍加载 `Desktop/frontend`（Vue 3），`wails.json` 使用 `npm install` / `npm run build`，窗口恢复 `1280×720` 最小尺寸与 16:9 比例锁定。
- `Desktop/build.bat` → `maintenance/core/build_manager.py`，仅构建 Vue 前端 + Go 服务/安装包。

## 7. 重建顺序

1. **入口与主题（已完成）**：桌面入口已装配 `buildAppTheme` + `AppThemeCache` + `ThemeCrossFade` + `AppScopes` + `AppUiLocalizations.delegate`，外观偏好使用 Android 的存储键并跨重启保存。
2. **壳与导航（已完成）**：六个分支的 `StatefulShellRoute.indexedStack`，`DockInsetScope` + `NavigationDock`（宽屏降级 `NavigationBar`），标签切换过渡复用 `_TabTransitionHost` 的语义。实现下沉为共享的 `lib/shell/dock_shell.dart`，Android 与桌面共用；桌面只保留 `lib/desktop/router.dart` 的页面映射，不写第二套壳。
3. **页面骨架（已完成）**：`CommonScaffold` + `PageBody`；首页按 Android 仪表盘重建（电源按钮、诗句、卡片板），其余分支先用 `NullStatus` 表达"尚未接入"，不用假数据。
   - 共享而非复制：`PowerState` 下沉到 `data/vpn/power_state.dart`（桌面不必引入 VPN 通道），`buildHomeHeadline` 供两端共用，`DashboardCardEntrance` 从 `DashboardBoard` 提升为公开组件，`dashboardWidgetsProvider` / `dashboardEditingProvider` 拆到 `state/dashboard_layout_providers.dart`（只依赖偏好，无原生数据源）。
   - 电源按钮当前停在 `PowerState.stopped`，点击只用 `homePowerPending` 说明"尚未接入"；每张卡片用 `commonPendingTitle` 徽标代替数字。第 4 步接上本机 API 后替换，不动骨架。
   - 桌面卡片板暂为只读（不提供编辑/移除），编辑入口随数据接入一起恢复，避免在没有数据的板上做无意义排序。
4. **数据接入**：按分支逐个接本机 HTTP API 与 Wails 绑定，替换占位。
5. **外观设置**：复用 `lib/pages/appearance` 的组件与预览语义，不另做一套。

每一步都应先让该步的页面在视觉上与 Android 对应页面一致，再进入下一步；不允许先铺页面再统一改皮。

## 8. 验收与守卫

重建后必须存在以下自动化守卫，防止再次偏离（当前实现：`test/desktop_app_test.dart`、`test/desktop_shell_test.dart`）：

1. **主题守卫**：同一 `AppThemeSpec` 下，桌面 `ThemeData` 的 `colorScheme`、`textTheme`、`cardTheme.shape` 与 `buildAppTheme` 输出一致。
2. **骨架守卫**：桌面一级路由集合与 `lib/router.dart` 的六个分支路径一致；页面必须由 `CommonScaffold` 承载。
3. **视觉语言守卫**：桌面 UI 目录内不出现 `Icons.`、`BorderRadius.circular(`、硬编码中文字符串（可用简单源码扫描测试实现）。
4. **响应式守卫**：宽/窄两种宽度下的组件测试，窄屏出现 `NavigationBar`/`NavigationDock`，页面无横向溢出。

## 9. 明确禁止的做法

以下反模式来自 `6dbda50` 的教训，任何一条出现都视为目标偏离：

1. 为桌面单独写 `ThemeData`（哪怕只是"微调字号"）。
2. 在 `lib/desktop` 内自造卡片、状态标签、指标块、按钮等基础组件。
3. 用 `BorderRadius.circular` 代替 `AppShape` 的超椭圆。
4. 用 Material `Icons.*` 代替 `AppGlyphs`。
5. 在页面里硬编码中文文案，或把 `locale` 写死。
6. 为桌面另立导航结构与偏好键，导致与 Android 两套信息架构。
7. 用"共享了颜色种子"充当"与 Android 一致"。
