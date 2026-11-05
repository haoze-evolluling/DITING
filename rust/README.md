# Rust 规则内核（试点）

`diting-rule-core` 是把 Android 端规则解析链路（AdGuard/ABP 行解析、hosts、dnsmasq、去重与
`$badfilter` 聚合）移植到 Rust 的**试点**：Dart 实现原样保留，Rust 只是可选快路径。

## 为什么是这块

- **纯函数、零 IO**：一行文本进，一组规则出，语义可以逐字段和 Dart 对拍。
- **真实批量负载**：订阅更新时整份列表在 UI isolate 上同步解析，几万到十几万行会直接卡界面。
- **影响面可控**：只有 `parseCategorized` 一个入口，失败就回退，规则入库（sqflite）完全不动。
- **已有测试**：`android/app/test/rule_parse_test.dart` 锁定了语义，加上新的对拍测试。

## 结构

```
rust/
├── Cargo.toml                      # workspace
├── build_android.py                # NDK 交叉编译 + 拷入 jniLibs
└── diting-rule-core/
    ├── src/models.rs               # ParsedRule / CategorizedRules（对应 rule_models.dart）
    ├── src/domain.rs               # 域名归一化、字面量 IP（对应 rule_domain_utils.dart）
    ├── src/line.rs                 # 单行 adblock/URL/cosmetic 解析 + 去重键
    ├── src/hosts.rs                # hosts 与 dnsmasq（对应 hosts_parser.dart）
    ├── src/document.rs             # 整份文本聚合（对应 rule_parser.dart）
    ├── src/ffi.rs                  # C ABI + 二进制载荷
    ├── src/fast_hash.rs            # 去重索引用的随机种子 FxHash
    └── examples/bench.rs           # 纯 Rust 解析/编码耗时
```

Dart 侧：

| 文件 | 作用 |
|---|---|
| `android/app/lib/data/rules/rust_rule_core.dart` | 加载 `.so`/`.dll`、校验 ABI、调 FFI、解二进制载荷 |
| `android/app/lib/data/rules/rule_parser.dart` | `parseCategorized` 优先走 Rust，`parseCategorizedInDart` 是基准实现 |
| `android/app/test/rule_parse_rust_parity_test.dart` | Dart ↔ Rust 对拍（逐行语料 + 整份文本 + 6000 行随机拼接） |
| `android/app/tool/rule_core_bench.dart` | 端到端耗时对照（可 AOT 编译） |

## 构建与启用

```bash
# 1. 本机（Windows/Linux）构建，供 flutter test 与 bench 使用
cd rust && cargo build --release

# 2. Android：交叉编译 arm64-v8a / x86_64 并拷入 app 的 jniLibs
python rust/build_android.py            # --abi arm64 / x86_64 / all（默认 all）
```

不跑第 2 步就照旧走 Dart 实现，功能完全不变。运行时判定见 `RustRuleCore`：

1. `DITING_RULE_CORE=off` → 强制 Dart；
2. 按 `DITING_RULE_CORE_LIB` → 打包名（`libditing_rule_core.so`）→ `rust/target/<profile>/` 依次探测；
3. ABI 版本必须等于 `ABI_VERSION`（`src/ffi.rs`），不匹配即跳过；
4. 调用期任何异常（解码失败等）→ 本次及后续都回退 Dart，不影响导入。

## 数据流

一次调用解一整份文档，而不是一行一次跨界：

```
Dart: utf8 bytes ──diting_rule_core_parse──> Rust: 解析 + 去重 + 聚合 ──> 二进制载荷
                                                                          │
Dart: 顺序读取（ASCII 走 String.fromCharCodes，其余走 utf8）<─────────────┘
```

载荷格式在 `src/ffi.rs` 顶部注释里；改布局或改语义就同时改 `ABI_VERSION` 与
`rust_rule_core.dart` 的 `_abiVersion`，否则加载端会拒绝并回退。

### ABI 与打包目标

`build_android.py` 默认编 `arm64-v8a` + `x86_64`，但**进不进包由 `android/app` 的 Gradle 策略
决定**（见 `app/build.gradle.kts` 的“ABI policy”）：

| 构建 | Flutter 参数 | 进包的 Rust `.so` |
|---|---|---|
| Release（`build_apk.bat` [3]，默认） | `--target-platform android-arm64 -PditingAbi=arm64` | 仅 `arm64-v8a` |
| Release（`ditingAbi` 未指定） | `flutter build apk --release` | 仅 `arm64-v8a`（release 固定剔除 x86_64） |
| Release 上模拟器 / 双 ABI 分发 | `-PditingAbi=all` | `arm64-v8a` + `x86_64` |
| Debug（`build_apk.bat` [1][2]，默认） | 未指定 `ditingAbi` | `arm64-v8a` + `x86_64` |
| 按 ABI 拆包 | `--split-per-abi -PditingAbi=all` | 按 `--target-platform` 各自一个 |

也就是说 release 只发 `arm64-v8a`，`rust/build_android.py` 编出来的 x86_64 产物会被
Gradle 的 `jniLibs.excludes` 剔除，不占体积；它的作用是为 debug 包与模拟器实例准备。
反过来说，只跑 `python rust/build_android.py --abi arm64` 时，任何带 x86_64 的变体都会因为
缺库而回退 Dart——功能正常，只是没走快路径。

Android 15+ 的 16 KB 页要求同样覆盖这个库：NDK r27+ 的链接器默认按 `0x4000` 对齐，
`llvm-readelf -l` 可直接核对。

## 语义一致性

`rule_parse_rust_parity_test.dart` 里 150 条手写语料 + 4000 行合成列表 + 6000 行随机拼接，
逐字段（pattern / rawLine / important / appScope / appInverted / isWildcard / denyallow /
isRegex / dnsType / targetType / targetValue / isException）与计数器和 Dart 全等。

已知边界（都在语料内验证过，不影响实际规则列表）：

- 非 ASCII 域名：Dart 走 `Uri.parse` 后百分号编码，逐字复刻其结果（`#`/`?`/`\`/userinfo 之后
  的 ASCII 部分仍会被接受）。
- `\uFEFF`（BOM）开头的行：`rawLine` 保留 BOM；Dart 的 `utf8.decode` 会吞掉开头 BOM，故解码端
  显式补回。
- 非 ASCII 的 `toLowerCase` 特例（如开尔文符号 → `k`）不逐字节复刻。
- 正则合法性：Dart 用 `RegExp` 编译校验；Rust 侧只做保守的结构校验（括号/字符类/量词）。
  多接受的正则会在 Go 引擎加载时被跳过并记日志，不会让引擎加载失败。

## 性能（本机 Windows/amd64，`dart compile exe` AOT 对照）

语料：真实订阅形态的合成列表（域名规则 / hosts / cosmetic / regex / 重复行混合）。

| 行数 | Dart | Rust（含 FFI + 载荷解码） | 加速 |
|---|---|---|---|
| 100,000 | 0.98–1.18 s（85–100k 行/s） | 0.20–0.27 s（370–500k 行/s） | 4.3–5.0x |
| 20,000 | ~0.19 s | ~0.045 s | ~4.3x |

数值取三次运行，波动来自本机（VM）负载；比例比绝对值更值得看。

纯 Rust 侧（`cargo run --release --example bench`）10 万行约 0.15–0.21 s，其中载荷编码约 7 ms，
即绝大多数时间在解析与去重；FFI 与解码只是零头。

复现：

```bash
cd android/app
dart compile exe tool/rule_core_bench.dart -o build/rule_core_bench.exe
build/rule_core_bench.exe
```

## 后续可做

- **移出 UI isolate**：现在仍同步解析（100k 行 ≈ 0.2 s）。下一步可以把调用丢进
  `Isolate.run`，但要接受规则对象跨 isolate 的拷贝成本，或改成 Rust 直接写库。
- **去重键去字符串化**：目前每条规则拼一个去重键字符串，约占文档解析时间的三成；
  改成对字段哈希 + 碰撞时逐字段比较可以再省一截。
- **扩大范围**：`rule_domain_utils.dart` 之外，日志聚合、备份导入等纯逻辑模块同样适合这条路
  （同样的 FFI 形态、同样的对拍测试）。
