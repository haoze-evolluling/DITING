# 谛听 (DITING)

谛听（DITING）是一款专注于本地 DNS 解析优化与网络流量过滤的开源工具。致力于在设备本地实现高性能、低延迟的域名解析，提供灵活的规则过滤、防追踪与流量控制能力，完全在本地闭环运行，无任何远程数据上传与隐私追踪。

本项目当前为 **Android 移动端（全功能正式版）** 实现：基于 Android `VpnService` 与 Go 用户态网络栈（gVisor netstack），支持完整的 DNS 接管优化、规则订阅过滤、细粒度应用网络分流、可选 HTTPS 流量解密检查、应用流量监控与快捷设置磁贴。

***

## 核心特性

### 📡 DNS 解析与上游调度

- **多协议支持**：支持标准 DNS（UDP/TCP 53）、DNS-over-HTTPS（DoH）与 DNS-over-TLS（DoT）。
- **多策略调度**：提供**单一服务**（Single）、**智能优选**（Smart EWMA 加权延迟与成功率）、**最快响应**（Fastest 并发竞速）及**依次尝试**（Sequential 备援容灾）四种解析调度模式。
- **服务商管理**：内置主流公共 DNS 服务商（阿里、腾讯、Cloudflare、Google、DNSPod 等），支持自由增删与编辑自定义 DoH/DoT 节点。
- **Bootstrap 引导与防绕过**：支持内置与自定义 Bootstrap IP 解析加密上游域名，避免递归解析死锁；支持 DDR 防绕过机制（阻断 `_dns.resolver.arpa`），引导客户端规范经由本地通道解析。

### ⚡ 智能缓存与弱网容灾

- **并发安全缓存**：采用 64 分片并发安全 LRU 缓存，提供跟随 TTL、平衡、高命中等多档策略预设，兼顾解析实时性与响应效率。
- **乐观容灾（Stale-While-Revalidate）**：当上游解析超时或网络出现波动时，短暂复用仍处于宽限期内的过期缓存，保障弱网环境下的基本可用性。

### 🛡️ 规则引擎与地址覆写

- **多维度规则匹配**：支持域名黑白名单（兼容 AdGuard 语法、通配符与正则）、网页元素隐藏（Cosmetic）规则、IPv4 / IPv6 地址覆写（A / AAAA 记录静态覆写）与 CNAME 重定向。
- **规则订阅与自动更新**：支持 AdGuard 格式远程规则订阅，支持规则分组、镜像源模板加速（如 GitHub 镜像代理）与后台定时自动拉取更新。
- **灵活阻断响应**：支持零地址（`0.0.0.0` / `::`）、NXDOMAIN、NODATA 与 REFUSED 四种拦截响应行为。

### 🔒 应用管控与网络分流（Android）

- **排除应用（Bypass）**：支持按应用绕过 VPN，直接使用底层网络与系统 DNS。
- **禁止联网**：按应用丢弃全部网络连接，阻止后台未经授权的外联行为。
- **应用白名单访问**：仅允许指定应用连接白名单域名解析出的有效 IP，阻断其他非白名单 IP 直连。
- **出站代理联动**：支持将过滤后的流量转发至本地 SOCKS5（支持 UDP ASSOCIATE）或 HTTP CONNECT 代理。

### 🔍 HTTPS 流量检查（Android 可选高级功能）

- **按需解密**：基于 Go 用户态网络栈（gVisor netstack）与本地 CA 根证书，仅对用户显式信任且主动勾选的目标应用进行解密与 URL 级规则匹配。
- **安全自适应旁路**：遇证书绑定（Certificate Pinning）、双向 TLS、EV 证书及预设敏感域名时自动直连旁路，保障金融与关键安全应用正常通行。
- **QUIC / HTTP/3 引导**：支持按目标应用阻断 QUIC（UDP 443）流量，平滑引导客户端回退至 TCP 进行分析。

### 🏠 局域网独立服务器模式（Standalone Server）

- 本机 1053 端口（UDP/TCP）提供轻量 DNS 解析服务，供局域网内其他设备（路由器、PC、电视等）将 DNS 指向本机使用。
- 与普通模式共享规则库与缓存，完全本地解耦，不建立 VPN 通道。

### 📊 全景可观测与实用工具

- **实时监控仪表盘**：提供 DNS 请求日志流、拦截记录、HTTP 检查日志、缓存命中状态、服务商健康度与规则拦截统计。
- **应用流量洞察（Android）**：按应用 UID 采样统计实时网速与历史消耗排行，支持悬浮窗实时查看与状态栏实时网速。
- **内置诊断工具**：内置 DNS 手动解析查询与 Ping 延迟测试工具，支持配置导入导出与 Android 快捷设置磁贴（Quick Settings Tile）。
- **个性化与多语言**：支持简体中文 / 英文界面，多套 Material 3 调色板与深浅色模式切换，可自定义背景图；集成可选的私有 LLM API 助手（BYOK，默认关闭，仅用于辅助域名与流量研判）。

***

## 运行架构与安全边界

- **Android 端架构**：
  - **默认模式（DNS-Only）**：仅路由 DNS 查询端口（53）流量，不代理普通应用数据及 TCP/UDP 传输，轻量低耗。
  - **高级模式（Go 用户态网络栈）**：当启用 HTTPS 检查、禁止联网或应用白名单访问时，Go 隧道接管相关网络流量进行精确处理；其他未配置应用直接原样转发。
  - **独立服务器模式**：监听 `0.0.0.0:1053`，供局域网外部设备接入。
- **隐私保障**：全本地运行，无云端账户体系，无上报遥测，所有缓存、规则库与配置数据完整保存在设备本地。

***

## 项目工程结构

```
DITING/
├── Android/         # Android 客户端完整工程（应用层、UI、Room 数据库、Go 隧道 AAR）
│   ├── app/         # Android 主程序源码与依赖配置
│   ├── tunnel/      # Go 用户态网络栈与 DNS 引擎源码（编译为 tunnel.aar）
│   └── build_apk.bat# Android 交互式构建与安装脚本
├── docs/            # 设计规范、开发指南与技术文档
│   ├── development/ # 工程维护文档（构建记录、证书规范、语法参考等）
│   └── assets/      # 静态资源与赞助二维码
└── scripts/         # 项目维护与辅助脚本
```

***

## 环境要求与构建指南

### 📱 Android 客户端

#### 运行与构建要求
- 运行系统：Android 10 及以上（API 级别 29+）
- 设备架构：`arm64-v8a`
- 构建环境：JDK 11 或更高版本（推荐使用 Android Studio 自带 JBR）、Android SDK

#### 构建命令
进入 `Android/` 目录，推荐直接使用 Gradle Wrapper（Windows、Linux 与 CI 通用）：

```bash
cd Android

# 编译 Debug APK
./gradlew :app:assembleDebug --console=plain    # Windows 下为 gradlew.bat

# 编译 Release APK（已混淆压缩）
./gradlew :app:assembleRelease --console=plain
```

Windows 下亦可在 `Android/` 目录下运行交互式辅助脚本 `build_apk.bat`（或在项目根目录执行 `.\Android\build_apk.bat`）：选择 Debug / Release 模式后自动编译、定位产物 APK，并可选通过 ADB 安装到目标设备（支持输入 `IP:端口` 的无线调试连接）。

构建产物路径：
- 标准 APK：`Android/app/build/outputs/apk/<buildType>/app-<buildType>.apk`
- 版本化安装包：`Android/app/build/outputs/apk/versioned/<buildType>/DITING-<buildType>-v<versionName>.apk`

***

## 技术栈

- **Android 客户端**：Kotlin / Jetpack Compose / Material 3 / Coroutines & Flow / Navigation Compose / Room / DataStore / VpnService / OkHttp / WorkManager
- **核心引擎与网络栈**：Go 1.23+ / gVisor netstack / `gomobile` / quic-go / miekg/dns

***

## 开发文档索引

项目技术规范与开发维护文档归档于 `docs/development/` 目录：

- [Go AAR 构建记录](docs/development/aar-build-notes.md) — Android 端 Go 隧道 AAR（`tunnel.aar`）的编译环境、构建参数与产物验证方法。
- [Android 签名证书管理与发布签名规范](docs/development/android-signing-certificate-management.md) — 4096 位 Android 正式发布签名证书技术规格、指纹与打包流程。
- [AdGuard 规则修饰符语法参考](docs/development/adguard-rule-modifier-syntax-reference.md) — AdGuard 规则语法与 `$modifier` 规范整理，包含规则引擎适配说明。
- [云控贡献者名单维护说明](docs/development/recognition-members.md) — 赞助者与共建者名单的云控机制、配置 JSON 格式与头像维护流程。

***

<a id="sponsorship"></a>

## 赞助支持

如果您觉得谛听对您有所帮助，欢迎赞助支持本项目的开发与维护。付款时请备注您的昵称，以便同步加入项目赞助者名单。

| 支付宝付款码 | 微信付款码 |
| :---: | :---: |
| ![支付宝付款码](docs/assets/alipay_code.png) | ![微信付款码](docs/assets/wechatpay_code.png) |

关于赞助者与共建者名单的动态展示机制，请参阅 [云控贡献者名单维护说明](docs/development/recognition-members.md)。

***

## 作者与开源协议

- **作者**：[haoze-evolluling](https://github.com/haoze-evolluling)
- **开源协议**：本项目基于 [GNU General Public License v3.0 (GPL-3.0)](https://www.gnu.org/licenses/gpl-3.0.html) 协议开源。
