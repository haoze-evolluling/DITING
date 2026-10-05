# DITING 极速模式分阶段实施计划

> 状态:方案已评审、架构决策已确认 | 创建:2026-10-04 | 实施节奏:按阶段独立提交
> 核心理念:**新文件优先、物理隔离、复制复用**。新模式尽量通过创建新文件实现，最大程度减少对旧代码的修改；旧有 KT 文件与旧模式逻辑保持严格独立。对于可复用的现有代码、UI、逻辑设计或流量处理方案，优先直接复制并在新文件中独立使用与适配，严禁修改原代码后让新旧模式共用同一套实现。

## 1. 背景与总体目标

为 DITING 新增第三个工作模式——**极速模式**,用户可在「普通模式」「极速模式」「服务器模式」间自由切换:

- 普通/服务器模式:维持 **Android 10(API 29)** 门槛,继续使用 Go 内核与全隧道代理;
- 极速模式:**纯 Kotlin 原生实现**(去除 Go 内核依赖),最低支持 **Android 7(API 24)** (ARM64);
- 极速模式定位为「普通模式的轻量化 Kotlin 实现」:复用普通模式核心网络交互体验与全部 DNS 设置,精简 9 项高级功能,保留核心能力(DNS 解析加速、规则过滤、缓存、日志);
- **工程实现原则**:极速模式采用独立的 `express` 代码树，不与旧模式强行共用受侵入的 KT 文件。现有能力（传输、通知、UI、报文编解码等）一律通过“源码级复制到新文件并独立定制”的方式实现复用，确保旧模式零风险、极速模式轻装演进。

## 2. 已确认的架构决策

| 决策项 | 结论 |
|---|---|
| 代码组织与隔离原则 | **独立新文件优先 / 复制复用优先**:极速模式核心实现全部落在独立的 `express/` 模块下。严禁为共用逻辑而侵入式修改现有旧 KT 文件;可复用模块直接源码级复制至新文件中独立维护;旧代码仅在最外层路由入口保留最小必要的极简分流,保持旧模式代码 100% 独立稳定 |
| 数据面架构 | **DNS 专用 VPN(窄路由)**:TUN 仅承载 DNS 流量;虚拟 DNS 地址(/30、/64)与公共 DNS 劫持列表(/32)路由进 TUN,UDP/TCP 53 交 Kotlin 引擎;进入 TUN 的非 53 端口 TCP 流量快速回写 RST,避免连接挂死超时;其余流量走物理网络 |
| 公共 DNS 劫持 | **首版即加入**:约 20 个常见公共 DNS IP(8.8.8.8、1.1.1.1、223.5.5.5 等)+ 若干 IPv6 |
| 无需自研完整 TCP/IP 栈 | 非 DNS 流量不进 TUN(非 53 端口 TCP 仅做 RST 快速拒绝);TCP 仅需支持 DNS-over-TCP(极简终结器) |
| UI 呈现策略 | **独立 UI 视图文件**:直接复制现有 UI 结构创建极速模式专属 UI 页面,在物理文件层面直接剔除 9 项专属功能,不在旧 UI 文件中插入模式分支或动态门控,旧模式 UI 零改动 |
| 已知取舍 | 硬编码小众 DNS 的应用可能绕过;无法阻断 DoT:853/私人 DNS;无 QUIC 管控;「绕过局域网」无意义(在独立主页中移除) |

被移除的 9 项功能(MITM、应用级管控、流量统计、出站代理等)本就依赖全隧道,在极速模式专属新文件中直接去除,与该架构天然一致。

## 3. 能力范围

**保留**(与普通模式一致):电源启停、DNS 服务商选择、解析模式(单一/智能/最快/依次)、规则控制开关、黑白名单与订阅规则、DNS 缓存(多档策略)、查询/竞速/引导日志、DNS 缓存统计页、悬浮日志、通知与快捷磁贴、配置导入导出。

**移除**(在极速模式独立 UI 中直接去除对应入口,底层设置数据保留,切回普通模式即恢复):覆写名单、应用流量统计(含通知栏网速)、应用独立规则、禁止联网应用、排除应用、HTTPS 流量检查(含 CA 证书页)、出站代理、网络诊断、AI 分析(含全部入口)。

## 4. 可复用资产与复用策略

| 能力 | 现有资产来源 | 复用策略(复制独立使用 / 独立新文件) |
|---|---|---|
| 上游 DoH 传输 | `vpn/DnsLatencyTester.kt` 中的 DoH 通信实现 | **直接复制独立使用**:新建 `express/transport/ExpressDohTransport.kt`,不修改 `DnsLatencyTester.kt` |
| 上游 Plain/DoT 传输 | `vpn/PlainDnsTransport.kt`、`vpn/DotTransport.kt` | **直接复制独立使用**:新建 `express/transport/ExpressPlainDnsTransport.kt`、`ExpressDotTransport.kt`,隔离底层网络变更 |
| 阻断应答与报文处理 | `vpn/DnsMessageUtils.kt` | **直接复制独立使用**:新建 `express/engine/ExpressDnsMessageUtils.kt`,独立保障极速模式 DNS 报文编解码与 TTL patch |
| 前台通知构建 | `notification/VpnNotificationBuilder.kt` | **直接复制独立使用**:新建 `express/notification/ExpressNotificationBuilder.kt`,独立定制极速通知与兼容分发,旧通知类零修改 |
| 主界面与功能卡片 UI | `ui/MainScreenContent.kt`、`ui/FeatureHubScreen.kt` | **直接复制独立使用**:新建 `express/ui/ExpressMainScreen.kt`、`ExpressFeatureHubScreen.kt`,物理移除全隧道功能,旧 UI 文件零修改 |
| 规则判定逻辑 | `vpn/DomainPolicyEngine.kt`、`BlockRuleMatcher` 等 | **独立适配引入**:在 `express/engine/` 下独立装配判定接口,复用底层只读数据结构或独立规则判定副本 |
| 订阅规则 DTRI 读取 | `vpn/MappedSubscriptionRuleIndex.kt` | **安全只读复用**:纯 Kotlin mmap 只读模型,无需修改文件 |
| 规则加载管线 | Room 规则库 + 规则缓存模型 | **复用数据源**:极速模式直接读取现有 Room 规则库,服务内部独立管理规则同步触发 |
| DNS 缓存持久化 | Room `DnsCacheDao` 与数据表 | **复用存储层**:极速模式直接向现有 Room 写入缓存,缓存查看页面直接复用 DAO 分页查询 |
| 日志与健康监测 | `DnsLogger`、`RaceLogger`、`BootstrapLogger` | **直接引用**:作为标准日志汇聚点写入数据,不触碰旧逻辑 |

**全新开发与独立实现**:TUN 数据面编解码、DNS 查询编排器、极速 TCP 53 终结器、ExpressVpnService、独立 UI 页面。预估新增/复制约 2500~3500 行 Kotlin,均集中于独立的 `express` 包下,旧有代码仅需最少量的单点路由分发。

## 5. 阶段总览(6 个阶段)

| 阶段 | 主题 | 核心产出 | 前置依赖 |
|---|---|---|---|
| 一 | 数据面编解码层 | `ExpressPacketCodec`、`PublicDnsHijackList` + JVM 测试(纯新增独立文件) | 无(纯新增) |
| 二 | DNS 引擎与独立传输层 | 独立复制 `ExpressDohTransport`、`ExpressPlainDnsTransport`、`ExpressDotTransport`、`ExpressDnsMessageUtils`、新增 `ExpressDnsEngine`、`ExpressUpstreamDispatcher`、`ExpressTcpDnsHandler` + JVM 测试(旧文件零修改) | 阶段一 |
| 三 | 极速 VPN 服务与系统集成 | `ExpressVpnService`、`ExpressTunnelManager`、`ExpressVpnController`、独立复制 `ExpressNotificationBuilder`、`ExpressVpnIntents`、Manifest 注册 | 阶段二 |
| 四 | 模式框架与极简路由分发 | `AppWorkMode.EXPRESS`、独立 `ExpressWorkModeCard`、独立 `ExpressModeLauncher`、minSdk 24 (维持 arm64)、低版本 API 兼容,旧入口仅保留单行委托分流 | 阶段三 |
| 五 | 极速独立 UI 视图层 | 独立新建 `ExpressMainScreen`、`ExpressFeatureHubScreen`、`ExpressNavigation` 等,直接复制现有 UI 结构并在独立文件中物理剔除 9 项功能,旧 UI 文件零改动 | 阶段四 |
| 六 | 配置迁移、文档与整体验收 | 独立配置读取辅助、README/docs、多版本验收矩阵与全流程回归 | 阶段五 |

> 排序原则:阶段一~三为纯新增(`express` 包闭环,旧代码零修改,每个提交均可运行);阶段四落地极简模式路由后极速端到端可用;阶段五通过独立 UI 文件彻底隔离视图呈现;阶段六做收尾与全量验收。

## 6. 各阶段详细计划

### 阶段一:数据面编解码层(纯 Kotlin 基础库)

**目标**:提供 TUN 收发包的解析与构建能力,JVM 可测,零 Android 依赖,完全在独立新文件中实现,不触碰现有代码。

**涉及范围**:新增 `express/engine/` 包;`app/src/test/`。

**具体工作**:

1. `ExpressPacketCodec.kt`(~400 行,纯新增):
   - IPv4 解析:version/IHL 校验、总长、协议号、源/目的地址;识别分片(非首片丢弃,首片含 DF 处理);
   - IPv6 解析:固定头 + 逐跳扩展头跳过,识别上层协议 UDP/TCP;
   - UDP 头:源/目的端口、长度、校验和;**目的端口 53** 识别为 DNS 查询;
   - TCP 头(服务于 DNS-over-TCP 及非 53 端口兜底):源/目的端口、seq/ack、标志位、窗口;
   - 非 53 端口快速拒绝:针对进入 TUN 的非 53 端口 TCP 报文(如发往劫持 IP 的 443/853 端口)快速回写 TCP RST,避免外部连接握手死锁超时;丢弃其他非 DNS 异常报文;
   - 应答包构建:IP(v4/v6)+ UDP 头 + DNS 载荷,校验和计算(IPv4 头校验和、UDP 校验和含伪首部、IPv6 伪首部)、IP ID 生成、TTL patch;
   - 缓冲区策略:复用 buffer、避免逐包分配(老设备性能关键)。
2. `PublicDnsHijackList.kt`(~60 行,纯新增):约 20 个常见公共 DNS IPv4(8.8.8.8/8.8.4.4、1.1.1.1/1.0.0.1、9.9.9.9/149.112.112.112、208.67.222.222/220.220、223.5.5.5/223.6.6.6、119.29.29.29、114.114.114.114/115.115、180.76.76.76、77.88.8.8/8.1、94.140.14.14/15、185.228.168.9/169.9、64.6.64.6/65.6 等)+ 约 8 个 IPv6(2001:4860:4860::8888/8844、2606:4700:4700::1111/1001 等),带来源注释;供阶段三路由配置消费。
3. JVM 单元测试:已知报文向量往返、校验和正确性(标准向量)、非 53 端口 TCP RST 构造、畸形包鲁棒(截断/越界/版本错)、IPv6 扩展头跳过、TTL patch 幂等。

**交付与验收**:测试全绿;`git status` 仅新增文件;对现有代码零修改。

**提交**:`feat(express): 新增极速模式数据面包编解码与公共 DNS 劫持清单`

### 阶段二:DNS 引擎与独立传输层

**目标**:完成极速模式的查询处理管线与上游分发。通过复制现有成熟逻辑到新文件实现传输层与报文处理独立化，**严禁修改现有 `DnsLatencyTester.kt` 等旧文件**，实现极速模式与旧模式在底层传输上的物理隔离。

**涉及范围**:新增 `express/engine/`、`express/transport/`;`app/src/test/`。现有文件零修改。

**具体工作**:

1. `express/transport/ExpressDohTransport.kt`(~160 行,新文件,复制独立使用):
   - **直接复制 `vpn/DnsLatencyTester.kt` 中的 DoH POST 客户端实现**并适配为传输组件(OkHttp、`application/dns-message`、bootstrap 地址解析、protect 回调绑定);
   - **完全不修改 `DnsLatencyTester.kt` 现有文件**,避免对既有测速逻辑产生任何偶发影响或接口共用包袱。
2. `express/transport/ExpressPlainDnsTransport.kt` 与 `ExpressDotTransport.kt`(~200 行,新文件,复制独立使用):
   - 直接复制现有的 `PlainDnsTransport` 与 `DotTransport` 逻辑,独立构建极速模式传输类;
   - 增加独立 EDNS0 缓冲大小协商(1232~1400 字节)与超时控制,与普通模式传输实现彻底解耦,后续升级不互相干扰。
3. `express/engine/ExpressDnsMessageUtils.kt`(~180 行,新文件,复制独立使用):
   - 直接复制现有 `vpn/DnsMessageUtils.kt` 中所必需的 DNS 协议解析、阻断报文合成(NXDOMAIN/REFUSED/A记录伪造)、TTL 偏移计算与响应校验逻辑;
   - 在新文件中独立演进,不改动旧工具类。
4. `express/engine/ExpressDnsEngine.kt`(~350 行,纯新增):
   - 查询管线(对齐 Go 顺序)——`_dns.resolver.arpa` 返回 NXDOMAIN(DDR 反制)→ 规则开关(`isDomainRulesEnabled`)→ 判定(依赖注入判定接口,委托底层规则库)→ 命中按 `BlockResponseMode` + `ExpressDnsMessageUtils` 构建阻断应答 → 未命中走 Room 缓存查询 → `ExpressUpstreamDispatcher`;
   - 非 A/AAAA 类型照常转发;统计计数(查询/拦截/缓存命中/延迟);`ProtectSocketProvider` 接口由服务注入;引擎自身不依赖 android.*,完全在 JVM 可测。
5. `express/engine/ExpressUpstreamDispatcher.kt`(~300 行,纯新增):
   - 按 `DnsResolutionMode` 分发——SINGLE 直发;PARALLEL_RACE 协程竞速(首个有效响应胜出,其余取消,在协程取消回调中主动 close 底层 Socket,立即释放 IO 线程);PRIMARY_BACKUP 依次 failover;SMART_PREDICTION 首版按竞速处理;
   - 协议调度统一分派到上述 `Express*Transport` 独立传输层;竞速与引导日志写入现有 Logger;响应合法性严格校验。
6. `express/engine/ExpressTcpDnsHandler.kt`(~350 行,纯新增):
   - 极简 DNS-over-TCP 终结器——三次握手应答、对端序号/确认号跟踪、载荷重组、2 字节长度分帧后交引擎、应答分段回写、FIN/RST 处理、基础重传定时;
   - 核心能力独立交付,保障客户端在极少数因响应超长触发 TC 标志重试时不超时卡死。
7. JVM 单元测试:判定矩阵、四种策略分发(假传输层)、竞速取消与 Socket 及时释放、缓存命中/过期、TCP 握手与分帧。

**交付与验收**:测试全绿;「Go↔Kotlin 语义对齐清单」逐项复核;现有代码零修改。

**提交**:`feat(express): 新增极速 DNS 引擎、独立上游传输与 DNS-over-TCP 处理`

### 阶段三:极速 VPN 服务与系统集成(express 包自闭环)

**目标**:数据面 + 引擎装配成可运行的独立 VPN 服务。前台通知、隧道管理与控制器全部采用独立新文件或复制独立实现，本阶段结束时极速模式完整可用但**尚无 UI 入口**(纯新增,不影响现有行为)。

**涉及范围**:新增 `express/`、`express/notification/`;`AndroidManifest.xml` 注册服务。

**具体工作**:

1. `express/notification/ExpressNotificationBuilder.kt`(~180 行,新文件,复制独立使用):
   - **直接复制 `notification/VpnNotificationBuilder.kt` 的核心构建逻辑**,为极速模式量身定制前台通知(独立展示「极速模式运行中」、DNS 服务器摘要,去除网速与应用流量展示);
   - 针对 Android 7+ 做好版本兼容分支(API < 26 不使用 NotificationChannel);
   - **完全不修改旧有的 `VpnNotificationBuilder.kt`**,让旧模式通知逻辑保持独立。
2. `express/ExpressVpnService.kt`(~300 行,纯新增):
   - 继承 `VpnService` + START_STICKY;`onStartCommand` 动作分发(START/STOP/REFRESH_CONFIG/SYNC_RULES/CLEAR_CACHE);
   - TUN 建立——地址 10.0.0.2/30 + fd00:abcd::2/64、DNS 10.0.0.1/fd00:abcd::1,**路由仅含** 10.0.0.0/30、fd00:abcd::1/128 与劫持清单 /32(IPv6 劫持项仅在启用且有物理 IPv6 时添加);
   - `addDisallowedApplication(self)`;MTU 1400;前台通知调用独立的 `ExpressNotificationBuilder`;`startForeground` 按版本分支(<29 不带 type);`onRevoke` 清理。
3. `express/ExpressTunnelManager.kt`(~300 行,纯新增):
   - TUN 读写循环(读线程 → codec → 协程池分发;UDP:53 → 引擎,TCP:53 → TCP 处理器)→ 写回;
   - `protect()` 注入;启动前等待规则缓存就绪;独立封装 IPv6 物理网络探测(复制现有探测设计,在新文件中独立实现);生命周期管理与崩溃兜底。
4. `express/ExpressVpnController.kt`(~120 行,纯新增):
   - 提供 `StateFlow<Boolean>` isRunning、start/stop 方法,专门供极速模式独立 UI 消费;
   - 缓存无缝衔接:直接基于 Room 持久化,不修改旧模式的任何状态控制器。
5. `express/ExpressVpnIntents.kt`(~80 行,纯新增):
   - 独立定义极速模式专用 Action 常量与 Intent 构造辅助方法,与普通模式 Intent 彻底解耦。
6. Manifest 注册:注册 `.express.ExpressVpnService`(`BIND_VPN_SERVICE` + specialUse "vpn")。

**交付与验收**:adb 手动拉起/停止服务,规则命中与放行、缓存、日志在真机/模拟器验证;普通/服务器模式行为与代码零变化。

**提交**:`feat(express): 新增极速模式独立 VPN 服务与通知集成`

### 阶段四:模式框架与极简路由分发

**目标**:三模式枚举与选择卡片就绪,建立对极速模式的极简路由桥接;支持 Android 7(API 24, 64 位)设备安装与兼容。**对旧 Activity 仅做最小必要的单行委托分流，核心交互与启动逻辑全部落在独立新文件中**。

**涉及范围**:`ui/mode/`、`express/ui/`、`MainActivity.kt`(微改路由)、`SettingsRouteActivity.kt`(微改路由)、`app/build.gradle.kts`、`AndroidManifest.xml`。

**具体工作**:

1. `AppWorkMode.kt`:新增 `EXPRESS("express")`;增加 `minApiLevel`(NORMAL/DNS=29、EXPRESS=24);文案(badge「极速」、summary「Kotlin 原生轻量实现,DNS 解析加速与规则过滤,支持 Android 7+ (64 位)」)。
2. `express/ui/ExpressWorkModeCard.kt`(~120 行,新文件,复制独立使用):
   - 直接参考/复制现有 `WorkModeCard` 的卡片样式与布局逻辑,独立实现极速模式工作卡片;
   - 独立封装极速模式的环境检查(Android 7+、64 位架构)与点击行为,**不侵入修改原 `WorkModeCard.kt`**。
3. `express/ExpressModeLauncher.kt`(~150 行,纯新增):
   - 独立封装极速模式的互斥切换、服务停止(停止旧 `DnsVpnService` 与 `DnsModeService`)、权限申请与启动流程;
   - `MainActivity` 与 `SettingsRouteActivity` 在模式切换处理分支中,**仅以单行形式委托调用 `ExpressModeLauncher`**,原有普通模式与服务器模式的既有启动和恢复逻辑保持原封不动。
4. `express/ExpressSettingsRefresher.kt`(~100 行,纯新增):
   - 极速模式下的 DNS 设置变更热刷新统一通过该独立类组装 `ExpressVpnIntents.REFRESH_CONFIG` 发送;旧有的 `RuntimeDnsSettingsRefresher` 保持独立,仅做极简的模式分发。
5. 构建配置与低版本基座:
   - `minSdk 29→24`;架构维持 `arm64-v8a`(避免 32 位设备缺失 libgojni 导致无法安装);
   - 通知兼容:AppNotificationChannels 与后台 Worker 增加 `SDK_INT >= O` 门控,避免在 API 24/25 上因缺少 NotificationChannel 崩溃;
   - 统一使用 `ContextCompat.startForegroundService` 与版本化 `startForeground`(<29 不传 type)。
6. 系统快捷入口:新增独立的极速模式快捷磁贴或在 `DitingTileService` 中极简分发到 `ExpressVpnController`。

**交付与验收**:API 24 模拟器完整走通极速模式(选择屏→授权→启停→过滤);普通/服务器在 <29 设备置灰不可用;现有两模式代码结构无侵入,回归正常。

**提交**:`feat(mode): 新增极速模式选择卡片与独立启动分流器`

### 阶段五:极速独立 UI 视图层(彻底解耦)

**目标**:贯彻“新文件实现、复制复用、物理隔离”原则，**不修改现有 `FeatureHubScreen.kt`、`MainScreenContent.kt` 等旧 UI 文件**，直接复制并创建极速模式专属独立的 UI 界面，在文件物理结构上天然剔除 9 项全隧道专属功能。

**涉及范围**:新增 `express/ui/` 包;主界面导航入口做极简模式视图切换。旧 UI 文件零修改。

**具体工作**:

1. `express/ui/ExpressMainScreen.kt`(~400 行,新文件,复制独立使用):
   - **直接复制 `ui/MainScreenContent.kt` 的核心视觉布局与交互设计**(仪表盘头部、中央电源启停大卡片、DNS 提供商信息、快速日志摘要与运行状态卡片);
   - 界面状态直接绑定 `ExpressVpnController`;
   - **在独立文件中物理去除**普通模式中依赖全隧道的控制项(如「绕过局域网」快捷开关、应用流量实时卡片等);
   - **旧有的 `MainScreenContent.kt` 保持完全不变**,普通模式继续使用旧页面,零修改零风险。
2. `express/ui/ExpressFeatureHubScreen.kt`(~350 行,新文件,复制独立使用):
   - **直接复制 `ui/FeatureHubScreen.kt` 的卡片网格布局、分组体系与交互动画**;
   - **在独立文件中物理删除 9 项不支持的高级功能卡片**:覆写名单、应用流量统计、应用独立规则、禁止联网应用、排除应用、HTTPS 流量检查、出站代理、网络诊断、AI 分析;
   - 仅保留并紧凑排列极速模式支持的功能(DNS 服务商选择、解析模式、规则控制、DNS 缓存、请求日志、悬浮日志等);
   - **不需要编写侵入式的动态门控系统**,卡片天然纯净,代码直观清晰,彻底避免旧文件臃肿;旧 `FeatureHubScreen.kt` 原封不动。
3. `express/ui/ExpressNavigation.kt`(~150 行,纯新增):
   - 独立定义极速模式的主界面底部导航项(BottomBar)与 Tab 映射;
   - 仅包含极速模式所需的 Tab 目的地,不修改现有 `BottomBarDestination.kt`。
4. 共享详情页的独立与复用:
   - 对于完全通用的功能页(DNS 提供商配置、规则黑白名单、缓存详情页等),极速模式独立导航直接导航复用现有 Screen,无需重复复制;
   - 对于含全隧道过滤项的页面(如 `RequestLogScreen.kt` 中的 HTTPS 流量类型筛选),直接复制新建 `express/ui/ExpressRequestLogScreen.kt`,物理移除 HTTPS 相关过滤选项,不改动旧日志页面。
5. 根视图极简切换:
   - 在主界面根组件中根据当前 `AppWorkMode`,如果是普通/服务器模式则渲染原版 `MainScreenContent`,如果是极速模式则渲染 `ExpressMainScreen`,实现根部干净利落的视图解耦。

**交付与验收**:极速模式下 9 项功能入口物理不存在且不可直达,UI 流畅纯净;普通模式 UI 与现有版本像素级一致(旧 UI 代码零变动)。

**提交**:`feat(express-ui): 新增极速模式专属独立主界面与功能聚合页`

### 阶段六:配置迁移、文档与整体验收

**目标**:收尾与全量验证,形成可发布状态。旧模式配置导入导出逻辑与极速模式解耦。

**涉及范围**:`express/config/`、`README.md`、`docs/`、全量测试矩阵。

**具体工作**:

1. 配置导入导出:
   - 新增 `express/config/ExpressConfigAdapter.kt`,专门负责极速模式下的配置安全导入导出;
   - 确保极速模式下导出的配置纯净,导入时不触碰被移除功能的本地存储;普通模式旧导入导出逻辑保持独立。
2. 文档:
   - 更新 README 中的模式支持矩阵(极速 Android 7+ ARM64 / 普通·服务器 Android 10+);
   - 编写 `docs/development/express-mode-architecture.md`,详细记录“独立新文件实现、零污染旧代码”的架构设计、数据面实现、DNS 劫持清单维护与取舍说明。
3. 验收矩阵测试:
   - 模拟器/真机覆盖 API 24/29/33(+36) (arm64-v8a);
   - 核心链路:极速模式启停、DNS 解析加速(4 种模式)、规则命中与放行、多档缓存命中与持久化、竞速与日志写入、三模式互斥无损切换;
   - 降级场景:<29 设备存量模式配置平滑处理;低内存/老旧设备性能与功耗抽查。
4. 全量回归:
   - 针对普通模式与服务器模式执行全流程自动化与手工回归,由于旧代码改动极小,回归验证更加聚焦且风险可控;
   - `./gradlew test` 全绿;`build_apk.bat` 打包顺利通过。

**提交**:`docs: 补充极速模式独立架构文档与整体验收验证`

## 7. 跨阶段约定

- **新文件优先与源码隔离原则**:极速模式的核心功能、传输层、隧道服务、控制器、通知和 UI 一律新建独立文件;对于可以复用的现有代码、UI、逻辑设计或流量处理方案，优先直接复制并在新文件中独立使用与适配，**严禁修改原代码后让新旧模式共用同一套实现**。
- **旧代码独立性与零回归保障**:旧模式 KT 文件和旧模式代码必须保持完全独立,旧文件修改点严格限制在最外层的极简单点分流(如模式启动委托),杜绝侵入式逻辑改造。
- **单文件行数红线**:每个新建的 Kotlin 代码文件必须严格遵守不超过 600 行(AGENTS.md 要求),职责单一,避免大文件。
- **提交规范**:按阶段独立提交,提交信息使用中文,遵循 Conventional Commits 并保持历史风格,简洁准确;禁止提交未完成修改。
- **极速引擎 JVM 可测性**:极速引擎新代码(JVM 可测部分)不依赖 android.*,保证单元测试独立健壮。
- **性能与资源控制**:逐包处理避免内存分配放大;读循环单线程 + 协程池分发;无全隧道流量统计,息屏零额外轮询,天然极低功耗。

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 代码复制带来的维护考量 | 极速模式(轻量 DNS 窄路由)与普通模式(全隧道 Go 代理)定位与演进诉求截然不同;物理隔离独立演进带来的「零回归风险」和「低版本高自由度适配」价值远高于强行抽象共用所产生的耦合成本与复杂性 |
| DNS-over-TCP 极简栈正确性 | 仅面向本机解析器、DNS 尺寸;完备脚本化测试;上游默认启用 EDNS0(1232 字节),绝大多数大响应在 UDP 直接承载;TCP 53 作为关键能力严格测试交付,确保客户端在极少数分段重试时不会死锁超时 |
| Android 7 OEM 对 VPN DNS 的兼容差异 | 验收矩阵覆盖 API 24 真机/模拟器;劫持清单与虚拟 DNS 双通道互为兜底 |
| minSdk 24 引入低版本 API 违规 | 阶段四集中 lint NewApi 审计 + 运行时门控;极速专属代码在设计上即面向 API 24 编写,旧模式专属代码仅在 >=29 执行 |
| 架构兼容与安装保障 | 维持 arm64-v8a 过滤,不混入无 32 位 .so 的 armeabi-v7a 声明,确保安装合规;覆盖 API 24+ ARM64 主流设备 |
| 老设备性能与发热 | 编解码零分配策略、窄路由天然低负载;阶段六专门抽查低端机型内存占用与能耗表现 |

## 9. 验收标准(总体)

1. **架构隔离性**:极速模式实现自成体系,绝大部分代码集中于 `express/` 包下;旧模式 KT 文件几乎无改动,新旧模式完全不共用可能带来副作用的内部实现类。
2. **系统与设备支持**:Android 7(API 24, 64 位)设备可正常安装并流畅运行极速模式;普通/服务器模式在 Android 10 以下正确置灰且提示清晰。
3. **三模式互斥切换**:普通模式、极速模式、服务器模式三向切换无缝互斥,启停干净,设置数据无损保留。
4. **核心能力对齐**:极速模式在独立代码下完整达成核心 DNS 网络管理能力:4 种解析模式、规则过滤(订阅+黑白名单)、多档缓存、日志记录、悬浮日志、前台通知与快捷磁贴。
5. **界面呈现纯净**:极速模式专属 UI 页面中 9 项全隧道专属功能物理剔除,无死链、无多余选项;普通模式 UI 100% 保持现状。
6. **存量稳定性**:普通模式与服务器模式全流程回归测试 100% 通过,既有代码逻辑不受极速模式引入的影响。
