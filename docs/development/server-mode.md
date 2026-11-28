# Android 服务器模式

服务器模式是第三种工作模式，和普通/简洁模式共用同一个 Rust 内核，不再有独立的 Rust 进程：

- DNS 解析、上游调度、缓存、阻断与查询日志全部由进程内 `Engine` 完成。
- 对局域网提供 DNS 由内核的 standalone 监听（`Engine.startStandalone`）承担，日志写进服务器模式
  自己的日志库，和普通/简洁模式共用同一套表结构。
- Android 前台服务 `ServerDnsService` 只负责内核生命周期、监听端口监督与 Root 端口重定向。
- Flutter 侧通过 MethodChannel `com.haoze.diting/server` 启停服务；配置、订阅、统计和日志直接读写
  服务器模式的数据集，不再有控制 Socket。

## 数据集

服务器模式的数据集（`DataSet.server`）与普通/简洁模式平级：

| 项目 | 位置 |
| --- | --- |
| 偏好 | `diting_server_prefs` |
| 规则与订阅 | `diting_server_rules_v2`（`StorageContract.serverRulesDatabase`） |
| 日志与缓存镜像 | `diting_server_logs_v2`（`StorageContract.serverLogsDatabase`） |
| 规则索引 | `files/rule-index/server` |

规则表、订阅表、`dns_log`、`dns_race_log`、`bootstrap_log`、`dns_cache` 的结构与其他数据集完全
一致，后续新增字段只需改一处 schema。`dns_log` 额外记录服务器模式需要的客户端与链路字段：
`clientIp`、`clientName`、`protocol`、`upstreamProvider`、`rcode`、`cacheHit`、`durationMs`、`ttl`。

## 配置

- 运行配置以 `ServerConfig` JSON 的形式保存在 `diting_server_prefs/server_config_json`。
- Flutter 通过 `encodeServerDnsConfig` 把它映射成内核的 `DnsConfig` 文档（上游、Bootstrap、缓存、
  阻断响应），启动和修改配置时都走同一条 `apply_dns_config` 路径。
- 上游、过滤、缓存的字段含义与旧服务器模式保持一致；服务器模式特有的 `filter.lists` 同时作为
  订阅定义的来源。

## 监听与 Root

内核始终以应用 UID 在 `0.0.0.0:1053`（含 IPv6）监听。Root 只用于把局域网的 53 端口转到该端口：

| 启动方式 | 对外端口 | 行为 |
| --- | --- | --- |
| 非 Root | `1053` | 直接监听 1053，客户端需显式指定端口 |
| Root | `53` | 通过 `su` 执行一段极小的 iptables 脚本，把入站 UDP/TCP 53 REDIRECT 到 1053 |

端口重定向由 `ServerPortRedirect` 完成，脚本来自应用私有目录：

```text
iptables  -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 1053
iptables  -t nat -I PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 1053
ip6tables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 1053
ip6tables -t nat -I PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 1053
```

REDIRECT 只改目的地址，源地址保持不变，所以内核日志里的客户端 IP 是真实值。脚本在 `su` 会话里
阻塞读取 stdin；App 进程退出后 stdin 关闭，脚本的 EXIT trap 会删除规则，不会残留“把 DNS 指向
死端口”的规则。Root 不可用、`iptables` 缺失或规则校验失败时自动回退到 1053，并在日志中说明。

Root 探测仍是带 6 秒超时的 `su -c id -u`。启动偏好 `prefer_root` 保存在 `server_mode_prefs`。

## 日志链路

`Engine` 的 `LogItem` 增加客户端与链路字段后，经 `batch_payload` → `diting-log-core` →
Kotlin `DnsLogWriter` 写入 `diting_server_logs_v2.dns_log`。`EngineLogCallbacks` 以 `all` 模式挂载，
`LogRetention` 按 `queryLog.retentionDays` 清理；服务器模式不写 HTTP 流量表。

统计与查询日志由 Flutter 直接读 `dns_log`，字段和普通模式的日志页一致，可按域名、客户端、类型、
状态、rcode 与时间范围筛选。缓存命中来自内核返回的 `HIT` / `STALE` / `SHARED` / `MISS`。

## 规则订阅

订阅定义保存在 `ServerConfig.filter.lists`，迁移后写入 `diting_server_rules_v2.subscription`，
复用普通/简洁模式的订阅仓库、下载器、镜像模板与自动更新逻辑：

- `group` 映射到 `subscription_group`；
- `kind` 为 `domain` 或 `hosts`；
- `sourceType` 为 `remote` 或 `local`；
- `mirrorTemplate` / `mirrorFallback` 原样保留；
- 规则正文由订阅更新重新导入到同一张 `block_rule` 表，内核通过 `EngineRuleLoader` 装载
  `RuleDataset.SERVER` 快照。

## 界面

服务器模式完全并入普通 Shell，不再有独立的 `/server` 导航壳：

- `/` → 服务器首页（`ServerHomePage`），`/hub` → 服务器配置中心，`/logs` → 服务器日志页。
- 底部 Dock 隐藏“流量”入口；普通设置页、外观、关于等系统页面共用。
- 服务器配置子页保留 `/server/upstream`、`/server/filter`、`/server/settings` 等路径，作为普通
  Shell 之外的叶子路由。旧路径 `/server`、`/server/hub`、`/server/logs` 会重定向到新入口。

## 升级迁移

`migrateLegacyServerData` 在启动时、且当前工作模式为服务器模式时运行一次：

1. 读取旧 `files/server/config.json`，不存在则读取旧 `files/server/server.db` 的
   `meta.server_config`。
2. 转成新的 `ServerConfig` JSON 写入 `diting_server_prefs/server_config_json`。
3. 把 `filter.lists` 写入 `diting_server_rules_v2` 的订阅表（保留分组、镜像与启用状态）。
4. 迁移成功后删除旧 `server.db`、`config.json`、`server.log`、`control.sock` 以及旧的
   `querylog/`、`rules/` 目录；旧查询日志按约定丢弃。
5. 写入 `server_legacy_migrated=1`，之后不再扫描。

规则正文不迁移（旧桌面格式已不再支持），订阅会在下次更新或自动更新时重新下载导入。

## 启动与保活

启动偏好保存在原生 `server_mode_prefs`：

- 开机自启动：`auto_start`。设备重启或应用更新后，若当前工作模式仍为 `server`、已同意用户协议
  且开关开启，`BootAutoStartReceiver` 启动前台服务。
- 异常退出自动重启：`auto_restart`，默认开启。监控每秒检查 `Engine.isRunning()`，按
  1.5s / 3s / 6s / 12s / 24s 退避重启，最多 5 次；期间状态为 `restarting`。
- 这两个开关通过 `launch_settings` / `set_launch_settings` 读写，不写入 `ServerConfig`。

服务启动顺序：创建前台通知 → 新建 `Engine` → 应用 DNS 配置 → 挂载日志、分辨率、Bootstrap 与缓存
镜像 → 装载服务器规则 → `startStandalone(1053)` → 视 Root 情况启用 53 重定向 → 上报
`ServerProcessState.ready`。失败时保留错误并停止。

## 调试

```bash
adb shell run-as com.haoze.diting ls -l files/server
adb shell run-as com.haoze.diting ls -l databases | grep server
adb logcat -s ServerDnsService ServerPortRedirect DataPlaneControl
```

确认规则是否生效：`adb shell iptables -t nat -L PREROUTING -n -v`。停止服务后这些规则应自动消失。

## 首版边界

不包含 DHCP、入站 DoH/DoT、按客户端分组策略、访问控制与 Web 管理台。服务运行期间订阅自动更新
由 Flutter 侧的共享更新器负责；应用退到后台后前台服务继续监听，切换工作模式或手动停止会结束服务。
