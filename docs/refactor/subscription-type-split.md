# 规则订阅按类型拆分重构规划

> 目标：把当前"一次订阅导入全部规则类型"的混合模型，拆分为 **黑白名单规则（block + allow）** 与 **hosts 规则（IP/CNAME 覆写）** 两条独立链路，并同步拆分索引产物与 UI 界面，使数据、导入、索引、界面四层职责对齐。

- 状态：**待评审**
- 影响版本：数据库 v35 → v36
- 影响范围：数据层 / 领域层 / 索引产物 / UI 层 / 配置导入导出

---

## 1. 背景

现状的问题不是"功能坏了"，而是**类型维度缺位**：

1. 订阅表已有 `kind` 字段（`block`/`allow`/`rewrite`/`unified`/`all`），但**导入链路完全没读它**。`CategorizedRuleStreamImporter.import()` 一次解析把 block / allow / rewrite 三桶全部落库，`kind` 只是历史遗留的展示标签。
2. 因此"hosts 订阅"与"域名订阅"在 UI 上是同一列表、同一套操作、同一个统计口径（"黑名单 x / 白名单 y / 覆写 z"混排），用户无法按类型隔离管理。
3. 领域层的"更新订阅"是**跨三表**动作：`SubscriptionRuleStorage.publishStagedRules()` 同时对 block / allow / rewrite 三张规则表执行 source 改名。订阅一旦带上类型语义，这个"跨表"行为就是错误的作用域。
4. 索引产物命名以规则**表**为单位（`subscription-block.trie` / `subscription-allow.trie` / `subscription-rewrite.trie`），没有表达"黑白名单 vs hosts"的类型分层，未来新增产物时无法收敛。

---

## 2. 现状盘点（含证据）

### 2.1 数据模型

| 对象 | 位置 | 说明 |
| --- | --- | --- |
| `SubscriptionEntity.kind` | `data/entity/SubscriptionEntity.kt:16` | 默认 `block`，实际写入 `unified` |
| `SubscriptionKind` | `data/entity/SubscriptionEntity.kt:38-44` | `block` / `allow` / `rewrite` / `unified` / `all`，**无一处读取** |
| 订阅唯一约束 | `SubscriptionEntity.kt:9` | `Index(unique = true) on url` —— 同一 URL 无法作为两种订阅并存 |
| 规则主体表 | `block_rule` / `allow_rule` / `rewrite_rule` | 主体 + `*_source` 关联表，`OnConflictStrategy.IGNORE` 去重 |
| source 命名 | `vpn/SubscriptionRuleStorage.kt:18-20` | `sub_<id>` 正式源、`staging_sub_<id>` 影子源、`useradd`、`local_import`、`local_hosts` |
| DAO 已有能力 | `data/dao/SubscriptionDao.kt:34-53` | `withBlockRules()` / `withAllowRules()` / `withRewriteRules()` —— 已支持"按规则类型反查订阅" |

### 2.2 导入链路

```
UI（RuleManagementViewModel / SubscriptionViewModel）
  └─ RuleOperationScheduler.enqueue(...)              vpn/RuleOperationWorker.kt:70
      └─ SubscriptionManager.addSubscription / addLocalSubscription / updateSubscription
          └─ SubscriptionDownloader.downloadAndImport / downloadAndStage
              └─ CategorizedRuleStreamImporter.import()   vpn/SubscriptionRuleStreamer.kt:25
                  ├─ AdGuardRuleParser.parseCategorizedLine(line)  vpn/AdGuardRuleParser.kt:135
                  └─ 每 1000 条 flush：BlockListManager / AllowListManager / RewriteRuleManager
```

- `kind` 参数在 `SubscriptionManager.addSubscription()` 签名里存在（`SubscriptionManager.kt:79`），但只被写入实体，**未传给 streamer，未参与过滤**。
- `RuleOperationType.IMPORT_RULES` 与 `IMPORT_HOSTS_RULES` 是两个独立入口（`RuleOperationWorker.kt:320-333`），其中 hosts 走 `parseHostsRewriteLine` 只收真实 IP 行。也就是说"本地文件"已经事实上分了两类，**只有订阅链路还是混合的**。
- 统计口径有误：`RuleImportSummary.duplicateCount = parsedRules - inserted`（`SubscriptionRuleStreamer.kt:101`），实际把"类型不匹配被丢弃"的规则也计入了重复。

### 2.3 索引产物

| 现产物 | 生成方 | 说明 |
| --- | --- | --- |
| `rule-index/subscription-block.trie` | `BlockRuleCache`（`vpn/BlockRuleManager` 传入，`BlockListManager.kt:29`） | mmap DTRI，非通配、非 appScope 的订阅规则 |
| `rule-index/subscription-block.trie.important` | 同上，文件名 = `name + ".important"`（`BlockRuleCache.kt:129`） | 同上，important 分桶 |
| `rule-index/subscription-allow.trie` | `AllowListManager.kt:21` | 同上 |
| `rule-index/subscription-allow.trie.important` | `AllowRuleCache.kt:114` | **未被 `DomainPolicy.buildRuleSnapshotJson` 下发**（只传了 `allowTriePath`，`DomainPolicy.kt:131`） |
| `rule-index/subscription-rewrite.trie` | `RewriteRuleManager.kt:29 / 213` | `MappedSubscriptionRewriteIndex`，hosts 覆写 |

- 目录按 scope 分层：DNS 用 `filesDir/rule-index/`，HTTPS 用 `rule-index/https/`（`RuleOperationWorker.kt:144-146`）。
- Go 侧通过 Java 下发的 JSON 快照拿到 trie 路径（`DomainPolicy.buildRuleSnapshotJson`，`tunnel/policy_engine.go:674 applySnapshot`）。
- 编译策略：临时文件 → 原子 rename（`MappedSubscriptionRuleIndex.compileAndLoad`，`MappedSubscriptionRuleIndex.kt:125`），失败回退内存 Map。

### 2.4 UI 现状

| 界面 | 位置 | 现状 |
| --- | --- | --- |
| 规则控制总控页 | `ui/RuleControlScreen.kt` | 全局开关 + 导航入口（URL 规则、订阅、自动更新、镜像模板） |
| 规则列表页 | `ui/RuleListScreen.kt` + `ui/RuleListViewModel.kt` | 已按 `ManagedRuleKind`（`RuleListViewModel.kt:349`）分为 BLOCK / ALLOW / REWRITE / URL_BLOCK / URL_ALLOW 五类，每类可筛选"来源订阅" |
| 订阅管理页 | `ui/SubscriptionScreen.kt` + `SubscriptionViewModel.kt` | **单页混合展示全部订阅**，用 `ruleBreakdowns`（`SubscriptionViewModel.kt:35`）显示"黑名单/白名单/覆写"计数 |
| 添加订阅对话框 | `ui/SubscriptionDialogs.kt` | **无类型选项**，`pendingKind` 硬编码 `SubscriptionKind.UNIFIED`（`SubscriptionScreen.kt:71,118,229`） |
| 配置导入导出 | `ui/ConfigTransferScreen.kt` + `ui/transfer/ConfigImporter.kt` | 订阅按 `scope + url` 判重（`ConfigImporter.kt:789`），不含 kind |

**结论**：规则列表页已经"按类型"了（5 类），订阅链路还没有（混合）。

---

## 3. 目标模型

### 3.1 两类规则的定义

| 类型 | 值 | 覆盖的规则形态 | 落地表 | 索引产物 |
| --- | --- | --- | --- | --- |
| 黑白名单规则 | `domain` | AdGuard `\|\|domain^`、`@@\|\|domain^`、纯域名、dnsmasq sinkhole 行、hosts 中的 sinkhole 行（`0.0.0.0`/`::` 等） | `block_rule` + `allow_rule` | domain 组索引 |
| hosts 规则 | `hosts` | hosts `IP domain...`（真实 IP）、dnsmasq `address=/d/ip`、`$dnsrewrite=` → IPV4 / IPV6 / CNAME | `rewrite_rule` | hosts 组索引 |

> 关键语义：**sinkhole 行归黑白名单，真实 IP 行归 hosts**。这条边界由 `AdGuardRuleParser` 现有的 `SINKHOLE_ADDRESSES`（`AdGuardRuleParser.kt:83`）天然决定，不需要新规则。

### 3.2 kind 语义重定义

```kotlin
object SubscriptionKind {
    const val DOMAIN = "domain"   // 黑白名单（block + allow）
    const val HOSTS  = "hosts"    // hosts 覆写（IPV4 / IPV6 / CNAME）
    // 旧值兼容映射（读取时归一化，不再写入）
    // block / allow / unified / all -> DOMAIN
    // rewrite                       -> HOSTS
}
```

### 3.3 归属矩阵（导入过滤规则）

| 解析桶 | DOMAIN 订阅 | HOSTS 订阅 |
| --- | --- | --- |
| `blockRules` | 入库 | 丢弃，计入 `typeSkippedCount` |
| `allowRules` | 入库 | 丢弃，计入 `typeSkippedCount` |
| `rewriteRules` | 丢弃，计入 `typeSkippedCount` | 入库 |

---

## 4. 拆分范围（文件清单）

### 4.1 数据层
- `data/entity/SubscriptionEntity.kt` —— 重定义 `SubscriptionKind`（`DOMAIN`/`HOSTS`），保留旧值映射函数
- `data/dao/SubscriptionDao.kt` —— 唯一约束改 `(url, kind)`；`byUrl` → `byUrlAndKind`；`allRemote`/`observeAll` 增加 kind 维度查询；`resetAfterRuleCleanup` 按 kind 限定
- `data/AppDatabase.kt` —— `version = 36` + `MIGRATION_35_36`

### 4.2 领域层
- `vpn/SubscriptionRuleStreamer.kt` —— `import()` 增加 `kind` 参数并做三桶过滤；`RuleImportSummary` 新增 `typeSkippedCount`，修正 `duplicateCount` 口径
- `vpn/SubscriptionModels.kt` —— `RuleImportSummary` 字段与 `displayMessage()` 文案
- `vpn/SubscriptionManager.kt` —— `addSubscription` / `addRemoteSubscription` / `addLocalSubscription` / `editSubscription` 全部透传 kind；判重改 `(url, kind)`
- `vpn/SubscriptionDownloader.kt` —— `downloadAndImport` / `downloadAndStage` 透传 kind
- `vpn/SubscriptionRuleStorage.kt` —— **按 kind 限定作用域**：`removeRulesBySource` / `publishStagedRules` / `setSubscriptionRulesEnabled` 只作用于该类型对应的表
- `vpn/RuleOperationWorker.kt` —— 参数带 kind；`IMPORT_RULES` 支持指定类型（或拆为 `IMPORT_DOMAIN_RULES` / `IMPORT_HOSTS_RULES`）
- `ui/RuleManagementViewModel.kt` —— 本地文件导入入口透传类型

### 4.3 索引产物
- `vpn/BlockListManager.kt:29`、`vpn/AllowListManager.kt:21`、`vpn/RewriteRuleManager.kt:29/213`
- `vpn/BlockRuleCache.kt:129`、`vpn/AllowRuleCache.kt:114`（important 文件命名）
- `vpn/DomainPolicy.kt:118-135`（Go 侧 JSON 快照路径）
- 新增：`vpn/RuleIndexLayout.kt` —— 索引目录/文件名的**单一事实来源**（集中定义路径与 legacy 清理清单）

### 4.4 UI 层
- `ui/RuleControlScreen.kt` —— 入口按两类重构
- `ui/RuleListScreen.kt` / `ui/RuleListViewModel.kt` —— 承载两类列表（黑白名单页聚合 BLOCK + ALLOW）
- 新增 `ui/HostsRuleListScreen.kt`（或复用 RuleListScreen 的 REWRITE 模式）
- `ui/SubscriptionScreen.kt` —— 按 kind 过滤渲染；拆为 `DomainSubscriptionScreen` / `HostsSubscriptionScreen`（共用列表与对话框组件）
- `ui/SubscriptionViewModel.kt` —— 按 kind 过滤订阅；`SubscriptionRuleBreakdown` 语义对齐
- `ui/SubscriptionDialogs.kt` —— 添加/编辑对话框增加"类型"选择（黑白名单 / hosts / 自动识别）
- `ui/SubscriptionItemList.kt` —— 列表项类型标识
- `ui/ConfigTransferScreen.kt`、`ui/transfer/ConfigImporter.kt` —— 订阅导出携带 kind、导入按 `(url, kind)` 判重
- `ui/localization/RulesAndSubscriptionLocalization.kt` —— 新增文案 key

---

## 5. 关键设计决策

### D1. 旧订阅的迁移策略（★需决策）

| 方案 | 做法 | 优点 | 缺点 |
| --- | --- | --- | --- |
| **A. 拆记录（推荐）** | 迁移时按各订阅实际持有的规则来源判定：只有黑白名单规则 → `domain`；只有覆写 → `hosts`；两者都有 → **拆成两条订阅记录**，并把对应 source 从 `sub_<oldId>` 重绑到新 id | 语义最干净；"同一 URL 既是域名源又是 hosts 源"成为可表达的产品形态；订阅天然只含一类规则 | 迁移 SQL 最复杂，需在 migration 内取 `last_insert_rowid()` 重绑 source；风险集中在一次迁移 |
| B. 只改标签 | `unified/all/block/allow` → `domain`，`rewrite` → `hosts`；混合型订阅全归 domain，并在更新时按 kind 限定作用域，属于 hosts 侧的历史规则保留但不再随订阅更新 | 迁移极简，风险最低 | 混合订阅的 hosts 部分变成"孤儿规则"（既不更新也不清理），需额外做一次清理提示 |
| C. 延迟拆分 | v36 只做数据打标，导入/索引/UI 三步全上；拆分混合订阅交给用户手动重加 | 风险最低 | 未真正解决混合问题，与本次目标有偏差 |

> ⚠️ 注意：`AppDatabase.kt:100` 已开启 `fallbackToDestructiveMigration(true)`。**迁移若抛异常，用户数据会被直接清空**。方案 A 的复杂度会放大这一风险，必须在迁移内做防御式检查（表/列存在性、单事务、失败可重入）。

### D2. source 命名是否带类型

**保持 `sub_<id>` 不变**（不引入 `sub_domain_<id>`）。理由：订阅 id 全局唯一，类型拆分后同一 URL 的两条订阅天然是两个 id 两个 source，隔离已经成立；改命名会牵动 `LIKE 'sub_%'` 的十余处查询与索引，收益为零。

### D3. 索引目录分层方式

采用**子目录分层**（方案见 §6），不采用 filename 前缀。理由：子目录便于整体清理与整体校验，且未来新增产物时路径语义自洽。

### D4. 旧索引产物处理

**首启原地改名迁移**（`RuleIndexLayout.migrateLegacyLayout()`，由 `DitingApp.onCreate` 在后台线程调用一次）：把旧扁平文件名 `rename` 进新的 `domain/` / `hosts/` 子目录，不做双读兼容、也不强制重建。理由：索引虽是纯派生数据，但全量重建在大订阅上有可感知的首启耗时；rename 是与之等价安全的——目标已存在时删旧文件、rename 失败时也删旧文件，两种情况都自然回落为重建，因此不需要额外兜底分支。无对应新路径的历史残留（`dns-subscription-rewrite.trie`、`https-subscription-rewrite.trie`）直接删除。DNS 与 `https` 两个 scope 目录都做一遍，`migrateScope()` 对不存在的目录直接返回，可重复执行。

### D5. 索引目录的 scope 解析归属

路径解析收敛进 `RuleIndexLayout`：`scopeDirectory(filesDir, scope)` 负责 DNS → `rule-index/`、HTTPS → `rule-index/https/`，`domainDirectory()` / `hostsDirectory()` 负责类型分层。原先 `RuleOperationWorker` 与 `SubscriptionAutoUpdate` 各自内联拼了一遍 `"https"`，现统一走这一处。

---

## 6. 索引产物拆分方案

### 6.1 目录布局（新）

```
filesDir/
├── rule-index/                      # DNS scope
│   ├── domain/
│   │   ├── block.trie               # 原 subscription-block.trie
│   │   ├── block.important.trie     # 原 subscription-block.trie.important
│   │   ├── allow.trie               # 原 subscription-allow.trie
│   │   └── allow.important.trie     # 原 subscription-allow.trie.important
│   └── hosts/
│       └── rewrite.trie             # 原 subscription-rewrite.trie
└── rule-index/https/                # HTTPS scope（同上结构）
    ├── domain/…
    └── hosts/…
```

### 6.2 映射与迁移

| 旧路径 | 新路径 |
| --- | --- |
| `subscription-block.trie` | `domain/block.trie` |
| `subscription-block.trie.important` | `domain/block.important.trie` |
| `subscription-allow.trie` | `domain/allow.trie` |
| `subscription-allow.trie.important` | `domain/allow.important.trie` |
| `subscription-rewrite.trie` | `hosts/rewrite.trie` |
| `dns-subscription-rewrite.trie`、`https-subscription-rewrite.trie` | 直接删除（历史残留） |

- 一次性动作：首启 `rename` 进新目录（见 D4），不做删除重建。
- `RuleIndexLayout` 暴露：`scopeDirectory(filesDir, scope)`、`blockIndex(indexDir)`、`blockImportantIndex(indexDir)`、`allowIndex(indexDir)`、`allowImportantIndex(indexDir)`、`hostsIndex(indexDir)`、`legacyDomainFiles()` / `legacyHostsFiles()`、`migrateLegacyLayout(filesDir)`、`deleteLegacyFiles(indexDir)`、`deleteAll(indexDir)`。
- important 文件名不再由 `BlockRuleCache` / `AllowRuleCache` 从普通索引名推导（旧推导式会得出 `block.trie.important`，与新布局的 `block.important.trie` 不一致），改为由 `RuleIndexLayout` 显式给出两条路径。

### 6.3 顺带修复：important 白名单订阅规则在 Go 引擎侧丢失

**这不是"补个字段"级别的顺手改动，而是一个真实的功能缺陷。**

- `AllowRuleCache` 把订阅白名单拆成两个索引：普通规则进 `allow.trie`，`$important` 规则进 `allow.important.trie`。
- 关键在 `AllowRuleCache.reload()`：当普通索引与 important 索引**都**成功构建时（`mapped != null && importantMapped != null`），`processSubscriptionRule()` 只在 `mapped == null` / `importantMapped == null` 时才把规则放进内存 fallback 集合（`SubscriptionModels.kt` 同侧的 `AllowRuleCache.kt:202-205`）。也就是说**索引存在时，important 订阅规则既不进 fallback，也不在快照里**。
- 而 `DomainPolicy.buildRuleSnapshotJson()` 只下发了 `allowTriePath`，从未下发 `allow.important.trie` → Go 引擎的 Priority 4 完全看不到这批规则。
- 影响：一旦 allow 索引建好，订阅里的 `$important` 放行规则在 **HTTPS / Go 引擎路径下静默失效**（不报错、不崩溃，只是放行不再生效）。Java 侧进程内匹配（`AllowRuleCache.findMatch()` → `findImportantSubscriptionMatch()`）是正常的，所以症状是"两种模式行为不一致"。

修复（本次已实施，Java/Go 同批次）：

1. `DomainPolicy.buildRuleSnapshotJson()` 增下发 `importantAllowTriePath`。
2. `tunnel/policy_engine.go`：`ruleSnapshotJSON` 增 `ImportantAllowTriePath` 字段、纳入 `neededPaths` 生命周期管理、`snap.importantAllowTrie = getOrOpenTrie(...)`、`hasRules` 计入该 trie。
3. `evaluate()` Priority 4 中，`importantAllowTrie` 判定必须排在 `allowTrie` **之前**，与 Java 侧 `findMatch()` 的 important-优先顺序对齐。

---

## 7. 实施步骤

按"每步可独立验证、可回滚"切分。P0/P1 是行为等价改造，P2/P3 才产生可感知变化。

### P0 基础设施（无行为变化）
1. 新增 `SubscriptionKind.DOMAIN` / `HOSTS` 与 `normalizeKind()` 兼容映射。
2. 新增 `RuleIndexLayout`，把三处索引文件名硬编码（`BlockListManager` / `AllowListManager` / `RewriteRuleManager`）收敛进来；**此步先保持旧路径**。
3. 补 `RuleImportSummary.typeSkippedCount` 字段与统计口径（`duplicateCount` 不再混入类型丢弃）。
4. 验证：编译通过；`AdGuardRuleParserTest` / `BlockRuleCacheTest` 保持绿色。

### P1 数据层迁移（v36）
5. `SubscriptionEntity` 唯一索引改为 `(url, kind)`；`byUrl` → `byUrlAndKind`。
6. 编写 `MIGRATION_35_36`：按 §5-D1 选定方案执行（含 source 重绑或仅打标）。
7. 同步改造 `SubscriptionManager` / `SubscriptionRuleStorage` 的判重与作用域（按 kind 限定 promote/delete 的表范围）。
8. 验证：用 v35 数据库副本手工验证迁移（含混合订阅、纯域名订阅、纯 hosts 订阅三种样本）；确认迁移后规则计数与订阅计数符合预期。

### P2 导入链路按类型过滤
9. `CategorizedRuleStreamImporter.import(kind)` 增加三桶过滤 + 类型跳过统计。
10. `SubscriptionDownloader` / `SubscriptionManager` 全线透传 kind。
11. `RuleOperationWorker` 本地文件导入支持指定类型（保留 `IMPORT_HOSTS_RULES` 语义）。
12. 验证：添加一个纯域名订阅 → 只落 block/allow；添加一个 hosts 订阅 → 只落 rewrite；汇总信息中类型跳过数量正确。

### P3 索引产物拆分
13. 切换到 `RuleIndexLayout` 新路径，落地 legacy 清理。
14. 更新 `DomainPolicy` 快照路径 + 补 `importantAllowTriePath`；同步改 Go 侧 `applySnapshot`。
15. 验证：DNS 模式与 **HTTPS 模式** 双模式回归（拦截、放行、覆写各取 3 条样本）；首启重建耗时与内存无异常；`rule-index` 目录只剩新结构。

### P4 UI 拆分
16. `RuleControlScreen` 入口改为"黑白名单规则 / hosts 规则"两个分组。
17. 订阅页按 kind 拆分渲染；添加/编辑对话框增加类型选择（含"自动识别"入口，映射到按内容判定）。
18. 新增 hosts 规则列表页（复用 `RuleListScreen` 的 REWRITE 分支或独立实现）。
19. `ConfigTransfer` 导出携带 kind，导入按 `(url, kind)` 判重。
20. 文案与本地化 key 补齐；更新 `README.md` / `README.zh-CN.md` 的"规则过滤与地址覆写"章节描述。
21. 验证：UI 全链路手工回归（添加 / 更新 / 重命名 / 启用停用 / 删除 / 分组 / 自动更新）。

### P5 收尾
22. 清理 `SubscriptionKind` 的 `UNIFIED`/`ALL` 写入路径与死代码（`REWRITE`/`block`/`allow` 旧常量删除，仅保留读取映射）。
23. 移除 `RewriteRuleManager` 里重复的 `LEGACY_INDEX_FILE_NAME` 常量。

---

## 8. 风险与缓解

| 风险 | 等级 | 缓解措施 |
| --- | --- | --- |
| DB 迁移失败触发 destructive migration，用户规则全丢 | **高** | 迁移单事务；先做 v35 副本演练；`fallbackToDestructiveMigration` 保持开启但迁移内做存在性防御；发版说明标注"首次启动会重建索引" |
| 迁移中 source 重绑（方案 A）出错，规则挂到错误订阅 | 高 | 重绑与索引重建都在同一事务；迁移后跑一次一致性校验（孤儿 source 数应为 0） |
| 索引路径变更后 Go 侧拿不到 trie，HTTPS 模式拦截失效 | 中 | Java/Go 同批次改；`applySnapshot` 失败时保留旧快照；双模式回归必须覆盖 |
| 首启强制重建索引导致启动变慢 | 中 | 重建在 IO 线程并已有 fallback；可对比重建前后的启动耗时指标 |
| 旧订阅在用户眼中"少了一半规则" | 中 | 更新订阅时的汇总信息明确提示类型跳过数量；文档说明类型语义变化 |
| UI 拆分导致入口变深 | 低 | 在规则控制页保留两类入口的计数与状态摘要 |

---

## 9. 验收清单

- [ ] 添加"黑白名单"类型订阅，库中只产生 block/allow 规则
- [ ] 添加"hosts"类型订阅，库中只产生 rewrite 规则
- [ ] 同一 URL 可分别作为两类订阅添加（唯一约束为 `(url, kind)`）
- [ ] 更新订阅只影响对应类型表，另一类型规则数量不变
- [ ] `rule-index` 下只存在 `domain/` 与 `hosts/` 两种子目录，旧文件已清理
- [ ] DNS 模式与 HTTPS 模式的拦截 / 放行 / 覆写行为与重构前一致
- [ ] 订阅停用、删除、分组、自动更新、重命名全链路正常
- [ ] 配置导出→导入往返后订阅种类与规则归属不变
- [ ] 旧版本（v35）数据库升级到 v36 后规则无丢失（含混合订阅样本）

---

## 10. 边界（本次不做）

- **URL 规则（`GoUrlRule` / `ManagedRuleKind.URL_BLOCK` / `URL_ALLOW`）不参与本次拆分**，它属于 HTTPS 抓包体系，与订阅链路无关。
- 不重命名 `sub_<id>` source 格式。
- 不改 `RuleScope`（HTTPS scope 已退化为兼容用途，`RuleScope.kt:3`）。
- 不引入规则类型的第三类（例如把 CNAME 覆写从 hosts 中再拆出）。
- 不重构 `AdGuardRuleParser` 的解析逻辑本身。
