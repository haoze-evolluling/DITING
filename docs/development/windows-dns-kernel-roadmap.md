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
|        Wails v2 + Vue 3 + TypeScript + Element Plus       |
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
├── frontend/                    # Wails Vue 3 前端工程
│   ├── src/
│   │   ├── api/                 # 状态与控制调用
│   │   ├── components/          # 仪表盘、开关、配置卡片
│   │   ├── views/               # 主界面与设置页
│   │   ├── App.vue
│   │   └── main.ts
│   ├── package.json
│   └── vite.config.ts
├── wails.json                   # Wails 配置文件
├── go.mod
└── go.sum
```

*注：每个 Go 代码文件均严格遵循行数控制规范（单文件不超过 600 行）。*

---

## 6. 分阶段开发路线图 (Roadmap)

### 阶段零：工程骨架与基础依赖搭建 (Phase 0)
- **阶段目标**：建立 Windows 端独立 Go 模块，打通 Wails 与特权服务的构建骨架。
- **具体工作**：
  1. 初始化 `Windows/go.mod`，引入 `github.com/miekg/dns`、`github.com/kardianos/service` 等核心依赖。
  2. 使用 Wails CLI 初始化 `frontend` 前端骨架（Vue 3 + TypeScript + Tailwind CSS）。
  3. 配置 `cmd/service` 和 `cmd/gui` 编译脚本与输出路径。
- **涉及模块**：`Windows/go.mod`, `wails.json`, `frontend/`, `cmd/`
- **前置依赖**：Go 1.23+ 环境、Wails v2 CLI、Node.js / pnpm。
- **验收标准**：
  - `go build ./cmd/service` 成功生成二进制并可输出版本号。
  - `wails build` 可成功拉起空白应用窗口并正常渲染。

---

### 阶段一：Go 核心 DNS 转发与服务层实现 (Phase 1)
- **阶段目标**：构建独立的 DNS 核心转发模块与服务监听管道，实现本地 DNS 代理基础功能。
- **具体工作**：
  1. 移植并改造 Android 端 `resolver_plain.go`、`resolver_doh.go` 与 `resolver_dot.go`，剥离 gomobile 与 netstack 代码。
  2. 实现单服务（Single）与主备切换（Primary-Backup）两种基础调度策略。
  3. 实现 Bootstrap 基础引导机制，保证 DoH 域名可被引导解析。
  4. 基于 `miekg/dns` 实现 `127.0.0.1:53` 与 `[::1]:53` 双栈监听，搭建 Pipeline 请求处理流水线。
  5. 编写单元测试模拟并发 DNS 查询与上游失败回退。
- **涉及模块**：`internal/core/*`, `internal/dns/*`
- **前置依赖**：阶段零完成。
- **验收标准**：
  - 单元测试覆盖率 $\ge 80\%$。
  - 使用 `nslookup www.bing.com 127.0.0.1` 能成功接收请求、转发至上游并正确获得 A/AAAA 响应。

---

### 阶段二：Windows 平台 DNS 接管、还原与容灾自愈 (Phase 2)
- **阶段目标**：实现 Windows 活动物理网卡的自动识别、双栈 DNS 接管、配置安全持久化与自愈还原。
- **具体工作**：
  1. 编写网卡扫描模块，通过 PowerShell / WMI 正确过滤出物理以太网和 Wi-Fi 网卡，排除虚拟与休眠适配器。
  2. 实现 53 端口占用探测，若遇到 ICS (SharedAccess) 等占用能明确输出诊断告警。
  3. 实现接管逻辑：备份原 DNS 并设置网卡为 `127.0.0.1` / `::1`，执行刷新缓存。
  4. 实现还原逻辑：根据持久化记录还原 DHCP 或指定静态 DNS，并清理状态文件。
  5. 实现异常崩溃与意外重启自愈检查：启动时检测到残留状态自动触发还原。
- **涉及模块**：`internal/platform/windows/*`
- **前置依赖**：阶段一完成。
- **验收标准**：
  - 执行接管命令后，网卡 IPv4/IPv6 DNS 正确指向本地，浏览器及系统网络正常解析。
  - 执行还原命令后，网卡完全恢复初始 DHCP/静态 DNS 状态。
  - 模拟 Kill 服务进程后再次启动，能自动检测到异常状态并正确自愈还原。

---

### 阶段三：服务化封装与 IPC 通信层实现 (Phase 3)
- **阶段目标**：将内核与平台能力包装为后台特权服务，提供本地 REST API 与 WebSocket 实时状态流。
- **具体工作**：
  1. 接入 `kardianos/service`，实现服务的安装、卸载、启动、停止及控制台 `-run` 调试模式。
  2. 实现本地 HTTP 控制服务（默认监听 `127.0.0.1:15353`，带鉴权 Token）。
  3. 实现 RESTful 接口：
     - `POST /api/v1/dns/start`、`POST /api/v1/dns/stop`
     - `POST /api/v1/takeover/enable`、`POST /api/v1/takeover/disable`
     - `GET /api/v1/status`（包含运行状态、当前上游、接管网卡列表）
  4. 实现 WebSocket `/api/v1/events`：推送实时查询计数、延迟及健康状态。
- **涉及模块**：`cmd/service/*`, `internal/ipc/*`, `internal/config/*`
- **前置依赖**：阶段二完成。
- **验收标准**：
  - `diting-service.exe -service install` 成功注册进 Windows 服务管理器。
  - 通过 curl 或 Postman 调用 REST API 能成功控制 DNS 启停与接管还原。
  - WebSocket 持续稳定输出请求事件流。

---

### 阶段四：Wails UI 客户端集成与端到端闭环验证 (Phase 4)
- **阶段目标**：完成前端界面构建，与特权服务打通，实现完整的桌面端产品闭环。
- **具体工作**：
  1. 在 Wails 中实现 IPC Client，封装与 `diting-service` 的 HTTP/WS 调用。
  2. 搭建 Vue 3 前端界面：
     - **服务总控卡片**：一键开启/停止 DNS 服务与系统接管状态。
     - **网卡状态列表**：展示当前系统网卡接管与 DNS 分配详情。
     - **实时指标展示**：展示当前解析 QPS、平均延迟、成功率。
     - **上游配置面板**：配置上游 DNS 服务器地址与监听端口。
  3. 异常边界交互：当特权服务未运行或端口冲突时，前端提供友好指引与重试提示。
- **涉及模块**：`cmd/gui/*`, `frontend/src/*`, `wails.json`
- **前置依赖**：阶段三完成。
- **验收标准**：
  - 启动 `diting-gui.exe`，无需管理员提权即可打开。
  - 点击“启动接管”，系统网卡 DNS 切换至 `127.0.0.1`，界面实时展示解析请求与延迟指标。
  - 点击“停止接管”，系统网卡 DNS 恢复原样，全程网络平滑无中断。
  - 达成阶段核心闭环交付标准。

---

## 7. 后续扩展演进规划 (Future Roadmap)

第一阶段核心闭环建立后，架构中预留的插槽可平滑扩展以下功能，避免重复重构：

| 演进阶段 | 功能领域 | 对应扩展模块与设计 |
|---|---|---|
| **Phase 5** | **智能缓存体系** | 引入移植自 Android 的 64 分片 LRU 缓存、Optimistic/Stale-While-Revalidate 容灾与 TTL 限制中间件 (`CacheMiddleware`) |
| **Phase 6** | **规则过滤引擎** | 引入移植自 Android 的 AdGuard 语法解析器、Mmap Trie 树、BloomFilter 预检与阻断响应中间件 (`FilterMiddleware`) |
| **Phase 7** | **智能调度与竞速** | 引入移植自 Android 的 EWMA 智能延迟预测（Smart Prediction）与并行竞速（Parallel Race）上游调度 |
| **Phase 8** | **高级网络分流与统计** | 支持按域名分流上游、出站代理联动、查询日志落库与历史统计图表 |
