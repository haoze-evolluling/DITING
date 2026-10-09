# 谛听 (DITING)

谛听（DITING）是一款专注于本地高性能 DNS 解析加速、智能调度优化与网络流量过滤的开源工具。致力于在设备本地实现低延迟解析、灵活规则阻断、防追踪与流量管控，全链路在本地闭环运行，无任何远程数据上传与隐私追踪。

本项目已实现跨平台支持：
- 📱 **Android 移动端**：支持纯 Kotlin 极速模式（窄路由、极低功耗）、Go 用户态全隧道模式（gVisor netstack、应用级分流、HTTPS 检查）及局域网独立 DNS 服务模式。
- 💻 **Windows 桌面端**：基于「特权系统服务 + Wails 桌面 GUI + 局域网 Web 控制台」双二进制协作架构，提供物理网卡双栈 DNS 安全接管、崩溃自愈、53 端口冲突检测、局域网 DNS 服务与浏览器远程管理。
- 🧰 **开发者维护工具箱**：基于 Python + PyWebView 提供桌面可视化维护套件，涵盖 DNS 批量压测、代码规范扫描、品牌资产渲染、界面自动截图、跨端统一流水线构建与全端版本同步。

---

## 核心特性

### 📡 DNS 解析与上游调度
- **多协议支持**：支持标准 DNS（UDP/TCP 53）、DNS-over-HTTPS（DoH）与 DNS-over-TLS（DoT）。
- **多策略调度**：提供**单一服务**（Single）、**智能优选**（Smart EWMA 延迟预测与成功率考量）、**最快响应**（Fastest 并发竞速）及**依次尝试**（Sequential 备援容灾）四种调度模式。
- **服务商管理**：内置阿里、腾讯、Cloudflare、Google、DNSPod 等主流公共 DNS，支持自由扩展与编辑自定义节点。
- **Bootstrap 引导与防绕过**：内置与自定义 Bootstrap IP 负责解析加密上游域名，杜绝递归死锁；启用 DDR 防绕过机制（拦截 `_dns.resolver.arpa`），引导流量规范经由本地通道解析。

### ⚡ 智能缓存与容灾防击穿
- **并发安全分片缓存**：采用 64 分片并发安全 LRU 缓存，提供跟随 TTL、平衡、高命中等多档预设策略，兼顾解析实时性与响应效率。
- **乐观容灾（Stale-While-Revalidate）**：在上游超时或网络抖动时，短暂复用仍处于宽限期内的过期缓存，保障弱网基本可用。
- **并发合并防击穿（Singleflight）**：针对突发同一域名的并发解析请求进行请求合并，减轻上游负载并防止本地缓存击穿。

### 🛡️ 规则引擎与地址覆写
- **高性能多维度匹配**：支持域名黑白名单（兼容 AdGuard 语法、通配符与正则）、Trie 前缀树与 Bloom 过滤器加速、网页元素隐藏（Cosmetic）规则。
- **规则订阅与自动更新**：支持 AdGuard 格式远程规则订阅，支持规则分组、镜像源模板加速（如 GitHub 镜像代理）与后台定时自动拉取更新。
- **静态覆写与重定向**：支持 IPv4 / IPv6 静态地址覆写（A / AAAA 记录）与 CNAME 重定向解析。
- **多样化阻断响应**：支持零地址（`0.0.0.0` / `::`）、NXDOMAIN、NODATA 与 REFUSED 四种拦截响应行为。

### 📱 Android 移动端专属特性
- **细粒度应用分流**：支持排除应用（Bypass 直连物理网络）、禁止联网（丢弃全部外联）与应用白名单访问（仅限访问已解析 IP）。
- **可选 HTTPS 流量检查**：基于 gVisor netstack 与本地 CA 根证书，仅对用户勾选的应用解密与 URL 级过滤；支持证书绑定自适应旁路与 QUIC/H3 引导回退。
- **出站代理联动**：支持将流量转接至本地 SOCKS5（含 UDP ASSOCIATE）或 HTTP CONNECT 代理。
- **全景洞察与诊断工具**：支持悬浮窗与状态栏实时网速、按 UID 流量消耗统计排行、Ping 延迟 / Traceroute / DNS 手动解析诊断与快捷设置磁贴（Quick Settings Tile）。
- **个性化与智能化**：支持 Material 3 动态取色、深浅主题与自定义背景；支持配置导入导出；集成可选的私有 LLM API 助手（BYOK，默认关闭，仅用于域名分析与研判）。

### 💻 Windows 桌面端专属特性
- **双二进制协作架构**：特权服务（`diting-service.exe`，管理员权限后台守护）负责网卡与网络核心；桌面 GUI（`diting-gui.exe`，普通权限免 UAC）负责可视化交互，两者通过本地 IPC 通信。
- **物理网卡双栈接管与安全自愈**：自动识别并接管活动物理网卡的 IPv4/IPv6 DNS 配置；接管前原子备份原始状态，程序退出或异常中断时全自动恢复；内置应急脱困（Emergency Restore）能力。
- **端口冲突检测与进程识别**：启动前自动探测 53 端口占用情况，精准定位占用进程名与 PID。
- **局域网独立 DNS 服务**：特权服务支持监听 `0.0.0.0:53` 与 `[::]:53`，内置一键放行 Windows 防火墙 53 端口（UDP 与 TCP）入站规则，供局域网外部设备将本机作为 DNS 枢纽。
- **局域网 Web 远程管理控制台**：服务内置 Web 仪表盘与 REST 接口（默认监听 15353 端口），集成管理员账号密码鉴权、安全 Session/Token 与防火墙 Web 端口放行，支持局域网其他设备通过浏览器远程管理。
- **系统集成**：支持一键注册与管理 Windows 系统服务、开机静默启动、界面截图捕获。

### 🧰 开发者桌面维护工具箱
- **桌面可视化交互**：基于 Python + PyWebView + 原生 WebView2 构建，双击 `maintenance/run_maintenance.bat` 即可启动图形化维护界面。
- **六大核心工坊能力**：
  - **🌐 DNS 调试诊断**：单次解析探测与多轮并发批量压测，统计平均延迟、耗时抖动与丢包率。
  - **📊 代码规模扫描**：递归扫描源码文件，严格检查单文件行数（遵循不超过 600 行的项目规范）。
  - **🎨 品牌 Logo 工坊**：一键预览与导出高清松石绿品牌 Logo（含 SVG 矢量图、各尺寸 PNG 与 Windows ICO 格式）。
  - **🔨 Windows 构建打包**：支持 Windows 特权服务、Wails 桌面端、NSIS 完整安装包的一键流水线构建与依赖工具链检测。
  - **🔖 统一版本管理**：跨 Go、NSIS、Wails、前端 package.json 等统一检测、同步版本号并生成校验信息。
  - **📸 界面自动截图**：基于无头 Edge 浏览器驱动前端开发服务器，自动化导出深浅双主题、多标签页与多分辨率的高清 UI 截图。

---

## 工作模式与平台支持矩阵

| 平台 | 模块 / 模式 | 最低系统要求 | 核心引擎与实现 | 核心特性与适用场景 |
|---|---|---|---|---|
| **Android** | ⚡ **极速模式** (Express) | Android 7.0+ (API 24)<br>`arm64-v8a` | **纯 Kotlin 原生**<br>轻量窄路由 TUN | **超轻量、极低功耗**。仅捕获 DNS 流量（53 端口），其余直接走物理网络；提供核心解析加速、4 种调度模式、规则拦截与缓存。适合老旧设备或注重省电的用户。 |
| **Android** | 🛡️ **普通模式** (Normal) | Android 10.0+ (API 29)<br>`arm64-v8a` | **Go 用户态协议栈**<br>(gVisor netstack + AAR) | **全功能网络管控**。全隧道接管，支持细粒度应用分流、可选 HTTPS 流量解密检查、出站代理联动、实时网速与流量排行。 |
| **Android** | 🏠 **服务器模式** (Server) | Android 10.0+ (API 29)<br>`arm64-v8a` | **Go 独立 DNS 服务**<br>(监听 `0.0.0.0:1053`) | **局域网共享 DNS**。供同一局域网下的 PC、路由器或电视接入解析，共享本地规则与缓存，不占用 VPN 槽位。 |
| **Windows** | ⚙️ **特权核心服务** (Service) | Windows 10+ (64-bit) | **Go 原生服务**<br>(Windows Service / CLI) | **底层接管与 DNS 核心**。双栈接管物理网卡、本地 53 端口监听、LRU 缓存与规则匹配、崩溃自愈、53 端口冲突检测。 |
| **Windows** | 🏠 **局域网 DNS 服务** (LAN DNS) | Windows 10+ (64-bit) | **Go 双栈监听**<br>(监听 `0.0.0.0:53` / `[::]:53`) | **局域网 DNS 枢纽**。供局域网内其他设备接入解析，支持一键配置 Windows 防火墙 53 端口 UDP/TCP 放行规则。 |
| **Windows** | 🖥️ **桌面图形控制台** (GUI) | Windows 10+ (64-bit)<br>WebView2 运行时 | **Wails v2 + Vue 3**<br>TypeScript + Material Web | **桌面交互与监控**。免管理员权限运行，提供实时查询流日志、服务商管理、缓存与规则配置、系统服务安装与启停、应急脱困与开机自启。 |
| **Windows** | 🌐 **局域网 Web 控制台** | 任意主流浏览器 | **嵌入式 Web 仪表盘**<br>(带管理员账号认证) | **跨设备远程管理**。局域网内任意手机、平板或 PC 无需安装客户端，直接通过浏览器访问 15353 端口管理 Windows 核心服务。 |

---

## 项目工程结构

```
DITING/
├── Android/                    # Android 客户端工程
│   ├── app/                    # Android 应用层源码（UI、Room 数据库、极速模式模块）
│   ├── tunnel/                 # Go 用户态网络栈与 DNS 隧道模块（编译为 tunnel.aar）
│   └── build_apk.bat           # Android 交互式构建、版本归档与 ADB 安装脚本
├── Windows/                    # Windows 桌面端工程
│   ├── cmd/
│   │   ├── gui/                # Wails GUI 调试入口
│   │   └── service/            # Windows 特权核心服务（CLI 与系统服务）源码
│   ├── internal/               # Windows 端核心实现（DNS 内核、平台适配、IPC、鉴权）
│   ├── frontend/               # Wails 前端界面源码（Vue 3 + TypeScript + Material Web）
│   ├── build/                  # Windows 构建输出、图标与 NSIS 打包脚本
│   ├── main.go                 # Wails 桌面客户端应用主入口
│   ├── build.bat               # Windows 端多目标流水线构建脚本
│   ├── set_version.bat         # Windows 端版本同步与检测脚本
│   └── wails.json              # Wails 项目配置文件
├── maintenance/                # 开发者桌面交互式工具箱 (Python + PyWebView)
│   ├── api.py                  # 工具箱前后端通信桥接层
│   ├── app.py                  # 工具箱桌面应用启动入口
│   ├── core/                   # 核心维护模块（构建、压测、扫描、Logo 导出、截图、版本管理）
│   ├── web/                    # 工具箱前端界面（HTML/CSS/JS）
│   └── run_maintenance.bat     # 工具箱一键启动脚本
├── docs/                       # 项目技术规范与维护文档
│   ├── development/            # 核心架构与开发指南（AAR 构建、Windows 规划、贡献者维护）
│   │   └── Archive/            # 历史设计方案与归档技术规范
│   └── assets/                 # 文档静态资源（收款码图片等）
├── avatars/                    # 赞助者与共建者头像资源（云控展示）
├── recognition_members.json    # 赞助者与共建者名单配置（云端热更新）
└── AGENTS.md                   # 项目开发与代码规范定义
```

---

## 环境要求与构建指南

### 📱 Android 客户端

#### 运行与构建要求
- **系统要求**：极速模式 Android 7.0+ (API 24+)；普通模式 / 服务器模式 Android 10.0+ (API 29+)。
- **硬件架构**：`arm64-v8a`。
- **构建环境**：JDK 11 或更高版本（推荐使用 Android Studio 自带 JBR）、Android SDK。

#### 构建命令
在 `Android/` 目录下使用 Gradle Wrapper：

```bash
cd Android

# 编译 Debug APK
./gradlew :app:assembleDebug --console=plain    # Windows 下使用 gradlew.bat

# 编译 Release APK
./gradlew :app:assembleRelease --console=plain
```

亦可在 Windows 下直接运行 `Android/build_apk.bat`：支持一键选择编译模式、自动归档产物，并可通过 ADB（支持无线调试）快速部署至真机。

构建产物路径：
- 标准 APK：`Android/app/build/outputs/apk/<buildType>/app-<buildType>.apk`
- 归档 APK：`Android/app/build/outputs/apk/versioned/<buildType>/DITING-<buildType>-v<versionName>.apk`

---

### 💻 Windows 桌面端

#### 构建环境要求
- **Go**：Go 1.23 或更高版本。
- **Node.js**：Node.js 18+ 与 npm。
- **Wails CLI**：Wails v2 (`go install github.com/wailsapp/wails/v2/cmd/wails@latest`)。
- **NSIS**（可选）：`makensis`（用于打包独立安装包）。

#### 构建方式

##### 1. 使用构建脚本（推荐）
在 `Windows/` 目录下运行 `build.bat`（自动调度 Python 构建引擎）：

```cmd
cd Windows

# 构建全部产物（特权服务 + GUI 客户端 + NSIS 安装包）
build.bat -t all -b release

# 仅构建特权服务 (diting-service.exe)
build.bat -t service -b release

# 仅构建 GUI 客户端 (diting-gui.exe)
build.bat -t gui -b release

# 仅打包 NSIS 独立安装包
build.bat -t installer -b release
```

构建产物默认生成在 `Windows/build/bin/` 目录下。

##### 2. 手动分步构建
```cmd
cd Windows

# 1. 编译特权服务
go build -ldflags "-s -w -H windowsgui -X main.Version=1.3.1" -o build/bin/diting-service.exe ./cmd/service

# 2. 编译 GUI 客户端
wails build -platform windows/amd64 -o diting-gui.exe

# 3. 打包 NSIS 安装包（需预先编译好服务与 GUI）
makensis -DPRODUCT_VERSION=1.3.1 -DOUTPUT_FILENAME=build/bin/DITING-release-v1.3.1.exe build/windows/installer/project.nsi
```

---

### 🧰 开发者桌面工具箱 (Maintenance Toolbox)

工具箱提供统一的可视化维护界面，免去记忆各类命令行参数的负担。

#### 环境要求
- Python 3.8+
- 安装依赖库：
  ```bash
  pip install pywebview dnspython pillow
  ```

#### 启动方式
双击运行项目根目录下的 `maintenance/run_maintenance.bat`，或在命令行中执行：

```bash
python maintenance/app.py
```

#### 版本号统一同步
如需发布新版本，可通过工具箱的「统一版本管理」模块更新，或使用快捷脚本执行全端检测与同步：

```cmd
.\Windows\set_version.bat 1.3.2
```

---

## 技术栈一览

- **Android 客户端**：Kotlin / Jetpack Compose / Material 3 / Coroutines & Flow / Room / DataStore / VpnService / OkHttp / WorkManager
- **Windows 桌面端**：Go 1.23+ / Wails v2 / Vue 3 / TypeScript / Vite / @material/web (Material 3) / Win32 API / Windows Service
- **核心 DNS 引擎**：Go / gVisor netstack (Android) / miekg/dns / quic-go / Singleflight
- **维护工具箱**：Python 3 / PyWebView (WebView2) / HTML5 / CSS3 / JavaScript

---

## 开发与参考文档

项目技术规范与深度设计文档归档于 `docs/development/` 目录：

- [Windows 端基础 DNS 内核架构设计与分阶段开发规划](docs/development/windows-dns-kernel-roadmap.md) — Windows 端双进程架构、网卡接管与恢复状态机、IPC 与 Pipeline 详细设计。
- [Go AAR 构建记录](docs/development/aar-build-notes.md) — Android 端 Go 隧道 AAR（`tunnel.aar`）的编译环境、构建参数与跨平台交叉编译细节。
- [云控贡献者名单维护说明](docs/development/recognition-members.md) — 赞助者与共建者名单的云控机制、配置 JSON 规范与头像资源维护指南。
- [AdGuard 规则修饰符语法参考（历史归档）](docs/development/Archive/adguard-rule-modifier-syntax-reference.md) — AdGuard 规则语法与 `$modifier` 规范整理，包含规则引擎适配说明。
- [Android 签名证书管理与发布签名规范（历史归档）](docs/development/Archive/android-signing-certificate-management.md) — 4096 位 Android 正式发布签名证书技术规格、指纹与打包流程。
- [极速模式架构设计与技术规范（历史归档）](docs/development/Archive/express-mode-architecture.md) — 极速模式（Express Mode）窄路由数据面、DNS 劫持清单与取舍说明。

---

<a id="sponsorship"></a>

## 赞助支持

如果您觉得谛听对您有所帮助，欢迎赞助支持本项目的开发与维护。付款时请备注您的昵称，以便同步加入项目赞助者名单。

| 支付宝付款码 | 微信付款码 |
| :---: | :---: |
| ![支付宝付款码](docs/assets/alipay_code.png) | ![微信付款码](docs/assets/wechatpay_code.png) |

关于赞助者与共建者名单的动态展示机制与头像提交规范，请参阅 [云控贡献者名单维护说明](docs/development/recognition-members.md)。

---

## 作者与开源协议

- **作者**：[haoze-evolluling](https://github.com/haoze-evolluling)
- **开源协议**：本项目基于 [GNU General Public License v3.0 (GPL-3.0)](https://www.gnu.org/licenses/gpl-3.0.html) 协议开源。
