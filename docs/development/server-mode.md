# Android 服务器模式

服务器模式是第三种工作模式，数据面与控制面分离：

- `rust/diting-server` 是独立的长驻 Rust 进程，复用桌面 DNS 栈完成解析、规则过滤、缓存与查询日志。
- 服务器运行时与隧道引擎、UI 内核一起链接进 `libditing_native.so`；APK 里只有一个极小的
  `libditing_server.so` 启动器，由它加载合并库并调用 `diting_server_main`，避免重复打包 DNS/TLS
  栈。
- Flutter 管理端通过 MethodChannel `com.haoze.diting/server` 启停进程，并通过应用私有 Unix
  Domain Socket 读写运行中配置。
- Android 前台服务 `ServerDnsService` 只负责 Root 探测、启动/监督/停止 Rust 进程，不参与 DNS
  查询处理。

## 监听与 Root

| 启动方式 | 端口 | 行为 |
| --- | --- | --- |
| 非 Root | `1053` | 以应用 UID 直接启动，监听 `0.0.0.0` 与可用的 IPv6 地址 |
| Root | `53` | 通过 `su -c` 启动，先绑定 UDP/TCP 53，再降权到应用 UID |

Root 授权不是必需项。Root 探测使用带 6 秒超时的 `su -c id -u`；未授权、超时或 `su` 不存在时
直接按非 Root 启动。Root 进程绑定 53 失败时不会静默改用 1053，而是把错误回报给管理端；用户可在
服务器设置中关闭 Root 模式后重试。

Root 启动顺序固定为：

1. 启动器加载同目录的 `libditing_native.so`。
2. 读取、校验并规范化 `config.json`。
3. 同步绑定 DNS UDP/TCP 套接字。
4. 创建控制 Socket，并把数据目录与控制 Socket 交给应用 UID。
5. 清空 Root 附加组，仅保留 Android 应用联网所需的 `AID_INET (3003)`，再执行 `setgid` /
   `setuid`。若连该组也清空，已绑定的 53 端口仍能接收请求，但降权后无法创建出站套接字，
   Bootstrap 与上游 DoT 会全部失败并返回 `SERVFAIL`。
6. 确认已不是 Root 后创建 Tokio 运行时并启动 DNS 与控制循环。

降权失败时进程退出，不允许以 Root 身份继续服务。

Android 没有 `rustls-native-certs` 期望的 `/etc/ssl/certs` 汇总文件，服务器复用引擎的
`UpstreamTrust::platform()`：读取 `/system/etc/security/cacerts` 与 Conscrypt APEX 目录，再附加
内置 ISRG 根。否则 DoT/DoH 上游会以 `UnknownIssuer` 失败。

## 数据目录与存储

服务器模式使用独立数据库 `filesDir/server/server.db`，与普通/简洁模式的数据库和偏好完全分离。
数据库复用桌面端 `diting-desktop-sqlite` 的 schema：`query_log`、`filter_contents`、`dns_cache`、
`config_sections` 与 `meta`。

```text
filesDir/server/
├── server.db         # 配置、查询日志、规则正文、DNS 缓存（WAL）
├── config.json       # 未运行时的兼容镜像，运行时以数据库为准
├── control.sock      # 0600 控制 Socket
├── server.log        # 前台服务捕获的进程输出
├── rules/            # 旧版规则缓存，首次升级后导入并删除
└── querylog/         # 旧版 JSONL 日志，首次升级后导入并删除
```

- 配置：完整 `ServerConfig` 以 JSON 写入 `meta.server_config`，同时写入 `config_sections`；启动时
  优先使用数据库，若 `config.json` 比数据库更新（例如未运行时由管理端修改）则导入该文件。
- 查询日志：内存环（`maxEntries` 只约束内存）+ SQLite 异步写入；数据库按 `retentionDays` 清理，
  重启后自动回填最近 24 小时的统计。
- 规则正文：订阅清单缓存写入 `filter_contents`；DNS 缓存随进程退出写入 `dns_cache`，启动时恢复。
- 首次升级：启动时自动把旧的 `config.json`、`querylog/*.jsonl`、`rules/*.txt`、`cache.json`
  导入新库，成功后删除这些旧文件并写入 `meta.server_legacy_migration` 标记。

## 规则订阅

服务器模式的订阅配置保存在 `ServerConfig.filter.lists`，界面与普通/简洁模式对齐，支持：

- 分组：`group` 字段保存分组名，订阅页可按分组筛选，分组管理只改列表字段。
- 收录类型：`kind` 为 `domain` 或 `hosts`，下载后只保留对应格式的正文。
- 来源：`sourceType` 为 `remote` 或 `local`；本地文件由管理端复制到数据库目录下的
  `server_local/`，再以文件路径交给 Rust 端读取。
- 镜像加速：`mirrorTemplate` 仅用于展示，`mirrorUrl` 是管理端展开后的实际地址；下载时先请求
  镜像，失败且 `mirrorFallback` 为真时再请求原始地址。
- 自动更新：`autoUpdate` 与 `updateIntervalHours` 控制服务器进程内每分钟一次的到期检查；
  手动刷新仍通过 `filter_refresh`。
- 从其他模式导入：管理端只读打开普通/简洁模式的规则数据库，复制订阅配置后由服务器重新下载。

旧 `dns` 模式的数据库、偏好和日志不会迁移；`ServerModeRetirement` 继续清理旧数据。

## 启动与保活

服务器模式的启动偏好保存在原生 `server_mode_prefs`，与服务器配置数据库分离：

- 开机自启动：`auto_start`。设备重启（`BOOT_COMPLETED`）或应用更新
  （`MY_PACKAGE_REPLACED`）后，若当前工作模式仍为 `server`、已同意用户协议且开关开启，
  `BootAutoStartReceiver` 会直接启动前台服务。其他模式继续沿用「前后台行为 → 开机自启动」。
- 异常退出自动重启：`auto_restart`，默认开启。服务器进程就绪后意外退出时，前台服务按
  1.5s / 3s / 6s / 12s / 24s 的退避重新拉起，最多 5 次；期间状态为 `restarting`，通知栏显示
  “正在自动重启”。用户手动停止会让排队中的重启立即失效，连续失败达到上限后保留错误信息并停止。
- 这两个开关通过 MethodChannel 的 `launch_settings` / `set_launch_settings` 读写，仅影响本机
  进程行为，不写入 `ServerConfig`。

## 控制协议

控制 Socket 只接受应用私有目录内的文件系统 Unix Socket 连接，权限为 `0600`。每次连接发送一行
JSON，服务端返回一行 JSON：

```json
{"id":1,"method":"status","params":{}}
{"id":1,"ok":true,"result":{"running":true,"port":1053}}
```

首版方法：

- `status`：监听端口、实际绑定地址、Root 状态、启动时间与过滤规则数。
- `get_config` / `update_config`：读取或替换可管理配置；监听身份由进程实际身份决定，不能被 UI 改写。
- `stats`：24 小时汇总、每小时点、Top 域名、Top 拦截域名与 Top 客户端。
- `query_log` / `clear_query_log`：分页筛选与清空内存及按日文件。
- `filter_refresh` / `filter_check`：手动刷新订阅、测试单个域名；刷新失败时仍会落库
  `lastStatus` / `lastError`。
- `cache_clear`：清空内存与数据库中的 DNS 缓存。
- `shutdown`：写入响应后通知主循环优雅退出。

错误响应统一为：

```json
{"id":1,"ok":false,"error":{"code":"request_failed","message":"..."}}
```

## 调试

在设备上可执行以下命令（需要可访问应用私有目录的调试环境）：

```bash
adb shell run-as com.haoze.diting ls -l files/server
adb logcat -s ServerDnsService DataPlaneControl
```

手动启动独立进程（root 设备示例，UID/GID 按应用实际值替换）：

```bash
su -c '/data/app/.../lib/arm64/libditing_server.so \
  --data-dir /data/user/0/com.haoze.diting/files/server \
  --port 53 --bind 0.0.0.0 --drop-uid 10123 --drop-gid 10123'
```

进程就绪后 stdout 会输出一行 `SERVER_READY {...}`，其中包含端口、Root 状态、实际地址、控制
Socket 路径与 PID。启动器固定从自身目录加载 `libditing_native.so`；手工部署时必须让两个文件
位于同一目录。停止时可向控制 Socket 发送 `shutdown`，或向进程发送 `SIGTERM`。

## 首版边界

不包含 DHCP、入站 DoH/DoT、按客户端分组策略、访问控制与 Web 管理台。
订阅自动更新只在服务器进程运行期间执行；应用退到后台后服务继续运行，切换工作模式或手动停止
会结束进程。开机自启与异常重启见上一节。
