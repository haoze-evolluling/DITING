# 谛听 (DITING) Windows 端基础 DNS 内核架构设计与分阶段开发规划

## 1. 项目背景与设计目标

### 1.1 背景
谛听（DITING）移动端已在 Android 平台落地，提供多协议上游解析、多调度策略、规则拦截和高性能缓存能力。为了扩展至桌面平台，现启动 Windows 客户端研发，技术栈选定为 **Go + Wails**。

### 1.2 第一阶段核心目标
现阶段不追求全量特性迁移，专注于**基础工程结构搭建**与**最小可用 DNS 内核**，建立高内聚低耦合的架构骨架，完整跑通以下核心闭环：
$$\text{启动内核} \longrightarrow \text{接管系统 DNS} \longrightarrow \text{接收并处理 DNS 请求} \longrightarrow \text{安全恢复系统 DNS}$$

### 1.3 关键设计原则
1. **核心解耦**：核心 DNS 转发与调度逻辑保持纯 Go 实现，不与平台 API 或 UI 强绑定。
2. **渐进式演进**：服务层采用 Pipeline 中间件链设计，为后续规则引擎、LRU 缓存、应用分流、统计留出标准化插槽。
3. **安全自愈**：修改系统 DNS 涉及网络连通性底线，必须具备全自动状态持久化与崩溃自愈能力。

---

## 2. 既有实现分析与技术借鉴

### 2.1 Android Go 内核 (`Android/tunnel`) 深度剖析

#### 可复用与迁移模块
- **多协议上游转发器 (`resolver_*.go`)**：
  - `resolver_plain.go`：标准 UDP/TCP 53 查询，具备超时回退与重试。
  - `resolver_doh.go`：基于 HTTP/2 的 DoH 解析器，具备连接池复用。
  - `resolver_dot.go` / `resolver_doq.go`：TLS 与 QUIC 协议连接复用与会话保持。
- **调度与容灾策略 (`resolver_strategy.go`)**：
  - `single`（单节点）、`primary_backup`（主备容灾）、`parallel_race`（并发竞速）、`smart_prediction`（EWMA 延迟预测优选）。
- **引导解析器 (`bootstrap_resolver.go`)**：
  - 解决 DoH/DoT 域名解析递归死锁，带健康度评分与衰减淘汰机制。
- **独立监听服务 (`engine_standalone.go`)**：
  - 基于 `github.com/miekg/dns` 的双栈服务监听与发包分发机制。

#### 需剥离与重构模块（Android 专有特性）
- **Android 用户态协议栈**：移除 `gVisor netstack`、`tun2socks` 及虚拟 TUN 文件描述符。
- **移动端进程绑定**：剥离基于 `/proc/net/udp` 的 Linux Socket UID 解析与流量追踪。
- **Gomobile 类型约束**：去除 Gomobile 对导包类型的严苛限制，恢复原生 Go 接口与泛型设计。
- **Socket 保护**：去除 Android VpnService 专用的 `protectSocketFn`。

### 2.2 AdGuard Home 架构经验借鉴

- **处理管道与中间件模式 (`internal/dnsforward`)**：
  - AGH 采用请求处理链：`Access Control` $\rightarrow$ `DNS Rewrite` $\rightarrow$ `Filtering` $\rightarrow$ `Cache` $\rightarrow$ `Upstream`。
  - 谛听 Windows 端吸收该模式，以 Pipeline/Handler 模式组织请求分发，降低模块间耦合。
- **Windows 服务化运行体系 (`aghos` / `ossvc`)**：
  - 引入 `github.com/kardianos/service`，同一套代码无缝支持 Windows Service 后台注册与前台终端调试运行。
- **状态流转与优雅停机**：
  - 采用 Context 树与 WaitGroup 跟踪活跃请求（In-flight Queries），确保服务停止时不丢包、不挂起监听端口。

---

## 3. 系统整体架构设计

### 3.1 权限模型与双二进制协作模式

Windows 修改适配器 DNS 需要管理员权限（Administrator）。为兼顾 UI 用户体验与系统安全性，采用**服务化/IPC 分离的双二进制协作架构**：

```
+-----------------------------------------------------------+
|               用户界面层 (diting-gui.exe)                   |
|   Wails v2 + Vue 3 + TypeScript + @material/web (M3)      |
|                 (普通用户权限运行，轻量免 UAC)              |
+-----------------------------+-----------------------------+
                              |
                     Local HTTP / WebSocket
                   (127.0.0.1:15353 + Token)
                              |
+-----------------------------v-----------------------------+
|               核心特权服务 (diting-service.exe)             |
|         Windows Service / 后台守护进程 (管理员权限)          |
|                                                           |
|  [IPC Server]       [Windows Platform]    [DNS Service]   |
|  - REST Control API - 物理网卡枚举         - 53 双栈监听   |
|  - WS Metrics Stream- 双栈 DNS 接管/还原   - 中间件流水线  |
|                     - 崩溃持久化自愈       - 纯 Go 内核    |
+-----------------------------------------------------------+
```

### 3.2 架构分层职责

```
                +----------------------------+
                |    Wails Frontend (UI)     |
                |  (Vue 3 + Material Web M3) |
                +--------------+-------------+
                               |
                               v
                +----------------------------+
                |     Wails Go Bridge        |
                +--------------+-------------+
                               | IPC (HTTP/WS)
                               v
+-----------------------------------------------------------+
|                      diting-service                       |
|                                                           |
|  +-----------------------------------------------------+  |
|  |                 DNS Service Layer                   |  |
|  |   - UDP/TCP 53 双栈 Listener                         |  |
|  |   - Pipeline (Context -> Middleware -> Next)        |  |
|  +---------------------------+-------------------------+  |
|                              |                            |
|  +---------------------------v-------------------------+  |
|  |                 Core Kernel (Pure Go)               |  |
|  |   - Upstream Resolver (Plain / DoH / DoT)           |  |
|  |   - Scheduler (Single / Race / Backup / Smart)      |  |
|  |   - Bootstrap Resolver                              |  |
|  +-----------------------------------------------------+  |
|                                                           |
|  +-----------------------------------------------------+  |
|  |              Windows Platform Layer                 |  |
|  |   - Adapter Manager (物理网卡过滤)                   |  |
|  |   - DNS Override (PowerShell / netsh)               |  |
|  |   - State Persistence (JSON 灾备备份)               |  |
|  |   - Port 53 Detector (冲突检测)                     |  |
|  +-----------------------------------------------------+  |
+-----------------------------------------------------------+
```

---

## 4. 关键技术方案实现设计

### 4.1 物理网卡双栈接管与恢复机制
1. **网卡枚举与过滤**：
   - 过滤虚拟网卡（Hyper-V, WSL, VMware, TAP, TUN, Loopback）。
   - 仅选定连接状态为 `Up` 且包含有效 IPv4 默认网关的活动物理网卡。
2. **状态备份与原子持久化**：
   - 接管前记录网卡 GUID、名称、IPv4/IPv6 获取模式（DHCP 或 Static）以及原有 DNS 列表。
   - 序列化至 `%ProgramData%\DITING\dns_state.json`。
3. **双栈接管配置**：
   - IPv4 设置为 `127.0.0.1`。
   - IPv6 设置为 `::1`（防止 Windows 优先经由 IPv6 泄露或绕过）。
   - 刷新系统缓存：执行 `ipconfig /flushdns` 或 Win32 `DnsFlushResolverCache`。
4. **异常恢复与灾备自愈**：
   - `diting-service` 启动时首先检查 `dns_state.json`。若上次非正常退出导致系统 DNS 残留指向本地，则执行自愈还原。
   - 监听系统信号（SIGINT, SIGTERM, Windows 服务停止事件），触发优雅还原。
   - 随程序生成独立离线恢复脚本 `restore-dns.bat`，确保极端情况下用户可一键脱困。

### 4.2 DNS 服务层流水线（Pipeline）设计
借鉴 AGH 中间件设计，定义标准上下文与处理器接口：

```go
type DNSContext struct {
    Req       *dns.Msg
    Resp      *dns.Msg
    ClientIP  net.IP
    Protocol  string
    StartTime time.Time
}

type Middleware func(ctx *DNSContext, next func() error) error
```

第一阶段流水线极简装配：
$$\text{MetricsMiddleware (统计耗时)} \longrightarrow \text{ForwardMiddleware (转发上游)}$$
后续特性可直接在插槽中横向插入：
$$\dots \longrightarrow \text{RuleFilterMiddleware} \longrightarrow \text{CacheMiddleware} \longrightarrow \dots$$

---

## 5. 源码工程目录规划

Windows 端源码集中位于 `Windows/` 根目录下，模块组织如下：

```
Windows/
├── cmd/
│   ├── service/                 # 核心特权服务入口 (diting-service.exe)
│   │   └── main.go
│   └── gui/                     # Wails GUI 客户端入口 (diting-gui.exe)
│       └── main.go
├── internal/
│   ├── core/                    # 纯 Go DNS 核心内核 (无平台依赖)
│   │   ├── resolver.go          # 上游多协议解析器 (Plain/DoH/DoT)
│   │   ├── resolver_plain.go    # UDP/TCP 53 上游通信
│   │   ├── resolver_doh.go      # DoH HTTP/2 通信
│   │   ├── resolver_dot.go      # DoT TLS 通信
│   │   ├── scheduler.go         # 调度策略 (Single / Race / Backup)
│   │   └── bootstrap.go         # 引导解析与健康评分
│   ├── dns/                     # DNS 服务层与监听
│   │   ├── server.go            # 基于 miekg/dns 的双栈监听器
│   │   ├── context.go           # DNSContext 定义
│   │   ├── pipeline.go          # 中间件链编排器
│   │   └── forwarder.go         # 默认上游转发处理器
│   ├── platform/
│   │   └── windows/             # Windows 平台专用能力
│   │       ├── adapter.go       # 物理网卡枚举与状态监测
│   │       ├── takeover.go      # 系统 DNS 接管与恢复实现
│   │       ├── state.go         # 网卡状态持久化与自愈检查
│   │       └── portcheck.go     # 53 端口冲突检测
│   ├── ipc/                     # UI 与 Service 间通信
│   │   ├── server.go            # 本地 HTTP API & WebSocket 服务
│   │   ├── client.go            # GUI 端使用的 IPC 客户端
│   │   └── types.go             # 状态、控制指令与指标 DTO
│   └── config/                  # 配置管理
│       ├── config.go            # 配置结构体 (监听、上游、IPC)
│       └── store.go             # 配置文件读写与默认值填充
├── frontend/                    # Wails Vue 3 前端工程 (遵循 Material Design 3)
│   ├── src/
│   │   ├── api/                 # IPC HTTP/WS 客户端与事件通信封装
│   │   ├── assets/              # 本地静态资源 (内嵌 Material Symbols 离线图标与 Logo)
│   │   ├── theme/               # M3 动态色彩体系 (Seed Color 算法与 CSS 变量 Tokens)
│   │   ├── components/          # 基于 @material/web 封装的通用 M3 组件与卡片
│   │   ├── views/               # 5 大核心业务视图 (Dashboard, Adapters, Upstream, Logs, Settings)
│   │   ├── App.vue              # 根视图 (集成 M3 Navigation Rail 与路由/视图容器)
│   │   ├── style.css            # 全局样式与 M3 Design Tokens 注入
│   │   └── main.ts              # 应用入口 (Vue 初始化、M3 组件注册与自定义元素配置)
│   ├── package.json             # 依赖配置 (包含 @material/web)
│   └── vite.config.ts           # Vite 配置 (配置 isCustomElement 规则支持 md-* 标签)
├── wails.json                   # Wails 配置文件
├── go.mod
└── go.sum
```

*注：每个 Go 代码文件均严格遵循行数控制规范（单文件不超过 600 行）。*

---

## 6. 分阶段开发路线图 (Roadmap)

### 6.1 已完成阶段里程碑 (Completed Milestones: Phase 0～3)

当前 Windows 端核心后端底座与特权服务已全量落地并完成自愈与协议健壮性验证：

- **阶段零：工程骨架与基础依赖搭建 (Phase 0 - 已完成)**
  - 建立 Windows 独立 Go 模块，打通 Wails 与 `cmd/service`、`cmd/gui` 双二进制构建流程。
  - 建立代码行数控制规范（单文件 $\le 600$ 行）与自动化脚本体系。
- **阶段一：Go 核心 DNS 转发与服务层实现 (Phase 1 - 已完成)**
  - 成功移植 Plain (UDP/TCP 53)、DoH、DoT 多协议上游解析器及 Bootstrap 引导机制，剥离 gomobile/netstack 依赖。
  - 基于 `miekg/dns` 实现双栈监听与 Context/Middleware 中间件流水线，单测覆盖率达到标杆，通过 Python 专项脚本验证并发查询与上游失败回退。
- **阶段二：Windows 平台 DNS 接管、还原与容灾自愈 (Phase 2 - 已完成)**
  - 实现真实物理网卡精准枚举与虚拟/休眠适配器过滤，支持 53 端口冲突检测与占用告警。
  - 实现双栈 DNS 接管（IPv4 `127.0.0.1` / IPv6 `::1`）与原子持久化（`dns_state.json`）。
  - 实现基于快照的精准还原，具备服务启动自检与崩溃/意外断电灾备自愈能力，附带离线 `restore-dns.bat`。
- **阶段三：服务化封装与 IPC 通信层实现 (Phase 3 - 已完成)**
  - 接入 `kardianos/service` 支持后台 Windows Service 注册及前台 `-run` 调试。
  - 搭建本地轻量 HTTP RESTful 控制接口（`127.0.0.1:15353` + Token 鉴权）及 WebSocket 实时指标推送流（`/api/v1/events`）。
- **阶段四：Material Design 3 桌面端 UI 研发与全流程闭环 (Phase 4 - 已完成)**
  - 接入官方 `@material/web` 组件库与 MCU 动态色彩算法（Dynamic Color），实现多预设种子色与 Windows 系统强调色提取，支持深色/浅色平滑切换。
  - 搭建标准桌面端 Navigation Rail 导航体系与五大核心业务视图（Dashboard、Adapters、Upstream、Logs、Settings），内嵌离线 Material Symbols 矢量图标。
  - 完成特权服务 IPC 前后端打通与异常边界交互，支持一键接管/还原、单卡控制、上游动态热更与实时延迟探测。

---

### 6.2 阶段四验收与完成记录 (Phase 4 Completed)

- **阶段目标**：全面构建遵循 **Material Design 3 (M3)** 规范的高品质桌面客户端，深度参考、学习并复用 `LearningObjects/material-web-main` 的设计体系与代码资产，与特权服务打通实现开箱即用的产品化闭环。
- **UI/UX 与前端技术核心要求**：
  1. **组件库接入与 Vue 3 原生集成**：
     - 直接引入 `@material/web` 官方 Web Components 组件库。
     - 在 Vite / Vue 3 编译层配置 `isCustomElement: (tag) => tag.startsWith('md-')`，实现 Vue 模板对 `<md-*>` 自定义元素的原生数据绑定与事件监听。
     - 深度参考 `LearningObjects/material-web-main` 中各核心组件的规范与代码设计：
       - 开关：`<md-switch>`（服务主控、网卡接管、自启开关）
       - 按钮：`<md-filled-button>`, `<md-outlined-button>`, `<md-text-button>`, `<md-icon-button>`
       - 列表：`<md-list>`, `<md-list-item>`（网卡呈现、上游节点列表）
       - 输入：`<md-outlined-text-field>`, `<md-filled-text-field>`（上游配置、Token 输入）
       - 选择：`<md-radio>`, `<md-outlined-select>`, `<md-select-option>`（调度策略与协议选择）
       - 弹窗：`<md-dialog>`（新增/编辑节点、恢复确认、错误警示）
       - 反馈与进度：`<md-circular-progress>`, `<md-linear-progress>`（延迟测速、加载状态）
       - 质感动效：`<md-elevation>`, `<md-ripple>`（卡片层级阴影与平滑水波纹反馈）
  2. **M3 Dynamic Color 调色体系与双色系主题**：
     - 参考 `material-web-main/tokens` 与色彩规范，接入 M3 Dynamic Color 算法。
     - 支持基于 **Seed Color**（种子色）全量生成 M3 语义化色盘（Primary, Secondary, Tertiary, Surface, Surface Container 等），支持用户自定义主题色或直接提取 Windows 系统强调色（Accent Color）。
     - 提供**深色模式（Dark）与浅色模式（Light）**平滑切换，默认跟随 Windows 桌面系统偏好。
  3. **桌面端 Navigation Rail 导航体系**：
     - 采用标准 M3 桌面端 **Navigation Rail**（左侧垂直导航轨）+ 主工作区流式卡片架构，保证 1024x768 桌面分辨率下的信息聚焦。
     - 导航栏集成品牌 Logo、特权服务运行状态徽标（Active/Inactive Badge）以及 5 大核心功能路由入口。
  4. **五大核心业务视图实现**：
     - **仪表总览 (Dashboard)**：
       - 核心状态总控大卡片：内置 `<md-switch>` 控制全局 DNS 代理及一键网络接管。
       - 实时遥测指标：展示实时解析 QPS、平均延迟、查询成功率高光数据卡片与平滑波形图。
       - 快捷上游与网卡摘要：呈现当前活动调度策略及接管网卡简报。
     - **网卡接管 (Adapters)**：
       - 物理网卡列表：以 `<md-list>` 结构清晰列出已识别活动物理网卡（排除虚拟网卡）。
       - 网卡详情：显示适配器名称、IPv4/IPv6 获取模式（DHCP/Static）、原始 DNS 与当前接管 DNS 对比。
       - 独立接管控制：支持针对特定物理网卡单独开启/还原接管。
     - **上游配置 (Upstream)**：
       - 上游节点管理：展示已配置的 Plain、DoH、DoT 节点列表及健康状态。
       - 调度策略配置：通过 `<md-radio>` / `<md-outlined-select>` 切换单节点（Single）、主备容灾（Primary-Backup）等调度模式。
       - 节点编辑与测试：利用 `<md-dialog>` 支持添加/修改上游，支持使用 `<md-circular-progress>` 显示实时延迟探测结果。
     - **实时日志 (Logs)**：
       - 实时事件滚动流：基于 WebSocket 连接（`/api/v1/events`）无延迟渲染 DNS 查询记录。
       - 检索与过滤：提供按域名、查询类型（A/AAAA）即时过滤，不同响应码（NOERROR、NXDOMAIN、SERVFAIL）采用 M3 彩色 Chips 区分。
       - 调试工具：支持一键清空日志视图、暂停/继续滚屏。
     - **设置中心 (Settings)**：
       - IPC 通信配置：配置本地特权服务监听端口（默认 15353）与 Token，内置连接探测。
       - 外观与主题：Seed Color 拾色器、系统强调色提取开关、浅色/深色主题切换。
       - 系统与容灾工具：Windows 开机启动配置、一键触发离线自愈恢复脚本（`restore-dns.bat`）。
  5. **离线图标与视觉资源规范**：
     - 本地内嵌 Material Symbols 矢量字体或 SVG 图标集，杜绝任何公网 CDN 依赖，保证在离线及内网环境中界面渲染完整。
  6. **IPC 前后端打通与异常边界交互**：
     - 封装 Wails 前端 HTTP/WebSocket 客户端，无缝调用后台 `diting-service` REST 接口。
     - 增加特权服务生命周期感知：当服务未运行、崩溃或端口冲突时，前端呈现友好的 M3 引导 Dialog，指导用户一键启动服务或排查 53 端口冲突。
- **涉及模块**：`Windows/frontend/*`, `Windows/cmd/gui/*`, `Windows/wails.json`
- **前置依赖**：阶段三特权服务与 IPC 接口就绪（已达成）。
- **验收标准**：
  - 启动 `diting-gui.exe` 免 UAC 弹窗秒级渲染，全界面符合 M3 视觉质感（圆角、Elevation、Ripple 动效）。
  - 支持 Seed Color 动态调色与明暗主题切换，UI 元素对比度与色彩层次分明。
  - 五大视图功能完整可用，能通过 IPC 接口稳定控制 DNS 服务与系统网卡双栈接管/还原。
  - WebSocket 遥测指标流与日志流持续稳定推送，高并发查询下界面不卡顿、内存平稳。
  - 完全脱离外网 CDN 运行，断网状态下界面与图标完全正常。

---

## 7. 后续扩展演进规划 (Future Roadmap)

第一阶段核心闭环建立后，架构中预留的插槽可平滑扩展以下功能，后端核心与 M3 前端界面保持端到端同步演进：

| 演进阶段 | 功能领域 | 对应后端内核扩展模块与设计 | 配套 Material Design 3 前端界面规划 |
|---|---|---|---|
| **Phase 5** | **智能缓存体系** | 移植 64 分片并发安全 LRU 缓存、Optimistic/Stale-While-Revalidate 容灾与 TTL 重写中间件 (`CacheMiddleware`) | **缓存监控大盘**：实时缓存命中率仪表图、热点域名 Top 统计、缓存条目检索与一键清空 `<md-dialog>` |
| **Phase 6** | **规则过滤引擎** | 移植 AdGuard 语法解析器、Mmap Trie 树、BloomFilter 预检与阻断响应中间件 (`FilterMiddleware`) | **规则管理中心**：订阅规则源列表、内置/自定义规则编辑器、规则拦截率统计与拦截日志高亮过滤 |
| **Phase 7** | **智能调度与竞速** | 移植 EWMA 智能延迟预测（Smart Prediction）与并行竞速（Parallel Race）上游调度策略 | **调度可视化面板**：各上游节点动态延迟分布折线图、EWMA 预测评分雷达图、竞速获胜率对比看板 |
| **Phase 8** | **高级网络分流与统计** | 支持按域名/分流规则匹配不同上游、出站代理联动、查询日志持久化与历史分析 | **统计与高级网络视图**：时序查询趋势图、客户端/协议分流拓扑展示、历史日志分页检索与导出 |
