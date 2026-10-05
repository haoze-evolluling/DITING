# 三模式数据隔离实施方案

> 状态：方案评审稿
> 关联文档：`docs/development/express-mode-architecture.md`、`docs/development/express-mode-plan.md`
> 前置排查：普通/极速/服务器三模式的规则数据互通情况已结合代码与存储层逐一核实，结论直接体现在本方案第 2、3 节。

## 1. 背景与目标

应用现有三种工作模式（`AppWorkMode`，`Android/app/src/main/java/com/haoze/diting/ui/mode/AppWorkMode.kt:11`）：

| 模式 | 枚举值 | 实现方式 | 运行时入口 |
| --- | --- | --- | --- |
| 普通模式 | `NORMAL` | Kotlin UI + Go 隧道引擎（`Android/tunnel`） | `DnsVpnService` |
| 服务器模式 | `DNS` | Kotlin UI + Go standalone DNS 引擎 | `DnsModeService` |
| 极速模式 | `EXPRESS` | 纯 Kotlin（无 Go 依赖） | `ExpressVpnService` |

当前三种模式的数据边界不完整：服务器模式拥有独立规则库，但**普通模式与极速模式共用同一套规则数据库、规则索引文件与大量设置项**，且部分清理操作会跨模式波及。

本方案目标：

1. 为三种模式各自建立并维护完全独立的规则数据、订阅、规则索引、DNS 缓存、运行日志与模式相关设置。
2. 明确"全局层"数据（应用外观、语言等）保持共享，不纳入隔离范围。
3. 给出既有用户数据的迁移与兼容策略，保证升级后普通模式零感知、极速模式规则无缝延续。
4. 消除现有跨模式清理、配置导入导出的波及问题。

## 2. 现状结论（排查衔接）

上一轮排查已确认的核心事实，是本方案的出发点：

1. **普通 ⇄ 极速完全互通**：极速模式引擎启动时直接打开普通模式数据库 `diting_database`（`ExpressTunnelManager.kt:236`），共用同一 `rule-index` 索引目录（`ExpressTunnelManager.kt:237`）；极速模式所有规则页面（规则控制/黑名单/白名单/订阅）均以默认 `RuleDataset.NORMAL` 数据集打开（`SettingsRouteActivity.kt:54-57`、`ExpressRuleControlScreen.kt:50`、`MainActivity.kt:130-134`）。
2. **服务器模式已隔离**：拥有独立规则库 `diting_dns_rules`（`DnsRulesDatabase.kt:100`），且刻意不使用磁盘规则索引——`DnsQueryFilter` 以 `indexDirectory = null` 构建纯内存缓存，注释明确"索引文件归 VPN 模式所有"（`DnsQueryFilter.kt:25-53`）。
3. **"快速索引"为普通/极速共用**：Kotlin 侧 `MappedSubscriptionRuleIndex`（自研 DTRI 格式：mmap + 域名树 + Bloom 过滤器，`MappedSubscriptionRuleIndex.kt:19`）由两模式共用；普通模式额外把索引文件路径推给 Go 引擎 `policySnapshot` 复读（`GoTunnelRuleManager.kt:33`、`tunnel/policy_snapshot.go:113-124`、`tunnel/policy_dtri_reader.go`）。
4. **规则订阅普通 ⇄ 极速共通**：订阅记录同表，自动更新共用同一个 WorkManager 任务（NORMAL 数据集分支，`SubscriptionAutoUpdateScheduler.kt:127-135`）。

## 3. 现状数据耦合清单

### 3.1 规则数据库（Room）

| 数据 | 普通模式 | 极速模式 | 服务器模式 |
| --- | --- | --- | --- |
| 规则库文件 | `diting_database`（`AppDatabase.kt:127`） | **同左，共用** | `diting_dns_rules`（独立） |
| block/allow/rewrite/cosmetic/go_url 规则及 source 表 | 共用 | 共用 | 独立 |
| subscription / subscription_group / subscription_auto_update_item | 共用 | 共用 | 独立 |
| mirror_template | 共用 | 共用 | 独立 |

### 3.2 运行时数据表

| 数据 | 普通模式 | 极速模式 | 服务器模式 |
| --- | --- | --- | --- |
| `dns_cache`（DNS 响应缓存） | 使用 | **共用同表**（`ExpressTunnelManager.kt:244`） | 未接入 |
| `dns_log`（解析日志） | 使用 | **共用同表**（`ExpressTunnelManager.kt:245`；`ExpressRequestLogScreen.kt:86` 直读） | 未接入（走 Go 引擎 LogCallback） |
| `race_log` / `bootstrap_log` | 使用 | **共用同表**（`ExpressTunnelManager.kt:246-247`） | 未接入 |
| `http_request_log` / `app_traffic_daily` | 专属（HTTPS 检查/流量统计） | 不使用 | 不使用 |

### 3.3 规则索引文件（DTRI）

| 项 | 说明 |
| --- | --- |
| 路径 | `filesDir/rule-index/`，布局由 `RuleIndexLayout` 统一定义（`RuleIndexLayout.kt:27-48`） |
| 普通模式 | 写入并 mmap 读取；同时把 `.trie` 路径推给 Go 引擎复读 |
| 极速模式 | **与普通模式共写同一批文件**（`ExpressTunnelManager.kt:237`） |
| 服务器模式 | 不使用（纯内存，`DnsQueryFilter.kt:30-53`） |
| 现存风险 | 模式切换瞬间存在两套引擎先后读写同一索引文件的并发窗口；`RuleOperationWorker.kt:156` 注释已意识到"索引文件归 VPN 模式所有"，但极速模式并未遵守该约定 |

### 3.4 SharedPreferences

`dns_vpn_prefs` 是一个被十余个 Store 共用的"超级偏好文件"（`ui/settings/SettingsPreferencesExtensions.kt:5`），普通与极速模式读写其中同一批 key：

| Store / 使用者 | 内容 | 耦合判定 |
| --- | --- | --- |
| `AppRulesSettingsStore` | 域名规则总开关、拦截响应模式、动态拦截配置、地址规则开关、HTTPS 检查等 | 普通/极速共用，**需按模式隔离** |
| `SubscriptionAutoUpdateSettings`（`SubscriptionAutoUpdateScheduler.kt:32`） | 订阅自动更新开关与间隔 | 普通/极速共用，**需按模式隔离** |
| `ResolutionSettingsStore` | 解析模式、竞速/主备服务商选择 | 普通/极速共用，**需按模式隔离** |
| `DnsCacheSettingsStore` | DNS 缓存策略 | 普通/极速共用，**需按模式隔离** |
| `DnsProvider`（`DnsProvider.kt:50`） | 用户服务商列表与选中项 | 普通/极速共用，**需按模式隔离** |
| `ProviderHealthStore` / `BootstrapHealthStore` | 服务商与 Bootstrap 健康权重 | 普通/极速共用，**需按模式隔离** |
| `BootstrapDnsSettingsStore` | Bootstrap DNS 配置 | 普通/极速共用，**需按模式隔离** |
| `SystemSettingsStore` | IPv6 模式、日志模式、通知监控等混合集合 | 部分 key 需隔离（逐 key 盘点，见 Phase 1） |
| `AppLanguageManager` / `HiddenFeaturesStore` / `AppearanceSettingsStore` 等 | 语言、隐藏功能、外观 | 全局，保留共享 |
| `WorkModeStore`（`diting_settings`） | 当前工作模式 | 全局，保留共享 |
| `DnsModePreferences` / `DnsRuleSettings`（`diting_dns_mode_prefs`） | 服务器模式专属 | 已隔离，维持现状 |
| `ExpressVpnController`（`express_vpn_prefs`） | 极速模式运行状态 | 已隔离，维持现状 |

### 3.5 运行时与调度耦合

| 位置 | 现状 | 问题 |
| --- | --- | --- |
| `RuntimeDnsSettingsRefresher.kt:15-87` | 按"当前工作模式"（`WorkModeStore.getAppWorkMode`）分发刷新 | 分发依据是 UI 所处模式而非数据归属；隔离后须改为纯数据集驱动 |
| `RuleOperationWorker.kt:52,145-157` | 已按 `RuleDataset` 分道（NORMAL/DNS_MODE），索引目录按数据集判定 | 需扩展第三数据集 |
| `SubscriptionAutoUpdateScheduler.kt:58-135` | NORMAL 与 DNS_MODE 两套 WorkManager 任务名 | 极速搭 NORMAL 的车；需新增 EXPRESS 任务名 |
| `SubscriptionAutoUpdateEngine.kt:224`（`rebuildCachesAndNotifyRuntime`） | 更新后重建共享索引并按工作模式通知运行引擎 | 需按数据集重建各自索引 |
| `DataCleanupManager.kt:102-146,208-255,356-383` | 清理函数同时清空 `AppDatabase` 与 `DnsRulesDatabase` 两库 | **跨库波及** |
| `ConfigExporter.kt:24` / `ConfigImporter.kt:14` | 硬编码 `AppDatabase` | 极速导入导出虽经 `ExpressConfigAdapter` 裁剪，底层仍读写普通模式存储 |
| `CosmeticRuleManager.kt:25-28`、`DefaultWhitelistSeeder.kt:30` | 单例/播种均绑定 `AppDatabase` | 需标注归属：两者均为普通模式专属能力 |

### 3.6 已确认的用户可见耦合副作用

1. **极速模式清理波及全部模式**：`ExpressDataCleanupScreen.kt:194-204` 直调 `DataCleanupManager.clearAllDomainRules` / `clearAllSubscriptions`，这两个函数会同时清空普通模式与服务器模式的规则库（`DataCleanupManager.kt:102-146,208-255`）。用户在极速模式"清理域名规则"，普通模式和服务器模式的黑白名单、订阅会一并被删除。
2. **普通模式清理波及极速模式**：同理，普通模式清理后极速模式的规则与订阅同时消失。
3. **模式切换的隐式数据跟随**：由于普通/极速共用数据与设置，用户在一个模式下修改总开关、解析模式、服务商后，另一模式行为随之改变，无法分别调优。
4. **清理 DNS 缓存按当前模式判断**（`DataCleanupManager.kt:79-81`）：仅清理共享缓存表并按当前模式刷新引擎，无法只清某一个模式的缓存。

## 4. 隔离目标架构

### 4.1 分层原则

| 层 | 内容 | 策略 |
| --- | --- | --- |
| 全局层 | 工作模式选择（`WorkModeStore`）、外观/主题/背景、语言、通知偏好、隐藏功能、引导与协议状态、隐私授权、崩溃状态、应用更新包 | 保持共享，不纳入隔离 |
| 模式层 | 规则库（黑白名单/覆写/URL/修饰/订阅/镜像模板）、规则索引文件、DNS 响应缓存、解析/竞速/Bootstrap 日志、规则开关与拦截策略、解析模式与服务商配置、健康权重、订阅自动更新配置 | 每模式独立存储，互不可见 |

### 4.2 目标存储布局

| 模式 | 规则与运行时库 | 规则索引目录 | 模式设置 |
| --- | --- | --- | --- |
| 普通模式 | `diting_database`（原库原位，含 `http_request_log`、`app_traffic_daily`） | `filesDir/rule-index/`（原目录原位，避免重建） | `dns_vpn_prefs` 中 `ds_normal_` 前缀 key |
| 极速模式 | **新建** `diting_express`（规则表 + `dns_cache`/`dns_log`/`race_log`/`bootstrap_log`） | `filesDir/rule-index/express/` | `dns_vpn_prefs` 中 `ds_express_` 前缀 key |
| 服务器模式 | `diting_dns_rules`（维持现状） | 不使用（维持纯内存） | `diting_dns_mode_prefs`（维持现状） |

极速模式新库复用现有 Entity/DAO 类（与 `DnsRulesDatabase` 复用方式一致，`RuleDataSources` 接口不变），并追加四个运行时表实体（直接复用 `DnsCacheEntity`/`DnsLogEntity`/`RaceLogEntity`/`BootstrapLogEntity` 与对应 DAO）。`go_url_rule`/`cosmetic_rule` 表仅建表满足 `RuleDataSources` 接口，极速模式物理上不使用（无 HTTPS 检查/内容过滤），种子迁移亦不复制。

## 5. 关键设计决策

### D1：`RuleDataset` 三元化（改动主轴）

`RuleDataset` 增加 `EXPRESS` 枚举值（`data/RuleDataset.kt:19`）。所有按 `NORMAL`/`DNS_MODE` 二元分支的代码统一改为三元分发：

- `RuleDatabases.forDataset`（`DnsRulesDatabase.kt:122-133`）：`EXPRESS -> ExpressRulesDatabase.getInstance(context)`。
- `RuleSettingsAccess`（`ui/settings/RuleSettingsAccess.kt:18`）：新增 `EXPRESS` 分支，读取 `ds_express_` 前缀 key。
- `RuleOperationScheduler` / `RuleOperationWorker` / `SubscriptionAutoUpdateScheduler`：输入数据集从调用方传入（极速 UI 固定传 EXPRESS），新增任务名 `subscription_auto_update_express`（含 retry）。
- `DitingApp.kt:51` 的 `SubscriptionAutoUpdateScheduler.sync` 改为同步三个数据集。

### D2：极速模式独立数据库

新建 `data/ExpressRulesDatabase.kt`，文件名 `diting_express`，version 1，`exportSchema = false`。实体与 DAO 全部复用现有类，新增四个运行时表。单例模式与现有两库一致。

### D3：模式相关 prefs 作用域化

不拆分 prefs 文件，而是引入统一的 key 前缀包装（改动面最小、可灰度）：

- 新增 `ModeScopedPrefs` 工具：`fun key(dataset: RuleDataset, raw: String) = "${dataset.prefix}$raw"`（前缀：`ds_normal_` / `ds_express_`；服务器模式继续走 `diting_dns_mode_prefs`，不参与）。
- 第 3.4 节标记"需按模式隔离"的 Store 内部改为经 `ModeScopedPrefs` 读写；`RuleSettingsAccess` / 各 ViewModel 已持有 dataset 参数，逐层传递即可。
- 普通 key 读取兼容：读取 `ds_normal_x` 前不存在时回退读旧 key `x`（一次性迁移见第 6 节，回退仅作为迁移失败兜底）。
- 全局 Store（外观/语言/隐藏功能/引导等）不改。

### D4：规则索引目录按数据集分域

`RuleIndexLayout` 增加数据集维度：`rootDirectory(filesDir, dataset)`——NORMAL 返回原 `rule-index/`（历史索引继续有效，无需重建），EXPRESS 返回 `rule-index/express/`。调用点同步改造：`ExpressTunnelManager.kt:237`、`DataCleanupManager`（3 处索引重建）、`RuleOperationWorker.kt:157`、`DnsVpnTunnelManager`（普通模式不变）。服务器模式维持 `indexDirectory = null`。

### D5：运行时分发改为数据集驱动

`RuntimeDnsSettingsRefresher` 删除"按当前 WorkMode 判断"的分支（`RuntimeDnsSettingsRefresher.kt:25-28,50-53,75-78`），改为：

- `NORMAL` → 刷新 `DnsVpnService`（若运行）
- `EXPRESS` → 刷新 `ExpressVpnService`（若运行，`ExpressSettingsRefresher` 保留为内部实现）
- `DNS_MODE` → 刷新 `DnsModeService`（维持现状）

`WorkModeStore` 仅用于决定"当前 UI 编辑哪个数据集"：极速 UI（`ExpressMainScreen`/`ExpressRuleControlScreen`/`ExpressFeatureHubScreen` 链路）固定传 `RuleDataset.EXPRESS`；`SettingsRouteActivity` 的 express 分支（`SettingsRouteActivity.kt:311-320`）与 `MainActivity.kt:261-283` 的极速导航全部改传 EXPRESS 数据集。

### D6：配置导入导出按数据集路由

- `ConfigExporter` / `ConfigImporter` 构造函数增加 `dataset` 参数，替换硬编码的 `AppDatabase.getInstance`。
- 导出 JSON 增加元数据字段 `"dataset": "normal" | "express" | "dns"`。
- `ExpressConfigAdapter` 改为以 EXPRESS 数据集操作；导入时按当前模式数据集写入，跨模式导入文件按第 4.1 节分层原则裁剪（全隧道项仅在普通模式数据集落地）。

### D7：数据清理按数据集收敛

- `DataCleanupManager` 所有清理函数增加 `dataset` 参数：只清目标数据集的库、索引、prefs key 与缓存，并只刷新对应运行引擎。
- `ExpressDataCleanupScreen.kt:194-204` 全部改传 `RuleDataset.EXPRESS`，消除第 3.6 节问题 1。
- `clearAllLocalData`（一键全面清理）保留"遍历三个数据集分别清理"的语义，属于用户明确的全局操作。
- `resetCaCertificate` / `resetAppRules` / `resetOutboundProxy` 标注为普通模式专属入口，从极速清理界面移除（当前已未展示，代码层同步收敛）。

### D8：Go 引擎规则面不动

普通模式（DTRI 路径推送 + mmap 复读）与服务器模式（无索引快照）与 Go 侧交互协议均不变；极速模式无 Go 引擎。`Android/tunnel` 本方案零改动。隔离完成后，普通与极速共写 `rule-index` 的并发窗口（第 3.3 节现存风险）自然消除。

## 6. 数据迁移与兼容

### 6.1 迁移范围

| 数据 | 策略 |
| --- | --- |
| 普通模式规则/订阅/设置/索引 | **原位不动**，普通模式用户零感知 |
| 极速模式规则/订阅 | 一次性种子复制：`diting_database` → `diting_express` 的 block/allow/rewrite 规则及 source 表、subscription、subscription_group、subscription_auto_update_item、mirror_template |
| 极速模式设置 | 一次性种子复制 `dns_vpn_prefs` 中模式相关 key（规则开关、拦截响应、解析模式、服务商列表与选中项、缓存策略、Bootstrap 配置、订阅自动更新）→ `ds_express_` 前缀 |
| 规则索引 | 不复制文件；种子完成后对 `rule-index/express/` 执行 `refreshCache(forceRebuild = true)` 重建（DTRI 是纯派生数据，`RuleIndexLayout.kt:24-26` 注释明确可随时重建） |
| 运行时数据（dns_cache、三类日志） | 不迁移，各模式升级后自然重新积累 |
| HTTPS 检查/CA、出站代理、应用管控、流量统计 | 不迁移（极速模式物理不支持） |
| 服务器模式 | 维持"从空开始、无迁移"的既有设计（`DnsRulesDatabase.kt:32-34`） |

### 6.2 迁移触发与流程

1. 版本标记：`diting_settings`（`WorkModeStore` 同文件）写入 `express_dataset_seeded_version`。
2. 触发时机：`DitingApp` 启动后台协程静默执行（优先于用户进入极速模式），不阻塞启动；若用户在种子完成前立即开启极速模式，`ExpressTunnelManager` 现有的 3 秒预热超时（`ExpressTunnelManager.kt:256-268`）按空规则启动，种子完成后通过 `ACTION_SYNC_RULES` 补齐。
3. 种子过程与引擎写入互斥：三模式服务本身互斥运行，种子仅在极速引擎未运行时执行复制；失败则下次启动重试，成功才写版本标记。
4. `fallbackToDestructiveMigration(true)` 对新库无影响（从 version 1 起步）；`diting_database` 结构无任何变更，不触发迁移路径。

### 6.3 兼容与回退

- 降级场景（如回退安装旧版本）：旧版本继续读写 `diting_database` 与旧 key，数据完整保留，仅极速模式新增的数据不回读——可接受。
- 普通 prefs key 读取回退（D3）仅在种子失败时兜底，种子成功后可移除回退逻辑（预留一个版本周期）。
- 订阅自动更新拆分后，NORMAL 与 EXPRESS 两个 Worker 各自下载订阅，网络流量增加属隔离的预期代价，在发版说明中告知。

## 7. 实施计划

按四个阶段推进，每阶段独立可编译、可提交、可回退。

### Phase 1：数据层地基

- [ ] `RuleDataset` 增加 `EXPRESS`；`RuleDatabases` 三元化。
- [ ] 新建 `ExpressRulesDatabase`（规则表 + 4 运行时表）。
- [ ] `RuleIndexLayout` 增加数据集维度，`rootDirectory(filesDir, dataset)`。
- [ ] `ModeScopedPrefs` 工具与 `RuleSettingsAccess` 三元化。
- 验收：编译通过；`grep -rn "RuleDataset.NORMAL" com/haoze/diting/express/` 无新增引用；三库可同时实例化。

### Phase 2：运行时与调度

- [ ] `ExpressTunnelManager` 切换至 `ExpressRulesDatabase` 与 `rule-index/express/`（`ExpressTunnelManager.kt:236-247`）。
- [ ] `RuntimeDnsSettingsRefresher` 改数据集驱动（D5）。
- [ ] `RuleOperationWorker`、`SubscriptionAutoUpdateScheduler`/`Engine`、`DitingApp.sync` 三元化；新增 express 订阅自动更新任务名。
- [ ] `ExpressVpnService` 的 `ACTION_SYNC_RULES` 链路验证（`ExpressVpnService.kt:58`）。
- 验收：极速模式运行时读写仅触碰 `diting_express` 与 `rule-index/express/`；普通模式行为与升级前一致。

### Phase 3：UI 入口与配套功能

- [ ] 极速 UI 全链路传 `RuleDataset.EXPRESS`（`MainActivity.kt:261-283`、`SettingsRouteActivity.kt:311-320` 及 express 各 Screen）。
- [ ] `ConfigExporter`/`ConfigImporter` 数据集参数化；`ExpressConfigAdapter` 切 EXPRESS（D6）。
- [ ] `DataCleanupManager` 数据集参数化；`ExpressDataCleanupScreen` 改传 EXPRESS（D7，修复第 3.6 节问题 1/2/4）。
- [ ] `CosmeticRuleManager`、`DefaultWhitelistSeeder` 标注普通模式专属并断言数据集。
- 验收：极速模式清理/导入导出不再波及其它模式；普通模式清理不再影响极速数据。

### Phase 4：迁移与回归

- [ ] 实现第 6 节种子迁移（表复制 + prefs key 复制 + 版本标记 + 索引重建）。
- [ ] 回归清单：
  - 升级安装 → 首次进入极速模式，规则/订阅/解析配置与升级前一致；
  - 普通模式增删规则 → 极速模式不受影响，反之亦然；
  - 三模式分别清理规则/订阅/缓存，互不波及；
  - 订阅自动更新在三模式下各自按配置执行、互不干扰；
  - 极速模式配置导出 → 卸载重装 → 导入还原；
  - `AppDatabase.getInstance` 全量调用点审查（见第 9 节）。

## 8. 风险与对策

| 风险 | 对策 |
| --- | --- |
| `AppDatabase` 直引用遗漏（隐藏的极速读取路径） | Phase 1 前全量盘点 `grep -rn "AppDatabase.getInstance"`，逐点标注归属（normal-only / dataset-aware / 全局）；验收时极速链路直连数必须为 0 |
| prefs key 盘点不全导致两模式仍读同一 key | 以 Store 为单位逐 key 审查（第 3.4 节清单为基础），`SystemSettingsStore` 等混合 Store 单独出 key 分层表 |
| 种子迁移与用户快速操作竞态 | 种子仅在极速引擎未运行时执行；未完成时极速按空规则启动 + 完成后补同步（6.2 节） |
| 订阅双份下载流量翻倍 | 属隔离预期代价，发版说明告知；后续可评估共享下载缓存的优化项（不在本期） |
| `SystemSettingsStore` 中部分 key 语义本应全局（如隐藏引导） | 逐 key 判定，宁可保留共享也不误隔离造成"设置丢失"观感 |
| 新库 `fallbackToDestructiveMigration` 误伤 | 新库 version 1 起步无迁移路径；后续升版本时再评估移除 destructive |

## 9. 验收清单（代码级）

1. `grep -rn "AppDatabase.getInstance" --include=*.kt`：express 包内零命中；其余命中点均有归属标注。
2. `grep -rn "RuleDataset.NORMAL" com/haoze/diting/express/`：零命中。
3. `grep -rn "\"rule-index\"" --include=*.kt`：仅 `RuleIndexLayout` 与普通模式调用点命中。
4. 三库文件并存：`databases/diting_database`、`databases/diting_dns_rules`、`databases/diting_express`。
5. `filesDir/rule-index/express/` 存在 4 个 `.trie` 产物（block/block.important/allow/allow.important）。
6. 第 7 节 Phase 4 回归清单全部通过。
