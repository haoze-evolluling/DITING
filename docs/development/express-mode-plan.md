# DITING 极速模式分阶段实施计划

> 状态:方案已评审、架构决策已确认 | 创建:2026-10-04 | 实施节奏:按阶段独立提交

## 1. 背景与总体目标

为 DITING 新增第三个工作模式——**极速模式**,用户可在「普通模式」「极速模式」「服务器模式」间自由切换:

- 普通/服务器模式:维持 **Android 10(API 29)** 门槛,继续使用 Go 内核;
- 极速模式:**纯 Kotlin 原生实现**(去除 Go 内核依赖),最低支持 **Android 7(API 24)** (ARM64);
- 极速模式定位为「普通模式的轻量化 Kotlin 实现」:复用普通模式 UI 与全部 DNS 设置,精简 9 项高级功能,保留核心网络管理能力(DNS 解析加速、规则过滤、缓存、日志)。

## 2. 已确认的架构决策

| 决策项 | 结论 |
|---|---|
| 数据面架构 | **DNS 专用 VPN(窄路由)**:TUN 仅承载 DNS 流量;虚拟 DNS 地址(/30、/64)与公共 DNS 劫持列表(/32)路由进 TUN,UDP/TCP 53 交 Kotlin 引擎;进入 TUN 的非 53 端口 TCP 流量快速回写 RST,避免连接挂死超时;其余流量走物理网络 |
| 公共 DNS 劫持 | **首版即加入**:约 20 个常见公共 DNS IP(8.8.8.8、1.1.1.1、223.5.5.5 等)+ 若干 IPv6 |
| 无需自研完整 TCP/IP 栈 | 非 DNS 流量不进 TUN(非 53 端口 TCP 仅做 RST 快速拒绝);TCP 仅需支持 DNS-over-TCP(极简终结器) |
| 已知取舍 | 硬编码小众 DNS 的应用可能绕过;无法阻断 DoT:853/私人 DNS;无 QUIC 管控;「绕过局域网」无意义(隐藏) |

被移除的 9 项功能(MITM、应用级管控、流量统计、出站代理等)本就依赖全隧道,与该架构天然一致。

## 3. 能力范围

**保留**(与普通模式一致):电源启停、DNS 服务商选择、解析模式(单一/智能/最快/依次)、规则控制开关、黑白名单与订阅规则、DNS 缓存(多档策略)、查询/竞速/引导日志、DNS 缓存统计页、悬浮日志、通知与快捷磁贴、配置导入导出。

**移除**(仅隐藏入口,设置数据保留,切回普通模式即恢复):覆写名单、应用流量统计(含通知栏网速)、应用独立规则、禁止联网应用、排除应用、HTTPS 流量检查(含 CA 证书页)、出站代理、网络诊断、AI 分析(含全部入口)。

## 4. 可复用资产(已代码验证)

| 能力 | 现成实现 |
|---|---|
| 规则判定(7 级优先级) | `vpn/DomainPolicyEngine.kt` + `BlockRuleMatcher`/`AllowRuleMatcher` |
| 订阅规则 DTRI 读取 | `vpn/MappedSubscriptionRuleIndex.kt`(纯 Kotlin mmap,与 Go 同格式) |
| 规则加载管线 | `BlockRuleCacheLoader`/`AllowRuleCacheLoader` + Room 规则库 |
| DNS 缓存 | `vpn/cache/DnsResponseCache`(分片 LRU + single-flight + stale + Room 持久化) |
| 上游传输 | `vpn/PlainDnsTransport.kt`、`vpn/DotTransport.kt`;DoH 从 `DnsLatencyTester.kt` 提取为 `vpn/DohTransport.kt`(DnsProtocol 仅 PLAIN/DOH/DOT,无需 DoQ) |
| 配置模型 | `HttpsDnsConfigSnapshot`、`DnsVpnProviderResolver`、`BlockResponseMode`、`DynamicBlockResponsePolicy`、`DnsResolutionMode`、`DnsCachePolicy` |
| 阻断应答 | `vpn/DnsMessageUtils.kt`(问题解析、阻断应答、TTL patch、响应校验) |
| 日志/健康 | `DnsLogger`、`RaceLogger`、`BootstrapLogger`、`ProviderHealthEngine`、`BootstrapHealthEngine` |
| 通知 | `notification/VpnNotificationBuilder`(无服务耦合) |

**全新开发**:TUN 数据面编解码、DNS 查询编排器、ExpressVpnService、模式框架与 UI 裁剪。预估新增约 2400~3300 行 Kotlin。

## 5. 阶段总览(6 个阶段)

| 阶段 | 主题 | 核心产出 | 前置依赖 |
|---|---|---|---|
| 一 | 数据面编解码层 | `ExpressPacketCodec`、`PublicDnsHijackList` + JVM 测试 | 无(纯新增) |
| 二 | DNS 引擎与上游分发 | `DohTransport` 提取、`ExpressDnsEngine`、`ExpressUpstreamDispatcher`、`ExpressTcpDnsHandler` + JVM 测试 | 阶段一 |
| 三 | 极速 VPN 服务与系统集成 | `ExpressVpnService`、`ExpressTunnelManager`、意图/刷新/控制器、Manifest 注册 | 阶段二 |
| 四 | 模式框架与构建基座 | `AppWorkMode.EXPRESS`、选择屏三卡、三向切换、minSdk 24 (维持 arm64)、通知渠道兼容、磁贴/常驻通知/API 审计 | 阶段三 |
| 五 | UI 模式化裁剪 | `ModeFeatureGate` + 全部接入点过滤 | 阶段四 |
| 六 | 配置迁移、文档与整体验收 | 导入导出、README/docs、多版本验收矩阵 | 阶段五 |

> 排序原则:阶段一~三为纯新增(`express` 包闭环,不影响现有行为,每个提交均可运行);阶段四落地后极速端到端可用;阶段五、六做裁剪与收尾。

## 6. 各阶段详细计划

### 阶段一:数据面编解码层(纯 Kotlin 基础库)

**目标**:提供 TUN 收发包的解析与构建能力,JVM 可测,零 Android 依赖,不触碰现有代码。

**涉及范围**:新增 `express/engine/` 包;`app/src/test/`。

**具体工作**:

1. `ExpressPacketCodec.kt`(~400 行):
   - IPv4 解析:version/IHL 校验、总长、协议号、源/目的地址;识别分片(非首片丢弃,首片含 DF 处理);
   - IPv6 解析:固定头 + 逐跳扩展头跳过,识别上层协议 UDP/TCP;
   - UDP 头:源/目的端口、长度、校验和;**目的端口 53** 识别为 DNS 查询;
   - TCP 头(服务于 DNS-over-TCP 及非 53 端口兜底):源/目的端口、seq/ack、标志位、窗口;
   - 非 53 端口快速拒绝:针对进入 TUN 的非 53 端口 TCP 报文(如发往劫持 IP 的 443/853 端口)快速回写 TCP RST,避免外部连接握手死锁超时;丢弃其他非 DNS 异常报文;
   - 应答包构建:IP(v4/v6)+ UDP 头 + DNS 载荷,校验和计算(IPv4 头校验和、UDP 校验和含伪首部、IPv6 伪首部)、IP ID 生成、TTL patch(复用 `DnsMessageUtils.ResponseTtlMetadata` 偏移量方案);
   - 缓冲区策略:复用 buffer、避免逐包分配(老设备性能关键)。
2. `PublicDnsHijackList.kt`(~60 行):约 20 个常见公共 DNS IPv4(8.8.8.8/8.8.4.4、1.1.1.1/1.0.0.1、9.9.9.9/149.112.112.112、208.67.222.222/220.220、223.5.5.5/223.6.6.6、119.29.29.29、114.114.114.114/115.115、180.76.76.76、77.88.8.8/8.1、94.140.14.14/15、185.228.168.9/169.9、64.6.64.6/65.6 等)+ 约 8 个 IPv6(2001:4860:4860::8888/8844、2606:4700:4700::1111/1001 等),带来源注释;供阶段三路由配置消费。
3. JVM 单元测试:已知报文向量往返、校验和正确性(标准向量)、非 53 端口 TCP RST 构造、畸形包鲁棒(截断/越界/版本错)、IPv6 扩展头跳过、TTL patch 幂等。

**交付与验收**:测试全绿;`git status` 仅新增文件;对现有代码零修改。

**提交**:`feat(express): 新增极速模式数据面包编解码与公共 DNS 劫持清单`

### 阶段二:DNS 引擎与上游分发

**目标**:完成极速模式的「大脑」——与 Go 内核 `handleDNSQuery` 语义对齐的 Kotlin 查询管线与上游策略,JVM 可测。

**涉及范围**:新增 `express/engine/`;微改 `vpn/DnsLatencyTester.kt`(DoH 提取,行为不变);`app/src/test/`。

**具体工作**:

1. `vpn/DohTransport.kt`(新,~150 行):从 `DnsLatencyTester` 提取 DoH POST 客户端(OkHttp、`application/dns-message`、bootstrap 地址、protect 回调);`DnsLatencyTester` 改为调用,回归测速功能。
2. `ExpressDnsEngine.kt`(~350 行):查询管线(对齐 Go 顺序)——`_dns.resolver.arpa` 返回 NXDOMAIN(DDR 反制)→ 规则开关(`isDomainRulesEnabled`)→ 判定(依赖注入的 `DomainDecisionFunction`,生产实现委托 `DomainPolicy.evaluate`)→ 命中按 `BlockResponseMode` + `DnsMessageUtils` 构建阻断应答 + `DynamicBlockResponsePolicy` 动态响应 → 未命中走 `DnsResponseCache.resolve`(single-flight/stale/负缓存)→ `ExpressUpstreamDispatcher`;非 A/AAAA 类型照常转发;统计计数(查询/拦截/缓存命中/延迟);`ProtectSocketProvider` 接口由服务注入;引擎自身不依赖 android.*(DomainPolicy 经接口隔离,便于 JVM 测试)。
3. `ExpressUpstreamDispatcher.kt`(~300 行):`DnsVpnProviderResolver` 解析 provider 列表;按 `DnsResolutionMode` 分发——SINGLE 直发;PARALLEL_RACE 协程竞速(首个有效响应胜出,其余取消;在协程取消回调中主动 close 对应底层 Socket,中断阻塞读并立即释放 `Dispatchers.IO` 线程,防止高频查询线程饥饿);PRIMARY_BACKUP 依次 failover;SMART_PREDICTION 首版按竞速处理(列表已由智能选择裁剪,EWMA 排序列为后续增强);协议映射 PLAIN→`PlainDnsTransport`、DOT→`DotTransport`、DOH→`DohTransport`;上游默认支持 EDNS0(协商 1232~1400 字节缓冲,降低大响应截断);超时复用 `DnsTimeoutConstants`;竞速/引导结果写 `RaceLogger`/`BootstrapLogger`;响应校验复用 `isUsableUpstreamResponse`(事务 ID/Question 一致、rcode 合法)。
4. `ExpressTcpDnsHandler.kt`(~350 行):极简 DNS-over-TCP 终结——三次握手应答、对端序号/确认号跟踪、载荷重组、2 字节长度分帧后交引擎、应答分段回写、FIN/RST 处理、基础重传定时;作为核心能力严格交付,保障客户端在极少数因响应超长触发 TC 标志重试时不超时卡死。
5. JVM 单元测试:判定矩阵(四种阻断应答/放行/过滤关闭)、四种策略分发(假传输层)、竞速取消与 Socket 及时释放、缓存集成命中/过期/stale、TCP 握手与分帧(脚本化对端)。

**交付与验收**:测试全绿;「Go↔Kotlin 语义对齐清单」逐项复核(判定优先级、阻断应答、动态响应、负缓存、stale)。

**提交**:`feat(express): 新增极速 DNS 引擎、上游分发与 DNS-over-TCP 处理`

### 阶段三:极速 VPN 服务与系统集成(express 包闭环)

**目标**:数据面 + 引擎装配成可运行的 VPN 服务。本阶段结束时极速模式完整可用但**尚无 UI 入口**(纯新增,不影响现有行为)。

**涉及范围**:新增 `express/`;`AndroidManifest.xml` 注册服务。

**具体工作**:

1. `ExpressVpnService.kt`(~300 行):`VpnService` + START_STICKY;`onStartCommand` 动作分发(START/STOP/REFRESH_CONFIG/SYNC_RULES/CLEAR_CACHE,常量与工厂 `ExpressVpnIntents.kt`);TUN 建立——地址 10.0.0.2/30 + fd00:abcd::2/64、DNS 10.0.0.1/fd00:abcd::1,**路由仅含** 10.0.0.0/30、fd00:abcd::1/128 与劫持清单 /32(IPv6 劫持项仅在该模式启用且有物理 IPv6 时添加);`addDisallowedApplication(self)`;MTU 1400;前台通知复用 `VpnNotificationBuilder`;`startForeground` 按版本分支(<29 不带 type);`onRevoke` 清理。
2. `ExpressTunnelManager.kt`(~300 行):TUN 读写循环(读线程 → codec → 协程池分发;UDP:53 → 引擎,TCP:53 → TCP 处理器)→ 写回;`protect()` 注入;启动前等待规则缓存就绪(`BlockRuleCache`/`AllowRuleCache` 加载完成);IPv6 按设置与物理网络探测(复用 `DnsVpnTunnelManager` 探测思路);生命周期与崩溃兜底。
3. `ExpressVpnController.kt`(~120 行):`StateFlow<Boolean>` isRunning、start/stop,供 UI 电源开关;缓存无缝复用:DnsResponseCache 自带 Room 持久化写入,DnsCacheScreen 与 ViewModel 直接基于 Room DAO 分页查询,无需额外编写 JSON 统计桥。
4. 热刷新:REFRESH_CONFIG 重建 `HttpsDnsConfigSnapshot`(复用现有读取逻辑)、SYNC_RULES 重载规则缓存并失效 `DomainPolicy` 判定缓存;`RuntimeDnsSettingsRefresher` 的模式路由留待阶段四。
5. Manifest:注册 `.express.ExpressVpnService`(`BIND_VPN_SERVICE` + specialUse "vpn")。

**交付与验收**:adb 手动拉起/停止服务,规则命中与放行、缓存、日志在真机/模拟器验证;普通/服务器模式行为零变化。

**提交**:`feat(express): 新增极速模式 VPN 服务与数据面集成`

### 阶段四:模式框架与构建基座

**目标**:三模式框架落地,极速端到端可用;应用可在 Android 7(API 24, 64 位)设备安装并使用极速模式。

**涉及范围**:`ui/mode/`、`MainActivity.kt`、`SettingsRouteActivity.kt`、`ui/RuntimeDnsSettingsRefresher.kt`、`vpn/DitingTileService.kt`、`notification/VpnMonitorService|Manager`、`app/build.gradle.kts`、`AndroidManifest.xml`。

**具体工作**:

1. `AppWorkMode.kt`:新增 `EXPRESS("express")`;增加 `minApiLevel`(NORMAL/DNS=29、EXPRESS=24);文案(badge「极速」、summary「Kotlin 原生轻量实现,DNS 解析加速与规则过滤,支持 Android 7+ (64 位)」)。
2. `WorkModeSelectionScreen`/`WorkModeCard`:第三卡自动渲染;不可用模式置灰并显示「需要 Android 10」/「需要 64 位设备」。
3. 切换流:`MainActivity`(152-241 行区域)与 `SettingsRouteActivity`(439-471 行区域)三向互斥——切极速时停 `DnsVpnService` 与 `DnsModeService` 后进入 MainScreen(极速态);降级保护:存量模式为 normal/dns 的设备不满足条件时回退模式选择屏;`RuntimeDnsSettingsRefresher` 按模式路由到 `ExpressVpnIntents`。
4. 构建配置:`minSdk 29→24`;架构维持 `arm64-v8a`(避免 32 位设备缺失 libgojni 导致 INSTALL_FAILED_NO_MATCHING_ABIS 无法安装)。
5. 系统入口:`DitingTileService` 极速分支;`VpnMonitorService`/`VpnMonitorManager` 常驻快捷通知支持拉起极速服务;极速模式不做开机自启(与普通模式一致)。
6. API 兼容审计:通知系统兼容:AppNotificationChannels 与后台 Worker 增加 `SDK_INT >= O` 门控,避免在 API 24/25 上因缺少 NotificationChannel 崩溃;统一使用 `ContextCompat.startForegroundService` 与版本化 `startForeground`(<29 不传 type);lint NewApi 清理共享路径(UI 在 API 24-28 可达但普通模式专属代码不可达的保证);express 服务已在阶段三处理版本分支。

**交付与验收**:API 24 模拟器完整走通极速模式(选择→授权→启停→过滤→日志);普通/服务器在 <29 设备不可选且提示正确;三模式互斥切换无损;现有两模式回归正常。

**提交**:`feat(mode): 新增极速模式框架并下放最低支持至 Android 7`

### 阶段五:UI 模式化裁剪

**目标**:极速模式下 9 项功能入口全部不可见、不可直达;普通模式 UI 零变化。

**涉及范围**:新增 `ui/mode/ModeFeatureGate.kt`;改动 `ui/FeatureHubScreen.kt`、`ui/BottomBarDestination.kt`、`ui/SettingsSearchCatalog.kt`、`SettingsRouteActivity.kt`、`ui/ModernLogDashboardScreen.kt`、`ui/DnsCacheScreen.kt`、`ui/RequestLogScreen.kt`、`ui/agent/AgentAnalysisSheet.kt` 调用点、`ui/MainScreenContent.kt` 等。

**具体工作**:

1. `ModeFeatureGate.kt`(单点维护):极速隐藏清单——覆写名单、应用流量统计(含通知栏网速与流量 tab)、应用独立规则、禁止联网应用、排除应用、HTTPS 流量检查(含 CA 证书页与 URL 规则)、出站代理、网络诊断(含 NETWORK_TOOLS tab)、AI 分析(含 4 处入口与 AgentApi 设置);派生隐藏:请求日志 HTTPS 来源、首页「绕过局域网」等全隧道快捷项。
2. 接入点:FeatureHub 卡片过滤(与 `HiddenFeaturesStore` 的用户自隐藏叠加,模式门控优先);`BottomBarDestination` 在极速下过滤且不可被用户配置选中;`SettingsSearchCatalog` 设置首页 + 搜索同步过滤;`SettingsRouteActivity` 对被移除页面路由拦截回退(防直达死链);`MainScreenContent` 启停/状态分派到 `ExpressVpnController`,状态文案按模式微调。
3. 共享页面行为核对:服务商选择、解析模式、规则控制、日志仪表盘、DNS 缓存、悬浮日志在极速下保持完整可用。

**交付与验收**:极速下九项功能不可见且路由不可达;无死链/空白页;普通模式 UI 与交互无任何变化(逐屏对比)。

**提交**:`feat(ui): 极速模式下隐藏全隧道专属功能入口`

### 阶段六:配置迁移、文档与整体验收

**目标**:收尾与全量验证,形成可发布状态。

**涉及范围**:`ui/transfer/`、`README.md`、`docs/`、全量测试。

**具体工作**:

1. 配置导入导出:`ConfigExporter`/`ConfigTransferParser`/`PreferenceConfigImporter` 支持 `express` 模式值往返;确认极速不读写被移除功能的 store。
2. 文档:README 版本矩阵(极速 Android 7+ / 普通·服务器 Android 10+)与模式说明;`docs/development/` 补充极速架构说明(数据面、劫持清单维护方式、已知取舍)。
3. 验收矩阵:模拟器/真机 API 24/29/33(+36) (arm64-v8a);场景:启停、规则命中/放行、缓存命中与清理、竞速与日志落盘、三模式互斥切换、降级场景(<29 存量 normal)、低端机稳定性与功耗抽查。
4. 回归:普通/服务器模式全流程回归清单;`./gradlew test` 全绿;`build_apk.bat` 打包验证。

**提交**:`docs: 更新极速模式说明与版本支持矩阵`(及必要修复提交)

## 7. 跨阶段约定

- 每个代码文件 ≤600 行(AGENTS.md);每阶段一或多个独立提交,中文 Conventional Commits;禁止提交未完成修改(阶段一~三均为纯新增可运行提交,阶段四起每阶段结束均为完整可用状态)。
- 移除功能仅隐藏入口,设置数据保留不动;极速服务不读取这些开关。
- 极速引擎新代码(JVM 可测部分)不依赖 android.*;android 耦合(如 `android.util.LruCache`)经接口隔离在 `express` 包外。
- 性能红线:逐包处理避免分配放大;读循环单线程 + 处理协程池;息屏无额外轮询(无流量统计,天然省电)。

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| DNS-over-TCP 极简栈正确性 | 仅面向本机解析器、DNS 尺寸;完备脚本化测试;上游默认启用 EDNS0(1232 字节),绝大多数大响应在 UDP 直接承载;TCP 53 作为关键能力严格测试交付,确保客户端在极少数分段重试时不会死锁超时 |
| Android 7 OEM 对 VPN DNS 的兼容差异 | 验收矩阵覆盖 API 24 真机/模拟器;劫持清单与虚拟 DNS 双通道互为兜底 |
| minSdk 24 引入共享路径 API 违规 | 阶段四集中 lint NewApi 审计 + 运行时门控(普通模式代码在 <29 不可达) |
| 架构兼容与安装保障 | 维持 arm64-v8a 过滤,不混入无 32 位 .so 的 armeabi-v7a 声明,确保安装合规;覆盖 API 24+ ARM64 主流设备 |
| 老设备性能 | 编解码零分配策略、窄路由天然低负载;抽查低端机 |
| 缓存/日志页面数据复用 | DnsResponseCache 自带 Room 持久化写入,UI 直接通过 DnsCacheDao 读取,无需 Go 格式 JSON 桥接 |

## 9. 验收标准(总体)

1. Android 7(API 24, 64 位)设备可安装并完整使用极速模式;普通/服务器模式在 Android 10 以下正确不可用。
2. 三模式自由切换、互斥运行,切换无损、设置数据保留。
3. 极速模式核心能力与普通模式对齐:解析加速(4 种模式)、规则过滤(订阅 + 自定义 + 特殊规则)、多档缓存、日志、悬浮日志、通知/磁贴。
4. 9 项指定功能在极速下入口全部隐藏且不可直达。
5. 普通/服务器模式行为与现状完全一致(回归通过)。
