# 谛听 (DITING)

本地优先的开源 DNS 加速与广告 / 追踪拦截工具：上游解析加速、规则过滤、缓存与流量统计均在设备本地完成；
除用户主动配置的远程订阅、更新检查与可选 LLM 助手外，不上传查询数据。支持 Android、Windows 与 Linux，
并提供开发者维护工具箱。

- 📱 **Android**：Flutter 客户端 + Rust 隧道引擎（`rust/diting-engine`），随包交付两个原生库
  `libditing_engine.so`（隧道数据面与 DNS 管线）与 `libditing_kernels.so`（合并后的 UI 内核）；提供极速、
  普通（用户态 TCP/IP 全隧道）与服务器（局域网 DNS）三种模式，要求 Android 9.0+（API 28+）。
- 💻 **Windows**：Go 特权服务 `diting-service.exe` + Flutter 桌面端 + 内嵌于服务的 Web 控制台，支持物理网卡
  双栈 DNS 接管与离线恢复脚本。
- 🐧 **Linux**：Go 可执行文件 `diting-service`（内嵌 Web 控制台）+ 七个 Rust 内核 `.so`，由 systemd 托管，
  自动适配多种系统 DNS 后端。
- 🧰 **维护工具箱**：Python + PyWebView，涵盖 DNS 压测、代码扫描、Logo 导出、跨端构建与版本同步。

## 核心特性

- **解析与调度**：支持 UDP/TCP、DoH、DoT、DoQ 四种上游传输（桌面服务另含 DoH3）；四种调度策略
  —— 单一（`single`）、主备（`primary_backup`）、并行竞速（`parallel_race`）与智能预测
  （`smart_prediction`，基于 SRTT/RTTVAR、EWMA 失败率与连败惩罚在 Rust 侧计算）；内置主流服务商并支持
  自定义节点；Bootstrap IP 解析加密上游域名，DDR 检测防绕过。
- **缓存与容灾**：64 分片并发 LRU 缓存（默认 4096 条预算），提供保守（跟随 DNS TTL）/ 平衡 / 高命中三套
  TTL 预设；上游异常时按宽限期复用过期缓存（stale-while-revalidate）；Singleflight 合并并发回源。
- **规则引擎**：域名黑白名单与 AdGuard 语法（通配符、正则、Cosmetic 元素隐藏），Rust 侧以 Trie + Bloom
  索引加速解析与判定（缺库即报错，无降级实现）；远程订阅支持分组、镜像与定时更新；A/AAAA/CNAME/NS/PTR
  等静态改写；空 IP / NXDOMAIN / REFUSED 三种阻断响应与按域名的动态升级；上游伪应答（bogus NXDOMAIN）纠正。
- **Android 专属**：应用分流与白名单、可选 HTTPS 检查（本地 CA、按应用选择、HTTP/3 开关与域名旁路）、
  SOCKS5/HTTP 出站代理、悬浮窗与流量排行、Ping/Traceroute/DNS 诊断、快捷磁贴、Material 3 主题、
  配置导入导出、可选 BYOK LLM 助手（需自备 API Key）。
- **Windows 专属**：Go 特权服务 + 免 UAC 的 Flutter 桌面端（本地 IPC）；物理网卡双栈 DNS 接管、
  接管状态持久化与离线 `restore-dns.bat`；53 端口冲突检测与进程定位；局域网 DNS 与防火墙放行；
  15353 端口 Web 控制台（账号鉴权）；服务注册、开机启动与系统托盘。
- **Linux 专属**：systemd 托管；按 systemd-resolved → NetworkManager → `/etc/resolv.conf` 顺序自动适配
  后端，支持接管前快照、退出还原与离线 `restore-dns.sh`；stub 冲突处置与 firewalld/ufw/nftables/iptables
  放行；配置在 `/etc/diting`、数据在 `/var/lib/diting`（可用 `DITING_DATA_DIR` 覆盖）；Web 控制台默认 15353 端口。

## 平台支持

| 平台 | 模式 | 最低要求 | 说明 |
|---|---|---|---|
| Android | ⚡ 极速模式 | 9.0+ / `arm64-v8a`（模拟器 `x86_64`） | DNS 窄路由：仅 DNS 子网与公共解析器进入 TUN，其余流量走系统路由 |
| Android | 🛡️ 普通模式 | 9.0+ / `arm64-v8a` | 用户态 TCP/IP 全隧道，支持应用分流、HTTPS 检查、出站代理 |
| Android | 🏠 服务器模式 | 9.0+ / `arm64-v8a` | 独立 DNS 服务，监听 `0.0.0.0:1053` 共享给局域网，支持四种调度策略 |
| Windows | ⚙️ 核心服务 | 10+ 64-bit | 双栈接管、本地 53 监听、缓存与规则、局域网 DNS、离线恢复 |
| Windows | 🖥️ 桌面 GUI | 10+ 64-bit | 免管理员权限管理服务，关闭窗口隐藏到托盘 |
| Windows | 🌐 Web 控制台 | 任意主流浏览器 | 15353 端口远程管理核心服务 |
| Linux | ⚙️ 核心服务 | systemd / `amd64`·`arm64` | 多后端接管、53 监听、缓存与规则、局域网 DNS、离线还原 |
| Linux | 🌐 Web 控制台 | 任意主流浏览器 | 15353 端口完成全部配置，无需桌面环境 |

Android 三种模式共用同一个 Rust 引擎，差异只在 TUN 路由范围：极速模式仅接管 DNS，普通模式接管全网络，
服务器模式不建隧道、只对外提供 DNS 服务。

## 工程结构

```
DITING/
├── android/app/             # Flutter Android 客户端：lib、test、android 原生壳、build_apk.bat
├── desktop/
│   ├── app/                 # Flutter 桌面端（Windows 窗口 + web/ 供 Web 控制台使用的前端）
│   ├── service/             # Go 特权服务 diting-service：IPC、DNS 管线、内嵌前端产物（frontend/dist）
│   ├── toolbox/             # Python + PyWebView 维护工具箱
│   └── build_installer.bat  # Windows EXE / Linux deb 安装包构建入口
├── shared/                  # 两端共用：设计系统、主题、l10n、配置与 SQLite 读取
├── rust/                    # Rust 内核 crate 与 Android 隧道引擎（diting-engine；构建/校验脚本同目录）
├── docs/                    # 开发文档与静态资源
├── avatars/                 # 赞助者与共建者头像
├── recognition_members.json # 云端贡献者名单（见 docs/development/recognition-members.md）
├── pubspec.yaml             # Flutter pub workspace 根（一份 lockfile）
└── AGENTS.md                # 开发与代码规范
```

## 快速开始

工作区共用一份 lockfile，先在仓库根解析依赖：

```bash
flutter pub get
flutter analyze
```

测试按包分别运行（不要从根目录跑 `flutter test android/app`，原因见下文的构建环境文档）：

```bash
cd android/app && flutter test     # Android 套件
cd desktop/app && flutter test     # 桌面端套件
```

### Android

要求 Flutter 3.50+、JDK 17+、Android SDK（API 28+）、Rust 工具链与 Android NDK
（`ring` 需要 `CC_<target>`/`AR_<target>`，`build_android.py` 会自己从 NDK 取）。NDK 由
`ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT` 或 `android/local.properties` 的 `sdk.dir` 定位。
Gradle/AGP/Kotlin 版本与国内 Maven 镜像配置见 [Android 构建环境](docs/development/android-build-environment.md)。

首次构建前先用 `python rust/build_android.py` 生成两个 `.so`：隧道引擎 `libditing_engine.so`
与合并后的 UI 内核 `libditing_kernels.so`（构建产物、不入库）。

```bash
python rust/build_android.py              # arm64-v8a + x86_64，release
python rust/build_android.py --abi arm64  # 只出真机包
python rust/build_android.py --debug      # 更快编译、运行时略慢
```

随后运行 `android/app/build_apk.bat` 交互式打包（脚本会自动先跑上面的命令），或
`cd android/app && flutter test` 跑测试。签名与产物说明见脚本内提示。

### Windows / Linux

```bat
desktop\build_installer.bat            :: Windows EXE
desktop\build_installer.bat both       :: EXE + Linux deb（经 WSL）
```

构建管线由 `desktop\toolbox\core\build_manager.py` 驱动：Flutter Web 控制台 → Flutter Windows 程序 →
`diting-service.exe` → NSIS 安装包，最终产物在 `desktop\service\build\bin`。依赖 Flutter 3.50+、Go 1.25+、
Rust（cargo）、Python 3.10+、Visual Studio「使用 C++ 的桌面开发」工作负载、Windows 开发者模式，EXE 目标
另需 NSIS，deb 目标需 WSL。`desktop\service\build.bat`、`desktop\service\build_deb.bat` 是同一条管线的
入口；仅构建 Linux 二进制或 `.deb` 也可直接用 `desktop/service/build_linux.sh`（`--package` 打包 deb、
`-a arm64` 选架构）。

### 维护工具箱

```bash
python -m pip install -r desktop/toolbox/requirements.txt
python desktop/toolbox/app.py
```

也可双击 `desktop/toolbox/run_maintenance.bat`（自动补齐依赖）。

### 版本号

桌面端版本号只有一处字面量：`desktop/app/pubspec.yaml` 的 `version:`（Flutter 工具链强制要求它存在）。
服务端可执行文件、NSIS 安装包与 Linux deb 都在构建期从它取版本号，不再各存一份：

```cmd
python desktop\toolbox\core\version_manager.py -s          :: 查看真源与派生位置
desktop\service\set_version.bat 2.2.12 -d                    :: 预览（不落盘）
desktop\service\set_version.bat 2.2.12 -c                    :: 写入唯一真源并提交
```

Android 客户端（`android/app/pubspec.yaml`）是独立产品线，加 `-g android` 单独升级，不影响桌面端。

## 技术栈

- **客户端**：Flutter / Dart 3 / Riverpod / go_router / sqflite / Material 3
- **Android 引擎**：Rust（tokio / rustls / hyper / quinn / smoltcp），经 JNI 由 Kotlin `VpnService` 驱动；
  UI 侧内核合并为单个 `libditing_kernels.so`
- **桌面服务端**：Go 1.25+（miekg/dns、quic-go、kardianos/service、gorilla/websocket），通过 `purego`
  在运行期动态加载 Rust 内核（stamp / filter / rewrite / safebrowsing / hosts / dns64 / ratelimit），
  保持 `CGO_ENABLED=0`；Flutter 桌面端与 Web 控制台复用同一套 UI
- **Android 原生**：Kotlin 通道（VpnService、快捷磁贴、悬浮窗）
- **工具箱**：Python 3 / PyWebView（Windows 上使用 WebView2）

## 开发文档

- [Android 构建环境](docs/development/android-build-environment.md) — 工具链版本上限、Maven 镜像与测试注意事项。
- [云控贡献者名单维护](docs/development/recognition-members.md) — 名单机制、JSON 规范与头像规范。

`rust/build_android.py` 与 `rust/verify.py` 的用法见各自脚本头部的说明（`--android`、`--desktop`、`--engine`、
`--dart`、`--smoke`、`--all` 等选项）。

## 赞助支持

如果谛听对您有帮助，欢迎赞助支持项目开发。付款时请备注昵称，以便同步加入赞助者名单。

| 支付宝付款码 | 微信付款码 |
| :---: | :---: |
| ![支付宝付款码](docs/assets/alipay_code.png) | ![微信付款码](docs/assets/wechatpay_code.png) |

## 作者与开源协议

- **作者**：[haoze-evolluling](https://github.com/haoze-evolluling)
- **协议**：[GNU General Public License v3.0 (GPL-3.0)](https://www.gnu.org/licenses/gpl-3.0.html)
