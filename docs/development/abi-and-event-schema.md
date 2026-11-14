# FFI ABI 版本与事件 schema（阶段 0 · K9）

> 目标：多内核、多入口（Dart `dart:ffi`、Kotlin JNI、服务/工作管理器/广播接收器）协作时，
> **ABI 版本可校验、事件 JSON schema 冻结**，外部观察者（Tasker/脚本/未来本地 HTTP API）不追着漂移的字段跑。

## 1. 每个内核独立的 `ABI_VERSION`

- 每个 `diting-*-core` crate 在 `src/ffi.rs`（或 `jni_bridge.rs` 所在的 `lib.rs`）导出一个
  `pub const ABI_VERSION: u32`，并在 `lib.rs` 里 `pub use ffi::ABI_VERSION;`。
- 变更**payload 布局或语义**时必须自增该常量；加载方（Dart `Rust*Core.instance`、JNI 包装）持有同值常量，
  不一致即“缺库硬报错”，不写第二套实现。
- 现有约定：JSON 载荷前缀固定 8 字节头 —— `magic(u32 LE) | abi(u32 LE)`。magic 用于区分内核
  （如 `DSC1`=subscription，`DSC2`=schedule，`DHC1`=hit），旧库/串库会被立即拒绝。

阶段 0 新增内核的 ABI 常量：

| crate | ABI 常量 | 载荷头 magic |
|---|---|---|
| `diting-schedule-core` | `ABI_VERSION = 1` | `DSC2` |
| `diting-hit-core` | `ABI_VERSION = 1` | `DHC1` |
| `diting-event-core` | `SCHEMA_VERSION = "diting.event/1"`（JNI，无二进制头） | — |

## 2. 伞库版本：`diting_kernels_abi_version()`

`diting-kernels`（`libditing_kernels.so`）额外导出一个 bundle 级版本：

```c
uint32_t diting_kernels_abi_version(void); // 返回 KERNELS_ABI_VERSION
```

加载方可以先校验 bundle 版本，再逐个 probe 具体内核入口。引擎数据面 `libditing_engine.so` 保持独立，
不混入此版本。

## 3. 事件信封（冻结）

单一信封，事件名在 `event` 字段；版本在 `schema` 字段。**2.5.x 内只增字段，不改名、不删字段**。

```json
{
  "schema": "diting.event/1",
  "event": "state_changed",
  "ts": 1710000000000,
  "source": "android",
  "data": {
    "workMode": "normal",      // normal | dns | express | unknown
    "running": true,
    "reclaiming": false,
    "persisted": true,
    "startedAt": 1710000000000, // 0 = 未运行
    "pausedUntil": 0,           // 0 = 未暂停
    "error": null               // string | null
  }
}
```

- 实现唯一来源：`rust/diting-event-core/src/schema.rs`（`state_changed` + `validate`），Kotlin 通过
  `com.haoze.diting.automation.EventNative` 走 JNI 生成，不手拼 JSON。
- 广播动作：`com.haoze.diting.action.STATE_CHANGED`，靠**签名级**自定义权限
  `com.haoze.diting.permission.RECEIVE_EVENTS` 限定接收方（外部 App 不持签名无法接收，也不影响系统）。
- 有效期：整个 `2.5.x` 冻结；升级 schema 版本视为破坏性变更，需同步通知所有外部消费者。

## 4. 新增事件 / 新增字段的流程

1. 在 `schema.rs` 增加常量与构建函数，`validate` 同步支持；旧事件保持不变。
2. 单测覆盖：合法信封、未知枚举折叠、缺失/类型错误被拒。
3. 如外部需要，更新本文件的事件表与字段说明（additive）。
4. 事件名与字段名一旦发布即视为契约，禁止复用为不同语义。

## 5. 安全边界

- 事件广播不携带密钥/代理密码等敏感字段，`error` 只放稳定错误文本。
- 广播接收方按签名权限过滤；自动化入口 `AutomationReceiver` 另用签名级 `CONTROL` 权限。
- 任何 ABI/schema 不一致都必须**硬失败**（抛错/拒绝），不得静默降级到第二套实现。
