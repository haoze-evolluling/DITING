# DNSSR

谛听（DNSSR）是一款 Android 本地 DNS 解析与域名过滤工具。默认模式通过 Android `VpnService` 建立仅处理 DNS 的本地通道；用户也可以为明确选择的应用启用 HTTPS 流量检查，或按应用阻止联网。所有处理均在设备本地完成。

项目仓库：https://github.com/haoze-evolluling/DITING

## 功能

- 支持普通 DNS、DNS-over-HTTPS（DoH）和 DNS-over-TLS（DoT）。
- 内置多个服务商，可添加、编辑、删除自定义服务商，并在首页控制服务商显示。
- 支持 DNS 缓存，可选择跟随上游 TTL、限制最长 TTL 或固定 TTL，并可在上游失败时使用短暂过期缓存。
- 支持域名屏蔽规则、白名单规则和 AdGuard DNS 规则订阅；订阅可手动刷新或定期自动更新。
- 支持 NXDOMAIN、返回 `0.0.0.0` 或 `::` 等屏蔽响应方式。
- 支持 Bootstrap IP，减少解析 DoH 与 DoT 服务商域名时对系统 DNS 的依赖。
- 提供 DNS 请求日志、规则拦截率、缓存记录、竞速统计、服务商健康状态与 Bootstrap 统计。
- 支持导入、导出自定义服务商和规则订阅配置，以及 Android 快捷设置磁贴开关。
- 支持按应用排除 VPN（使用系统 DNS）、按应用阻止全部网络连接，或仅允许访问独立白名单域名（Android 10+）。
- 支持按应用启用 HTTPS 流量检查、域名和 URL 规则、HTTPS 检查自动旁路、根证书安装验证及可选 HTTP/3 回退。

## 工作方式与边界

启动服务后，Android 会要求授予 VPN 权限。默认模式只路由 DNS 查询，不代理普通网页、应用数据或文件传输流量。启用 HTTPS 流量检查、禁止联网应用或应用白名单访问后，Go 隧道使用 Go 用户态网络栈（gVisor netstack）接管 VPN 的 TCP、UDP、DNS 和 HTTP(S) 流量：HTTPS 流量检查仅解密用户选择且信任谛听 HTTPS 检查根证书的应用，其他应用直接转发；禁止联网应用的全部连接将被丢弃。应用白名单访问仅放行所选应用从白名单域名解析得到且仍在 DNS TTL 内的 IP，直连 IP、局域网和加密 DNS 会被阻断；共享 CDN IP 在有效期内可能承载其他站点。

证书固定、自定义证书校验、双向 TLS、EV 证书及安全敏感域名会触发 HTTPS 检查自动旁路。HTTP/3 默认直连；可选择阻断目标应用的 QUIC，使支持回退的客户端改用 TCP。检查记录只保存应用、authority、协议、结果、匹配规则和时间。

DNS 缓存、日志、规则和服务商配置均保存在设备本机。上游服务商仍会收到为完成解析所必需的域名请求。DoH 和 DoT 会加密设备到上游之间的 DNS 传输；普通 DNS 不具备此保护。

## 使用

1. 安装并打开谛听，在首页选择 DNS 服务商。
2. 根据需要在“设置”中管理服务商、选择解析模式、配置缓存和 Bootstrap IP。
3. 需要过滤域名时，在“规则管理”中添加屏蔽或白名单规则，或导入订阅地址。
4. 点击首页电源按钮并在系统弹窗中授权 VPN。
5. 在“日志”中查看 DNS 请求、缓存、竞速、规则拦截与 Bootstrap 统计。
6. 可选：右滑至功能卡片区，配置应用白名单访问、禁止联网应用或其他规则功能。

## 构建

环境要求：Android Studio、Android SDK 和 JDK 11。重新生成 Go 隧道还需要 Go 与 `gomobile`。项目最低支持 Android 7.0（API 24），目标 SDK 36；HTTPS 流量检查、禁止联网和应用白名单访问需要 Android 10（API 29）或更高版本。

```powershell
.\gradlew.bat :app:assembleDebug --console=plain
```

构建产物：

```text
app/build/outputs/apk/debug/app-debug.apk
```

## 技术栈

- Kotlin 与 Jetpack Compose
- Go 用户态 TCP/IP 栈（gVisor netstack）与 `gomobile`
- Android `VpnService`
- Room
- OkHttp
- Navigation Compose、Paging 与 WorkManager

## 赞助

如果这个项目帮助到了你，欢迎通过下面的付款码支持项目。付款时请备注您的网名或希望展示的名称，方便将您的名字加入赞助者名单。

支付宝付款码：

![支付宝付款码](docs/alipay_code.png)

微信付款码：

![微信付款码](docs/wechatpay_code.png)

## 作者与许可证

- 作者：haoze-evolluling（集美大学人工智能系大三学生）
- 本项目按 GNU GPL-3.0 发布
