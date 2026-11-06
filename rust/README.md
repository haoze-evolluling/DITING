# Rust 内核

五个 crate：`diting-rule-core` 负责规则数据的解析与索引，`diting-policy-core` 负责
**Go 隧道引擎的规则判定与决策缓存内核**，`diting-stamp-core` 负责**桌面服务的 `sdns://` 印章解析**，
`diting-filter-core` 负责**桌面服务的规则文本解析与规则索引匹配**，`diting-go-compat` 是两个内核共用的
Go 标准库语义（大小写折叠、`strings` 辅助、`regexp` 翻译、`dns.StringToType`）。
七个接入点都只有 Rust 一条实现，原实现已删除：库缺失、ABI 不匹配或载荷被拒时直接报错，不再有
第二套语义可以静默跑起来。

| 入口 | 调用方 | Rust 产物 | 缺失时 |
|---|---|---|---|
| 规则文档解析 | Dart（`dart:ffi`） | 归类、去重、`$badfilter` 聚合后的紧凑载荷 | 导入抛错 |
| 规则页检索 | Dart（`dart:ffi`，句柄） | 预折叠索引，查询返回命中行号 | 规则页抛错 |
| DTRI 索引编译 | Kotlin（JNI） | mmap 索引，与 JVM 参考实现逐字节相同 | 快照编译失败 |
| 策略快照构建 + 判定 + 决策缓存 | Go（`dlopen` + C ABI） | 规则表、通配索引、DTRI 读取、七级优先级、归一化与缓存 | 隧道启动失败 |
| DNS 印章解析 | Go 桌面服务（纯 Go 动态加载 + C ABI） | 解析后的印章记录、`URL()`/`Server()` 派生串 | 上游配置失败 |
| 规则索引与匹配 | Go 桌面服务（纯 Go 动态加载 + C ABI） | 四层字典树、布隆预检、通配/正则表、判定与重写选择 | 规则索引构建失败 |
| 规则文本解析 | Go 桌面服务（同一个库，纯 Go 动态加载 + C ABI） | 逐行的模式、标志位、`$dnstype`、排除集合与 `$dnsrewrite` 取值 | 列表加载失败 |

第四个是**职责划分的迁移**：域名归一化、规则判定与决策缓存整体在 Rust，Go 侧只保留快照生命周期
（构建、原子换新、延迟释放）。第五个把地址校验、默认端口省略与 DoH 默认路径也一并搬走了，
Go 侧只留取值类型与证书指纹适配。第六个搬的是每次查询都走的判定内核：Go 只保留规则文本、
规则加载与 `$dnsrewrite` 的应答记录构造，判定结果以「命中第几条规则」的形式回传。第七个把
**读文本**这一段也交给了 Rust（`rule_parser.go` 整份删除）：注释与元素隐藏规则、hosts 形式、
`@@`、`$` 修饰符切分、`$dnstype`、`$denyallow=`/`$to=`、AdGuard 域名形态、通配模式与 IDNA 归一化。
Go 侧只留两件仍然属于它的事：`regexp` 与 `buildWildcardRegex` 的编译（匹配器要用编译后的源），
以及 `$dnsrewrite` 取值解析（它连同 `buildRewriteRR` 属于 rewrite 子系统那一轮）。

Android 侧用 cgo 调策略内核；桌面服务侧刻意**不用 cgo**：Windows 走 `syscall.LazyDLL`，Linux 走
`purego`，`CGO_ENABLED=0 GOOS=linux GOARCH=... go build` 的交叉编译链一行都不用改。

## 结构

```
rust/
├── build_android.py                # NDK 交叉编译两个 Android crate + 拷入 jniLibs
├── verify.py                       # fmt / clippy / test / Go / Dart / 基准
├── diting-rule-core/src/
│   ├── models.rs domain.rs line.rs hosts.rs document.rs   # 解析（取代原 rule_parser.dart 等）
│   ├── ffi.rs                      # 解析的 C ABI + 载荷格式（ABI_VERSION）
│   ├── search.rs search_ffi.rs     # 折叠与检索索引、C ABI、句柄（SEARCH_ABI_VERSION）
│   ├── dtri.rs dtri/tests.rs       # DTRI 写入器（取代 MappedSubscriptionRuleIndex.compile）
│   ├── jni_bridge.rs               # Kotlin 调用 DTRI 的 JNI 入口
│   └── fast_hash.rs                # 去重索引用的随机种子 FxHash
├── diting-go-compat/src/
│   ├── text.rs                     # Go 语义的 ToLower / TrimSpace / 去尾点 / 后缀匹配
│   ├── regex.rs                    # Go regexp → Rust regex 翻译、规则正则编译与前缀预筛
│   └── dns_type.rs                 # dns.StringToType（两个内核共用的类型表）
├── diting-stamp-core/src/
│   ├── stamp.rs stamp/tests.rs     # 印章逐字节解析、地址/主机名校验、URL()/Server() 派生
│   └── ffi.rs                      # 桌面服务 Go 侧动态加载的 C ABI（ABI_VERSION）+ 载荷布局
├── diting-filter-core/src/
│   ├── parse.rs parse/tests.rs     # 规则文本解析：行/文档、修饰符、通配、IDNA 归一化（原 rule_parser.go）
│   ├── parse_payload.rs            # 解析请求/回应的二进制布局
│   ├── rule.rs                     # 一条规则的判定字段：标志位、$dnstype、排除集合、重写动作
│   ├── trie.rs                     # DomainTrie：倒序标签字典树与后缀/精确走法
│   ├── bloom.rs                    # DomainBloomFilter：拦截字典树前的预检
│   ├── index.rs index/tests.rs     # 四层优先级、通配/正则表、重写选择（原 RuleMatcher）
│   ├── payload.rs                  # 与 Go 共享的紧凑二进制布局
│   └── ffi.rs                      # build / match / parse_rules / parse_rule / free 的 C ABI（ABI_VERSION）
├── diting-filter-core/tests/fixtures/parse_corpus.tsv  # 迁移时 Go 解析器的 200 行语料快照
├── diting-policy-core/src/
│   ├── json.rs                     # 快照载荷（字段与 Android 侧推送的 JSON 一一对应）
│   ├── glob.rs wildcard_index.rs   # 通配编译与索引（取代 policy_wildcard_index.go）
│   ├── dtri_read.rs                # bloom + 标签游走 + mmap 复用（取代 policy_dtri_reader.go）
│   ├── special.rs                  # specialRule（appScope / denyallow / dnsType / regex / glob）
│   ├── tables.rs decision.rs       # 桶与 inverted 规则、匹配辅助、判定类型
│   ├── cache.rs                    # 分片 CLOCK 决策缓存 + reason 池（取代 policy_decision_cache.go）
│   ├── snapshot.rs snapshot/query.rs  # policySnapshot：表构建、七级判定 + 归一化/缓存入口、prewarm
│   └── ffi.rs                      # Go 侧 dlopen 的 C ABI（ABI_VERSION）
├── examples/                       # bench.rs / search_bench.rs / dtri_bench.rs / policy_bench.rs
│                                   #   （桌面两套的内核基准在各自 crate 的 examples/ 下）
├── tests/corpus.rs                 # 解析语料的固定分类用例
├── tests/dtri_golden.rs + fixtures/ # Rust ↔ JVM 参考实现逐字节对拍
└── tools/dtri-reference/DTRIReference.java   # DTRI 参考写入器（生成 fixtures / 基准）
```

- Dart：`rust_rule_core.dart`（加载 `.so`、校验 ABI、解载荷）、`rule_parser.dart`（一层转发）、
  `rule_search_index.dart`（表变化即释放）、`rules_providers.dart`。
- Kotlin：`RustRuleIndexCompiler.kt`（打包 `EnabledRule` + JNI）、
  `MappedSubscriptionRuleIndex.kt`（写镜像 + 头校验）。
- 桌面服务 Go（印章）：`stamp_native.go`（探测与加载、ABI 校验、`parse` / `free`、载荷解码）、
  `stamp_native_windows.go`（`syscall.LazyDLL`）、`stamp_native_unix.go`（`purego`）、
  `resolver_stamp.go`（只留取值类型与 `Pins()` 适配）、`stamp_native_test.go`（载荷布局与探测路径）、
  `resolver_stamp_test.go`（原有用例，现在全部穿过 FFI 跑）。
- 桌面服务 Go（规则索引 + 规则解析）：`filter_native.go`（加载、规则载荷编码、判定解码）、
  `filter_native_windows.go` / `filter_native_unix.go`（两个平台的加载器）、
  `native_lib.go`（两个内核共用的探测顺序与平台文件名）、
  `rule_matcher.go`（`RuleMatcher` 只剩句柄生命周期与结果翻译）、
  `parse_native.go`（解析请求编码、解析结果解码、正则编译与 `$dnsrewrite` 取值解析）、
  `rule_parser.go`（`ParsedRule` 定义、两个入口、`buildWildcardRegex`）、
  `rule_engine*.go`（配置、加载、计划、统计不变）、
  `filter_native_test.go` / `parse_native_test.go`（载荷布局与失败路径）、
  `rule_parser_bench_test.go`（整份列表的端到端基准）。
- Go：`policy_native.go`（`dlopen`、ABI 校验、`evaluate` / `evaluateUncached` / `prewarm`、句柄释放）、
  `policy_snapshot.go`（快照与一次调用入口）、`policy_engine.go`（构建与原子换新）、
  `policy_native_test.go`（固定用例 + 应用基准）。

## 构建与启用

```bash
cd rust && cargo build --release        # 本机：供 flutter test、go test、基准使用（含两个桌面内核）
python rust/build_android.py            # Android：两个 .so，arm64-v8a / x86_64 交叉编译并拷入 jniLibs
```

桌面服务的两个内核按平台单独交付（Android 用不到它们）：

- Windows：`cargo build --release -p diting-stamp-core -p diting-filter-core` 产出
  `diting_stamp_core.dll` 与 `diting_filter_core.dll`，`build_manager.py` 在打 EXE 时各编一次，
  NSIS 把两个都装到 `diting-service.exe` 同目录；
- Linux：`build_linux.sh` 按目标架构编/复用 `libditing_stamp_core.so` 与 `libditing_filter_core.so`，
  装到 `/usr/lib/diting/`；
- 探测顺序（两个内核相同）：`DITING_STAMP_CORE_LIB` / `DITING_FILTER_CORE_LIB` → 可执行文件同目录
  → `/usr/lib/diting`、`/usr/local/lib/diting` → `rust/target/{release,debug}/`（`go test` 用）。

没有 `.so` 就是错误，而不是“功能不变地慢一点”：

- Dart 侧首次导入抛 `StateError`（`DITING_RULE_CORE_LIB` 可指定显式路径，否则按打包名 →
  `rust/target/{release,debug}/` 探测）；
- Kotlin 侧 `System.loadLibrary("diting_rule_core")` 失败即抛 `IllegalStateException`；
- Go 侧 `ApplyRuleSnapshot` 返回错误，`EngineRuleLoader` / 独立 DNS 服务把它当作启动失败，
  不会以“过滤静默关闭”的状态起隧道；
- 桌面服务侧 `ParseServerStamp` 返回错误，上游配置构建随之失败，不会退化成“印章当作普通地址”；
  `RuleMatcher.BuildFromRules` 返回错误，规则引擎重建随之失败，不会退化成“规则静默不生效”。

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

规则文本：列表字节 ──parse_rules──> Rust 逐行解析+归一化 ──> 每行(pattern, flags, dnstype, denyallow, to, rewrite 原文)
          ──> Go 编译正则/通配源 + 解析 $dnsrewrite ──> []*ParsedRule ──> filter_build
```

布局与语义的权威注释在 `diting-rule-core/src/ffi.rs`、`search_ffi.rs`、`dtri.rs` 与
`diting-policy-core/src/ffi.rs`、`snapshot.rs`、`diting-filter-core/src/ffi.rs`、`parse.rs` 顶部；
改动要同步对应的 `ABI_VERSION` / `SEARCH_ABI_VERSION` 与 fixtures。

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

**印章（桌面服务）**：`resolver_stamp_test.go` 的用例一条都没改，现在全部穿过 FFI 落到 Rust。
`stamp.rs` 的单测把同一批向量逐条钉住（默认端口补全、props 位图、DoH 默认路径、VLP 截断、
IPv6 字面量、非 IP 地址、端口越界、不支持的协议族）；`ffi.rs` 的单测钉住载荷布局、拒绝消息与释放往返；
`stamp_native_test.go` 钉住布局版本不符 / 尾随字节 / 截断载荷必须报错，以及探测顺序。

印章解析只有 Rust 一份实现，Go 侧不再保留任何印章解析代码。

**规则索引（桌面服务）**：`RuleMatcher` 的对外行为一条没变，原 Go 用例（优先级、通配/正则例外、
`$denyallow=` 回落、`$dnsrewrite` 的取消 / 求和 / NODATA / 失败码优先 / 父域继承）现在全部穿过 FFI
跑到 Rust。`index.rs` 的用例逐条复刻了这批断言，`trie.rs` / `bloom.rs` 的单测接管了原 Go 里直接测
`DomainTrie` / `DomainBloomFilter` 的两条用例。

判定一致性靠三件事钉住：

- **同源的正则**：Go 传给内核的不是规则里的域名模式，而是它自己编译用的那份模式源
  （`(*regexp.Regexp).String()`），通配源仍由 `buildWildcardRegex` 单点推导，内核用同一套
  `diting-go-compat::regex` 翻译后编译；
- **同序的走法**：字典树的深度优先、精确标签优先于 `*`、通配/正则表按规则顺序首个命中即返回，
  三者共同决定“报哪一条规则”，所以 `MatchedRule` / `ListName` 与迁移前一致；
- **同形的载荷**：`payload.rs` 与 `filter_native_test.go` 各自钉住同一份布局，字段顺序或宽度一变
  就是布局版本不符的硬错误。

**规则文本解析（桌面服务）**：迁移时把同一份语料（200 行）分别喂给原 Go 解析器与 Rust 实现，
逐行对比「模式 + 全部标志位 + `$dnstype` + 两个排除集合」，并把这份对照固化成
`diting-filter-core/tests/fixtures/parse_corpus.tsv`（`parse/tests.rs` 逐行断言，含整份文档一次性的
结果）。域名归一化另跑了 194,432 个码点（U+0080..U+2FFFF 逐码点插进 `a<c>b.test`）的两边对照：
除了下面「已知边界」里列出的表版本差异，没有一处判定不同。原 Go 侧用例
（`rule_test.go`、`rule_modifiers_test.go`、`rule_modifiers_rewrite_test.go`）一条没改，现在全部穿过
FFI 跑；`parse_native_test.go` 另钉住请求/回应载荷布局、标志位与失败路径。

**策略内核**：`tests/policy_core.rs` 把 DTRI fixtures 喂给快照，断言每个可索引规则解析到语料声明的
source、禁用规则回落到父后缀；`ffi.rs` 的单测钉住构建 / 判定 / 释放往返与错误上报，以及归一化、
缓存命中与未命中答案一致、换新 prewarm；`cache.rs` 的单测钉住维度折叠、CLOCK 淘汰（热键存活）与
热键排序；`android/engine/policy_native_test.go` 用固定快照覆盖各规则族，并在 Go 侧逐条对比
`evaluate` 与 `evaluate_uncached`。

## 印章内核的已知边界

- **字符串字段必须是 UTF-8**：Rust 用 `String` 保存 lp-string，非法 UTF-8 直接报错；原 Go 实现会把
  原始字节照样带出。DNS 印章规范里全是 ASCII，只有手工构造的字节才会走到这里，所以选择明确报错。
- **base64 报错文案**：接受/拒绝的集合与 Go `RawURLEncoding.Strict()` 一致（不接受填充、尾随位必须为 0、
  长度 `% 4 == 1` 拒绝），但错误文字来自 `base64` crate，不是 Go 的
  `illegal base64 data at input byte N`。
- **地址校验用 Rust 的 IP 解析**：`Ipv4Addr`/`Ipv6Addr` 与 `net.ParseIP` 在带前导零的 IPv4、带 zone 的
  IPv6 上都拒绝，合法集合一致；地址文本按原样保留（只补端口、按需加 IPv6 方括号），不做重排。
- **`splitStampPort` 在两侧各有一份**：Rust 侧供印章解析用，Go 侧留给按主机名查证书指纹的 `pinHost`
  （处理的是普通 `host:port`，与印章无关）。改切分规则要同时改两处。
- **依赖**：`desktop/service` 的 `go.mod` 新增 `github.com/ebitengine/purego`（Apache-2.0），只用于
  Linux/macOS 的纯 Go 动态加载；Windows 走标准库 `syscall.LazyDLL`。两个内核共用这套加载器。

## 规则索引内核的已知边界

- **域名归一化仍在 Go 侧**：`RuleMatcher.Match` 先做
  `strings.TrimSuffix(strings.ToLower(strings.TrimSpace(d)), ".")` 再调内核，因为命中 `$dnsrewrite`
  时构造 `dns.RR` 需要同一个名字。跨边界契约就是“已归一化”，与策略内核一致。
- **正则的编译结果由 Go 决定**：规则先由 Go 的 `regexp` 编译（编译失败即丢弃规则，行为与迁移前
  一致），编译通过的源再交给内核翻译编译。若内核拒绝了某条 Go 接受的源，该规则永不命中，
  `BuildFromRules` 会记录条数（`uncompiled_patterns`）而不是静默丢弃整次加载。
- **应答记录仍在 Go**：内核只回传 `rcode` 与命中规则的下标，`dns.RR` 的构造（含 `$dnsrewrite` 的
  `TTL`、`dns.Fqdn` 与 SVCB 参数解析）留在 `rewrite_records.go`，等 rewrite 子系统迁移时一起走。
- **规则原文与来源仍在 Go**：载荷只带判定字段（标志位、`$dnstype`、排除集合、重写 `key`），
  命中后按下标回查 `[]*ParsedRule`，所以那条切片在匹配器重建前必须保持存活。
- **布隆过滤器不参与判定**：它只负责在拦截字典树之前挡掉干净域名，位宽与哈希个数与 Go 完全一致，
  但即便有差异也只会多走一次字典树——真正的语义在 `trie.rs` / `index.rs`。
- **不可达分支的选择**：`Match` 无法返回错误。若内核在单次调用上返回非 0 状态（句柄提前释放或
  ABI 错配这类不可达状态），Go 侧记录日志后回落 `pass`：DNS 过滤失败时放行比让解析器崩掉安全。
  构建期失败则是硬错误，不会走到这里。
- **`diting-go-compat` 是三个内核的唯一副本**：策略内核、规则索引与规则解析都用它的大小写折叠、
  后缀匹配、正则翻译与 `dns.StringToType`，`diting-policy-core` 以 `pub use ... as text/regex_go/dns_type`
  保留原路径，代码未改动。

## 规则文本解析的已知边界

- **IDNA 表版本**：Rust 用 `idna` crate 的 UTS 46 实现（ICU4X 编译数据），Go 侧原先用
  `idna.Lookup`（`golang.org/x/net@v0.57` 的 Unicode 表）。两边对**已分配的合法域名字符**判定一致；
  差异只在表版本：逐码点对照（U+0080..U+2FFFF，194,432 个）里 1655 个「后来才分配」的码点这里接受、
  Go 拒绝（如 U+0558、U+0B53、U+1ADE），U+2135..U+2138 反向。新表更接近当下的 Unicode，故不回去对齐。
- **`xn--` 空标签**：Go 的 idna 把空 punycode 载荷解成空标签，`||xn--.test^` 会变成模式 `.test`
  （永远匹配不到任何查询）；这里的 idna 拒绝它，整条规则被丢弃。这是唯一一条接受/拒绝不同的输入。
- **正则与通配源仍在 Go**：`/regex/` 由 Go `regexp.Compile("(?i)" + 源)` 编译（编译失败即丢规则），
  通配源由 `buildWildcardRegex` 单点推导后随规则交给匹配内核；内核只回传模式文本。
- **`$dnsrewrite` 取值仍在 Go**：内核回传原文（裸形式为空串），`parseDNSRewriteModifier` 负责取值解析
  与记录级校验，失败即丢规则（与迁移前一致）。它和 `buildRewriteRR` 属于 rewrite 子系统迁移的一部分。
- **非 UTF-8 列表**：字节按 UTF-8 有损解码（非法字节变 U+FFFD），与 Go 的 `strings.ToLower` 把非法
  字节折叠成 U+FFFD、IDNA 随即拒绝的结果一致；不会因为一个坏字节让整份列表加载失败。
- **单行 1 MiB 上限消失**：原实现用 `bufio.Scanner`（上限 1 MiB，超限整份列表报错），现在整份
  字节一次交给内核，超长行只是那一行解析失败。
- **`ParseRuleLine` 是每行一次 FFI**：只有自定义规则与内置服务目录走这条路（数百条，启动时一次），
  订阅列表走整份批量入口。
- **产物体积**：IDNA 表（`idna` + ICU4X 编译数据）让 `diting_filter_core` 的 release DLL 从 1.52 MB
  涨到 1.73 MB。只有桌面服务加载这个库，Android 的两个 `.so` 不受影响。

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

桌面规则判定（20k 条合成规则，1024 个域名轮转，`i % 5` 混合干净/字典树/通配/正则/重写）：

| 规则集 | 迁移前（Go） | 迁移后（Rust + FFI） | 纯 Rust |
|---|---|---|---|
| 生产比例（99% 纯域名、1% 通配、0.1% 正则） | 139–142 µs | 23.8–23.9 µs（约 5.9x） | 17.8 µs |
| 最坏情况（10% 通配、10% 正则） | 2.11 ms | 1.45 ms（约 1.45x） | 1.03 ms |

两种规则集的瓶颈不同：生产比例下每次查询要扫过 200 条通配 + 20 条正则（两份实现共有的线性表设计，
这一轮不改），Rust 的 `regex` 在同一批模式上比 Go 的 `regexp` 快得多，差距就在这里；最坏情况里
4000 条模式把两边都压到毫秒级，差距只剩正向匹配本身。纯 Rust 与经 FFI 之间的 1–6 µs
是 ABI 往返、载荷解码与 Go 侧归一化。20k 条规则的索引构建纯 Rust 约 12 ms，只在规则变更时发生。

复现：

```bash
cd rust && cargo run --release -p diting-filter-core --example filter_bench -- 20000 200000 realistic
cd desktop/service && go test -run XXX -bench BenchmarkRuleMatcherMatch -benchtime 200000x ./internal/core
```

规则文本解析（10 万行、2.45 MB 合成语料：88% 纯域名、4% 白名单、3% 通配、1% `$important`、
1% `$dnstype`、1% `$denyallow`、1% 正则、1% punycode IDN）：

| 路径 | 耗时 | 分配 |
|---|---|---|
| 迁移前：原 Go `ParseRules`（含 IDNA、正则编译、重写解析） | 172.7 ms | 71 MB / 901k 次 |
| 迁移后：`ParseRules` 端到端（编码 + FFI + 解码 + 同样的 Go 侧补做） | 150.1 ms | 84 MB / 591k 次 |
| 纯 Rust 解析（不含跨边界编解码与 Go 侧建 `ParsedRule`） | 70 ms | — |

纯解析只要原来的 0.4 倍，端到端却只快 15%：`ParsedRule` 仍然要逐条在 Go 里建出来（匹配器要
`Regex` 源、查询日志要 `Raw`），而载荷要跨两次边界（请求 2.4 MB、回应 6.2 MB）。整份列表只在
规则变更时解析一次。

复现：

```bash
cd rust && cargo run --release -p diting-filter-core --example parse_bench -- /tmp/bench100k.txt
cd desktop/service && DITING_PARSE_BENCH=/tmp/bench100k.txt   go test -run XXX -bench BenchmarkParseRulesLarge -benchtime 5x ./internal/core
```

决策缓存搬进内核后，命中也要过一次 FFI（此前 Go 侧直接返回，不进库）。纯 Rust 命中约 0.12 µs，
加上 cgo 调用仍远低于一次未命中的走法。
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
python rust/verify.py --desktop  # 再加桌面服务（Go）全量用例：印章解析与规则解析全部经 Rust
python rust/verify.py --dart     # 再加 Dart 侧规则解析与入库用例
python rust/verify.py --android  # 再加 arm64-v8a 交叉编译（两个 .so）
python rust/verify.py --bench    # 再加 DTRI / 检索 / 策略判定基准
python rust/verify.py --all      # 全量
```

`--go` 会先 `cargo build --release`（Go 侧按约定探测 `rust/target/release/`），并且需要 `cgo` 与
C 编译器（Windows 用 mingw，Linux/macOS 用 gcc/clang）。`--desktop` 不需要 cgo：桌面内核走纯 Go 动态
加载，先 `cargo build --release -p diting-stamp-core -p diting-filter-core` 再去 `desktop/service` 跑
`go test ./...`。`--dart` 同样需要先建好本机产物：Dart 侧
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

## 迁移方针

后端代码统一迁移到 Rust：所有模块都逐步完成迁移，不再按迁移收益、优先级或改动范围筛选。
迁移是**换主人**，不是加一条并存的快路径：模块迁完后原实现随之删除，不保留第二套语义。
跨语言边界沿用本文件的约定：独立 ABI 版本号、固定载荷布局、语料与 fixtures、`verify.py` 入口。

## 后续可做

- **快照构建提速**：Rust 侧按流式解析 / 并行建表，把 53k 规则的 ~30 ms 压到十几毫秒。
- **正则语义彻底对齐**：字符类里的 `\D\W\S` 也翻成 ASCII 取反，把“已知边界”里那条消掉。
- **去重键去字符串化**：每条规则拼一个去重键约占解析时间三成，改成字段哈希 + 碰撞时逐字段比较。
- **DTRI 增量更新**：按 source 分片只重编受影响分片，把万级列表的写入后延迟压到一次小编译。
- **检索索引预热**：表稳定后在空闲时预热，把首次折叠的 ~30 ms 从“第一个键”挪开。
- **桌面服务的 rewrite 子系统**：`rewrite.go` / `rewrite_lookup.go` /
  `rewrite_records.go` 是独立于 `$dnsrewrite` 修饰符的另一套入口（自定义重写记录 + SVCB 参数解析），
  与规则解析共用记录构造。搬完它顺带带走的还有三件留在 Go 的事：`$dnsrewrite` 取值的记录级校验、
  `RewriteAction.key()` 的取值归一化（现在由 Go 算好再交给匹配内核），以及 `ParsedRule` 上那个
  `*regexp.Regexp`（正则源届时可以只在 Rust 侧编译）。
- **正则与通配模式的编译归属**：现在 Go 编译后把源交给内核，两条路径各编一次；rewrite 子系统
  迁移时把 `ParsedRule.Regex` 一并搬走，`buildWildcardRegex` 就只剩内核里的一份。
- **备份导入导出**：语义面较大，可先精简备份格式再逐组迁移。
