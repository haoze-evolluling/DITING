# 三模式存储 V2 迁移与旧库清理实施文档

> 状态：实施中
> 适用范围：Android 客户端（Flutter + Kotlin）
> 目标版本：2.4.10 之后的下一个正式版本
> 关联模块：`shared/lib/data/db`、`android/app/lib/data/db`、`android/app/android/app/src/main/kotlin/com/haoze/diting`

## 1. 背景与目标

当前应用存在三种工作模式：

| 模式 | `app_work_mode` | 偏好容器 |
| --- | --- | --- |
| 普通模式 | `normal` | `dns_vpn_prefs` |
| 极速模式 | `express` | `diting_express_prefs` |
| 服务器模式 | `dns` | `diting_dns_mode_prefs` |

历史上三种模式的数据存放在旧合并库中：

- `diting_database`：普通模式规则、订阅、日志、HTTP 日志、流量、自动化；
- `diting_express`：极速模式规则、订阅、日志；
- `diting_dns_rules`：服务器模式规则、订阅；
- `diting_server_logs`：服务器模式日志。

仓库中还存在一套未发布的“规则库/日志库拆分”实现（`diting_normal_rules`、`diting_normal_logs`、`diting_express_rules`、`diting_express_logs`、`diting_dns_logs`、`diting_app`）。该版本未对外发布，本方案不迁移它，只把它作为旧产物清理。

本次目标：

1. 为每个模式建立全新的规则库和日志库，共 3 模式 × 2 = 6 个模式库；
2. 为全局自动化数据建立 1 个全新全局库；
3. 只从旧合并库迁移用户数据；
4. 迁移、校验、切换完成并确认新库可正常读写后，彻底删除旧库、未发布拆分库、旧规则索引和旧存储偏好键；
5. 运行时 Dart/Kotlin 只认新库名，移除双布局、旧库名和一切历史兼容分支；
6. 对无法满足新 schema 的数据允许丢弃，但必须记录数量与原因；
7. 迁移失败不得导致数据丢失或应用不可启动。

## 2. 目标存储结构

### 2.1 新数据库文件

| 数据库 | 内容 | `application_id` |
| --- | --- | --- |
| `diting_normal_rules_v2` | 普通模式规则、订阅、`rule_version`、`mirror_template` | `0x44495431` |
| `diting_normal_logs_v2` | 普通模式 `dns_cache`/`dns_log`/`dns_race_log`/`bootstrap_log`、`http_request_log`、`app_traffic_daily` | `0x44495432` |
| `diting_express_rules_v2` | 极速模式规则、订阅、`rule_version`、`mirror_template` | `0x44495433` |
| `diting_express_logs_v2` | 极速模式 4 张日志表 | `0x44495434` |
| `diting_dns_rules_v2` | 服务器模式规则、订阅、`rule_version`、`mirror_template` | `0x44495435` |
| `diting_dns_logs_v2` | 服务器模式 4 张日志表 | `0x44495436` |
| `diting_global_v2` | `automation_rule`、`automation_profile`、`automation_event` | `0x44495437` |

所有库：

- `PRAGMA user_version = 1`；
- 唯一 `application_id`，打开时校验；
- `journal_mode = WAL`、`synchronous = NORMAL`、`foreign_keys = ON`、`busy_timeout = 5000`；
- 表名、列名、索引名保持不变，避免修改 Rust SQL 规划器和 Kotlin 写入 SQL。

### 2.2 模式映射

| 模式 | 规则库 | 日志库 |
| --- | --- | --- |
| normal | `diting_normal_rules_v2` | `diting_normal_logs_v2` |
| express | `diting_express_rules_v2` | `diting_express_logs_v2` |
| server | `diting_dns_rules_v2` | `diting_dns_logs_v2` |

全局自动化固定使用 `diting_global_v2`，不随模式切换。

### 2.3 运行时不变量

- Dart 的 `DataSet.ruleDatabase` / `logsDatabase` 直接返回新库名；
- Kotlin 的 `RuleDataset.rulesDatabase()` / `logsDatabase()` 直接返回新库名；
- 不再存在 `StorageLayout`、`storage_layout_version`、双布局回退；
- 只有一次性迁移模块可以出现旧库名；
- 迁移模块之外的源码和测试中不得出现旧数据库名。

## 3. 数据处置矩阵

### 3.1 迁移

| 来源（仅旧合并库） | 表 | 目标 |
| --- | --- | --- |
| `diting_database` | 规则 10 表 + `mirror_template` + 订阅 3 表 + `rule_version`（如存在） | `diting_normal_rules_v2` |
| `diting_database` | `dns_log`、`dns_race_log`、`bootstrap_log`、`http_request_log`、`app_traffic_daily` | `diting_normal_logs_v2` |
| `diting_database` | `automation_rule`、`automation_profile`、`automation_event` | `diting_global_v2` |
| `diting_express` | 规则/订阅/`rule_version` | `diting_express_rules_v2` |
| `diting_express` | `dns_log`、`dns_race_log`、`bootstrap_log` | `diting_express_logs_v2` |
| `diting_dns_rules` | 规则/订阅/`rule_version` | `diting_dns_rules_v2` |
| `diting_server_logs` | `dns_log`、`dns_race_log`、`bootstrap_log` | `diting_dns_logs_v2` |

### 3.2 舍弃

- 旧库 `dns_cache`：纯缓存，引擎重启后自动重建；
- 源库中不存在于目标 schema 的表；
- 目标 schema 中不存在的列（复制时取列交集）；
- 违反唯一索引的重复行，记录数量；
- 找不到父行的子表孤儿行，记录数量；
- 未发布拆分库及其 sidecar：不迁移，直接删除；
- 旧规则索引目录：删除后按新库重新编译；
- 旧存储偏好键：`storage_layout_version`、`storage_split_completed_at`、`storage_migration_error`。

### 3.3 源库损坏

- 源库 `quick_check` 失败或关键表无法读取时，该库标记为损坏；
- 迁移门禁必须让用户确认“放弃该模式旧数据”后才能继续；
- 确认后该模式以空库完成迁移，并记录原因。

## 4. 迁移状态机

在 `diting_settings` 中新增：

- `storage_v2_state`：`0` 未开始、`1` 迁移中、`2` 已校验、`3` 已清理；
- `storage_v2_completed_at`：epoch millis；
- `storage_v2_error`：最近失败原因；
- `storage_v2_report`：JSON 格式的复制/丢弃/校验摘要。

同时使用 `databases/.storage_v2_migrating` 文件锁：

- Dart 在复制前创建，成功后删除；
- Kotlin 服务、Widget、自动化在读写前检查；
- 锁超过 10 分钟视为过期，下次启动清理；
- `state=0` 或 `state=1` 时原生数据面拒绝启动。

状态流转：

```text
0 --开始复制--> 1 --复制并校验通过--> 2 --删除旧库并烟测通过--> 3
1 --失败--> 0（保留旧库，删除新库半成品）
2 --清理失败--> 2（下次启动重试）
```

## 5. 迁移流程

### 5.1 启动门禁

`main()`：

1. 加载偏好与版本；
2. 读取 `storage_v2_state` 并检查 7 个新库是否存在；
3. 已就绪：直接初始化规则、字体、容器并 `runApp`；
4. 未就绪：`runApp(StorageV2GateApp)`，显示迁移界面；
5. 门禁内执行迁移，成功后调用 `startApp` 替换根组件；
6. 失败显示原因，提供“重试”和“放弃旧数据并继续”。

### 5.2 前置条件

- 三个数据平面均未运行；运行中则门禁提示停止，并提供“停止连接并继续”；
- 设置文件锁；
- 写入 `state=1` 并等待平台确认；
- 关闭旧的 sqflite/原生连接；
- 删除上次中断留下的 7 个新库半成品及 sidecar。

### 5.3 复制

对每个目标库：

1. 用 canonical schema 创建新库；
2. 以只读方式打开源库，不触发 `onCreate/onUpgrade`；
3. 执行 `PRAGMA source.quick_check`；
4. `ATTACH` 源库；
5. `PRAGMA foreign_keys=OFF`；
6. 按父表→子表顺序复制，列取交集，`INSERT OR IGNORE`；
7. 大表按 `id` 分页复制，每批 5000 行；
8. 复制完成后 `PRAGMA foreign_keys=ON`、`DETACH`，切回 WAL/NORMAL。

复制期间目标库使用 `journal_mode=DELETE`、`synchronous=OFF`，因为目标文件在成功前可丢弃。

### 5.4 校验

每个目标库必须通过：

- `PRAGMA integrity_check` 返回 `ok`；
- `PRAGMA foreign_key_check` 为空；
- `PRAGMA user_version = 1`；
- `PRAGMA application_id` 等于约定值；
- 表集合等于期望集合（允许 `sqlite_sequence`、`android_metadata`）；
- 行数校验：
  - 日志表、`automation_event`、`rule_version`：目标行数必须等于源行数；
  - 规则/订阅/模板/自动化规则与档案：允许目标行数小于等于源行数，差异只允许来自重复/孤儿，并写入报告；
- 仓储烟测：读取每种模式的规则、订阅、日志、流量、自动化、版本历史；
- 写入烟测：事务内插入并回滚哨兵行；
- 原生烟测：每个日志库 `probeOk=true` 且 WAL；每个规则库关键表存在。

校验通过后用 `putIntAwaiting` 写入 `state=2`。

### 5.5 清理

应用首帧后执行，必须满足：

- `state=2`；
- 三个数据平面均未运行；
- 新库启动烟测通过。

步骤：

1. 原生 `AppDatabase.closeAll()`；
2. 删除旧合并库及其 `-wal`/`-shm`；
3. 删除未发布拆分库及其 sidecar；
4. 删除三个规则索引根目录；
5. 删除旧存储偏好键；
6. 写入 `state=3`；
7. 失败保留 `state=2`，下次启动重试。

### 5.6 恢复与防旧数据

- 每次启动 `state=2/3` 时扫描并删除已知旧库名，防止 Auto Backup 恢复；
- 新库缺失：状态回 `0`，旧库存在则重迁，否则建空库并记录；
- 新库损坏：状态 `2` 且旧库仍在时可重迁；状态 `3` 时重建空库并记录；
- 清理后降级到旧版本会以空库启动，发布说明必须注明。

## 6. 代码改动清单

### 6.1 Dart / shared

- 重写 `storage_contract.dart`：7 个新库常量、状态键、`DatabaseKind`；
- 重写 `datasets.dart`：删除 legacy 字段与布局方法；
- `legacy_database.dart` → `app_database.dart`：新库打开器、`application_id` 校验、只读源库打开、半成品清理；
- `legacy_schema.dart` → `database_schema.dart`：canonical schema、`rule_version` 标准表；
- 新增 `legacy_storage_source.dart`：唯一旧库名/表清单；
- 新增 `storage_v2_migration.dart`、`storage_v2_copy.dart`、`storage_v2_verify.dart`、`storage_v2_cleanup.dart`；
- 删除 `storage_migration.dart`、`storage_reclaim.dart`；
- `legacy_settings.dart`：删除布局方法，新增 V2 状态方法；
- `legacy_settings_provider.dart`：删除 `storageLayoutProvider`；
- 更新所有数据库解析 provider、清理、导出、悬浮日志、开发者页；
- 更新 ARB 文案并重新生成 l10n。

### 6.2 Dart / android app

- `main.dart`：启动门禁、`startApp`、启动后清理；
- 新增 `storage_v2_gate.dart` 与原生通道客户端；
- `rule_bootstrap.dart`：直接使用 `dataSet.ruleDatabase`；
- `data_cleanup_service.dart` / `cleanup_sql.dart`：删除布局与旧库回收；
- `developer_page.dart`：删除重试迁移/释放旧库，改为新库诊断；
- `floating_log_data.dart`、`floating_log_main.dart`、`bootstrap_settings_page.dart`、`automation_providers.dart`、`log_providers.dart`、`observability_providers.dart`、`server_status_providers.dart`、`subscription_providers.dart`、`traffic_providers.dart`、`request_export_providers.dart`、`rule_providers.dart`、`rule_dataset_providers.dart`、`agent_providers.dart`。

### 6.3 Kotlin

- `StorageContract.kt`：7 个新常量，删除布局与 Context 依赖；
- `RuleDataset.kt`：删除 legacy/split 方法，直接返回新库名；
- `LegacyDb.kt` → `AppDatabase.kt`：重命名并更新全部调用点；
- 新增 `StorageGate.kt`、`StorageMaintenanceBridge.kt`；
- 服务、日志写入器、保留期、Widget、健康探针、规则快照、自动化引擎全部改用新库名；
- `MainActivity` 注册存储维护通道；
- `RuleIndexLayout.deleteAll` 由清理通道调用。

### 6.4 Rust

- 无功能改动；
- 更新 `diting-log-core/src/health.rs` 测试字符串和 `rust/tools/log-smoke/LogSmoke.java` 中的旧库名。

### 6.5 测试

- 重写 `storage_migration_test.dart` 为 V2 迁移测试；
- 更新契约一致性、数据集映射、备份、清理、规则仓库测试；
- 新增旧库 fixture（仅测试使用）；
- 新增中断、重复执行、部分旧库、源库损坏、Auto Backup 复活、模式隔离测试。

## 7. 验证方案

### 7.1 自动化测试

在 `android/app` 下执行：

```bash
flutter test
```

重点覆盖：

- 7 个新库 schema、`user_version`、`application_id`；
- 四类旧库到 7 个新库的复制；
- `dns_cache` 不复制；
- 规则、订阅、模板、`rule_version`、自动化、HTTP、流量行数；
- 重复执行幂等；
- 中断后重试；
- 源库损坏时失败且不写 `state=2`；
- 旧库删除只发生在 `state=2` 且无水数据面；
- 旧库名清理后不再被打开。

### 7.2 静态检查

```bash
cd android/app && flutter analyze
```

Kotlin 编译：

```bash
cd android/app/android && ./gradlew :app:compileDebugKotlin
```

### 7.3 设备验收

1. 从 2.4.9 旧合并库升级，三种模式数据完整；
2. 全新安装，7 个新库创建成功；
3. 隧道运行中升级，门禁要求停止后迁移；
4. 迁移中强杀进程，再次启动可恢复；
5. 大数据量（10 万规则、100 万日志）迁移有进度且可完成；
6. 清理后 `databases/` 只剩 7 个新库及 sidecar；
7. 三模式切换、规则过滤、日志写入、Widget、悬浮日志、自动化、备份导入全部正常；
8. Auto Backup 恢复旧库后首次启动被清理。

### 7.4 验收标准

- 运行时源码（迁移模块除外）不出现旧库名；
- 旧库、未发布拆分库、旧索引、旧偏好键全部删除；
- 7 个新库 `integrity_check`、`foreign_key_check` 通过；
- 三模式数据互不串库；
- 无空规则快照、静默丢日志、Widget 空数据；
- 每个代码文件不超过 600 行。

## 8. 实施顺序

1. 文档与契约：本文档、`StorageContract`、`DatabaseKind`、`DataSet`；
2. 新 schema 与打开器：`DatabaseSchema`、`AppDatabase`、`rule_version` 入 schema；
3. 迁移引擎：旧库清单、复制、校验、清理、状态机、单元测试；
4. Dart 运行时切换：provider、清理、导出、悬浮日志、开发者页、门禁；
5. Kotlin 切换：契约、数据集、写入器、服务、健康探针、维护通道；
6. 删除旧代码与注释，更新测试与文案；
7. 全量测试、Kotlin 编译、设备验收；
8. 提交 Git。
