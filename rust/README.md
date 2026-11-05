# Rust 内核

两个 crate：`diting-rule-core` 负责规则数据的解析与索引，`diting-policy-core` 负责
**Go 隧道引擎的规则判定内核**。两侧的原实现（Dart / Kotlin / Go）都原样保留，任何失败都回退，
功能与行为不变。

| 入口 | 调用方 | Rust 产物 | 回退 |
|---|---|---|---|
| 规则文档解析 | Dart（`dart:ffi`） | 归类、去重、`$badfilter` 聚合后的紧凑载荷 | `parseCategorizedInDart` |
| 规则页检索 | Dart（`dart:ffi`，句柄） | 预折叠索引，查询返回命中行号 | `filteredRulesProvider` 的 `.where` |
| DTRI 索引编译 | Kotlin（JNI） | 与 Kotlin 写入器逐字节相同的 mmap 索引 | `MappedSubscriptionRuleIndex.compile` |
| 策略快照构建 + 判定 | Go（`dlopen` + C ABI） | 规则表、通配索引、DTRI 读取、七级优先级 | `policySnapshot.evaluateGo` |

前三个是“纯计算、失败无感”的快路径；第四个是**职责划分的迁移**：域名规则判定整体挪到 Rust，
Go 侧只保留生命周期、决策缓存、域名归一化，以及（关键的）同一套判定逻辑作为回退与对拍基准。

## 结构

```
rust/
├── build_android.py                # NDK 交叉编译两个 crate + 拷入 jniLibs
├── verify.py                       # fmt / clippy / test / Go 对拍 / Dart 对拍 / 基准
├── diting-rule-core/src/
│   ├── models.rs domain.rs line.rs hosts.rs document.rs   # 解析（对应 rule_parser.dart 等）
│   ├── ffi.rs                      # 解析的 C ABI + 载荷格式（ABI_VERSION）
│   ├── search.rs search_ffi.rs     # 折叠与检索索引、C ABI、句柄（SEARCH_ABI_VERSION）
│   ├── dtri.rs dtri/tests.rs       # DTRI 写入器（对应 MappedSubscriptionRuleIndex）
│   ├── jni_bridge.rs               # Kotlin 调用 DTRI 的 JNI 入口
│   └── fast_hash.rs                # 去重索引用的随机种子 FxHash
├── diting-policy-core/src/
│   ├── json.rs                     # 快照载荷（字段与 ruleSnapshotJSON 一一对应）
│   ├── text.rs                     # Go 语义的 ToLower / TrimSpace / 后缀匹配
│   ├── dns_type.rs                 # dns.StringToType（dnsType 修饰符用）
│   ├── glob.rs wildcard_index.rs   # newWildcardMatcher / policy_wildcard_index.go
│   ├── dtri_read.rs                # policy_dtri_reader.go：bloom + 标签游走 + mmap 复用
│   ├── regex_go.rs                 # Go regexp → Rust regex 翻译与前缀预筛
│   ├── special.rs                  # specialRule（appScope / denyallow / dnsType / regex / glob）
│   ├── tables.rs decision.rs       # 桶与 inverted 规则、匹配辅助、判定类型
│   ├── snapshot.rs                 # policySnapshot：表构建、hasRules、七级判定
│   └── ffi.rs                      # Go 侧 dlopen 的 C ABI（ABI_VERSION）
├── examples/                       # bench.rs / search_bench.rs / dtri_bench.rs / policy_bench.rs
├── tests/dtri_golden.rs + fixtures/ # Rust ↔ 参考实现逐字节对拍
└── tools/dtri-reference/DTRIReference.java   # Kotlin compile 的桌面 JVM 复刻（生成 fixtures / 基准）
```

- Dart：`rust_rule_core.dart`（加载 `.so`、校验 ABI、解载荷）、`rule_parser.dart`、
  `rule_search_index.dart`（表变化即释放）、`rules_providers.dart`；
  对拍在 `test/rule_parse_rust_parity_test.dart`、`test/rule_search_rust_parity_test.dart`；
  端到端计时在 `tool/rule_core_bench.dart`、`tool/rule_search_bench.dart`。
- Kotlin：`RustRuleIndexCompiler.kt`（打包 `EnabledRule` + JNI + 失败标记）、
  `MappedSubscriptionRuleIndex.kt`（先写 Rust 产物并自校验，失败回退）。
- Go：`policy_native.go`（`dlopen`、ABI 校验、加载探测、故障闩锁）、
  `policy_native_parity.go`（每次应用快照的对拍探针、正则接受集校验、切回 Go）、
  `policy_snapshot.go`（`evaluateGo` 原判定逻辑 + `evaluateNormalized` 分流）、
  `policy_native_test.go`（随机快照 / 随机正则 / DTRI 全量对拍）。

## 构建与启用

```bash
cd rust && cargo build --release        # 本机：供 flutter test、go test、基准使用
python rust/build_android.py            # Android：两个 .so，arm64-v8a / x86_64 交叉编译并拷入 jniLibs
```

不跑第二步就没有 `.so`：Dart / Kotlin / Go 三侧各自按原实现工作，功能完全不变。

运行时判定（Go 策略内核）：

- `DITING_POLICY_CORE=off|go` 强制走 Go；`DITING_POLICY_CORE_LIB=<路径>` 指定产物；否则按
  `libditing_policy_core.so`（打包名）→ `rust/target/{release,debug}/` 依次探测，
  `ABI_VERSION` 不匹配即跳过（老产物只会让这一条路径降级）。
- 应用快照时先构建 Go 表（原路径，同时是回退与基准），再构建 Rust 快照，然后：
  1. 比对 `hasRules` / `appSensitive` / `qtypeSensitive`；
  2. 比对正则接受集（Go 编译成功条数必须等于 Rust 的：`\p{...}` 名称集合、超大模式之类的差异
     在这里现形）；
  3. 用快照自身的规则派生出最多 96 个探针查询，两边各答一遍，判定与 reason 必须逐字相同。
  任何一步不一致：记一条日志，本快照继续用 Go。
- 调用期 `evaluate` 返回错误码（含 panic 被捕获）→ 本快照的 Rust 路径立即作废，后续查询走 Go。
- 快照换新后旧句柄延迟 2 秒释放（与 Go 的 DTRI reader 同一个约定），释放前等待在途调用退出。

## 数据流

```
解析：utf8 bytes ──parse──> Rust 解析+去重+聚合 ──> 二进制载荷 ──> Dart 顺序读取
DTRI：EnabledRule 分页 ──pack──> u32 计数 + 每条(pattern, source, flags, appScope, denyallow, dnsType)
       ──JNI──> Rust 过滤+trie+bloom ──> 写临时文件 → load() 自校验 → 原子替换 → Go mmap
检索：规则表 ──search_build──> 折叠进连续 arena ──> 句柄
       查询词 ──search_query(句柄)──> 折叠查询词 + 扫描 ──> 命中行号（Uint32List）
       规则表变化 → search_free_index(句柄)

策略：ApplyRuleSnapshot(json) ──> Go 解码 + 建表（回退用）
                              ──> Rust snapshot_build(json) ──> 句柄（含 4 条路径的 mmap trie）
     请求 ──normalizePolicyDomain──> 决策缓存 ──命中──> 返回
                                           └─未命中─> evaluate(句柄, 域名, 应用, qtype)
                                                      ──> blocked + reason（指向快照内字符串）
```

布局与语义的权威注释在 `diting-rule-core/src/ffi.rs`、`search_ffi.rs`、`dtri.rs` 与
`diting-policy-core/src/ffi.rs`、`snapshot.rs` 顶部；改动要同步对应的 `ABI_VERSION` /
`SEARCH_ABI_VERSION`、参考实现与 fixtures。

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

**DTRI（写入）**：三层对拍，任一层失败 `verify.py` 即报错。

1. `tests/dtri_golden.rs`：与 `DTRIReference.java`（同样的 `Locale.ROOT` 小写、UTF-16 排序、
   `HashMap` 去重、bloom 位序）逐字节相等；`.pack` fixtures 钉住 JNI 载荷格式。覆盖大小写、尾点、
   Unicode、同 pattern 多 source 取最小、应跳过的规则族。
2. `android/engine/policy_dtri_rust_test.go`：Go 引擎 mmap 这些 fixture，按自身 `find` 语义查回
   语料声明的 source。
3. 10 万条语料一次性对照：Rust 镜像与 JVM 参考实现 3,548,571 字节完全一致。

已知边界：bloom 的 Kotlin 写入器按 UTF-16 码元低 8 位做 FNV、Go 读取器按 UTF-8 字节；纯规则归一化后
是 ASCII 故不影响，Rust 复刻写入器（逐字节一致）而不“修”成 UTF-8，否则不再是 drop-in 替换。

**策略内核**：Go 的 `evaluateGo` 是基准，四条对拍线全部在 `verify.py --go` 里跑：

1. 随机快照对拍（`TestNativePolicyMatchesGoOnRandomSnapshots`）：每轮随机生成 `globalBlock` /
   `globalAllow` / `globalImportant` / `disabledRules` / `appRules` / `invertedBlock` /
   `invertedAllow` / `specialBlock` / `specialAllow`（含 appScope、appInverted、denyallow、
   dnsType、大小写、`*` 通配、非 ASCII），再用规则自身派生 + 变异出的域名 × 5 个应用名 ×
   4 个 qtype（含 0）逐一比较 `blocked` 与 `reason`。默认 60 轮，可用
   `DITING_POLICY_PARITY_ROUNDS` / `DITING_POLICY_PARITY_SEED` 加大。
2. 随机正则对拍（`TestNativePolicyMatchesGoOnRandomRegexes`）：从「字面量 / 字符类 / `\d\w\s\b` /
   锚点 / 量词 / 交替 / 内联标志 / Unicode 转义」的语法池随机拼 pattern，配随机域名（含 `Ä`、
   `straße`、`İstanbul`、`ſ`、`KELVIN`）比对判定。
3. 手写语料（`TestNativePolicyMatchesGoOnProbeHeavyPayloads`）：denyallow、appScope 优先级阶梯、
   `dnsType` 正负向、四级白/黑名单交叉。
4. DTRI 读取（`TestNativePolicyMatchesGoOnDTRI`）：同一份 `.dtri` fixture 由 Go reader 与 Rust
   reader 分别喂各自的七级判定，逐域名一致；`policy_core.rs` 另外直接断言 fixture 语料声明的
   source。
5. 小写折叠（`TestNativeLowerMatchesGoSweepsEveryCodepoint`）：把全部 Unicode 标量值拼成一个
   字符串，一次比对 Rust 与 `strings.ToLower`（Go 的简单映射，`U+0130` → `i` 已单独钉住）。

## 策略内核的已知边界

- **正则翻译**：规则里的正则由 Go 的 RE2 语法翻成 Rust `regex`。`\d`、`\w`、`\s`、`\b` 被翻译成
  ASCII 版本（Go 本来就是 ASCII），`\pL` → `\p{L}`、`\p{^Greek}` → `\P{Greek}`。仍有细微差别：
  字符类里的 `\D` / `\W` / `\S` 交给 Rust 的 Unicode 取反（只对非 ASCII 数字/字母有差异，而 DNS
  域名归一化后基本不含）。**接受集不同**（Go 能编、Rust 编不出，或反之）由
  构建期的条数校验识破，整份快照退回 Go，不会出现“少了一条正则规则”的结果。
- **正则前缀预筛**：Go 用 `regexp/syntax` 求 `^` 后的字面量前缀，Rust 用保守的字符串扫描等价物
  （遇到顶层 `|` 直接放弃）。“没有前缀”只是少一层预筛，不影响判定。
- **通配符规则**用 `(?i)^glob$` 编译，折叠语义与 Go 一致；编译**延迟**到首次真正需要它时（订阅规则
  里上千条 glob 大多永不命中，构建期编译会让规则保存慢好几倍）。代价是某个已命中的 glob 首次命中时
  多花约 0.1 ms。
- **尾点通配**：`*.foo.` 这类模式在 Go 的 wildcardIndex 里永远命中不了（residual 预筛要求域名以
  `."+模式结尾`，而域名归一化后不带尾点），Rust 照抄不改。
- **reason 字符串**：Rust 只回传指向快照内字符串的指针与长度，Go 立刻拷走；字符串本身不跨快照存活。
- **快照构建成本**：Go 表 + Rust 表都建（回退与对拍需要），53k 规则的一份快照应用约 150 ms
  （纯 Go 约 62 ms），只在规则变更时发生，不在查询路径上。

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

策略判定（53k 规则 + 3.7k 通配 + 30 条正则，1024 个域名轮转，含 FFI 与 reason 拷贝）：

| 实现 | 每查询耗时 |
|---|---|
| Go 走法 `evaluateGo` | 2.0–2.2 µs |
| Rust 内核（经 C ABI，含 reason 拷贝） | 1.7–1.8 µs |
| Rust 纯走法（`policy_bench`，不含 FFI） | 1.1–1.4 µs |

本机计时噪声不小（±20%），结论是**持平到略快**：跨一次边界的固定成本约 0.1–0.3 µs，纯走法比 Go 快
约 1.6x。**真正的热路径不是它**：命中决策缓存的查询根本不进内核，因此这里的目标是“不比原来慢”，
而不是把决策缓存也搬走。同一份快照的构建：

| 场景 | 耗时 |
|---|---|
| 只有 Go 表（`DITING_POLICY_CORE=off`） | ~62 ms |
| Go 表 + Rust 表 + 探针对拍 | ~150 ms |
| 其中 Rust 纯构建（`policy_bench`） | ~31 ms |

复现：

```bash
cd android/app && dart compile exe tool/rule_core_bench.dart -o build/rule_core_bench.exe && build/rule_core_bench.exe
dart compile exe tool/rule_search_bench.dart -o build/rule_search_bench.exe && build/rule_search_bench.exe
cd rust && cargo run --release --example search_bench
cargo run --release -p diting-policy-core --example policy_bench -- --synthetic 50000 20000

# DTRI（同一份语料喂两边）
java rust/tools/dtri-reference/DTRIReference.java --generate 100000 /tmp/rules.txt
java rust/tools/dtri-reference/DTRIReference.java /tmp/rules.txt /tmp/ref.dtri
cargo run --release --example dtri_bench -- /tmp/rules.txt /tmp/rust.dtri
cmp /tmp/ref.dtri /tmp/rust.dtri && echo 一致
java rust/tools/dtri-reference/DTRIReference.java --bench /tmp/rules.txt 5   # 同进程多次取最优
# 同设备对比：javac --release 17 + d8 打成 dex，dalvikvm -cp classes.dex DTRIReference --bench rules.txt 5

# 策略判定（Go 侧两路对比，注意 Apply 基准很慢，别用 -benchtime 20000x）
cd android/engine
go test -run XXX -bench 'BenchmarkPolicyEvaluate(GoWalk|RustKernel)Large' -benchtime 20000x .
go test -run XXX -bench BenchmarkPolicyApplyLargeWithRust -benchtime 3x .
```

## 验证

```bash
python rust/verify.py            # fmt + clippy -D warnings + cargo test
python rust/verify.py --go       # 再加 Go 读取 DTRI fixture 与策略内核全量对拍
python rust/verify.py --dart     # 再加解析与检索的 Dart ↔ Rust 对拍
python rust/verify.py --android  # 再加 arm64-v8a 交叉编译（两个 .so）
python rust/verify.py --bench    # 再加 DTRI / 检索 / 策略判定基准
python rust/verify.py --all      # 全量
```

`--go` 会先 `cargo build --release`（Go 侧按约定探测 `rust/target/release/`），并且需要 `cgo` 与
C 编译器（Windows 用 mingw，Linux/macOS 用 gcc/clang）：策略内核的对拍本质上就是跨语言比对，
没有 C 工具链就只剩单侧测试。`--dart` 需要先 `cargo build --release`，未构建时对拍用例自行
skip，不会假绿。

改了写入语义要一起重生成 fixtures：

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
2. 原实现留下当基准。快路径要求失败回退；像策略内核这样**换主人**的，还要在应用时对拍探针，
   让“答案不变”成为每次运行的检查而非一次性验证。
3. 一次调用搬一整批；跨多次调用（如索引）用句柄并在源数据变化 / 页面销毁时显式释放。
4. 独立 ABI 版本号，旧产物只降级这一条路径，不牵连已迁移模块。
5. 对拍为主：Rust 单测 + 与 Dart/Kotlin/Go 参考实现逐字段 / 逐字节 / 逐判定对比，不一致即失败。
6. 基准可复现：`examples/*_bench.rs` 测纯 Rust，`tool/*_bench.dart` 与 `go test -bench` 测端到端，
   数字写进“性能”。
7. 接进 `verify.py`，让“语义没变”可持续验证而非一次性检查。
8. 非 ASCII、大小写、排序等差异要么对齐要么写进“已知边界”，不顺手“修”成自己认为更对的样子。
9. 跨语言边界上的字符串一律“谁拥有谁负责”：reason 用指针 + 长度交给调用方立刻拷走，不做引用计数。

## 后续可做

- **策略内核吃下决策缓存**：缓存与判定一起放进 Rust，`prewarm` 也留在同一侧，Go 只剩一次调用。
- **快照构建提速**：Rust 侧按流式解析 / 并行建表，把 53k 规则的 ~90 ms 压到十几毫秒。
- **正则语义彻底对齐**：字符类里的 `\D\W\S` 也翻成 ASCII 取反，把“已知边界”里那条消掉。
- **去重键去字符串化**：每条规则拼一个去重键约占解析时间三成，改成字段哈希 + 碰撞时逐字段比较。
- **DTRI 增量更新**：按 source 分片只重编受影响分片，把万级列表的写入后延迟压到一次小编译。
- **检索索引预热**：表稳定后在空闲时预热，把首次折叠的 ~30 ms 从“第一个键”挪开。
- **备份导入导出**：同样适合这条路，但语义面大得多，需先精简备份格式再逐组迁移。
