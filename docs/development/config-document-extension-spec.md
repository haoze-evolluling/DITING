# 配置文档扩展规范（阶段 0 · K10）

> 目标：新增配置项只能走 `diting-*-config-core` 的“document 构建 + validate + 默认值”单一实现，
> 杜绝“UI 开了引擎不认”“字符串各写一遍”“缺省行为漂移”。本文是落地时的检查清单，不是新机制。

## 1. 适用范围

凡是从 Dart/Kotlin/Dart 设置页写入、最终被 Rust 引擎或内核消费的配置，都属于本文范畴，例如：

- DNS 配置：`diting-dns-config-core`（`ApplyDNSConfig` 文档、provider、缓存、bootstrap）。
- 引擎配置：`diting-config-core`（协议名、阻断响应名、rewrite 表）。
- 出站代理：`diting-outbound-proxy-core`。
- VPN 计划/看门狗：`diting-vpn-config-core`。
- 备份信封：`diting-backup-core`（导入/导出分组）。

后续阶段新增：`diting-route-config-core`、`diting-netprofile-core`、`diting-*-config-core` 的隐私/路由字段等。

## 2. 一条配置项的最小改动集

新增一个配置字段 `foo` 时，必须同时改到下列**全部**位置，缺一即视为未完成：

1. **Rust document 构建**：在对应 crate 的 document 模块里，从输入载荷读取 `foo`、类型收敛（数字/布尔/枚举）、
   写入规范的输出文档结构。未知值不猜测，按 `fallback` 或缺省处理。
2. **Rust validate**：给出**稳定的错误文本**（错误文案是 UI 直接展示的契约）；越界、非法枚举、互相矛盾
   的字段必须在这里拒绝，而不是等引擎运行时。
3. **Rust 默认值**：与 Dart 端“缺省即关闭/缺省即默认”完全一致。默认值集中在一处常量/函数，禁止散落。
4. **Dart 读取与写入**：`legacy_settings_*`/provider 读写 `foo`；页面控件与字段一一对应；空值/旧版本升级
   走统一迁移，不在页面内 `if (foo == null)` 各写一份。
5. **Kotlin（如涉及）**：若 Kotlin 也需要 `foo`（例如 VPN 计划、通知），通过 JNI 内核读取，不自行解析字符串。
6. **测试**：在 crate 的 `tests/*.tsv`（行为冻结夹具）或单测中覆盖：合法值、边界值、非法值、缺省值四类。
7. **备份/迁移**：若 `foo` 需要持久化，纳入 `diting-backup-core` 的对应分组（剔除 token/代理密码等密钥）；
   表结构变更用 `ADD COLUMN` / `CREATE TABLE IF NOT EXISTS`，保证可回滚。

## 3. 命名与对齐约定

- **单一拼写**：同一概念在 Rust document、Dart 字段、Kotlin extra、SQLite 列、备份 JSON 使用同一
  `camelCase`/`snake_case` 约定（沿用各层既有风格），不新造别名。
- **布尔语义**：新增开关默认 `false`（“缺省即关闭”），除非该功能是既有行为的显式延伸并有测试证明。
- **枚举**：只接受白名单值；未知值一律降级到默认或报稳定错误，**绝不**透传到引擎。
- **数值钳制**：范围约束写在 validate（如 `windowSeconds` 10–300），document 层做二次钳制不得改变语义。
- **空集合**：`null` 与 `[]` 的语义必须明确（通常都表示“无”），并在测试中固定。

## 4. 反例（禁止）

- 在页面/Provider 里 `jsonEncode` 手拼引擎配置字符串。
- Rust 与 Dart 各写一份默认值，且数值不同。
- 只在 UI 校验、引擎不校验。
- 新字段未进备份分组，升级/恢复后丢失。
- 错误文案在 Rust 用英文、UI 再映射一份中文。

## 5. 检查清单（提交前逐项确认）

- [ ] document 构建读取了新字段，未知值有确定行为
- [ ] validate 有稳定错误文本，覆盖越界/非法枚举/矛盾组合
- [ ] 默认值与 Dart 端“缺省即关闭”一致，且集中定义
- [ ] Dart 读写与页面控件对应，升级迁移统一
- [ ] 如涉及 Kotlin，经 JNI 内核而非重复解析
- [ ] 夹具/单测覆盖合法、边界、非法、缺省四类
- [ ] 需要持久化的字段已进备份分组（剔除密钥）
- [ ] 表结构变更为 `ADD COLUMN` / `IF NOT EXISTS`，可回滚
