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
5. 清空附加组并执行 `setgid` / `setuid`。
6. 确认已不是 Root 后创建 Tokio 运行时并启动 DNS 与控制循环。

降权失败时进程退出，不允许以 Root 身份继续服务。

Android 没有 `rustls-native-certs` 期望的 `/etc/ssl/certs` 汇总文件，服务器复用引擎的
`UpstreamTrust::platform()`：读取 `/system/etc/security/cacerts` 与 Conscrypt APEX 目录，再附加
内置 ISRG 根。否则 DoT/DoH 上游会以 `UnknownIssuer` 失败。

## 数据目录

所有文件位于 `filesDir/server/`，与普通/极速模式的数据库和偏好完全分离：

```text
filesDir/server/
├── config.json       # 服务器独立配置
├── control.sock      # 0600 控制 Socket
├── server.log        # 前台服务捕获的进程输出
├── rules/            # 规则订阅缓存
└── querylog/         # 按日 JSONL 查询日志
```

旧 `dns` 模式的数据库、偏好和日志不会迁移；`ServerModeRetirement` 继续清理旧数据。

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
- `filter_refresh` / `filter_check`：手动刷新订阅、测试单个域名。
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

不包含 DHCP、入站 DoH/DoT/DoQ、按客户端分组策略、访问控制、Web 管理台、开机自启与自动订阅更新。
应用退到后台后服务继续运行；切换工作模式或手动停止会结束进程。
