# 桌面管理端（Tauri + React）

桌面端管理界面位于 `desktop/ui/`，替代已移除的 Flutter 桌面前端。工程同时产出两种形态：

- **Tauri 桌面客户端**：独立窗口，直接连接本机已安装的 `diting-service`；
- **Web 管理页**：同一份 Vite 构建产物由 `diting-service` 在管理端口直接托管。

两者共享同一套 API 客户端、页面与设计系统，不存在两套界面实现。

## 架构

```
┌─────────────────────┐        HTTP /api/v1/*        ┌──────────────────────────┐
│ Tauri 窗口 (WebView)│ ───────────────────────────▶ │ diting-service           │
│ React SPA           │        WebSocket /events     │ 127.0.0.1:15353          │
└─────────────────────┘                              │ ├─ 管理 API              │
┌─────────────────────┐                              │ ├─ 静态 Web 管理页       │
│ 浏览器 Web 管理页   │ ───────────────────────────▶ │ └─ DNS 数据面            │
└─────────────────────┘                              └──────────────────────────┘
```

- 后端保持独立进程/系统服务，前端不内嵌 DNS 运行时，也不负责提权。
- 桌面客户端与 Web 管理页都通过 `Authorization: Bearer <token>` 访问管理 API；WebSocket
  使用 `?token=` 查询参数，因为浏览器 WebSocket 无法设置自定义请求头。
- IPC 默认监听 `127.0.0.1:15353`，可在服务启动参数或配置中修改；桌面客户端可在登录失败时
  修改管理地址，也可在“设置 → 账户与连接”中修改。
- Tauri 客户端的 Origin 为 `tauri://localhost` 或 `http(s)://tauri.localhost`，后端
  `cors.rs` 显式信任这两个保留来源；普通网页无法伪造。

## 工程结构

```
desktop/ui/
├─ src/
│  ├─ components/
│  │  ├─ charts/      趋势图（Recharts，含数据表视图）
│  │  ├─ dashboard/   运行概览、接管、上游、诊断
│  │  ├─ layout/      侧栏、顶栏、页面外壳
│  │  ├─ logs/        日志筛选、表格、详情抽屉、排名
│  │  └─ ui/          按钮、卡片、弹窗、选择器等基础组件
│  ├─ hooks/          API 查询、实时事件流、主题、退出登录
│  ├─ lib/            API 客户端、类型、格式化、文案映射
│  ├─ pages/          登录/初始化、概览、查询日志、设置
│  └─ stores/         认证、外观、实时数据（Zustand）
├─ src-tauri/         Tauri 2 壳、窗口配置、权限与图标
└─ dist/              Vite 构建产物（不入库，服务构建时嵌入）
```

### 认证与实时链路

- 首次启动时 `GET /api/v1/auth/status` 返回 `initialized=false`，界面进入管理员初始化流程。
- 登录成功后 token 写入 `localStorage`，401 响应会清空会话并回到登录页。
- `GET /api/v1/events` 的 WebSocket 事件用于实时查询流、QPS/指标与 DNS/接管状态变更；
  断线后指数退避重连。`dns`、`takeover` 事件会触发状态查询刷新。
- 概览页的“最近查询”在实时流为空时回退到历史检索；查询日志页默认展示历史，可切换实时模式。

## 设计约定

- 桌面优先：左侧固定导航、顶部运行状态栏、内容区多列网格；最小窗口 1080 × 700。
- 视觉参考 Android 端的圆角卡片、蓝色强调色与克制留白，布局参考 AdGuard Home 的
  仪表盘/查询日志结构。
- 颜色、圆角、字体全部通过 `src/styles.css` 的 CSS 变量定义；支持浅色/深色/跟随系统与
  四种强调色，用户选择保存在本机。
- 图表遵循单一纵轴、固定顺序的分类色、图例 + 数值直标、悬停十字线与数据表视图；
  分类色板已通过色觉障碍与对比度校验。
- 文件保持 600 行以内，页面与组件按职责拆分。

## 开发

```bash
cd desktop/ui
npm install
npm run dev          # 浏览器开发模式，默认代理到 127.0.0.1:15353
npm run tauri:dev    # 桌面窗口
```

`npm run dev` 的代理目标可通过 `DITING_DEV_API` 覆盖，便于连接测试端口上的服务。Vite
开发服务器固定监听 `1420`。

## 构建与嵌入

```bash
cd desktop/ui
npm run build        # 输出 desktop/ui/dist
cd ../../rust
cargo build --release -p diting-desktop-service
```

`rust/diting-desktop-ipc/build.rs` 在编译期读取 `desktop/ui/dist`（可用 `DITING_UI_DIST`
覆盖），把文件表嵌入服务二进制；未构建前端时 `HAS_ASSETS=false`，服务返回“前端静态资源包未加载”占位页。
因此更新 Web 管理页必须重新编译服务。

界面显示的版本号由 Vite 在构建期读取 `desktop/service/VERSION` 注入；Tauri 安装包版本读取
`desktop/ui/package.json`。`npm run dev` / `npm run build` 前会执行
`scripts/check-version.mjs`，校验 `package.json` 与 `src-tauri/Cargo.toml` 的版本和
`VERSION` 一致，避免发版时版本漂移。

Tauri 客户端单独构建：

```bash
cd desktop/ui
npm run tauri:build
```

Windows 也可直接运行 `desktop\build_client.bat`，`--debug` 生成不打包的调试版本。
产物由 Tauri 生成（Windows 为 `.msi` / `.exe`，Linux 为 `.deb` / AppImage），与
`desktop/build_installer.bat` 生成的服务安装包相互独立。

服务安装包流水线 `desktop/build_installer.bat` 会自动先执行 `npm run build` 并嵌入 Web
管理页；没有 Node.js 时可加 `--skip-ui` 退化为纯服务安装包。

## 当前范围

第一期覆盖：

- 登录/管理员初始化、服务连接与会话管理；
- 运行概览：DNS 启停、系统 DNS 接管、网卡接管、紧急恢复、端口诊断与自动修复；
- 上游列表、Bootstrap、缓存/拦截/延迟指标、24 小时趋势；
- 查询日志：实时流、历史检索、域名/客户端/状态/类型筛选、分页、详情、清空与 Top 排名；
- 设置：主题与强调色、日志容量/落盘/保留周期、服务信息与连接地址。

规则订阅、上游管理、加密 DNS、客户端访问控制等模块在后续阶段接入同一套 API。
