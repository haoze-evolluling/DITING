# Rust 规则内核

`diting-rule-core` 把规则链路上三处纯计算搬到 Rust。Dart / Kotlin 实现原样保留，Rust 只是
**可选快路径**，任何失败都回退，功能不变：

| 入口 | 调用方 | Rust 产物 | 回退 |
|---|---|---|---|
| 规则文档解析 | Dart（`dart:ffi`） | 归类、去重、`$badfilter` 聚合后的紧凑载荷 | `parseCategorizedInDart` |
| 规则页检索 | Dart（`dart:ffi`，句柄） | 预折叠索引，查询返回命中行号 | `filteredRulesProvider` 的 `.where` |
| DTRI 索引编译 | Kotlin（JNI） | 与 Kotlin 写入器逐字节相同的 mmap 索引 | `MappedSubscriptionRuleIndex.compile` |

选它们是因为同时满足：纯计算零 IO、真实批量负载（十万行级 / 每键重算）、影响面可控（失败回退）、
已有可逐字节对拍的参考实现。解析每份文档一次调用，检索折叠一次查询只扫字节，DTRI 是
“一个 compile 在大型订阅上要几秒”的纯 CPU + 一次文件写。

## 结构

```
rust/
├── build_android.py                # NDK 交叉编译 + 拷入 jniLibs
├── verify.py                       # fmt / clippy / test / Go 读取 / 基准
├── diting-rule-core/src/
│   ├── models.rs domain.rs line.rs hosts.rs document.rs   # 解析（对应 rule_parser.dart 等）
│   ├── ffi.rs                      # 解析的 C ABI + 载荷格式（ABI_VERSION）
│   ├── search.rs search_ffi.rs     # 折叠与检索索引、C ABI、句柄（SEARCH_ABI_VERSION）
│   ├── dtri.rs dtri/tests.rs       # DTRI 写入器（对应 MappedSubscriptionRuleIndex）
│   ├── jni_bridge.rs               # Kotlin 调用 DTRI 的 JNI 入口
│   └── fast_hash.rs                # 去重索引用的随机种子 FxHash
├── examples/                       # bench.rs / search_bench.rs / dtri_bench.rs（纯 Rust 计时）
├── tests/dtri_golden.rs + fixtures/ # Rust ↔ 参考实现逐字节对拍
└── tools/dtri-reference/DTRIReference.java   # Kotlin compile 的桌面 JVM 复刻（生成 fixtures / 基准）
```

- Dart：`rust_rule_core.dart`（加载 `.so`、校验 ABI、解载荷）、`rule_parser.dart`、
  `rule_search_index.dart`（表变化即释放）、`rules_providers.dart`；
  对拍在 `test/rule_parse_rust_parity_test.dart`、`test/rule_search_rust_parity_test.dart`；
  端到端计时在 `tool/rule_core_bench.dart`、`tool/rule_search_bench.dart`。
- Kotlin：`RustRuleIndexCompiler.kt`（打包 `EnabledRule` + JNI + 失败标记）、
  `MappedSubscriptionRuleIndex.kt`（先写 Rust 产物并自校验，失败回退）。

## 构建与启用

```bash
cd rust && cargo build --release        # 本机：供 flutter test、Go 兼容测试与 bench 使用
python rust/build_android.py            # Android：arm64-v8a / x86_64 交叉编译并拷入 jniLibs
```

不跑第二步就照旧走 Dart / Kotlin，功能完全不变。运行时判定：

- **解析**：`DITING_RULE_CORE=off` 强制 Dart；否则按 `DITING_RULE_CORE_LIB` → 打包名 →
  `rust/target/<profile>/` 探测，`ABI_VERSION` 不匹配即跳过；调用期异常后本进程一直回退。
- **检索**：与解析共用 `.so` 但 ABI 独立，缺符号或 `SEARCH_ABI_VERSION` 对不上只用 Dart 过滤
  （解析不受影响）；首次真正查询才建索引（空查询与启动期分页不付折叠成本）；失败后本进程不再重试。
- **DTRI**：`loadLibrary` 失败或调用期任何 `Throwable` → 本进程走 Kotlin；Rust 镜像先写临时文件
  并用 `MappedSubscriptionRuleIndex.load` 自校验，通过才原子替换。

JNI 符号 `Java_com_haoze_diting_core_rule_RustRuleIndexCompiler_compile` 由 R8 的
`-keepclasseswithmembernames ... { native <methods>; }` 保住，无需新增混淆规则。

## 数据流

```
解析：utf8 bytes ──parse──> Rust 解析+去重+聚合 ──> 二进制载荷 ──> Dart 顺序读取
DTRI：EnabledRule 分页 ──pack──> u32 计数 + 每条(pattern, source, flags, appScope, denyallow, dnsType)
       ──JNI──> Rust 过滤+trie+bloom ──> 写临时文件 → load() 自校验 → 原子替换 → Go mmap
检索：规则表 ──search_build──> 折叠进连续 arena ──> 句柄
       查询词 ──search_query(句柄)──> 折叠查询词 + 扫描 ──> 命中行号（Uint32List）
       规则表变化 → search_free_index(句柄)
```

布局与语义的权威注释在 `src/ffi.rs`、`src/search_ffi.rs`、`src/dtri.rs` 顶部；改动要同步对应的
`ABI_VERSION` / `SEARCH_ABI_VERSION`、参考实现与 fixtures。

## 语义一致性

**解析**：150 条手写语料 + 4000 行合成列表 + 6000 行随机拼接，逐字段（pattern / rawLine /
important / appScope / appInverted / isWildcard / denyallow / isRegex / dnsType / targetType /
targetValue / isException）与计数器对拍，与 Dart 全等。

**检索**：Rust 命中行号与「原来的 Dart 过滤」逐条对比（150 行语料 × 24 查询、2000 行随机表 ×
120 随机查询），以及 `filteredRulesProvider` 整链路结果。难点是折叠必须与 `String.toLowerCase`
完全一致：

- Dart 折叠上下文无关（`'ΑΣ'` → `ασ`），`str::to_lowercase` 会套 final-sigma（`ας`），故逐 `char` 折叠；
- `U+0130`（İ）Dart 折叠成 `i`，Unicode 是 `i` + 组合点，单独钉住映射；
- Dart 折叠表比 Unicode 旧，Deseret / Cherokee / Vithkuqi 等区块不动；`search.rs` 的
  `DART_UNMAPPED` 是逐码点跑 `String.toLowerCase` 对拍得出的 465 个码点（合并成区间）。

已知边界：Dart 按 UTF-16 码元匹配、Rust 按 UTF-8 字节匹配，只有查询词含孤立代理项这类构造不出
的输入才有差异；规则模式解析后不含孤立代理项。

**DTRI**：三层对拍，任一层失败 `verify.py` 即报错。

1. `tests/dtri_golden.rs`：与 `DTRIReference.java`（同样的 `Locale.ROOT` 小写、UTF-16 排序、
   `HashMap` 去重、bloom 位序）逐字节相等；`.pack` fixtures 钉住 JNI 载荷格式。覆盖大小写、尾点、
   Unicode、同 pattern 多 source 取最小、应跳过的规则族。
2. `android/engine/policy_dtri_rust_test.go`：Go 引擎 mmap 这些 fixture，按自身 `find` 语义查回
   语料声明的 source。
3. 10 万条语料一次性对照：Rust 镜像与 JVM 参考实现 3,548,571 字节完全一致。

已知边界：bloom 的 Kotlin 写入器按 UTF-16 码元低 8 位做 FNV、Go 读取器按 UTF-8 字节；纯规则归一化后
是 ASCII 故不影响，Rust 复刻写入器（逐字节一致）而不“修”成 UTF-8，否则不再是 drop-in 替换。

## 性能（本机 Windows/amd64）

规则解析（`dart compile exe` AOT，本机合成语料，Rust 含 FFI + 载荷解码）：

| 行数 | Dart | Rust | 加速 |
|---|---|---|---|
| 100,000 | 0.98–1.18 s | 0.20–0.27 s | 4.3–5.0x |
| 20,000 | ~0.19 s | ~0.045 s | ~4.3x |

DTRI 编译（10 万条，输出均为 3,548,571 字节）：

| 环境 / 实现 | 耗时 |
|---|---|
| 桌面 JVM 冷启动单次 | 565–609 ms |
| 桌面 JVM `--bench` 预热 3 次取最优 | ~306 ms |
| 本机 Rust `dtri_bench` | ~127 ms |
| 模拟器 ART（x86_64）Kotlin 算法 `--bench` 5 次取最优 | 430–453 ms |
| 模拟器原生（同一台）Rust `dtri_bench` | 116–142 ms |

同设备原生是 ART 上 Kotlin 的 3.0–3.9x，桌面预热后 2.4x。JVM 与 ART 都不是发布时序，**逐字节相同**
才是核心保证；Rust 另把节点标签放进共享字节池、用 `(parent, label)` 哈希表代替子节点线性扫描。

规则页检索（AOT，10 万行，6 个查询取最优，含 FFI 与命中解码）：

| 实现 | 每键耗时 |
|---|---|
| Dart `toLowerCase().contains`（迁移前） | 15–20 ms |
| Rust 索引（含 12–14 ms 纯扫描） | 2.4–3.5 ms |

约 5x。首次查询前一次性折叠约 30 ms（编码 17–20 ms + FFI ~2 ms + Rust 折叠 ~10 ms），之后仅在规则表
变化时重建；空查询与启动期分页不建索引。纯 Rust（不含 FFI）用 `examples/search_bench.rs` 测：100k 行
构建 9–15 ms、扫描 2.4–3.5 ms/查询。折叠文本存在连续 arena（每条一个 `(start, len)`），100k 行从
200k 个 `String` 变成一次分配；命中行号用 `Uint32List` 回传，宽查询不会因装箱把收益吐回去。

复现：

```bash
cd android/app && dart compile exe tool/rule_core_bench.dart -o build/rule_core_bench.exe && build/rule_core_bench.exe
dart compile exe tool/rule_search_bench.dart -o build/rule_search_bench.exe && build/rule_search_bench.exe
cd rust && cargo run --release --example search_bench

# DTRI（同一份语料喂两边）
java rust/tools/dtri-reference/DTRIReference.java --generate 100000 /tmp/rules.txt
java rust/tools/dtri-reference/DTRIReference.java /tmp/rules.txt /tmp/ref.dtri
cargo run --release --example dtri_bench -- /tmp/rules.txt /tmp/rust.dtri
cmp /tmp/ref.dtri /tmp/rust.dtri && echo 一致
java rust/tools/dtri-reference/DTRIReference.java --bench /tmp/rules.txt 5   # 同进程多次取最优
# 同设备对比：javac --release 17 + d8 打成 dex，dalvikvm -cp classes.dex DTRIReference --bench rules.txt 5
```

## 验证

```bash
python rust/verify.py            # fmt + clippy -D warnings + cargo test
python rust/verify.py --go       # 再加 Go 引擎读取 Rust DTRI fixture
python rust/verify.py --dart     # 再加解析与检索的 Dart ↔ Rust 对拍
python rust/verify.py --android  # 再加 arm64-v8a 交叉编译
python rust/verify.py --all      # 全量
```

`--dart` 需要先 `cargo build --release`（Dart 侧按约定探测 `rust/target/release/`），未构建时对拍
用例自行 skip，不会假绿。改了写入语义要一起重生成 fixtures：

```bash
for name in basic sources unicode; do
  java rust/tools/dtri-reference/DTRIReference.java \
    rust/diting-rule-core/tests/fixtures/$name.rules.txt \
    rust/diting-rule-core/tests/fixtures/$name.dtri
done
cd rust && cargo test --test dtri_golden
```

## 新模块迁移检查清单

下一个候选模块过不了这几条就不搬：

1. 先证明是纯计算且在热路径上（十万级行、秒级耗时或每键重算），否则载荷编解码只会更慢。
2. 原实现留下当基准，Rust 只做快路径：失败回退，不向用户抛错。
3. 一次调用搬一整批；跨多次调用（如索引）用句柄并在源数据变化 / 页面销毁时显式释放。
4. 独立 ABI 版本号，旧产物只降级这一条快路径，不牵连已迁移模块。
5. 对拍为主：Rust 单测 + 与 Dart/Kotlin 参考实现逐字段 / 逐字节对比，不一致即失败。
6. 基准可复现：`examples/*_bench.rs` 测纯 Rust，`tool/*_bench.dart` 测端到端，数字写进“性能”。
7. 接进 `verify.py`，让“语义没变”可持续验证而非一次性检查。
8. 非 ASCII、大小写、排序等差异要么对齐要么写进“已知边界”，不顺手“修”成自己认为更对的样子。

## 后续可做

- **去重键去字符串化**：每条规则拼一个去重键约占解析时间三成，改成字段哈希 + 碰撞时逐字段比较。
- **DTRI 增量更新**：按 source 分片只重编受影响分片，把万级列表的写入后延迟压到一次小编译。
- **检索索引预热**：表稳定后在空闲时预热，把首次折叠的 ~30 ms 从“第一个键”挪开。
- **备份导入导出**：同样适合这条路，但语义面大得多，需先精简备份格式再逐组迁移。
