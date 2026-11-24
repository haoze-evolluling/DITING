# 谛听 DITING

谛听（DITING）是一个以本地 DNS 为核心的网络过滤与隐私工具。域名解析、规则匹配、缓存与日志都在设备本机完成，不依赖云端服务。

项目包含 Android 客户端与桌面端服务：

- Android 客户端：Flutter 界面、Kotlin 系统集成与 Rust 数据面，提供普通、简洁、服务器三种工作模式。
- 桌面端：Rust 特权服务负责系统 DNS 接管、局域网 DNS 服务与管理 API；管理界面由服务内嵌并托管的 React Web 管理页提供，同时支持 Windows、Linux 与 OpenWrt 路由器。

Android 应用 ID 为 `com.haoze.diting`，最低支持 Android 9（API 28）。

## 主要能力

### DNS 解析

- 上游服务商：DoH、DoT 与传统 UDP/TCP DNS，可自定义服务商与上游节点。
- 引导解析（Bootstrap）：用于首次解析加密上游域名。
- 解析策略：单一服务、智能选择、最快响应、依次尝试。
- 解析缓存：开关、容量、TTL 上下限、排除规则与落盘持久化（64 分片 LRU）。
- 域名覆写：把域名指向指定 IPv4、IPv6、CNAME 或 TXT。
- DNS64：在 IPv6-only 网络中用 `64:ff9b::/96` 前缀从 A 记录合成 AAAA。
- DNS 隐私：阻断 HTTPS/SVCB 记录与 DNS 重绑定保护（Android）；协议加固与 ECS 子网隐私（桌面端）。
- 网络诊断：DNS 查询、Ping、Traceroute、测速、DNS 延迟与 DNS 泄漏检测。
- Captive Portal 检测：判断网络是否需要登录门户。

### 规则与拦截

- 在线规则订阅与本地规则文件，支持 AdGuard/Adblock 语法、hosts 与 dnsmasq 行格式。
- 自定义黑名单、白名单、域名覆写与规则检测。
- 拦截方式：应答模式、阻断地址、订阅更新周期、临时暂停与时间计划。
- 内置应用与网站规则，可整组拦截并按周计划放行。
- 订阅版本历史：记录规则快照，支持差异对比与一键回滚。
- 规则解析、索引、快照与命中统计由 Rust 内核完成。

### 应用与网络（Android）

- 普通与简洁模式全隧道接管，支持按应用规则、禁止联网应用与绕过直连应用。
- 实时连接监控、应用洞察、连接地图与按应用上下行流量统计。
- 按应用限制 DNS 查询速率与新建连接数。
- 网络档案：按 SSID、计费网络、漫游等网络条件切换配置。
- 按需连接：仅在满足指定网络条件时建立隧道。
- 出站代理：把过滤后的流量转发到 SOCKS5 或 HTTP CONNECT 代理。
- HTTPS 检查：对指定应用解密 HTTP(S) 流量，支持域名与 URL 过滤，需要安装并信任本地 CA 证书。
- Root 免 VPN DNS 接管：已 Root 设备可在普通与简洁模式下不申请 VPN 权限，直接把本机 DNS 重定向到内置引擎。

### 自动化与集成（Android）

- 场景自动化：定时、网络、状态与手动触发，支持条件组合和优先级。
- 自动化动作：暂停拦截、屏蔽服务、切换档案等。
- 时间表与档案管理。
- 外部控制：广播 `START` / `STOP` / `TOGGLE`、`diting://` 订阅深链、快捷设置磁贴、主屏小组件。
- 悬浮日志窗与前台服务常驻通知，可自定义通知详情与文案。

### 日志、数据与维护

- DNS 查询、HTTP 请求、解析竞速与 Bootstrap 日志。
- 实时统计、Top 域名/客户端排名、明细检索与日志导出。
- 日志保留策略与数据清理。
- 配置导入导出、备份与 WebDAV 传输。
- 故障排查：崩溃日志与运行日志的抓取、导出。
- 数据库健康检查与 Android 三模式存储 V2 迁移。
- 应用内检查更新并调起系统安装器（Android）。

### 桌面端

- 系统 DNS 接管：Windows 逐网卡接管，Linux 支持 systemd-resolved 等后端；提供紧急恢复与端口诊断。
- 局域网 DNS 服务：对外监听 53 端口，供路由器和终端共享解析与拦截。
- 客户端访问控制：限定可解析的局域网客户端，并按客户端限速。
- 加密 DNS 服务：以 DoT、DoH 向局域网提供加密解析，支持自签证书与 PEM/PKCS#12 导入。
- 上游解析、缓存、自定义重写、规则订阅、自定义规则、时间计划与应用拦截。
- 安全隐私：协议加固、ECS 隐私、DNS 重绑定与 hosts 防御。
- 查询日志、客户端分组流量统计与规则检测。
- 桌面管理端：React Web 管理页（由服务托管，浏览器访问），提供运行概览、DNS 启停、系统 DNS 接管、网络诊断、查询日志与 24 小时统计，并支持缓存策略与落盘、上游与 Bootstrap、域名条件分流与回退上游、规则订阅与服务拦截、时间计划、安全搜索与威胁情报、隐私加固与 Hosts/ECS/DNS64、域名重写与区文件、局域网访问控制与客户端分组、加密 DNS 与证书管理、Web 远程管理与管理员改密。
- 管理 API：HTTP/WebSocket，带认证与 CORS。
- 服务托管：Windows 通过 SCM 注册系统服务，Linux 提供 deb 安装包与服务注册命令，OpenWrt 提供 musl 静态链接的 `.ipk` 安装包与 `procd` 守护服务（支持「接管 53 端口」与「作为 dnsmasq 上游」双模式、`.lan` 本地域名回流、DHCP 租约设备名自动识别、局域网 53 端口 DNAT 重定向，以及 `/etc/diting` 与 `/tmp/diting` 冷热分离闪存保护）。

## 工作模式

Android 客户端在首次启动时选择工作模式，之后可在设置中切换。切换时会先停止当前模式的服务，各模式的规则、缓存与日志相互独立。

| 模式 | 数据面 | 特点 |
| --- | --- | --- |
| 普通模式 | `VpnService` + TUN 全隧道，Rust 引擎接管全部流量 | 规则、HTTPS 检查、按应用分流、流量统计 |
| 简洁模式 | 与普通模式相同的全隧道数据面，规则与日志另存一套 | 功能与普通模式完全一致，数据完全独立，功能中心默认少显示几类卡片（可恢复） |
| 服务器模式 | 独立 Rust 进程监听 53 或 1053 端口 | 为局域网设备提供 DNS 过滤、缓存与查询日志 |

### 普通模式

Rust 引擎接管全部流量，支持应用分流、按应用拦截、HTTPS 检查、出站代理、按 UID 的连接日志与流量统计。可选启用 Root 免 VPN DNS 接管：在已获取 Root 权限的设备上，引擎以应用 UID 运行并监听回环地址，由 `iptables`/`ip6tables` 把 53 端口流量重定向到该端口，同时安装 INPUT 丢弃链避免成为局域网开放解析器。该方式只接管本机 DNS，不提供 TUN 数据面的分流、HTTPS 检查或按应用日志。

### 简洁模式

与普通模式共用同一套全隧道数据面，路由、引擎能力、通知与统计行为完全一致，区别只在数据：规则库、日志库与偏好容器各自独立，两种模式互不影响。功能中心默认把「应用与网络」「高级与诊断」「数据与维护」三类卡片收进「隐藏功能」，需要时在功能中心 →「隐藏功能」里恢复。

Root 免 VPN DNS 接管在普通模式与简洁模式下都可启用，接管期间读取的是当前模式自己的规则库、日志库与偏好容器。

### 服务器模式（Android）

服务器模式把数据面与控制面分离：`rust/diting-server` 作为独立长驻进程复用桌面 DNS 栈，Flutter 管理端通过 MethodChannel 启停进程，并通过应用私有 Unix Domain Socket 读写运行中配置。Root 设备监听 53 端口并降权到应用 UID，非 Root 设备监听 1053 端口。进程输出写入 `server.log`，查询日志按日保存为 JSONL。

## 技术架构

### 仓库布局

| 目录 | 内容 |
| --- | --- |
| `shared/` | `diting_shared`：Flutter 设计系统、主题、双语本地化、路由分支，以及共用的偏好与数据库封装 |
| `android/app/` | `diting_android`：Android Flutter 界面、Kotlin 系统集成、Gradle 工程与 APK 构建脚本 |
| `desktop/service/` | 桌面服务构建与打包资产、版本真源 `VERSION` 与 Linux 打包脚本 |
| `desktop/ui/` | React Web 管理端；Vite 构建产物由服务嵌入并托管为 Web 管理页 |
| `desktop/toolbox/` | Python 开发者工具箱（DNS 调试、代码扫描、Logo 工坊、Android 版本维护）与安装包构建引擎 |
| `rust/` | Rust 工作区：DNS/规则内核、Android 隧道引擎、桌面服务与服务器进程 |
| `docs/development/` | 构建环境、Root 接管、服务器模式、桌面迁移与存储迁移说明 |
| `avatars/`、`recognition_members.json` | 云控赞助者名单与头像 |
| `LearningObjects/` | 第三方项目的本地参考副本，不参与本项目的构建 |

### Android 运行时

界面由 Flutter 构建，Kotlin 负责 Android 系统能力，Rust 负责数据面：

- Flutter 通过 MethodChannel 与 Kotlin 通信，覆盖 VPN、Root DNS、服务器、自动化、通知、存储与诊断等通道。
- Kotlin 用 `FullTunnelVpnService` 承载普通与简洁模式共用的全隧道逻辑，`DitingVpnService` / `ExpressVpnService` 只注入各自的模式参数与数据存储；另有 `RootDnsService`、`ServerDnsService`，以及前台服务、唤起广播、快捷磁贴、桌面小组件与悬浮日志窗。
- `libditing_native.so` 是单一 cdylib，链接隧道引擎、全部 Flutter/Kotlin 侧内核和服务器运行时；`libditing_server.so` 是服务器模式的极小启动器，加载同一份原生库后调用 `diting_server_main`。
- 数据存储使用 SQLite：三种模式各自的规则库与日志库，加上一个全局自动化库，共 7 个 V2 数据库。服务器模式另有独立的 `files/server/` 目录与 JSONL 查询日志。

Rust 内核包括 DNS 线格式、解析器调度、上游传输、缓存、策略与规则匹配、Bootstrap、HTTPS 检查（证书与 MITM）、出站代理、TUN 网络栈、嗅探、日志与流量统计、自动化、订阅、备份、诊断探测、IP 质量与更新检查等模块。

### 桌面端运行时

`diting-service` 是纯 Rust 特权服务，负责：

- 启动与管理 DNS 监听（UDP、TCP，以及 DoT、DoH 加密服务）。
- 接管系统 DNS、配置防火墙、诊断端口占用，并在退出或异常时恢复原配置。
- 提供 HTTP/WebSocket 管理 API，默认监听 `127.0.0.1:15353`，包含认证与 CORS。

服务同时托管内嵌的 Web 管理页：`rust/diting-desktop-ipc/build.rs` 在编译期读取
`desktop/ui/dist`，未构建前端时返回占位页。管理页通过回环地址访问同一套管理 API，
安装包会在公共桌面创建“谛听 DNS 管理页”快捷方式。

桌面端数据目录：

- Windows：`%ProgramData%\DITING`
- Linux root：`/etc/diting` 与 `/var/lib/diting`
- OpenWrt：核心配置与状态持久化在 `/etc/diting`（随 `sysupgrade` 保留），高频写入的查询日志默认独立存于内存盘 `/tmp/diting/querylog.db`（可在设置页切换至外置挂载磁盘）
- Linux 非 root：`~/.diting`
- 可用环境变量 `DITING_DATA_DIR` 覆盖

配置、规则正文、DNS 缓存、查询日志、接管状态与管理端会话统一保存在数据目录下的
`diting.db`（SQLite，WAL 模式）。证书 PEM/私钥、登录背景图与 `service.log` 仍保留为文件。
首次启动会把旧的 `config.json`、`filters/`、`querylog/`、`cache.json`、`dns_state.json`
导入数据库，成功后删除旧文件；导入失败时保留旧文件并在本次运行回退文件后端。

### Rust 工作区

Rust 工作区按职责分为三组，另有测试与兼容支持 crate：

| 分组 | 主要 crate | 职责 |
| --- | --- | --- |
| 共用 DNS/规则内核 | `diting-dns-wire`、`diting-rule-core`、`diting-policy-core`、`diting-dns-cache-core`、`diting-filter-core`、`diting-rewrite-core`、`diting-upstream-core`、`diting-resolver-core`、`diting-mitm-core`、`diting-cert-core`、`diting-log-core` 等 | 解析、规则解析与匹配、缓存、上游传输、HTTPS 检查、日志与统计 |
| Android 数据面与内核 | `diting-engine`、`diting-kernels`、`diting-native`、`diting-server`、`diting-server-launcher` | 隧道引擎、UI 侧内核、合并原生库与服务器进程 |
| 桌面服务 | `diting-desktop-api`、`diting-desktop-core`、`diting-desktop-dns`、`diting-desktop-platform`、`diting-desktop-app`、`diting-desktop-ipc`、`diting-desktop-sqlite`、`diting-desktop-service` | 配置模型、引擎门面、DNS 数据面、平台能力、运行时、SQLite 存储、管理 API 与服务二进制 |
| 测试与兼容支持 | `diting-corpus`、`diting-mitm-spike`、`diting-netstack-spike`、`diting-tun-spike`、`diting-go-compat` | 基线语料、迁移阶段验证与 Go 标准库兼容辅助 |

## 环境要求

| 组件 | 要求 |
| --- | --- |
| Flutter / Dart | Flutter 3.50（beta 频道）与 Dart 3.14；工作区通过 `pubspec.yaml` 的 `workspace` 统一解析依赖 |
| Rust | 稳定版工具链与 Cargo，edition 2021 |
| Node.js | 20 或更高，用于桌面管理端 Web 界面构建 |
| Python | 3.10 或更高，用于构建与验证脚本 |
| Android | JDK 17+、Android SDK、NDK；应用 `minSdk` 为 28，交叉编译使用 API 28 工具链 |
| Windows 打包 | Visual Studio 的“使用 C++ 的桌面开发”工作负载（提供 Rust MSVC 链接器）；生成 EXE 安装包还需 NSIS |
| Linux 打包 | Cargo；在 Windows 上生成 deb 需要 WSL |

Android 的 Gradle、AGP、Kotlin 版本与镜像配置见 `docs/development/android-build-environment.md`。

## 构建与运行

### 解析依赖与静态检查

在仓库根目录执行：

```bash
flutter pub get
flutter analyze
```

工作区根目录只负责统一解析依赖与静态检查，测试需要进入各包目录运行。

### Android

推荐使用交互式构建脚本：

```bat
android\app\build_apk.bat
```

脚本会先调用 `python rust\build_android.py` 生成原生库，再通过 `flutter build apk` 打包，支持 Debug/Release、arm64 与 x86_64 等组合。

手动构建：

```bash
python rust/build_android.py
cd android/app
flutter build apk --release
```

`rust/build_android.py` 默认构建 arm64-v8a 与 x86_64，并输出：

- `libditing_native.so`：隧道引擎、UI 内核与服务器运行时合并后的原生库。
- `libditing_server.so`：服务器模式启动器。

NDK 从 `ANDROID_NDK_HOME`、`ANDROID_NDK_ROOT` 或 `android/local.properties` 的 `sdk.dir` 下自动定位。

### 桌面端

#### 桌面服务

启动 Rust 服务：

```bash
cd rust
cargo run -p diting-desktop-service -- -run
```

服务默认在 `127.0.0.1:15353` 提供管理 API 与 Web 管理页。系统 DNS 接管等特权操作需要管理员
或 root 权限。

生成安装包：

```bat
desktop\build_exe.bat
desktop\build_deb.bat
desktop\build_ipk.bat -a both
```

第一条命令生成 Windows EXE 安装包，第二条生成 Linux deb（经 WSL），第三条通过 WSL 生成 OpenWrt `x86_64` 与 `aarch64` 的 `.ipk` 安装包。完整流水线为：`desktop/ui` 前端构建 → `diting-service` 编译（嵌入 Web 管理页）→ NSIS / deb / ipk 安装包；版本号取自 `desktop/service/VERSION`，产物位于 `desktop\service\build\bin`。构建前端需要 Node.js 与 npm，可用 `--skip-ui` 跳过并生成不带 Web 管理页的服务安装包。Windows 安装完成后会在公共桌面创建“谛听 DNS 管理页”快捷方式，用默认浏览器打开 Web 管理页。

Linux / OpenWrt 单独构建：

```bash
cd desktop/service
./build_linux.sh --package
./build_openwrt.sh --package -a both
```

OpenWrt 安装与使用（覆盖 OpenWrt 21.02–24.10 及 ImmortalWrt / iStoreOS 等衍生固件）：

```bash
opkg install diting_<版本>_openwrt_x86_64.ipk    # 或 aarch64 包
# 浏览器打开 http://<路由器LAN_IP>:15353 完成管理员初始化并开启路由器 DNS 接管
# 若忘记管理员密码，可通过 SSH 重置：
diting-service -reset-password <新密码>
```

`diting-service` 还提供 `-check-ports`、`-restore`、`-reset-password`、`-service install|uninstall`、`-config`、`-port`、`-ipc-addr` 与 `-token` 等参数。

#### 桌面管理端

管理端位于 `desktop/ui/`，使用 Vite + React 19 + TypeScript，构建产物由服务嵌入为 Web
管理页，通过浏览器访问 `http://127.0.0.1:15353/`。

```bash
cd desktop/ui
npm install
npm run dev            # 浏览器开发模式，/api 代理到 127.0.0.1:15353
npm run build          # 类型检查并构建前端到 desktop/ui/dist
```

需要连接其他端口的探测服务时，可设置 `DITING_DEV_API`，例如
`DITING_DEV_API=http://127.0.0.1:15355 npm run dev`。前端的 `npm run build` 必须在
`cargo build -p diting-desktop-service` 之前执行，服务才会嵌入最新的 Web 管理页。

### Rust 验证

在 `rust/` 目录执行基础检查：

```bash
cargo fmt --all --check
cargo clippy --all-targets -- -D warnings
cargo test
```

或使用统一验证脚本：

```bash
python rust/verify.py
python rust/verify.py --all
```

桌面管理端执行 `cd desktop/ui && npm run build` 进行类型检查与生产构建。前端开发说明见
`docs/development/desktop-ui.md`。

`verify.py` 默认运行格式检查、Clippy（警告视为错误）与所有 crate 的测试；可追加 `--android`、`--desktop`、`--engine`、`--smoke`、`--dart`、`--bench`。`--all` 依次运行 `--engine`、`--android`、`--desktop`、`--dart` 与 `--bench`，`--smoke` 需要单独指定。

### Flutter 测试

测试按包运行：

```bash
cd shared && flutter test
cd android/app && flutter test
```

首次运行前需要为 sqlite3 原生资源开启一次开关：

```bash
flutter config --enable-native-assets
```

项目使用 Flutter 原生资源（native assets）加载 sqlite3；不开启时测试会直接退出。工作区根目录不要直接运行 `flutter test android/app`，否则原生依赖与测试资源包无法按子包解析。

## 数据与隐私

- 解析、规则匹配、缓存与查询日志默认全部在本机完成，不要求登录账号或上传数据。
- AI 分析功能需要用户自行配置兼容 OpenAI 接口的服务地址与密钥；只有在用户主动发起分析时才访问该服务。
- 赞助者名单与头像从项目 GitHub 仓库的 `recognition_members.json` 与 `avatars/` 拉取，并缓存到本地；网络异常时使用上一次成功的缓存。
- 应用更新检查访问 GitHub Releases；Android 下载更新包后交给系统安装器处理。
- 桌面端的配置、规则、缓存、查询日志与会话保存在数据目录的 `diting.db` 中，证书与登录背景图保留为文件；可通过 `DITING_DATA_DIR` 迁移整个数据目录。

## 参与与反馈

项目仓库：<https://github.com/haoze-evolluling/DITING>

问题反馈与功能建议请提交 Issue；代码贡献请提交 Pull Request，并遵循 `AGENTS.md` 中的代码规范与提交约定。

## 赞助

<a id="sponsorship"></a>

应用内“关于 - 赞助”页面提供赞助入口。赞助者名单由仓库根目录的 `recognition_members.json` 与 `avatars/` 维护，推送到 `main` 分支后对全部客户端生效，无需发版。

## 许可

本项目以 GNU General Public License v3.0 授权，完整条款见 `LICENSE`。
