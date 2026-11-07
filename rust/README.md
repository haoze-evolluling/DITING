# Rust 内核

十九个 crate：`diting-rule-core` 负责规则数据的解析与索引，`diting-policy-core` 负责
**Go 隧道引擎的规则判定与决策缓存内核**，`diting-dns-cache-core` 负责**同一引擎的 DNS 缓存
容器与查询内核**（wire 取值、分片 LRU、TTL 策略、清扫、统计与快照），`diting-mitm-core` 负责
**同一引擎的 MITM 拦截过滤**（应用白名单、`path.Match` 排除规则、敏感主机判定、自动黑名单与
失败计数、持久化文件），`diting-stamp-core` 负责**桌面服务的 `sdns://` 印章解析**，
`diting-filter-core` 负责**桌面服务的规则文本解析与规则索引匹配**，`diting-rewrite-core` 负责
**桌面服务的重写引擎、重写记录取值解析与 `$dnsrewrite` 取值解析**，`diting-safebrowsing-core` 负责
**桌面服务的声誉查询哈希前缀内核**（主机归一化与校验、各级父域的 SHA-256、前缀查询名、TXT 摘要
解析、按前缀的 LRU），`diting-hosts-core` 负责**桌面服务的本地权威内核**（hosts 文件解析、
IPv4/IPv6/反查映射、`HasDomain`、`.in-addr.arpa` / `.ip6.arpa` 反查名解析），
`diting-dns64-core` 负责**桌面服务的 DNS64 合成内核**（`net.ParseCIDR` 语义的前缀解析、RFC 6052
地址嵌入、RFC 6147 排除集与“应答里是否已有有效 AAAA”），`diting-cosmetic-core` 负责**同一隧道
引擎的装饰注入内核**（流式 `<head>` 扫描、主机名归一化与 `<link>` 标签），`diting-resolver-core`
负责**同一隧道引擎的上游统计与调度评分内核**（SRTT + RTTVAR 估计、失败率 EWMA、连败惩罚、熔断与
半开探针，以及 hedge / 单次超时 / UDP 重试三种自适应延迟），`diting-dns-core` 负责**同一隧道引擎的
DNS 应答检查与阻断升级内核**（上游空答案判定、唯一地址列表，以及按域名的请求窗口、NODATA 与
NXDOMAIN 动态升级），`diting-sniffer-core` 负责**同一隧道引擎的 TLS / 明文 HTTP 流嗅探内核**
（ClientHello 记录、握手与扩展长度走法、SNI 取值、HTTP 方法门禁、`Host` 头取值与 Go 语义的
字节级 TrimSpace / EqualFold），`diting-bootstrap-core` 负责**同一隧道引擎的加密 DNS 引导解析内核**
（端点健康的半衰期衰减、EWMA 延迟与抖动、连败惩罚与冷却、带探索率的加权选择、回退排序与一分钟
主机缓存），`diting-allowlist-core` 负责**同一隧道引擎的严格应用白名单内核**（域名的 Unicode
小写 / 去空白 / 去一个尾点归一化、逐级父域后缀走法、按 UID 的 TTL 授权表、应答按域名分发与
256 条剪枝），`diting-connlog-core` 负责**同一隧道引擎的连接日志去重内核**（`connLogKey`
的逐字节构造、8192 条上限的键集合、溢出整表清空与清空计数），`diting-ipcache-core` 负责**同一隧道引擎的
IP→域名 LRU 内核**（原地更新并把条目移到最近写入位置、淘汰最久未写入项、`get` 不提升、非正容量
回退 2048），`diting-go-compat` 是各内核共用的 Go 标准库语义（大小写折叠、
`strings` 辅助、`regexp` 翻译、`dns.StringToType`、`net.IP` 文本与折叠）。
二十三个接入点都只有 Rust 一条实现，原实现已删除：库缺失、ABI 不匹配或载荷被拒时直接报错，不再有
第二套语义可以静默跑起来。六个例外都只影响“复用、调度、判定辅助、取址路径、日志去重与主机名提示”，
不影响回答：DNS 缓存
内核缺失时缓存停用、查询直连解析器；解析器统计内核缺失时每个上游按冷启动取值参与调度；DNS 应答
内核缺失时空答案按普通应答记日志、动态升级关闭（每个阻断沿用配置的应答模式）；引导解析内核缺失时
加密 DNS 提供商主机名按普通系统解析路径取址；连接日志去重内核缺失时不再去重（日志更吵，事件不变）；
IP→域名缓存内核缺失时直连 IP 的流没有主机名提示（标签缺失，回答不变）。流嗅探内核缺失时 MITM 启动失败（隧道照常起，只是
不解密），直连回退只是少了 SNI 的主机名提示，也不影响回答。应用白名单内核缺失时，**已配置规则**的
引擎对被选中的 UID 拒绝 DNS 与连接（fail-closed，环回仍放行），未选中的应用与未配置规则时行为不变；它不会静默放行已开启的严格模式。

| 入口 | 调用方 | Rust 产物 | 缺失时 |
|---|---|---|---|
| 规则文档解析 | Dart（`dart:ffi`） | 归类、去重、`$badfilter` 聚合后的紧凑载荷 | 导入抛错 |
| 规则页检索 | Dart（`dart:ffi`，句柄） | 预折叠索引，查询返回命中行号 | 规则页抛错 |
| DTRI 索引编译 | Kotlin（JNI） | mmap 索引，与 JVM 参考实现逐字节相同 | 快照编译失败 |
| 策略快照构建 + 判定 + 决策缓存 | Go（`dlopen` + C ABI） | 规则表、通配索引、DTRI 读取、七级优先级、归一化与缓存 | 隧道启动失败 |
| DNS 缓存容器 / 键 / 响应元数据 / ID-TTL 改写 | Go（`dlopen` + C ABI，句柄） | 分片 LRU、TTL 策略、清扫、缓存键、最小 TTL 与 TTL 偏移、链目标、A/AAAA、改写副本、统计与快照 | 缓存停用：不写入、不命中（直连上游） |
| MITM 拦截过滤 + 自动黑名单 | Go（`dlopen` + C ABI，句柄） | 应用白名单、`path.Match` 排除规则、敏感主机启发式、失败计数与黑名单 TTL、持久化文件 | MITM 启动失败（隧道照常起，只是不解密） |
| DNS 印章解析 | Go 桌面服务（纯 Go 动态加载 + C ABI） | 解析后的印章记录、`URL()`/`Server()` 派生串 | 上游配置失败 |
| 规则索引与匹配 | Go 桌面服务（纯 Go 动态加载 + C ABI） | 四层字典树、布隆预检、通配/正则表、判定与重写选择 | 规则索引构建失败 |
| 规则文本解析 | Go 桌面服务（同一个库，纯 Go 动态加载 + C ABI） | 逐行的模式、标志位、`$dnstype`、排除集合与 `$dnsrewrite` 取值 | 列表加载失败 |
| 重写记录构造 | Go 桌面服务（纯 Go 动态加载 + C ABI） | 类型表、目标域名判定、A/AAAA/CNAME/NS/PTR/TXT/MX/SRV/HTTPS/SVCB 取值与 SVCB 参数 | 构建 `dns.RR` 失败，该记录/规则被丢弃并写日志 |
| `$dnsrewrite` 取值解析 | Go 桌面服务（同一个库，纯 Go 动态加载 + C ABI） | 应答码关键字、显式/简写切分、取值校验、例外比对键的归一化 | 规则被丢弃（与非法正则一致） |
| 重写引擎索引 + 查询 | Go 桌面服务（同一个库，纯 Go 动态加载 + C ABI） | 精确/泛域名索引、PTR 反查、rcode 覆盖、CNAME 链、属主 CNAME 合并、记录列表 | 重写引擎启动失败（配置变更同样报错） |
| 声誉查询哈希前缀 | Go 桌面服务（纯 Go 动态加载 + C ABI，句柄） | 主机归一化与域名校验、各级父域 SHA-256、前缀查询名、TXT 摘要解析、按前缀的 LRU 与 TTL | 声誉查询引擎启动失败 |
| 本地 hosts 权威应答 | Go 桌面服务（纯 Go 动态加载 + C ABI，句柄） | hosts 文本解析、各级映射与 PTR 别名、`HasDomain`、反查名解析 | hosts 解析器启动失败 |
| DNS64 合成 | Go 桌面服务（纯 Go 动态加载 + C ABI，句柄） | 前缀解析与 RFC 6052 嵌入、RFC 6147 排除集、有效 AAAA 判定 | DNS64 合成器启动失败 |
| 装饰注入（HTML 流式改写） | Go 隧道引擎（`dlopen` + C ABI，句柄） | `<head>` 扫描状态机（carry / pending / 16 KiB 上限）、主机名归一化与 `url.QueryEscape`、`<link>` 标签 | MITM 启动失败（隧道照常起，只是不解密） |
| 解析器统计（SRTT / 熔断 / 自适应延迟） | Go 隧道引擎（`dlopen` + C ABI，每上游一个句柄） | SRTT + RTTVAR 估计、失败率 EWMA、连败惩罚的半衰期衰减、熔断与半开探针、hedge / 单次超时 / UDP 重试 | 调度退回冷启动取值（默认评分、冷启动延迟、每次尝试都放行），回答不变 |
| DNS 应答检查 + 动态阻断升级 | Go 隧道引擎（`dlopen` + C ABI，引擎一个句柄） | 上游空答案判定（全为 `0.0.0.0` / `::` / 回环）、唯一地址列表、按域名的窗口计数与 NODATA→NXDOMAIN 升级 | 空答案按普通应答记日志、升级关闭（阻断沿用配置模式），回答不变 |
| TLS / 明文 HTTP 流嗅探 | Go 隧道引擎（`dlopen` + C ABI） | ClientHello 记录/握手/扩展长度走法与 SNI、HTTP 方法门禁与 `Host` 头 | MITM 启动失败（隧道照常起，只是不解密）；直连回退丢失 SNI 主机名提示，回答不变 |
| 加密 DNS 引导解析评分 | Go 隧道引擎（`dlopen` + C ABI，每解析器一个句柄） | 端点健康的半衰期衰减、EWMA 延迟与抖动、连败惩罚与冷却、带探索率的加权选择、回退排序与一分钟主机缓存 | 引导解析停用（主机名走普通系统解析路径），回答不变 |
| 严格应用白名单（域名判定 + IP 授权） | Go 隧道引擎（`dlopen` + C ABI，每引擎一个句柄） | 域名归一化与逐级父域走法、按 UID 的 TTL 授权表、应答按域名分发、256 条剪枝 | 已配置规则时被选中 UID 转 fail-closed（拒绝 DNS 与连接，环回仍放行）；未选中的应用与未配置时行为不变 |
| 连接日志去重 | Go 隧道引擎（`dlopen` + C ABI，全局一个句柄） | `connLogKey` 的构造、8192 条键集合、溢出整表清空与清空计数 | 不再去重（日志更吵），事件与回答不变 |
| IP→域名 LRU 缓存 | Go 隧道引擎（`dlopen` + C ABI，每引擎一个句柄） | 原地更新 + 移到最近写入位置、淘汰最久未写入项、`get` 不提升、非正容量回退 2048 | 主机名提示停用（直连 IP 的流没有域名标签），回答不变 |

第四个是**职责划分的迁移**：域名归一化、规则判定与决策缓存整体在 Rust，Go 侧只保留快照生命周期
（构建、原子换新、延迟释放）。第五个把地址校验、默认端口省略与 DoH 默认路径也一并搬走了，
Go 侧只留取值类型与证书指纹适配。第六个搬的是每次查询都走的判定内核：Go 只保留规则文本、
规则加载与 `$dnsrewrite` 的应答记录构造，判定结果以「命中第几条规则」的形式回传。第七个把
**读文本**这一段也交给了 Rust（`rule_parser.go` 整份删除）：注释与元素隐藏规则、hosts 形式、
`@@`、`$` 修饰符切分、`$dnstype`、`$denyallow=`/`$to=`、AdGuard 域名形态、通配模式与 IDNA 归一化。
Go 侧只留两件仍然属于它的事：`regexp` 与 `buildWildcardRegex` 的编译（匹配器要用编译后的源），
以及 `$dnsrewrite` 取值解析（它连同 `buildRewriteRR` 属于 rewrite 子系统那一轮）。第八个把
**重写记录的取值语法**搬到了 Rust（`rewrite_records.go` 的 `buildRewriteRR` 只剩一层载荷解码）：
记录类型表、目标域名判定、MX/SRV 的字段切分、HTTPS/SVCB 的参数列表与 AdGuard Home 对齐的取值限制
都在 `record.rs`，Go 侧只按回传的类型号填 `dns.RR`（应答要直接进 `dns.Msg`）。自定义重写规则与
`$dnsrewrite` 修饰符走同一条路径，所以两边的取值语法不可能再各写一份。第九个搬的是 Android
隧道引擎的 **DNS 缓存 wire 层**（`dns_cache_wire.go` 整份删除）：问题键、最小 TTL / SOA 回退、
TTL 偏移、CNAME/SVCB/HTTPS 目标、A/AAAA 文本化以及命中时的 ID/TTL 改写都在 `wire.rs`。Go 侧只留
分片 LRU、TTL 策略算术、单飞与清扫，缓存条目里不再有第二份 `dns.Msg` 解包结果。第十个把桌面服务的
**重写引擎本身**搬进同一个 crate（`rewrite.go` / `rewrite_lookup.go` 只剩配置与 `dns.RR` 构造）：
域名归一化、精确/泛域名索引、PTR 反查、rcode 覆盖、CNAME 链与属主 CNAME 合并都在 `engine.rs`；
显式记录在快照构建时一次编译（不再每次命中重新解析），命中时回传完整记录列表。Go 侧保留配置本身
（IPC 的 JSON 形态与增删改），每次变更重建快照并换新，旧句柄在写锁内释放。第十一个把
**`$dnsrewrite` 的取值语法**也搬进同一个 crate（`rule_modifiers_rewrite.go` 只剩结构、展示文案与
`dns.RR` 构造）：应答码关键字、`RCODE;TYPE;VALUE` 的切分、简写形式（地址 / CNAME / 裸形式）与取值校验
都在 `action.rs`，校验直接走 `record::build`，所以修饰符与自定义重写规则不可能对同一个取值给出两种
答案。例外规则用于互相取消的归一化键也从 `RewriteAction.key()` 搬进内核：比对发生在规则索引里，
把归一化留在调用方就会让 `127.0.0.1` 与 `::ffff:127.0.0.1` 这类等价写法取消不掉对方。

第十二个把 Android 隧道引擎的 **DNS 缓存容器本身**搬进同一个 crate（`dns_cache.go`、
`dns_cache_types.go`、`dns_cache_policy.go`、`dns_cache_snapshot.go` 整份删除）：分片 LRU 与
FNV 分桶、命中晋升节流、TTL 策略算术（跟随 / 上限 / 固定 / 最小）、RFC 2308 负缓存、过期条目的
懒惰与后台清扫、统计与按命中数排序的快照都在 `cache.rs` / `policy.rs`。Go 侧只剩三件必须留在 Go
的事：单飞（它要调用 Go 的解析回调）、缓存句柄的 finalizer，以及把内核回传的布尔标志缓存成原子量
供引擎在调用前判断开关。命中路径仍是一次 FFI：内核返回「改写后的 wire + 链目标 + IP 列表」，
Go 把它们交给原有的应答链与应用放行逻辑。

第十三个把 Android 隧道引擎的 **MITM 智能过滤**搬进 `diting-mitm-core`（`mitm_filter.go` 只剩日志与
句柄生命周期、`sniSensitiveKeywords` 与 `matchHostPattern` / `isSensitiveHost` / `isIPAddress` 整份删除）：
应用白名单、排除规则（Go `path.Match` 的逐字节复刻）、敏感主机启发式、失败计数与自动黑名单、
持久化文件都在内核里。时间从 Go 注入（`now_ms`），内核不读时钟，所以过期与十分钟失败窗口能被
单测钉死；文件由内核读写，Go 只把路径交给它。日志仍然在 Go：内核回传“失败计数 / 阈值 / 归一化
主机 / 原因 / 写入错误”，Go 照原格式打印。

第十四个把桌面服务的 **声誉查询哈希前缀层**搬进新建的 `diting-safebrowsing-core`
（`safebrowsing.go` 只剩上游查询、`context` 超时、fail-open 取舍与计数）：主机归一化与
`dns.IsDomainName` 校验、各级父域的 SHA-256、eTLD+1 之上 4 层的截断、公共后缀的排除、前缀查询名、
TXT 摘要解析、按前缀的 LRU 与 TTL 都在 `hash.rs` / `cache.rs` / `engine.rs`。Go 侧保留的三件事都
是不过回调就搬不动的：向上游解析器的 `Exchange` 调用（fail-open 的方向由它决定）、超时，以及供 UI
展示的统计。缺库时 `NewSafeBrowsingEngine` 返回错误、服务启动失败，不会以“界面显示已开启、实际
什么都没查”的状态跑起来。

第十五个把桌面服务的**本地权威 hosts 层**搬进新建的 `diting-hosts-core`（`hosts_resolver.go`
只剩配置、TTL 与把地址填进 `dns.RR` 的那几行）：行解析（`#` 注释、Unicode 空白分列、接口 zone
截断、`net.ParseIP` 接受的字面量）、IPv4/IPv6 两张表、反查表与别名顺序、`HasDomain`、以及
`.in-addr.arpa` / `.ip6.arpa` 的反查名解析都在内核里。反查名解析原本是 hosts 与重写引擎共用的
Go 函数，现在只剩内核一份，`ParseIPFromArpa` 变成一次调用。文件读取也进了内核（表由「路径 +
内联文本」的 source 列表构建），`Reload` 重读上次真正读成功的路径，`UpdateConfig` 先建新表再在
写锁内换指针并释放旧表，热重载窗口里没有「解析不出、也不再是本地权威」的空档（BUG-59）。

第十六个把桌面服务的 **DNS64 合成层**搬进新建的 `diting-dns64-core`（`dns64.go` 只剩配置、锁与
`dns.AAAA` 构造）：`net.ParseCIDR` 的接受/拒绝判定（`netip.ParseAddr` 的地址规则、`dtoi` 允许前导零
的掩码、IPv4 网段算 `bits = 32`）、RFC 6052 六种前缀长度下的字节摆放与保留的 `u` 位、
`IPNet.Contains` 的 `To4` 折叠、RFC 6147 排除集，以及 `HasValidAAAARecords` 都在内核里。这个
折叠有个反直觉的后果被照抄了下来：默认排除项 `::ffff:0:0/96` 的网段会塌成 `0.0.0.0/0`，
于是**任何** IPv4 形态的地址都算被排除（语料钉住了这一点）。Go 侧留下的是需要 `dns.Msg` 与解析器
的部分：A 记录问询、A/CNAME/DNAME 的最小 TTL、把别名补进应答、构造 `dns.AAAA`。缺库时
`NewDNS64Synthesizer` 返回错误、服务启动失败；前缀写错仍然只是警告（改配置要经过 UI，服务得先活着）。

第十七个把 Android 隧道引擎的**装饰注入**搬进新建的 `diting-cosmetic-core`（`mitm_cosmetic_inject.go`
只剩规则载荷、日志与 `io.ReadCloser` 包装）：流式扫描器整体在 `inject.rs` —— 尾部半截 `<head`
标记的 carry、注入后放不下的 pending、16 KiB 扫描上限、`>` 之后拼接的位置都在内核里，
`normalizeCosmeticHost`（`net.SplitHostPort` 的形状判定 + 一个尾点）、`url.QueryEscape` 与 `<link>`
标签在 `host.rs`。本地资产服务器服务 `?h=<host>` 时走同一个 FFI（`normalize_host`），
注入的链接与查到的规则不可能对同一个主机给出两种写法。Go 侧留下的是必须留在 Go 的：规则 JSON
载荷、`ShouldInjectHTML`（一行 `strings.Contains`，加一次 FFI 只是给谓词多一条错误路径）、
响应头与 zlib 解压、以及 reader 的 `Close`（释放句柄的唯一时机）。

第十八个把 Android 隧道引擎的 **上游统计与调度评分**搬进新建的 `diting-resolver-core`
（`resolver_stats.go` 只剩句柄、`time.Duration` 换算与冷启动回退）：RTO 式的 SRTT/RTTVAR 估计、
失败率 EWMA、连败惩罚的半衰期衰减、指数退避的熔断与半开探针，以及 hedge 延迟、单次尝试超时、
plain UDP 重试间隔三档自适应取值都在 `stats.rs`。时间从 Go 注入（`now_ns`），内核不读时钟，所以
迁移时能把原 Go 实现的 76 步操作轨迹逐字段固化成 `tests/fixtures/stats_trace.tsv` 并对拍。Go 侧
留下的是它自己的类型（每个上游一个 `*providerStats`）、四处 `time.Now()` 与 `time.Duration`
换算。缺库时每个上游按冷启动取值参与调度（默认评分、冷启动延迟、每次尝试都放行），这正是迁移前
“没有统计的上游”的既有形态，回答不变。

第十九个把 Android 隧道引擎的 **DNS 应答检查与动态阻断升级**搬进新建的 `diting-dns-core`
（`dns_response_helpers.go` 只剩 `dns.Msg` 到载荷的遍历与缓存回填，`dns_config.go` 只剩配置结构）：
「整段 A/AAAA 都是 `0.0.0.0` / `::` / 回环」的空答案判定与唯一地址列表在 `answer.rs`，按域名的请求
窗口、阈值、NODATA 与 NXDOMAIN 冷却（含 4096 条上限）在 `block.rs`。`net.IP` 的文本形态与折叠搬进了
共用的 `diting-go-compat::ip`：`net.IP.String()` 的 `?hex` / `<nil>` 分支、IPv4 映射折叠、`netip`
的零段压缩规则都由迁移语料逐条钉住。Go 侧留下的是 `dns.Msg` 的记录遍历（记录本身是 Go 值，还要
进缓存与应答链）、`dns.Question` → `dns.RR` 的构造、`time.Duration` 换算与 `ipDomainCache` 的写入。
阻断模式的四个枚举值与其文本拼写（`ParseResponseType`）也留在 Go：它是枚举的字面拼写，不是判定逻辑。

第二十个把 Android 隧道引擎的 **TLS / 明文 HTTP 流嗅探**搬进新建的 `diting-sniffer-core`
（`mitm_sniffer.go` 只剩一次 peek `Read`、回放 reader 与 `intToStr`）：`parseClientHelloSNI`
的 TLS 记录、握手、session / cipher / compression / extension 长度走法与 SNI 列表取值，
`looksLikeHTTPRequest` 的 16 字节方法门禁，`parseHTTPHost` 的 CRLF 行走与 `Host` 取值都在内核里。
剪枝的两处细节也照抄了：`strings.TrimSpace` 按 rune 剪枝但保留原始字节（非法 UTF-8 字节不是空白，
不能走 `String` 往返），`strings.EqualFold(name, "Host")` 在 ASCII 目标下只多一个 `ſ`（U+017F）
折叠成 `s`。分类门槛仍是调用方的那个（至少 3 字节、`0x16`、主版本 `0x03`），所以“过了门槛但解析器
读不出来”仍然是 TLS + 空主机名，回退到 IP，而不是把流当成别的东西直连。Go 侧只留 peek、超时、
回放 reader 与拨号/中继；MITM 启动时 `ensureSnifferKernel` 失败即启动失败，直连回退用同一个分类调用，
缺库只是没有主机名提示（与 SNI 解析为空一致）。

第二十一个把 Android 隧道引擎的**加密 DNS 引导解析评分**搬进新建的 `diting-bootstrap-core`
（`bootstrap_resolver.go` 只剩 JSON 配置、UDP 查询、日志回调与 `net.IP` 直通）：端点健康的
半衰期衰减、EWMA 延迟与抖动、连败惩罚、三连败后的 30 秒冷却，以及“按权重抽主端点 + 冷却/低样本
时提高探索率 + 回退按权重降序稳定排序”的选择逻辑都在内核里。时间与随机数都从 Go 注入：
`now_ns`、两次 `rand.Float64()` 与一次 `rand.Uint64()`（内核按候选数取模，仅此与 `rand.Intn`
的取模偏差不同，分布用例钉住结论），所以整条健康轨迹能被离线重放。主机缓存（60 秒）也进了内核，
配置变更只清缓存、`ResetStats` 清健康与缓存，与迁移前的两处生命周期一致。Go 侧保留的是必须留在
Go 的：JSON 形态的配置、`queryBootstrapDNS` 的拨号与 `dns.Msg` 解析、日志文案。缺库时
`newBootstrapResolver` 拿不到句柄，`IsEnabled` 直接为假，调用方按“未配置引导服务器”的既有路径
用主机名拨号——这正是迁移前没有引导配置时的形态，回答不变。

第二十二个把 Android 隧道引擎的**严格应用白名单**搬进新建的 `diting-allowlist-core`
（`engine_app_allowlist.go` 只剩 JSON 配置、`dns.Msg` 的 A/AAAA 遍历与 `net.IP` 环回快路径）：
配置项归一化（`strings.TrimSpace` → `strings.ToLower` → 去一个尾点）、查询名的“只小写 + 去一个
尾点”归一化、逐级父域走法、按 UID 的 IP 授权表与 TTL、应答按域名分发给所有匹配 UID（netd 归属
的查询也能授权真正的应用），以及超过 256 条时只清理已过期项，全部在内核里。`domainMatches` 的
`strings.ToLower` 走共用的 Go 语义实现（`U+0130` 折叠为 `i`，Rust 的完整映射会多出组合点），
语料钉住了这一点。Go 侧保留的是必须留在 Go 的：JSON 形态与 `strconv.Atoi`、`dns.Msg` 的记录
遍历（A 取 `To4()`、AAAA 取 `To16()`）、`ip.IsLoopback()` 的快路径与日志。时间由 Go 注入
（`now_ns`），测试用假时钟替代直接改表。缺库时未配置规则不受影响；已配置规则的引擎转到
fail-closed：被选中 UID 的 `domainAllowed` / `connectionAllowed` 一律拒绝（环回仍放行），未选中的应用不受影响，不会静默把严格模式
变成全放行。

第二十三个把 Android 隧道引擎的**连接日志去重**搬进新建的 `diting-connlog-core`
（`engine_connection_log.go` 只剩 flow → app/dest 推导、日志文本与回调分发）：`connLogKey` 的
逐字节构造（`[blk|]app|dest|port|proto[|reason]`、`strconv.AppendInt` 的十进制拼写）、8192 条
键集合、满表后整表清空、以及只在溢出时递增的 `cleared` 计数都在内核里。这一步还去掉了 Go 侧每个
flow 都分配的拼接字符串——包括随后被丢弃的重复项。Go 侧保留的是必须留在 Go 的：UID/包名解析、
端口与协议的来源、日志文案。缺库时 `markSeen` 恒为“没见过的键”，也就是**不再去重**：事件一条
不少，只是日志更吵；回答不受影响。

第二十四个把 Android 隧道引擎的 **IP→域名 LRU 缓存**搬进新建的 `diting-ipcache-core`
（`ip_domain_cache.go` 只剩句柄；调用方照旧传 `net.IP.String()`）：键表、最近写入顺序、命中时
不提升、原地更新后移到最近写入位置、满容量时淘汰最久未写入项，以及非正容量回退 2048 都在内核里。
顺序用一个单调递增的 `u128` 戳 + `BTreeMap<戳, IP>` 实现，等价于 Go 的 `container/list`
`MoveToFront` / `Back()`，淘汰是 `O(log n)` 且没有 unsafe 链表；`get` 不写时间戳，所以“读不提升”
这条与迁移前完全一致。缺库时每次查询都 miss，直连 IP 的流失去主机名提示，回答与转发不受影响。

Android 侧用 cgo 调策略内核、DNS 缓存内核、MITM 过滤内核、装饰注入内核、解析器统计内核、DNS 应答内核、流嗅探内核、引导解析内核、应用白名单内核、连接日志去重内核与 IP→域名缓存内核；桌面服务侧刻意**不用 cgo**：Windows 走
`syscall.LazyDLL`，Linux 走 `purego`，`CGO_ENABLED=0 GOOS=linux GOARCH=... go build` 的交叉编译链
一行都不用改。

## 结构

```
rust/
├── build_android.py                # NDK 交叉编译十二个 Android crate + 拷入 jniLibs
├── verify.py                       # fmt / clippy / test / Go / Dart / 基准
├── diting-rule-core/src/
│   ├── models.rs domain.rs line.rs hosts.rs document.rs   # 解析（取代原 rule_parser.dart 等）
│   ├── ffi.rs                      # 解析的 C ABI + 载荷格式（ABI_VERSION）
│   ├── search.rs search_ffi.rs     # 折叠与检索索引、C ABI、句柄（SEARCH_ABI_VERSION）
│   ├── dtri.rs dtri/tests.rs       # DTRI 写入器（取代 MappedSubscriptionRuleIndex.compile）
│   ├── jni_bridge.rs               # Kotlin 调用 DTRI 的 JNI 入口
│   └── fast_hash.rs                # 去重索引用的随机种子 FxHash
├── diting-go-compat/src/
│   ├── text.rs                     # Go 语义的 ToLower / ToUpper / TrimSpace / 去尾点 / 后缀匹配
│   ├── regex.rs                    # Go regexp → Rust regex 翻译、规则正则编译与前缀预筛
│   └── dns_type.rs                 # dns.StringToType（多个内核共用的类型表）
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
├── diting-rewrite-core/src/
│   ├── record.rs record/tests.rs   # 重写记录：类型表、目标域名判定、各类型取值与 SVCB 参数（原 buildRewriteRR）
│   ├── action.rs action/tests.rs   # $dnsrewrite 取值语法与例外比对键的归一化（原 parseDNSRewriteModifier + RewriteAction.key）
│   ├── engine.rs engine/tests.rs   # 重写引擎：精确/泛域名索引、PTR、rcode、CNAME 链与属主合并（原 rewrite.go + rewrite_lookup.go）
│   ├── payload.rs                  # 记录请求/回应、动作请求/回应与引擎配置/回应的二进制布局
│   └── ffi.rs ffi/tests.rs         # build_record / record_types / parse_action / action_key / engine_* / free_bytes（ABI_VERSION）
├── diting-safebrowsing-core/src/
│   ├── hash.rs hash/tests.rs       # 主机归一化与校验、各级父域 SHA-256、查询名、TXT 摘要（原 normalizeCheckHost 等）
│   ├── cache.rs cache/tests.rs     # 按 2 字节前缀的 LRU：查找、写入、过期、淘汰（原 hashCache）
│   ├── engine.rs engine/tests.rs   # 两个服务的缓存与 plan/apply（原 hashChecker 与 SafeBrowsingEngine 的缓存部分）
│   ├── payload.rs payload/tests.rs # 计划与应答请求的二进制布局
│   └── ffi.rs ffi/tests.rs         # new / configure / plan / apply / free / free_bytes（ABI_VERSION）
├── diting-hosts-core/src/
│   ├── ip.rs ip/tests.rs           # net.ParseIP 与 To4 折叠、hosts 条目的 zone 截断（原 net.ParseIP 用法）
│   ├── arpa.rs arpa/tests.rs       # .in-addr.arpa / .ip6.arpa 反查名解析（原 ParseIPFromArpa）
│   ├── hosts.rs hosts/tests.rs     # hosts 文本解析、三张映射、lookup / has_domain / ptr / reverse
│   ├── payload.rs payload/tests.rs # source 列表、表信息、查表、反查与反查名的二进制布局
│   └── ffi.rs ffi/tests.rs         # new / info / lookup / contains / ptr / reverse / parse_arpa（ABI_VERSION）
├── diting-hosts-core/tests/fixtures/expectations.tsv  # 迁移时 Go 实现生成的地址/反查名/查表语料
├── diting-dns64-core/src/
│   ├── addr.rs addr/tests.rs       # netip.ParseAddr 文本规则、To4 折叠、CIDRMask、dtoi
│   ├── prefix.rs prefix/tests.rs   # net.ParseCIDR、RFC 6052 前缀集、IPNet.Contains
│   ├── engine.rs engine/tests.rs   # 前缀表、排除集、嵌入 / 合成 / 排除 / 有效 AAAA
│   ├── payload.rs payload/tests.rs # 前缀表、地址表与合成结果的二进制布局
│   └── ffi.rs ffi/tests.rs         # new / embed / embed_prefix / synthesize / excluded / has_valid
├── diting-dns64-core/tests/fixtures/   # 迁移时 Go 实现生成的前缀/嵌入/排除/合成语料（5 份 TSV）
├── diting-safebrowsing-core/tests/fixtures/hash_corpus.tsv  # 迁移时 Go 实现生成的主机→摘要→查询名语料
├── diting-filter-core/tests/fixtures/parse_corpus.tsv  # 迁移时 Go 解析器的 200 行语料快照
├── diting-dns-cache-core/src/
│   ├── wire.rs wire/tests.rs       # 缓存键、记录遍历、TTL 偏移、最小 TTL/SOA、链目标、A/AAAA、ID/TTL 改写
│   ├── policy.rs policy/tests.rs   # 配置归一化、TTL 策略算术、RFC 2308 负缓存、调用方布尔标志（原 dns_cache_policy.go）
│   ├── cache.rs cache/maintenance.rs cache/tests.rs
│   │                               # 分片 LRU、条目与截止时间、晋升节流、清扫线程、统计、快照（原 dns_cache.go 等四份）
│   ├── payload.rs                  # 与 Go 共享的配置 / 命中 / 统计 / 快照二进制布局
│   └── ffi.rs ffi/tests.rs         # 句柄生命周期 + question_key / get / put / refresh / stats / snapshot 的 C ABI（ABI_VERSION）
├── diting-mitm-core/src/
│   ├── pattern.rs pattern/tests.rs # Go `path.Match` 的逐字节复刻 + `matchHostPattern`（排除规则）
│   ├── sensitive.rs sensitive/tests.rs # `isSensitiveHost` / `isIPAddress`（银行、支付、身份端点）
│   ├── filter.rs filter/tests.rs   # 白名单、失败计数、黑名单 TTL、持久化文件（原 mitm_filter.go）
│   ├── payload.rs                  # 与 Go 共享的判定报告二进制布局
│   ├── ffi.rs ffi/tests.rs         # new / free / set_allowed_uids / set_bypass_rules / allows_interception / record_failure / blacklist / load_persistent / free_bytes（ABI_VERSION）
│   └── tests/fixtures/*.tsv        # 迁移时 Go 原函数生成的 path.Match / host 模式 / 敏感主机语料
├── diting-cosmetic-core/src/
│   ├── inject.rs inject/tests.rs   # 流式 `<head>` 扫描：carry / pending / 扫描上限 / 拼接（原 mitm_cosmetic_inject.go）
│   ├── host.rs host/tests.rs       # 主机名归一化、`net.SplitHostPort` 形状判定、`url.QueryEscape`、`<link>` 标签
│   ├── payload.rs                  # 文本载荷布局（`<link>` 标签与归一化主机）
│   ├── ffi.rs ffi/tests.rs         # new / free / pending / process / normalize_host / link_tag / free_bytes（ABI_VERSION）
│   └── tests/fixtures/*.tsv        # 迁移时 Go 原实现生成的注入对拍、主机归一化与 `<link>` 语料
├── diting-resolver-core/src/
│   ├── stats.rs stats/tests.rs     # SRTT/RTTVAR 估计、失败率 EWMA、连败惩罚、熔断与三种自适应延迟（原 resolver_stats.go）
│   ├── ffi.rs ffi/tests.rs         # new / free / record_* / allow_attempt / score / hedge / attempt / udp / 计数器（ABI_VERSION）
│   └── tests/fixtures/stats_trace.tsv  # 迁移时 Go 实现生成的 76 步操作轨迹（状态 + 派生值逐行对拍）
├── diting-dns-core/src/
│   ├── answer.rs                   # 空答案判定与唯一地址列表（原 isUpstreamBlockedMsg + resolvedAddressesMsg）
│   ├── block.rs block/tests.rs     # 按域名的窗口计数、NODATA→NXDOMAIN 升级与 4096 条上限（原 dynamicBlockTracker）
│   ├── payload.rs payload/tests.rs # 答案检查请求/回应与阻断判定的二进制布局
│   ├── ffi.rs ffi/tests.rs         # inspect_answer / blocks_new / reset / response / free / free_bytes（ABI_VERSION）
│   └── tests/fixtures/*.tsv        # 迁移时 Go 实现生成的 net.IP 文本、答案集与阻断升级语料（3 份）
├── diting-sniffer-core/src/
│   ├── tls.rs tls/tests.rs         # TLS 记录/握手/扩展长度走法与 SNI 取值（原 parseClientHelloSNI）
│   ├── http.rs http/tests.rs       # HTTP 方法门禁、`Host` 行走、字节级 TrimSpace 与 EqualFold（原 looksLikeHTTPRequest + parseHTTPHost）
│   ├── payload.rs payload/tests.rs # 分类结果的二进制布局（kind + 原始主机名字节）
│   ├── ffi.rs ffi/tests.rs         # classify / free_bytes（ABI_VERSION）
│   └── tests/fixtures/*.tsv        # 迁移时 Go 实现生成的 SNI 与 HTTP 语料（含全部前缀与字节腐蚀）
├── diting-ipcache-core/src/
│   ├── cache.rs cache/tests.rs     # 键表、最近写入顺序、原地更新、淘汰与默认容量（原 ip_domain_cache.go）
│   ├── ffi.rs ffi/tests.rs         # new / free / put / get / len（ABI_VERSION）
│   └── tests/fixtures/lru_trace.tsv  # 迁移时 Go 实现生成的 25 步 LRU 轨迹
├── diting-connlog-core/src/
│   ├── key.rs key/tests.rs         # connLogKey 的逐字节构造（原 connLogKey）
│   ├── dedup.rs dedup/tests.rs     # 8192 条键集合、溢出整表清空与 cleared 计数（原 connLogSeenDedup）
│   ├── payload.rs payload/tests.rs # 去重请求的二进制布局
│   ├── ffi.rs ffi/tests.rs         # new / free / mark / reset / size / cleared（ABI_VERSION）
│   └── tests/fixtures/*.tsv        # 迁移时 Go 实现生成的键语料与 7 步去重轨迹（2 份）
├── diting-allowlist-core/src/
│   ├── domain.rs domain/tests.rs   # 配置项/查询名归一化与逐级父域走法（原 SetAppAllowlist 归一化 + domainMatches）
│   ├── engine.rs engine/tests.rs   # 域名集合、按 UID 的 TTL 授权、应答按域名分发与 256 条剪枝（原 appAllowlist）
│   ├── payload.rs payload/tests.rs # 配置与应答授权的二进制布局
│   ├── ffi.rs ffi/tests.rs         # new / free / configure / has_uids / domain_allowed / connection_allowed / remember / grant_count（ABI_VERSION）
│   └── tests/fixtures/domain_matches.tsv  # 迁移时 Go 实现生成的 250 行域名走法语料
├── diting-bootstrap-core/src/
│   ├── health.rs health/tests.rs   # 端点健康：半衰期衰减、EWMA 延迟/抖动、连败惩罚与 30 秒冷却（原 bootstrapIPHealth）
│   ├── engine.rs engine/tests.rs   # 加权主端点 + 探索率 + 回退排序、一分钟主机缓存、健康表（原 choosePlan / healthMap / cache）
│   ├── payload.rs payload/tests.rs # 计划请求/回应与评分回应的二进制布局
│   ├── ffi.rs ffi/tests.rs         # new / free / reset / clear_cache / record_result / score / plan / cache_get / cache_put / health_count（ABI_VERSION）
│   └── tests/fixtures/health_trace.tsv  # 迁移时 Go 实现生成的 26 步健康轨迹
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
  `native_lib.go`（六个内核对共用的探测顺序与平台文件名）、
  `rule_matcher.go`（`RuleMatcher` 只剩句柄生命周期与结果翻译）、
  `parse_native.go`（解析请求编码、解析结果解码、正则编译）、
  `rule_parser.go`（`ParsedRule` 定义、两个入口、`buildWildcardRegex`）、
  `rule_engine*.go`（配置、加载、计划、统计不变）、
  `filter_native_test.go` / `parse_native_test.go`（载荷布局与失败路径）、
  `rule_parser_bench_test.go`（整份列表的端到端基准）。
- 桌面服务 Go（重写引擎 + 重写记录）：`rewrite.go`（`RewriteEngine` 只剩配置、快照换新与 `GetRules` 等生命周期）、
  `rewrite_lookup.go`（`Lookup*` 一次句柄调用 + PTR 记录构造）、
  `rewrite_engine_native.go`（引擎配置编码、警告/判定/PTR/反查回应解码）、
  `rewrite_native.go`（加载、单条记录请求编码、回应解码、`buildRewriteRR`）、
  `rewrite_action_native.go`（`$dnsrewrite` 解析与归一化键的请求编码、回应解码）、
  `rewrite_native_windows.go` / `rewrite_native_unix.go`（两个平台的加载器）、
  `rewrite_engine_native_test.go` / `rewrite_native_test.go` / `rewrite_action_native_test.go`（载荷布局与探测路径）、
  `rule_modifiers_rewrite.go`（只剩 `RewriteAction` 结构、`Records` 与展示文案）、
  `rewrite_records.go`（只剩 `RewriteRecord` 与应答码表）、
  `rewrite_test.go` / `rewrite_records_test.go` / `rule_modifiers_rewrite_test.go`（原有用例，现在全部穿过 FFI 跑）。
- 桌面服务 Go（声誉查询）：`safebrowsing.go`（`SafeBrowsingEngine` 只剩上游查询、超时、fail-open 取舍与计数）、
  `safebrowsing_native.go`（加载、计划载荷编码/解码、应答请求编码）、
  `safebrowsing_native_windows.go` / `safebrowsing_native_unix.go`（两个平台的加载器）、
  `safebrowsing_native_test.go`（计划载荷解码、应答请求编码与探测顺序）、
  `safebrowsing_test.go`（主机摘要、查询名、缓存、归因与失败路径，全部穿过 FFI 跑）。
- 桌面服务 Go（本地 hosts）：`hosts_resolver.go`（配置、TTL、source 列表热重载、地址到 `dns.RR`）、
  `hosts_native.go`（加载、source 列表编码、四类回应解码、`ParseIPFromArpa`）、
  `hosts_native_windows.go` / `hosts_native_unix.go`（两个平台的加载器）、
  `hosts_native_test.go`（四类载荷布局与探测顺序）、
  `hosts_resolver_test.go`（原有解析/查表/PTR 用例，另加热重载、配置替换与反向查询，全部穿过 FFI 跑）。
- 桌面服务 Go（DNS64）：`dns64.go`（配置、锁、`dns.AAAA` 构造、`EmbedIPv4InIPv6` 包装）、
  `dns64_native.go`（加载、前缀与地址载荷编码、合成结果解码、配置错误的分类）、
  `dns64_native_windows.go` / `dns64_native_unix.go`（两个平台的加载器）、
  `dns64_native_test.go`（载荷布局、配置错误文案、探测顺序）、
  `dns64_test.go`（原有 RFC 6052 前缀长度、多前缀、排除集与非法前缀用例，全部穿过 FFI 跑）。
- Go（DNS 缓存）：`dns_cache_native.go`（加载、ABI 校验、键构建）、
  `dns_cache_native_container.go`（句柄生命周期、四个载荷的编解码）、
  `dns_cache_native_stub.go`（无 cgo 时缓存不写入）、`dns_cache.go`（单飞、句柄 finalizer、
  开关标志与命中包装）、`dns_cache_snapshot.go`（快照的 JSON 投影）、
  `dns_cache_native_test.go`（配置编码与命中载荷解码的布局用例）。
- Go（MITM 过滤）：`mitm_filter_native.go`（加载、ABI 校验、判定报告解码）、
  `mitm_filter_native_stub.go`（无 cgo 时建不出句柄）、`mitm_filter.go`（只剩日志与句柄生命周期）、
  `mitm_filter_native_test.go`（报告载荷布局与坏载荷）、`mitm_filter_test.go`（白名单、排除规则、
  敏感主机、失败计数、黑名单与持久化文件，全部穿过 FFI 跑）。
- Go（装饰注入）：`mitm_cosmetic_native.go`（加载、ABI 校验、标签/归一化载荷、`pending` / `process` / 释放）、
  `mitm_cosmetic_native_stub.go`（无 cgo 时建不出句柄）、`mitm_cosmetic_payload.go`（文本载荷布局，
  不需要 cgo 就能测解码）、`mitm_cosmetic_inject.go`（规则载荷、`ShouldInjectHTML`、`io.ReadCloser` 包装）、
  `mitm_cosmetic_native_test.go`（载荷布局、探测路径与原有注入用例）、
  `mitm_cosmetic_payload_test.go`（无 cgo 也能跑的载荷解码用例）。
- Go（DNS 应答与阻断升级）：`dns_core_payload.go`（答案检查请求编码与报告解码，不需要 cgo 就能测）、
  `dns_core_native.go`（加载、ABI 校验、`time.Duration` 换算）、`dns_core_native_stub.go`（无 cgo 时
  两项功能降级）、`dns_response_helpers.go`（`dns.Msg` 遍历、`dns.RR` 构造与 `ipDomainCache` 回填）、
  `dns_blocks.go`（`dynamicBlockTracker` 只剩句柄）、`dns_core_payload_test.go`（两侧布局）、
  `engine_block_response_test.go`（阻断模式与动态升级，全部穿过 FFI 跑）。
- Go（解析器统计）：`resolver_stats.go`（`providerStats` 只剩句柄、四处 `time.Now()`、`time.Duration` 换算与
  冷启动回退）、`resolver_stats_native.go`（加载、ABI 校验、十三个符号的调用包装）、
  `resolver_stats_native_stub.go`（无 cgo 时全部冷启动）；原有用例
  （`resolver_test.go` 的 EWMA 用例、`resolver_smart_test.go` 的三条统计用例与四条调度用例）全部穿过 FFI 跑。
- Go（流嗅探）：`mitm_sniffer.go`（只剩一次 peek `Read`、回放 reader 与 `intToStr`）、
  `mitm_sniffer_native.go`（加载、ABI 校验、`classifyFlow` 调用与载荷解码）、
  `mitm_sniffer_native_stub.go`（无 cgo 时 MITM 启动失败、直连回退无主机名提示）、
  `mitm_sniffer_payload.go`（分类载荷布局，不需要 cgo 就能测）、
  `mitm_sniffer_native_test.go`（三类流、截断记录与字节级 `EqualFold` 用例）、
  `mitm_sniffer_payload_test.go`（无 cgo 也能跑的载荷解码用例）。
- Go（IP→域名缓存）：`ip_domain_cache.go`（只剩句柄生命周期与空缓存回退）、
  `ipcache_native.go`（加载、ABI 校验、读回域的缓冲与五个符号的调用包装）、
  `ipcache_native_stub.go`（无 cgo 时提示停用）、`ip_domain_cache_test.go`（更新、读不提升、
  淘汰、空键与无内核回退，全部穿过 FFI 跑）。
- Go（连接日志去重）：`engine_connection_log.go`（flow → app/dest 推导、日志文本与回调）、
  `connlog_native.go`（加载、ABI 校验、去重载荷编码与六个符号的调用包装）、
  `connlog_native_stub.go`（无 cgo 时不去重）、`connlog_seen_test.go`（有界集合、溢出计数与
  前缀/原因键，全部穿过 FFI 跑）。
- Go（应用白名单）：`engine_app_allowlist.go`（JSON 配置、`dns.Msg` 遍历、环回快路径与日志）、
  `allowlist_native.go`（加载、ABI 校验、两套载荷编码与八个符号的调用包装）、
  `allowlist_native_stub.go`（无 cgo 时被选中 UID fail-closed）、`engine_app_allowlist_test.go`
  （原有缓存命中/陈旧/负答案/TTL 用例，现在全部穿过 FFI 跑，另加无内核 fail-closed 与配置解析用例）。
- Go（引导解析）：`bootstrap_resolver.go`（JSON 配置、UDP 查询、日志回调与 `net.IP` 直通）、
  `bootstrap_native.go`（加载、ABI 校验、计划载荷编码/解码与十一个符号的调用包装）、
  `bootstrap_native_stub.go`（无 cgo 时引导解析停用）、`bootstrap_resolver_test.go`
  （原有健康、分布与解析用例，现在全部穿过 FFI 跑）。
- Go：`policy_native.go`（`dlopen`、ABI 校验、`evaluate` / `evaluateUncached` / `prewarm`、句柄释放）、
  `policy_snapshot.go`（快照与一次调用入口）、`policy_engine.go`（构建与原子换新）、
  `policy_native_test.go`（固定用例 + 应用基准）。

## 构建与启用

```bash
cd rust && cargo build --release        # 本机：供 flutter test、go test、基准使用（工作区全部 crate）
python rust/build_android.py            # Android：十二个 .so，arm64-v8a / x86_64 交叉编译并拷入 jniLibs
```

DNS 缓存内核（容器 + wire）、MITM 过滤内核、装饰注入内核、解析器统计内核、DNS 应答内核、流嗅探内核、
引导解析内核、应用白名单内核、连接日志去重内核与 IP→域名缓存内核只随 Android APK 交付（桌面服务
没有这十块），由 `build_android.py` 与另外两个 `.so` 一起拷入 `jniLibs`。

桌面服务的六个内核按平台单独交付（Android 用不到它们）：

- Windows：`cargo build --release -p diting-stamp-core -p diting-filter-core -p diting-rewrite-core
  -p diting-safebrowsing-core -p diting-hosts-core -p diting-dns64-core` 产出
  `diting_stamp_core.dll`、`diting_filter_core.dll`、`diting_rewrite_core.dll`、
  `diting_safebrowsing_core.dll`、`diting_hosts_core.dll` 与 `diting_dns64_core.dll`，
  `build_manager.py` 在打 EXE 时各编一次，NSIS 把六个都装到 `diting-service.exe` 同目录；
- Linux：`build_linux.sh` 按目标架构编/复用 `libditing_stamp_core.so`、
  `libditing_filter_core.so`、`libditing_rewrite_core.so`、`libditing_safebrowsing_core.so`、
  `libditing_hosts_core.so` 与 `libditing_dns64_core.so`，装到 `/usr/lib/diting/`；
- 探测顺序（六个内核相同）：`DITING_STAMP_CORE_LIB` / `DITING_FILTER_CORE_LIB` /
  `DITING_REWRITE_CORE_LIB` / `DITING_SAFEBROWSING_CORE_LIB` / `DITING_HOSTS_CORE_LIB` /
  `DITING_DNS64_CORE_LIB` → 可执行文件同目录 → `/usr/lib/diting`、`/usr/local/lib/diting` →
  `rust/target/{release,debug}/`（`go test` 用）。

没有 `.so` 就是错误，而不是“功能不变地慢一点”：

- Dart 侧首次导入抛 `StateError`（`DITING_RULE_CORE_LIB` 可指定显式路径，否则按打包名 →
  `rust/target/{release,debug}/` 探测）；
- Kotlin 侧 `System.loadLibrary("diting_rule_core")` 失败即抛 `IllegalStateException`；
- Go 侧 `ApplyRuleSnapshot` 返回错误，`EngineRuleLoader` / 独立 DNS 服务把它当作启动失败，
  不会以“过滤静默关闭”的状态起隧道；
- Go 侧 DNS 缓存内核缺失时建不出缓存句柄：`put` 拒绝写入、每次查询都 miss，引擎照常直连解析器，
  回答不变，只是不再复用；加载失败会写一条日志，不会静默切换成另一套 TTL/ID 语义；
- Go 侧解析器统计内核缺失时每个上游都按冷启动取值参与调度（默认评分、冷启动的 hedge / 单次超时 /
  UDP 重试、每次尝试都放行），回答不变，只是不再自适应；加载失败会写一条日志；
- Go 侧 DNS 应答内核缺失时上游空答案按普通应答记日志（不再计入 `upstream_dns`），动态升级关闭，
  每个阻断沿用配置的应答模式；回答不变，加载失败会写一条日志；
- 桌面服务侧 `ParseServerStamp` 返回错误，上游配置构建随之失败，不会退化成“印章当作普通地址”；
  `RuleMatcher.BuildFromRules` 返回错误，规则引擎重建随之失败，不会退化成“规则静默不生效”；
  `buildRewriteRR` 返回错误，重写规则编译失败（自定义规则丢掉那一条，`$dnsrewrite` 丢掉整条规则），
  不会退化成“配了却不生效的记录”；
  `NewRewriteEngine` / `Configure` / `AddRule` / `DeleteRule` 返回错误，服务启动或配置变更失败，
  不会以“重写规则静默不生效”的空引擎继续跑；
  `NewSafeBrowsingEngine` 返回错误，服务启动失败，不会以“声誉查询显示已开启、实际什么都没查”的状态跑；
  `NewHostsResolver` 返回错误，服务启动失败，不会以“内网域名当作公网域名转发出去”的空解析器继续跑；
  `NewDNS64Synthesizer` 返回错误，服务启动失败，不会以“开关显示已开启、实际不合成”的状态跑
  （前缀写错不算：那是配置错误，只记警告，与迁移前一致）。

重写引擎的调用约定：

- 每份配置一个句柄：`engine_build` 一次编完索引、PTR 映射与显式记录，Go 把它藏在写锁后面；
- 查询一次 `engine_lookup`：内核做归一化、精确/泛域名匹配、七级记录选择、CNAME 链与属主合并，
  回传 `(matched, rcode, 记录列表)`，Go 只把字段填进 `dns.RR`；
- PTR 与反向查询传 4/16 字节地址而不是文本：PTR 映射的键是地址字节，两侧不必对 IPv6 的规范文本
  取得一致；
- 配置变更重建句柄并在写锁内换新，旧句柄随后释放；重建失败时旧句柄与原配置完全保留。

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
          ──> Go 编译正则/通配源 ──> []*ParsedRule ──> filter_build
          rewrite 原文 ──parse_action──> Rust 切分/校验 ──> (bare, rcode, rrtype, value)
          ──> filter_build 时再调 action_key 取归一化键

重写记录：RewriteRecord{type, value} ──build_record(名称, qtype, ttl)──> Rust 解析/校验/限定类型
          ──> 二进制载荷（类型号 + 字段）──> Go 填 dns.RR → dns.Msg 应答
          自定义重写规则（编译期与查询期）与 $dnsrewrite 修饰符走同一条入口

重写引擎：RewriteConfig{RewriteRule[]} ──engine_build──> Rust 建精确/泛域名索引 + PTR + 编译显式记录
          ──> 句柄 ──> Go 原子换新（旧句柄在写锁内释放）
          查询 ──engine_lookup(句柄, 域名, qtype)──> 归一化 ──> 规则匹配 ──> rcode/CNAME 链/属主合并
                                                    ──> 记录列表 ──> Go 填 dns.RR
          PTR ──engine_ptr_lookup(句柄, 4/16 字节地址)──> []域名 ──> Go 填 dns.PTR
          PTR ──engine_reverse_lookup(句柄, 4/16 字节地址)──> 首个域名

缓存：配置 JSON ──dns_cache_new──> Rust 归一化配置 + 分片表 + 清扫线程 ──> 句柄
      响应字节 ──dns_cache_put──> Rust 按 wire 取值（最小 TTL、TTL 偏移、链目标、A/AAAA）
                ──> TTL 策略 ──> 条目（保留上游 wire 原文）
      查询 ──dns_cache_get──> 缓存键 ──> 分片查找 ──命中──> 改写 ID/剩余 TTL ──> (wire, 链目标, IP)
      陈旧 ──dns_cache_get（stale）──> 1 秒 TTL 的改写副本 ──> Go 单飞后台刷新
            ──refresh_begin / refresh_done──> 每个条目同时只允许一个刷新
      UI ──dns_cache_stats / dns_cache_snapshot──> 计数与最热条目

MITM 过滤：白名单 CSV / 排除规则文本 ──set_allowed_uids / set_bypass_rules──> Rust 归一化并保存
          连接 ──allows_interception(域名, now_ms)──> 黑名单（过期即清）──> 排除规则 ──> 敏感主机/地址
                                                    ──> 1 拦截 / 0 直连
          握手失败 ──record_failure(域名, 错误文本, now_ms)──> 失败计数（10 分钟窗口）
                    ──达到阈值（3 次，证书被拒 2 次）──> 黑名单 7 天 + 追加文件行
                    ──回传（计数/阈值/主机/原因/写入错误）──> Go 写日志
          启动 ──load_persistent(路径, now_ms)──> Rust 读文件、丢弃过期行、记住路径

本地 hosts：配置 ──diting_hosts_new（source 列表：系统路径 + 自定义文件 + 内联文本）──> Rust 读文件建表
          查询 ──diting_hosts_lookup(域名, qtype)──> 归一化 ──> 4/16 字节地址列表 ──> Go 填 dns.A / dns.AAAA
          权威 NODATA ──diting_hosts_contains(域名)──> 1 / 0
          反查 ──diting_hosts_ptr(反查名)──> 别名列表（文件顺序）──> Go 填 dns.PTR
          客户端归属 ──diting_hosts_reverse(4/16 字节地址)──> 首选别名
          反查名解析 ──diting_hosts_parse_arpa(名字)──> 地址（hosts 与重写引擎共用）

DNS64：配置 ──diting_dns64_new(enabled, 前缀文本列表)──> Rust 校验 RFC 6052 长度并建排除集
       合成 ──diting_dns64_synthesize(4 字节地址)──> 每个前缀一条 16 字节地址 ──> Go 构造 dns.AAAA
       有效判定 ──diting_dns64_has_valid(地址列表)──> 1 / 0
       排除判定 ──diting_dns64_excluded(宽度 + 字节)──> 1 / 0
       单前缀嵌入 ──diting_dns64_embed_net(16 字节前缀, 掩码长度, 4 字节)──> 16 字节（`EmbedIPv4InIPv6`）

装饰注入：规则 JSON ──SetCosmeticRules──> Go 全局（内核不需要它，样式表由 Go 侧编译）
          响应 ──diting_cosmetic_link_tag(页面主机, 资产主机)──> `<link>` 标签载荷 ──> diting_cosmetic_new(标签)
                ──> 句柄（carry / pending / 扫描计数各自独立）
          读取 ──diting_cosmetic_pending(缓冲区)──> 上次没放下或压在 carry 的字节
               ──diting_cosmetic_process(缓冲区, n, 上游标志)──> 原地改写 + 本次该回多少个字节
                      ──> 上游错误是否随这一次一起返回（队列没排空就先返回 nil）
          样式表 ──diting_cosmetic_normalize_host(`?h=` 值)──> 与注入时同一个归一化主机

解析器统计：上游返回 ──diting_resolver_record_success(rtt, now)──> 折入 SRTT/RTTVAR、清零熔断
          失败/策略拒绝 ──record_failure / record_policy_failure(now)──> 失败率与连败计数 ──> 熔断
          并发落败 ──record_censored(elapsed)──> 作为下界 RTT 样本（不计失败）
          调度 ──diting_resolver_score(now)──> rankProviders 排序 ──> smart_prediction / parallel_race 的候选顺序
          primary_backup ──allow_attempt(now)──> 跳过熔断中的上游，冷却到期只放行一个半开探针
          延迟 ──hedge_delay / attempt_timeout / udp_retry_delay──> 内核回传纳秒，Go 转 time.Duration

DNS 应答：上游应答 ──inspect_answer(记录列表)──> Rust 逐条判定空地址 / 回环 ──> (blocked, 唯一地址文本)
          阻断 ──blocks_response(域名, 窗口, 阈值, 冷却, 配置模式, now_ns)──> NODATA / NXDOMAIN / 配置模式
          ApplyDNSConfig ──blocks_reset──> 清空所有域名计数

引导解析：解析请求（主机名）──diting_bootstrap_cache_get(主机, now_ns)──> 命中即返回地址
          未命中 ──Go 组装 (id, weight) 列表 + now_ns + 三档随机数──>
              ──diting_bootstrap_plan(载荷)──> Rust 衰减健康 ──> 冷却过滤 ──> 探索率 ──> 加权主端点
                    ──> 回退按权重降序（稳定）──> Go 逐个 UDP 查询
          每次尝试 ──diting_bootstrap_record_result(id, success, elapsed_ms, now_ns)──> 健康折叠
          成功 ──diting_bootstrap_cache_put(主机, 地址, now_ns)──> 60 秒缓存
          配置变更 ──diting_bootstrap_clear_cache──> 保留健康；ResetStats ──diting_bootstrap_reset──> 清健康与缓存
          观察 ──diting_bootstrap_score(id, 配置权重, now_ns)──> (weight, cooling, sample_count)

应用白名单：配置 JSON ──Go 解析 uid/域名原文──> diting_allowlist_configure(载荷)
                ──> Rust 归一化并建集合 ──> 清空全部 IP 授权
          查询 ──diting_allowlist_domain_allowed(uid, 域名)──> 未选中 UID 放行；选中 UID 走逐级父域
          连接 ──diting_allowlist_connection_allowed(uid, 地址, now_ns)──> 环回放行 / 未选中放行 / 查 TTL 授权
          应答 ──Go 遍历 A/AAAA（To4 / To16 + TTL）──> diting_allowlist_remember(uid, 原始问题名, 记录, now_ns)
                ──> Rust 归一化问题名 ──> 找到所有匹配 UID（空问题只用归属 UID）
                ──> 过滤零 TTL/未指定地址 ──> 写入授权 ──> 超过 256 条时清理已过期项
          配置变更 ──diting_allowlist_configure──> 域名集合与授权整体换新

连接日志去重：flow ──Go 推导 app / dest / port / protocol / reason──>
              ──diting_connlog_mark(载荷)──> Rust 拼 `connLogKey` ──> 命中即丢弃
              ──> 未命中则写入集合；满 8192 条时先整表清空再写入（cleared 加一）
          新会话 ──diting_connlog_reset──> 清集合、保留 cleared
          观察 ──diting_connlog_size / diting_connlog_cleared──> 计数

IP→域名缓存：上游应答 ──Go 取 A/AAAA 文本 + 归一化域名──> diting_ipcache_put(IP, 域名)
              ──> Rust 原地更新并移到最近写入位置；新键在满容量时淘汰最久未写入项
          直连 IP 流 ──diting_ipcache_get(IP)──> 域名（读不提升）──> MITM 直通的主机名提示

声誉查询：配置 ──diting_sb_new / diting_sb_configure──> Rust 建两份前缀缓存（恶意网址库 / 家长控制）
          查询 ──diting_sb_plan(服务, 域名, now_ms)──> Rust 归一化+校验 ──> 各级父域 SHA-256
                                    ──> 前缀查缓存（未命中则回传查询名）──> Go 发 TXT 查询
               应答 ──diting_sb_apply(服务, 待查摘要, TXT 文本, now_ms)──> 校验 64 位十六进制
                    ──> 写入缓存 ──> 1 拦截 / 0 放行
```

布局与语义的权威注释在 `diting-rule-core/src/ffi.rs`、`search_ffi.rs`、`dtri.rs` 与
`diting-policy-core/src/ffi.rs`、`snapshot.rs`、`diting-dns-cache-core/src/{wire,policy,cache,payload,ffi}.rs`、
`diting-mitm-core/src/{pattern,filter,payload,ffi}.rs`、
`diting-filter-core/src/ffi.rs`、`parse.rs`、`diting-rewrite-core/src/{action,record,engine,payload,ffi}.rs`、
`diting-safebrowsing-core/src/{hash,cache,engine,payload,ffi}.rs` 与
`diting-hosts-core/src/{ip,arpa,hosts,payload,ffi}.rs` 与
`diting-dns64-core/src/{addr,prefix,engine,payload,ffi}.rs` 与
`diting-cosmetic-core/src/{inject,host,payload,ffi}.rs`、`diting-resolver-core/src/{stats,ffi}.rs`、`diting-dns-core/src/{answer,block,payload,ffi}.rs`、
`diting-sniffer-core/src/{tls,http,payload,ffi}.rs`、
`diting-bootstrap-core/src/{health,engine,payload,ffi}.rs`、
`diting-allowlist-core/src/{domain,engine,payload,ffi}.rs`、
`diting-connlog-core/src/{key,dedup,payload,ffi}.rs`、
`diting-ipcache-core/src/{cache,ffi}.rs` 与
`diting-go-compat/src/ip.rs` 顶部；
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

**重写记录（桌面服务）**：`rewrite_test.go` / `rewrite_records_test.go` 的断言一条没改，现在全部
穿过 FFI 取得记录；只有两个只测已删函数的用例跟着搬走了（`TestParseSVCBParams` 的参数语料进了
`record/tests.rs`，`RewriteRecordTypes` 改为向内核取值并断言完全一致的升序列表）。`record/tests.rs`
逐条钉住原 `buildRewriteRR` 的分支：MX/SRV 字段切分、目标域名与 `dns.Fqdn`、A/AAAA 的 IPv4 判定
（含 `::ffff:` 映射与 "IPv4 字面量不能变成 AAAA"）、TXT 的空白拒绝、HTTPS/SVCB 的全部参数
（含逗号列表、单地址 hint、ech 的 Base64、`mandatory` 的键表、引号取值）、类型不匹配返回
“无记录”而 CNAME 对任何查询类型都返回；`ffi/tests.rs` 钉住请求/回应载荷布局、拒绝消息与坏参数；
`rewrite_native_test.go` 另钉住 Go 侧的编码与解码（回应用布局、尾随字节、截断、未知类型号、
未知参数键）与探测顺序。

**`$dnsrewrite` 取值（桌面服务）**：`rule_modifiers_rewrite_test.go` 的 AdGuard 语法、非法取值、
记录构造与例外取消断言一条没改，现在全部穿过 FFI 跑：解析落到 `action.rs`，记录落到 `record.rs`。
`action/tests.rs` 逐条钉住原 `parseDNSRewriteModifier` 的分支（关键字大小写、显式/简写、`NOERROR;;`、
只切前两个分号、`::ffff:` 折叠、非法地址/域名/类型/应答码），并把 `RewriteAction.key()` 的归一化
搬过来（地址规范文本、目标名小写去尾点、其它取值去空白、裸形式为 `bare`）；
`rewrite_action_native_test.go` 钉住 Go 侧两条编解码布局与坏载荷，另加两条端到端用例证明等价写法
（`::ffff:127.0.0.1` vs `127.0.0.1`、`TARGET.Test.` vs `target.test`）的例外规则确实互相取消。

**重写引擎（桌面服务）**：`engine/tests.rs` 逐条复刻原 `rewrite.go` / `rewrite_lookup.go` 的行为：
精确与泛域名、最长后缀优先与同长按配置顺序、精确同名后写覆盖、PTR 多别名与精确规则限定、
rcode 覆盖与未知名字回落、CNAME 链 / 循环 / 深度上限、快捷 TXT 多字符串、显式记录的类型过滤与
属主 CNAME 合并；`engine/tests.rs` 同时钉住构建警告（非法记录、未知 rcode）。`ffi/tests.rs` 钉住
引擎句柄的构建 / 判定 / PTR / 反查 / 释放往返与坏参数；`rewrite_engine_native_test.go` 钉住 Go 侧的
配置编码与三类回应解码（布局、尾随字节、未知标志）。原 `rewrite_test.go` / `rewrite_records_test.go`
一条断言未改，现在全部穿过 FFI 跑。

**声誉查询（桌面服务）**：`hash/tests.rs` 的 `hash_corpus.tsv` 是迁移时直接跑原 Go 实现（`normalizeCheckHost`
+ `hostnameToHashes` + `buildHashQuestion`）生成的：60 余行主机名逐行断言「归一化结果 + 完整摘要集合 +
查询名」，覆盖大小写、首尾点、转义标签、超长标签与超长名字、私有后缀、wildcard 后缀（`*.ck`）、
未知 TLD 与非 ASCII。`cache/tests.rs` 用注入的 `now_ms` 逐条钉住原 `hashCache` 的行为（前缀去重、
负结果入缓存、死线严格比较、LRU 淘汰与写入刷新死线）；`engine/tests.rs` 钉住两个服务互不共享、
未知服务号被拒与「有效期变化整份重建」的规则；`ffi/tests.rs` 钉住句柄往返、跳过、坏载荷状态与
空句柄。Go 侧的原有用例一条断言未改，现在全部穿过 FFI 跑：白盒用例（摘要数、eTLD+1、截断、查询名、
缓存容量与重建）改为读内核回传的计划与「是否重新外发查询」，行为断言保持不变。

**本地 hosts（桌面服务）**：`tests/fixtures/expectations.tsv` 是迁移时直接跑原 Go 实现生成的：地址字段
（含 zone、IPv4 映射、前导零、带空格的边界）的接受/拒绝与规范化字节、反查名的解析结果、三份 hosts
文档上的 `HasDomain` / `Lookup(A/AAAA)` / `LookupPTR` 逐条断言，文件里还留了一条超过 64 KiB 的行来钉住
`bufio.Scanner` 的截断行为。`ip/tests.rs`、`arpa/tests.rs`、`hosts/tests.rs` 逐分支复刻原实现的
条件（注释剥离、Unicode 字段切分、`strings.ToLower` 对 `U+0130` 的折叠、重复条目去重与顺序、
接口 zone 截断）；`ffi/tests.rs` 钉住句柄往返、空表、空句柄与坏参数；`hosts_native_test.go` 钉住
Go 侧四类载荷的布局与探测顺序。原 `hosts_resolver_test.go` 的断言一条未改，现在全部穿过 FFI 跑，
另加了三组只属于新边界的行为用例（热重载重读、配置整体替换、地址反查）。

**DNS64（桌面服务）**：五份语料都是迁移时直接跑原 Go 实现生成的：`prefixes.tsv` 把 55 个前缀写法
（六种合法长度、主机位非零、前导零掩码、`+96`/`-1`/`9 6`/`96/96`、IPv4 网段、zone、全空白）钉成
`ok:<ones>:<掩码后 16 字节>` / `parse` / `length` / `skip`；`embed.tsv`、`excluded.tsv`、
`has_valid.tsv`、`synth.tsv` 把六种前缀长度下的嵌入字节、默认排除集的判定、有效 AAAA 的组合与
多前缀的合成顺序逐条固定下来。`addr/tests.rs`、`prefix/tests.rs`、`engine/tests.rs` 复刻
`netip.ParseAddr` 与 `dtoi` 的分支，`ffi/tests.rs` 钉住状态码（0/1/2/3/4）、索引回传与空句柄；
`dns64_native_test.go` 钉住 Go 侧三类载荷的布局、配置错误的原文与探测顺序。原 `dns64_test.go` 的
断言一条未改。

**策略内核**：`tests/policy_core.rs` 把 DTRI fixtures 喂给快照，断言每个可索引规则解析到语料声明的
source、禁用规则回落到父后缀；`ffi.rs` 的单测钉住构建 / 判定 / 释放往返与错误上报，以及归一化、
缓存命中与未命中答案一致、换新 prewarm；`cache.rs` 的单测钉住维度折叠、CLOCK 淘汰（热键存活）与
热键排序；`android/engine/policy_native_test.go` 用固定快照覆盖各规则族，并在 Go 侧逐条对比
`evaluate` 与 `evaluate_uncached`。

**DNS 缓存容器**：`cache/tests.rs` 逐条复刻原 `dns_cache_test.go` / `dns_cache_snapshot_test.go` 与
`dns_low_regression_test.go` 里那条 LRU 孤儿用例的行为：ID/TTL 改写、TTL 上限 / 固定 / 最小、
陈旧回退的一秒 TTL、负缓存、惰性过期不计淘汰、清扫只回收过期条目、`clear` 之后分片仍可用、
按分片淘汰最久未晋升的条目、单飞复检不计命中/未命中、关闭开关即释放条目、快照按命中数排序并过滤
过期条目。`policy/tests.rs` 钉住 `normalizeDNSCacheConfig` 的默认值与 `calculateEffectiveTTL` /
`calculateNegativeTTL` 的每个分支。Go 侧原有用例除两条只测已删内部结构的（`getEntry` 改时间、
`shard` 的 LRU 孤儿）以外一条未改，现在全部穿过 FFI 跑；那两条的断言搬进 Rust 单测。

**MITM 过滤**：三份 fixture 是迁移时把原 Go 函数跑出来的结果固化的文件——`pattern/tests.rs` 的
2964 行 `path.Match` 语料（`ok` / `no` / `bad`）、2765 行 `matchHostPattern` 语料（含 `@@`、`||`、
尾 `^` 与大小写），`sensitive/tests.rs` 的 73 行敏感主机与地址语料。时间相关分支不靠 fixture：
`filter/tests.rs` 注入 `now_ms`，逐条钉住黑名单过期、十分钟失败窗口（含“恰好一个窗口仍计数”
与“多一毫秒重新开始”）、两种阈值、持久化文件的读/写/过期过滤与 `clear` 截断。
`android/engine/mitm_filter_test.go` 另从 Go 侧走一遍白名单、排除规则、敏感主机、失败计数、
黑名单与持久化文件；`mitm_filter_native_test.go` 钉住报告载荷布局与两类坏载荷。

**DNS 应答检查与阻断升级**：三份语料都是迁移时直接跑原 Go 实现生成的：`ip_string.tsv` 有 102 行
（`net.IP.String()` 的 4/16 字节、IPv4 映射、零段压缩与并列取舍、奇数长度 `?hex`、空地址 `<nil>`、
固定种子的伪随机 16 字节），`answers.tsv` 有 25 组答案集（空 / 仅 CNAME / 单个空地址 / 回环 / 混合 /
重复地址 / `::` 在 A 记录里不算 IPv4zero / 整段为空的判定），`blocks_trace.tsv` 是 25 步脚本化时钟下
的升级轨迹（窗口内计数、阈值边界、NXDOMAIN 冷却、冷却到期后重新升级、窗口重置、阈值为 0、窗口为 0、
禁用时透传）。`tests/corpus.rs` 逐行重放并断言完全相等；`block/tests.rs` 另钉住 4096 条上限、时钟
回拨与「禁用不记状态」，`payload/tests.rs` 与 `ffi/tests.rs` 钉住布局、坏载荷与空句柄。
Go 侧原有断言（阻断模式、动态升级、`nil` 引擎默认值、拒绝快照不发布）一条未改，现在全部穿过 FFI 跑，
另加 `dns_core_payload_test.go` 的布局用例。

**TLS / 明文 HTTP 流嗅探**：两份语料是迁移时直接跑原 Go 实现生成的：`sni.tsv` 覆盖正常/大写/长
主机名、无 SNI、非 host_name 条目、多条目、扩展顺序、记录/扩展/session 长度越界，另加一份合法
握手从 0 到整长的每一条前缀与 16 处字节腐蚀；`http.tsv` 覆盖方法门禁的 16 字节边界、大小写与
`ſ` 折叠、空值与带端口的 `Host`、只认 CRLF、非法 UTF-8 名称/取值，另加一份完整请求的每一条前缀。
`tests/corpus.rs` 逐行重放并断言完全相等；`tls/tests.rs` 与 `http/tests.rs` 另钉住夹具没走到
的分支（越界 session 长度、空 SNI、`::1` 取值的首个冒号截断、`TrimSpace` 的字节保留）。
Go 侧原有断言一条未改，现在全部穿过 FFI 跑，另加 `mitm_sniffer_payload_test.go` 的布局用例。

**IP→域名缓存**：`tests/fixtures/lru_trace.tsv` 是迁移时直接跑原 Go 实现生成的 25 步轨迹（容量 3）：
原地更新、`get` 不提升、淘汰的是最久未写入项而不是最久未读项、同值重复 put 也算一次触碰、空 IP/空域
被忽略，每行同时记录查表结果与当前条数。`tests/corpus.rs` 逐行重放；`cache/tests.rs` 另钉住容量 1、
非正容量回退 2048（插满 2048 条再插一条后仍为 2048 且最旧项被淘汰）与 Unicode 域。Go 侧新增
`ip_domain_cache_test.go`，把边界行为全部穿过 FFI 跑，并钉住无内核时的空缓存回退。

**连接日志去重**：两份语料都是迁移时直接跑原 Go 实现生成的：`keys.tsv` 有 7 行，覆盖空字段、
Unicode、字段内部含 `|`、负数端口与协议，逐字节比对 `connLogKey`；`dedup_trace.tsv` 是 7 步轨迹
（首次、重复、blocked 前缀 + 原因、空字段键、reset），逐行断言 `dup` / `size` / `cleared`。
`dedup/tests.rs` 另钉住 8192 条上限：满表时重复键不清表，下一个新键先整表清空再插入、`cleared`
加一，`reset` 只清集合不清计数。Go 侧原有断言一条未改，现在全部穿过 FFI 跑；键格式用例已由
`keys.tsv` 取代，白盒的 `cleared` 读取换成内核的 `clearedCount`。

**应用白名单**：`tests/fixtures/domain_matches.tsv` 是迁移时直接跑原 Go `domainMatches` 生成的
250 行语料（10 组允许集合 × 25 条查询）：精确命中、标签边界、父域项、一个与两个尾点、ASCII 大小写、
`U+0130` 的 Go 折叠、查询两侧空白（走法不裁剪）与空查询。`tests/corpus.rs` 逐行重放并断言相等；
`domain/tests.rs` 钉住配置项的“裁剪 → 小写 → 去一个尾点”与查询名的“只小写 + 去一个尾点”两种不同
归一化；`engine/tests.rs` 钉住选中 UID 的空集合、未选中 UID 放行、环回豁免、TTL 到期边界、
零 TTL/未指定地址/`::ffff:0.0.0.0` 不授权、空问题只授权归属 UID、重复配置项后写生效、
重配清空授权与 256 条剪枝。Go 侧原有断言一条未改，现在全部穿过 FFI 跑；只有两处白盒读取换成了
内核的 `grantCount` 与假时钟。

**引导解析评分**：`tests/fixtures/health_trace.tsv` 是迁移时直接跑原 Go 实现生成的 26 步健康轨迹
（连续成功压低 EWMA、三连败触发冷却、冷却严格的到期边界、成功清冷却、31 分钟与 2 小时后的半衰期
衰减、0 与负数耗时钳到 1 ms），每行同时记录完整状态与评分三件套；`tests/corpus.rs` 逐行重放并
以 1e-9 容差断言（`powf` 在不同 libm 上可能差最后一位）。`engine/tests.rs` 另钉住加权抽取、
探索索引、全冷却回退、重复 id 不进回退、排序稳定性与缓存的一分钟边界。
Go 侧原有用例一条断言未改，现在全部穿过 FFI 跑；健康白盒读取改成内核的 `score` / `health_count`。

**解析器统计**：`tests/fixtures/stats_trace.tsv` 是迁移时直接跑原 Go 实现生成的 76 步操作轨迹（三份
脚本：EWMA 截断与熔断升级、两端钳位、冷启动下游标样本），每行同时记录完整状态（SRTT / RTTVAR /
失败率的二进制位 / 连败次数 / 三个时间戳 / 熔断死线 / 半开探针）与四个派生值；`tests/corpus.rs`
逐行重放并断言完全相等。`stats/tests.rs` 另钉住夹具没有走到的两端钳位、权重下限与冷却上限。
Go 侧原有用例一条断言未改，现在全部穿过 FFI 跑；只有两处白盒读取从字段改成方法
（`sampleCount()` / `failureCount()`），因为状态已在核内。

## DNS 缓存内核的已知边界

- **缓存键格式**：`name:qtype:qclass`，ASCII 小写、标签用 `.` 连接、无尾点，压缩指针最多 64 跳；
  与旧 `appendQuestionKey` 逐字节相同（`question_key` 同时回传各段，Go 不再反向解析键）。键长超过
  Go 侧 268 字节缓冲区的畸形问题会被拒绝；旧实现会临时扩容，但这类响应过不了名称 255 字节上限，本来
  也永远不会命中。
- **名称解码**：与 miekg/dns `UnpackDomainName` 相同——`.`、空格、引号、括号等加反斜杠，非可打印
  字节写成 `\DDD`，根名是 `.`。链目标要参与规则匹配，所以这里不能“简化”。
- **按旧解包器的接受面复刻**：空 rdata（`noRdata`）、消息在记录边界结束但头部还声明更多记录、
  SOA 在字段边界结束时剩余字段为 0，都按旧 `dns.Msg.Unpack` 的行为接受，缓存内容与迁移前一致。
- **两类放宽/收紧只涉及畸形报文**：未读取类型的 rdata 只按 `rdLength` 跳过（旧实现逐类型校验），
  因此少数畸形 MX/TXT 会被缓存而旧实现丢弃；问题段被截断的响应不再缓存（旧 `unpackQuestion`
  会吞掉 qclass 截断错误并返回 `qclass=0`）。合法响应的路径完全一致。
- **缓存条目不再持有 `dns.Msg`**：解析器仍解包一次用于校验，缓存按 wire 取值；命中时一次分片查找
  加一次 `patch_response`（拷贝 + 改 ID/TTL），上游原文保留在 `entry.wire` 里供后续命中复用。
- **单飞仍在 Go**：它要在临界区里调用 Go 的解析回调，搬进 Rust 只能靠回调指针，收益不抵风险；
  它不持有缓存状态，复检与写入都经句柄，所以「每个客户端查询只计一次」的语义与迁移前相同。
- **命中路径的载荷**：命中也过一次 FFI 与一次载荷编解码（wire + 链目标 + IP 列表）。本机
  `BenchmarkDNSCacheGetFast_Hit` 从约 0.62 µs / 3 次分配变成约 1.6 µs / 7 次分配；相对一次真实
  上游解析（毫秒级）可以忽略，但确实是这一轮唯一的净开销。`后续可做`里列了去掉多余拷贝的办法。
- **时间源**：截止时间用 `Instant`（单调时钟）判断，`created/expires/lastHit` 另存墙钟毫秒供快照
  展示，与 Go 原来「判定用单调时钟、快照用墙钟」的取值方式一致。清扫间隔仍是 60 秒。
- **并发语义**：分片锁从 `sync.RWMutex` 换成 `RwLock`，晋升与淘汰的临界区与 Go 相同；`clear`
  直接清空 `HashMap`，因此不再有 Go `container/list` 那种「孤儿元素被重新链接」的可能。
- **缺库时**：`put` 拒绝写入、查询全部 miss，隧道仍可正常解析（答案直连上游），并在首次探测时
  写一条日志。这是唯一一个“缺库只降级不失败”的内核，因为它只影响复用，不影响回答。
- **一致性验证**：wire 层迁移时用随机语料（5000 条合法响应 + 2000 条截断报文）把旧 Go 实现与
  内核逐项对比——键、最小 TTL、TTL 偏移、链目标、IP 列表、改写后的整段 wire 全部相同；容器迁移
  后又用同一批响应把两边的命中结果、命中/未命中计数、淘汰与快照顺序逐项对齐。

## MITM 过滤内核的已知边界

- **时间从 Go 注入**：每个有状态的调用都带 `now_ms`。内核不读时钟，所以“黑名单 7 天”“失败窗口
  10 分钟”能被单测钉死；代价是 Go 每次决策都要算一次 `time.Now().UnixMilli()`（与旧实现一样）。
- **持久化文件归内核**：`host|unix_seconds|reason` 的读、写、过期过滤与去重都在 `filter.rs`，
  Go 只传路径。写入失败不再静默：报告载荷里回传错误文本，Go 照原格式打印那条 `WARNING`。
  追加在写锁内做，因此不需要第二条文件锁。
- **非 UTF-8 主机按“不拦截”处理**：Go 字符串可以是任意字节，内核收的是 UTF-8。DNS 名、SNI
  与 `Host` 头到不了这里，但若到了，拒绝拦截是保守的方向。
- **64 KiB 行上限消失**：旧实现用 `bufio.Scanner`（单行 64 KiB），超长行会让它停下且不报错；
  现在整份文件一次读完，超长行只是一行。文件本来就只有几百行。
- **`getBlacklistCount` 不过期清理**：与旧实现一样只统计未过期的条目，真正的删除发生在
  `allows_interception` 撞到过期条目时或重新加载时。
- **移除不重写文件**：`RemoveFromBlacklist` 只删内存条目（与 Go 一样），下次启动那一行还会回来；
  要彻底清空得用 `ClearBlacklist`（它会截断文件）。
- **`allows_interception` 锁粒度**：命中黑名单时一次读锁，过期时再拿写锁删除，然后另一次读锁
  扫排除规则（与 Go 的 RWMutex 走法一致，只是不再分别加锁取切片引用）。
- **日志仍在 Go**：内核不打印任何东西；句子、格式与顺序由 `mitm_filter.go` 保留，便于与迁移前
  的日志直接对比。
- **缺库时**：`NewMitmFilter` 返回错误，`StartStackMitm` 失败（返回空 CA），引擎不起拦截。
  这是保守侧：不会静默开始解密本来该放行的端点，也不会“过滤静默失效”。
- **一致性验证**：`pattern` / `host_pattern` / `sensitive_host` 三份 fixture 是迁移时直接跑原 Go
  函数生成的（2964 + 2765 + 73 行），`filter` 的时间相关分支由注入时钟的单测钉住；`path.Match`
  的逐字节复刻包含 `/` 规则、字符类、转义与 `ErrBadPattern`。

## 装饰注入内核的已知边界

- **旧实现在两类输入上会写坏页面，这里没有照抄**：`bytes.ToLower` 是逐 rune 折叠，遇到非法 UTF-8
  字节会把每个字节换成三字节的 `U+FFFD`、遇到 `İ`(U+0130) 会把两字节折成一字节，于是它算出的
  `<head` 下标与原始缓冲区对不上——前者直接 `slice bounds out of range` 崩在读 body 的 goroutine
  里，后者把标签插进标记中间。内核在原地做 ASCII 折叠：多字节字符里不会出现 `<` 或 ASCII 字母，
  所以匹配结果相同而下标永远指向真实字节。这两类输入不进对拍语料（记录的是崩溃，不是行为），
  由 `inject.rs` 的单测钉住现在的结论。
- **`cap == 0` 的 `Read` 不再空转**：旧实现在 pending 非空且 `len(p) == 0` 时每次返回 `(0, nil)`，
  调用方会死循环；内核在这种调用上直接落到上游（`io.Copy` 与 net/http 都不会传 0 长度缓冲区）。
- **`carry` 只在“尾部是 `<head` 的前缀”时生效**：与旧实现一致，最多压 4 个字节（`<hea`）。
  `partial_head` 与完整 `<head` 走的是两条路：后者压整段等 `>`。
- **`<head` 之后没有 `>` 且同一次读到 EOF 时，那截标记会丢**：这是旧行为（`out` 只有 `<head` 之前
  的部分），A-064 修的是“数据读完、下一读拿 EOF”那条路径。两条路径都在语料里
  （`partial_prefix_at_eof` / `partial_prefix_then_eof`），没有顺手改。
- **`normalize_host` 走损失转换**：Go 的 `strings.ToLower` 逐 rune 折叠非法字节，`&str` 只能
  `from_utf8_lossy`（一个非法序列换一个 `U+FFFD`，Go 是每个非法字节一个）。主机名在现实中是
  ASCII 或 IDN UTF-8，语料覆盖了两侧都合法的写法。
- **`url.QueryEscape` 是按字节复刻**：字母数字与 `-_.~` 保留、空格变 `+`、其余 `%XX` 大写十六进制。
  `net.SplitHostPort` 只复刻**是否接受**（含 `]` 的形状检查），它从不校验端口值——旧代码也只用了
  错误是否为空这一个比特。
- **`ShouldInjectHTML` 留在 Go**：`strings.Contains(strings.ToLower(ct), "text/html")` 一行、
  每次响应问一次，搬进内核只会给一个纯谓词加一条错误路径。
- **规则载荷与样式表编译仍在 Go**：`SetCosmeticRules` 存的是原始 JSON，`buildCosmeticCss` 把
  hide/exception 编译成 CSS 文本——那是另一块（`mitm_local_server.go`），本轮没有搬。
- **句柄随 body 关闭释放**：`resp.Body` 就是那个 reader（不再是 `io.NopCloser`），`Close` 释放
  内核句柄并顺带关闭上游；漏关会随 GC 回收 `resp.Body`，但句柄本身要等下次建 reader。
- **测试需要 cgo**：内核是 cgo 加载的，`mitm_cosmetic_native_test.go` 整份带 `//go:build cgo`；
  不值得为它造一个纯 Go 的假内核（那就是第二套实现）。载荷解码在
  `mitm_cosmetic_payload_test.go` 里，不带 cgo 也能跑。

## 解析器统计内核的已知边界

- **时间从 Go 注入**：带状态的调用都带 `now_ns`（unix 纳秒），读取类调用只在需要比较惩罚衰减时才
  要 `now_ns`。内核不读时钟，所以「惩罚每 30 秒减半」「熔断冷却 5 秒起翻倍」能被单测钉死；代价是
  Go 每次记录事件都算一次 `time.Now()`（与旧实现一样）。
- **单位是纳秒整数**：Go 的 `time.Duration` 就是 `int64` 纳秒，内核在每个入口收发纳秒，浮点只在
  SRTT / RTTVAR 与失败率内部使用。`f64 as i64` 与 Go 的 `time.Duration(float64)` 同样向零截断，
  语料因此能逐位（含失败率的二进制位）比较。
- **时钟回拨**：惩罚衰减用 `now_ns - last_failure_ns`，为负时不衰减（与旧实现的 `since > 0` 相同）；
  熔断冷却比较的是绝对值。跨时钟回拨的行为与迁移前一致，没有额外加固。
- **锁粒度**：内核内一把 `RwLock`，读路径（评分、三种延迟、计数器）取读锁，记录与半开探针取写锁，
  与旧 `sync.RWMutex` 相同。「检查并置位探针」仍在一次写锁内完成，并发查询不会同时放行两个半开
  探针。
- **句柄随统计对象释放**：`resolver_stats.go` 在创建时注册 finalizer，最后一个引用消失后释放内核
  句柄；`providerStatsMap` 按上游 ID 复用统计对象，所以换配置时同一上游的历史会被保留（与旧实现
  完全一致）。
- **缺库时**：所有上游按冷启动取值参与调度——评分 `defaultEWMA`、hedge `hedgeDelayCold`、单次超时
  `attemptTimeoutCold`、UDP 重试 `udpRetryDelayCold`、每次尝试都放行。这正是迁移前 `p.stats == nil`
  的既有分支，回答不变；首次加载失败写一条日志。
- **调参表在两侧各有一份，由测试钉住**：`resolver_stats.go` 顶部保留六个数值（四个冷启动值供无库
  回退读，两个钳位与半衰期供用例断言），内核 `stats.rs` 是唯一的执行者。改任何一个值都要同时改两边
  并重新生成 `stats_trace.tsv`。

## DNS 应答内核的已知边界

- **`net.IP` 文本按 Go 复刻**：`diting-go-compat::ip::go_ip_string` 复刻 `net.IP.String()` ——
  4 字节点分、16 字节先试 `To4` 折叠（只有 `::ffff:a.b.c.d` 会折成点分）、其余按 `netip` 的零段规则
  压缩（长度 ≥ 2 的连续零段，左起最长者，平局取左）、奇数长度输出 `?` + 小写十六进制、空地址
  `<nil>`。`ip_string.tsv` 的 102 行把这条路径钉死；DNS 缓存内核自己的 4/16 字节格式化与它逐字节
  相同，所以两处没有行为差异（只是没共享代码）。
- **`0.0.0.0` 与 `::` 在 Go 里并不等价**：`net.IPv4zero` 是 16 字节的 `::ffff:0.0.0.0`，所以 A 记录里的
  4 字节零与其映射形式都算“空”，而 A 记录里的 16 字节 `::` 不算（`Equal` 长度相同但字节不同）；
  AAAA 只认 16 字节全零。`answers.tsv` 把这两条反直觉的分支都固化了。
- **零长度地址按 Go 走**：手工构造的 `dns.A`（没有地址）仍然算一条 IP 记录、不算空，日志里是
  `<nil>`；线上解包不会产生这种记录（A/AAAA 必须是 4/16 字节），保留只是为了“同一份 Go 判定”。
- **只有 A/AAAA 进载荷**：`isUpstreamBlockedMsg` / `resolvedAddressesMsg` 本来就忽略其它类型，所以
  Go 编码时直接跳过，内核也就看不到它们（`answers.tsv` 里的 `cname` / `txt` 行断言的是这一点）。
- **每次转发一次 FFI（一条载荷）**：编码是 `dns.Msg` 的 A/AAAA 记录一次拷贝（几十字节），内核回传
  「判定 + 唯一地址文本」。standalone 的两个调用点合并成一次 `inspectUpstreamAnswer`，诊断入口仍只
  需要判定。
- **地址去重的键是文本**：与 Go 一样先算 `String()` 再去重，因此 `A 1.2.3.4` 与映射形式的同地址只
  出现一次；顺序是应答顺序，不是排序。
- **阈值/窗口的负数语义照抄**：负阈值等价于 0（`requestCount > threshold` 立刻升级），负窗口等价于
  「每次调用都开新窗口」。`ApplyDNSConfig` 会把它们归一化成 ≥ 1，所以只有直接写配置的测试会碰到。
- **淘汰是不确定的**：`len > 4096` 时丢一个任意键；Go 的 map 迭代顺序本来也未定义，语料只钉住上限。
- **键是已归一化的域名**：`effectiveBlockResponseType` 仍用
  `strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")` 归一化后再调内核（与策略
  内核同一个跨边界约定），所以同一域名的大小写变体必然落在同一个计数器上。
- **`ParseResponseType` 留在 Go**：四个枚举值（0..3）是 Go 的类型，文本拼写是它的一行 switch；
  内核只回传数字，不参与字符串解析。
- **缺库时**：`inspectUpstreamAnswer` 返回「不拦截 + 空地址」（空答案按普通应答记日志），
  `dynamicBlockTracker` 每个阻断都返回配置模式（升级关闭）。加载失败写一条日志，不会伪装成
  “动态阻断已生效”。
- **一致性验证**：三份语料都是迁移时直接跑原 Go 实现生成的（102 + 25 + 25 行），Rust 的
  `answer/tests` 与 Go 侧 `dns_core_payload_test.go` 各自钉住载荷布局，`ffi/tests.rs` 钉住空句柄与
  坏参数。

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
  Linux/macOS 的纯 Go 动态加载；Windows 走标准库 `syscall.LazyDLL`。六个内核共用这套加载器。

## 规则索引内核的已知边界

- **域名归一化仍在 Go 侧**：`RuleMatcher.Match` 先做
  `strings.TrimSuffix(strings.ToLower(strings.TrimSpace(d)), ".")` 再调内核，因为命中 `$dnsrewrite`
  时构造 `dns.RR` 需要同一个名字。跨边界契约就是“已归一化”，与策略内核一致。
- **正则的编译结果由 Go 决定**：规则先由 Go 的 `regexp` 编译（编译失败即丢弃规则，行为与迁移前
  一致），编译通过的源再交给内核翻译编译。若内核拒绝了某条 Go 接受的源，该规则永不命中，
  `BuildFromRules` 会记录条数（`uncompiled_patterns`）而不是静默丢弃整次加载。
- **应答记录仍在 Go**：内核只回传 `rcode` 与命中规则的下标，`dns.RR` 的构造（含 `$dnsrewrite` 的
  `TTL`、`dns.Fqdn` 与 SVCB 参数）留在 `rewrite_native.go`，取值解析与校验在
  `diting-rewrite-core`。
- **规则原文与来源仍在 Go**：载荷只带判定字段（标志位、`$dnstype`、排除集合、重写 `key`），
  命中后按下标回查 `[]*ParsedRule`，所以那条切片在匹配器重建前必须保持存活。
- **布隆过滤器不参与判定**：它只负责在拦截字典树之前挡掉干净域名，位宽与哈希个数与 Go 完全一致，
  但即便有差异也只会多走一次字典树——真正的语义在 `trie.rs` / `index.rs`。
- **不可达分支的选择**：`Match` 无法返回错误。若内核在单次调用上返回非 0 状态（句柄提前释放或
  ABI 错配这类不可达状态），Go 侧记录日志后回落 `pass`：DNS 过滤失败时放行比让解析器崩掉安全。
  构建期失败则是硬错误，不会走到这里。
- **`diting-go-compat` 是各内核的唯一副本**：策略内核、规则索引、规则解析与重写记录都用它的
  大小写折叠（`ToLower` / `ToUpper`）、后缀匹配、正则翻译与 `dns.StringToType`，
  `diting-policy-core` 以 `pub use ... as text/regex_go/dns_type`
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
- **`$dnsrewrite` 取值解析也在内核**：规则解析内核只回传原文（裸形式为空串），Go 再把它交给
  `rewrite_action_native.go`，由 `diting-rewrite-core` 的 `action.rs` 切分与校验（见下节）。
  两条 FFI 都在规则加载时发生，不在查询路径上。
- **非 UTF-8 列表**：字节按 UTF-8 有损解码（非法字节变 U+FFFD），与 Go 的 `strings.ToLower` 把非法
  字节折叠成 U+FFFD、IDNA 随即拒绝的结果一致；不会因为一个坏字节让整份列表加载失败。
- **单行 1 MiB 上限消失**：原实现用 `bufio.Scanner`（上限 1 MiB，超限整份列表报错），现在整份
  字节一次交给内核，超长行只是那一行解析失败。
- **`ParseRuleLine` 是每行一次 FFI**：只有自定义规则与内置服务目录走这条路（数百条，启动时一次），
  订阅列表走整份批量入口。
- **产物体积**：IDNA 表（`idna` + ICU4X 编译数据）让 `diting_filter_core` 的 release DLL 从 1.52 MB
  涨到 1.73 MB。只有桌面服务加载这个库，Android 的两个 `.so` 不受影响。

## 重写记录内核的已知边界

- **`dns.RR` 仍在 Go 构造**：载荷只带类型号与已解析的字段（优先级、目标名、SVCB 参数列表等），
  `dns.RR_Header`、`Class`、`dns.HTTPS` 包装都在 `rewrite_native.go` 里。理由是应答要直接进
  `dns.Msg`，把结构再编码一次反而多一层。
- **每次构造一次 FFI（`$dnsrewrite`）**：自定义重写规则的显式记录已在引擎快照构建时编译一次，
  查询期直接回传；只有 `$dnsrewrite` 修饰符仍在每次命中时调一次 `buildRewriteRR`。都是一个固定
  小载荷加一次 `dns.RR` 分配。
- **IDNA 表版本**：目标域名校验用 `idna` crate 的 UTS 46（与 `diting-filter-core` 同一套配置），
  Go 原先用 `idna.Lookup`。已分配的合法域名字符判定一致，差异只在表版本（见「规则文本解析的
  已知边界」）。
- **ech 的 Base64 报错文案**：接受/拒绝的集合与 Go `base64.StdEncoding` 一致（标准字母表、
  必需填充），但错误文字来自 `base64` crate，不是 Go 的 `illegal base64 data at input byte N`。
- **地址解析用 Rust**：`Ipv4Addr` / `Ipv6Addr` 与 `net.ParseIP` 在带前导零的 IPv4 上同样拒绝；
  `::ffff:` 映射、`To4` / `To16` 的取舍（AAAA 拒绝 IPv4 字面量、`ipv6hint` 接受并映射）逐条
  按 Go 的行为对齐。
- **缺库时的表现**：`buildRewriteRR` 返回错误，`$dnsrewrite` 整条规则被丢弃（与迁移前对非法取值的处理
  一致）；引擎快照构建失败则 `NewRewriteEngine` / `Configure` / `AddRule` / `DeleteRule` 返回错误，
  服务启动或配置变更随之失败，不会退化成“重写规则静默不生效”。
- **记录类型表只在 Rust**：Go 侧的 `rewriteRecordTypes` 已删除，`RewriteRecordTypes()` 向内核取值；
  名字→类型号在 Go 侧仍用 `dns.StringToType`（`$dnsrewrite` 本来就用它），支持与否问内核。
- **产物体积**：新库依赖 `idna` 与 `base64`，release DLL 约 320 KB（filter 内核 1.73 MB 之外）。

## `$dnsrewrite` 取值内核的已知边界

- **展示文案仍在 Go**：`RewriteAction.String()` 用 `rcodeNames` 与 `dns.TypeToString` 拼日志文本，
  不参与任何判定；应答码与记录类型的解析（以及属性键）在内核里各有一份表，但只有内核那份影响行为。
- **错误文案的来源**：`dns.StringToType` 认得而重写内核不支持的记录类型（如 `NAPTR`）统一报
  「不支持的记录类型」，Go 原先先过表再在 `buildRewriteRR` 拒绝；接受/拒绝的集合完全相同，只有文本
  前缀不同。
- **键的归一化整份在内核**：地址用 `Ipv4Addr` / `Ipv6Addr` 解析与展示（`::ffff:` 折叠成 IPv4，
  IPv6 文本按 RFC 5952），目标名用 `diting-go-compat` 的 Go 语义小写与去尾点。Go 侧不再有第二份
  归一化，等价写法能不能互相取消只取决于内核。
- **取键失败是硬错误**：`filterEncodeRules` 里一次 `action_key` 调用失败会让 `BuildFromRules` 报错，
  而不是把未归一化的键放进索引——那样规则仍会命中，但例外会静默失效。
- **每条带 `$dnsrewrite` 的规则两次 FFI**：解析一次（`parse_action`）、建索引时取键一次
  （`action_key`），都在规则加载时发生，不在查询路径上。

## 重写引擎内核的已知边界

- **配置仍归 Go**：`RewriteRule` / `RewriteConfig` 是 IPC 的 JSON 形态，增删改也在 Go。每次变更重建
  整份快照（与旧实现在 `AddRule` / `DeleteRule` / `Configure` 里做的一样），规则不多，重建不在
  查询热路径上。若重建失败，旧快照与原配置完全保留。
- **`dns.RR` 仍在 Go 构造**：内核回传 `(matched, rcode, 记录列表)`，每条带类型号、属主、TTL 与
  已解好的字段；`dns.RR_Header` / `Class` / `dns.HTTPS` 包装留在 `rewrite_engine_native.go`，
  与记录构造的理由相同：应答要直接进 `dns.Msg`。
- **锁粒度**：查询在 Go 的 `RLock` 下做一次 FFI（旧实现整段判定也在同一把 RLock 内），配置变更
  在写锁内建新句柄并换新；旧句柄在写锁内释放，此时不可能还有读者。
- **PTR 键是地址字节**：Go 传入 `To4` 规范后的 4 字节或原生 16 字节，两边不必就 IPv6 的规范文本
  取得一致；映射到 IPv4 的形式在构建与查询两侧同样折叠成 4 字节。
- **CNAME 链的深度与循环判定逐条复刻**：先检查 `visited.len() > 8`，再归一化、查重、查规则，
  与旧 `chaseCNAME` 的顺序一致，所以最大链长与循环截断点不变。
- **无结尾点的泛域名**：归一化会去掉首尾点，`*.` 因此变成精确规则 `*`（旧实现同样如此）；
  `*.foo.` → `*.foo`。这类边界保留而不“修正”。
- **单次查询不可达的失败**：句柄构建成功后查询不应失败；若内核返回非 0 状态，Go 记一条日志并按
  “未命中”处理，让查询流向下一个中间件，而不是让解析器崩掉。构建期失败是硬错误。
- **警告文案由 Rust 生成**：非法显式记录与无法识别的 rcode 的提示在 `engine.rs` 里拼好，Go 仍用
  `[Rewrite]` 前缀写日志；含义与迁移前一致，引号风格来自 Rust 的 `{:?}`。

## 声誉查询内核的已知边界

- **公共后缀表换了数据源**：Go 侧用 `golang.org/x/net/publicsuffix`（2026-02-06 的 PSL 快照），内核用
  `psl` crate 自带的快照。ICANN / 私有后缀的判定方式一致（私有后缀与未知 TLD 都当作“没有注册域可
  锚定”，逐级上溯全部标签），差异只在表版本：两次快照之间新增的后缀会让摘要集合不同。
- **非 ASCII 主机名的公共后缀判定不同**：`golang.org/x/net/publicsuffix` 只收录 punycode 形式的
  TLD，`пример.рф` 的那一级后缀在 Go 眼里是未知 TLD（两级都参与比对），`psl` 同时收录 Unicode
  形式（只比对一级）。DNS 问题里的名字本来就是 punycode，查询路径遇不到这种输入；`hash/tests.rs`
  把这条差异单独钉住。
- **`dns.IsDomainName` 是逐字节复刻**：包括 `IsDomainName(Fqdn(x))` 内部再补一次点的行为、转义标签
  的 `begin` 算术、255 字节上限与「尾部孤立反斜杠」的拒绝。只有手工构造的名字能区分这些分支，
  但复刻一遍的成本远低于“简化后接受了旧实现拒绝的名字”。
- **时间从 Go 注入**：`plan` / `apply` 都带 `now_ms`，Go 传 `time.Now().UnixMilli()`；死线比较是
  `now_ms > expires_ms`（与 `time.Now().After` 一致）。Rust 单测因此不需要 sleep，Go 侧只剩一条
  1 秒有效期的端到端用例（它验的是「新时刻确实交给了内核」）。
- **`CacheSize = 0` 每次 `Configure` 都清空缓存**：旧实现比较的是“生效容量（0 归一化成 10000）
  != 配置原值（0）”，所以只要配置里写 0，每次配置变更都会重建缓存。照抄不改：代价只是一次清空。
- **判定顺序与计数仍在 Go**：两次 `plan`（恶意网址库命中即短路，家长控制那次只在需要时发）与中间的
  `Exchange` 都在 Go 里串起来，计数也只在 Go 累加——为计数再加一次 FFI 不值得。代价是同一主机名
  的归一化与 SHA-256 可能算两遍（≤4 个摘要，微秒级）。
- **TXT 段仍在 Go 侧取出**：`dns.Msg` 的类型断言留在 Go（应答要直接进 `dns.Msg`），内核只负责
  「64 位十六进制」的校验与摘要解码，因此 `collectHashes` 的过滤语义只有内核一份。
- **单次查询的坏载荷按放行处理**：句柄建好之后 `plan` 不应失败；若内核回传未知状态或坏载荷，Go 记
  一条日志并按“没有结论”放行，与模块整体的 fail-open 方向一致。缺库是硬错误（启动失败）。

## DNS64 内核的已知边界

- **`::ffff:0:0/96` 会匹配所有 IPv4 形态的地址**：`networkNumberAndMask` 把映射网段折成 4 字节
  `0.0.0.0` 加零掩码，于是 `Contains` 对任何 4 字节地址（以及任何 16 字节映射地址）都为真。迁移
  前就是这样，语料把它固化了。真要收窄，得单独改语义并补语料，不能在迁移里顺手“修好”。
- **前缀的 `IPNet` 形态与 `To16` 形态分开保存**：`EmbedIPv4InIPv6` 从 `IPNet.IP.To16()` 出发，
  对 `::ffff:0:0/96` 这类折叠过的网段，它与“按 128 位掩码后的地址”并不相同；内核把两者都算出来，
  嵌入用后者、比较用前者。
- **`EmbedIPv4InIPv6` 按字节传前缀，不走文本**：`IPNet.String()` 会把 `::ffff:0:0/96` 打成
  `0.0.0.0/0`，再按文本解析就成了另一条前缀（这个差异在迁移中真实出现过：语料一度被新实现重新
  生成，暴露了这 6 行）。所以这条 FFI 收的是 16 字节前缀与掩码长度，`bits == 32` 与
  RFC 6052 之外的长度由 Go / 内核分别拒绝。
- **`netip.ParseAddr` 是复刻**：Rust 的 `Ipv4Addr` / `Ipv6Addr` 解析器在 zone、点分前导零、
  连续双冒号这些规则上与 Go 一致（zone 两侧都拒绝，只是 Go 是先接受再在 `ParseCIDR` 里拒绝），
  语料钉住了 55 种写法。未来 Rust 若放宽某条，语料会立刻报错。
- **前缀错误文案留在 Go**：内核只回状态码（parse / length）与出错下标，`解析 DNS64 前缀 %q 失败:
  invalid CIDR address: ...` 与 RFC 6052 那句话由 Go 拼——`%w` 的 `net.ParseError` 原文因此一字不差。
- **配置错误不阻断启动**：缺库是硬错误，前缀写错只是警告，与迁移前一致（否则用户连改配置的 UI
  都打不开）。`IsDNS64ConfigError` 是两者唯一的分界。
- **TTL 与别名仍在 Go**：A/CNAME/DNAME 的最小 TTL、`overrideTTL > 0` 的覆盖、把 CNAME/DNAME
  补进应答、`RR_Header` 的 name/class 都由 Go 决定；内核只回答“这个 4 字节地址在每个前缀下
  应该变成哪 16 个字节”。
- **每条 A 记录一次 FFI**：`SynthesizeFromAWithTTL` 按记录调用（通常 1–4 条），而不是把整份应答
  编成载荷；换来的 Go 侧代码与迁移前一模一样，少一层中间表示。
- **`HasValidAAAARecords` 的地址按原宽度传入**：AAAA 里没有地址的（`nil`）在 Go 侧直接跳过——
  旧实现里 `IsExcluded(nil)` 为真，也就是“不算有效 AAAA”，两侧结论相同。

## 本地 hosts 内核的已知边界

- **非 UTF-8 字节按 UTF-8 损失转换**：Go 的 `strings.ToLower` 会把每个非法字节换成 `U+FFFD`，
  内核用 `String::from_utf8_lossy`（一个非法序列一个 `U+FFFD`）。绝大多数非法序列两者一样，
  差别只在「一个多字节序列里坏在中间」这类输入上。hosts 里出现这种主机名的概率可以忽略，
  但真遇到时查表键可能不同。
- **`net.ParseIP` 是复刻，不是等价替换**：`1.2.3.4.5`、`1.2.3`、`01.2.3.4`、`0x7f.0.0.1`、
  `1::2::3::4`、`::ffff:01.2.3.4` 这些字面量两侧都拒绝，接受的那些也逐字节相同——语料把
  Go 的判定表整份固化了下来，只是 Rust 的解析器换了实现，未来的 Rust 版本若放宽某条规则，
  语料会立刻报错。
- **64 KiB 的行会截断整个文件**：`bufio.Scanner` 在超过 `MaxScanTokenSize` 时永久停止迭代，
  后面的行一条都不会被解析。这是原实现的既有行为，照抄保留（否则「超过上限后继续读」会让
  同一个文件在两侧读出不同的表）。
- **PTR 键用折叠后的地址而不是 `ip.String()`**：Go 用 `ip.String()` 当键，映射形式的 `::ffff:1.2.3.4`
  会打印成 `1.2.3.4`，与 IPv4 条目重合；内核直接把映射形式折叠成 4 字节，键因此相同，且不再依赖
  两个语言对 IPv6 压缩形式的打印结果一致。
- **表是不可变的**：`LoadFile` / `LoadReader` / `Reload` / `UpdateConfig` 都是「建新表 → 换指针 →
  释放旧表」，读路径在 `RLock` 内调用内核，所以旧表不会在有查询在飞时被释放。代价是热重载会
  重建整张表（旧实现重填映射也是 O(全部条目)）。
- **文本来源存在 Go 侧**：`LoadReader` 的输入被当成 source 列表里的一段文本记住，重载时重放；
  `UpdateConfig` 会丢掉它们（旧实现整体替换映射，同样会丢）。
- **`dns.PTR` 的目标名仍在 Go 侧补尾点**：内核回传的是文件里那条主机名（已小写、去首尾点），
  `dns.Fqdn` 由 Go 调用——它同时决定了 `dns.RR_Header.Name` 的形态，留在 Go 更直观。
- **`ParseIPFromArpa` 现在是一次 FFI 调用**：调用方（hosts 反查、重写引擎反查）签名未变，
  IPv4 结果从 16 字节的 `net.IP` 变成 4 字节（`String()` 与 `To4()` 的观察结果不变）。
- **路径经文本往返**：`loadedFiles` 由内核回传 `Path::display()` 的结果，Go 再原样用作下一次
  重载的路径。Windows 的路径本来就是 UTF-16，Linux 上非法 UTF-8 的路径会被损失转换——那种路径
  连错误信息都打不出来，因此没有为它保留字节通道。

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

DNS 缓存命中（同一台机器、同一份答案，200k 次取最慢与最快各一轮）：

| 实现 | 每命中耗时 | 分配 |
|---|---|---|
| 迁移前：Go 分片 LRU + 一次 `patch_response` | 0.61–0.67 µs | 3 次 / 376 B |
| 迁移后：句柄 `get` + 命中载荷编解码 | 1.60–1.76 µs | 7 次 / 288 B |

多出来的一次 FFI 与载荷编解码约 1 µs。命中路径本来就要拷贝答案；相对一次真实上游解析（毫秒级）
这点开销可以忽略，但它是这一轮唯一的净开销，所以 `后续可做`里留了「把改写直接做进载荷缓冲」的条目。
未命中路径（一次 `put`）只在收到上游答案时发生，次数比命中少一个数量级。

复现：

```bash
cd android/engine
go test -run XXX -bench BenchmarkDNSCacheGetFast_Hit -benchtime 200000x .
```

## 验证

```bash
python rust/verify.py            # fmt + clippy -D warnings + cargo test
python rust/verify.py --go       # 再加 Go 侧策略内核、DNS 缓存内核、MITM 过滤内核、装饰注入内核、解析器统计内核、DNS 应答内核、流嗅探内核、引导解析内核、应用白名单内核、连接日志去重内核、IP→域名缓存内核与 DTRI fixture 用例
python rust/verify.py --desktop  # 再加桌面服务（Go）全量用例：印章、规则、重写记录、声誉查询、hosts 与 DNS64 全部经 Rust
python rust/verify.py --dart     # 再加 Dart 侧规则解析与入库用例
python rust/verify.py --android  # 再加 arm64-v8a 交叉编译（十二个 .so）
python rust/verify.py --bench    # 再加 DTRI / 检索 / 策略判定基准
python rust/verify.py --all      # 全量
```

`--go` 会先 `cargo build --release`（Go 侧按约定探测 `rust/target/release/`），并且需要 `cgo` 与
C 编译器（Windows 用 mingw，Linux/macOS 用 gcc/clang）。这一步的 `go test` 带 `-count=1`：内核是
Go 看不见的外部文件，缓存会让“重建内核后重跑”变成假跑。`--desktop` 不需要 cgo：桌面内核走纯 Go 动态
加载，先 `cargo build --release -p diting-stamp-core -p diting-filter-core -p diting-rewrite-core
-p diting-safebrowsing-core -p diting-hosts-core -p diting-dns64-core` 再去 `desktop/service`
跑 `go test ./...`。
`--dart` 同样需要先建好本机产物：Dart 侧已经没有第二份解析器可以兜底。

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
- **正则与通配模式的编译归属**：现在 Go 编译后把源交给内核，两条路径各编一次；把
  `ParsedRule.Regex` 一并搬到 Rust 后，`buildWildcardRegex` 就只剩内核里的一份。
- **缓存命中载荷**：现在命中要拷贝三次（patch、载荷编码、Go 侧拷出）。让内核把 ID/TTL 直接改写进
  载荷缓冲、Go 侧按段落读取，可以省掉两次拷贝。
- **备份导入导出**：语义面较大，可先精简备份格式再逐组迁移。
