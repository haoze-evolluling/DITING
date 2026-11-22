# 桌面管理端（Web）

桌面端管理界面位于 `desktop/ui/`，替代已移除的 Flutter 桌面前端。工程只产出一份 Vite 构建
产物：由 `diting-service` 在管理端口直接托管，用户通过浏览器访问 Web 管理页。

- 后端保持独立进程/系统服务，前端不内嵌 DNS 运行时，也不负责提权。
- 安装包会在公共桌面创建“谛听 DNS 管理页”快捷方式，指向 `http://127.0.0.1:15353/`。

## 架构

```
┌─────────────────────┐        HTTP /api/v1/*        ┌──────────────────────────┐
│ 浏览器 Web 管理页   │ ───────────────────────────▶ │ diting-service           │
│ React SPA           │        WebSocket /events     │ 127.0.0.1:15353          │
└─────────────────────┘                              │ ├─ 管理 API              │
                                                     │ ├─ 静态 Web 管理页       │
                                                     │ └─ DNS 数据面            │
                                                     └──────────────────────────┘
```

- 管理页通过 `Authorization: Bearer <token>` 访问管理 API；WebSocket 使用 `?token=`
  查询参数，因为浏览器 WebSocket 无法设置自定义请求头。
- IPC 默认监听 `127.0.0.1:15353`，可在服务启动参数或配置中修改；管理页可在登录失败时
  修改管理地址，也可在“设置 → 账户与连接”中修改。
- 管理页与服务同源，CORS 只信任回环地址与 `localhost` 来源。

## 工程结构

```
desktop/ui/
├─ src/
│  ├─ components/
│  │  ├─ charts/      趋势图（Recharts，含数据表视图）
│  │  ├─ dashboard/   运行概览、接管、上游、诊断
│  │  ├─ filters/     拦截状态、订阅源、自定义规则、服务拦截、时间计划
│  │  ├─ lan/         局域网服务、访问控制、速率限制、客户端别名
│  │  ├─ encrypted/   加密 DNS 服务、证书、反向代理来源
│  │  ├─ upstreams/   上游服务器编辑与 Bootstrap
│  │  ├─ layout/      侧栏、顶栏、页面外壳
│  │  ├─ logs/        日志筛选、表格、详情抽屉、排名
│  │  └─ ui/          按钮、卡片、弹窗、选择器等基础组件
│  ├─ hooks/          API 查询、实时事件流、主题、退出登录
│  ├─ lib/            API 客户端、类型、格式化、文案映射
│  ├─ pages/          登录/初始化、概览、查询日志、规则、上游、局域网、加密 DNS、设置
│  └─ stores/         认证、外观、实时数据（Zustand）
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

界面显示的版本号由 Vite 在构建期读取 `desktop/service/VERSION` 注入。`npm run dev` /
`npm run build` 前会执行 `scripts/check-version.mjs`，校验 `desktop/ui/package.json` 的版本
和 `VERSION` 一致，避免发版时版本漂移。

服务安装包流水线 `desktop/build_installer.bat` 会自动先执行 `npm run build` 并嵌入 Web
管理页；没有 Node.js 时可加 `--skip-ui` 退化为纯服务安装包。

## 当前范围

已覆盖：

- 登录/管理员初始化、服务连接与会话管理；
- 运行概览：DNS 启停、系统 DNS 接管、网卡接管、紧急恢复、端口诊断与自动修复；
- 上游列表、Bootstrap、缓存/拦截/延迟指标、24 小时趋势；
- 查询日志：实时流、历史检索、域名/客户端/状态/类型筛选、分页、详情、清空与 Top 排名；
- 上游管理：解析策略、上游服务器增删改与连通性测试、DNS Stamp 导入、Bootstrap 服务器维护；
- 规则与拦截：拦截开关与临时暂停、订阅源增删改/启停/刷新、自定义规则与规则检测、内置服务整组或单项拦截、按周时间计划；
- 局域网与客户端：对外 53 端口开关、防火墙规则、允许/阻断客户端、速率限制、客户端别名；
- 加密 DNS：DoT/DoH 开关与端口、服务证书自签与 PEM/PKCS#12 导入、移动端描述文件下载、反向代理可信来源；
- 设置：主题与强调色、日志容量/落盘/保留周期、服务信息与连接地址。

以上页面统一通过 `/api/v1/*` 管理 API 读写，服务端配置变更会立即持久化并生效。
