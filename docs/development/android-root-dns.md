# Android Root 免 VPN DNS 接管

普通模式与简洁模式的可选运行方式：在已获取 Root 权限的设备上，不申请也不使用 Android VPN 权限，
直接把本机 DNS 查询重定向到内置的 Rust DNS 引擎。它不是独立工作模式，而是当前模式的一种数据面；
规则库、日志库、上游配置和缓存策略都取自当前工作模式（`RuleDataset.active`），两种模式互不串数据。

## 运行时组成

| 组件 | 作用 |
| --- | --- |
| `RootDnsService` | 前台服务：探测 Root、启停引擎、安装/移除重定向规则 |
| `RootDnsBridge` | MethodChannel `com.haoze.diting/root_dns`，与 VPN 通道同形 |
| `RootDnsRules` | 通过 `su -c` 管理 iptables / ip6tables 链与 Private DNS |
| Rust `Engine::startStandaloneLoopback` | 无 TUN 的 UDP/TCP DNS 服务，复用当前模式的解析、规则、缓存与日志 |

引擎以应用 UID 运行，监听 `15353–15356` 中的第一个空闲端口；Root 只负责把流量导向该端口，
不用于运行 DNS 进程本身。监听地址限定为回环（`127.0.0.1` / `::1`）：`REDIRECT` 只改写
目的地址，回程源地址由 conntrack 还原；若绑定 `0.0.0.0`，应答会带着网卡地址返回，使用
connected socket 的系统解析器会把它当成伪造包丢弃。

## 启动顺序

1. `su -c id -u` 探测 Root，6 秒超时；未授权、超时或没有 `su` 都视为失败。
2. 创建独立 `Engine`，应用与当前模式相同的 `dnsConfig`，加载当前模式的规则快照，恢复暂停 /
   仅白名单状态，并接入 DNS 日志、Bootstrap 日志与缓存镜像。
3. 在 `15353–15356` 上启动独立 DNS 服务。
4. 安装 `nat OUTPUT` 链 `DITING_ROOT_DNS`：
   - `-m owner --uid-owner <应用 UID> -j RETURN`：本应用自己的上游查询不重定向，避免回环；
   - `UDP/TCP 53 -> REDIRECT --to-ports <监听端口>`。
5. 安装 `INPUT` 链 `DITING_ROOT_DNS_IN`：丢弃发往监听端口的非 `lo` 流量，避免成为局域网开放解析器。
6. 关闭系统 Private DNS（DoT 使用 853 端口，不会被 53 重定向捕获），并保存原值。
7. 刷新 netd 解析缓存。

停止顺序相反：先移除链并恢复 Private DNS，再关闭监听器，因此不会出现“查询仍被重定向但无人应答”
的窗口。

## 持久化与故障恢复

- `dns_root_prefs`：`root_dns_running`（原生运行标志）、`root_dns_rules_installed`（规则所有权）、
  Private DNS 原值与 `last_dns_config`（快捷开关重放）。
- `dns_vpn_prefs`：`root_dns_takeover_enabled`（开关）、`root_dns_running`（UI 侧运行标志）。
- 安装规则前写入 `root_dns_rules_installed`，成功移除后才清除。进程在两者之间被杀时，
  `DitingApplication` 冷启动会调用 `reconcileStaleRules` 清理残留链并恢复 Private DNS；
  清理失败则保留标记，下次启动继续重试。

## 控制协议

通道 `com.haoze.diting/root_dns`：

- `start {dnsConfig}` → `{started, needsPermission, error}`；原生侧先探测 Root。
- `stop` / `status` / `trafficRates` / `applyDnsConfig` / `reloadRules`：与 VPN 通道语义一致。
- `probeRoot` → `{available, uid, message}`。

Dart 侧 `MethodChannelRootDnsController` 实现 `VpnController`，`prepare()` 恒为 `true`：
Root 模式下不存在系统 VPN 授权对话框。

## 能力边界

- 只接管本机 DNS。应用内自带的 DoH/DoT 客户端、硬编码解析器不会被 53 端口重定向捕获。
- 应用分流、按应用拦截、HTTPS 检查、出站代理、按 UID 的连接日志都依赖 TUN 数据面，此模式不可用。
- DNS 查询日志中的来源应用固定显示 `RootProxy`：独立服务没有 `/proc/net` 的来源 UID 归属。
- IPv6 重定向依赖内核的 `ip6tables nat`；缺失时仍会安装 INPUT 丢弃链，但 IPv6 DNS 不会被接管。
- 与其他 VPN 应用同时运行时，第三方 VPN 可能自行接管 DNS，结果取决于其路由策略。
- 网络切换后若系统刷新了 netd 链，可能需要重新开始一次接管。

## 调试

```bash
adb shell su -c 'iptables -t nat -S DITING_ROOT_DNS'
adb shell su -c 'iptables -S DITING_ROOT_DNS_IN'
adb shell su -c 'settings get global private_dns_mode'
adb logcat -s RootDnsService DataPlaneControl
```
