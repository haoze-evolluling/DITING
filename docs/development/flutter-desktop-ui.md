# 谛听桌面端 Flutter UI 重构说明与迭代路线

> 当前阶段：**可运行的 UI 基础骨架（第一阶段）**
> 本文记录桌面端 Flutter 展示层的架构边界、完成范围、组件规范、适配方案和后续任务。这里不是“全功能迁移已完成”的声明。

## 1. 目标与边界

本次重构以 Flutter 统一 Android 与 Windows 桌面的 UI 技术栈，优先建立可持续扩展的基础框架，而不是一次性复制旧版所有页面。

- **替换范围**：Windows Wails 原生窗口中的 Vue 展示层。
- **复用范围**：现有 Go DNS 内核、Windows 服务管理、网卡接管、规则引擎、HTTP API、Wails App 绑定与托盘逻辑。
- **暂不替换**：`Desktop/frontend/` 中的局域网 Web 控制台。它继续独立构建并由 `diting-service` 内嵌，避免骨架阶段削弱远程管理能力。
- **不引入**：另一套 DNS 业务规则、另一份核心状态副本、Android 启动流程、Android 原生通道或演示数据驱动的假功能。
- **Linux 桌面窗口**：不在本阶段新增。Linux 仍按现有交付方式使用服务与 Web 控制台。

## 2. 总体架构

```text
DITING-Flutter/lib/desktop/main.dart
              │
              ▼
Flutter Material 3 桌面 UI（独立入口、独立路由与状态）
              │
              ├── HTTP /api/v1/* ───────► 本机 diting-service
              │                            DNS 状态、启停、网卡接管等
              │
              └── window.go.main.App ───► 现有 Wails App 绑定
                                           核心服务、自启动、应急恢复等

Flutter Web release 产物
              │
              ▼
Desktop/flutter_frontend/dist ──────────► Wails Windows 窗口

Desktop/frontend/dist（Vue，独立保留） ──► 局域网 Web 控制台
```

桌面入口与 Android 入口分离，但共享同一 Flutter 工程、Material 3 设计方向和 `AppPalette` 主题色定义。桌面端只引入自身需要的模块，不执行 Android 的规则数据库初始化、VPN、悬浮窗等启动逻辑。

## 3. 当前已完成

### 3.1 基础框架

| 项目 | 当前状态 | 说明 |
|---|---|---|
| 独立桌面入口 | 已完成 | `lib/desktop/main.dart`，不影响 `lib/main.dart` 的 Android 流程 |
| 应用根与主题 | 已完成 | 支持跟随系统、浅色、深色及九组主题色选择 |
| 路由体系 | 已完成 | `go_router` + `ShellRoute`，五类一级页面有稳定路径 |
| 全局页面骨架 | 已完成 | 品牌导航、顶栏、连接状态、刷新入口、内容区 |
| 响应式导航 | 已完成 | 宽侧栏、图标导航栏、窄屏底部导航三档 |
| 通用组件 | 已完成 | 页面容器、卡片、卡片标题、状态标签、指标块、待接入面板 |
| 状态管理 | 已完成 | Riverpod；10 秒轮询、手动刷新、操作忙碌态与错误反馈 |
| 桌面快捷键 | 已完成 | `Ctrl+1–5` 切换一级页面，`F5` 刷新 |
| 外观偏好持久化 | 已完成 | 使用 `shared_preferences`，桌面键独立于 Android 设置 |
| 测试 | 已完成 | 数据映射、总览、DNS 开关、导航、主题和窄屏组件测试 |
| Wails 集成 | 已完成 | 独立 Flutter 资源包、构建脚本与 Windows 可执行文件构建验证 |

### 3.2 已接真实后端的能力

| 页面/组件 | 已接能力 | 后端来源 |
|---|---|---|
| 总览 | DNS 运行状态、QPS、平均延迟、成功率、运行时长 | `GET /api/v1/status` |
| 总览 | DNS 启动与停止 | `POST /api/v1/dns/start`、`/dns/stop` |
| 总览 | 物理网卡接管状态与启停 | `GET /api/v1/status`、`POST /api/v1/takeover/enable`、`/disable` |
| 总览/解析 | 调度模式、上游数量、监听地址、缓存命中率与条目数 | `GET /api/v1/status` |
| 总览/防护 | 有效规则、启用订阅、累计拦截与拦截比例 | `GET /api/v1/status` |
| 设备 | 保护网卡数、局域网开放状态和监听地址摘要 | `GET /api/v1/status` |
| 设置 | Windows 核心服务状态、启动、停止、重启、安装并启动 | 现有 Wails App 绑定 |
| 设置 | 当前用户开机自启动 | 现有 Wails App 绑定 |
| 设置 | DNS 应急恢复 | 现有 Wails App 绑定 |

所有“待接入”区域只说明后续能力，不显示伪造的成功状态或业务数据。后台不可达时会保留最后一次成功快照并显示错误，不会把未知状态写成“运行正常”。

## 4. 目录与职责

```text
DITING-Flutter/
├── lib/desktop/
│   ├── main.dart                       # 桌面启动入口，仅加载桌面偏好
│   ├── app/
│   │   ├── desktop_app.dart            # MaterialApp、主题、本地化
│   │   └── desktop_router.dart         # 一级页面枚举与 ShellRoute
│   ├── data/
│   │   ├── desktop_models.dart         # UI 所需的不可变状态模型
│   │   ├── desktop_backend.dart        # 本机 Go HTTP API 适配
│   │   ├── desktop_native_bridge.dart  # 原生能力抽象，便于测试
│   │   ├── wails_bridge.dart           # Web/Wails JS interop 实现
│   │   └── wails_bridge_stub.dart      # VM 测试与非 JS 环境占位实现
│   ├── state/desktop_providers.dart    # 外观、轮询快照与操作状态
│   ├── shell/desktop_shell.dart        # 导航、顶栏和快捷键
│   ├── widgets/desktop_components.dart # 跨页面基础组件与格式化
│   └── pages/
│       ├── overview_page.dart          # 已接真实数据的总览
│       ├── module_page.dart            # 解析/防护/设备的工作区骨架
│       └── settings_page.dart          # 外观、核心服务和恢复
├── test/desktop_ui_test.dart
└── web/                                # Flutter Web/Wails 启动资源

Desktop/
├── flutter_frontend/
│   ├── embed.go                        # 仅供 Wails GUI 使用的 Flutter 资源
│   └── dist/                           # 构建产物，不入库（保留 .gitkeep）
├── frontend/                           # 保留的局域网 Web 控制台
├── build_flutter_frontend.ps1          # Flutter 桌面前端构建入口
├── platform_windows.go                 # 仅调整资源引用与窗口适配行为
└── wails.json                          # Wails 前端构建钩子
```

新增代码文件遵循仓库的 600 行上限。后续页面变大时，应优先按“页面 / 区域组件 / 表单对话框”拆分，而不是继续堆入现有文件。

## 5. 导航与跨屏适配

### 5.1 一级路由

| 页面 | 路径 | 快捷键 |
|---|---|---|
| 总览 | `/overview` | `Ctrl+1` |
| 解析 | `/resolution` | `Ctrl+2` |
| 防护 | `/protection` | `Ctrl+3` |
| 设备 | `/devices` | `Ctrl+4` |
| 设置 | `/settings` | `Ctrl+5` |

路由只负责页面位置，业务数据统一来自 `desktopDashboardProvider`，避免每个页面各自建立一套连接状态。

### 5.2 布局断点

断点以窗口可用宽度为准，而不是设备型号：

| 可用宽度 | 导航形式 | 内容策略 |
|---|---|---|
| `>= 1120` | 240 px 完整侧栏 | 指标四列，主要卡片双列 |
| `760–1119` | 80 px 图标导航栏 + Tooltip | 指标按宽度二/四列，卡片可转单列 |
| `< 760` | 底部 NavigationBar | 页面缩小边距，指标与卡片单列/双列自适应 |

- Windows 最小窗口为 **720×560**，不再锁定 16:9。
- 主内容最大宽度为 **1440 px**，超宽屏避免文字和表单无限拉宽。
- 所有页面主体可滚动；窄屏为底部导航预留空间由 `Scaffold` 自动处理。
- 后续表格页需单独制定“固定关键列 → 横向滚动 → 详情侧栏”的降级规则，不能简单压缩到不可读。

## 6. 组件与视觉规范

1. **设计语言**：Material 3；与 Android 共用 `AppPalette` 色种，不在页面中散落硬编码品牌色。
2. **圆角层级**：主运行卡片 24 px，普通卡片 20 px，指标/子块 12–16 px，状态标签使用胶囊形。
3. **间距**：以 4/8 px 为基准；桌面页面常规边距 28 px，窄屏 16 px，卡片间距 20 px。
4. **文字密度**：桌面正文 14–15 px，辅助信息 12 px；标题使用字重和层级，而不是仅依赖颜色。
5. **状态表达**：运行、停止、未知、忙碌必须区分；不用绿色装饰未连接状态。
6. **数值**：QPS、延迟等数字使用等宽数字特性；大计数使用 K/M 缩写，详细编辑页仍可显示完整值。
7. **交互反馈**：按钮使用 Material hover/focus/pressed 状态；图标按钮必须有 Tooltip；耗时操作禁用重复提交。
8. **危险操作**：停止核心服务、卸载、清规则、清日志等后续操作需要确认与结果反馈，不能只提供视觉按钮。
9. **空态与加载**：首批页面使用真实快照；后续列表页统一提供首次加载、空数据、离线保留数据、请求失败四种状态。
10. **动效**：只使用短暂、低幅度的状态反馈；禁止为装饰引入常驻重绘。路由切换不得包裹并复制 `ShellRoute` 的 Navigator。

## 7. 状态与错误约定

- 初次读取和后台轮询复用同一个 `refresh` 入口，10 秒轮询与 `F5` 不会并发重复请求。
- DNS/接管/原生服务操作期间使用 `isActionBusy`，防止重复提交。
- 请求失败通过页面提示条或 SnackBar 展示；用户可手动重试。
- 浏览器预览没有 Wails 原生桥接，服务管理区域会明确降级，不模拟原生结果。
- Wails JS 实现通过条件导入隔离，VM 组件测试不依赖浏览器或 WebView2。

## 8. 运行与构建

### 8.1 浏览器中开发 UI

```bash
cd DITING-Flutter
flutter pub get
flutter run -d chrome -t lib/desktop/main.dart
```

默认 API 地址为 `http://127.0.0.1:15353`。如需临时指定其他本机兼容服务：

```bash
flutter run -d chrome -t lib/desktop/main.dart \
  --dart-define=DITING_DESKTOP_API=http://127.0.0.1:15353
```

浏览器预览可调试布局和 HTTP 数据，不提供 Wails 原生服务按钮。跨域与鉴权行为以现有 Go 服务配置为准；Wails 环境会读取旧前端同源保存的 `diting_ipc_token`，并继续通过 `Authorization` 与 `X-API-Token` 传递。

### 8.2 单独构建 Flutter 桌面资源

```powershell
cd Desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_flutter_frontend.ps1
```

产物写入 `Desktop/flutter_frontend/dist/`。CanvasKit 等运行资源随包提供，不依赖 CDN。

### 8.3 构建 Windows 桌面应用

```cmd
cd Desktop
build.bat
```

构建链分别编译：

1. 保留的 Vue 局域网 Web 控制台；
2. Flutter 桌面 UI（由 Wails `frontend:build` 钩子调用）；
3. 现有 Go GUI 与核心服务；
4. NSIS 安装包。

仅做 Wails 集成复验时，可先构建 Flutter 资源，再执行：

```cmd
wails build -platform windows/amd64 -o diting-gui.exe -s -nopackage
```

`-s` 表示跳过重复前端构建，日常完整发布仍应使用 `build.bat`。

## 9. 当前验证范围

已执行并通过：

```bash
cd DITING-Flutter
flutter analyze lib/desktop test/desktop_ui_test.dart test/desktop_backend_test.dart
flutter test test/desktop_ui_test.dart test/desktop_backend_test.dart
flutter build web --target lib/desktop/main.dart --release

cd ../Desktop
go test .
go test ./cmd/service
wails build -platform windows/amd64 -o diting-gui-flutter-smoke.exe -s -nopackage
```

组件测试覆盖宽屏真实状态、DNS 开关、一级导航、深色主题、窄屏底部导航和 JSON 比例语义。此次没有修改 DNS 业务逻辑，因此没有重复运行整个 Go 内核测试集。

## 10. 尚未实现的功能

### 10.1 总览

- 实时查询流、查询历史、筛选与详情；
- QPS/延迟历史图表与 WebSocket 实时事件；
- 统计中心、缓存热点域名；
- 53 端口冲突检测、自动修复及对应引导对话框；
- 快捷暂停/恢复规则拦截。

### 10.2 解析

- 上游服务器增删改、协议校验、测速与调度配置；
- Bootstrap、条件分流、Fallback；
- 缓存容量、TTL、排除规则、持久化与缓存条目；
- DNS 重写、本地权威区、DNS64 与 IPv6 过渡配置。

### 10.3 防护

- 规则订阅增删改、刷新、镜像与更新状态；
- 自定义规则、批量编辑、规则检测；
- 应用/服务拦截、家长控制、安全搜索、恶意网址库；
- 拦截响应方式、时间计划、深链复检等高级选项。

### 10.4 设备

- 网卡列表与按网卡接管；
- 局域网 DNS、监听配置和防火墙；
- 客户端别名、分组与访问控制；
- DoT/DoH/DoQ 服务、证书、ACL 和移动配置；
- 协议隐私、速率限制、Hosts 与 Rebind 防护。

### 10.5 设置与跨模块

- 局域网 Web 控制台配置与鉴权管理；
- 界面截图、诊断详情、服务卸载；
- 配置导入导出、更新检查；
- 完整键盘焦点顺序、屏幕阅读器语义审查与高对比度验证；
- 多语言、文字缩放、减少动态效果等桌面偏好；
- 包体裁剪、WebView2 冷启动与长列表性能实测。

## 11. 后续实施顺序

### 第二阶段：打通核心工作流（优先）

1. **实时观测**：增加 WebSocket 事件适配和查询列表，替换总览的纯轮询实时性缺口。
2. **上游解析**：实现只读列表 → 新建/编辑 → 测速 → 调度配置，表单校验复用后端错误。
3. **规则订阅**：实现列表、启停、刷新与编辑；大数据量规则不直接一次性渲染。
4. **网卡与接管**：增加网卡选择、冲突提示和可恢复的操作反馈。
5. **诊断闭环**：补齐端口冲突、应急恢复结果与服务日志入口。

### 第三阶段：补齐高级模块

按“缓存与重写 → 拦截策略 → 客户端分组 → 加密 DNS → 安全隐私 → Web 管理”的顺序迁移。每个模块完成后再进入下一个，避免产生大量只有外壳的二级页面。

### 第四阶段：体验与发布完善

- 统一表格、表单、侧栏详情、确认对话框、Toast 和空态规范；
- 完成键盘、语义、文字缩放、减少动效和高对比度审查；
- 测量 WebView2 首帧、内存、CPU、GPU 与大列表帧率；
- 评估按需裁剪 CanvasKit 符号与未使用运行资源，发布后验证离线启动；
- 决定局域网 Web 控制台是否也在功能完整后迁移到 Flutter；不在骨架阶段同时重写两套界面。

## 12. 新增页面的实施约束

1. 在 `DesktopSection` 或目标页面的子路由中登记路径，不在页面内部自行维护另一套选中状态。
2. 先定义 UI 所需模型与后端适配，再编写页面；不要把 JSON Map 直接传入组件。
3. 优先复用现有 Go API/Wails 绑定。只有后端确实缺少能力时才另立后端任务，不在 UI 中重新实现业务规则。
4. 复用 `DesktopPage`、`DesktopCard`、`CardHeading`、`StatusPill` 等组件；新通用组件放入 `widgets/`。
5. 表单需有验证、提交忙碌态、错误保留与成功反馈；危险操作需确认。
6. 至少增加对应数据解析测试和一种宽/窄屏组件测试；涉及异步状态时覆盖失败路径。
7. 同步更新本文“已完成”和“尚未实现”清单，保持文档与实际能力一致。
