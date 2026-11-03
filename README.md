# 谛听 (DITING)

本地优先的开源 DNS 加速与流量过滤工具：低延迟解析、规则阻断、防追踪与流量管控全部在设备本地完成，
不上传数据。支持 Android、Windows 与 Linux，并附带开发者维护工具箱。

- 📱 **Android**：Flutter 客户端 + Go 隧道引擎（`android/engine`，gomobile 编译为 AAR），支持极速、
  普通（gVisor 全隧道）与局域网 DNS 服务三种模式，要求 Android 9.0+（`arm64-v8a`）。
- 💻 **Windows**：特权服务 + Flutter 桌面端 + 局域网 Web 控制台，支持物理网卡双栈 DNS 接管与崩溃自愈。
- 🐧 **Linux**：单二进制 `diting-service` 内嵌 Web 控制台，systemd 托管，自动适配多种 DNS 后端。
- 🧰 **维护工具箱**：Python + PyWebView，涵盖压测、代码扫描、Logo 导出、跨端构建与版本同步。

## 核心特性

- **解析与调度**：UDP/TCP、DoH、DoT；单一 / 智能优选（EWMA）/ 最快响应 / 依次尝试四种调度；
  内置主流服务商并支持自定义节点；Bootstrap IP 解析加密上游域名，DDR 拦截防绕过。
- **缓存与容灾**：64 分片并发 LRU 缓存，跟随 TTL / 平衡 / 高命中等策略；上游异常时宽限期复用过期缓存
  （Stale-While-Revalidate）；Singleflight 合并并发请求。
- **规则引擎**：域名黑白名单与 AdGuard 语法（通配符、正则、Cosmetic），Trie + Bloom 加速；
  远程订阅支持分组、镜像与定时更新；A/AAAA 静态覆写与 CNAME 重定向；四种阻断响应。
- **Android 专属**：应用分流与白名单、可选 HTTPS 检查（gVisor netstack + 本地 CA、证书绑定旁路、
  QUIC/H3 回退）、SOCKS5/HTTP 出站代理、悬浮窗与流量排行、Ping/Traceroute/DNS 诊断、快捷磁贴、
  Material 3 主题、配置导入导出、可选 BYOK LLM 助手（默认关闭）。
- **Windows 专属**：`diting-service.exe` 特权核心 + 免 UAC 的 Flutter 桌面端，本地 IPC；双栈 DNS 接管
  与原子备份/自动恢复；53 端口冲突检测与进程定位；局域网 DNS 与防火墙放行；15353 端口 Web 控制台
  （管理员鉴权）；服务注册、开机静默启动与系统托盘。
- **Linux 专属**：systemd 托管；自动适配 systemd-resolved → NetworkManager → `/etc/resolv.conf`，
  接管前快照、退出还原、崩溃自愈并生成离线 `restore-dns.sh`；stub 冲突处置与
  firewalld/ufw/nftables/iptables 放行；配置在 `/etc/diting`、数据在 `/var/lib/diting`（可用
  `DITING_DATA_DIR` 覆盖）；Web 控制台默认 15353 端口。

## 平台支持

| 平台 | 模式 | 最低要求 | 说明 |
|---|---|---|---|
| Android | ⚡ 极速模式 | 9.0+ / `arm64-v8a` | DNS 窄路由：TUN 只接管 53 端口与公共 DNS 劫持地址，轻量省电 |
| Android | 🛡️ 普通模式 | 9.0+ / `arm64-v8a` | gVisor 全隧道，支持应用分流、HTTPS 检查、出站代理 |
| Android | 🏠 服务器模式 | 9.0+ / `arm64-v8a` | 独立 DNS 服务，监听 `0.0.0.0:1053` 共享给局域网 |
| Windows | ⚙️ 核心服务 | 10+ 64-bit | 双栈接管、本地 53 监听、缓存规则、局域网 DNS、崩溃自愈 |
| Windows | 🖥️ 桌面 GUI | 10+ 64-bit | 免管理员权限管理服务，关闭窗口隐藏到托盘 |
| Windows | 🌐 Web 控制台 | 任意主流浏览器 | 15353 端口远程管理核心服务 |
| Linux | ⚙️ 核心服务 | systemd / `amd64`·`arm64` | 多后端接管、53 监听、缓存规则、局域网 DNS、离线还原 |
| Linux | 🌐 Web 控制台 | 任意主流浏览器 | 15353 端口完成全部配置，无需桌面环境 |

Android 三种模式共用同一套 Go 引擎，差异只在 TUN 路由范围：极速模式仅接管 DNS，普通模式接管全网络，
服务器模式不建隧道。

## 工程结构

```
DITING/
├── android/
│   ├── app/                   # Flutter Android 客户端：lib、test、原生壳、build_apk.bat
│   └── engine/                # Go 隧道引擎源码与 build_aar.ps1
├── desktop/
│   ├── app/                   # Flutter Windows 桌面窗口 + web/（局域网 Web 控制台）
│   ├── service/               # Go 特权服务 diting-service、IPC、内嵌前端产物
│   ├── toolbox/               # Python + PyWebView 维护工具箱
│   └── build_installer.bat    # 桌面端安装包（Windows EXE / Linux deb）
├── shared/                    # 两端共用的设计系统、主题、l10n、配置与 SQLite 读取
├── docs/                      # 开发文档与静态资源
├── avatars/                   # 赞助者与共建者头像
├── recognition_members.json   # 赞助者与共建者名单（见 docs/development/recognition-members.md）
├── pubspec.yaml               # Flutter pub workspace 根（一份 lockfile）
└── AGENTS.md                  # 开发与代码规范
```

平台日常工作说明见 [`android/README.md`](android/README.md)、[`desktop/README.md`](desktop/README.md)、
[`desktop/service/README.md`](desktop/service/README.md) 与 [`shared/README.md`](shared/README.md)。

## 快速开始

工作区共用一份 lockfile，先在仓库根解析依赖：

```bash
flutter pub get
flutter analyze
```

### Android

要求 Flutter 3.50+、JDK 17+、Android SDK（API 28+）。Gradle/AGP/Kotlin 版本与国内 Maven 镜像配置见
[Android 构建环境](docs/development/android-build-environment.md)。

首次构建前需在 `android/engine` 生成隧道引擎 AAR（构建产物，不入库）：

```powershell
cd android/engine
pwsh -File build_aar.ps1            # arm64，release 默认
pwsh -File build_aar.ps1 -Arch all  # 双 ABI，debug 默认
```

随后运行 `android/app/build_apk.bat` 交互式打包，或 `cd android/app && flutter test` 跑测试。
AAR 选择规则、签名与产物说明见 [`android/README.md`](android/README.md)。

### Windows / Linux

```bat
desktop\build_installer.bat            :: Windows EXE
desktop\build_installer.bat both       :: EXE + Linux deb
```

桌面端依赖 Flutter 3.50+、Visual Studio「使用 C++ 的桌面开发」工作负载与 Windows 开发者模式。
服务端单独构建、Linux 打包、手动编译等见 [`desktop/service/README.md`](desktop/service/README.md)。

### 维护工具箱

```bash
python -m pip install -r desktop/toolbox/requirements.txt
python desktop/toolbox/app.py
```

也可双击 `desktop/toolbox/run_maintenance.bat`（自动补齐依赖）。版本同步的命令行用法：

```cmd
python desktop\toolbox\core\version_manager.py 2.0.2 -g flutter
desktop\service\set_version.bat 2.2.9 -g common
```

## 技术栈

- **客户端**：Flutter / Dart 3 / Riverpod / go_router / sqflite（直接打开 2.2.9 的库）/ Material 3
- **服务端**：Go 1.25+ / gVisor netstack / miekg/dns / quic-go / Singleflight / Windows Service / systemd
- **Android 原生**：Kotlin 通道（VpnService、快捷磁贴、悬浮窗）
- **工具箱**：Python 3 / PyWebView (WebView2)

## 开发文档

- [Go AAR 构建记录](docs/development/aar-build-notes.md) — 编译参数、环境变量与常见问题。
- [Android 构建环境](docs/development/android-build-environment.md) — 工具链版本上限与 Maven 镜像。
- [云控贡献者名单维护](docs/development/recognition-members.md) — 名单机制、JSON 规范与头像规范。

## 赞助支持

如果谛听对您有帮助，欢迎赞助支持项目开发。付款时请备注昵称，以便同步加入赞助者名单。

| 支付宝付款码 | 微信付款码 |
| :---: | :---: |
| ![支付宝付款码](docs/assets/alipay_code.png) | ![微信付款码](docs/assets/wechatpay_code.png) |

## 作者与开源协议

- **作者**：[haoze-evolluling](https://github.com/haoze-evolluling)
- **协议**：[GNU General Public License v3.0 (GPL-3.0)](https://www.gnu.org/licenses/gpl-3.0.html)
