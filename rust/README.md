# Rust 内核

两个 crate：`diting-rule-core` 负责规则数据的解析与索引，`diting-policy-core` 负责
**Go 隧道引擎的规则判定与决策缓存内核**。四个接入点都只有 Rust 一条实现，原实现已删除：库缺失、
ABI 不匹配或载荷被拒时直接报错，不再有第二套语义可以静默跑起来。

| 入口 | 调用方 | Rust 产物 | 缺失时 |
|---|---|---|---|
| 规则文档解析 | Dart（`dart:ffi`） | 归类、去重、`$badfilter` 聚合后的紧凑载荷 | 导入抛错 |
| 规则页检索 | Dart（`dart:ffi`，句柄） | 预折叠索引，查询返回命中行号 | 规则页抛错 |
| DTRI 索引编译 | Kotlin（JNI） | mmap 索引，与 JVM 参考实现逐字节相同 | 快照编译失败 |
| 策略快照构建 + 判定 + 决策缓存 | Go（`dlopen` + C ABI） | 规则表、通配索引、DTRI 读取、七级优先级、归一化与缓存 | 隧道启动失败 |

第四个是**职责划分的迁移**：域名归一化、规则判定与决策缓存整体在 Rust，Go 侧只保留快照生命周期
（构建、原子换新、延迟释放）。

## 结构

```
rust/
├── build_android.py                # NDK 交叉编译两个 crate + 拷入 jniLibs
├── verify.py                       # fmt / clippy / test / Go / Dart / 基准
├── diting-rule-core/src/
│   ├── models.rs domain.rs line.rs hosts.rs document.rs   # 解析（取代原 rule_parser.dart 等）
│   ├── ffi.rs                      # 解析的 C ABI + 载荷格式（ABI_VERSION）
│   ├── search.rs search_ffi.rs     # 折叠与检索索引、C ABI、句柄（SEARCH_ABI_VERSION）
│   ├── dtri.rs dtri/tests.rs       # DTRI 写入器（取代 MappedSubscriptionRuleIndex.compile）
│   ├── jni_bridge.rs               # Kotlin 调用 DTRI 的 JNI 入口
│   └── fast_hash.rs                # 去重索引用的随机种子 FxHash
├── diting-policy-core/src/
│   ├── json.rs                     # 快照载荷（字段与 Android 侧推送的 JSON 一一对应）
│   ├── text.rs                     # Go 语义的 ToLower / TrimSpace / normalizePolicyDomain
│   ├── dns_type.rs                 # dns.StringToType（dnsType 修饰符用）
│   ├── glob.rs wildcard_index.rs   # 通配编译与索引（取代 policy_wildcard_index.go）
│   ├── dtri_read.rs                # bloom + 标签游走 + mmap 复用（取代 policy_dtri_reader.go）
│   ├── regex_go.rs                 # Go regexp → Rust regex 翻译与前缀预筛
│   ├── special.rs                  # specialRule（appScope / denyallow / dnsType / regex / glob）
│   ├── tables.rs decision.rs       # 桶与 inverted 规则、匹配辅助、判定类型
│   ├── cache.rs                    # 分片 CLOCK 决策缓存 + reason 池（取代 policy_decision_cache.go）
│   ├── snapshot.rs snapshot/query.rs  # policySnapshot：表构建、七级判定 + 归一化/缓存入口、prewarm
│   └── ffi.rs                      # Go 侧 dlopen 的 C ABI（ABI_VERSION）
├── examples/                       # bench.rs / search_bench.rs / dtri_bench.rs / policy_bench.rs
├── tests/corpus.rs                 # 解析语料的固定分类用例
├── tests/dtri_golden.rs + fixtures/ # Rust ↔ JVM 参考实现逐字节对拍
└── tools/dtri-reference/DTRIReference.java   # DTRI 参考写入器（生成 fixtures / 基准）
```

- Dart：`rust_rule_core.dart`（加载 `.so`、校验 ABI、解载荷）、`rule_parser.dart`（一层转发）、
  `rule_search_index.dart`（表变化即释放）、`rules_providers.dart`。
- Kotlin：`RustRuleIndexCompiler.kt`（打包 `EnabledRule` + JNI）、
  `MappedSubscriptionRuleIndex.kt`（写镜像 + 头校验）。
- Go：`policy_native.go`（`dlopen`、ABI 校验、`evaluate` / `evaluateUncached` / `prewarm`、句柄释放）、
  `policy_snapshot.go`（快照与一次调用入口）、`policy_engine.go`（构建与原子换新）、
  `policy_native_test.go`（固定用例 + 应用基准）。

## 构建与启用

```bash
cd rust && cargo build --release        # 本机：供 flutter test、go test、基准使用
python rust/build_android.py            # Android：两个 .so，arm64-v8a / x86_64 交叉编译并拷入 jniLibs
```

没有 `.so` 就是错误，而不是“功能不变地慢一点”：

- Dart 侧首次导入抛 `StateError`（`DITING_RULE_CORE_LIB` 可指定显式路径，否则按打包名 →
  `rust/target/{release,debug}/` 探测）；
- Kotlin 侧 `System.loadLibrary("diting_rule_core")` 失败即抛 `IllegalStateException`；
- Go 侧 `ApplyRuleSnapshot` 返回错误，`EngineRuleLoader` / 独立 DNS 服务把它当作启动失败，
  不会以“过滤静默关闭”的状态起隧道。

策略内核的调用约定：

- 每次应用快照只建一份 Rust 快照；`hasRules` / `appSensitive` / `qtypeSensitive` 由内核的
  `snapshot_flags` 提供，Go 只读 hasRules，不保留第二份规则表，也不再解析快照 JSON；
- 查询一律一次 `evaluate`：内核做域名归一化（小写、去空白、去尾点）、查决策缓存，未命中才走七级；
  reason 是指向快照内池化字符串的指针 + 长度，Go 立刻拷走；
- `evaluate_uncached` 只给固定用例与基准用：同一走法不读不写缓存，用来证明命中不会改变答案；
- 快照换新后先在后台 `prewarm(新, 旧)`，再延迟 2 秒释放旧句柄；释放前等待在途调用退出
  （cgo 调用不可抢占），prewarm 期间两个句柄都算在途。

## 数据流

```
解析：utf8 bytes ──parse──> Rust 解析+去重+聚合 ──> 二进制载荷 ──> Dart 顺序读取
DTRI：EnabledRule 分页 ──pack──> u32 计数 + 每条(pattern, source, flags, appScope, denyallow, dnsType)
       ──JNI──> Rust 过滤+trie+bloom ──> 写临时文件 → load() 头校验 → 原子替换
检索：规则表 ──search_build──> 折叠进连续 arena ──> 句柄
       查询词 ──search_query(句柄)──> 折叠查询词 + 扫描 ──> 命中行号（Uint32List）
       规则表变化 → search_free_index(句柄)

策略：ApplyRuleSnapshot(json) ──> Rust snapshot_build(json) ──> 句柄（含 4 条路径的 mmap trie + 决策缓存）
     请求 ──evaluate(句柄, 域名, 应用, qtype)──> 归一化 ──> 决策缓存 ──命中──> 返回
                                                          └─未命中─> 七级走法 ──> blocked + reason
     规则变更 ──prewarm(新句柄, 旧句柄)──> 旧快照的热键在新快照上重算
```

布局与语义的权威注释在 `diting-rule-core/src/ffi.rs`、`search_ffi.rs`、`dtri.rs` 与
`diting-policy-core/src/ffi.rs`、`snapshot.rs` 顶部；改动要同步对应的 `ABI_VERSION` /
`SEARCH_ABI_VERSION` 与 fixtures。

## 语义一致性

原实现删除后，保证来自三处：语料固定用例、逐字节 fixtures、Rust 单测。

**解析**：`tests/corpus.rs` 固化了一份覆盖注释、元素隐藏、URL/正则形态、修饰符族、hosts、dnsmasq
与边界构造的语料，断言各族条数、计数器与若干精确 pattern；`line.rs` / `hosts.rs` / `domain.rs` /
`document.rs` 的单测逐条钉住分支行为。

**检索**：`search.rs` 的折叠必须与 Dart 的 `String.toLowerCase` 完全一致：

- Dart 折叠上下文无关（`'ΑΣ'` → `ασ`），`str::to_lowercase` 会套 final-sigma（`ας`），故逐 `char` 折叠；
- `U+0130`（İ）Dart 折叠成 `i`，Unicode 是 `i` + 组合点，单独钉住映射；
- Dart 折叠表比 Unicode 旧，Deseret / Cherokee / Vithkuqi 等区块不动；`search.rs` 的
  `DART_UNMAPPED` 是逐码点跑 `String.toLowerCase` 得出的 465 个码点（合并成区间）。

已知边界：Dart 按 UTF-16 码元匹配、Rust 按 UTF-8 字节匹配，只有查询词含孤立代理项这类构造不出
的输入才有差异；规则模式解析后不含孤立代理项。

**DTRI（写入）**：

1. `tests/dtri_golden.rs`：与 `DTRIReference.java`（同样的 `Locale.ROOT` 小写、UTF-16 排序、
   `HashMap` 去重、bloom 位序）逐字节相等；`.pack` fixtures 钉住 JNI 载荷格式。覆盖大小写、尾点、
   Unicode、同 pattern 多 source 取最小、应跳过的规则族。
2. `android/engine/policy_dtri_rust_test.go`：策略内核按 fixture 语料声明的 source 解析每个可索引规则。
3. 10 万条语料一次性对照：Rust 镜像与 JVM 参考实现 3,548,571 字节完全一致。

已知边界：bloom 的 Kotlin 打包端按 UTF-16 码元低 8 位做 FNV；纯规则归一化后是 ASCII 故不影响，
Rust 复刻写入器（逐字节一致）而不“修”成 UTF-8，否则不再是 drop-in 替换。

**策略内核**：`tests/policy_core.rs` 把 DTRI fixtures 喂给快照，断言每个可索引规则解析到语料声明的
source、禁用规则回落到父后缀；`ffi.rs` 的单测钉住构建 / 判定 / 释放往返与错误上报，以及归一化、
缓存命中与未命中答案一致、换新 prewarm；`cache.rs` 的单测钉住维度折叠、CLOCK 淘汰（热键存活）与
热键排序；`android/engine/policy_native_test.go` 用固定快照覆盖各规则族，并在 Go 侧逐条对比
`evaluate` 与 `evaluate_uncached`。

## 策略内核的已知边界

- **正则翻译**：规则里的正则由 Go 的 RE2 语法翻成 Rust `regex`。`\d`、`\w`、`\s`、`\b` 被翻译成
  ASCII 版本（Go 本来就是 ASCII），`\pL` → `\p{L}`、`\p{^Greek}` → `\P{Greek}`。仍有细微差别：
  字符类里的 `\D` / `\W` / `\S` 交给 Rust 的 Unicode 取反（只对非 ASCII 数字/字母有差异，而 DNS
  域名归一化后基本不含）。
- **正则前缀预筛**：Go 侧原来的 `regexp/syntax` 前缀提取由 Rust 的保守字符串扫描等价物实现
  （遇到顶层 `|` 直接放弃）。“没有前缀”只是少一层预筛，不影响判定。
- **通配符规则**用 `(?i)^glob$` 编译，折叠语义与 Go 一致；编译**延迟**到首次真正需要它时（订阅规则
  里上千条 glob 大多永不命中，构建期编译会让规则保存慢好几倍）。代价是某个已命中的 glob 首次命中时
  多花约 0.1 ms。
- **尾点通配**：`*.foo.` 这类模式在原来的 Go 索引里永远命中不了（residual 预筛要求域名以
  `."+模式结尾`，而域名归一化后不带尾点），Rust 照抄不改。
- **reason 字符串**：Rust 只回传指向快照内字符串的指针与长度，Go 立刻拷走；非空 reason 在快照的
  reason 池里去重驻留，所以缓存条目被淘汰也不会让刚拿到的指针悬空，池随快照一起释放。池的大小由
  “出现过的不同 reason”决定（事实上就是规则 pattern），不随查询量增长。
- **决策缓存**：16 分片 × 512 条（共 8192），CLOCK 淘汰 + 命中计数折半；缓存随快照整体换新，
  所以规则变更不会读到旧答案。缓存存的是快照内的判定结果，不跨快照共享。
- **快照构建成本**：只剩 Rust 一份表，53k 规则的纯构建约 30 ms（`policy_bench`），只在规则变更时
  发生，不在查询路径上。

## 性能（本机 Windows/amd64，迁移时的实测值）

规则解析（AOT，10 万行合成语料，含 FFI + 载荷解码）：Rust 0.20–0.27 s，原 Dart 实现 0.98–1.18 s，
约 4–5x。原 Dart 实现与基准工具已删除，数字仅作迁移记录。

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

规则页检索（AOT，10 万行，6 个查询取最优，含 FFI 与命中解码）：Rust 索引 2.4–3.5 ms/键（其中纯扫描
2.4–3.5 ms），原 Dart `toLowerCase().contains` 15–20 ms，约 5x。首次查询前一次性折叠约 30 ms（编码
17–20 ms + FFI ~2 ms + Rust 折叠 ~10 ms），之后仅在规则表变化时重建；空查询与启动期分页不建索引。
纯 Rust（不含 FFI）用 `examples/search_bench.rs` 测：100k 行构建 9–15 ms。折叠文本存在连续 arena
（每条一个 `(start, len)`），100k 行从 200k 个 `String` 变成一次分配；命中行号用 `Uint32List` 回传。

策略判定（53k 规则 + 3.7k 通配 + 30 条正则，1024 个域名轮转）：

| 路径 | 每查询耗时 |
|---|---|
| 缓存命中（`answer`：归一化 + 缓存查找 + reason） | 0.12 µs |
| 未命中（`evaluate` 七级走法） | 0.7–0.8 µs |
| 同上，旧记录：Rust 纯走法 / 经 C ABI（迁移时，含 reason 拷贝） | 1.1–1.4 µs / 1.7–1.8 µs |

决策缓存搬进内核后，命中也要过一次 FFI（此前 Go 侧直接返回，不进库）。纯 Rust 命中约 0.12 µs，
加上 cgo 调用仍远低于一次未命中的走法；目标是不拖慢查询，而不是把缓存留在 Go 里换一次表维护。
本机计时噪声不小（±20%，冷启动首轮可慢 3–4 倍）。应用一份 53k 规则快照的开销就是一次纯 Rust 构建
（~30 ms）加上换新与旧句柄延迟释放。

复现：

```bash
cd rust && cargo run --release --example search_bench
cargo run --release --example dtri_bench -- /tmp/rules.txt /tmp/rust.dtri
cargo run --release -p diting-policy-core --example policy_bench -- --synthetic 50000 20000

# DTRI（同一份语料喂两边）
java rust/tools/dtri-reference/DTRIReference.java --generate 100000 /tmp/rules.txt
java rust/tools/dtri-reference/DTRIReference.java /tmp/rules.txt /tmp/ref.dtri
cargo run --release --example dtri_bench -- /tmp/rules.txt /tmp/rust.dtri
cmp /tmp/ref.dtri /tmp/rust.dtri && echo 一致
java rust/tools/dtri-reference/DTRIReference.java --bench /tmp/rules.txt 5   # 同进程多次取最优
# 同设备对比：javac --release 17 + d8 打成 dex，dalvikvm -cp classes.dex DTRIReference --bench rules.txt 5

# 策略（Go 端到端；Apply 基准很慢，别用 -benchtime 20000x）
cd android/engine
go test -run XXX -bench BenchmarkPolicyEvaluateLargeCold -benchtime 20000x .
go test -run XXX -bench BenchmarkPolicyApplyLargeWithRust -benchtime 3x .
```

## 验证

```bash
python rust/verify.py            # fmt + clippy -D warnings + cargo test
python rust/verify.py --go       # 再加 Go 侧策略内核用例与 DTRI fixture 用例
python rust/verify.py --dart     # 再加 Dart 侧规则解析与入库用例
python rust/verify.py --android  # 再加 arm64-v8a 交叉编译（两个 .so）
python rust/verify.py --bench    # 再加 DTRI / 检索 / 策略判定基准
python rust/verify.py --all      # 全量
```

`--go` 会先 `cargo build --release`（Go 侧按约定探测 `rust/target/release/`），并且需要 `cgo` 与
C 编译器（Windows 用 mingw，Linux/macOS 用 gcc/clang）。`--dart` 同样需要先建好本机产物：Dart 侧
已经没有第二份解析器可以兜底。

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
2. 迁移是**换主人**，不是加一条快路径：原实现要一起删掉，不要让两套语义并存到需要对拍维持一致。
3. 一次调用搬一整批；跨多次调用（如索引）用句柄并在源数据变化 / 页面销毁时显式释放。
4. 独立 ABI 版本号，旧产物直接报错而不是降级——降级代码就是下一份要维护的语义。
5. 迁移前把原实现的语料转成固定用例（`tests/corpus.rs`、fixtures），迁移后由 Rust 侧自己守。
6. 基准可复现：`examples/*_bench.rs` 测纯 Rust，`go test -bench` 测端到端，数字写进“性能”。
7. 接进 `verify.py`，让用例在每次改动后都跑得起来。
8. 非 ASCII、大小写、排序等差异要么对齐要么写进“已知边界”，不顺手“修”成自己认为更对的样子。
9. 跨语言边界上的字符串一律“谁拥有谁负责”：reason 用指针 + 长度交给调用方立刻拷走，不做引用计数。

## 后续可做

- **快照构建提速**：Rust 侧按流式解析 / 并行建表，把 53k 规则的 ~30 ms 压到十几毫秒。
- **正则语义彻底对齐**：字符类里的 `\D\W\S` 也翻成 ASCII 取反，把“已知边界”里那条消掉。
- **去重键去字符串化**：每条规则拼一个去重键约占解析时间三成，改成字段哈希 + 碰撞时逐字段比较。
- **DTRI 增量更新**：按 source 分片只重编受影响分片，把万级列表的写入后延迟压到一次小编译。
- **检索索引预热**：表稳定后在空闲时预热，把首次折叠的 ~30 ms 从“第一个键”挪开。
- **备份导入导出**：同样适合这条路，但语义面大得多，需先精简备份格式再逐组迁移。
