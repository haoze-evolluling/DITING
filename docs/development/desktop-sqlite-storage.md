# 桌面端 SQLite 存储

桌面服务把结构化数据统一保存在数据目录下的 `diting.db`；文件后端仅保留给测试与显式回退使用。
Android 服务器模式已改为复用普通/简洁模式的 SQLite 数据集，见 `docs/development/server-mode.md`。

## 文件布局

- `diting.db`：配置分节、DNS 缓存、规则正文、查询日志、接管状态、管理端会话、迁移标记。
- `diting.db-wal` / `diting.db-shm`：WAL 与共享内存文件；备份时需一并复制。
- `certs/`、`login_bg.*`、`service.log`：仍保留为文件。
- Linux 下数据库及其 WAL/SHM 权限为 `0600`；Windows 依赖数据目录 ACL。

数据库使用 WAL、`synchronous=NORMAL`、`busy_timeout=5000`、`foreign_keys=ON`、
`auto_vacuum=INCREMENTAL`。网络盘无法启用 WAL 时回退 `DELETE` 日志模式并打印告警。

## 表结构

| 表 | 内容 |
| --- | --- |
| `meta` | 数据库元信息（如 `created_at`）。 |
| `config_sections` | 每个顶层配置分节一行 JSON，加载时组装为完整 `Config`。 |
| `takeover_state` | 系统 DNS 接管的单行快照 JSON。 |
| `dns_cache` | DNS 缓存条目，按 key 存储 wire 应答、TTL 与命中统计。 |
| `filter_contents` | 订阅规则正文原始字节、checksum 与抓取时间。 |
| `query_log` | 查询日志（时间、域名、客户端、状态、上游、耗时等）。 |
| `web_sessions` | 管理端 bearer token 会话，启动时回填内存。 |
| `legacy_imports` | 旧文件迁移标记，JSONL 记录下一行进度。 |

`config_sections` 的 key 与 `Config` 序列化后的顶层字段名一致。缺失或损坏的分节回退默认值。

## 迁移

服务在构造运行时之前、打开数据库之后执行迁移：

1. 读取 `-config` 指定的旧 `config.json`（默认配置路径），导入配置分节。
2. 按有效配置定位 `dns_state.json`、`cache.json`、`filters/`、`querylog/` 并导入。
3. JSONL 每 1000 行一个事务，同时写入 `legacy_imports.progress`；中断后从下一行继续。
4. 每个文件导入成功并标记 `done=1` 后删除；删除失败只告警，下次启动重试。
5. 损坏的配置文件重命名为 `.corrupt` 保留；坏日志行跳过并计数。
6. 数据库打开或迁移失败且旧文件仍存在时，本次运行回退文件后端；旧文件已删除时直接报错退出。

`-config` 以 `.json` 结尾时视为旧配置路径，数据库放在其父目录的 `diting.db`；其他路径视为数据库路径。

## 写入与保留

- 查询日志：热路径写内存环与有界队列；专用线程每 256 条或 1 秒批量提交，队列满时丢弃。
  每 60 秒清理超过 `retentionDays` 与 `maxEntries` 的记录。
- 缓存：手动或按间隔导出快照，事务内替换 `dns_cache`。
- 规则：订阅正文写入 `filter_contents`，元数据仍随配置保存。
- 配置：通过 `ConfigStore` 单事务按分节 upsert。
- 关闭顺序：停止 DNS 与管理 API → 刷写并关闭查询日志 → 保存缓存 → WAL checkpoint。

## 备份与恢复

停止服务后复制整个数据目录，或至少复制 `diting.db`、`diting.db-wal`、`diting.db-shm`。
运行中只复制 `diting.db` 可能丢失最近提交。恢复时停止服务，替换上述文件后启动。
`SQLITE_CORRUPT` 不会自动重建数据库，请从备份恢复。
