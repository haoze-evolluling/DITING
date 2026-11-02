# 谛听 (DITING)

谛听（DITING）是一款本地优先的开源 DNS 加速与网络流量过滤工具，提供低延迟解析、规则阻断、防追踪与流量管控。全部处理在设备本地闭环完成，不上传远程数据；支持 Android、Windows、Linux 三端，并提供开发者维护工具箱。

- 📱 **Android**：`android/`（Flutter 架构）自带 Go 隧道引擎源码（`engine/`，gomobile 编译为 AAR），支持极速模式、普通模式（gVisor netstack 全隧道）与局域网独立 DNS 服务，要求 Android 9.0+（`arm64-v8a`）。
- 💻 **Windows**：特权系统服务 + Flutter 桌面端 + 局域网 Web 控制台，支持物理网卡双栈 DNS 接管与崩溃自愈。
- 🐧 **Linux**：单二进制 `diting-service` + 内嵌 Web 控制台，systemd 托管，自动适配多种 DNS 后端。
- 🧰 **维护工具箱**：Python + PyWebView 桌面套件，涵盖压测、代码扫描、Logo 导出、跨端构建与版本同步。

---

## 核心特性

### 📡 DNS 解析与调度
- **多协议**：UDP/TCP 53、DNS-over-HTTPS（DoH）、DNS-over-TLS（DoT）。
- **四种调度**：单一服务（Single）、智能优选（Smart EWMA）、最快响应（Fastest 并发竞速）、依次尝试（Sequential 备援）。
- **服务商管理**：内置阿里、腾讯、Cloudflare、Google、DNSPod 等，支持自定义节点。
- **Bootstrap 与防绕过**：内置/自定义 Bootstrap IP 解析加密上游域名；启用 DDR 拦截 `_dns.resolver.arpa`，防止绕过本地通道。

### ⚡ 缓存与容灾
- **分片 LRU 缓存**：64 分片并发安全缓存，支持跟随 TTL、平衡、高命中等多档策略。
- **乐观容灾**：上游超时或抖动时，在宽限期内复用过期缓存（Stale-While-Revalidate）。
- **并发合并**：Singleflight 合并同一域名的并发请求，降低上游负载并防止缓存击穿。

### 🛡️ 规则引擎与地址覆写
- **多维度匹配**：域名黑白名单，兼容 AdGuard 语法、通配符与正则；Trie 前缀树 + Bloom 过滤器加速，支持网页元素隐藏（Cosmetic）规则。
- **规则订阅**：AdGuard 格式远程订阅，支持分组、镜像源加速与后台定时更新。
- **静态覆写**：A/AAAA 记录静态地址覆写与 CNAME 重定向解析。
- **阻断响应**：支持零地址（`0.0.0.0` / `::`）、NXDOMAIN、NODATA、REFUSED 四种行为。

### 📱 Android 专属
- **应用分流**：排除应用（Bypass 直连）、禁止联网、应用白名单。
- **可选 HTTPS 检查**：基于 gVisor netstack 与本地 CA，仅对勾选应用解密和 URL 级过滤；支持证书绑定旁路与 QUIC/H3 回退。
- **出站代理**：本地 SOCKS5（含 UDP ASSOCIATE）或 HTTP CONNECT。
- **洞察与诊断**：悬浮窗/状态栏网速、按 UID 流量排行、Ping/Traceroute/DNS 诊断、快捷设置磁贴。
- **个性化**：Material 3 动态取色、深浅主题、配置导入导出；可选 BYOK LLM 助手（默认关闭）。

### 💻 Windows 专属
- **双二进制架构**：`diting-service.exe`（管理员权限）负责网络核心，`diting_desktop.exe`（Flutter，免 UAC）负责交互，经本地 IPC 通信。
- **双栈接管与自愈**：自动接管活动物理网卡 IPv4/IPv6 DNS，接管前原子备份，退出或异常时自动恢复，支持应急脱困。
- **端口冲突检测**：启动前探测 53 端口占用，定位进程名与 PID。
- **局域网 DNS 服务**：监听 `0.0.0.0:53` 与 `[::]:53`，一键放行 Windows 防火墙 UDP/TCP 入站。
- **局域网 Web 控制台**：默认 15353 端口，管理员鉴权、Session/Token 与防火墙放行，支持浏览器远程管理。
- **系统集成**：Windows 服务注册与管理、开机静默启动、系统托盘（关闭窗口隐藏到托盘，托盘菜单可直接启停/重启核心服务、开关开机自启与退出程序）。

### 🐧 Linux 专属
- **单二进制交付**：`diting-service` 内嵌 Flutter Web 控制台；systemd 托管，开机自启、异常重启。
- **多后端接管**：自动适配 systemd-resolved（`resolvectl`）→ NetworkManager（`nmcli`）→ `/etc/resolv.conf`，接管前快照、退出还原、崩溃自愈，并生成离线 `restore-dns.sh`。
- **stub 冲突处置**：识别 `127.0.0.53:53` / `127.0.0.54:53` 占用，可写入 `DNSStubListener=no` drop-in 并重启服务。
- **防火墙适配**：探测 firewalld / ufw / nftables / iptables 并维护放行规则；无防火墙管理器时降级为诊断提示。
- **FHS 目录**：配置在 `/etc/diting`、数据在 `/var/lib/diting`，支持 `DITING_DATA_DIR` 整体覆盖。
- **Web 控制台**：内嵌仪表盘默认 15353 端口，支持管理员鉴权与全功能远程配置。

### 🧰 维护工具箱
- 基于 Python + PyWebView + WebView2，双击 `desktop/toolbox/run_maintenance.bat` 即可启动。
- 五大工坊：DNS 诊断压测、代码规模扫描、品牌 Logo 导出、跨端构建打包、版本号维护。

---

## 平台支持矩阵

| 平台 | 模式 | 最低要求 | 说明 |
|---|---|---|---|
| **Android** | ⚡ 极速模式 | Android 9.0+ / `arm64-v8a` | Go 引擎 + DNS 窄路由：TUN 只接管 53 端口与公共 DNS 劫持地址，其余流量直连物理网络，轻量省电 |
| **Android** | 🛡️ 普通模式 | Android 9.0+ / `arm64-v8a` | gVisor 全隧道，支持应用分流、HTTPS 检查、出站代理 |
| **Android** | 🏠 服务器模式 | Android 9.0+ / `arm64-v8a` | Go 独立 DNS 服务，监听 `0.0.0.0:1053`，共享给局域网设备 |
| **Windows** | ⚙️ 特权核心服务 | Windows 10+ 64-bit | 双栈接管物理网卡、本地 53 监听、缓存规则、局域网 DNS、崩溃自愈 |
| **Windows** | 🖥️ 桌面 GUI | Windows 10+ 64-bit | Flutter 原生窗口，免管理员权限管理服务与实时日志；关闭窗口隐藏到系统托盘 |
| **Windows** | 🌐 Web 控制台 | 任意主流浏览器 | 访问 15353 端口远程管理 Windows 核心服务 |
| **Linux** | ⚙️ 核心服务 | systemd 发行版 / `amd64`·`arm64` | 多后端 DNS 接管、53 监听、缓存规则、局域网 DNS、离线还原 |
| **Linux** | 🌐 Web 控制台 | 任意主流浏览器 | 访问 15353 端口完成全部配置，无需桌面环境 |

> 三种 Android 模式均由 `android/app` 客户端提供，共用同一套 Go 引擎源码（`android/engine/`，按架构编译为
> `tunnel-arm64/x64/all.aar`），读取 2.2.9 的配置与数据库；部分页面数据仍为演示。

---

## 工程结构

```
DITING/
├── android/                   # Android 端专属代码
│   ├── app/                   #   Flutter Android 客户端：lib、test、android/ 原生壳、build_apk.bat
│   └── engine/                #   Go 隧道引擎源码与 build_aar.ps1
├── desktop/                   # 桌面端专属代码
│   ├── app/                   #   Flutter Windows 桌面窗口 + web/（局域网 Web 控制台）
│   ├── service/               #   Go 特权服务 diting-service、IPC、内嵌前端产物
│   ├── toolbox/               #   Python + PyWebView 开发者维护工具箱（assets/brand 为品牌矢量源）
│   └── build_installer.bat    #   构建桌面端安装包（Windows EXE / Linux deb）
├── shared/                    # 两端共用的 Flutter 设计系统、主题、l10n、配置与 SQLite 读取（GPL-3.0）
├── docs/                      # 开发文档与静态资源
├── avatars/                   # 赞助者与共建者头像
├── recognition_members.json   # 赞助者与共建者名单
├── pubspec.yaml               # Flutter pub workspace 根（一份 lockfile）
├── AGENTS.md                  # 开发与代码规范
└── README.md
```

各平台的日常工作说明见 [`android/README.md`](android/README.md)、[`desktop/README.md`](desktop/README.md)
与 [`shared/README.md`](shared/README.md)。

> **引擎说明**：Go 隧道引擎源码位于 `android/engine`，工程自含源码与 AAR 构建入口
> （`build_aar.ps1`）。三种工作模式共用同一引擎，差异只在 TUN 路由范围：极速模式仅接管 DNS，
> 普通模式接管全网络，服务器模式不建隧道。AAR 为构建产物、不入库，首次打包前需本地生成。


---

## 构建指南

### 📱 Android（`android/app`）

要求 Flutter 3.47+、JDK 11+、Android SDK；最低 Android 9.0（API 28），Release 产物架构为 `arm64-v8a`。
隧道引擎 AAR 不入库，首次构建前先在 `android/engine` 执行 `pwsh -File build_aar.ps1`
生成 `tunnel-arm64.aar`（模拟器或 debug 包用 `-Arch x64` / `-Arch all`）。

```bash
flutter pub get                # 工作区根：一次解析 shared + 两个 app
flutter analyze
cd android/app
flutter test
```

日常打包运行 `android/app/build_apk.bat`，交互式选择编译档位并自动归档：

| 档位 | 编译模式 | 签名 | Flutter 库架构 | 隧道引擎架构 | 可安装的设备 |
| --- | --- | --- | --- | --- | --- |
| 1 | Debug | Debug Key | `arm64-v8a`+`x86_64` | 双 ABI 一体 | ARM 手机/平板 **与 x86_64 模拟器** |
| 2 | Debug | Release Key | `arm64-v8a`+`x86_64` | 双 ABI 一体 | 同上（可覆盖安装正式包） |
| 3 | Release | Release Key | `arm64-v8a` | 仅 arm64 | ARM 手机/平板（默认档位） |
| 4 | Release | Release Key | `x86_64` | 仅 x86_64 | **仅 x86_64 模拟器** |
| 5 | — | — | — | — | 清理编译缓存与构建产物（`flutter clean` + `gradlew clean`） |

**架构匹配注意**：3 档打的是 arm64 引擎（`tunnel-arm64.aar`），4 档打的是 x86_64 引擎
（`tunnel-x64.aar`），1/2 档 debug 打的是双 ABI 一体引擎（`tunnel-all.aar`，真机与模拟器同包
通用）。三种 AAR 都是构建产物、**不入库**：全新克隆后首次打包前，先在 `android/engine`
执行 `pwsh -File build_aar.ps1`（或 `-Arch x64` / `-Arch all`）生成；`build.gradle.kts` 按
`-PditingAbi` / `--target-platform` 自动选用，缺文件时
构建报错并提示。把 3/4 档的包装到不匹配的设备上会报「安装失败 / 安装包与系统不兼容」。
另外所有 debug 构建共用同一输出文件 `app-debug.apk`，磁盘上的产物永远是**最后一次**构建的
结果——装设备前先看构建日志里的 `Tunnel engine ABI` 行确认。

为缩小安装包体积，Release 档位以 `-PditingAbi=<abi>` 构建单架构包，并通过
`-PditingCompressNativeLibs=true`（默认）对 `.so` 使用 legacy 打包（安装时解压）。
详情见 [Go AAR 构建记录](docs/development/aar-build-notes.md)。

### 🖥️ Flutter 桌面端（`desktop/app`）

要求 Flutter 3.47+、Visual Studio「使用 C++ 的桌面开发」工作负载（`flutter doctor -v` 中
Visual Studio 一栏为 OK），并开启 Windows 开发者模式（`start ms-settings:developers`，
插件符号链接需要）。入口 `lib/main.dart`，共享代码来自 `shared`。

```bat
desktop\build_installer.bat            :: 构建 Windows EXE 安装包
desktop\build_installer.bat both       :: EXE + Linux deb
```

手动等价命令（从源码运行窗口，不打包）：

```bash
cd desktop/app
flutter run -d windows
flutter build windows --release
```

### 💻 Windows
要求 Go 1.25+、Flutter 3.47+、Visual Studio「使用 C++ 的桌面开发」工作负载；打包独立安装包需 NSIS（可选）。

```cmd
cd desktop\service
build.bat
```

一键构建 Windows EXE 安装包，纯净产物输出至 `desktop/service/build/bin/DITING-release-v*.exe`。构建脚本会先构建 Flutter Web 控制台、Flutter Windows 桌面端与特权服务，再交给 NSIS 打包，并自动注入版本、提交与构建时间。

需要自定义目标或双平台打包时：`python desktop\toolbox\core\build_manager.py -t both -b release`。

<details>
<summary>手动编译二进制</summary>

```cmd
cd desktop\service

REM 构建 Web 控制台产物（服务 embed 需要）
python build_frontend.py

REM 编译特权服务
go build -ldflags "-s -w -H windowsgui" -o build/bin/diting-service.exe ./cmd/service

REM 编译 Flutter 桌面端
cd ..\app
flutter build windows --release
```
</details>

### 🐧 Linux
要求 Go 1.25+；生成 `.deb` 需 `dpkg-deb`（可选）。

```bash
cd desktop/service
./build_linux.sh --package            # 当前架构
./build_linux.sh -a arm64 --package   # 指定 amd64 / arm64 / arm
```

在 Windows 上可通过 `build_deb.bat` 打包：Windows 本机 Go 交叉编译 Linux 二进制，WSL 仅用 `dpkg-deb` 组装，无需在 WSL 内安装 Go。产物为 `desktop/service/build/bin/` 下的 `.deb` 或单二进制。

安装为 systemd 服务：

```bash
cd desktop/service/build/linux
sudo ./install.sh --bin ../../build/bin/diting-service
systemctl status diting-dnsservice
```

管理地址：`http://127.0.0.1:15353`。卸载：`sudo ./uninstall.sh`（保留配置），加 `--purge` 一并清理。

WSL 调试时 53 端口可能被 systemd-resolved stub 占用，建议用 `DITING_DATA_DIR` 重定向数据并以非特权端口验证。

<details>
<summary>手动交叉编译</summary>

```bash
cd desktop/service
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -trimpath -ldflags "-s -w" \
  -o build/bin/diting-service ./cmd/service
```
</details>

### 🧰 维护工具箱
要求 Python 3.8+。首次运行可执行：

```bash
python -m pip install -r desktop/toolbox/requirements.txt
python desktop/toolbox/app.py
```

也可直接双击 `desktop/toolbox/run_maintenance.bat`：脚本会检测缺失依赖并自动安装，异常退出时保留窗口以便查看报错。

版本号维护在工具箱的「版本号维护」页完成：Flutter Android / 桌面端（`android/app/pubspec.yaml`、`desktop/app/pubspec.yaml`）是常用入口；服务端 / NSIS 的版本号维护已折叠归档，仅在需要时展开。命令行等价用法：

```cmd
REM 同步 Flutter 客户端版本（构建号自动按 major*10000+minor*100+patch 推导，只增不减）
python desktop/toolbox/core/version_manager.py 2.0.2 -g flutter

REM 同步服务端等其余模块（示例）
.\desktop\service\set_version.bat 2.2.9 -g common
```

---

## 技术栈

- **Android**：Flutter / Dart 3 / Riverpod / go_router / sqflite（直接打开 2.2.9 的库）/ 移植的 Material 3 设计系统 / Kotlin 原生通道（VpnService、快捷磁贴、悬浮窗）
- **Windows**：Go 1.25+ / Flutter / Dart / Win32 API / Windows Service
- **Linux**：Go 1.25+ / systemd / resolvectl / nmcli / netlink / Flutter 内嵌控制台
- **DNS 引擎**：Go / gVisor netstack / miekg/dns / quic-go / Singleflight
- **维护工具箱**：Python 3 / PyWebView (WebView2) / HTML5 / CSS3 / JavaScript

---

## 开发文档

- [Go AAR 构建记录](docs/development/aar-build-notes.md) — Android `tunnel.aar` 的编译环境、参数与交叉编译细节。
- [云控贡献者名单维护](docs/development/recognition-members.md) — 名单云控机制、JSON 规范与头像维护。

---

<a id="sponsorship"></a>

## 赞助支持

如果谛听对您有帮助，欢迎赞助支持项目开发。付款时请备注昵称，以便同步加入赞助者名单。

| 支付宝付款码 | 微信付款码 |
| :---: | :---: |
| ![支付宝付款码](docs/assets/alipay_code.png) | ![微信付款码](docs/assets/wechatpay_code.png) |

名单展示机制与头像提交规范见 [云控贡献者名单维护说明](docs/development/recognition-members.md)。

---

## 作者与开源协议

- **作者**：[haoze-evolluling](https://github.com/haoze-evolluling)
- **开源协议**：[GNU General Public License v3.0 (GPL-3.0)](https://www.gnu.org/licenses/gpl-3.0.html)
