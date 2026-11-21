# 谛听 DITING

谛听（DITING）是一个以本地 DNS 为核心的网络过滤与隐私工具。域名解析、规则匹配、缓存与日志都在设备本机完成，不依赖云端服务。

项目包含 Android 客户端与桌面端服务：

- Android 客户端：Flutter 界面、Kotlin 系统集成与 Rust 数据面，提供普通、极速、服务器三种工作模式。
- 桌面端：仅保留 Rust 特权服务后端，负责系统 DNS 接管、局域网 DNS 服务与管理 API；Flutter 前端界面已移除。

Android 应用 ID 为 `com.haoze.diting`，最低支持 Android 9（API 28）。

## 主要能力

### DNS 解析

- 上游服务商：DoH、DoT 与传统 UDP/TCP DNS，可自定义服务商与上游节点。
- 引导解析（Bootstrap）：用于首次解析加密上游域名。
- 解析策略：单一服务、智能选择、最快响应、依次尝试。
- 解析缓存：开关、容量、TTL 上下限、排除规则与落盘持久化；极速模式使用 64 分片 LRU。
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

- 普通模式全隧道接管，支持按应用规则、禁止联网应用与绕过直连应用。
- 实时连接监控、应用洞察、连接地图与按应用上下行流量统计。
- 按应用限制 DNS 查询速率与新建连接数。
- 网络档案：按 SSID、计费网络、漫游等网络条件切换配置。
- 按需连接：仅在满足指定网络条件时建立隧道。
- 出站代理：把过滤后的流量转发到 SOCKS5 或 HTTP CONNECT 代理。
- HTTPS 检查：对指定应用解密 HTTP(S) 流量，支持域名与 URL 过滤，需要安装并信任本地 CA 证书。
- Root 免 VPN DNS 接管：已 Root 设备可在普通模式下不申请 VPN 权限，直接把本机 DNS 重定向到内置引擎。

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
- 加密 DNS 服务：以 DoT、DoH、DoQ 向局域网提供加密解析，支持自签证书与 PEM/PKCS#12 导入。
- 上游解析、缓存、自定义重写、规则订阅、自定义规则、时间计划与应用拦截。
- 安全隐私：协议加固、ECS 隐私、DNS 重绑定与 hosts 防御。
- 查询日志、客户端分组流量统计与规则检测。
- 管理 API：HTTP/WebSocket，带认证与 CORS。
- 服务托管：Windows 通过 SCM 注册系统服务，Linux 提供 deb 安装包与服务注册命令。

## 工作模式

Android 客户端在首次启动时选择工作模式，之后可在设置中切换。切换时会先停止当前模式的服务，各模式的规则、缓存与日志相互独立。

| 模式 | 数据面 | 特点 |
| --- | --- | --- |
| 普通模式 | `VpnService` + TUN 全隧道，Rust 引擎接管全部流量 | 功能最完整：规则、HTTPS 检查、按应用分流、流量统计 |
| 极速模式 | 窄路由，仅接管 DNS 端口，其余流量直连物理网络 | 功耗更低，四种上游调度，64 分片 LRU 缓存 |
| 服务器模式 | 独立 Rust 进程监听 53 或 1053 端口 | 为局域网设备提供 DNS 过滤、缓存与查询日志 |

### 普通模式

Rust 引擎接管全部流量，支持应用分流、按应用拦截、HTTPS 检查、出站代理、按 UID 的连接日志与流量统计。可选启用 Root 免 VPN DNS 接管：在已获取 Root 权限的设备上，引擎以应用 UID 运行并监听回环地址，由 `iptables`/`ip6tables` 把 53 端口流量重定向到该端口，同时安装 INPUT 丢弃链避免成为局域网开放解析器。该方式只接管本机 DNS，不提供 TUN 数据面的分流、HTTPS 检查或按应用日志。

### 极速模式

只把 DNS 端口收窄接管，其他流量直连物理网络。适合只需要 DNS 过滤、希望降低功耗的场景，要求 Android 9+ 的 64 位设备。

### 服务器模式（Android）

服务器模式把数据面与控制面分离：`rust/diting-server` 作为独立长驻进程复用桌面 DNS 栈，Flutter 管理端通过 MethodChannel 启停进程，并通过应用私有 Unix Domain Socket 读写运行中配置。Root 设备监听 53 端口并降权到应用 UID，非 Root 设备监听 1053 端口。进程输出写入 `server.log`，查询日志按日保存为 JSONL。

## 技术架构

### 仓库布局

| 目录 | 内容 |
| --- | --- |
| `shared/` | `diting_shared`：Flutter 设计系统、主题、双语本地化、路由分支，以及共用的偏好与数据库封装 |
| `android/app/` | `diting_android`：Android Flutter 界面、Kotlin 系统集成、Gradle 工程与 APK 构建脚本 |
| `desktop/service/` | 桌面服务构建与打包资产、版本真源 `VERSION` 与 Linux 打包脚本 |
| `desktop/toolbox/` | Python 构建、版本管理、打包与环境预检工具 |
| `rust/` | Rust 工作区：DNS/规则内核、Android 隧道引擎、桌面服务与服务器进程 |
| `docs/development/` | 构建环境、Root 接管、服务器模式、桌面迁移与存储迁移说明 |
| `avatars/`、`recognition_members.json` | 云控赞助者名单与头像 |
| `LearningObjects/` | 第三方项目的本地参考副本，不参与本项目的构建 |

### Android 运行时

界面由 Flutter 构建，Kotlin 负责 Android 系统能力，Rust 负责数据面：

- Flutter 通过 MethodChannel 与 Kotlin 通信，覆盖 VPN、Root DNS、服务器、自动化、通知、存储与诊断等通道。
- Kotlin 实现 `DitingVpnService`（普通模式）、`ExpressVpnService`（极速模式）、`RootDnsService`、`ServerDnsService`，以及前台服务、唤起广播、快捷磁贴、桌面小组件与悬浮日志窗。
- `libditing_native.so` 是单一 cdylib，链接隧道引擎、全部 Flutter/Kotlin 侧内核和服务器运行时；`libditing_server.so` 是服务器模式的极小启动器，加载同一份原生库后调用 `diting_server_main`。
- 数据存储使用 SQLite：三种模式各自的规则库与日志库，加上一个全局自动化库，共 7 个 V2 数据库。服务器模式另有独立的 `files/server/` 目录与 JSONL 查询日志。

Rust 内核包括 DNS 线格式、解析器调度、上游传输、缓存、策略与规则匹配、Bootstrap、HTTPS 检查（证书与 MITM）、出站代理、TUN 网络栈、嗅探、日志与流量统计、自动化、订阅、备份、诊断探测、IP 质量与更新检查等模块。

### 桌面端运行时

`diting-service` 是纯 Rust 特权服务，负责：

- 启动与管理 DNS 监听（UDP、TCP，以及 DoT、DoH、DoQ 加密服务）。
- 接管系统 DNS、配置防火墙、诊断端口占用，并在退出或异常时恢复原配置。
- 提供 HTTP/WebSocket 管理 API，默认监听 `127.0.0.1:15353`，包含认证与 CORS。

桌面端不再内置前端界面，管理 API 由外部调用方直接访问。

桌面端数据目录：

- Windows：`%ProgramData%\DITING`
- Linux root：`/etc/diting` 与 `/var/lib/diting`
- Linux 非 root：`~/.diting`
- 可用环境变量 `DITING_DATA_DIR` 覆盖

### Rust 工作区

Rust 工作区按职责分为三组，另有测试与兼容支持 crate：

| 分组 | 主要 crate | 职责 |
| --- | --- | --- |
| 共用 DNS/规则内核 | `diting-dns-wire`、`diting-rule-core`、`diting-policy-core`、`diting-dns-cache-core`、`diting-filter-core`、`diting-rewrite-core`、`diting-upstream-core`、`diting-resolver-core`、`diting-mitm-core`、`diting-cert-core`、`diting-log-core` 等 | 解析、规则解析与匹配、缓存、上游传输、HTTPS 检查、日志与统计 |
| Android 数据面与内核 | `diting-engine`、`diting-kernels`、`diting-native`、`diting-server`、`diting-server-launcher` | 隧道引擎、UI 侧内核、合并原生库与服务器进程 |
| 桌面服务 | `diting-desktop-api`、`diting-desktop-core`、`diting-desktop-dns`、`diting-desktop-platform`、`diting-desktop-app`、`diting-desktop-ipc`、`diting-desktop-service` | 配置模型、引擎门面、DNS 数据面、平台能力、运行时、管理 API 与服务二进制 |
| 测试与兼容支持 | `diting-corpus`、`diting-mitm-spike`、`diting-netstack-spike`、`diting-tun-spike`、`diting-go-compat` | 基线语料、迁移阶段验证与 Go 标准库兼容辅助 |

## 环境要求

| 组件 | 要求 |
| --- | --- |
| Flutter / Dart | Flutter 3.50（beta 频道）与 Dart 3.14；工作区通过 `pubspec.yaml` 的 `workspace` 统一解析依赖 |
| Rust | 稳定版工具链与 Cargo，edition 2021 |
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

启动 Rust 服务：

```bash
cd rust
cargo run -p diting-desktop-service -- -run
```

服务默认在 `127.0.0.1:15353` 提供管理 API。系统 DNS 接管等特权操作需要管理员或 root 权限。

生成安装包：

```bat
desktop\build_installer.bat
desktop\build_installer.bat both
```

第一条命令生成 Windows EXE 安装包，第二条同时生成 Linux deb。完整流水线为：`diting-service` → NSIS / deb 安装包；版本号取自 `desktop/service/VERSION`，产物位于 `desktop\service\build\bin`。

Linux 单独构建：

```bash
cd desktop/service
./build_linux.sh --package
sudo diting-service -service install
```

`diting-service` 还提供 `-check-ports`、`-restore`、`-service install|uninstall`、`-config`、`-port`、`-ipc-addr` 与 `-token` 等参数。

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
- 桌面端配置文件、规则、缓存、证书与查询日志保存在上述数据目录，可通过 `DITING_DATA_DIR` 迁移。

## 参与与反馈

项目仓库：<https://github.com/haoze-evolluling/DITING>

问题反馈与功能建议请提交 Issue；代码贡献请提交 Pull Request，并遵循 `AGENTS.md` 中的代码规范与提交约定。

## 赞助

<a id="sponsorship"></a>

应用内“关于 - 赞助”页面提供赞助入口。赞助者名单由仓库根目录的 `recognition_members.json` 与 `avatars/` 维护，推送到 `main` 分支后对全部客户端生效，无需发版。

## 许可

本项目以 GNU General Public License v3.0 授权，完整条款见 `LICENSE`。
