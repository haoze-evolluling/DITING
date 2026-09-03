<p align="right">🌐 <a href="README.md">English</a> | <b>简体中文</b></p>

# 谛听 (DNSSR)

谛听（DNSSR）是一款专为 Android 打造的本地 DNS 解析优化与网络流量过滤工具。默认通过 Android `VpnService` 建立仅接管 DNS 请求的轻量本地通道；亦可按需启用 Go 用户态网络栈，实现细粒度的应用联网管控与可选的 HTTPS 流量检查。所有解析、过滤与统计分析均在设备本地完成，安全透明且无任何远程数据收集。

***

## 核心特性

### 📡 DNS 解析与上游策略

- **多协议支持**：支持标准 DNS（UDP/TCP 53）、DNS-over-HTTPS（DoH）与 DNS-over-TLS（DoT）。
- **多策略调度**：提供**单一服务**、**智能优选**（基于近期延迟与成功率动态加权）、**最快响应**（并发竞速）及**依次尝试**（主备容灾）四种解析模式。
- **服务商管理**：内置主流公共 DNS 服务商，支持自由添加、编辑自定义 DoH/DoT 节点，并可灵活定制首页展示列表。
- **Bootstrap 引导**：支持内置与自定义 Bootstrap IP 解析上游域名，避免递归解析死锁并支持智能权重优选。

### ⚡ 智能缓存与容灾优化

- **灵活缓存策略**：提供跟随上游 TTL、标准平衡、高命中等多档预设，兼顾解析实时性与响应效率。
- **乐观容灾**：当上游解析失败或超时时，支持短暂复用有效期内的过期缓存，保障弱网环境下的可用性。

### 🛡️ 规则过滤与地址覆写

- **多维度规则**：支持域名黑白名单、IPv4 / IPv6 地址覆写与 CNAME 重定向。
- **AdGuard 规则订阅**：支持 AdGuard DNS 格式订阅，支持规则分组、镜像站模板加速与后台定时自动更新。
- **灵活拦截响应**：支持 NXDOMAIN、`0.0.0.0`、`::` 及自定义响应等多种阻断模式。

### 🔒 应用管控与网络分流

- **排除应用**：支持按应用绕过 VPN，直接使用系统网络与系统 DNS。
- **禁止联网**：按应用直接丢弃全部网络连接，阻止后台未经授权的外联。
- **应用白名单访问**：仅允许指定应用连接白名单域名解析出的有效 IP，阻断其他直连外联。
- **出站代理联动**：支持将过滤后的流量转发至本地 SOCKS5 或 HTTP CONNECT 代理。

### 🔍 HTTPS 流量检查（可选高级功能）

- **按需解密**：基于 Go 用户态网络栈（gVisor netstack）与本地 CA 根证书，仅对用户显式选择且信任证书的应用进行解密与 URL 级规则匹配。
- **安全自适应旁路**：遇证书固定（Certificate Pinning）、双向 TLS、EV 证书及敏感域名时自动直连旁路。
- **QUIC / HTTP/3 控制**：支持阻断目标应用的 QUIC 流量，引导客户端平滑回退至 TCP 进行分析。

### 📊 全景可观测与实用工具

- **实时监控仪表盘**：提供 DNS 请求日志、HTTP 检查日志、缓存详情、竞速测速、服务商健康度与规则拦截统计。
- **悬浮日志窗口**：支持悬浮窗实时查看后台解析动态。
- **便捷管理**：支持自定义配置与规则订阅的导入/导出，提供 Android 快捷设置磁贴（Quick Settings Tile）。

***

## 运行架构与安全边界

- **默认模式（DNS-Only）**：仅路由 DNS 查询端口流量，不代理普通应用数据及 TCP/UDP 传输，轻量低耗。
- **高级模式（Go 用户态网络栈）**：当启用 HTTPS 检查、禁止联网或应用白名单访问时，Go 隧道接管相关网络流量进行精确处理；其他未配置应用直接原样转发。
- **隐私保障**：所有 DNS 缓存、规则库、日志记录和配置数据均完整保存在设备本地，不设任何数据上传与遥测。

***

## 环境要求与构建

### 运行环境

- **最低版本**：Android 10（API 29）
- **目标版本**：Target SDK 36
- **架构支持**：`arm64-v8a`

### 开发与构建要求

- Android Studio 与 Android SDK
- JDK 11 或更高版本（推荐使用 Android Studio 自带 JBR）
- （可选）若需重新编译 Go 隧道 AAR，需配置 Go 1.20+、`gomobile` 与 Android NDK，详见 [Go AAR 构建记录](docs/development/aar-build-notes.md)。

### 构建命令

```powershell
# 编译 Debug APK
.\gradlew.bat :app:assembleDebug --console=plain

# 编译 Release APK
.\gradlew.bat :app:assembleRelease --console=plain
```

构建产物路径：

- Debug APK: `app/build/outputs/apk/debug/app-debug.apk`
- 版本化安装包: `app/build/outputs/apk/versioned/`

***

## 技术栈

- **界面与架构**：Kotlin / Jetpack Compose / Material 3 / Coroutines & Flow / Navigation Compose
- **用户态网络栈**：Go / gVisor netstack / `gomobile`
- **网络与系统服务**：Android `VpnService` / OkHttp / WorkManager
- **本地存储**：Room / Paging 3 / DataStore

***

## 赞助

如果您觉得本项目对您有所帮助，欢迎赞助支持。付款时请备注您的昵称，以便同步加入赞助者名单。

| 支付宝付款码 | 微信付款码 |
| :---: | :---: |
| ![支付宝付款码](docs/assets/alipay_code.png) | ![微信付款码](docs/assets/wechatpay_code.png) |

关于赞助者与共建者名单的动态展示机制，请参阅 [云控贡献者名单说明](docs/features/recognition-members.md)。

***

## 作者与许可证

- **作者**：[haoze-evolluling](https://github.com/haoze-evolluling)
- **开源协议**：本项目基于 [GNU General Public License v3.0 (GPL-3.0)](https://www.gnu.org/licenses/gpl-3.0.html) 协议发布。
