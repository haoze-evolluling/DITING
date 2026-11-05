# Rust 规则内核

`diting-rule-core` 把规则链路上两处纯计算搬到了 Rust，Dart / Kotlin 实现原样保留，Rust 只是
**可选快路径**：

| 入口 | 调用方 | Rust 产物 | 回退 |
|---|---|---|---|
| 规则文档解析 | Dart（`dart:ffi`） | 归类、去重、`$badfilter` 聚合后的紧凑载荷 | `parseCategorizedInDart` |
| DTRI 订阅索引编译 | Kotlin（JNI） | 与 Kotlin 写入器逐字节相同的 mmap 索引文件 | `MappedSubscriptionRuleIndex.compile` |

## 为什么是这两块

- **规则文档解析**：纯函数、零 IO，一行文本进、一组规则出；订阅更新时整份列表在 UI isolate 上
  同步解析，几万到十几万行会直接卡界面。只有 `parseCategorized` 一个入口，失败就回退。
- **DTRI 索引编译**：规则写入后要把整张订阅表重新编译成 Go 引擎 mmap 的 trie，`RuleSnapshotStore`
  的注释写得很直白——“一个 compile 在大型订阅上要几秒”。这是纯 CPU + 一次文件写，输入是
  `EnabledRule` 序列，输出是格式固定的二进制；Kotlin 算法（`HashMap` 节点树 + 排序 + bloom）
  适合用 Rust 重写，且可以用桌面 JVM 参考实现逐字节对拍。

两块都满足：纯计算、真实批量负载、影响面可控（失败回退）、已有可对拍的参考实现。

## 结构

```
rust/
├── Cargo.toml                      # workspace
├── build_android.py                # NDK 交叉编译 + 拷入 jniLibs
├── verify.py                       # fmt / clippy / test / Go 读取 / 基准
├── diting-rule-core/
│   ├── src/models.rs               # ParsedRule / CategorizedRules（对应 rule_models.dart）
│   ├── src/domain.rs               # 域名归一化、字面量 IP（对应 rule_domain_utils.dart）
│   ├── src/line.rs                 # 单行 adblock/URL/cosmetic 解析 + 去重键
│   ├── src/hosts.rs                # hosts 与 dnsmasq（对应 hosts_parser.dart）
│   ├── src/document.rs             # 整份文本聚合（对应 rule_parser.dart）
│   ├── src/ffi.rs                  # C ABI + 二进制载荷
│   ├── src/dtri.rs                 # DTRI 写入器（对应 MappedSubscriptionRuleIndex）
│   ├── src/dtri/tests.rs           # 写入器单测（跳过规则族、排序、载荷解码）
│   ├── src/jni_bridge.rs           # Kotlin 调用 DTRI 写入器的 JNI 入口
│   ├── src/fast_hash.rs            # 去重索引用的随机种子 FxHash
│   ├── examples/bench.rs           # 纯 Rust 解析/编码耗时
│   ├── examples/dtri_bench.rs      # DTRI 编译耗时（可指定同一份语料）
│   ├── tests/dtri_golden.rs        # Rust ↔ 参考实现逐字节对拍（镜像 + JNI 载荷）
│   └── tests/fixtures/             # 共享语料 + 参考实现生成的 .dtri / .pack
└── tools/dtri-reference/
    └── DTRIReference.java          # Kotlin compile 的桌面 JVM 复刻（生成 fixtures / 基准）
```

Dart 侧：

| 文件 | 作用 |
|---|---|
| `android/app/lib/data/rules/rust_rule_core.dart` | 加载 `.so`/`.dll`、校验 ABI、调 FFI、解二进制载荷 |
| `android/app/lib/data/rules/rule_parser.dart` | `parseCategorized` 优先走 Rust，`parseCategorizedInDart` 是基准实现 |
| `android/app/test/rule_parse_rust_parity_test.dart` | Dart ↔ Rust 对拍（逐行语料 + 整份文本 + 6000 行随机拼接） |
| `android/app/tool/rule_core_bench.dart` | 端到端耗时对照（可 AOT 编译） |

Kotlin 侧：

| 文件 | 作用 |
|---|---|
| `.../core/rule/RustRuleIndexCompiler.kt` | 打包 `EnabledRule`、加载 `libditing_rule_core.so`、JNI 调用、失败标记 |
| `.../core/rule/MappedSubscriptionRuleIndex.kt` | 先写 Rust 产物并自校验，任何失败回退原 Kotlin 编译器 |

## 构建与启用

```bash
# 1. 本机（Windows/Linux）构建，供 flutter test、Go 兼容测试与 bench 使用
cd rust && cargo build --release

# 2. Android：交叉编译 arm64-v8a / x86_64 并拷入 app 的 jniLibs
python rust/build_android.py            # --abi arm64 / x86_64 / all（默认 all）
```

不跑第 2 步就照旧走 Dart / Kotlin 实现，功能完全不变。运行时判定：

**解析（Dart 侧 `RustRuleCore`）**

1. `DITING_RULE_CORE=off` → 强制 Dart；
2. 按 `DITING_RULE_CORE_LIB` → 打包名（`libditing_rule_core.so`）→ `rust/target/<profile>/` 依次探测；
3. ABI 版本必须等于 `ABI_VERSION`（`src/ffi.rs`），不匹配即跳过；
4. 调用期任何异常（解码失败等）→ 本次及后续都回退 Dart。

**DTRI（Kotlin 侧 `RustRuleIndexCompiler`）**

1. `System.loadLibrary("diting_rule_core")` 失败（没编 Rust / 老包）→ null，走 Kotlin；
2. 调用期任何 `Throwable`（缺少 JNI 符号的旧 `.so`、载荷异常）→ 本进程后续都走 Kotlin；
3. Rust 返回的镜像先写到临时文件并用 `MappedSubscriptionRuleIndex.load` 自校验，通过才替换正式索引；
   校验失败同样回退 Kotlin 重编。因此坏产物不会留下一个“读不出但看起来存在”的索引。

JNI 符号 `Java_com_haoze_diting_core_rule_RustRuleIndexCompiler_compile` 由 R8 的
`-keepclasseswithmembernames ... { native <methods>; }` 规则保住，无需新增混淆规则。

## 数据流

规则文档解析：一次调用解一整份文档，而不是一行一次跨界：

```
Dart: utf8 bytes ──diting_rule_core_parse──> Rust: 解析 + 去重 + 聚合 ──> 二进制载荷
                                                                          │
Dart: 顺序读取（ASCII 走 String.fromCharCodes，其余走 utf8）<─────────────┘
```

DTRI 索引编译：一次 JNI 调用搬一整份规则，Rust 返回整份镜像：

```
Kotlin: EnabledRule 分页读取 ──pack──> u32 计数 + 每条(pattern, source, flags, appScope, denyallow, dnsType)
        ──JNI──> Rust: 过滤 + trie + bloom ──> DTRI bytes
Kotlin: 写临时文件 → load() 自校验 → 原子替换 → Go 引擎 mmap
```

载荷与文件布局分别是 `src/ffi.rs`、`src/dtri.rs` 顶部注释；改布局或改语义要同时改
`ABI_VERSION` / 参考实现与 fixtures。

## 语义一致性

**解析**：`rule_parse_rust_parity_test.dart` 里 150 条手写语料 + 4000 行合成列表 + 6000 行随机拼接，
逐字段（pattern / rawLine / important / appScope / appInverted / isWildcard / denyallow /
isRegex / dnsType / targetType / targetValue / isException）与计数器和 Dart 全等。

**DTRI**：三层对拍，任何一层挂了都会让 `verify.py` 失败。

1. `tests/dtri_golden.rs`：同一份语料，Rust 输出与 `DTRIReference.java`（Kotlin `compile` 的
   桌面复刻，同样的 `Locale.ROOT` 小写、UTF-16 排序、`HashMap` 去重、bloom 位序）逐字节相等；
   `.pack` fixtures 还钉住了 Kotlin `RustRuleIndexCompiler.pack` 的 JNI 载荷格式，所以改字段顺序
   或长度写法会直接测试失败，不需要装 Android 构建。覆盖大小写、尾点、Unicode、同 pattern 多
   source 取最小、以及全部应跳过的规则族。
2. `android/engine/policy_dtri_rust_test.go`：Go 引擎（真正的消费者）mmap 这些 fixture，
   按自己的 `find` 语义逐条域名查回语料声明的 source。
3. 10 万条规则语料额外做过一次性对照：Rust 镜像与 JVM 参考实现 3,548,571 字节完全一致。

已知边界：

- **bloom 的非 ASCII 命名**：Kotlin 写入器按 UTF-16 code unit 低 8 位做 FNV，Go 读取器按 UTF-8
  字节。纯规则在归一化后是 ASCII，所以不影响实际规则；Rust 复刻**写入器**（逐字节一致），
  不顺手“修”成 UTF-8，否则就不再是 drop-in 替换。
- 解析侧的非 ASCII / BOM / 正则校验边界见试点说明，行为未变。

## 性能（本机 Windows/amd64）

规则解析（`dart compile exe` AOT 对照，语料：真实订阅形态的合成列表）：

| 行数 | Dart | Rust（含 FFI + 载荷解码） | 加速 |
|---|---|---|---|
| 100,000 | 0.98–1.18 s | 0.20–0.27 s | 4.3–5.0x |
| 20,000 | ~0.19 s | ~0.045 s | ~4.3x |

DTRI 编译（10 万条合成订阅，同一份语料，输出均为 3,548,571 字节）：

| 环境 / 实现 | 耗时 |
|---|---|
| 桌面 JVM，冷启动单次 | 565–609 ms |
| 桌面 JVM，`--bench` 预热 3 次取最优 | ~306 ms |
| 本机 Rust `dtri_bench` | ~127 ms |
| 模拟器 ART（x86_64），Kotlin 算法 `--bench` 5 次取最优 | 430–453 ms |
| 模拟器原生（同一台），Rust `dtri_bench` | 116–142 ms |

同一台设备上，原生实现是 ART 上 Kotlin 算法的 **3.0–3.9x**；桌面预热后是 2.4x。
桌面 JVM 与 ART 都不是发布版的真实时序，**输出逐字节相同**才是这次迁移的核心保证。
Rust 侧另外把节点标签放进共享字节池、用 `(parent, label)` 哈希表代替子节点线性扫描，
避免大 fan-out 下的 O(n²)。

复现：

```bash
# 解析侧
cd android/app
dart compile exe tool/rule_core_bench.dart -o build/rule_core_bench.exe
build/rule_core_bench.exe

# DTRI 侧（同一份语料喂两边）
java rust/tools/dtri-reference/DTRIReference.java --generate 100000 /tmp/rules.txt
java rust/tools/dtri-reference/DTRIReference.java /tmp/rules.txt /tmp/ref.dtri
cd rust && cargo run --release --example dtri_bench -- /tmp/rules.txt /tmp/rust.dtri
cmp /tmp/ref.dtri /tmp/rust.dtri && echo 一致

# 只比时间：--bench 在同一个进程里编译多次、取最优，冷 JIT 噪声不会被当成 Rust 的收益
java rust/tools/dtri-reference/DTRIReference.java --bench /tmp/rules.txt 5
cargo run --release --example dtri_bench -- /tmp/rules.txt

# 同一台设备上比（ART 跑 Kotlin 算法，原生跑 Rust）：javac --release 17 + d8 打成 dex，
# 再 `dalvikvm -cp classes.dex DTRIReference --bench rules.txt 5`（Rust 侧推 dtri_bench 二进制）
```

## 验证

```bash
python rust/verify.py            # fmt + clippy -D warnings + cargo test
python rust/verify.py --go       # 再加 Go 引擎读取 Rust DTRI fixture
python rust/verify.py --android  # 再加 arm64-v8a 交叉编译
python rust/verify.py --all      # 全量
```

fixtures 需要重新生成时（改了写入语义就一定一起改）：

```bash
for name in basic sources unicode; do
  java rust/tools/dtri-reference/DTRIReference.java \
    rust/diting-rule-core/tests/fixtures/$name.rules.txt \
    rust/diting-rule-core/tests/fixtures/$name.dtri
done
cd rust && cargo test --test dtri_golden
```

## 后续可做

- **去重键去字符串化**：解析侧目前每条规则拼一个去重键字符串，约占文档解析时间的三成；
  改成对字段哈希 + 碰撞时逐字段比较可以再省一截。
- **DTRI 增量更新**：现在规则一改就整份重编；按 source 分片、只重编受影响的分片，可以把
  万级列表的写入后延迟压到一次小编译。
- **规则检索**：规则页对内存中整张表做 `toLowerCase().contains`，10 万条每键约 25–35 ms
  （桌面实测）；预小写索引放到 Rust 是下一个最合适的纯计算模块。
- **备份导入导出**：纯逻辑部分同样适合这条路（同样的 FFI 形态、同样的对拍测试）。
