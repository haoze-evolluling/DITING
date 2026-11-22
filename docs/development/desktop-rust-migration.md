# 桌面端后端迁移至 Rust

桌面端（Windows / Linux）特权服务已从 Go 全面迁移为纯 Rust 实现，Android 与桌面端共用同一套解析器、
缓存与决策内核。本页记录迁移结论与对使用者的有意变化。

## 新的代码布局

| 目录 | 职责 |
|---|---|
| `rust/diting-desktop-api` | 配置模型、IPC DTO、平台值类型、版本信息 |
| `rust/diting-desktop-core` | 解析器/缓存/规则/查询日志/证书等引擎门面 |
| `rust/diting-desktop-dns` | DNS 数据面：UDP/TCP/DoT/DoH 监听、固定顺序管线与各处理阶段 |
| `rust/diting-desktop-platform` | Windows / Linux 平台能力（接管、防火墙、端口诊断、服务托管、路径） |
| `rust/diting-desktop-app` | 运行时组合：引擎生命周期、DNS 起停、后台维护、管理控制器 |
| `rust/diting-desktop-ipc` | HTTP/WebSocket 管理 API、鉴权/CORS |
| `rust/diting-desktop-service` | 二进制 `diting-service`：CLI、服务入口、自愈与还原 |
| `desktop/ui` | Tauri + React 桌面管理端；同一份构建产物由服务嵌入为 Web 管理页 |

`desktop/service` 仅保留构建与打包资产（`build/`、`build_linux.sh`、`VERSION`）与安装脚本。
旧的 Flutter 桌面前端已移除，管理界面由新的 `desktop/ui` 工程提供；服务在编译期嵌入
`desktop/ui/dist`，未构建前端时只提供占位页。详见 `desktop-ui.md`。

## 构建

```bat
desktop\build_installer.bat            :: Windows EXE
desktop\build_installer.bat both       :: EXE + Linux deb（经 WSL）
```

服务二进制由 `cargo build --release -p diting-desktop-service` 产出；Windows 安装包只包含一个
`diting-service.exe`，deb 只包含一个 `/usr/local/bin/diting-service`。桌面端版本号以
`desktop/service/VERSION` 为唯一真源，由 `rust/diting-desktop-api/build.rs` 在编译期注入。
deb 目标在 WSL 内直接编译，因此 WSL 需要已安装 Rust 工具链。

## 兼容性

保持不变：

- `config.json` 的字段名、默认值与归一化规则，旧配置可直接使用；
- 数据目录（Windows `%ProgramData%\DITING`；Linux root `/etc/diting` + `/var/lib/diting`，非 root
  `~/.diting`；`DITING_DATA_DIR` 覆盖）、`dns_state.json`、`filters/`、`querylog/`、`certs/`、
  `restore-dns.*` 的位置；
- `querylog-YYYYMMDD.jsonl` 文件名与行字段、24 小时本地时区桶与 Top-N；
- 缓存落盘文件的 v1 格式（旧缓存可读，Rust 写出的缓存旧版本同样可读）；
- HTTP/WebSocket API、JSON 信封、鉴权/CORS、事件类型与状态码；
- 加密 DNS 证书支持自签生成（ECDSA P-256 与 RSA-3072），并支持 PEM 与 PKCS#12
  （PBES2/AES，兼容传统 3DES/RC2）导入。

有意变化：

- 服务实现由 Go 改为 Rust；不再安装或加载七个内核动态库（`libditing_*.so` / `diting_*_core.dll`），
  相关环境变量（如 `DITING_FILTER_CORE_LIB`）不再生效；
- Windows 系统服务由原生 SCM API 直接注册，服务命令行为 `"diting-service.exe" -run`（安装时附加的
  `-config`/`-port`/`-ipc-addr`/`-token` 会一并写入）；SCM 托管的服务没有控制台，运行日志追加到数据目录的
  `service.log`，文件超过 2 MiB 时在下次启动前轮换；
- `diting-service -v` 的「DNS engine」一栏显示为原生 Rust；
- Linux 安装脚本会清理旧的 `/usr/lib/diting` 目录；
- 日志内部格式变化，不影响管理 API。

## 已知限制

- 证书 SAN 沿用 Go 的派生规则：`CertConfig` 默认已含 `serverName`，因此默认不会追加监听 IP；
  需要 IP 直连 DoT 时请在证书配置里显式填写 `ipAddresses`。

## 验证

- `cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test`；
- `python rust/verify.py --desktop`：包含真实的 DoT 回环握手、HTTP/WebSocket 契约测试；
- 手工冒烟：`diting-service -run -port <port> -ipc-addr 127.0.0.1:<port>` 后查询
  `/api/v1/health`、`/api/v1/status`，并验证 UDP/TCP/DoT/DoH 解析与 Web 配置热重绑。
