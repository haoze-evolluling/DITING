// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppL10nZh extends AppL10n {
  AppL10nZh([String locale = 'zh']) : super(locale);

  @override
  String get ruleTestTitle => '规则测试';

  @override
  String get ruleTestEnterSubtitle => '输入域名查看为何被拦截或放行';

  @override
  String get ruleTestIntro => '输入域名，立即查看判定结果、命中规则与改写结果。判定逻辑与引擎完全一致。';

  @override
  String get ruleTestDomainLabel => '域名';

  @override
  String get ruleTestDomainHint => '例如 ads.example.com';

  @override
  String get ruleTestQtype => '查询类型';

  @override
  String get ruleTestRun => '开始测试';

  @override
  String get ruleTestResultTitle => '判定结果';

  @override
  String get ruleTestActionBlock => '拦截';

  @override
  String get ruleTestActionAllow => '白名单放行';

  @override
  String get ruleTestActionPass => '放行';

  @override
  String get ruleTestMatchedRule => '命中规则';

  @override
  String get ruleTestReason => '原因';

  @override
  String get ruleTestRewriteTitle => '改写结果';

  @override
  String get ruleTestNoRewrite => '无改写';

  @override
  String get ruleTestInvalidDomain => '请输入有效域名';

  @override
  String get ruleTestFailed => '规则测试失败，请稍后重试';

  @override
  String get ruleTestEmptyHint => '测试结果会显示在这里';

  @override
  String get subscriptionHealthOk => '正常';

  @override
  String get subscriptionHealthUnchanged => '无变化';

  @override
  String get subscriptionHealthCached => '使用缓存';

  @override
  String get subscriptionHealthFailed => '更新失败';

  @override
  String get blockPauseTitle => '临时暂停';

  @override
  String get blockPauseEntrySubtitle => '临时跳过拦截 / 仅白名单';

  @override
  String get blockPauseIntro => '暂停后跳过全部拦截，DNS 仍照常解析，到期自动恢复。仅白名单模式只放行显式允许的域名。';

  @override
  String get blockPauseRunningLabel => '暂停中，剩余';

  @override
  String get blockPauseInactive => '当前未暂停，拦截正常生效';

  @override
  String get blockPauseResume => '立即恢复';

  @override
  String blockPausePresetButton(int minutes) {
    return '暂停 $minutes 分钟';
  }

  @override
  String get blockPauseAllowlistTitle => '仅白名单模式';

  @override
  String get blockPauseAllowlistSubtitle => '只放行显式允许的域名，其余全部拦截';

  @override
  String get blockPauseFailed => '设置失败，请稍后重试';

  @override
  String get appTitle => '谛听 DITING';

  @override
  String get uiBack => '返回';

  @override
  String get uiCancel => '取消';

  @override
  String get uiClearSearch => '清除搜索';

  @override
  String get uiClose => '关闭';

  @override
  String get uiHidePassword => '隐藏密码';

  @override
  String get uiMore => '更多';

  @override
  String get uiNoSearchResults => '无搜索结果';

  @override
  String get uiReset => '重置';

  @override
  String get uiSearch => '搜索';

  @override
  String get uiShowLess => '收起';

  @override
  String get uiShowMore => '展开';

  @override
  String get uiShowPassword => '显示密码';

  @override
  String get uiSort => '排序';

  @override
  String get uiSubmit => '提交';

  @override
  String get languageTitle => '语言设置';

  @override
  String get languageInterfaceSection => '界面语言';

  @override
  String get languageInterfaceFooter => '选择应用界面语言。「跟随系统」会跟随设备语言，非中文或英文的系统显示中文。';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get commonFollowSystem => '跟随系统';

  @override
  String get commonSelectAll => '全选';

  @override
  String get commonClear => '清除';

  @override
  String get commonInvertSelection => '反选';

  @override
  String get commonFilter => '过滤';

  @override
  String get commonSort => '排序';

  @override
  String get commonSave => '保存';

  @override
  String get commonDiscard => '不保存';

  @override
  String get commonSaveChangesTitle => '保存更改？';

  @override
  String get commonSaveChangesMessage => '你的选择还没保存。保存后离开，还是放弃这些修改？';

  @override
  String commonSaveChangesMessageFor(String name) {
    return '「$name」的选择还没保存。保存后离开，还是放弃这些修改？';
  }

  @override
  String get commonGrantPermission => '去授权';

  @override
  String get palettePurple => '鸢尾紫';

  @override
  String get paletteBlue => '睡莲蓝';

  @override
  String get paletteCyan => '池水青';

  @override
  String get paletteGreen => '柳叶绿';

  @override
  String get paletteOrange => '暮光赭';

  @override
  String get paletteRed => '罂粟红';

  @override
  String get palettePink => '暮霞粉';

  @override
  String get paletteGold => '麦穗金';

  @override
  String get themeModeLight => '浅色模式';

  @override
  String get themeModeDark => '深色模式';

  @override
  String get appListUnavailable => '读不到应用列表';

  @override
  String get appListFilterAll => '全部应用';

  @override
  String get appListFilterSystem => '系统应用';

  @override
  String get appListFilterUser => '用户应用';

  @override
  String get appListFilterSelected => '已勾选应用';

  @override
  String get appListSortLabelAsc => '应用名称 A-Z';

  @override
  String get appListSortLabelDesc => '应用名称 Z-A';

  @override
  String get appListSortPackageAsc => '包名 A-Z';

  @override
  String get appListSortPackageDesc => '包名 Z-A';

  @override
  String get appListNotRegistered => '未注册';

  @override
  String appListChannelUnavailable(String detail) {
    return '应用列表通道不可用：$detail';
  }

  @override
  String appListReadFailed(String detail) {
    return '读取应用列表失败：$detail';
  }

  @override
  String appListReadFailedCode(String code) {
    return '读取应用列表失败（$code）';
  }

  @override
  String dbWriteUnhealthy(int dropped, int failures) {
    return '日志写入异常：已丢弃 $dropped 条、打开失败 $failures 次，可在「故障排查」查看详情';
  }

  @override
  String get agreementDeclinedTitle => '已拒绝使用须知';

  @override
  String get agreementDeclinedMessage =>
      '未同意使用须知与免责声明，无法继续使用谛听。你可以直接退出应用，或重新查看条款后再决定。';

  @override
  String get agreementReviewAgain => '重新查看';

  @override
  String get agreementTitle => '使用须知与免责声明';

  @override
  String get agreementDecline => '不同意并退出';

  @override
  String get agreementAccept => '同意并继续';

  @override
  String get agreementMessage =>
      '软件说明\n谛听是一款专注于本地 DNS 解析优化与网络规则过滤的开源工具。提供三种工作模式：普通模式（全隧道深度管控）、极速模式（Go 引擎 + DNS 窄路由）与独立服务器模式（局域网免 VPN 服务）。本软件完全在设备本地闭环运行，无任何远程数据上传与隐私追踪。\n\n运行机制与注意事项\n普通模式与极速模式依赖 Android 本地 VPN 接口接管 DNS 解析，不连接任何远程 VPN 服务器；独立服务器模式无需 VPN 权限，直接监听本地 1053 端口供局域网设备接入。规则与日志完整保存在本机，启用高级扩展功能前请了解其具体影响。\n\n免责条款\n本软件按现状提供。使用者须遵守相关法律法规，自行确认规则与上游解析来源的合法性及安全性。严禁将本软件用于任何违法用途；使用者因自行配置或使用本软件所产生的后果由使用者自行承担。';

  @override
  String get homeProviderSingleLabel => '解析服务商';

  @override
  String get homeProviderRaceLabel => '竞速服务商';

  @override
  String get homeChartEmptyLabel => '还没有采到样本';

  @override
  String durationHours(int hours) {
    return '$hours 小时';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get dashboardDetailTooltip => '详情';

  @override
  String get dashboardEmptyLabel => '仪表盘还没有卡片';

  @override
  String get dashboardEmptyDescription => '进入编辑模式，从「添加卡片」里挑几个放上来。';

  @override
  String get dashboardEnterEditMode => '进入编辑模式';

  @override
  String get dashboardEditHint => '拖动手柄排序，点右上角移除；改完点右上角「完成」。';

  @override
  String get dashboardAllRemovedLabel => '卡片都移除了';

  @override
  String get dashboardAllRemovedDescription => '点下面的「添加卡片」挑一个。';

  @override
  String get dashboardAddCard => '添加卡片';

  @override
  String get providerSheetSingleTitle => '选择解析服务商';

  @override
  String get providerSheetRaceTitle => '选择竞速服务商';

  @override
  String get providerSheetSingleOptions => '可选服务商';

  @override
  String get providerSheetRaceMinimum => '至少选 2 个';

  @override
  String get providerSheetManage => '管理服务...';

  @override
  String get providerSheetVisibility => '服务显示...';

  @override
  String get providerSheetSingleFooter => '延迟取自上一次解析的健康记录，不是实时值。';

  @override
  String get providerSheetRaceFooter => '竞速模式下每个查询会并发发往所有选中服务商。';

  @override
  String get powerButtonStop => '停止';

  @override
  String get powerButtonStart => '开启';

  @override
  String get powerButtonStarting => '启动中';

  @override
  String get homeEditDashboard => '编辑仪表盘';

  @override
  String get homeDone => '完成';

  @override
  String get homeSwitchWorkMode => '切换工作模式';

  @override
  String get homeTitleNormal => '谛听 · 普通';

  @override
  String get homeTitleServer => '谛听 · 服务器';

  @override
  String get homeTitleExpress => '谛听 · 极速';

  @override
  String get logRequestsOverview => '请求概览';

  @override
  String get logTodayRequests => '今日请求';

  @override
  String get logPassed => '通过';

  @override
  String get logFiltered => '过滤';

  @override
  String get logCacheHits => '缓存命中';

  @override
  String get logHighlights => '重点记录';

  @override
  String get logBlocked => '过滤拦截';

  @override
  String get logFailed => '异常失败';

  @override
  String get logBypassed => '旁路直连';

  @override
  String get logOffModeTitle => '解析服务概况';

  @override
  String get logCacheEntries => '有效缓存';

  @override
  String get logCacheHitsTotal => '累计缓存命中';

  @override
  String get logRaceRequests => '并发竞速请求';

  @override
  String get logBootstrapAttempts => 'Bootstrap 尝试';

  @override
  String get logRecentRequests => '最近请求';

  @override
  String get logRecentRequestsEmpty => '暂无请求日志';

  @override
  String get logRecentBlocked => '最近拦截与错误';

  @override
  String get logRecentBlockedEmpty => '暂无拦截或错误记录';

  @override
  String get logCacheHotspots => '缓存热点';

  @override
  String get logCacheHotspotsEmpty => '暂无有效缓存';

  @override
  String logExpiresIn(String duration) {
    return '$duration 后过期';
  }

  @override
  String logTimes(String count) {
    return '$count 次';
  }

  @override
  String get logRaceWinners => '竞速胜出';

  @override
  String get logRaceWinnersEmpty => '暂无竞速数据';

  @override
  String logAverageWinLatency(String latency) {
    return '平均胜出耗时 $latency';
  }

  @override
  String get logBootstrapDnsEmpty => '暂无 Bootstrap 数据';

  @override
  String logBootstrapRow(String ip, String latency, String percent) {
    return '$ip · 成功 $percent · $latency';
  }

  @override
  String get logRuleBlocks => '规则拦截';

  @override
  String get logRuleBlocksEmpty => '暂无规则拦截数据';

  @override
  String logShareRow(String percent, String status) {
    return '$status · 占全部请求 $percent';
  }

  @override
  String get logPrivacyMode => '隐私模式保护中';

  @override
  String get logLoggingOff => '日志已关闭';

  @override
  String get logPrivacyModeBody =>
      '重新开启日志后，仪表盘将从新产生的请求开始统计。当前各类解析服务与缓存热点均正常工作。';

  @override
  String get logPerfTitle => '解析效能概况';

  @override
  String get logTodayStats => '今日统计';

  @override
  String get logAverageLatency => '平均解析耗时';

  @override
  String get logNoTimingSamples => '— · 今日暂无计时样本';

  @override
  String logSampleValue(String count, String value) {
    return '$value · $count 个样本';
  }

  @override
  String get logCacheHitRate => '缓存命中率';

  @override
  String logCacheHitRateValue(String percent) {
    return '$percent · 分母为通过 + 失败';
  }

  @override
  String get logRaceSuccessRate => '竞速成功率';

  @override
  String get logBootstrapSuccessRate => 'Bootstrap 成功率';

  @override
  String logRateValue(String count, String latency, String percent) {
    return '$percent · $count 次 · $latency';
  }

  @override
  String get dashboardRestoreDefaults => '恢复默认';

  @override
  String get dashboardAllCardsAdded => '卡片都放上来了';

  @override
  String get dashboardAllCardsAddedDescription => '想减少卡片，请回到编辑模式点卡片右上角的移除。';

  @override
  String get dashboardAvailableCards => '可添加的卡片';

  @override
  String get dashboardOrderHint => '卡片顺序可在编辑模式下拖拽调整。';

  @override
  String get dashboardCardProviderDescription => '当前解析服务商，点开即可切换或调整竞速列表';

  @override
  String get dashboardCardResolutionDescription => '解析模式选择、一句话说明与当前生效的 DNS 地址';

  @override
  String get dashboardCardStatusDescription => '内核状态、运行时长、当前服务商与今日查询';

  @override
  String get dashboardCardSpeedDescription => '上下行实时速率曲线与今日累计流量';

  @override
  String get dashboardCardSiteLatencyDescription => '自定义 4 个站点的实测延迟，详情页可按分类测速';

  @override
  String get dashboardCardMemoryDescription => '本进程 PSS 与 Java / 原生堆构成';

  @override
  String get dashboardCardIntranetDescription => '当前局域网地址、监听状态与复制入口';

  @override
  String get intranetIpTitle => '内网 IP';

  @override
  String get intranetCopyAddress => '复制地址';

  @override
  String get intranetReading => '读取中…';

  @override
  String get intranetNoActiveNetwork => '无活动网络';

  @override
  String get intranetLanAccess => '局域网接入';

  @override
  String get intranetConnectHint => '连上 Wi-Fi 或以太网后这里会显示可用地址';

  @override
  String get memoryTitle => '内存信息';

  @override
  String get memoryJavaHeap => 'Java 堆';

  @override
  String get memoryNativeHeap => '原生堆';

  @override
  String get memorySystemAvailable => '整机可用';

  @override
  String get speedTitle => '网络速度';

  @override
  String get speedUpload => '上传';

  @override
  String get speedDownload => '下载';

  @override
  String get speedExpressNoStats => '极速模式不统计';

  @override
  String get speedNoChannel => '当前环境无速率通道';

  @override
  String get resolutionModeTitle => '解析模式';

  @override
  String get resolutionNoProvider => '未选择服务商';

  @override
  String get resolutionSingleSummary => '只用当前选中的服务商，最快但可用性取决于它。';

  @override
  String get resolutionSmartSummary => '按历史成功率挑一个，失败后自动换下一个。';

  @override
  String get resolutionParallelSummary => '同时向所有服务商发起，取最先返回的结果。';

  @override
  String get resolutionPrimaryBackupSummary => '主服务商优先，超时后才动备用。';

  @override
  String get siteLatencyTesting => '测速中…';

  @override
  String get siteLatencyNotTested => '尚未测速';

  @override
  String get siteLatencyTitle => '网络测速';

  @override
  String get siteLatencyRetest => '重新测速';

  @override
  String get commonFailed => '失败';

  @override
  String get siteLatencyNoReply => '无回包';

  @override
  String get statusTitle => '状态';

  @override
  String get statusUptime => '运行时长';

  @override
  String get statusActiveProvider => '当前服务商';

  @override
  String get statusNotSelected => '未选择';

  @override
  String get statusTodayQueries => '今日查询';

  @override
  String get statusDetailTitle => '状态详情';

  @override
  String get statusNotTiming => '未计时';

  @override
  String get statusCoreSection => '内核';

  @override
  String get statusWorkMode => '工作模式';

  @override
  String get statusCoreState => '内核状态';

  @override
  String get statusListenPort => '监听端口';

  @override
  String get statusNotListening => '未监听';

  @override
  String get statusProviderFooter => '延迟是该服务商的最近一次实测值，不是本机到目标的往返。';

  @override
  String get statusNoProviderHint => '还没有选择服务商。在服务商管理里挑一个，解析才会走真实上游。';

  @override
  String get statusTodayCounts => '今日计数';

  @override
  String get statusCountsFooter =>
      '计数从本次内核启动开始累计，重启或切换工作模式后归零；已在服务器模式里做的重置也只清计数，不动规则与缓存。';

  @override
  String get statusQueries => '查询';

  @override
  String get statusBlocked => '已拦截';

  @override
  String get statusAverageLatency => '平均时延';

  @override
  String get statusCacheHitRate => '缓存命中率';

  @override
  String get statusServerPortReady => '本机 DNS 端口可用，局域网设备可把它当作 DNS';

  @override
  String get statusTunnelActive => '本机流量已经过谛听，解析与规则都在生效';

  @override
  String get statusServerPortClosed => 'DNS 端口未监听，服务器模式当前不提供解析';

  @override
  String get statusCoreStopped => '内核未运行，本机流量按系统默认网络走';

  @override
  String get siteLatencySheetLatency => '延迟';

  @override
  String get siteLatencySheetCategory => '分类';

  @override
  String get siteLatencySheetTarget => '目标';

  @override
  String get siteLatencySheetAverage => '平均往返';

  @override
  String get siteLatencySheetMinMax => '最小 / 最大';

  @override
  String get siteLatencySheetJitter => '抖动';

  @override
  String get siteLatencySheetLoss => '丢包';

  @override
  String get siteLatencySheetDns => '解析地址';

  @override
  String get siteLatencySheetLastRun => '最近测速';

  @override
  String get siteLatencySheetNotTested => '尚未测速。点测速按钮开始测量。';

  @override
  String get siteLatencySheetNoReply => '三个回显请求都没有收到应答，可能是站点限流或当前网络不通。';

  @override
  String get siteLatencySheetFallbackFooter =>
      '系统 ping 不可用，这次数值来自 TCP 握手 / isReachable，衡量的是建连时延而不是 ICMP 回显，会略高于真实往返。';

  @override
  String get siteLatencySheetIcmpFooter =>
      '数值来自系统 ping 的 ICMP 回显（3 次取平均）。本应用自身流量不经过 VPN，测的是物理网络。';

  @override
  String get trafficStructureLive => '实时汇总';

  @override
  String get trafficStructureFocused => '重点流量结构';

  @override
  String get trafficStructureToday => '今日流量结构';

  @override
  String get trafficStructureBypass => '旁路';

  @override
  String get trafficStructureCache => '缓存';

  @override
  String get trafficStructureRaceRate => '竞速成功率';

  @override
  String get trafficStructureBootstrapRate => 'Bootstrap 成功率';

  @override
  String get trafficStructureBlockedShare => '拦截占比';

  @override
  String get trafficStructureBlockRate => '拦截率';

  @override
  String get trafficStructureCacheRate => '缓存率';

  @override
  String get dashboardSitesTitle => '仪表盘站点';

  @override
  String get dashboardSitesCardSection => '仪表盘卡片';

  @override
  String get dashboardSitesAtLeastOne => '卡片至少保留 1 个站点';

  @override
  String get dashboardSitesFooter => '这四张卡片用的是同一个仪表盘卡片，改动立刻生效；测速在详情页按分类手动触发。';

  @override
  String get trafficMonitorTitle => '流量监控';

  @override
  String get trafficMonitorToday => '今日代理流量';

  @override
  String get trafficMonitorLiveRate => '实时速率';

  @override
  String get trafficMonitorNoStats => '本模式不统计';

  @override
  String get memoryDetailTitle => '内存详情';

  @override
  String get memoryResample => '重新采样';

  @override
  String get memoryProcessPss => '本进程 PSS';

  @override
  String get memoryUnavailable => '不可用';

  @override
  String get memoryOther => '其它';

  @override
  String get memoryComposition => '进程构成';

  @override
  String get memoryCompositionFooter =>
      'PSS 按共享页的比例计入本进程，因此 Java 堆与原生堆之和小于 PSS，差额是代码、图形缓冲与共享库。';

  @override
  String get memoryOtherCode => '其它（代码 / 共享库）';

  @override
  String get memorySystemSection => '整机内存';

  @override
  String get memorySystemFooter => '整机占用 = 总量 - 可用量，包含系统与所有应用；本进程只是其中一份。';

  @override
  String get memorySystemUsed => '整机已用';

  @override
  String get memoryRecentPss => '最近 PSS';

  @override
  String get memorySampling => '正在采样…';

  @override
  String get memoryRecentPssCaption =>
      '打开本页后每 2 秒采样一次，最多保留 60 个点；曲线持续上扬说明有内存未释放。';

  @override
  String get memorySourceFooter =>
      '数据来自 ActivityManager 的 MemoryInfo；切到后台或系统回收后数值会明显下降。';

  @override
  String get siteLatencyDetailTitle => '测速详情';

  @override
  String get siteLatencyTestAll => '测全部';

  @override
  String get siteLatencyCustomSites => '自定义仪表盘站点';

  @override
  String get siteLatencyConnectivity => '站点连通性';

  @override
  String get siteLatencyTestingShort => '测速中';

  @override
  String get siteLatencyNoTest => '未测速';

  @override
  String get siteLatencyInProgress => '进行中';

  @override
  String get siteLatencyPending => '待测';

  @override
  String get siteLatencyAllReachable => '全部通畅';

  @override
  String get siteLatencyTestingEach => '正在逐个站点测速…';

  @override
  String get siteLatencyPickCategory => '选一个分类点测速，或点右上角测全部。';

  @override
  String get siteLatencyThisRun => '本次结果';

  @override
  String get siteLatencyReachable => '通畅';

  @override
  String get siteLatencyMeasuredSites => '已测站点';

  @override
  String get siteLatencyDetailFooter =>
      '每个站点发 3 个 ICMP 回显，取平均值；系统 ping 不可用时退回 TCP 握手，会标上 * 号，数值略高于真实往返。本应用自身流量不经过 VPN，测的是物理网络。';

  @override
  String get intranetDetailTitle => '内网 IP 详情';

  @override
  String get intranetRefresh => '刷新网络信息';

  @override
  String get intranetLocalAddress => '本机局域网地址';

  @override
  String get intranetUsableAsDns => '可作 DNS';

  @override
  String get intranetLocalOnly => '仅本机';

  @override
  String get intranetSameSubnetHint => '同网段设备把 DNS 指到这个地址即可走本机解析。';

  @override
  String get intranetNetworkOverview => '网络概况';

  @override
  String get commonEnabled => '已启用';

  @override
  String get commonDisabled => '未启用';

  @override
  String get intranetDnsServers => 'DNS 服务器';

  @override
  String get intranetInterfaces => '接口';

  @override
  String get intranetNoInterface => '系统没有报告活动网络接口，可能是飞行模式或未联网。';

  @override
  String get intranetAdapter => '网卡';

  @override
  String get intranetGateway => '网关';

  @override
  String get intranetPrivateDnsOff => '系统私人 DNS 未开启，解析请求由本机与代理按模式处理。';

  @override
  String get intranetNoDnsServer => '没有读到 DNS 服务器：接口未下发 DNS，或当前环境没有诊断通道。';

  @override
  String get intranetPrimaryDns => '首选';

  @override
  String get intranetPrivateDns => '私人 DNS';

  @override
  String get intranetPortFooter =>
      '端口只在服务启动时绑定，改动端口后需要重启服务；把同网段设备的 DNS 指向上面的地址即可让它们走本机解析。';

  @override
  String get intranetCopyAddressWithPort => '复制地址（含端口）';

  @override
  String get speedDetailTitle => '网速详情';

  @override
  String get speedCurrentDownload => '当前下载';

  @override
  String get speedSamplingPaused => '暂停采样';

  @override
  String get speedLive => '实时';

  @override
  String get speedSamplingHint => '每秒采样一次，下图是最近一分钟。';

  @override
  String get speedCurrentUpload => '当前上传';

  @override
  String get speedDownloadPeak => '下行峰值';

  @override
  String get speedUploadPeak => '上行峰值';

  @override
  String get speedSamples => '样本';

  @override
  String get speedTodayTotal => '今日累计';

  @override
  String get speedNoTrafficToday => '流量库还没有今天的记录。';

  @override
  String get speedTotal => '合计';

  @override
  String get speedRateFooter =>
      '速率来自内核数据面的实时计数，只包含经过隧道转发的流量；本应用自身的探测与测速不计入。今日累计来自应用流量统计，与「流量统计」页同一份数据。';

  @override
  String get speedExpressSource => '极速模式不经过内核数据面，因此没有逐秒速率；切回普通模式后恢复。';

  @override
  String get speedNoChannelSource => '当前环境没有速率通道（桌面环境或纯 Dart 测试），读不到实时速率。';

  @override
  String get speedNoDataInMode => '当前模式下没有速率数据';

  @override
  String get speedWaitingSample => '正在等待第一个样本';

  @override
  String get commonNoData => '无数据';

  @override
  String get commonPendingTitle => '尚未接入';

  @override
  String get commonPendingBody => '这个页面还没有连接到本机服务，接入后会显示实时数据。';

  @override
  String get homePowerPending => '电源控制还没有接入本机服务';

  @override
  String intranetModeNotListening(String mode) {
    return '$mode不监听局域网，其他设备无法把这里当 DNS';
  }

  @override
  String intranetListeningOn(int port) {
    return '已监听 0.0.0.0:$port，其他设备把 DNS 指到上面的地址';
  }

  @override
  String intranetServiceStopped(int port) {
    return '服务未启动：启动后才会绑定 $port 端口';
  }

  @override
  String commonCopied(String text) {
    return '已复制 $text';
  }

  @override
  String intranetGatewaySuffix(String gateway) {
    return ' · 网关 $gateway';
  }

  @override
  String get speedTotalDash => '累计 —';

  @override
  String siteLatencyAliveRatio(int alive, int total) {
    return '$alive / $total 通畅';
  }

  @override
  String siteLatencyLastRun(String ago) {
    return '最近测速 $ago';
  }

  @override
  String siteLatencyProviderSuffix(String name) {
    return ' · 解析服务商 $name';
  }

  @override
  String siteLatencySitesCount(int count) {
    return '$count 个站点';
  }

  @override
  String siteLatencyTestCategory(String category) {
    return '测速$category';
  }

  @override
  String memorySystemShare(String percent) {
    return '占整机 $percent';
  }

  @override
  String memorySystemUsedOf(String total, String used) {
    return '整机已用 $used / $total';
  }

  @override
  String get memoryNoChannel => '当前环境读不到内存数据（桌面环境或纯 Dart 测试）。';

  @override
  String trafficStructureRateValue(
    String count,
    String latency,
    String percent,
  ) {
    return '$percent · $count 次 · $latency';
  }

  @override
  String trafficStructureShareValue(String count, String percent) {
    return '$percent · $count 次';
  }

  @override
  String statusPausedSummary(String core, String mode) {
    return '$mode$core，计时已暂停';
  }

  @override
  String speedTotalsDown(String percent) {
    return '下行 $percent';
  }

  @override
  String speedTotalsUp(String percent) {
    return '上行 $percent';
  }

  @override
  String speedPeakAverage(String average, String peak) {
    return '峰值 $peak · 平均 $average';
  }

  @override
  String get intranetConnectHintSentence => '连上 Wi-Fi 或以太网后这里会显示可用地址。';

  @override
  String intranetModeNotListeningSentence(String mode) {
    return '$mode不监听局域网，其它设备无法把这里当 DNS。';
  }

  @override
  String intranetPrivateDnsOn(String dns) {
    return '系统开启了私人 DNS（$dns），系统解析会走加密通道，可能绕过本地服务。';
  }

  @override
  String intranetSecondaryDns(int index) {
    return '备用 $index';
  }

  @override
  String intranetCopyAddressSemantics(String address) {
    return '复制地址 $address';
  }

  @override
  String speedTotalAccumulated(String value) {
    return '累计 $value';
  }

  @override
  String dashboardSitesFull(int count) {
    return '卡片只能放 $count 个站点，先点掉一个再换别的。';
  }

  @override
  String dashboardSitesRemaining(int count) {
    return '还可以再放 $count 个站点。';
  }

  @override
  String dashboardSitesMax(int count) {
    return '卡片最多放 $count 个站点，先取消一个再选。';
  }

  @override
  String dashboardSitesPosition(int index) {
    return '第 $index 位';
  }

  @override
  String siteLatencyFailedCount(int count) {
    return '$count 个失败';
  }

  @override
  String get siteLatencyDetailFooterLong =>
      '每个站点发 3 个 ICMP 回显，取平均值；系统 ping 不可用时退回 TCP 握手，会标上 * 号，数值略高于真实往返。本应用自身流量不经过 VPN，测的是物理网络。';

  @override
  String get homeLayerPowerButton => '启动按钮';

  @override
  String get homeLayerPoem => '首页古诗';

  @override
  String get bottomBarHome => '首页';

  @override
  String get bottomBarFeatureHub => '功能中心';

  @override
  String get bottomBarLogDashboard => '日志仪表盘';

  @override
  String get bottomBarAppTraffic => '应用流量';

  @override
  String get bottomBarNetworkTools => '网络工具';

  @override
  String get bottomBarSettings => '设置';

  @override
  String get bottomBarStyleFloating => '浮条';

  @override
  String get bottomBarStyleDocked => '普通';

  @override
  String get tabTransitionNone => '无';

  @override
  String get tabTransitionFade => '淡入';

  @override
  String get tabTransitionSlide => '滑动';

  @override
  String get tabTransitionScale => '缩放';

  @override
  String get commonOff => '关闭';

  @override
  String get glassModeStandard => '标准';

  @override
  String get glassModeUltra => '极致';

  @override
  String get previewBrightnessLight => '浅色';

  @override
  String get previewBrightnessDark => '深色';

  @override
  String get resolutionModeSingle => '单服务商';

  @override
  String get resolutionModeSmart => '智能选择';

  @override
  String get resolutionModeParallel => '并行竞速';

  @override
  String get resolutionModePrimaryBackup => '主备切换';

  @override
  String get workModeNormalTitle => '普通模式';

  @override
  String get workModeNormalBadge => '推荐';

  @override
  String get workModeNormalSummary => '全量域名解析、黑白名单、HTTPS 检查、网络管控';

  @override
  String get workModeServerTitle => '服务器模式';

  @override
  String get workModeServerBadge => '轻量';

  @override
  String get workModeServerSummary => '纯 DNS 代理与解析加速、低功耗';

  @override
  String get workModeExpressTitle => '极速模式';

  @override
  String get workModeExpressBadge => '极速';

  @override
  String get workModeExpressSummary => 'DNS 窄路由、加速与规则过滤、Android 9+（64 位）';

  @override
  String get stateStopped => '已停止';

  @override
  String get stateStarting => '启动中';

  @override
  String get stateRunning => '运行中';

  @override
  String get stateStopping => '停止中';

  @override
  String get powerStateError => '启动失败';

  @override
  String get serverStatusError => '异常';

  @override
  String get logModeAllLabel => '记录全部';

  @override
  String get logModeAllDescription => '请求、命中、竞速与拦截都进日志';

  @override
  String get logModeBlockedLabel => '仅拦截与错误';

  @override
  String get logModeBlockedDescription => '只记录被拦截与出错的请求';

  @override
  String get logModeOffLabel => '关闭日志';

  @override
  String get logModeOffDescription => '不记录任何请求，节省空间';

  @override
  String get ipv6AutoLabel => '自动';

  @override
  String get ipv6AutoDescription => '按当前网络能力决定是否启用';

  @override
  String get ipv6DisableLabel => '关闭';

  @override
  String get ipv6DisableDescription => '隧道内不启用 IPv6';

  @override
  String get ipv6PreferLabel => '优先';

  @override
  String get ipv6PreferDescription => '尽量走 IPv6，失败再回落';

  @override
  String get commonToday => '今日';

  @override
  String get logWindowSevenDays => '7 天';

  @override
  String get logWindowSevenDaysRecent => '近 7 天';

  @override
  String get commonAll => '全部';

  @override
  String get trafficWindowWeek => '本周';

  @override
  String get trafficWindowMonth => '本月';

  @override
  String get trafficSortTotal => '按总流量';

  @override
  String get trafficSortDownload => '按下载流量';

  @override
  String get trafficSortUpload => '按上传流量';

  @override
  String get davStatusIdle => '未连接';

  @override
  String get davStatusConnecting => '连接中';

  @override
  String get davStatusConnected => '连接成功';

  @override
  String get davStatusFailed => '连接失败';

  @override
  String get updateStageIdle => '未检查';

  @override
  String get updateStageChecking => '检查中';

  @override
  String get updateStageUpToDate => '已是最新';

  @override
  String get updateStageAvailable => '发现新版本';

  @override
  String get updateStageDownloading => '下载中';

  @override
  String get updateStageDownloaded => '下载完成';

  @override
  String get ipQualityStageIdle => '未检测';

  @override
  String get ipQualityStageLoading => '检测中';

  @override
  String get ipQualityStageLoaded => '检测完成';

  @override
  String get ipQualityStageFailed => '检测失败';

  @override
  String get subscriptionDeleted => '已删除';

  @override
  String get subscriptionDisabled => '已禁用';

  @override
  String get subscriptionUngrouped => '未分组';

  @override
  String get providerNotTested => '未测速';

  @override
  String get elapsedJustNow => '刚刚';

  @override
  String elapsedSecondsAgo(int count) {
    return '$count 秒前';
  }

  @override
  String elapsedMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String elapsedHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String elapsedDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String providerRaceSummary(String count, String names) {
    return '已选 $count 个：$names';
  }

  @override
  String get rulesDbUnavailable => '当前环境无法读写规则库';

  @override
  String get agentApiKeyMissing => '尚未配置可用的 API Key，请先在「AI 厂商管理」里填写并选中该厂商。';

  @override
  String get agentNoExtraInfo => '（无附加信息）';

  @override
  String get agentNoLegacyDatabase => '未找到旧版数据库，无法读取 DNS 与 HTTPS 日志；请先启动一次服务。';

  @override
  String get agentExpressNoHttps => '极速模式只做窄路由 DNS 加速，不产生 HTTPS 检查记录';

  @override
  String get autoUpdateDisabled => '自动更新已关闭';

  @override
  String get autoUpdateNoSubscriptions => '没有可自动更新的订阅';

  @override
  String get autoUpdateNotDue => '未到更新时间';

  @override
  String get autoUpdateBusy => '正在手动更新，本轮跳过';

  @override
  String get cleanupGroupRuntime => '运行数据';

  @override
  String get cleanupGroupWeights => '权重数据';

  @override
  String get cleanupGroupRules => '规则与订阅';

  @override
  String get cleanupGroupStorage => '存储与安全';

  @override
  String get cleanupGroupGuides => '引导与重置';

  @override
  String get backupReadFileFailed => '无法读取所选文件';

  @override
  String get caChannelUnavailable => '证书通道不可用';

  @override
  String get caInstallUnavailable => '无法调起证书安装界面';

  @override
  String get caDownloadDirUnavailable => '无法写入下载目录';

  @override
  String get fontSystemDefault => '系统默认';

  @override
  String get diagnosticsChannelUnavailable => '诊断通道不可用（当前平台没有原生实现）';

  @override
  String get diagnosticsUnsupported => '当前环境不支持该诊断能力';

  @override
  String get diagnosticsPingUnsupported => '当前环境不支持 Ping 探测';

  @override
  String get diagnosticsTraceUnsupported => '当前环境不支持路由追踪';

  @override
  String get diagnosticsDnsUnsupported => '当前环境不支持 DNS 查询';

  @override
  String get diagnosticsEmptyTarget => '请输入探测目标';

  @override
  String get diagnosticsTargetHasSpace => '目标不能包含空格';

  @override
  String get diagnosticsAnswerUpstream => '上游解析';

  @override
  String get diagnosticsAnswerCache => '缓存命中';

  @override
  String get diagnosticsAnswerRewrite => '覆写规则';

  @override
  String get diagnosticsAnswerBlocked => '被规则拦截';

  @override
  String get diagnosticsAnswerFailed => '查询失败';

  @override
  String get diagnosticsNoActiveNetwork => '无活动网络';

  @override
  String get aiPresetMainland => '国内厂商';

  @override
  String get aiPresetOverseas => '海外厂商';

  @override
  String get aiPresetAggregator => '聚合与本地部署';

  @override
  String get aiProviderConfigured => '已配置厂商';

  @override
  String get aiProviderExampleName => '示例厂商（请修改）';

  @override
  String get logSubscriptionDeleted => '已删除订阅';

  @override
  String get logRaceFastest => '最快响应';

  @override
  String get logRaceSmart => '智能选择';

  @override
  String get logRaceSequential => '依次尝试';

  @override
  String get logRaceSingle => '单服务商';

  @override
  String get providerNoProviderSelected => '未选择服务商';

  @override
  String get onDemandDisabled => '按需连接已关闭，未做改动';

  @override
  String get onDemandServerMode => '服务器模式不使用隧道，未做改动';

  @override
  String get onDemandUnknownSsid => '无法读取当前 Wi-Fi，未做改动';

  @override
  String get onDemandSameNetwork => '网络未变化，保持当前 VPN 状态';

  @override
  String get onDemandNoWifi => '当前不在 Wi-Fi 上，已断开 VPN';

  @override
  String get onDemandStarted => '已匹配白名单，VPN 已启动';

  @override
  String get onDemandAlreadyRunning => '已匹配白名单，VPN 正在运行';

  @override
  String get onDemandStopped => '当前网络不在白名单，已断开 VPN';

  @override
  String get onDemandAlreadyStopped => '当前网络不在白名单，VPN 未启动';

  @override
  String get onDemandBusy => 'VPN 正在切换状态，稍后再试';

  @override
  String get onDemandNeedsConsent => '已匹配白名单，等待系统 VPN 授权';

  @override
  String get speedTestSelectProvider => '请先选择至少一个测速服务商';

  @override
  String get speedTestEmptyDomain => '请输入用于测速的域名';

  @override
  String get imagePickerUnavailable => '当前设备没有可用的图片选择器';

  @override
  String get serverModeRequired => '请先切换到服务器模式';

  @override
  String get serverStartFailed => 'DNS 服务启动失败';

  @override
  String get serverStartTimeout => 'DNS 服务启动超时';

  @override
  String get recognitionInvalidConfig => '云端名单配置无效';

  @override
  String get recognitionGithubInterrupted => '与 GitHub 的连接被中断，请稍后重试';

  @override
  String get recognitionGithubTimeout => '连接 GitHub 超时，请检查网络后重试';

  @override
  String get recognitionNetworkUnavailable => '网络不可用，无法更新名单';

  @override
  String get recognitionUpdateFailed => '名单更新失败';

  @override
  String get subscriptionNotFound => '订阅不存在或数据库不可用';

  @override
  String get subscriptionDatabaseUnavailable => '订阅数据库不可用';

  @override
  String get subscriptionRuleDbUnavailable => '规则库不可用，下载的规则无法入库';

  @override
  String get subscriptionUpdateFailed => '更新失败';

  @override
  String get subscriptionLocalFileUnreadable => '无法读取本地文件';

  @override
  String get subscriptionLocalRuleDbUnavailable => '规则库不可用，本地规则无法入库';

  @override
  String get subscriptionNothingToUpdate => '没有可更新的订阅';

  @override
  String get subscriptionPickRuleFile => '请选择一个规则文件';

  @override
  String get subscriptionPickTxtFile => '请选择扩展名为 .txt 的规则文件';

  @override
  String get subscriptionLegacyDatabaseMissing => '订阅数据库不可用（未找到 1.4.3 数据库）';

  @override
  String get subscriptionThisFile => '该文件';

  @override
  String get subscriptionThisLink => '该订阅链接';

  @override
  String get subscriptionLocalRuleFile => '本地规则文件';

  @override
  String get webdavEmptyCredentials => '服务器地址与用户名不能为空';

  @override
  String get webdavDirectoryCreated => '目录不存在，已自动创建';

  @override
  String get webdavUploaded => '已上传到云端';

  @override
  String get webdavNoBackup => '云端还没有备份文件';

  @override
  String get webdavDownloaded => '已从云端取回备份';

  @override
  String get updateCheckFirst => '请先检查更新';

  @override
  String get updateDownloadFirst => '请先下载更新包';

  @override
  String get updateInstallerUnavailable => '无法调起系统安装器，请稍后重试';

  @override
  String get workModeNoDataPlane => '当前工作模式尚未接入数据面';

  @override
  String get workModeNoVpnConsent => '没有获得 VPN 授权';

  @override
  String get workModeStartTimeout => '服务启动超时';

  @override
  String get workModeVpnStartFailed => 'VPN 启动失败';

  @override
  String get aiProviderZhipu => '智谱 GLM';

  @override
  String get aiProviderMoonshot => 'Kimi（月之暗面）';

  @override
  String get aiProviderDashscope => '阿里云百炼（通义千问）';

  @override
  String get aiProviderVolcengine => '火山方舟（豆包）';

  @override
  String get aiProviderQianfan => '百度千帆（ERNIE）';

  @override
  String get aiProviderStepfun => '阶跃星辰';

  @override
  String get aiProviderSiliconflow => '硅基流动';

  @override
  String get aiProviderOllamaLocal => 'Ollama（本机）';

  @override
  String rulesReadFailed(String detail) {
    return '读取应用规则失败：$detail';
  }

  @override
  String autoUpdateChecked(int count) {
    return '已检查 $count 个订阅';
  }

  @override
  String caChannelUnavailableDetail(String detail) {
    return '证书通道不可用：$detail';
  }

  @override
  String caReadFailedCode(String code) {
    return '读取根证书失败（$code）';
  }

  @override
  String caReadFailed(String detail) {
    return '读取根证书失败：$detail';
  }

  @override
  String agentAnalysisFailed(String detail) {
    return '分析失败：$detail';
  }

  @override
  String diagnosticsFailedCode(String code) {
    return '诊断执行失败（$code）';
  }

  @override
  String diagnosticsFailed(String detail) {
    return '诊断执行失败：$detail';
  }

  @override
  String subscriptionDeletedWithId(int id) {
    return '已删除订阅 #$id';
  }

  @override
  String providerLatencyValue(int value) {
    return '${value}ms';
  }

  @override
  String providerRaceSummaryNames(int count, String names) {
    return '已选 $count 个：$names';
  }

  @override
  String get providerNamesSeparator => '、';

  @override
  String recognitionInvalidConfigKept(String detail) {
    return '云端名单配置无效（$detail），已保留本地缓存';
  }

  @override
  String recognitionFetchFailed(String detail) {
    return '云端名单拉取失败（$detail）';
  }

  @override
  String recognitionUpdateFailedDetail(String detail) {
    return '名单更新失败：$detail';
  }

  @override
  String subscriptionAlreadyExists(String kind, String what) {
    return '$what已作为$kind存在';
  }

  @override
  String subscriptionUpdatedCount(int count) {
    return '$count 个已更新';
  }

  @override
  String subscriptionUnchangedCount(int count) {
    return '$count 个未变化';
  }

  @override
  String subscriptionFailedCount(int count) {
    return '$count 个失败';
  }

  @override
  String subscriptionAlreadyExistsNamed(String kind, String name, String what) {
    return '$what已作为$kind存在（「$name」）';
  }

  @override
  String get commonBypass => '旁路';

  @override
  String get commonRewrite => '覆写';

  @override
  String get cleanupLogs => '删除请求日志';

  @override
  String get cleanupTraffic => '删除流量统计';

  @override
  String get cleanupCrash => '删除崩溃日志';

  @override
  String get cleanupDnsCache => '删除 DNS 缓存';

  @override
  String get cleanupProviderWeights => '恢复 DNS 默认权重';

  @override
  String get cleanupBootstrapWeights => '恢复 Bootstrap 权重';

  @override
  String get cleanupDomainRules => '删除全部域名规则';

  @override
  String get cleanupAddressRules => '删除全部地址规则';

  @override
  String get cleanupSubscriptions => '删除全部规则订阅';

  @override
  String get cleanupAppRules => '重置应用控制名单';

  @override
  String get cleanupOutboundProxy => '重置出站代理配置';

  @override
  String get cleanupCaCertificate => '重置 HTTPS 抓包证书';

  @override
  String get cleanupDownloadCache => '清理下载与临时缓存';

  @override
  String get cleanupCustomBackground => '清除自定义背景缓存';

  @override
  String get cleanupSettingsGuides => '重置所有新手引导';

  @override
  String get cleanupAllData => '清理全部本地数据';

  @override
  String cleanupDoneItems(String action, int count, String detail) {
    return '已$action：$count 项$detail';
  }

  @override
  String cleanupDoneEmpty(String action) {
    return '已$action：没有可清理的数据';
  }

  @override
  String get blockResponseNxdomain => '返回 NXDOMAIN';

  @override
  String get blockResponseNxdomainDescription => '返回域名不存在，并提供 5 分钟负缓存以减少重复查询';

  @override
  String get blockResponseNodata => '返回 NODATA';

  @override
  String get blockResponseNodataDescription => '返回域名存在但没有该记录，并提供 5 分钟负缓存';

  @override
  String get blockResponseRefused => '返回 REFUSED';

  @override
  String get blockResponseRefusedDescription => '返回服务器拒绝该查询，不提供缓存记录';

  @override
  String get blockResponseZeroAddress => '返回 0.0.0.0 / ::';

  @override
  String get blockResponseZeroAddressDescription =>
      'A 返回 0.0.0.0，AAAA 返回 ::，其他类型返回空结果';

  @override
  String get subscriptionSourceRemote => '网络订阅';

  @override
  String get subscriptionSourceLocal => '本地文件';

  @override
  String get subscriptionKindDomain => '黑白名单规则';

  @override
  String get subscriptionKindHosts => 'hosts 规则';

  @override
  String logRowDirect(String protocol) {
    return '$protocol 直连';
  }

  @override
  String logRowDirectWithPackage(String package, String protocol) {
    return '$protocol 直连 · $package';
  }

  @override
  String get logRowCacheHit => '命中缓存';

  @override
  String get logRowNoAuthority => '未取得 authority';

  @override
  String get cachePresetConservativeName => '保守';

  @override
  String get cachePresetConservativeSummary => '遵从服务器有效期 (TTL)';

  @override
  String get cachePresetConservativeDescription =>
      '遵从 DNS 服务器返回的有效期，不主动延长缓存时间，适合经常切换网络或对实时性敏感的场景。';

  @override
  String get cachePresetStandardName => '标准';

  @override
  String get cachePresetStandardSummary => '最长 1 小时，短记录至少 1 分钟';

  @override
  String get cachePresetStandardDescription =>
      '减少重复查询，同时避免记录过期滞后。解析失败时可短暂使用 5 分钟内的旧记录应急。';

  @override
  String get cachePresetAggressiveName => '高命中';

  @override
  String get cachePresetAggressiveSummary => '最长 6 小时，短记录至少 2 分钟';

  @override
  String get cachePresetAggressiveDescription =>
      '更偏向降低网络请求次数和提升弱网可用性。域名变更时更新可能会稍慢一些。';

  @override
  String get cacheDisabledSummary => '已关闭 · 每次解析都会请求上游';

  @override
  String get upstreamNameRequired => '请填写名称';

  @override
  String get upstreamAddressRequired => '请填写地址';

  @override
  String get upstreamDohNeedsHttps => 'DoH 地址必须以 https:// 开头';

  @override
  String get upstreamDohInvalidUrl => 'DoH 地址不是合法的 URL';

  @override
  String get upstreamPortRange => '端口需在 1–65535 之间';

  @override
  String get upstreamIpv6Invalid => 'IPv6 地址格式不正确';

  @override
  String get upstreamPresetAliyun => '阿里云';

  @override
  String get upstreamPresetTencent => '腾讯云 DNSPod';

  @override
  String get upstreamPresetByteDance => '字节跳动';

  @override
  String cleanupFailed(String detail) {
    return '清理失败：$detail';
  }

  @override
  String get cleanupProxyRestored => '已恢复直连';

  @override
  String get cleanupCaNeedsReimport => '需重新生成并导入系统证书';

  @override
  String get hubCategoryDns => 'DNS 服务';

  @override
  String get hubProviderManagement => '服务商管理';

  @override
  String get hubProviderManagementDescription => '配置与管理 DoH、DoT 与传统 DNS 解析服务商';

  @override
  String get hubBootstrap => '引导解析设置';

  @override
  String get hubBootstrapDescription => '配置用于首次解析加密上游域名的引导 DNS 节点';

  @override
  String get hubResolution => '解析模式';

  @override
  String get hubResolutionDescription => '选择单一服务、智能选择、最快响应或依次尝试策略';

  @override
  String get hubCache => '缓存设置';

  @override
  String get hubCacheDescription => '配置 DNS 缓存开关、缓存策略与最大最小生存时间 (TTL)';

  @override
  String get hubCategoryRules => '策略与规则';

  @override
  String get hubRuleControl => '规则控制';

  @override
  String get hubRuleControlDescription => '统一管理拦截策略开关与在线网络规则订阅';

  @override
  String get hubBlocklist => '黑名单';

  @override
  String get hubBlocklistDescription => '自定义屏蔽域名列表，匹配时返回拦截响应';

  @override
  String get hubAllowlist => '白名单';

  @override
  String get hubAllowlistDescription => '自定义放行域名列表，豁免所有规则直接放行';

  @override
  String get hubRewrite => '覆写名单';

  @override
  String get hubRewriteDescription => '自定义域名覆写指向特定 IPv4/IPv6 或 CNAME';

  @override
  String get hubCategoryNetwork => '网络控制';

  @override
  String get hubAppTraffic => '应用流量统计';

  @override
  String get hubAppTrafficDescription => '统计各应用的网络连接数、上传与下载流量明细';

  @override
  String get hubAppRules => '应用独立规则';

  @override
  String get hubAppRulesDescription => '为特定应用单独指定专属域名放行与网络规则';

  @override
  String get hubBlockedApps => '禁止联网应用';

  @override
  String get hubBlockedAppsDescription => '在本地隧道层拦截指定应用的全部网络外联';

  @override
  String get hubExcludedApps => '排除应用';

  @override
  String get hubExcludedAppsDescription => '允许指定应用绕过本软件直连网络';

  @override
  String get hubCategoryAdvanced => '高级与诊断';

  @override
  String get hubHttpsInspection => 'HTTPS 流量检查';

  @override
  String get hubHttpsInspectionDescription =>
      '解密并检查特定应用的 HTTP(S) 流量，支持域名与 URL 过滤';

  @override
  String get hubOutboundProxy => '出站代理';

  @override
  String get hubOutboundProxyDescription => '将过滤后的流量转发到本地 SOCKS5 或 HTTP 代理';

  @override
  String get hubDiagnostics => '网络诊断';

  @override
  String get hubDiagnosticsDescription => '提供 DNS 查询、Ping 延迟测试与网络连通性诊断工具';

  @override
  String get hubAiAnalysis => 'AI 分析';

  @override
  String get hubAiAnalysisDescription => '配置大语言模型接口与密钥，用于日志研判与网络流量分析';

  @override
  String get hubCategoryInterface => '界面与设置';

  @override
  String get hubAppearance => '外观调整';

  @override
  String get hubAppearanceDescription => '自定义日夜模式、主题色彩、组件透明度与软件壁纸背景';

  @override
  String get hubProviderVisibility => '服务显示';

  @override
  String get hubProviderVisibilityDescription => '自定义在首页解析服务下拉列表中显示的服务商';

  @override
  String get hubHiddenFeatures => '隐藏功能';

  @override
  String get hubHiddenFeaturesDescription => '自定义在功能中心显示的功能卡片，不改后台运行';

  @override
  String get hubOtherSettings => '其他设置';

  @override
  String get hubOtherSettingsDescription => '语言切换、前后台行为、通知设置等全局配置';

  @override
  String get hubCategoryData => '数据与维护';

  @override
  String get hubLogs => '日志';

  @override
  String get hubLogsDescription => '实时解析统计、请求明细查询与日志导出';

  @override
  String get hubBackup => '备份与迁移';

  @override
  String get hubBackupDescription => '导出与导入服务商、规则订阅及个性化设置';

  @override
  String get hubDataCleanup => '数据清理';

  @override
  String get hubDataCleanupDescription => '删除缓存、日志或域名与地址过滤规则';

  @override
  String get hubTroubleshooting => '故障排查';

  @override
  String get hubTroubleshootingDescription => '导出崩溃日志，手动抓取并导出运行日志发给开发者';

  @override
  String get hubCategoryAbout => '关于谛听';

  @override
  String get hubAbout => '关于';

  @override
  String get hubAboutDescription => '查看版本信息、检查更新、开源地址与贡献者名单';

  @override
  String get hubSponsor => '赞助';

  @override
  String get hubSponsorDescription => '支持谛听项目持续维护与开发';

  @override
  String get hubSponsors => '赞助者名单';

  @override
  String get hubSponsorsDescription => '鸣谢支持谛听项目的赞助者';

  @override
  String get hubContributors => '共建者名单';

  @override
  String get hubContributorsDescription => '感谢为谛听贡献代码与建议的共建者';

  @override
  String get fontSizeSmall => '小';

  @override
  String get fontSizeStandard => '标准';

  @override
  String get fontSizeLarge => '大';

  @override
  String get fontSizeExtraLarge => '特大';

  @override
  String get fontSizeFooter => '字号会同时放大正文、标题与列表行，不会改变系统设置；界面已按所选比例排版，无需重启。';

  @override
  String get fontSizePreview => '实时预览';

  @override
  String get appearancePoem => '谛听万象，明察清浊';

  @override
  String get appearancePoemBody => '网络连通性、规则命中与设备状态，都在这一页里说清楚。';

  @override
  String get appearanceTitle => '外观设置';

  @override
  String get appearanceInterfaceSection => '界面显示';

  @override
  String get appearanceHomeOpacitySubtitle => '交互组件与文字的透明度';

  @override
  String get appearancePureBlackOn => '深色表面折叠为纯黑，OLED 更省电';

  @override
  String get appearancePureBlackOff => '切到深色模式后才可开启';

  @override
  String get appearanceHomeSection => '首页内容';

  @override
  String get appearanceHomeSentenceSubtitle => '运行与停止两种状态各一句';

  @override
  String get appearanceNotification => '通知栏设置';

  @override
  String get appearanceNotificationSubtitle => '常驻通知、实时速率与自定义文案';

  @override
  String get appearanceBackgroundSection => '背景与动效';

  @override
  String get appearanceHapticSubtitle => '切换 tab 时给一次轻震';

  @override
  String get appearanceBottomBarStyleFloating => '浮在页面之上';

  @override
  String get appearanceBottomBarStyleDocked => '贴底排列';

  @override
  String get appearanceTabTransitionSubtitle => '切换底部标签时的动画方式';

  @override
  String get appearanceMotionFooter => '底栏样式、动画与玻璃只作用于浮条；普通底栏始终是实色。';

  @override
  String get appearancePaletteGoldLegacy => '落盘值沿用旧版的 indigo';

  @override
  String get appearancePaletteFooter =>
      '色板只提供种子，上屏的是 HCT 推导出的整套角色色。旧版没有自定义取色，因此这里也不提供。';

  @override
  String get launcherIconTitle => '应用图标';

  @override
  String get launcherIconInfoLabel => '选择桌面显示的应用图标';

  @override
  String get launcherIconDefault => '默认';

  @override
  String get launcherIconDefaultDescription => '谛听默认图标';

  @override
  String get launcherIconAdguard => 'AdGuard';

  @override
  String get launcherIconAdguardDescription => '绿色盾牌与白色对勾';

  @override
  String get launcherIconFooter =>
      '系统没有在运行时替换图标的接口，切换通过启用对应的启动入口实现。返回桌面即可看到；若桌面缓存未刷新，请稍候或重启桌面。';

  @override
  String get launcherIconApplied => '已切换应用图标，返回桌面即可看到';

  @override
  String get launcherIconApplyFailed => '切换应用图标失败，请稍后重试';

  @override
  String fontFamilySizeSubtitle(String percent) {
    return '当前 $percent%';
  }

  @override
  String get fontFamilySystemDefault => '跟随宿主平台的中文界面字体，最稳妥的选择';

  @override
  String get fontFamilyImported => '已导入的第三方字体';

  @override
  String get fontFamilyEmpty => '还没有导入字体。导入后即可在这里切换，字体文件只保存在本机。';

  @override
  String get fontFamilyFooter => '导入的字体只影响本机显示，删除后会自动回退到系统默认。';

  @override
  String get fontFamilyLocalOnly => '选择只影响本机显示，不改动服务端规则。';

  @override
  String get fontFamilyImportFailed => '导入失败';

  @override
  String get fontFamilyDeleteTitle => '删除字体';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDelete => '删除';

  @override
  String fontFamilyDeleteConfirm(String name) {
    return '删除「$name」后，使用该字体的界面会回退到系统默认。';
  }

  @override
  String get fontFamilyImport => '导入字体';

  @override
  String get fontFamilyReading => '正在读取字体文件…';

  @override
  String get fontFamilyPickFile => '选择本机的 TTF / OTF 文件';

  @override
  String get notificationPersistentSection => '常驻通知';

  @override
  String get notificationPersistentFooter => '关闭后服务运行时不再显示常驻通知，系统可能因此更快回收进程。';

  @override
  String get notificationPersistent => '通知常驻';

  @override
  String get notificationPersistentSubtitle => '服务运行时保留一条不可划掉的通知';

  @override
  String get notificationShowSpeedSubtitle => '在通知里显示当前上下行速率';

  @override
  String get notificationStatsSection => '通知详情';

  @override
  String get notificationStatsEmpty => '未显示任何详情，通知只保留状态文案';

  @override
  String get notificationStatsFooter =>
      '统计从本次服务启动开始累计，与日志记录模式无关；已开启的项目按住拖动可调整顺序。极速与服务器模式没有实时网速，该项会自动省略。';

  @override
  String get notificationStatsHidden => '未显示的项目';

  @override
  String get notificationStatTotal => '请求';

  @override
  String get notificationStatSpeed => '实时网速';

  @override
  String get notificationStatTotalSubtitle => '本次运行处理的请求总数（DNS 与 HTTPS）';

  @override
  String get notificationStatPassedSubtitle => '正常放行的请求，含覆写后返回的结果';

  @override
  String get notificationStatFilteredSubtitle => '被规则过滤拦截的请求';

  @override
  String get notificationStatFailedSubtitle => '解析或处理失败的请求';

  @override
  String get notificationStatCachedSubtitle => '由本机缓存直接应答的请求';

  @override
  String get notificationStatRewrittenSubtitle => '命中覆写规则、返回改写结果的请求';

  @override
  String get notificationTextRunning => 'DNS 服务开启时';

  @override
  String get notificationTextStopped => 'DNS 服务关闭时';

  @override
  String get notificationTextHint => '留空则使用默认文案';

  @override
  String get notificationTextSection => '通知文案';

  @override
  String get notificationTextFooter => '留空则使用默认文案；文案只影响通知栏，不改变服务行为。';

  @override
  String get notificationPermissions => '权限';

  @override
  String get notificationSystemPermission => '系统通知权限';

  @override
  String get notificationSystemPermissionSubtitle => '打开系统的通知设置页';

  @override
  String get backgroundTitle => '软件背景';

  @override
  String get backgroundSection => '自定义背景';

  @override
  String get backgroundFooter => '壁纸只保存在本机，不随备份导出。';

  @override
  String get backgroundEnable => '启用自定义背景';

  @override
  String get backgroundPickFirst => '请先添加一张图片';

  @override
  String get backgroundBehindPages => '在全部页面下垫一层壁纸';

  @override
  String get backgroundAddImage => '添加图片';

  @override
  String get backgroundAddImageSubtitle => '从相册选择一张';

  @override
  String get backgroundAdded => '已添加壁纸';

  @override
  String get backgroundAddedFooter => '点一下切换，长按删除。';

  @override
  String get backgroundEmpty => '还没有背景图';

  @override
  String get backgroundEmptyDescription => '点「添加图片」从相册里挑一张。';

  @override
  String get backgroundDeleteTitle => '删除壁纸';

  @override
  String get backgroundDeleteConfirm => '确定删除这张已添加的壁纸吗？';

  @override
  String get foregroundTitle => '前后台行为';

  @override
  String get foregroundPrivacySection => '后台与隐私';

  @override
  String get foregroundPrivacyFooter => '「后台隐藏」会从最近任务列表里移除本应用；下次从桌面图标进入即可。';

  @override
  String get foregroundHide => '后台隐藏';

  @override
  String get foregroundHideSubtitle => '不在最近任务列表中显示';

  @override
  String get foregroundRouting => '路由';

  @override
  String get foregroundBypassLan => '绕过局域网';

  @override
  String get foregroundBypassLanSubtitle => '本地网段与本机地址不走隧道';

  @override
  String get foregroundStability => '稳定性';

  @override
  String get foregroundBatteryFooter => '关闭电池优化后，系统在后台更不容易回收服务进程。';

  @override
  String get foregroundIgnoreBattery => '忽略电池优化';

  @override
  String get foregroundIgnoreBatterySubtitle => '请求把本应用加入系统白名单';

  @override
  String get dayNightTitle => '日夜模式';

  @override
  String get dayNightFollowSystemDescription => '系统切换深色时一起切换';

  @override
  String get dayNightFooter => '纯黑只在深色模式下生效，开关在「外观设置」的界面显示组里。';

  @override
  String get homeOpacityTitle => '首页透明度';

  @override
  String get homeOpacityComponents => '交互组件';

  @override
  String get homeOpacityComponentsFooter => '透明度只影响可见度，不影响这些组件的点击区域。';

  @override
  String get homeOpacityText => '文字';

  @override
  String get bottomBarHomeSubtitle => '首页与仪表盘';

  @override
  String get bottomBarFeatureHubSubtitle => '全部功能入口';

  @override
  String get bottomBarLogDashboardSubtitle => '日志仪表盘';

  @override
  String get bottomBarAppTrafficSubtitle => '应用流量排行';

  @override
  String get bottomBarNetworkToolsSubtitle => '测速与网络诊断';

  @override
  String get bottomBarSettingsSubtitle => '全部设置项';

  @override
  String get bottomBarMinimumHint => '底栏至少保留 2 项';

  @override
  String get bottomBarCustomTitle => '底栏自定义';

  @override
  String bottomBarItemsHeader(String count, String max) {
    return '底栏项（$count/$max）';
  }

  @override
  String bottomBarDragHint(String max) {
    return '按住右侧把手或长按整行拖动排序，顺序即底栏从左到右的顺序。至少 2 项、最多 $max 项：浮条按项数等比分配宽度，再多就挤到看不清图标。';
  }

  @override
  String get bottomBarDisabled => '未启用';

  @override
  String get bottomBarNewItemFooter => '新启用的项排在底栏最右侧。';

  @override
  String get bottomBarFeel => '手感';

  @override
  String get homeSentenceTitle => '首页句子';

  @override
  String get homeSentenceFooter => '两项均可留空；留空后对应状态下首页不显示句子，句子只在首页电源区下方出现一次。';

  @override
  String get appearancePaletteTitle => '主题色配置';

  @override
  String get appearancePaletteInfoLabel => '色板';

  @override
  String get appearancePaletteBody =>
      '色板只提供种子，上屏的是 HCT 推导出的整套角色色。旧版没有自定义取色，因此这里也不提供。';

  @override
  String get dayNightInfoLabel => '模式';

  @override
  String get appearanceFontSizeLabel => '字号';

  @override
  String appearanceFontSizeCurrent(int percent) {
    return '当前 $percent%';
  }

  @override
  String get appearanceFontSection => '字体';

  @override
  String appearanceFontImported(String name) {
    return '已导入 $name';
  }

  @override
  String appearanceFontDeleted(String name) {
    return '已删除 $name';
  }

  @override
  String appearanceBottomBarMax(int max) {
    return '底栏最多 $max 项';
  }

  @override
  String appearanceBottomBarHeader(int count, int max) {
    return '底栏项（$count/$max）';
  }

  @override
  String appearanceBottomBarDragBody(int max) {
    return '按住右侧把手或长按整行拖动排序，顺序即底栏从左到右的顺序。至少 2 项、最多 $max 项：浮条按项数等比分配宽度，再多就挤到看不清图标。';
  }

  @override
  String appearanceBottomBarSelected(int count) {
    return '已选 $count 项，可配置 2–4 项';
  }

  @override
  String get appearanceHaptic => '底栏触感反馈';

  @override
  String get appearancePureBlack => '纯黑';

  @override
  String get appearanceBottomBarStyle => '底栏样式';

  @override
  String get appearanceTabTransition => 'tab 切换动画';

  @override
  String get appearanceLiquidGlass => 'Liquid 玻璃';

  @override
  String get fontFamilyTitle => '字体设置';

  @override
  String get fontSizeRestoreDefaults => '恢复默认';

  @override
  String get fontFamilyHapticSubtitle => '切换 tab 时给一次轻震';

  @override
  String get ruleKindBlockTitle => '黑名单';

  @override
  String get ruleKindBlockSummary => '拦截匹配的域名';

  @override
  String get ruleKindAllowTitle => '白名单';

  @override
  String get ruleKindAllowSummary => '放行匹配的域名';

  @override
  String get ruleKindRewriteTitle => '覆写';

  @override
  String get ruleKindRewriteSummary => '改写域名解析结果';

  @override
  String get ruleSourceUser => '用户自定义';

  @override
  String get ruleSourceSubscription => '规则订阅';

  @override
  String get ruleSourcePreset => '内置预设';

  @override
  String get rulePatternRequired => '规则内容不能为空';

  @override
  String get ruleAllowNeedsAllowlist => '该规则为放行规则，请在白名单中添加';

  @override
  String get ruleAlreadyExists => '该规则已存在';

  @override
  String get ruleDomainHint => '域名，如 cdn.example.com';

  @override
  String get ruleTargetRequired => '目标值不能为空';

  @override
  String get ruleTargetHint => '目标值，如 10.0.0.8';

  @override
  String get ruleImportant => '重要';

  @override
  String get ruleReadOnly => '只读';

  @override
  String get ruleEdit => '编辑规则';

  @override
  String get ruleDelete => '删除规则';

  @override
  String get batchImportDone => '导入完成';

  @override
  String get batchAddTitle => '批量添加规则';

  @override
  String get batchTarget => '导入到';

  @override
  String get batchTargetTable => '目标规则表';

  @override
  String get batchTargetTableSubtitle => '导入的规则将写入所选规则表';

  @override
  String get batchPlaceholder =>
      '每行一条规则，例如：\n||ads.example.com^\n\n空行会被忽略，重复规则自动跳过。';

  @override
  String get batchImportable => '可导入';

  @override
  String get batchDuplicated => '重复';

  @override
  String get batchInvalid => '无效';

  @override
  String get batchInvalidHeader => '以下规则未通过校验';

  @override
  String get batchDuplicateHeader => '已存在，将跳过';

  @override
  String get ruleClearCustomTitle => '清空自定义规则';

  @override
  String get commonClearAll => '清空';

  @override
  String get ruleResetDefault => '重置默认白名单';

  @override
  String get commonReset => '重置';

  @override
  String get rulePresetProtectedTitle => '预设规则受保护';

  @override
  String get ruleAllowEditTitle => '允许编辑默认白名单？';

  @override
  String get ruleAllowEditConfirm => '仍然开启';

  @override
  String get ruleTotal => '规则总数';

  @override
  String get ruleEnabled => '已启用';

  @override
  String get ruleRewriteEntries => '覆写条目';

  @override
  String get ruleCustom => '自定义';

  @override
  String get ruleAllowEditDefault => '允许编辑默认白名单';

  @override
  String get ruleAllowEditDefaultSubtitle => '关闭时预设规则只读，避免误放宽放行范围';

  @override
  String get ruleNoMatch => '没有匹配的规则';

  @override
  String get ruleNoMatchDescription => '换个关键词或筛选条件再试';

  @override
  String get ruleAll => '全部';

  @override
  String get formIssuesTitle => '有几点需要先修正';

  @override
  String get formSave => '保存';

  @override
  String get formProcessing => '处理中…';

  @override
  String get formAdd => '添加';

  @override
  String get formDelete => '删除';

  @override
  String get formHelp => '说明';

  @override
  String get formGotIt => '知道了';

  @override
  String get rulePatternHint => '规则内容，如 ||ads.example.com^';

  @override
  String ruleBatchImported(String count, int kind) {
    return '已向$kind导入 $count 条规则。';
  }

  @override
  String ruleBatchSkippedDuplicates(int count) {
    return '跳过 $count 条重复规则。';
  }

  @override
  String ruleBatchAllowRejected(int count) {
    return '$count 条放行规则（含 #@#）未导入：该规则为放行规则，请在白名单中添加。';
  }

  @override
  String ruleBatchImportCount(int count) {
    return '导入 $count 条';
  }

  @override
  String ruleBatchMoreDuplicates(int count) {
    return '等 $count 条';
  }

  @override
  String ruleAddForKind(String kind) {
    return '添加$kind规则';
  }

  @override
  String get ruleEditDefaultPreset => '编辑默认预设规则';

  @override
  String ruleEditForKind(String kind) {
    return '编辑$kind规则';
  }

  @override
  String ruleDeletePresetMessage(String pattern) {
    return '「$pattern」是内置预设规则，删除后可通过重置默认恢复。';
  }

  @override
  String ruleDeleteSubscriptionMessage(String name, String pattern) {
    return '「$pattern」来自订阅「$name」，删除后下次更新订阅可能重新出现。';
  }

  @override
  String ruleDeleteUserMessage(String pattern) {
    return '确定删除「$pattern」吗？此操作不可撤销。';
  }

  @override
  String ruleClearCustomMessage(String kind) {
    return '将删除全部用户自定义的$kind规则，订阅与预设规则不受影响。';
  }

  @override
  String get ruleResetMessage => '将内置预设规则恢复为初始内容，你自己添加与订阅带来的规则保留。';

  @override
  String get rulePresetProtectedMessage =>
      '默认白名单规则处于只读状态。请先开启页面顶部的「允许编辑默认白名单」开关，再修改或删除这些规则。';

  @override
  String get ruleAllowEditMessage => '白名单是放行名单，改动它可能让本应被拦截的流量通过。确认你清楚这条风险后再开启。';

  @override
  String ruleTally(int matched, int enabled) {
    return '共 $matched 条 · 启用 $enabled';
  }

  @override
  String ruleNoRulesForKind(String kind) {
    return '还没有$kind规则';
  }

  @override
  String ruleClearCustomForKind(String kind) {
    return '清空自定义$kind';
  }

  @override
  String get subsPickTxt => '请选择扩展名为 .txt 的规则文件';

  @override
  String get subsNoPersistPermission => '系统未授予长期读取权限，更新时需要重新选择文件';

  @override
  String get subsGroupNameRequired => '分组名称不能为空';

  @override
  String get subsEdit => '编辑订阅';

  @override
  String get subsAdd => '添加订阅';

  @override
  String get subsSaveTooltip => '保存订阅';

  @override
  String get subsInfoSection => '订阅信息';

  @override
  String get subsSourceType => '订阅方式';

  @override
  String get subsSourceLocalPick => '从存储中选择一个 .txt 文件';

  @override
  String get subsSourceRemoteDownload => '从网络地址下载规则正文';

  @override
  String get subsLocalRuleFile => '本地规则文件';

  @override
  String get subsLocalFileSubscription => '本地文件订阅';

  @override
  String get subsPickFile => '选择规则文件';

  @override
  String get subsLocalFileHint => '仅支持 .txt，点击从存储中选择';

  @override
  String get subsLocalFileRepick => '点击可重新选择文件';

  @override
  String get subsChoose => '选择';

  @override
  String get subsNameOptional => '名称（可选）';

  @override
  String get subsNameEmptyFileName => '留空则取文件名';

  @override
  String get subsUrl => '订阅地址';

  @override
  String get subsNameEmptyUrlTail => '留空则取链接末段';

  @override
  String get subsRuleType => '规则类型';

  @override
  String get subsKindHostsHint => '仅导入 hosts 地址与 CNAME 覆写规则';

  @override
  String get subsKindDomainHint => '导入域名规则与黑白名单';

  @override
  String get subsGroupHint => '分组只影响订阅页的筛选与批量更新，可稍后调整。';

  @override
  String get subsNewGroupShort => '+ 新建';

  @override
  String get subsMirrorTemplateFooter =>
      '镜像地址会把原始订阅地址改写成镜像前缀，常用于加速 GitHub 等慢速源。';

  @override
  String get subsAddMirrorTemplate => '添加镜像站模板';

  @override
  String get subsAddMirrorTemplateSubtitle => '还没有模板，先去保存一个常用的镜像前缀';

  @override
  String get subsMirrorFooter => '下载时先请求镜像地址；镜像失败且开启回退时，再试原始地址。';

  @override
  String get subsUseMirrorTemplate => '使用镜像站模板';

  @override
  String get subsUseMirrorTemplateSubtitle => '订阅源较慢或被限速时，改写下载地址';

  @override
  String get subsMirrorTemplate => '镜像模板';

  @override
  String get subsMirrorFallback => '失败后回退直连';

  @override
  String get subsMirrorFallbackSubtitle => '镜像请求失败时，改用原始订阅地址';

  @override
  String get subsEffectiveUrl => '实际请求地址';

  @override
  String get subsNothingToUpdate => '没有可更新的远程订阅';

  @override
  String get subsDeleteTitle => '删除订阅';

  @override
  String get subsRenameTitle => '重命名订阅';

  @override
  String get subsNameRequired => '名称不能为空';

  @override
  String get subsTitle => '订阅';

  @override
  String get subsUpdateAll => '更新全部订阅';

  @override
  String get subsCount => '订阅数';

  @override
  String get subsRuleCount => '已入库规则';

  @override
  String get subsAbnormal => '异常';

  @override
  String get subsUpdating => '正在更新订阅…';

  @override
  String get subsEmptyLabel => '还没有订阅';

  @override
  String get subsEmptyDescription => '订阅可以批量维护规则；更新会下载正文、解析并写入规则库，拦截随之生效。';

  @override
  String get subsUpdateFooter =>
      '更新会下载正文、解析成黑/白名单与覆写规则并写入规则库，同时替换该订阅上一次贡献的规则；元素隐藏规则本仓不注入，不计入条数。';

  @override
  String get subsAllGroups => '全部';

  @override
  String get subsNewGroupTitle => '新建分组';

  @override
  String get subsEditRemoteHint =>
      '修改链接或收录类型后会立即重新下载，并替换该订阅原有的规则；订阅方式与本地文件不可更改。';

  @override
  String get subsEditLocalHint =>
      '本地文件通过系统文件选择器读取，应用只保留读取权限；同名的黑白名单与 hosts 订阅互不影响。';

  @override
  String get subsAddRemoteHint =>
      '同一条链接可以为黑白名单和 hosts 各建一条订阅（唯一性按「链接 + 类型」判定），保存后会立即下载一次正文并写入规则库。';

  @override
  String get subsKindLabel => '收录类型';

  @override
  String get subsGroupLabel => '所属分组';

  @override
  String get subsMirrorTitle => '镜像加速';

  @override
  String subsDeleteMessage(String name) {
    return '删除「$name」后不可撤销。\n\n删除会同时移除这条订阅贡献的全部规则（来源标签 sub_<id>）。';
  }

  @override
  String subsTotal(int count) {
    return '共 $count 个订阅';
  }

  @override
  String subsGroupTotal(String count, int group) {
    return '「$group」下 $count 个订阅';
  }

  @override
  String get subsUpdateNow => '立即更新';

  @override
  String get subsReimport => '重新导入文件';

  @override
  String get subsRename => '重命名';

  @override
  String subsConsecutiveFailures(int count) {
    return '连续失败 $count 次';
  }

  @override
  String get subsMirrorFallbackShort => '镜像 · 可回退';

  @override
  String get subsMirrorNoFallback => '镜像 · 不回退';

  @override
  String get subsLastUpdateFailed => '上次更新失败';

  @override
  String get subsNeverUpdated => '从未成功更新';

  @override
  String subsRuleCountValue(String count) {
    return '$count 条';
  }

  @override
  String subsRulesStored(String action, String count) {
    return '已入库 $count 条规则；$action该订阅贡献的规则。';
  }

  @override
  String get subsActionRemote => '更新会重新下载并替换';

  @override
  String get subsActionLocal => '重新导入会重新读取该文件并替换';

  @override
  String get subsPickRuleFile => '请选择一个规则文件';

  @override
  String get subsChange => '更换';

  @override
  String get subsGroupShort => '+ 分组';

  @override
  String get subsManageGroupsShort => '管理分组';

  @override
  String get subsManageGroupsTitle => '分组管理';

  @override
  String get subsGroupRenameTitle => '重命名分组';

  @override
  String get subsGroupDeleteTitle => '删除分组';

  @override
  String subsGroupDeleteMessage(String name) {
    return '删除「$name」后，组内订阅会移到未分组，订阅与规则本身不会被删除。';
  }

  @override
  String get subsGroupDuplicate => '已存在同名分组';

  @override
  String subsGroupSubCount(int count) {
    return '$count 个订阅';
  }

  @override
  String get subsGroupsEmpty => '还没有分组';

  @override
  String get subsGroupsEmptyHint => '点击右上角新建分组，之后可以在这里重命名或删除。';

  @override
  String get subsGroupsFooter => '分组只影响订阅页的筛选与批量更新；删除分组不会删除订阅或规则。';

  @override
  String subsMirrorName(String mirror) {
    return '镜像 $mirror';
  }

  @override
  String get trafficPackageName => '包名';

  @override
  String get trafficAppName => '应用名';

  @override
  String get trafficDown => '下行流量';

  @override
  String get trafficUp => '上行流量';

  @override
  String get trafficTotal => '合计';

  @override
  String get trafficShare => '占比';

  @override
  String get trafficStartDate => '统计起始日';

  @override
  String get trafficLastUpdate => '最后更新';

  @override
  String get trafficAttributionFooter =>
      '流量按 UID 归因到应用（上游 TrafficAttributionDialog 的口径）；同一应用的多进程流量合并计算。';

  @override
  String get trafficAttributionTitle => '流量归因说明';

  @override
  String get trafficScopeTitle => '统计口径';

  @override
  String get trafficScopeBody =>
      '流量按 UID 归因：每个应用的上下行字节数由引擎按 UID 累计后按天落库（表 app_traffic_daily，主键是「日期 + 包名」），不走包名匹配，因此共享 UID 的应用会合并成一项。';

  @override
  String get trafficWhyLowerTitle => '为什么数字比系统设置里少';

  @override
  String get trafficWhyLowerBody =>
      '这里只统计经过本机隧道处理的流量，未进入隧道的直连流量不计入；系统设置里的统计包含全部网卡流量。';

  @override
  String get trafficWhyNoRateTitle => '为什么没有实时速率';

  @override
  String get trafficWhyNoRateBody =>
      '实时速率需要内核每秒回报的速率序列；本仓的按天流量表只有「日期 + 包名 + 上下行累计字节」，没有速率列。因此「本次会话」窗口与「按实时速率」排序不可用，页面上也没有速率曲线——页面里出现的每个数字都是真实字节数。';

  @override
  String get trafficRetentionTitle => '记录保留多久';

  @override
  String get trafficRetentionBody => '按天保留，由原生侧的清理策略删除过期行；「全部历史」档位汇总表里现存的全部日期。';

  @override
  String get trafficSystemAppsTitle => '系统应用怎么识别';

  @override
  String get trafficSystemAppsBody =>
      '流量表里没有系统应用标记，页面按旧版 SystemAppClassifier 的同一份前缀表识别（android、com.android.*、各厂商预装前缀等）。「隐藏系统应用」开关的状态落在 traffic_stats_hide_system_apps。';

  @override
  String get trafficUpstreamFooter =>
      '上游对应 ui/traffic/TrafficAttributionDialog.kt 与 AppTrafficDetailDialog.kt；本页数字来自 app_traffic_daily。';

  @override
  String get trafficTitle => '流量统计';

  @override
  String get trafficClearHistory => '清除历史';

  @override
  String get trafficRefresh => '刷新';

  @override
  String get trafficAttribution => '归因说明';

  @override
  String get trafficLoadFailed => '无法读取流量记录';

  @override
  String get trafficLoading => '正在读取流量记录';

  @override
  String get trafficAppCount => '应用数';

  @override
  String get trafficAppCountUnit => '个';

  @override
  String get trafficNoData => '暂无流量数据';

  @override
  String get trafficNoMatchingApps => '没有匹配的应用';

  @override
  String get trafficRankingTitle => '应用流量排行';

  @override
  String trafficShareFooter(String range, String window) {
    return '占比按$window总字节数（下行 + 上行）计算；$range。点按一行查看该应用的上下行明细。';
  }

  @override
  String get trafficClearTitle => '清除全部流量记录？';

  @override
  String get trafficConfirmClear => '确认清除';

  @override
  String get trafficClearBody => '此操作将清空所有已持久化的应用历史流量统计，清除后无法恢复。';

  @override
  String get trafficRangeAllHistory => '范围为全部历史记录';

  @override
  String get trafficSessionRange => '本次会话';

  @override
  String get trafficSessionUnavailable => '「本次会话」需要内核按会话回报流量，本仓只有按天落库的历史记录';

  @override
  String get trafficLiveRate => '按实时速率';

  @override
  String get trafficHideSystemApps => '隐藏系统应用';

  @override
  String get trafficSearchHint => '搜索应用名或包名';

  @override
  String get trafficAllHistory => '全部历史';

  @override
  String get trafficLiveRateUnavailable => '「按实时网速」需要每秒速率，本仓的按天表里没有速率列';

  @override
  String get trafficHideSystemAppsSubtitle => '按系统应用标记与厂商预装前缀识别，隐藏后不计入排行';

  @override
  String trafficWindowLabelDate(String date) {
    return '统计日期 $date';
  }

  @override
  String trafficWindowLabelRange(String end, String start) {
    return '统计范围 $start 至 $end';
  }

  @override
  String trafficShareWindow(String range, String window) {
    return '占比按$window总字节数（下行 + 上行）计算；$range。点按一行查看该应用的上下行明细。';
  }

  @override
  String trafficTotalApps(int count, String total) {
    return '共 $count 个应用产生流量 · 合计 $total';
  }

  @override
  String trafficSearchEmpty(String search) {
    return '没有应用名或包名包含「$search」。';
  }

  @override
  String trafficHiddenCount(int count) {
    return '本次共有 $count 个应用被「隐藏系统应用」过滤掉，关闭该开关即可看到。';
  }

  @override
  String get trafficNoRecordsBody =>
      '流量按天由原生侧汇总落库；启动隧道并产生流量后，这里会出现各应用的下行 / 上行字节数。';

  @override
  String trafficNoRecordsForWindow(String window) {
    return '「$window」还没有流量记录。流量按天由原生侧汇总落库，换个时间窗口或启动隧道产生流量后再看。';
  }

  @override
  String trafficOptionUnavailable(String label, String reason) {
    return '「$label」不可用：$reason';
  }

  @override
  String get trafficNoSourceReason => '本仓没有对应的数据来源';

  @override
  String trafficCleared(int count) {
    return '已清除 $count 条流量记录';
  }

  @override
  String trafficClearFailed(String detail) {
    return '清除失败：$detail';
  }

  @override
  String trafficShareBarTooltip(String sort, String value) {
    return '占比条长度是这一行按「$sort」在当前窗口总量里的份额（当前 $value），与列表排序一致。';
  }

  @override
  String get trafficWhyDaemonTitle => '为什么系统设置将全部流量算给谛听？';

  @override
  String get trafficWhyDaemonBody =>
      '因 Android VPN 机制，系统将代理出站归属于守护进程。谛听自身不偷跑流量，点按查看统计口径。';

  @override
  String get trafficLiveRateTitle => '实时速率';

  @override
  String trafficNoLiveRate(String window) {
    return '本模式不统计实时速率：极速模式的窄路由不经过引擎的流量计数器，本仓也没有它的累计表。上面的 $window 下行 / 上行与下方排行都是真实数字。';
  }

  @override
  String trafficLiveRateBody(String window) {
    return '来自引擎的每秒速率（本次会话），与常驻通知里的读数同源；上面的 $window 下行 / 上行是 `app_traffic_daily` 的累计字节，两者口径不同，数字不必相等。';
  }

  @override
  String get trafficSearchPlaceholder => '搜索应用或包名...';

  @override
  String trafficWindowDown(String window) {
    return '$window下行';
  }

  @override
  String trafficWindowUp(String window) {
    return '$window上行';
  }

  @override
  String get obsRequestsTitle => '请求';

  @override
  String get obsSource => '来源';

  @override
  String get obsStatus => '状态';

  @override
  String get obsRefresh => '刷新';

  @override
  String get obsClearFilter => '清除筛选';

  @override
  String get obsLoadFailed => '无法读取请求记录';

  @override
  String get obsLoading => '正在读取请求记录';

  @override
  String get obsNoRecords => '还没有请求记录';

  @override
  String get obsNoMatchingRequests => '没有符合条件的请求';

  @override
  String get obsNoRecordsBody => '应用发出请求后会在这里留下记录；HTTPS 记录需要开启流量检查。';

  @override
  String get obsResetFilter => '重置筛选条件';

  @override
  String get obsRecordsHeader => '请求记录';

  @override
  String get obsRetry => '重试';

  @override
  String get obsBypassedDns => '直连，未经过 DNS 解析流程';

  @override
  String get obsBlockedDns => '被过滤规则拦截，未发出查询';

  @override
  String get obsRewrittenDns => '命中了覆写规则，返回改写后的结果';

  @override
  String get obsErrorDns => '解析过程出错，未取得应答';

  @override
  String get obsPassedDns => '按规则解析并正常返回';

  @override
  String get obsPassedHttps => '按规则转发成功';

  @override
  String get obsRewrittenHttps => '命中了覆写规则，返回改写后的请求';

  @override
  String get obsBlockedHttps => '被过滤规则拦截，未建立连接';

  @override
  String get obsBypassedHttps => '未解密直接转发（旁路）';

  @override
  String get obsErrorHttps => '处理过程出错';

  @override
  String get obsNoRuleHttps => '未命中规则（或未记录规则）';

  @override
  String get obsNone => '无';

  @override
  String get obsRequestDetailTitle => '请求详情';

  @override
  String get obsCachedChip => '缓存';

  @override
  String get obsBasicInfo => '基础信息';

  @override
  String get obsTime => '时间';

  @override
  String get obsProtocol => '协议';

  @override
  String get obsAppPackage => '应用包名';

  @override
  String get obsResolved => '解析结果';

  @override
  String get obsElapsed => '耗时';

  @override
  String get obsBlockingSubscription => '拦截订阅';

  @override
  String get obsRuleMatch => '规则命中';

  @override
  String get obsRule => '规则';

  @override
  String get obsHandling => '处理方式';

  @override
  String get obsError => '错误';

  @override
  String get obsAiAnalysis => 'AI 分析';

  @override
  String get obsRawRecord => '原始记录';

  @override
  String get obsRawRecordFooter => '引擎写入 message 字段的原文，未经改写。';

  @override
  String get obsFailedHint => '处理失败的请求可在「连接」页配合查看对应的活动连接。';

  @override
  String get obsRulesHint => '加入的黑白名单可在「规则」页查看和撤销。';

  @override
  String get obsCacheHit => '缓存命中';

  @override
  String obsCopied(String text) {
    return '已复制 $text';
  }

  @override
  String get obsCopyAddress => '复制地址';

  @override
  String get obsCopyDomain => '复制域名';

  @override
  String get obsInBlocklist => '已在黑名单';

  @override
  String get obsAddToBlocklist => '加入黑名单';

  @override
  String get obsInAllowlist => '已在白名单';

  @override
  String get obsAddToAllowlist => '加入白名单';

  @override
  String get obsIpOnlyFooter => '该记录只有 IP 地址，域名规则无法匹配，因此不能加入黑白名单。';

  @override
  String get obsAnalyzeRequest => '分析这条请求';

  @override
  String get obsAnalyzeRequestBody => '用配置的模型研判归属、风险与处置建议';

  @override
  String obsCopiedHost(String host) {
    return '已复制 $host';
  }

  @override
  String obsAddedToKind(String domain, String kind) {
    return '已将 $domain 加入$kind';
  }

  @override
  String obsAlreadyInKind(String domain, String kind) {
    return '$domain 已在$kind中';
  }

  @override
  String obsCurrentFilter(String filter) {
    return '当前筛选：$filter。';
  }

  @override
  String obsFooterCount(int count, int failed, String filter, String more) {
    return '共 $count 条，其中 $failed 条处理失败$filter$more。点按一行查看规则命中与处理结果。';
  }

  @override
  String obsFooterFilter(String filter) {
    return '（筛选：$filter）';
  }

  @override
  String get obsFooterMore => '；继续下滑加载更多';

  @override
  String get obsFooterAll => '；已加载全部';

  @override
  String get obsByApp => '按应用查看';

  @override
  String get obsViewAppRequests => '查看该应用的请求记录';

  @override
  String get obsAppsTitle => '按应用查看';

  @override
  String get obsAppsHeader => '应用';

  @override
  String get obsAppsEmpty => '还没有带应用归属的请求';

  @override
  String get obsAppsEmptyBody => '请求记录中带有应用包名时，会按应用汇总在这里。';

  @override
  String get obsAppsFooter => '按请求次数从多到少排列，统计范围为当前保留的全部请求记录。点按一个应用查看它的请求。';

  @override
  String obsAppRequestCount(int count) {
    return '$count 次请求';
  }

  @override
  String get obsExportLogs => '导出日志';

  @override
  String get obsExportTitle => '导出请求日志';

  @override
  String get obsExportRangeSection => '时间范围';

  @override
  String get obsExportRangeAll => '全部时间';

  @override
  String get obsExportRangeHour => '最近 1 小时';

  @override
  String get obsExportRangeDay => '最近 24 小时';

  @override
  String get obsExportRangeWeek => '最近 7 天';

  @override
  String get obsExportRangeCustom => '自定义';

  @override
  String get obsExportCustomRange => '起止日期';

  @override
  String get obsExportPickRange => '点击选择起止日期';

  @override
  String get obsExportScopeSection => '筛选条件';

  @override
  String get obsExportIntro => '选择时间范围、请求来源、状态与应用，再勾选需要导出的字段。';

  @override
  String get obsExportDnsOnlyNote => '当前模式没有 HTTPS 请求日志，导出仅包含 DNS 记录';

  @override
  String get obsExportApps => '应用';

  @override
  String get obsExportAllApps => '全部应用';

  @override
  String obsExportSelectedApps(int count) {
    return '已选 $count 个应用';
  }

  @override
  String obsExportSelectedColumns(int count) {
    return '已选 $count 个字段';
  }

  @override
  String get obsExportAppPickerTitle => '选择应用';

  @override
  String get obsExportAppPickerDone => '完成';

  @override
  String get obsExportColumnsSection => '包含字段';

  @override
  String get obsExportColumnTime => '时间';

  @override
  String get obsExportColumnSource => '来源';

  @override
  String get obsExportColumnStatus => '状态';

  @override
  String get obsExportColumnAppName => '应用名称';

  @override
  String get obsExportColumnPackage => '应用包名';

  @override
  String get obsExportColumnHost => '主机/查询';

  @override
  String get obsExportColumnProtocol => '协议';

  @override
  String get obsExportColumnRule => '匹配规则';

  @override
  String get obsExportColumnElapsed => '耗时(ms)';

  @override
  String get obsExportColumnCached => '缓存';

  @override
  String get obsExportColumnSubscription => '拦截订阅';

  @override
  String get obsExportColumnMessage => '原始消息';

  @override
  String get obsExportCachedYes => '是';

  @override
  String get obsExportCachedNo => '否';

  @override
  String get obsExportLimit => '条数上限';

  @override
  String obsExportLimitHint(int max) {
    return '1–$max';
  }

  @override
  String get obsExportAction => '导出 CSV';

  @override
  String get obsExportBusy => '正在导出…';

  @override
  String obsExportDone(int count) {
    return '已导出 $count 条记录';
  }

  @override
  String get obsExportEmpty => '没有符合条件的记录，未生成文件';

  @override
  String get obsExportCancelled => '已取消导出';

  @override
  String get obsExportFailed => '导出失败';

  @override
  String obsExportTruncated(int count) {
    return '已达到 $count 条上限';
  }

  @override
  String get obsExportFooter => 'CSV 文件（UTF-8），可用表格软件打开。';

  @override
  String get obsExportAtLeastOneColumn => '至少选择一个字段';

  @override
  String obsExportInvalidLimit(int max) {
    return '请输入 1–$max 之间的条数';
  }

  @override
  String get logsSubStatsTitle => '订阅拦截率';

  @override
  String get logsRefresh => '刷新';

  @override
  String get logsTimeRange => '时间范围';

  @override
  String get logsSubStatsFooter =>
      '拦截率为所选时间范围内，该订阅拦截请求数占全部已记录请求（DNS + HTTPS）的比例。';

  @override
  String get logsOverview => '概览';

  @override
  String get logsSubStatsLoadFailed => '无法读取拦截统计';

  @override
  String get logsLoadingStats => '正在加载统计数据';

  @override
  String get logsBlockingSubs => '屏蔽订阅';

  @override
  String get logsMissingSubColumn => '当前数据库缺少订阅标记列';

  @override
  String get logsMissingSubColumnBody =>
      '这张库是在加入「订阅拦截统计」之前创建的，日志行里没有记录 blockSubscriptionId。重新产生请求日志后即可统计，历史数据无法补算。';

  @override
  String get logsAllRecordedRequests => '全部已记录请求';

  @override
  String get logsBlockedRequests => '拦截请求';

  @override
  String get logsAllRecordedFooter => 'DNS 与 HTTPS 日志合计，含通过、屏蔽和失败。';

  @override
  String get logsNoBlockingSubs => '暂无屏蔽订阅';

  @override
  String get logsNoBlockingSubsBody => '导入屏蔽订阅并产生 DNS 或 HTTPS 请求后，此处将显示其拦截率。';

  @override
  String get logsBlockingSubsFooter => '按拦截次数排序；「已删除」表示订阅已移除，但历史命中仍保留。';

  @override
  String get logsExpired => '已过期';

  @override
  String get logsRaceTitle => '竞速统计';

  @override
  String get logsRaceFooter => '只统计真实发出过 DoH 请求的竞速解析；本机缓存命中的查询不进这张表。';

  @override
  String get logsRaceLoadFailed => '无法读取竞速记录';

  @override
  String get logsLoadingRace => '正在读取竞速记录';

  @override
  String logsRaceSummary(String range, String count) {
    return '$range内共 $count 次竞速解析。';
  }

  @override
  String get logsRaceEmptyRange => '所选时间范围内还没有竞速记录。';

  @override
  String get logsRaceRequests => '竞速请求';

  @override
  String get logsSuccess => '成功';

  @override
  String get logsAverageElapsed => '平均耗时';

  @override
  String get logsStrategyOverview => '策略概览';

  @override
  String get logsStrategyFooter =>
      '缓存命中的请求不触发竞速，因此不进这张表；首选命中率 = 首选服务商即胜出且成功的比例。';

  @override
  String get logsWinnerProviders => '胜出服务商';

  @override
  String get logsNoWinners => '还没有胜出记录';

  @override
  String get logsNoWinnersBody => '竞速解析成功后，胜出的服务商会在这里按次数排序。';

  @override
  String get logsWinnerFooter => '按胜出次数排序；平均耗时是该服务商胜出时的耗时均值。';

  @override
  String logsAverageWinLatency(String latency) {
    return '平均胜出耗时 $latency';
  }

  @override
  String get logsSmartPrimary => '智能选择首选';

  @override
  String get logsSmartPrimaryFooter =>
      '只有智能选择策略下才有意义；首选命中率统计「首选服务商就是胜出者」的比例，兜底救回的查询不计入。';

  @override
  String logsPrimaryHit(String percent, String latency) {
    return '首选命中 $percent · 平均首选耗时 $latency';
  }

  @override
  String get logsDashboardTitle => '日志仪表盘';

  @override
  String get logsModeTooltip => '日志模式';

  @override
  String get logsRequestsDashboard => '请求日志仪表盘';

  @override
  String get logsRequestsDashboardBody => '全部 DNS、HTTPS、缓存、竞速与规则拦截的实时概览';

  @override
  String get logsFocusedDashboard => '重点请求仪表盘';

  @override
  String get logsFocusedDashboardBody => 'DNS 与 HTTPS 拦截、错误、旁路记录及解析状态概览';

  @override
  String get logsServiceOverview => '服务状态与解析概览';

  @override
  String get logsPrivacyBody => '当前处于隐私模式，不记录请求明细。DNS 缓存、并发竞速与网络流量监控仍正常运行。';

  @override
  String get logsCacheTableTitle => 'DNS 缓存表';

  @override
  String logsCacheLoadFailed(String detail) {
    return '无法读取缓存表：$detail';
  }

  @override
  String get logsLoadingCache => '正在读取缓存表';

  @override
  String get logsCacheEmpty => '缓存表还没有条目';

  @override
  String get logsCacheNoMatch => '没有匹配的缓存';

  @override
  String get logsCacheEmptyBody =>
      '引擎解析成功后会把应答写进 dns_cache；全新安装或隧道刚启动时这张表可能还是空的。';

  @override
  String logsCurrentSearch(String query) {
    return '当前搜索：$query';
  }

  @override
  String get logsLiveCache => '有效缓存';

  @override
  String get logsNeverHit => '尚未命中';

  @override
  String logsCacheFooter(String count) {
    return '共 $count 条，按命中次数与过期时间排序。剩余 TTL 少于 30 秒的条目标橙色。点按一行查看详情，可复制域名、加入黑白名单或用 AI 分析。';
  }

  @override
  String get logsBootstrapTitle => 'Bootstrap 统计';

  @override
  String get logsBootstrapFooter => '成功率为成功次数 ÷ 尝试次数；平均耗时按各节点的尝试次数加权。';

  @override
  String get logsBootstrapLoadFailed => '无法读取 Bootstrap 记录';

  @override
  String get logsLoadingBootstrap => '正在读取 Bootstrap 记录';

  @override
  String logsBootstrapSummary(String range, String count) {
    return '$range内共 $count 次 Bootstrap 探测。';
  }

  @override
  String get logsBootstrapEmptyRange => '所选时间范围内还没有 Bootstrap 探测记录。';

  @override
  String get logsAttempts => '尝试次数';

  @override
  String get logsSuccessRate => '成功率';

  @override
  String get logsNodes => '节点';

  @override
  String get logsNoProbes => '还没有探测记录';

  @override
  String get logsNoProbesBody => '开启「启用 Bootstrap IP」并产生解析后，各节点的尝试与成功率会出现在这里。';

  @override
  String get logsNodesFooter => '按尝试次数排序；显示最近窗口内的聚合值。';

  @override
  String get logsCacheDetailTitle => '缓存详情';

  @override
  String get logsCacheExpiringBody => '缓存即将过期，过期后下一次查询会重新向上游解析';

  @override
  String get logsCacheValidBody => '缓存有效，命中时直接返回应答，不再请求上游';

  @override
  String get logsExpiring => '即将过期';

  @override
  String get logsValid => '有效';

  @override
  String logsHitTimes(int count) {
    return '命中 $count 次';
  }

  @override
  String get logsCacheInfo => '缓存信息';

  @override
  String get logsRecordType => '记录类型';

  @override
  String get logsRemainingTtl => '剩余 TTL';

  @override
  String get logsOriginalTtl => '原始 TTL';

  @override
  String get logsExpiry => '过期时间';

  @override
  String get logsHitCount => '命中次数';

  @override
  String get logsLastHit => '最后命中';

  @override
  String get logsResponseSize => '应答大小';

  @override
  String get logsAnalyzeDomain => '分析这个域名';

  @override
  String get logsCacheDetailFooter =>
      '缓存表每 10 秒从引擎内存同步一次，这里是打开时的快照。加入的黑白名单可在「规则」页查看和撤销。';

  @override
  String get logsAiInsight => 'AI 研判';

  @override
  String get logsNotAnalysed => '未分析';

  @override
  String get logsHasReport => '已有结论';

  @override
  String get logsAiInsightBody =>
      '把最近的 DNS 与 HTTPS 记录交给配置的模型，汇总异常请求、防护效果与优化建议。';

  @override
  String get logsAnalyseTraffic => '用 AI 研判最近流量';

  @override
  String get logsViewFullReport => '查看完整报告';

  @override
  String logsModelName(String model) {
    return '模型 $model';
  }

  @override
  String logsSuccessWith(String percent) {
    return '成功 $percent';
  }

  @override
  String logsAverageWith(String latency) {
    return '平均 $latency';
  }

  @override
  String logsPrimaryHitOnly(String percent) {
    return '首选命中 $percent';
  }

  @override
  String logsFallbackUses(String count) {
    return '兜底 $count 次';
  }

  @override
  String logsBootstrapRow(
    String ip,
    String percent,
    String latency,
    String failures,
  ) {
    return '$ip · 成功 $percent · 平均 $latency$failures';
  }

  @override
  String logsBootstrapFailures(String count) {
    return ' · 失败 $count 次';
  }

  @override
  String logsEntryCount(int count) {
    return '$count 条';
  }

  @override
  String logsCacheRow(String ttl, int count, int size) {
    return '$ttl · 命中 $count 次 · $size B';
  }

  @override
  String logsLastHitAt(String time) {
    return '最后命中 $time';
  }

  @override
  String logsCacheFooterCount(int count) {
    return '共 $count 条，按命中次数与过期时间排序。剩余 TTL 少于 30 秒的条目标橙色。点按一行查看详情，可复制域名、加入黑白名单或用 AI 分析。';
  }

  @override
  String logsSubStatsRow(String status, String count) {
    return '$status · 拦截 $count 次';
  }

  @override
  String get aboutTitle => '关于';

  @override
  String get aboutMore => '更多';

  @override
  String get aboutProject => '项目';

  @override
  String get aboutJoinQq => '加入 QQ 群';

  @override
  String aboutQqGroup(String number) {
    return '群号 $number';
  }

  @override
  String get aboutSponsor => '赞助';

  @override
  String get aboutCredits => '开源致谢';

  @override
  String get aboutCreditsUi => '界面组件与交互实现复用自该项目';

  @override
  String get aboutCreditsCore => 'Go 隧道内核最初魔改自该项目';

  @override
  String get aboutCreditsBody =>
      '上述两个项目均以 GPL-3.0 协议开源，相关代码与设计的版权归各自作者所有。谛听的界面层大量借鉴了 FlClash 的实现思路，隧道内核也源自 blockads-android 的早期改造；在此向它们的作者与所有贡献者致以诚挚谢意。';

  @override
  String get aboutSettings => '设置';

  @override
  String get aboutStartupCheck => '关闭启动时检查更新';

  @override
  String get aboutStartupCheckOn => '应用启动时不自动检查，可随时手动检查';

  @override
  String get aboutStartupCheckOff => '应用启动时自动检查新版本';

  @override
  String get aboutDisclaimerEntry => '使用须知与免责声明';

  @override
  String get aboutDisclaimerEntryBody => '软件说明、运行机制与免责条款全文';

  @override
  String get aboutOtherContributors => '其他贡献者';

  @override
  String get aboutSponsorList => '赞助者名单';

  @override
  String get aboutSponsorListBody => '鸣谢支持谛听项目的赞助者';

  @override
  String get aboutBuilderList => '共建者名单';

  @override
  String get aboutBuilderListBody => '感谢为谛听贡献代码与建议的共建者';

  @override
  String get aboutInstallerFailed => '无法调起系统安装器';

  @override
  String get aboutAppName => '谛听';

  @override
  String get aboutTagline =>
      '基于 Android VpnService 的本地优先 DNS 加速与流量过滤工具，简单易用，开源无广告。';

  @override
  String get aboutChecking => '检查中…';

  @override
  String get aboutCheckUpdate => '检查更新';

  @override
  String get aboutDownloading => '下载中…';

  @override
  String get aboutInstall => '安装';

  @override
  String get aboutDownload => '下载';

  @override
  String get aboutCheckingRelease => '正在检查 GitHub Release';

  @override
  String aboutUpToDate(String version) {
    return '当前已是最新版本$version';
  }

  @override
  String aboutVersionSuffix(String version) {
    return '（$version）';
  }

  @override
  String aboutFoundVersion(String version) {
    return '发现 $version版本';
  }

  @override
  String aboutCurrentSuffix(String version) {
    return '（当前 $version）';
  }

  @override
  String get aboutNew => '新';

  @override
  String get aboutNewVersion => '新版本';

  @override
  String aboutUpdatePackage(String version) {
    return '$version 更新包';
  }

  @override
  String aboutLinkCopyFallback(String url) {
    return '未能打开浏览器，链接已复制：$url';
  }

  @override
  String get devStressLogs => '日志压测';

  @override
  String devStressLogsBody(int count) {
    return '向当前模式的日志库真实写入 $count 条 DNS 日志';
  }

  @override
  String get devErrorReport => '错误上报自检';

  @override
  String get devErrorReportBody => '通过 FlutterError 上报一条测试异常，验证错误链路';

  @override
  String get devClearAll => '清空全部数据';

  @override
  String get devClearAllBody => '删除配置、规则与日志，恢复出厂状态';

  @override
  String get devVacuum => '压缩数据库';

  @override
  String get devVacuumBody => '对三个本地库执行 VACUUM，回收已删除记录占用的空间';

  @override
  String get devCancel => '取消';

  @override
  String get devRun => '执行';

  @override
  String devConfirmBody(String action) {
    return '$action\n\n该操作会真正改写本机数据，无法撤销。';
  }

  @override
  String devActionFailed(String action, String error) {
    return '$action失败：$error';
  }

  @override
  String get devStressNoDb => '日志压测失败：无法打开日志数据库';

  @override
  String devStressDone(String count, String file) {
    return '日志压测完成：写入 $count 条到 $file';
  }

  @override
  String get devTestException => '开发者选项触发的测试异常';

  @override
  String get devErrorReported => '已上报一条 FlutterError：开发者选项触发的测试异常';

  @override
  String get devVacuumNoDb => '压缩数据库失败：本机还没有数据库文件';

  @override
  String devVacuumDone(String files, int kb) {
    return '已压缩 $files，回收 $kb KB';
  }

  @override
  String get devRestartNeeded => '需要重启';

  @override
  String get devLater => '稍后';

  @override
  String get devQuitNow => '立即退出';

  @override
  String get devClearAllDone => '全部数据已清空，需要重新启动应用才能从出厂状态进入。';

  @override
  String get devOptions => '开发者选项';

  @override
  String get devDiagnostics => '诊断与观测';

  @override
  String get devIpQuality => 'IP 质量';

  @override
  String get devIpQualityBody => '实测出口地址与三个公开情报源的类型判断';

  @override
  String get devRequestLogs => '请求日志';

  @override
  String get devRequestLogsBody => '合并 http_request_log 与 dns_log 的实时请求记录';

  @override
  String get devLogRetention => '日志保留';

  @override
  String get devLogRetentionBody => '日志容量上限与 DNS 请求日志的记录范围';

  @override
  String get devTroubleshoot => '故障排查';

  @override
  String get devTroubleshootBody => '导出崩溃日志，手动抓取并导出运行日志';

  @override
  String get devDataCleanup => '数据清理';

  @override
  String get devUnlocked => '实验动作已解锁';

  @override
  String get devLocked => '关闭时下面的动作不可用';

  @override
  String get devWarning =>
      '这里的动作会真的改写本机数据（日志库、prefs、数据库文件），其中「清空全部数据」不可撤销，不要在生产环境打开。';

  @override
  String get devRunning => '执行中…';

  @override
  String get sponsorGithub => '在 GitHub 查看赞助方式';

  @override
  String get sponsorReadme => '查看 README 中的赞助说明';

  @override
  String get sponsorReadmeCopied => '未能打开浏览器，README 地址已复制';

  @override
  String get sponsorThanks => '致谢名单';

  @override
  String get sponsorThanksBody => '感谢每一位支持项目的朋友';

  @override
  String get sponsorBuildersBody => '感谢提出建议与帮助测试的伙伴';

  @override
  String get sponsorUsage => '你的每一笔支持都会用于';

  @override
  String get sponsorUsageNewFeatures => '持续开发新功能';

  @override
  String get sponsorUsageBugs => '修复 Bug';

  @override
  String get sponsorUsageTokens => '购买词元';

  @override
  String get sponsorFreeWays => '即使不捐赠，也欢迎';

  @override
  String get sponsorFreeStar => '点一个 Star⭐';

  @override
  String get sponsorFreeIssue => '提交 Issue';

  @override
  String get sponsorFreePr => '提交 PR';

  @override
  String get sponsorFreeShare => '分享给更多人';

  @override
  String get sponsorFooter => '感谢每一位支持项目的朋友！';

  @override
  String get sponsorBuyDrink => '请作者喝杯蜜雪 🧋';

  @override
  String get sponsorSupportKicker => '// 支持项目';

  @override
  String get sponsorNote => '如果这个项目帮助到了你，欢迎请作者喝杯蜜雪。付款时请备注昵称，以便同步加入赞助者名单。';

  @override
  String get sponsorAlipay => '支付宝';

  @override
  String get sponsorWechat => '微信支付';

  @override
  String get sponsorNickname => '备注昵称';

  @override
  String get sponsorScan => '扫码赞助';

  @override
  String sponsorQrCode(String label) {
    return '$label 收款码';
  }

  @override
  String get sponsorClose => '关闭';

  @override
  String get sponsorNoteShort => '付款时请备注昵称，以便同步加入赞助者名单。';

  @override
  String aboutQqCopied(String number) {
    return '未检测到 QQ，群号已复制：$number';
  }

  @override
  String get disclaimerTitle => '免责声明';

  @override
  String get disclaimerTerms => '条款全文';

  @override
  String get disclaimerSource => '正式条款以仓库 NOTICE.md 与随包 LICENSE 为准。';

  @override
  String get ipQualityRedetect => '重新检测';

  @override
  String get ipQualityEgress => '当前出口地址';

  @override
  String get ipQualitySources => '来源';

  @override
  String get ipQualitySourcesFooter =>
      '各来源对「住宅 / 机房」的判断经常互相矛盾：命中数越多越可信，但单一来源的「风险」标签不足以作为结论。';

  @override
  String get ipQualityQuerying => '正在查询出口 IP 与 3 个情报源…';

  @override
  String get ipQualityChecking => '检测中…';

  @override
  String get ipQualityDetecting => '正在检测';

  @override
  String get ipQualityFailed => '检测失败';

  @override
  String get ipQualityNotYet => '尚未检测';

  @override
  String get ipQualityDetectingBody => '正在获取出口 IP 并查询情报源，请稍候';

  @override
  String get ipQualityStartBody => '点下方按钮开始检测当前出口 IP 的质量';

  @override
  String get ipQualityStart => '开始检测';

  @override
  String ipQualityJudgedAs(String type) {
    return '判定为$type';
  }

  @override
  String get ipQualityNotUsed => '未采用';

  @override
  String get ipQualityUsed => '已采用';

  @override
  String devFooterWarning(int count) {
    return '这些动作直接作用于本机的数据库、prefs 与 native 通道：日志压测会真的写入 $count 条日志，压缩数据库执行的是 SQLite VACUUM，清空全部数据会删除所有本地数据并要求重启。';
  }

  @override
  String get devDataCleanupBody => '按类别删除日志、权重、规则与缓存';

  @override
  String get devConfigSection => '配置与资源';

  @override
  String get devCustomResources => '自定义资源';

  @override
  String get devCustomResourcesBody => 'User-Agent、按需连接等配置资源入口';

  @override
  String get devUserAgentBody => '订阅下载与测速请求携带的 UA';

  @override
  String get devOnDemand => '按需连接';

  @override
  String get devOnDemandBody => '按 SSID 决定是否启动 VPN';

  @override
  String get devWebdav => 'WebDAV 云同步';

  @override
  String get devWebdavBody => '把备份真实上传到自建的 WebDAV 服务';

  @override
  String get devUiSection => '界面与外观保留项';

  @override
  String get devFontFamilyBody => '选择界面字体族，独立页';

  @override
  String get devFontSizeBody => '全局文字缩放；在外观设置「界面显示」组内联滑杆';

  @override
  String get devTabAnimation => 'Tab 动画';

  @override
  String get devTabAnimationBody => '切换底部标签时的入场动画；在外观设置「背景与动效」组内联选项';

  @override
  String get devExperimental => '实验动作';

  @override
  String get devLegacyFooter =>
      '以上「诊断与观测」「配置与资源」「界面与外观保留项」里的页面都不属于旧版 1.4.3 的界面，保留供调试与组件验收；旧版对应的功能仍按旧版菜单进入，不经过本页。';

  @override
  String get unknownRouteTitle => '页面不存在';

  @override
  String get unknownRouteBody => '找不到这个页面';

  @override
  String get unknownRouteBack => '返回';

  @override
  String get disclaimerReadFirst => '使用前请阅读';

  @override
  String get disclaimerIntro =>
      '谛听是一款开源的本地域名解析与流量观测工具。软件本身不提供、不代理、也不转发任何网络接入服务，全部数据都在本机处理。';

  @override
  String get disclaimerLawful =>
      '请在遵守所在地法律法规的前提下使用本软件。将本软件用于任何未经授权的网络环境，后果由使用者自行承担。';

  @override
  String get disclaimerFirstRun => '首次启动时确认的文本';

  @override
  String get disclaimerImmutable => '不可修改';

  @override
  String get devFontFamily => '字体';

  @override
  String get devFontSize => '字号';

  @override
  String get devWarningTitle => '开发者模式';

  @override
  String get devFooterLegacy =>
      '以上「诊断与观测」「配置与资源」「界面与外观保留项」里的页面都不属于旧版 1.4.3 的界面，保留供调试与组件验收；旧版对应的功能仍按旧版菜单进入，不经过本页。';

  @override
  String get ipTypeResidential => '住宅';

  @override
  String get ipTypeMobile => '移动';

  @override
  String get ipTypeBusiness => '商业';

  @override
  String get ipTypeHosting => '机房';

  @override
  String get ipLevelGood => '优秀';

  @override
  String get ipLevelNormal => '一般';

  @override
  String get ipLevelRisky => '风险';

  @override
  String get ipStatusOk => '命中';

  @override
  String get ipStatusNoType => '无类型';

  @override
  String get ipStatusTimeout => '超时';

  @override
  String get ipStatusRateLimited => '限流';

  @override
  String get ipStatusMismatch => 'IP 不一致';

  @override
  String get modeSelectTitle => '选择工作模式';

  @override
  String get modeContinue => '继续';

  @override
  String get modeSwitchNote => '随时可以在设置里重新选择；切换模式会先停止当前模式的服务，两个模式不会同时运行。';

  @override
  String get modeSharedNote =>
      '三种模式共用一套规则与缓存，区别在接管方式：普通模式走全隧道，服务器模式只做局域网 DNS，极速模式把路由收窄到只接管 DNS。';

  @override
  String get modeNormalFeature1 => '全隧道接管';

  @override
  String get modeNormalFeature1Body => 'Go 栈接管全部流量，可按应用分流';

  @override
  String get modeNormalFeature2 => '全功能规则';

  @override
  String get modeNormalFeature2Body => '黑白名单、覆写、HTTPS 检查全部可用';

  @override
  String get modeNormalFeature3 => '可选 HTTPS 检查';

  @override
  String get modeNormalFeature3Body => '需要安装并信任本地 CA 证书';

  @override
  String get modeNormalFeature4 => '应用流量统计';

  @override
  String get modeNormalFeature4Body => '按应用记录上下行与查询数';

  @override
  String get modeServerFeature1 => '局域网 DNS 服务';

  @override
  String get modeServerFeature1Body => '监听 0.0.0.0，供同一网段设备使用';

  @override
  String get modeServerFeature2 => '不占 VPN 槽位';

  @override
  String get modeServerFeature2Body => '本机不建立隧道，可与其它 VPN 共存';

  @override
  String get modeServerFeature3 => '共享规则与缓存';

  @override
  String get modeServerFeature3Body => '与普通模式共用同一套规则库';

  @override
  String get modeServerFeature4 => '低功耗';

  @override
  String get modeServerFeature4Body => '只处理 DNS 查询，无流量转发';

  @override
  String get modeExpressFeature1 => 'Go 引擎 + 窄路由';

  @override
  String get modeExpressFeature1Body => '只接管 DNS 端口，其余流量直连物理网络';

  @override
  String get modeExpressFeature2 => '四种上游调度';

  @override
  String get modeExpressFeature2Body => '单服务商 / 智能 / 竞速 / 主备';

  @override
  String get modeExpressFeature3 => '64 分片 LRU 缓存';

  @override
  String get modeExpressFeature3Body => '命中率高、内存占用可控';

  @override
  String get modeExpressFeature4 => '更低功耗';

  @override
  String get modeExpressFeature4Body => '只处理 DNS 查询，无全隧道转发';

  @override
  String get onboardingTitle => '引导';

  @override
  String get onboardingSkip => '跳过引导';

  @override
  String get onboardingPrev => '上一步';

  @override
  String get onboardingStart => '开始使用';

  @override
  String get onboardingNext => '下一步';

  @override
  String onboardingChosen(String mode) {
    return '你选择了$mode';
  }

  @override
  String get onboardingChangeable => '之后还能改';

  @override
  String get onboardingChangeableBody => '设置 → 重新选择工作模式，随时可以切换。切换会先停止当前模式的服务。';

  @override
  String get onboardingSharedRules => '规则与缓存共用';

  @override
  String get onboardingSharedRulesBody => '三种模式共享同一套黑白名单与 DNS 缓存，不必为每个模式重配一遍。';

  @override
  String get onboardingExclusive => '模式互斥';

  @override
  String get onboardingExclusiveBody => '同一时刻只有一个模式在运行；离开时会先停掉上一个模式。';

  @override
  String get permVpn => 'VPN 连接';

  @override
  String get permNotification => '通知';

  @override
  String get permAppList => '应用列表';

  @override
  String get permBattery => '忽略电池优化';

  @override
  String get permRequired => '必需';

  @override
  String get permOptional => '可选';

  @override
  String get permVpnNormalBody => '建立本地隧道接管流量；拒绝则无法启动';

  @override
  String get permNotificationBody => '前台服务常驻通知；拒绝则服务可能被系统回收';

  @override
  String get permAppListBody => '按应用分流与统计；拒绝则只能按域名规则';

  @override
  String get permBatteryBody => '避免后台被杀；拒绝则长时间待机可能断开';

  @override
  String get permBatteryServerBody => '避免后台被杀；拒绝则局域网内会间歇不可用';

  @override
  String get permVpnExpressBody => '建立窄路由隧道；拒绝则无法启动';

  @override
  String get permNeeded => '需要这些权限';

  @override
  String get permAllLocal => '全部权限只在本机使用，不会上传任何数据。';

  @override
  String permGrantedCount(String granted, String total) {
    return '已授予 $granted / $total 项；全部权限只在本机使用，不会上传任何数据。';
  }

  @override
  String get onboardingTipNormal1 => '点首页的大圆钮启动服务，第一次会弹出系统 VPN 授权。';

  @override
  String get onboardingTipNormal2 => '黑名单 / 白名单在「功能中心 → 规则与订阅」里维护。';

  @override
  String get onboardingTipNormal3 => '首页句子和透明度都能在设置里改。';

  @override
  String get onboardingTipServer1 => '启动后把同网段设备的 DNS 指向「局域网接入」里显示的地址。';

  @override
  String get onboardingTipServer2 => '端口可在「服务器模式」页改，默认 5353。';

  @override
  String get onboardingTipServer3 => '本模式不建立 VPN，可与其它 VPN 同时运行。';

  @override
  String get onboardingTipExpress1 => '极速模式启动更快，但功能是普通模式的子集。';

  @override
  String get onboardingTipExpress2 => '多路竞速至少要选 2 家服务商。';

  @override
  String get onboardingTipExpress3 => '需要 HTTPS 检查或应用管控时请切回普通模式。';

  @override
  String get onboardingReady => '可以开始了';

  @override
  String get onboardingReadyBody => '下面是三条最常用的上手要点。';

  @override
  String onboardingTipIndex(String index) {
    return '第 $index 条';
  }

  @override
  String permStillDenied(String name) {
    return '$name 仍未授予，请在系统设置里允许后返回本页';
  }

  @override
  String get permGranted => '已授予';

  @override
  String get permDenied => '未授予';

  @override
  String get permUnknown => '状态未知';

  @override
  String get permGrant => '去授予';

  @override
  String get toolSpeedTest => '测速';

  @override
  String get toolPing => 'Ping 测试';

  @override
  String get toolDnsLookup => 'DNS 解析';

  @override
  String get toolTraceroute => '路由追踪';

  @override
  String get toolDiagnostics => '网络诊断';

  @override
  String get toolRefreshInfo => '刷新网络信息';

  @override
  String get toolActiveInterface => '活动接口';

  @override
  String get toolLocalAddress => '本机地址';

  @override
  String get toolDnsServers => 'DNS 服务器';

  @override
  String get toolCountUnit => '个';

  @override
  String toolPrivateDnsProbe(String dns) {
    return '探测走物理网络（本应用流量不经过隧道）；系统私人 DNS：$dns';
  }

  @override
  String get toolPhysicalProbe => '探测走物理网络：本应用自身流量被排除在隧道外，下面四个工具测的都是物理链路的真实时延。';

  @override
  String get toolInputHostOrIp => '输入 IP 或域名';

  @override
  String get toolPingCount4 => '4 次';

  @override
  String get toolPingCount10 => '10 次';

  @override
  String get toolPingOptions => '探测选项';

  @override
  String get toolViaTunnel => '通过 Go 隧道解析';

  @override
  String get toolViaTunnelPingBody => '域名经运行中的 Go 隧道解析（应用覆写与过滤规则），探测仍走物理网络';

  @override
  String get toolStartPing => '开始 Ping';

  @override
  String get toolPinging => '正在探测…';

  @override
  String get toolTcpFallback =>
      '系统 ICMP 受限，已用 TCP 回退测量。此时的时延是连接建立耗时，不能与 ICMP 往返时延直接比较。';

  @override
  String get toolPingFailed => '探测失败：未收到任何回复';

  @override
  String get toolTarget => '目标';

  @override
  String get toolResolvedAddress => '解析地址';

  @override
  String get toolAddressFamily => '地址族';

  @override
  String get toolSentReceived => '发送 / 接收';

  @override
  String get toolPacketLoss => '丢包率';

  @override
  String get toolMinAvgMax => '最小 / 平均 / 最大';

  @override
  String get toolJitter => '抖动';

  @override
  String get toolJitterFooter => '抖动按各包时延与均值的平均绝对偏差计算。';

  @override
  String toolPacketN(String n) {
    return '第 $n 个包';
  }

  @override
  String get toolTimeout => '超时';

  @override
  String toolPingSummary(String failed, String sent) {
    return '本次共发送 $sent 个探测包，失败 $failed 个。';
  }

  @override
  String get toolPingFooter =>
      'Ping 由原生侧执行：优先调用系统 ping 二进制，不可用时回退到地址可达性与 TCP 端口握手计时，并会明确标注。';

  @override
  String get toolDnsSystem => '跟随系统';

  @override
  String get toolDnsCustom => '自定义';

  @override
  String get toolCustomDnsError => '请输入自定义 DNS 服务器 IP';

  @override
  String get toolInputDomain => '输入要解析的域名';

  @override
  String get toolCustomDnsHint => '自定义 DNS 服务器 IP（如 1.1.1.1）';

  @override
  String get toolQueryOptions => '查询选项';

  @override
  String get toolViaTunnelDnsBody => '开启后由隧道引擎解析，会套用拦截规则与缓存；关闭时直接问系统解析器';

  @override
  String get toolStartQuery => '开始查询';

  @override
  String get toolQuerying => '查询中…';

  @override
  String get toolQueryDomain => '查询域名';

  @override
  String get toolRecordType => '记录类型';

  @override
  String get toolAnswerSource => '答案来源';

  @override
  String get toolElapsed => '耗时';

  @override
  String get toolAnswerCount => '答案条数';

  @override
  String get toolDnsBlockedBody => '该域名被隧道规则拦截，因此没有真实上游应答。';

  @override
  String get toolDnsNoAnswers => '没有返回任何应答记录。若来源是「被规则拦截」，说明该域名在本机规则里被拦掉了。';

  @override
  String get toolDnsFooter =>
      '「走隧道查询」问的是本软件的解析链路（含规则与缓存），此时服务器由隧道决定；关闭后可选择跟随系统或指定一台 DNS 服务器，两者结果可能不同。';

  @override
  String get toolTunnelEngine => '隧道引擎';

  @override
  String get toolSpeedChecking => '正在检查测速通道…';

  @override
  String get toolSpeedUnsupported =>
      '当前设备不支持测速：本机没有提供 DNS 查询耗时测量的原生通道，页面不会显示任何模拟耗时。';

  @override
  String get toolSpeedDomainHint => '用于测速的域名';

  @override
  String get toolSpeedProviders => '测速服务商';

  @override
  String toolNoProviders(String protocol) {
    return '暂无 $protocol DNS 服务商';
  }

  @override
  String get toolNoProvidersBody => '在「服务商管理」里添加后即可参与测速';

  @override
  String get toolSpeedSelectionNote =>
      '可选择 1 个或多个服务商；这里的选择只用于 DNS 查询测速，不影响竞速模式。';

  @override
  String get toolTestQueryTime => '测试查询耗时';

  @override
  String get toolSpeedRunning => '测速中…';

  @override
  String get toolSpeedEmpty =>
      '尚未测速。选好服务商后点上面的按钮，本应用会直接向每个服务商发送 3 次真实 DNS 查询并记录往返耗时。';

  @override
  String get toolSpeedResults => '查询耗时结果';

  @override
  String toolSpeedResultsFooter(String domain) {
    return '测速结果按成功优先、平均耗时从低到高排序；结果只反映本次查询时的网络状态。域名当前为「$domain」。';
  }

  @override
  String get toolSpeedFooter =>
      '测速由原生侧执行：向每个服务商分别发送真实的 DoH / DoT / 明文 DNS 查询，只有拿到成功应答的样本才计入耗时。';

  @override
  String get toolFastest => '最快';

  @override
  String toolSampleCount(String count, String rate) {
    return '$rate · 样本 $count';
  }

  @override
  String toolAllFailed(String count) {
    return '全部失败（$count 次）';
  }

  @override
  String get toolTraceOptions => '追踪选项';

  @override
  String get toolStartTrace => '开始追踪';

  @override
  String get toolTracing => '追踪中…';

  @override
  String get toolTraceFailed => '追踪失败：未收到任何回应';

  @override
  String get toolTraceCancelled => '追踪已取消。';

  @override
  String get toolHopCount => '跳数';

  @override
  String toolHopCountValue(String count, String max) {
    return '$count / 最多 $max';
  }

  @override
  String get toolNoResponse => '无响应';

  @override
  String get toolTraceFooter =>
      '星号表示该跳在超时时间内没有回包——不代表链路断了，很多路由器不响应探测包。绿色一行表示已到达目标。';

  @override
  String get toolTraceHops15 => '15 跳';

  @override
  String get toolTraceHops30 => '30 跳';

  @override
  String get uaDeleteTitle => '删除 User-Agent';

  @override
  String get uaDeleteBody => '确定删除这一条吗？只删候选，不影响当前已选中的 UA。';

  @override
  String get uaAdd => '添加 User-Agent';

  @override
  String get uaEdit => '编辑 User-Agent';

  @override
  String get uaNote => 'UA 会随订阅下载、规则集拉取与订阅测速请求一起发送；部分服务端按 UA 拒绝请求，改这里可以绕过。';

  @override
  String get uaCurrent => '当前选择';

  @override
  String get uaNoOverride => '不覆写';

  @override
  String get uaNoOverrideBody => '沿用订阅或内核自带的 UA';

  @override
  String get uaBuiltin => '内置';

  @override
  String get uaCustom => '自定义';

  @override
  String get uaBuiltinNote => '内置 UA 不可删除：删掉之后内核回落到默认值，用户会误以为「设置没生效」。';

  @override
  String get uaHint => '如：clash-verge/v2.0.0';

  @override
  String get uaEmptyError => 'UA 不能为空';

  @override
  String get uaDuplicateError => '该 UA 已存在';

  @override
  String get ssidInvalid => 'SSID 不能为空或已存在';

  @override
  String get ssidAdd => '添加 SSID';

  @override
  String get ssidEdit => '编辑 SSID';

  @override
  String get ssidSave => '保存 SSID';

  @override
  String get ssidHint => '区分大小写，与系统 Wi-Fi 列表里的名字完全一致';

  @override
  String get ssidExample => '如：Home-5G';

  @override
  String get ssidEmptyError => 'SSID 不能为空';

  @override
  String get ssidConnection => '连接方式';

  @override
  String get ssidCellular => '蜂窝网络';

  @override
  String get ssidCellularBody => '在该网络下也启动 VPN';

  @override
  String get ssidWifiBody => '连上该 SSID 时启动 VPN';

  @override
  String get ssidBothOff => '两种都关掉，等于把这条 SSID 从白名单里排除（VPN 不会启动）。';

  @override
  String get ssidDelay => '延迟';

  @override
  String get ssidStartDelay => '启动延迟';

  @override
  String get ssidStartDelayBody => '等待网络就绪后再启动 VPN';

  @override
  String get ssidImmediate => '立即连接';

  @override
  String get odTitle => '按需连接';

  @override
  String get odApplyNow => '立即应用';

  @override
  String get odEnable => '启用按需连接';

  @override
  String get odEnableBody => '连上白名单里的 SSID 时自动启动 VPN';

  @override
  String get odDisableBody => '关闭时 VPN 始终在线，不随网络切换';

  @override
  String get odNote =>
      '开启后，只有连上白名单里的 SSID 时才会自动启动 VPN；其余网络保持断开，省电也更可控。自动判定只在网络变化时启停 VPN，不会覆盖手动开关的结果；点右上角「立即应用」可立即按当前网络重新判定。';

  @override
  String get odAllowlist => 'SSID 白名单';

  @override
  String get odNoSsid => '还没有 SSID';

  @override
  String get odNoSsidBody => '没有白名单时按需连接不会触发';

  @override
  String get odDelayNote => '延迟用于等 Wi-Fi 完成认证与 DHCP；过早启动 VPN 会让首个请求落到尚未就绪的网络上。';

  @override
  String get odCellular => '蜂窝';

  @override
  String get odKindsNone => '不启用';

  @override
  String odDelayValue(String ms) {
    return '延迟 $ms ms';
  }

  @override
  String get odStateDisabled => '按需连接已关闭';

  @override
  String get odStateUnknown => '无法读取当前 Wi-Fi，白名单不会触发';

  @override
  String get odStateNoWifi => '当前不在 Wi-Fi 上，VPN 保持断开';

  @override
  String odStateMatched(String ssid) {
    return '已匹配 $ssid，VPN 会自动启动';
  }

  @override
  String get odStateUnmatched => '当前 Wi-Fi 不在白名单，VPN 保持断开';

  @override
  String get odDisabledHint => '按需连接已关闭，VPN 不再随网络切换';

  @override
  String get odPillDisabled => '未启用';

  @override
  String get odPillUnknown => '无法判断';

  @override
  String get odPillNoWifi => '未连接 Wi-Fi';

  @override
  String get odPillWillStart => '会启动 VPN';

  @override
  String get odPillWillNotStart => '不会启动 VPN';

  @override
  String get odDecision => '当前判定';

  @override
  String get odDecisionFooter => '判定按当前网络实时计算：切换 Wi-Fi 后重新读取即可看到结果。SSID 区分大小写。';

  @override
  String get odCurrentNetwork => '当前网络';

  @override
  String get odWifiName => 'Wi-Fi 名称';

  @override
  String get odReadAgain => '重新读取';

  @override
  String get odPermission => '读取权限';

  @override
  String get odPermissionBody => 'Android 10 起读取 Wi-Fi 名称需要位置权限';

  @override
  String get odNotGranted => '未授权';

  @override
  String get odWifiUnreadable => '本机当前无法读取 Wi-Fi 名称：请在系统设置里授予本应用位置权限后重新读取。';

  @override
  String get odSsidPrivacy => 'SSID 只用于匹配白名单，不会被上传；手动添加的 SSID 在无法读取时仍然可用。';

  @override
  String get odBatteryJoined => '已加入';

  @override
  String get odBatteryNotJoined => '未加入';

  @override
  String get odBatteryUnavailable => '不可用';

  @override
  String get odPrerequisites => '前置条件';

  @override
  String get odIgnoreBattery => '忽略电池优化';

  @override
  String get odBatteryOk => '系统不会在后台冻结 VPN 进程';

  @override
  String get odBatteryAsk => '未加入时后台 VPN 可能被系统冻结，点击申请';

  @override
  String get odBatteryNoChannel => '当前构建没有提供电池优化通道';

  @override
  String get odBatteryFooter => '点击「未加入」会打开系统授权页；返回后会重新读取真实状态，取消则保持未加入。';

  @override
  String get odBatteryJoinedHint => '已加入电池优化白名单';

  @override
  String get odBatteryStillOff => '仍未加入，VPN 可能被系统冻结';

  @override
  String get odBatteryUnsupportedHint => '当前构建不支持该授权';

  @override
  String get odCapNoPermission => '无法读取：需要位置权限';

  @override
  String odCapCurrent(String name) {
    return '当前连接：$name';
  }

  @override
  String get customResourcesTitle => '自定义资源';

  @override
  String get customResourcesNote =>
      '这些资源按名字被引用：改名字等于断开引用，改内容则在下一次加载配置时生效。它们不属于旧版 1.4.3 的界面，保留在此供调试使用。';

  @override
  String get customResourcesSection => '资源';

  @override
  String get configDelete => '删除';

  @override
  String get configCancel => '取消';

  @override
  String get configNotSet => '未设置';

  @override
  String configItemCount(int count) {
    return '共 $count 项';
  }

  @override
  String odEditSsidTooltip(String ssid) {
    return '编辑 $ssid';
  }

  @override
  String odDeleteSsidTooltip(String ssid) {
    return '删除 $ssid';
  }

  @override
  String serverSwitched(String name) {
    return '已切换到 $name，重启服务后生效';
  }

  @override
  String serverSelected(String name) {
    return '已选择 $name';
  }

  @override
  String serverAdded(String name) {
    return '已添加 $name';
  }

  @override
  String serverSaved(String name) {
    return '已保存 $name';
  }

  @override
  String serverDeleteConfirm(String name) {
    return '删除 $name？';
  }

  @override
  String get serverDeleteBody => '如果它正被使用，删除后会回落到第一个内置服务商。';

  @override
  String serverDeleted(String name) {
    return '已删除 $name';
  }

  @override
  String get serverUpstreamTitle => '上游服务器';

  @override
  String get serverAddCustom => '添加自定义服务商';

  @override
  String serverCurrentUpstream(String name, String protocol) {
    return '当前用于解析 DNS：($protocol) $name';
  }

  @override
  String get serverBuiltinProviders => '内置 DNS 服务商';

  @override
  String get serverNoBuiltin => '暂无内置服务商';

  @override
  String get serverCustomProviders => '自定义 DNS 服务商';

  @override
  String get serverNoCustom => '暂无自定义服务商';

  @override
  String get serverNoCustomBody => '点右上角加号添加 DoH / DoT / 明文 DNS 上游';

  @override
  String get serverUpstreamFooter =>
      '服务器模式支持单服务商与智能选择 / 并行竞速 / 主备切换，解析模式与候选上游在上方切换；需重启服务生效。内置服务商由应用维护，只能切换；自定义项可通过右侧菜单编辑或删除。';

  @override
  String serverEditName(String name) {
    return '编辑 $name';
  }

  @override
  String serverDeleteName(String name) {
    return '删除 $name';
  }

  @override
  String get serverEditCustom => '编辑自定义服务商';

  @override
  String get serverSave => '保存';

  @override
  String get serverName => '名称';

  @override
  String get serverDohAddress => 'DoH 地址';

  @override
  String get serverAddress => '服务器地址';

  @override
  String get serverDohPrefix => '必须以 https:// 开头';

  @override
  String get serverAddressHint => 'IPv4 / IPv6 均可；IPv6 可直接填 [::1]';

  @override
  String get serverPort => '端口';

  @override
  String get serverPortHint => 'DNS 通常 53，DoT 通常 853';

  @override
  String get serverUnavailable => '当前设备不可用';

  @override
  String get serverBatteryJoined => '已加入电池优化白名单';

  @override
  String get serverBatteryNotJoined => '尚未加入电池优化白名单';

  @override
  String get serverClearCache => '清空缓存';

  @override
  String get serverClear => '清空';

  @override
  String get serverClearCacheBody => '将清空本机已缓存的解析结果，下一次查询会重新向上游请求。';

  @override
  String get serverCacheCleared => '缓存已清空';

  @override
  String get serverCacheClearFailed => '清空失败：请先启动解析服务再试';

  @override
  String serverCacheOn(String preset) {
    return '$preset · 命中缓存的查询不再请求上游';
  }

  @override
  String get serverCacheOff => '已关闭 · 每次解析都请求上游 DNS';

  @override
  String get serverModeSettings => '模式设置';

  @override
  String get serverProxySettings => '代理与解析设置';

  @override
  String get serverCacheSettings => '缓存设置';

  @override
  String get serverRuleControl => '规则控制';

  @override
  String get serverRuleControlOn => '已开启 · 命中规则按拦截策略返回';

  @override
  String get serverRuleControlOff => '已关闭 · 不执行域名规则过滤';

  @override
  String get serverRuleMasterSaved => '规则开关已保存，重启 DNS 服务后生效';

  @override
  String get serverListenPort => '本地监听端口';

  @override
  String get serverListenPortBody => 'DNS 服务在本机监听的端口，默认 1053';

  @override
  String get serverRuleManagement => '规则管理';

  @override
  String get serverBlocklist => '黑名单';

  @override
  String get serverBlocklistBody => '管理域名屏蔽规则，独立规则库';

  @override
  String get serverAllowlist => '白名单';

  @override
  String get serverAllowlistBody => '管理域名放行规则，独立规则库';

  @override
  String get serverHosts => 'Hosts 覆写';

  @override
  String get serverHostsBody => '将指定域名解析到配置的 IP 或 CNAME';

  @override
  String get serverRulesFooter => '这三张表只影响服务器模式的独立规则库，与普通模式的规则互不覆盖。';

  @override
  String get serverDataReset => '数据与重置';

  @override
  String get serverResetStats => '重置运行统计';

  @override
  String get serverResetStatsBody => '清空本次运行的统计数据';

  @override
  String get serverBackground => '后台稳定性';

  @override
  String get serverBackgroundBody =>
      '系统会在后台冻结省电名单之外的应用；把它加入白名单，DNS 服务才能在息屏后继续应答局域网查询。';

  @override
  String get serverRunMode => '运行模式';

  @override
  String get serverWizard => '使用向导';

  @override
  String get serverWizardBody => '查看服务器模式架构原理、局域网配置与就绪指引';

  @override
  String get serverReselectMode => '重新选择工作模式';

  @override
  String get serverReselectModeBody => '浏览所有工作模式详情并重新选择';

  @override
  String get serverBatteryIgnored => '已忽略电池优化';

  @override
  String get serverBatteryIgnoredShort => '已忽略';

  @override
  String get serverBatteryKeepAlive => '保持 DNS 服务在后台稳定运行';

  @override
  String get serverIgnoreBattery => '忽略电池优化';

  @override
  String get serverCachePresetConservative => '保守';

  @override
  String get serverCachePresetHighHit => '高命中';

  @override
  String get serverCachePresetStandard => '标准';

  @override
  String get serverNavOverview => '概览';

  @override
  String get serverPortInvalid => '请输入数字';

  @override
  String serverPortRange(String max, String min) {
    return '范围 $min–$max';
  }

  @override
  String serverPortChanged(String port) {
    return '端口已改为 $port，重启服务后生效';
  }

  @override
  String get serverResetConfirm => '确认重置';

  @override
  String get serverResetStatsConfirmBody => '将清空本次运行的全部统计数据，确认继续吗？';

  @override
  String get serverStatsReset => '运行统计已重置';

  @override
  String get serverOverviewTitle => '谛听 · 服务器模式';

  @override
  String get serverSwitchMode => '切换工作模式';

  @override
  String get serverChangePort => '修改监听端口';

  @override
  String get serverCurrentUpstreamCard => '当前上游';

  @override
  String get serverLanAccess => '局域网接入';

  @override
  String get serverLanBody => '把同网段设备的 DNS 指向上面这个地址即可；端口只在启动时绑定，改动后需要重启服务。';

  @override
  String get serverNoNetwork => '未连接网络';

  @override
  String get serverLanConnectHint => '连上 Wi-Fi 或以太网后这里会显示可用地址';

  @override
  String get serverLanPointHint => '将局域网其他设备的 DNS 指向此地址';

  @override
  String serverCopied(String text) {
    return '已复制 $text';
  }

  @override
  String get serverServiceStatus => '服务状态';

  @override
  String get serverTotalQueries => '总查询量';

  @override
  String get serverCacheHits => '缓存命中';

  @override
  String get serverBlocked => '已拦截';

  @override
  String get serverAverageLatency => '平均时延';

  @override
  String get serverUptime => '运行时长';

  @override
  String get serverStatsLastSevenDays => '近 7 天累计';

  @override
  String get serverLogsTitle => '服务器日志仪表盘';

  @override
  String get serverLogsBody =>
      '查看局域网设备经服务器模式发起的 DNS 请求、拦截、缓存与上游竞速记录。服务器模式不建立 VPN 隧道，因此这里不含上下行流量与 HTTPS 检查数据。';

  @override
  String get serverResetStatsBodyShort => '清空本次运行的全部计数，不清规则与缓存';

  @override
  String get serverModeSettingsBody => '监听端口、后台稳定性、数据重置与运行模式';

  @override
  String get serverModeNote =>
      '服务器模式不建立 VPN 隧道：它只在本机监听 DNS 端口，因此可以与其它 VPN 共存，也不占用系统的 VPN 槽位；本机应用的查询不会自动经过该服务。';

  @override
  String get serverBusyStarting => '启动中';

  @override
  String get serverBusyStopping => '停止中';

  @override
  String get serverRunning => '停止';

  @override
  String get serverStopped => '开启';

  @override
  String serverListening(String port) {
    return '监听 0.0.0.0:$port';
  }

  @override
  String get serverStatusStopped => '服务器模式已停止';

  @override
  String get serverStatusStarting => '正在启动服务...';

  @override
  String get serverStatusRunning => '服务器模式运行中';

  @override
  String get serverStatusStopping => '正在停止服务...';

  @override
  String get serverStatusErrorText => '服务启动异常';

  @override
  String get troubleshootTitle => '故障排查';

  @override
  String get troubleshootRuntimeLogs => '运行日志';

  @override
  String get troubleshootRecordLogs => '记录运行日志';

  @override
  String get troubleshootExportLogs => '导出运行日志';

  @override
  String get troubleshootClearLogs => '清空运行日志';

  @override
  String get troubleshootClearLogsBody => '删除本地已记录的全部运行日志文件';

  @override
  String get troubleshootRecordNote =>
      '默认关闭。开启后会在通知栏显示状态，关闭软件或手动关闭后即停止记录；日志只保存在本机，不会自动上传。';

  @override
  String get troubleshootLocalDb => '本地数据库';

  @override
  String get troubleshootWriteStatus => '日志写入状态';

  @override
  String get troubleshootWriteStatusNote =>
      '日志、竞速记录与流量统计由后台直接写入本地数据库。出现丢弃或打开失败时，多为数据库被长时间占用，点击可重新读取；反复出现请导出运行日志反馈。';

  @override
  String get troubleshootCrashLogs => '崩溃日志';

  @override
  String get troubleshootExportCrashes => '导出崩溃日志';

  @override
  String get troubleshootClearCrashes => '清空崩溃日志';

  @override
  String get troubleshootClearCrashesBody => '删除本地所有已记录的崩溃文件';

  @override
  String get troubleshootCrashNote =>
      '发生未捕获异常时自动保存诊断信息与关键日志，仅保存在设备本地，导出后可反馈给开发者。';

  @override
  String get troubleshootCaptureWarning =>
      '抓取运行日志会持续读写少量文件，可能导致功耗升高、存储占用增加或产生其他未知影响，不需要时请及时关闭。导出的文件可发送给开发者，配合问题现象与发生时间能更快定位原因。';

  @override
  String get troubleshootReadingStatus => '正在读取抓取状态…';

  @override
  String troubleshootRecording(String size) {
    return '正在记录，已占用 $size，再次点击可关闭';
  }

  @override
  String troubleshootStoppedWithLogs(String size) {
    return '已关闭，本地已有 $size 日志可导出';
  }

  @override
  String get troubleshootStoppedNoLogs => '已关闭，开启后才会记录运行日志';

  @override
  String get troubleshootReadingLogs => '正在读取本地日志…';

  @override
  String get troubleshootNoLogs => '当前设备没有运行日志';

  @override
  String troubleshootLogCount(int count, String size) {
    return '共 $count 个文件，$size，点击导出文件';
  }

  @override
  String get troubleshootReadingHealth => '正在读取写入状态…';

  @override
  String get troubleshootHealthy => '正常，没有日志被丢弃';

  @override
  String troubleshootHealthyDetail(String detail, String mode) {
    return '正常，没有日志被丢弃（$mode · $detail）';
  }

  @override
  String troubleshootDropped(
    int dropped,
    String failed,
    int reason,
    String split,
  ) {
    return '已丢弃 $dropped 条日志$split，打开失败 $failed 次$reason';
  }

  @override
  String get troubleshootOverflow => '队列溢出';

  @override
  String get troubleshootTableMissing => '表缺失';

  @override
  String get troubleshootNoDatabase => '无数据库';

  @override
  String get troubleshootClosed => '停止时未写完';

  @override
  String get troubleshootReadingCrashes => '正在读取本机崩溃日志…';

  @override
  String get troubleshootNoCrashes => '当前设备没有崩溃日志';

  @override
  String troubleshootCrashCount(int count) {
    return '已记录 $count 份崩溃日志，点击导出文件';
  }

  @override
  String get troubleshootStoppedToast => '已停止记录运行日志';

  @override
  String get troubleshootStartTitle => '开启运行日志抓取';

  @override
  String get troubleshootCancel => '取消';

  @override
  String get troubleshootConfirmStart => '确定开启';

  @override
  String get troubleshootStartBody =>
      '该功能主要用于协助开发者排查问题，开启后会开始记录软件的运行日志，并持续写入本机存储。\n\n抓取期间可能导致功耗升高、存储占用增加，或产生其他未知影响。如非排查问题所需，建议用完即关。\n\n日志只保存在本机，关闭后停止记录；导出后你可以自行发送给开发者。';

  @override
  String get troubleshootStartedToast => '已开始记录运行日志';

  @override
  String get troubleshootStartFailedToast => '无法开启日志抓取，请稍后重试';

  @override
  String get troubleshootNoExportableLogs => '没有可导出的运行日志';

  @override
  String get troubleshootExportFailed => '导出失败：本机没有可写的导出目录';

  @override
  String troubleshootExported(String path) {
    return '已导出到 $path';
  }

  @override
  String get troubleshootConfirm => '确定';

  @override
  String get troubleshootClearLogsConfirm => '确认清空所有已保存的运行日志吗？该操作不可恢复。';

  @override
  String troubleshootClearedLogs(String count) {
    return '已清空 $count 个日志文件';
  }

  @override
  String get troubleshootNoClearableLogs => '没有可清空的运行日志';

  @override
  String get troubleshootNoExportableCrashes => '没有可导出的崩溃日志';

  @override
  String get troubleshootClearCrashesConfirm => '确认清空所有已保存的崩溃日志吗？';

  @override
  String troubleshootClearedCrashes(String count) {
    return '已清空 $count 份崩溃日志';
  }

  @override
  String get troubleshootNoClearableCrashes => '没有可清空的崩溃日志';

  @override
  String get bypassAddTitle => '添加绕过域名';

  @override
  String get bypassAdd => '添加';

  @override
  String get bypassSuffix => '域名后缀';

  @override
  String get bypassSuffixBody => '匹配该后缀及其子域名；不参与 HTTPS 解密';

  @override
  String get mirrorGlobal => '全局镜像';

  @override
  String get mirrorDefault => '默认使用镜像下载';

  @override
  String get mirrorNeedTemplate => '先添加一个模板后才能开启';

  @override
  String get mirrorTemplateNote => '订阅下载与软件更新都经由所选模板';

  @override
  String get mirrorTemplate => '使用的模板';

  @override
  String get mirrorNote =>
      '开启后，未单独设置镜像的订阅、检查更新与下载安装包都会先请求镜像，镜像失败时自动改用原始地址。单独设置过镜像的订阅仍按自己的设置。';

  @override
  String get hiddenFeaturesTitle => '隐藏功能';

  @override
  String get hiddenFeaturesReset => '恢复全部显示';

  @override
  String get hiddenFeaturesNote =>
      '自定义在功能中心显示的功能卡片。关闭开关将从功能中心隐藏该卡片，默认全部显示。隐藏仅调整界面展示，不会影响功能的后台运行与规则生效。设置会保存到本机，重启后仍然有效。';

  @override
  String get hiddenFeaturesFooter => '「隐藏功能」卡片固定常驻，确保随时可以在这里恢复。';

  @override
  String get cacheSettingsTitle => '缓存设置';

  @override
  String get cacheSection => '缓存';

  @override
  String get cacheLocalDns => '本地 DNS 缓存';

  @override
  String get cacheOffNote => '关闭后每次解析都会请求上游 DNS';

  @override
  String get cachePresetSection => '缓存档位';

  @override
  String get cachePresetNote =>
      '建议使用「标准」。档位会自动设置最长 TTL、最短 TTL 和解析失败兜底时间，不再需要手动填写秒数。';

  @override
  String get recognitionSponsorTitle => '赞助者名单';

  @override
  String get recognitionSponsorIntro =>
      '感谢每一位支持谛听项目的朋友！名单默认按赞助时间由早到晚排列，可通过右上角按钮切换为由晚到早；与赞助金额无关，每一份支持都同样珍贵。';

  @override
  String get recognitionSponsorSection => '赞助者';

  @override
  String get recognitionBuilderTitle => '共建者名单';

  @override
  String get recognitionBuilderIntro =>
      '感谢每一位为谛听提出建议、帮助测试的共建者！名单按用户名称的字母顺序排列，中文名称按拼音排序。';

  @override
  String get recognitionBuilderSection => '共建者';

  @override
  String get providerVisibilityTitle => '服务显示';

  @override
  String get providerVisibilityNote =>
      '关闭竞速模式时，首页解析服务下拉框仅显示这里选中的服务。当前正在使用的服务会始终保留。按住右侧手柄拖动可调整顺序，该顺序同时决定选择竞速服务商时的排列。';

  @override
  String providerVisibilityProtocol(String protocol) {
    return '$protocol 服务';
  }

  @override
  String providerVisibilityAll(String protocol) {
    return '全部 $protocol 服务';
  }

  @override
  String get providerVisibilityNone => '不显示该类型的服务';

  @override
  String get providerVisibilityAllOn => '显示该类型的全部服务';

  @override
  String providerVisibilityCount(String count) {
    return '已选择 $count 个服务';
  }

  @override
  String get markdownCopyCode => '复制代码';

  @override
  String get markdownCodeCopied => '代码已复制到剪贴板';

  @override
  String get recognitionUpdated => '名单已更新';

  @override
  String get recognitionRefresh => '刷新名单';

  @override
  String get recognitionSortAsc => '切换为由早到晚';

  @override
  String get recognitionSortDesc => '切换为由晚到早';

  @override
  String get recognitionEmpty => '暂时没有名单';

  @override
  String get recognitionLoadFailed => '名单加载失败';

  @override
  String get recognitionEmptyBody => '名单由云端下发，点这里拉取一次。';

  @override
  String get recognitionLoad => '加载名单';

  @override
  String get recognitionRetry => '重试';

  @override
  String get recognitionNoMembers => '暂时还没有成员';

  @override
  String get recognitionNoMembersBody => '名单会随云端配置更新，稍后再来看看。';

  @override
  String get recognitionRefreshShort => '刷新';

  @override
  String get recognitionCached => '正在显示本地缓存的名单';

  @override
  String recognitionLastUpdate(String time) {
    return '上次更新：$time';
  }

  @override
  String get recognitionCloudNote => '名单由云端下发，进入页面时自动检查更新';

  @override
  String appRulesAllowCount(String count, int package) {
    return '$package · $count 个放行域名';
  }

  @override
  String get appRulesConfigured => '已配置';

  @override
  String get appRulesSystem => '系统';

  @override
  String get appRulesIncludeSub => '包含子域名';

  @override
  String get appRulesDelete => '删除';

  @override
  String get appRulesAddDomainTitle => '添加放行域名';

  @override
  String get appRulesCancel => '取消';

  @override
  String get appRulesAdd => '添加';

  @override
  String get appRulesDomain => '域名';

  @override
  String get appRulesDomainHint => '只填裸域名；包含子域名，不需要写通配符或 @@ 前缀';

  @override
  String get appRulesAllowlistRow => '白名单（放行）';

  @override
  String get appRulesBlocklistRow => '黑名单（拦截）';

  @override
  String get appRulesImportant => '重要';

  @override
  String get appRulesDisable => '停用';

  @override
  String get appRulesEnable => '启用';

  @override
  String get appRulesAddRuleTitle => '添加 DNS 规则';

  @override
  String get appRulesRuleDomainHint => '只填裸域名；仅对本应用生效';

  @override
  String get appRulesBlocklist => '黑名单';

  @override
  String get appRulesAllowlist => '白名单';

  @override
  String get logRetentionTitle => '日志模式';

  @override
  String get logRetentionDnsLogs => 'DNS 请求日志';

  @override
  String get logRetentionOffNote => '关闭后不会删除已有日志，重新开启即可继续查看。';

  @override
  String get logRetentionOverlay => '悬浮窗';

  @override
  String get logRetentionOverlayLogs => '悬浮窗日志';

  @override
  String get logRetentionOverlayBody => 'VPN 运行且应用在后台时显示悬浮球，点按查看实时请求';

  @override
  String get logRetentionOverlayNote => '回到应用前台时悬浮窗会自动隐藏。仅普通模式可用。';

  @override
  String get logRetentionCleanup => '自动清理时间';

  @override
  String logRetentionKeepDays(String days) {
    return '保留 $days 天';
  }

  @override
  String get logRetentionCleanupNote =>
      '超过所选时间的请求日志由隧道服务每小时清理一次（首次在启动 30 秒后）。关闭日志不会删除已有记录。';

  @override
  String get appBlockTitle => '禁止联网应用';

  @override
  String get appBlockInfo => '通过本机 VPN 按 UID 阻止所选应用的全部网络连接。共享同一 UID 的应用会一并受影响。';

  @override
  String get appBlockToggle => '启用禁止联网';

  @override
  String get appBlockToggleEmpty => '尚未选择应用；开启后不会阻断流量';

  @override
  String get appBlockSelection => '禁止联网的应用';

  @override
  String get appExcludeTitle => '排除应用';

  @override
  String get appExcludeInfo => '排除后，应用将使用系统 DNS，不参与本应用的过滤、缓存、日志和统计。';

  @override
  String get appExcludeSelection => '排除的应用';

  @override
  String get appSelectionSaved => '已保存，启动 DNS VPN 后生效';

  @override
  String get appSelectionSaveTitle => '保存更改？';

  @override
  String appSelectionSaveBody(String title) {
    return '「$title」的选择还没保存。保存后离开，还是放弃这些修改？';
  }

  @override
  String get appSelectionSwitch => '开关';

  @override
  String get appSelectionNoAppsYet => '尚未选择应用';

  @override
  String appSelectionCount(String count) {
    return '已选择 $count 个应用';
  }

  @override
  String get appSelectionNoAppsAvailable => '设备上没有可选的应用';

  @override
  String get appSelectionNoMatch => '未找到匹配应用';

  @override
  String get appSelectionSave => '保存';

  @override
  String get appSelectionNothingRead => '未读取到任何已安装应用；此处的勾选保存后不会命中任何应用。';

  @override
  String get appSelectionExclusiveNote =>
      '勾选会同时取消该应用在「排除应用」「禁止联网」「HTTPS 检查」与应用独立规则里的选择。';

  @override
  String get bootstrapTitle => '引导解析设置';

  @override
  String get bootstrapAdd => '新增 Bootstrap IP';

  @override
  String get bootstrapGlobal => '全局开关';

  @override
  String get bootstrapEnable => '启用 Bootstrap IP';

  @override
  String get bootstrapEnableBody => '使用独立递归 DNS 解析加密服务商域名，支持智能权重优选与自动回退';

  @override
  String get bootstrapEnableNote =>
      '开启后将通过加权算法动态优选 Bootstrap IP；关闭后将通过系统 DNS 解析加密上游域名。';

  @override
  String get bootstrapBuiltin => '内置 Bootstrap IP';

  @override
  String get bootstrapCustom => '自定义 Bootstrap IP';

  @override
  String get bootstrapNoCustom => '暂无自定义 Bootstrap IP。点击右上角「新增」添加。';

  @override
  String bootstrapNoSample(String ip) {
    return '$ip · 暂无样本';
  }

  @override
  String bootstrapAverage(String ms) {
    return ' · 平均 ${ms}ms';
  }

  @override
  String bootstrapFailures(String count) {
    return ' · 失败 $count';
  }

  @override
  String bootstrapStats(
    String failures,
    String ip,
    String latency,
    String samples,
    String success,
  ) {
    return '$ip$latency · 样本 $samples · 成功 $success%$failures';
  }

  @override
  String get bootstrapInvalidIp => '请填写合法的 IPv4 或 IPv6 地址';

  @override
  String get bootstrapNameOptional => '名称（可选）';

  @override
  String get bootstrapIpAddress => 'IP 地址';

  @override
  String get caCertTitle => 'CA 证书设置';

  @override
  String get caCertStatusMissing => '尚未生成：引擎还没有产出 ca.crt';

  @override
  String get caCertStatusUntrusted => '已生成，但未装进系统信任存储';

  @override
  String get caCertStatusTrusted => '已生成且已被系统信任';

  @override
  String get caCertSectionStatus => '证书状态';

  @override
  String get caCertRootStatus => '根证书状态';

  @override
  String get caCertVerified => '已验证';

  @override
  String get caCertUnverified => '未验证';

  @override
  String get caCertReadFailed => '读取失败';

  @override
  String get caCertStatusFooter =>
      '仅已验证的根证书支持流量检查；启用了证书绑定（SSL Pinning）的应用将自动旁路。';

  @override
  String get caCertSectionActions => '证书操作';

  @override
  String get caCertGuide => '安装与卸载指南';

  @override
  String get caCertGuideSubtitle => '查看各机型系统证书的安装、移除及安全说明';

  @override
  String get caCertInstall => '安装根证书';

  @override
  String get caCertInstallSubtitle => '交给系统安装器；Android 11 起还需在设置里手动确认';

  @override
  String get caCertInstalled => '已安装';

  @override
  String get caCertNotInstalled => '未安装';

  @override
  String get caCertSaveToDownloads => '保存证书到下载目录';

  @override
  String get caCertSaveToDownloadsSubtitle => '下载目录里的 .crt 可在系统设置里手动安装';

  @override
  String get caCertFingerprint => '证书指纹';

  @override
  String get caCertNoFingerprint => '尚未生成证书时没有指纹';

  @override
  String get caCertFingerprintSubtitle => 'SHA-256（点击查看完整指纹）';

  @override
  String get caCertViewPem => '查看证书内容';

  @override
  String get caCertViewPemSubtitle => '以可复制的 PEM 文本显示，便于拷到别处安装';

  @override
  String get caCertSectionManage => '证书管理';

  @override
  String get caCertRegenerate => '重新生成根证书';

  @override
  String get caCertRegenerateSubtitle => '作废当前私钥并生成新证书，重置后需重新安装';

  @override
  String get caCertNoCertificate => '还没有可用证书，请先点「重新生成根证书」';

  @override
  String get caCertInstallDialogBody =>
      'Android 只允许用户手动把根证书装进「CA 证书」一栏，应用无法静默写入系统信任存储。\n\n点「继续」会先保存一份证书文件到下载目录，再尝试打开系统安装器；若安装器只提示去设置，请用该文件在「设置 → 安全 → 加密与凭据 → 安装证书 → CA 证书」里手动选中它。';

  @override
  String caCertSavedTo(String name) {
    return '证书已存到 $name。';
  }

  @override
  String get caCertDownloadsDir => '下载目录';

  @override
  String caCertSaveFailed(String error) {
    return '证书文件保存失败（$error）。';
  }

  @override
  String get caCertOpenedInstaller => '已打开系统证书安装界面。';

  @override
  String get caCertOpenedSettings => '系统没有证书安装器，已打开安全设置。';

  @override
  String get caCertInstallerUnavailable => '无法打开证书安装界面。';

  @override
  String get caCertManualHint => '若界面只提示前往设置，请在「加密与凭据 → 安装证书 → CA 证书」里手动选中它。';

  @override
  String caCertSavedHint(String name) {
    return '已保存到 $name，可在「加密与凭据 → 安装证书」里选中它';
  }

  @override
  String get caCertDownloadsFailed => '无法写入下载目录';

  @override
  String get caCertRegenerateTitle => '重新生成根证书？';

  @override
  String get caCertRegenerateBody =>
      '会删除现有的 ca.crt / ca.key 与黑名单缓存。已安装的旧证书随即失效，之前被信任的所有连接都需要重新安装新证书，HTTPS 检查也会被自动关闭。';

  @override
  String get caCertRegenerateAction => '重新生成';

  @override
  String caCertGenerateFailed(String error) {
    return '生成失败：$error';
  }

  @override
  String get caCertGenerated => '已生成新证书，请前往系统设置安装';

  @override
  String get caCertFingerprintTitle => '证书指纹（SHA-256）';

  @override
  String get caCertFingerprintCopied => '指纹已复制';

  @override
  String get caCertPemTitle => '根证书 PEM';

  @override
  String get caCertPemCopied => '证书内容已复制';

  @override
  String get caCertGuideTitle => 'CA 证书指南';

  @override
  String get caCertWhyTitle => '为什么需要安装';

  @override
  String get caCertWhyBody =>
      'HTTPS 流量检查需要在设备上建立一条本地解密通道。系统只信任「用户」证书区里手工安装的根证书，应用无法代替你点这一步。';

  @override
  String get caCertStepsTitle => '安装步骤';

  @override
  String get caCertStep1 => '1. 在「CA 证书设置」里点「安装根证书」，应用会把证书文件存进下载目录，再交给系统安装器。';

  @override
  String get caCertStep2 =>
      '2. Android 11 起系统安装器通常只提示前往设置，这是平台限制，不是应用故障。请从「设置 → 安全 → 加密与凭据 → 安装证书 → CA 证书」里选中下载目录里的那个 .crt 文件。';

  @override
  String get caCertStep3 => '3. 安装时系统会要求屏幕锁或指纹；设备没有锁屏时无法安装，需先设一个 PIN。';

  @override
  String get caCertStep4 => '4. 回到本页，状态应变成「已验证」；没变就退出重进该页重新检查。';

  @override
  String get caCertWhichAppsTitle => '哪些应用能被检查';

  @override
  String get caCertWhichAppsBody =>
      '系统只信任「用户」证书区的根证书，而 targetSdk 24（Android 7.0）及以上的应用默认不信任用户证书。只有自带网络安全配置允许用户 CA 的应用，其 HTTPS 才能被解密并看到明文。';

  @override
  String get caCertWhichAppsWarning =>
      '其余应用的 HTTPS 请求会被记录为「失败 / client_tls」，这是应用的证书绑定或系统策略导致的，属于预期行为；这类应用应加入绕过规则。';

  @override
  String get caCertRiskTitle => '卸载与风险';

  @override
  String get caCertRiskWarning =>
      '根证书一旦装进用户信任区，任何持有对应私钥的软件都能解密本机流量。不再使用时请到系统设置里删除它，并在本页「重新生成根证书」作废旧私钥。';

  @override
  String get caCertRiskPinning =>
      '部分应用使用证书绑定（SSL Pinning），装证书后仍会连接失败；这类应用应加入绕过规则，而不是反复重装证书。';

  @override
  String get commonCopy => '复制';

  @override
  String get commonContinue => '继续';

  @override
  String get commonUnknownReason => '未知原因';

  @override
  String get autoUpdateTitle => '自动更新设置';

  @override
  String get autoUpdateSection => '自动更新';

  @override
  String get autoUpdateRulesSwitch => '自动更新规则订阅';

  @override
  String get autoUpdateRulesSwitchSubtitle => '启动应用、回到前台或到达设定时刻时检查是否到期';

  @override
  String get autoUpdateIntervalSection => '更新频率';

  @override
  String autoUpdateEveryHours(int hours) {
    return '每 $hours 小时';
  }

  @override
  String get autoUpdateCustomInterval => '自定义更新时间';

  @override
  String get autoUpdateCustomHint => '输入 1 至 168 小时之间的更新时间';

  @override
  String get autoUpdateTimedSection => '按时刻更新';

  @override
  String autoUpdateDailyAt(String time) {
    return '每天 $time';
  }

  @override
  String autoUpdateEveryOtherDayAt(String time) {
    return '隔天 $time';
  }

  @override
  String get autoUpdateTimedPickHint => '点按选择执行时刻';

  @override
  String get autoUpdateTimedChangeHint => '点按修改执行时刻';

  @override
  String get autoUpdateIntervalFooter =>
      '设置保存在当前工作模式的数据集里（普通 / 极速 / 服务器各自独立）。按时刻更新使用手机系统时间与时区；新选的时刻若今天已过，从下一次开始计。本机没有后台任务队列：应用在前台时到点立即执行，不在前台时会在下次启动或切回前台时补跑，进程被完全关闭期间不会更新。';

  @override
  String get autoUpdateStatusSection => '执行状态';

  @override
  String get autoUpdateNext => '下次预计更新';

  @override
  String get autoUpdateLast => '上次自动更新';

  @override
  String get autoUpdateNoRunYet => '本次会话还没有执行过自动更新';

  @override
  String autoUpdateRunCount(int count) {
    return '（$count 个订阅）';
  }

  @override
  String get autoUpdateStatusFooter =>
      '按间隔时，判据是每条订阅的「上次尝试时间」与间隔；按时刻时，最近一个已到的时刻之后没有尝试过的订阅视为到期。正在手动更新时本轮会让路。';

  @override
  String get autoUpdateGroupsSection => '分组自动更新';

  @override
  String get autoUpdateReadingGroups => '读取分组中…';

  @override
  String get autoUpdateNoGroups => '还没有分组';

  @override
  String get autoUpdateNoGroupsSubtitle => '在规则订阅页新建分组后，可以在这里单独开关';

  @override
  String get autoUpdateGroupsFooter =>
      '仅会自动更新已开启的分组中的网络订阅；写入 `subscription_group` 表。';

  @override
  String get autoUpdateReadingSubs => '正在读取订阅…';

  @override
  String get autoUpdateNoCandidates => '没有可自动更新的订阅（需为远程、已启用、且所在分组已开启）';

  @override
  String get autoUpdateDueNow => '已到期：应用在前台时会立即执行';

  @override
  String autoUpdateRemainingHours(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟后';
  }

  @override
  String autoUpdateRemainingMinutes(int minutes) {
    return '$minutes 分钟后';
  }

  @override
  String autoUpdateNextAt(String moment, String left) {
    return '$moment（$left）';
  }

  @override
  String autoUpdateMoment(int month, int day, String time) {
    return '$month 月 $day 日 $time';
  }

  @override
  String get autoUpdateIntervalLabel => '更新间隔（小时）';

  @override
  String get autoUpdateIntervalHelper => '1–168 小时';

  @override
  String get mirrorTplTitle => '镜像站模板';

  @override
  String get mirrorTplAdd => '添加模板';

  @override
  String get mirrorTplIntro =>
      '保存常用的下载镜像。开启全局镜像后，订阅与软件更新默认都走所选模板；添加订阅时也可以单独指定模板。';

  @override
  String get mirrorTplActions => '操作';

  @override
  String get mirrorTplFormatExample => '镜像站格式示例';

  @override
  String get mirrorTplFormatExampleSubtitle => '了解占位符如何组成镜像地址';

  @override
  String get mirrorTplSaved => '已保存模板';

  @override
  String get mirrorTplReadFailed => '无法读取镜像站模板';

  @override
  String get mirrorTplReadFailedSubtitle => '旧库尚未就绪或该表不可用';

  @override
  String mirrorTplSavedCount(int count) {
    return '已保存模板（$count）';
  }

  @override
  String get mirrorTplReading => '正在读取镜像站模板…';

  @override
  String get mirrorTplEmpty => '暂无模板。点击右上角「添加模板」开始使用。';

  @override
  String get mirrorTplDuplicate => '同名模板已存在，请换一个名称';

  @override
  String get mirrorTplDuplicateSave => '保存失败：名称与已有模板重复';

  @override
  String get mirrorTplFormatTitle => '镜像站格式';

  @override
  String get mirrorTplFormatIntro => '镜像地址由固定前缀与占位符组成，下载订阅时会把占位符替换成真实链接。';

  @override
  String mirrorTplFormatUrl(String token) {
    return '$token：完整订阅地址';
  }

  @override
  String mirrorTplFormatScheme(String token) {
    return '$token：http 或 https';
  }

  @override
  String mirrorTplFormatUrlEncoded(String token) {
    return '$token：URL 编码后的完整地址';
  }

  @override
  String mirrorTplFormatHost(String token) {
    return '$token：订阅域名';
  }

  @override
  String mirrorTplFormatPath(String token) {
    return '$token：路径部分';
  }

  @override
  String mirrorTplFormatPathAndQuery(String token) {
    return '$token：路径与查询参数';
  }

  @override
  String mirrorTplFormatSample(String token) {
    return '示例：https://ghproxy.example.com/$token';
  }

  @override
  String mirrorTplFormatPlaceholders(
    String url,
    String scheme,
    String urlEncoded,
    String host,
    String path,
    String pathAndQuery,
  ) {
    return '可用占位符：$url、$scheme、$urlEncoded、$host、$path、$pathAndQuery';
  }

  @override
  String get mirrorTplNameLabel => '模板名称';

  @override
  String get mirrorTplNameHint => '例如：GitHub 镜像';

  @override
  String get mirrorTplAddressLabel => '模板地址';

  @override
  String get mirrorTplInvalid => '必须使用 HTTP(S) 并包含至少一个占位符';

  @override
  String get mirrorTplAddTitle => '添加镜像站模板';

  @override
  String get mirrorTplEditTitle => '编辑镜像站模板';

  @override
  String get commonEdit => '编辑';

  @override
  String get ruleControlUrlNotReadyCa => '未就绪 · 需先安装并验证 CA 根证书';

  @override
  String get ruleControlUrlNotReadyInspection => '未就绪 · 需在 HTTPS 流量检查中开启';

  @override
  String get ruleControlUrlNotReadyApps => '未就绪 · 需在 HTTPS 流量检查中选择目标应用';

  @override
  String get ruleControlUrlPaused => '已暂停 · 未启用解密 URL 过滤与重定向';

  @override
  String get ruleControlUrlRunning => '运行中 · 解密流量匹配 URL 屏蔽、放行及重定向';

  @override
  String get ruleControlIntro =>
      '统一管理域名过滤、URL 规则及规则覆写的总控开关、拦截策略与在线规则订阅。黑名单、白名单与覆写名单可在功能中心中独立管理。';

  @override
  String get ruleControlIntroLimited =>
      '统一管理域名过滤的总控开关、拦截策略与在线规则订阅。黑名单、白名单与覆写名单可在功能中心中独立管理。';

  @override
  String get ruleControlFilterSection => '过滤与覆写控制';

  @override
  String get ruleControlDomainRules => '启用域名规则';

  @override
  String get ruleControlDomainRulesOn => '开启 DNS 阶段域名屏蔽、白名单放行及 IPv4/IPv6 覆写';

  @override
  String get ruleControlDomainRulesOff => '已禁用 DNS 域名过滤，查询将直接放行';

  @override
  String get ruleControlUrlRules => 'URL 规则与内容过滤';

  @override
  String get ruleControlNotReady => '未就绪';

  @override
  String get ruleControlPolicySection => '拦截策略';

  @override
  String get ruleControlBlockResponse => '拦截响应';

  @override
  String ruleControlDynamicSummary(String mode) {
    return '动态策略：先 NODATA，高频请求后 $mode';
  }

  @override
  String get ruleControlSubsSection => '订阅与更新';

  @override
  String get ruleControlSubsSubtitle => '管理域名规则与 IPv4/IPv6 覆写订阅源及分组';

  @override
  String ruleControlCount(int count) {
    return '$count 个';
  }

  @override
  String ruleControlAutoUpdateOn(int hours) {
    return '已开启 · 每 $hours 小时自动更新';
  }

  @override
  String ruleControlAutoUpdateDaily(String time) {
    return '已开启 · 每天 $time 自动更新';
  }

  @override
  String ruleControlAutoUpdateEveryOtherDay(String time) {
    return '已开启 · 隔天 $time 自动更新';
  }

  @override
  String get ruleControlAutoUpdateOff => '已关闭自动更新';

  @override
  String get ruleControlMirrorSubtitle => '维护订阅下载镜像，可在添加订阅时直接选择';

  @override
  String get blockResponseFixedSection => '固定响应';

  @override
  String get blockResponseFixedFooter =>
      '动态策略开启时会临时覆盖以上选择：先返回 NODATA，高频请求后返回 NXDOMAIN。';

  @override
  String get blockResponseDynamicSection => '动态策略';

  @override
  String get blockResponseEnableDynamic => '启用动态策略';

  @override
  String get blockResponseEnableDynamicSubtitle => '同一域名的所有记录类型合并计数';

  @override
  String get blockResponseParameters => '动态参数';

  @override
  String blockResponseParamsSummary(int threshold, int window, int duration) {
    return '$threshold 次 / $window 秒 / 保持 $duration 秒';
  }

  @override
  String get blockResponseDynamicFooter =>
      '正常客户端会缓存 NODATA 响应。动态策略主要用于持续重试或忽略负缓存的请求。';

  @override
  String get blockResponseThresholdError => '请求次数需在 2–100 之间';

  @override
  String get blockResponseWindowError => '统计窗口需在 10–300 秒之间';

  @override
  String get blockResponseDurationError => '保持时长需在 60–3600 秒之间';

  @override
  String get blockResponseThresholdLabel => '请求次数';

  @override
  String get blockResponseThresholdHelper => '2–100 次；第 N+1 次开始升级';

  @override
  String get blockResponseWindowLabel => '统计窗口（秒）';

  @override
  String get blockResponseWindowHelper => '10–300 秒';

  @override
  String get blockResponseDurationLabel => 'NXDOMAIN 保持时长（秒）';

  @override
  String get blockResponseDurationHelper => '60–3600 秒；首次升级起固定计时';

  @override
  String get httpInspCheckingCa => '正在检查根证书…';

  @override
  String get httpInspNoAppsHint => '未选择目标应用，仅保留 DNS 过滤';

  @override
  String httpInspSelectedHint(int count) {
    return '已选 $count 个应用，其余直接转发';
  }

  @override
  String get httpInspScopeSection => '检查范围';

  @override
  String get httpInspEnable => '启用 HTTPS 检查';

  @override
  String get httpInspTargetApps => '目标应用';

  @override
  String get httpInspNoApps => '未选择任何应用';

  @override
  String httpInspSelectedApps(int count) {
    return '已选择 $count 个应用';
  }

  @override
  String get httpInspCaCert => 'CA 证书';

  @override
  String get httpInspCaReady => '证书已安装且指纹匹配，可查看或重置';

  @override
  String get httpInspContentSection => '解密内容过滤';

  @override
  String get httpInspUrlRules => '启用 URL 规则与重定向';

  @override
  String get httpInspNeedEnable => '需先启用 HTTPS 检查';

  @override
  String get httpInspUrlPaused => '已暂停 · 解密请求直接放行，不应用 URL 规则及 CNAME 重定向';

  @override
  String get httpInspUrlOn => '开启解密流量下的 URL 屏蔽、放行及 CNAME 重定向';

  @override
  String get httpInspProtocolSection => '协议与兼容性';

  @override
  String get httpInspBlockHttp3 => '拦截 HTTP/3 (QUIC)';

  @override
  String get httpInspBlockHttp3Subtitle => '阻断 QUIC 促使回退至 TCP 以便解密；若异常请关闭';

  @override
  String get httpInspBlockDot => '阻断加密 DNS (DoT)';

  @override
  String get httpInspBlockDotSubtitle => '阻断 TCP 853 端口，防止绕过域名规则';

  @override
  String get httpInspRequestLogs => '请求日志';

  @override
  String get httpInspRequestLogsSubtitle => '查看解密明细与自动旁路记录';

  @override
  String get httpInspBypassFooter =>
      '写入 https_bypass_rules，与 assets/https_passthrough.txt 的内置清单合并后交给引擎的 setExtraPassthroughSuffixes。';

  @override
  String httpInspBypassTitle(int count) {
    return 'HTTPS 绕过规则（$count）';
  }

  @override
  String get httpInspBypassEmpty => '未配置自定义绕过规则';

  @override
  String get httpInspBypassEmptySubtitle => '内置放行清单始终生效；这里是额外追加的域名后缀';

  @override
  String get httpInspBypassRowSubtitle => '不参与解密，直接透传';

  @override
  String get httpInspCaRequiredTitle => '需要先安装根证书';

  @override
  String get httpInspGoInstall => '前往安装';

  @override
  String get httpInspCaReadingBody => '正在读取根证书状态，请稍后再试。';

  @override
  String httpInspCaRequiredBody(String problem) {
    return 'HTTPS 检查要把解密后的明文交回应用，必须由系统的根证书信任链认可谛听的根证书。当前是「$problem」，所以还不能选择目标应用。\n\n去 CA 证书页生成并安装证书？';
  }

  @override
  String get httpInspCaMissing => '尚未生成根证书：前往 CA 证书页生成';

  @override
  String get httpInspCaNotInstalled => '证书已生成但未安装到系统信任存储';

  @override
  String get httpInspCaReadyShort => '证书已就绪';

  @override
  String get httpInspNeedDomainRulesTitle => '还需要开启域名规则';

  @override
  String get httpInspEnableAll => '全部开启';

  @override
  String get httpInspNeedDomainRulesBody =>
      'HTTPS 检查负责解密，域名规则负责决定解密后的流量怎么处理。当前域名规则是关闭状态，只开检查不会有任何拦截效果。\n\n是否同时开启域名规则？';

  @override
  String get httpInspAppsTitle => '选择检查应用';

  @override
  String get httpInspSelectVisible => '全选当前结果';

  @override
  String get httpInspDeselectVisible => '取消当前结果';

  @override
  String get httpInspAppsIntro =>
      'Go 隧道接管流量后，HTTPS 流量检查仅检查所选应用的 HTTP(S) 请求，其他应用直接转发。选择应用会取消其「排除应用」「禁止联网」与应用独立规则状态。';

  @override
  String httpInspAppsCount(int selected, int visible) {
    return '已选择 $selected 个应用（可见 $visible）';
  }

  @override
  String get commonLater => '稍后';

  @override
  String get ruleControlSubsTitle => '规则订阅';

  @override
  String get cleanupIntro => '以下操作会立即删除本机数据，删除后无法恢复。重要规则或配置请在执行前备份。';

  @override
  String cleanupRunning(String title) {
    return '正在执行：$title';
  }

  @override
  String get cleanupDescLogs => '清除 DNS、HTTP 请求日志、竞速统计及 Bootstrap 解析日志';

  @override
  String get cleanupDescTraffic => '清除所有应用的历史流量统计记录与实时统计状态';

  @override
  String get cleanupDescCrash => '清除本地保存的所有 Java 与 Native 异常崩溃日志';

  @override
  String get cleanupDescDnsCache => '移除已缓存的解析结果，下次访问会重新查询';

  @override
  String get cleanupDescProviderWeights => '清除智能选择的健康样本，让它重新按默认权重分配流量';

  @override
  String get cleanupDescBootstrapWeights => '清除 Bootstrap DNS 解析健康样本，重新按默认权重选择';

  @override
  String get cleanupDescDomainRules => '清除域名屏蔽、白名单、IPv4/IPv6 覆写及对应订阅，恢复预设白名单';

  @override
  String get cleanupDescAddressRules => '清除 URL 屏蔽、放行和 CNAME 覆写规则，不影响域名规则';

  @override
  String get cleanupDescSubscriptions => '清除所有网络与本地规则订阅、订阅分组及自动更新任务';

  @override
  String get cleanupDescAppRules => '清空分应用排除、禁止联网应用、应用白名单及抓包名单';

  @override
  String get cleanupDescOutboundProxy => '清空出站代理协议、服务器与鉴权信息，恢复直连';

  @override
  String get cleanupDescCaCertificate => '清除本地生成的 MITM CA 根证书与私钥';

  @override
  String get cleanupDescDownloadCache => '删除更新安装包、下载临时文件及应用临时缓存';

  @override
  String get cleanupDescCustomBackground => '清除已配置的自定义壁纸图片缓存及路径记录，恢复默认背景';

  @override
  String get cleanupDescSettingsGuides => '让所有首次进入说明再次显示，需要重新同意使用协议';

  @override
  String get cleanupDescAllData => '深度清空所有日志、缓存、规则、订阅、证书与配置，应用将退出';

  @override
  String get cleanupConfirmLogs =>
      '确定要删除所有 DNS、HTTP 请求日志、竞速统计和 Bootstrap DNS 解析统计吗？';

  @override
  String get cleanupConfirmTraffic => '确定要清除所有应用的历史流量统计记录与实时统计状态吗？';

  @override
  String get cleanupConfirmCrash => '确定要删除所有本地崩溃日志和崩溃统计状态吗？';

  @override
  String get cleanupConfirmDnsCache => '确定要删除所有本地 DNS 缓存吗？下次访问域名时会重新查询。';

  @override
  String get cleanupConfirmProviderWeights => '确定要清除所有服务商健康样本并恢复竞速模式默认权重吗？';

  @override
  String get cleanupConfirmBootstrapWeights =>
      '确定要清除 Bootstrap DNS 解析健康样本并恢复默认权重吗？';

  @override
  String get cleanupConfirmDomainRules =>
      '确定要删除全部域名规则吗？域名屏蔽、白名单、IPv4/IPv6 覆写规则及对应订阅都会被移除，地址规则不受影响。';

  @override
  String get cleanupConfirmAddressRules =>
      '确定要删除全部地址规则吗？URL 屏蔽、放行和 CNAME 覆写规则都会被移除，域名规则不受影响。';

  @override
  String get cleanupConfirmSubscriptions =>
      '确定要删除所有规则订阅吗？所有订阅链接、分组与订阅导入的规则都会被移除，手动添加的规则不受影响。';

  @override
  String get cleanupConfirmAppRules =>
      '确定要重置所有应用控制名单吗？分应用代理排除、禁止联网应用、应用独立白名单以及 HTTP/HTTPS 抓包应用配置都将被清空并恢复默认。';

  @override
  String get cleanupConfirmOutboundProxy =>
      '确定要重置出站代理配置吗？出站代理将被禁用，服务器地址、端口及账号密码将被清除。';

  @override
  String get cleanupConfirmCaCertificate =>
      '确定要清除本地生成的 HTTPS 抓包 CA 证书和私钥吗？如果系统已安装此证书，清除后需重新生成并导入系统方可继续解密抓包。';

  @override
  String get cleanupConfirmDownloadCache => '确定要删除下载的更新安装包和临时缓存文件吗？';

  @override
  String get cleanupConfirmCustomBackground => '确定要清除自定义壁纸缓存并恢复默认外观背景吗？';

  @override
  String get cleanupConfirmSettingsGuides =>
      '确定要重置所有应用设置新手引导和首次使用协议吗？这不会删除任何配置、规则、缓存、日志或证书。操作完成后应用将退出；下次打开时需要重新同意使用协议，所有新手引导也会再次显示。';

  @override
  String get cleanupConfirmAllData =>
      '确定要执行全面数据清理吗？将依次清理所有日志、流量统计、崩溃记录、DNS 缓存、服务商权重、域名及地址规则、规则订阅、临时缓存及抓包证书。所有自定义配置与规则将被清空，新手引导也将重置，操作完成后应用将退出。';

  @override
  String get cleanupRestartTitle => '需要重启应用';

  @override
  String get cleanupRestartBody => '清理已完成。新手引导与使用协议已重置，应用需要重新启动才会生效。';

  @override
  String get commonConfirm => '确定';

  @override
  String get transferTitle => '备份与迁移';

  @override
  String get transferMetricProviders => 'DNS 服务商';

  @override
  String get transferMetricSubs => '规则订阅';

  @override
  String get transferMetricCustomRules => '自定义规则';

  @override
  String get transferMetricListedApps => '名单应用';

  @override
  String get transferSectionAppConfig => '应用配置备份';

  @override
  String get transferSectionRules => '规则与订阅配置';

  @override
  String get transferSectionAppControl => '应用控制与流量管理';

  @override
  String get transferSectionPersonal => '个性化与通用设置';

  @override
  String get transferDeselectAll => '全不选';

  @override
  String get transferImportExportSection => '导入导出';

  @override
  String get transferExportJson => '导出应用配置 (JSON)';

  @override
  String get transferExportHintNone => '请先勾选要导出的分组';

  @override
  String transferExportHintCount(int count) {
    return '将勾选的 $count 组配置保存为 JSON 文件';
  }

  @override
  String get transferImportJson => '导入应用配置 (JSON)';

  @override
  String get transferImportSubtitle => '从备份文件合并配置，自动跳过本机已存在项目';

  @override
  String get transferImportExportFooter =>
      '导出的配置文件包含个人自定义设置，请妥善保管；导入时将合并配置并自动跳过已存在的条目。出站代理的账号密码不在备份范围内。';

  @override
  String get transferCloudSection => '云端备份';

  @override
  String get transferWebdav => 'WebDAV 云同步';

  @override
  String get transferWebdavSubtitle => '把配置文件同步到自建 WebDAV 服务器';

  @override
  String get transferBusyExporting => '正在生成备份文件…';

  @override
  String get transferBusySaving => '等待选择保存位置…';

  @override
  String get transferBusyPickingImport => '等待选择备份文件…';

  @override
  String get transferExportEmpty => '所选分组没有可导出的内容';

  @override
  String get transferExportCancelled => '已取消保存';

  @override
  String transferExportDone(int groups, int items) {
    return '已导出 $groups 组、共 $items 项';
  }

  @override
  String transferExportSkipped(int count) {
    return '；跳过 $count 项';
  }

  @override
  String get transferExportFailed => '导出失败';

  @override
  String get transferImportCancelled => '已取消导入';

  @override
  String get transferImportTitle => '导入应用配置';

  @override
  String get transferImportFailedChip => '导入失败';

  @override
  String get transferImportDoneChip => '导入完成';

  @override
  String transferImportSummary(int added, int updated, int skipped) {
    return '导入汇总：新增 $added 项，更新 $updated 项，跳过 $skipped 项';
  }

  @override
  String transferSourceFile(String name) {
    return '来源文件：$name';
  }

  @override
  String transferExportedAt(String time) {
    return '备份导出于 $time';
  }

  @override
  String transferOutcomeRow(String group, String detail) {
    return '  + $group · $detail';
  }

  @override
  String transferFailedGroupRow(String group, String error) {
    return '  ! $group：$error';
  }

  @override
  String get transferNothingChanged => '  （备份中的条目本机都已存在，没有需要变更的内容）';

  @override
  String transferSubscriptionsNote(int count) {
    return '包含 $count 个订阅，请进入订阅管理执行规则更新。';
  }

  @override
  String get transferDone => '完成';

  @override
  String transferOutcomeAdded(int count) {
    return '新增 $count';
  }

  @override
  String transferOutcomeUpdated(int count) {
    return '更新 $count';
  }

  @override
  String transferOutcomeSkipped(int count) {
    return '跳过 $count';
  }

  @override
  String get transferNoChange => '无变化';

  @override
  String get transferOutcomeSeparator => '，';

  @override
  String get webdavClearConfig => '清空配置';

  @override
  String get webdavTest => '测试连接';

  @override
  String get webdavServer => '服务器';

  @override
  String get webdavUsername => '用户名';

  @override
  String get webdavPassword => '密码';

  @override
  String get webdavPath => '远端路径';

  @override
  String get webdavUpload => '上传备份';

  @override
  String get webdavDownload => '下载恢复';

  @override
  String webdavFooter(String hint) {
    return '「测试连接」会真实发起 WebDAV 请求：PROPFIND 探测目录，不存在则尝试创建。上传与下载走与「备份与迁移」同一份备份格式。$hint密码只存在内存里，不落盘。';
  }

  @override
  String get webdavFooterConnected => '连接成功后即可上传或恢复。';

  @override
  String get webdavNoConfig => '本机没有可备份的配置';

  @override
  String get webdavUploadFailed => '上传失败';

  @override
  String get webdavNoCloudBackup => '云端没有可恢复的备份';

  @override
  String get webdavRestoreTitle => '从云端恢复配置';

  @override
  String get webdavRestoreFailed => '恢复失败';

  @override
  String get webdavRestoreDone => '恢复完成';

  @override
  String webdavRestoreSummary(int added, int updated, int skipped) {
    return '恢复汇总：新增 $added 项，更新 $updated 项，跳过 $skipped 项';
  }

  @override
  String webdavOutcomeRow(String group, int added, int skipped) {
    return '  + $group · 新增 $added，跳过 $skipped';
  }

  @override
  String get webdavNothingChanged => '  （云端备份与本机一致，没有需要变更的内容）';

  @override
  String get webdavHintIdle => '配置服务器信息后可测试连接';

  @override
  String get webdavHintConnecting => '正在握手，请稍候';

  @override
  String get webdavHintConnected => '可上传备份或从云端恢复配置';

  @override
  String get webdavHintFailed => '检查地址、账号与证书后重试';

  @override
  String get backupGroupProviders => '自定义 DNS 服务商';

  @override
  String get backupGroupProvidersDesc => 'DoH、DoT 服务商与解析配置';

  @override
  String get backupGroupBootstrap => '自定义 Bootstrap IP';

  @override
  String get backupGroupBootstrapDesc => '引导 DNS 节点与启用状态';

  @override
  String get backupGroupCache => 'DNS 缓存策略';

  @override
  String get backupGroupCacheDesc => 'DNS 缓存开关、预设与 TTL 控制';

  @override
  String get backupGroupOutbound => '出站代理配置';

  @override
  String get backupGroupOutboundDesc => 'SOCKS5 / HTTP 代理与代理应用，不含账号密码';

  @override
  String get backupGroupSubscriptions => '网络规则订阅';

  @override
  String get backupGroupSubscriptionsDesc => '订阅源链接、镜像加速与自动更新';

  @override
  String get backupGroupDomainRules => '自定义屏蔽域名规则';

  @override
  String get backupGroupDomainRulesDesc => '手动添加的域名屏蔽规则及状态';

  @override
  String get backupGroupRewriteDomain => '自定义复写域名规则';

  @override
  String get backupGroupRewriteDomainDesc => 'IPv4 / IPv6 域名覆写规则';

  @override
  String get backupGroupRewriteCname => '自定义复写 CNAME 规则';

  @override
  String get backupGroupRewriteCnameDesc => 'CNAME 域名覆写规则';

  @override
  String get backupGroupAddressRules => '自定义屏蔽地址规则';

  @override
  String get backupGroupAddressRulesDesc => 'URL 路径屏蔽规则';

  @override
  String get backupGroupExcluded => '排除应用名单';

  @override
  String get backupGroupExcludedDesc => '绕过过滤使用系统 DNS 的应用';

  @override
  String get backupGroupBlocked => '禁止联网名单';

  @override
  String get backupGroupBlockedDesc => '服务运行时禁止联网的应用';

  @override
  String get backupGroupAllowlist => '应用独立规则与放行';

  @override
  String get backupGroupAllowlistDesc => '单应用放行规则与域名白名单';

  @override
  String get backupGroupHttpInspection => 'HTTPS 抓包检测配置';

  @override
  String get backupGroupHttpInspectionDesc => '流量抓包开关与目标应用名单';

  @override
  String get backupGroupAppearance => '外观与界面个性化';

  @override
  String get backupGroupAppearanceDesc => '主题风格、组件透明度与标语';

  @override
  String get backupGroupSystem => '系统与通用设置';

  @override
  String get backupGroupSystemDesc => '局域网绕行、日志模式、语言与通知';

  @override
  String webdavUploadedCount(int groups, int items) {
    return '已上传 $groups 组、共 $items 项';
  }

  @override
  String get agentApiEnabled => 'AI 分析已启用';

  @override
  String get agentApiDisabled => 'AI 分析未启用';

  @override
  String get agentApiNoProvider => '尚未配置 AI 厂商；请先在「AI 厂商管理」中添加并填写 API Key。';

  @override
  String agentApiCurrentProvider(String name, String model) {
    return '当前厂商：$name · $model';
  }

  @override
  String get agentApiNoModel => '未选择模型';

  @override
  String get agentApiKeyConfigured => '密钥已配置';

  @override
  String agentApiTemperature(String value) {
    return '温度 $value';
  }

  @override
  String get agentApiProviderChip => '请求由你的厂商处理';

  @override
  String get agentApiReadyHintOn => '补全厂商与密钥后，日志页就能直接发起分析。';

  @override
  String get agentApiReadyHintOff => '开启后即可在日志页直接发起分析。';

  @override
  String get agentApiSectionProvider => '厂商与参数';

  @override
  String agentApiProvidersSubtitle(int count) {
    return '$count 个已配置厂商 · 选择接口与模型';
  }

  @override
  String get agentParamsSubtitle => '系统提示词与采样温度';

  @override
  String get agentApiSectionTest => '功能测试';

  @override
  String get agentApiTestDomain => '分析一个域名';

  @override
  String get agentApiTestDomainSubtitle => '用示例域名真实调用模型，检查安全风险与处置建议';

  @override
  String get agentApiTestTraffic => '分析最近流量';

  @override
  String get agentApiTestTrafficSubtitle => '汇总最近 DNS 与 HTTPS 记录后真实调用模型';

  @override
  String get agentApiTestFooterReady => '两项都会真实请求你配置的厂商并消耗额度。';

  @override
  String get agentApiTestFooterNotReady => '当前配置不完整（未启用或缺少 API Key），点击会提示先补配置。';

  @override
  String get agentApiSectionEntries => '分析入口';

  @override
  String get agentApiCacheTable => 'DNS 缓存表';

  @override
  String get agentApiCacheTableSubtitle => '点按任意一行，分析该域名的安全风险';

  @override
  String get agentApiRequests => '请求记录';

  @override
  String get agentApiRequestsSubtitle => '打开一条请求的详情，底部可分析该域名';

  @override
  String get agentApiDashboard => '日志仪表盘';

  @override
  String get agentApiDashboardSubtitle => '「AI 研判」卡片可对最近流量发起整体分析';

  @override
  String get agentApiEntriesFooter =>
      '分析结果里的域名可以一键写入白名单或屏蔽规则，写入后启动 DNS VPN 生效。';

  @override
  String get agentApiSectionReset => '重置设置';

  @override
  String get agentApiResetItem => '恢复出厂默认配置';

  @override
  String get agentApiResetSubtitle => '将清空厂商、API Key、提示词与温度';

  @override
  String get agentApiFooter => 'AI 分析用于辅助研判，不会自动修改规则；所有请求由你配置的厂商处理，密钥只存在本机。';

  @override
  String get agentApiResetTitle => '恢复默认配置？';

  @override
  String get agentApiResetBody => '此操作将把所有 AI 分析参数、API Key 与系统提示词恢复为默认设置。';

  @override
  String get agentApiResetConfirm => '确认恢复';

  @override
  String get agentProvidersTitle => 'AI 厂商管理';

  @override
  String get agentProvidersAdd => '添加自定义厂商';

  @override
  String get agentProvidersIntro =>
      '点选下方预设厂商会自动预填接口地址；模型名请在编辑页点「拉取模型」从厂商真实返回的列表里选。编辑时若 API Key 留空则保留原密钥。密钥以旧版同一套掩码混淆后存在本机，不额外落明文。';

  @override
  String get agentProvidersMine => '我的厂商';

  @override
  String get agentProvidersEmpty => '暂无厂商';

  @override
  String get agentProvidersEmptySubtitle => '从下方预设厂商目录点选，或点击右上角添加自定义厂商';

  @override
  String agentProvidersRow(String model, String baseUrl, String key) {
    return '$model · $baseUrl · $key';
  }

  @override
  String get agentProvidersKeyConfigured => '密钥已配置';

  @override
  String get agentProvidersKeyMissing => '缺少密钥';

  @override
  String get agentProvidersFooter =>
      '点一行可切换当前生效厂商；切换会把接口地址、密钥与模型同步到旧版的四个平铺键，避免新版界面与旧版读取来源不一致。';

  @override
  String get agentProvidersAdded => '已添加';

  @override
  String get agentProvidersDeleteTitle => '删除厂商';

  @override
  String agentProvidersDeleteBody(String name) {
    return '确定要删除「$name」吗？相关 API Key 也会从本机移除。';
  }

  @override
  String get agentEditorAddTitle => '添加厂商';

  @override
  String get agentEditorEditTitle => '编辑厂商';

  @override
  String get agentEditorPaste => '从剪贴板识别';

  @override
  String get agentEditorName => '厂商名称';

  @override
  String get agentEditorBaseUrl => '接口地址';

  @override
  String get agentEditorModel => '模型名称';

  @override
  String get agentEditorModelHint => '点「拉取模型」从厂商返回的列表里选';

  @override
  String get agentEditorKeyKeep => '留空则保留原密钥';

  @override
  String get agentEditorKeyLocal => '仅保存在本机（旧版同一套掩码）';

  @override
  String get agentEditorFetching => '请求中…';

  @override
  String get agentEditorFetch => '拉取模型';

  @override
  String get agentEditorTest => '测试连接';

  @override
  String get agentEditorErrorRequired => '请填写名称、以 http(s) 开头的接口地址与模型名';

  @override
  String get agentEditorErrorBaseUrl => '请先填写接口地址';

  @override
  String get agentEditorErrorTestNeeds => '测试连接需要接口地址与模型名';

  @override
  String agentEditorFetched(int count) {
    return '拉取到 $count 个模型，点下方标签选择';
  }

  @override
  String agentEditorFetchFailed(String error) {
    return '拉取模型失败：$error';
  }

  @override
  String agentEditorConnected(String model) {
    return '连接成功：$model';
  }

  @override
  String agentEditorUsage(int tokens) {
    return '，用量 $tokens tokens';
  }

  @override
  String agentEditorConnectFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String get agentParamsTitle => '参数与提示词';

  @override
  String get agentParamsPromptSection => '系统提示词';

  @override
  String get agentParamsPromptItem => '系统提示词设定';

  @override
  String get agentParamsPromptUnset => '未设置（将使用各分析场景的内置提示词）';

  @override
  String get agentParamsPromptFooter => '留空时域名分析与流量分析各用自己那份内置提示词；填写后两者都以此为准。';

  @override
  String get agentParamsPromptHint => '例如：你是一名网络安全与 DNS 威胁情报专家……';

  @override
  String get agentParamsTemperatureSection => '采样温度（Temperature）';

  @override
  String get agentParamsTemperatureItem => '生成随机度与创造性';

  @override
  String get agentParamsTemperatureFooter =>
      '安全研判建议 0.2–0.4：温度越低，结论越稳定、越少自由发挥。';

  @override
  String get agentParamsTemperatureStrict => '严谨精确（适合安全分析与结构化输出）';

  @override
  String get agentParamsTemperatureBalanced => '平衡适中（推荐日常综合分析场景）';

  @override
  String get agentParamsTemperatureWild => '发散多变（输出内容更为丰富自由）';

  @override
  String get agentParamsTemplateSecurity => '安全威胁分析';

  @override
  String get agentParamsTemplateTechnical => '极简技术审查';

  @override
  String get agentParamsTemplatePrivacy => '隐私与遥测审查';

  @override
  String get agentSheetCopied => '分析结果已复制到剪贴板';

  @override
  String agentSheetRuleAdded(String kind) {
    return '已写入$kind，启动 DNS VPN 后生效';
  }

  @override
  String agentSheetRuleExists(String kind) {
    return '该域名已在$kind中';
  }

  @override
  String get agentSheetFooter => 'AI 只做研判，不会自动修改规则；结论仅供参考。请求由你配置的厂商处理，密钥只存在本机。';

  @override
  String get agentSheetDisabledTitle => 'AI 分析功能已关闭';

  @override
  String get agentSheetDisabledBody => 'AI 分析服务当前处于停用状态。你可以直接在此开启，或前往设置页面管理。';

  @override
  String get agentSheetEnableAndStart => '开启 AI 分析并继续';

  @override
  String get agentSheetNoKeyTitle => '未配置 API 密钥';

  @override
  String get agentSheetNoKeyBody => '需配置 OpenAI 兼容的 API 密钥后，方可使用 AI 域名与流量分析功能。';

  @override
  String get agentSheetGoConfigure => '前往配置';

  @override
  String get agentSheetRunning => '正在进行 AI 分析…';

  @override
  String agentSheetModel(String model) {
    return '模型 $model';
  }

  @override
  String get agentSheetUnknown => '未知';

  @override
  String get agentSheetFailed => '分析失败';

  @override
  String get agentSheetUnknownError => '未知错误';

  @override
  String get agentSheetCheckSettings => '检查设置';

  @override
  String get agentSheetNotStarted => '尚未分析';

  @override
  String get agentSheetSuperseded => '结果已被新的分析取代';

  @override
  String get agentSheetStartHint => '点下面的按钮开始分析。';

  @override
  String get agentSheetSupersededHint => '另一个分析请求覆盖了这次会话，重新分析可以取回结论。';

  @override
  String get agentSheetStart => '开始分析';

  @override
  String get agentSheetHideDigest => '收起送检摘要';

  @override
  String get agentSheetShowDigest => '查看送检摘要';

  @override
  String get agentSheetAddBlock => '加入屏蔽规则';

  @override
  String get agentSheetCopyResult => '复制结果';

  @override
  String get agentSheetReanalyze => '重新分析';

  @override
  String get agentTargetDomainTitle => '域名安全分析';

  @override
  String get agentTargetTrafficTitle => '网络流量分析';

  @override
  String get agentTargetTrafficSubtitle => '基于近期 DNS 与 HTTPS 监控数据';

  @override
  String get agentApiChipKeyMissing => '缺少 API Key';

  @override
  String get agentSheetAddAllowlist => '加入白名单';

  @override
  String get featureHubLongPress => '可长按';

  @override
  String get outboundSaved => '出站代理设置已保存，启动隧道后生效';

  @override
  String outboundSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get outboundResetTitle => '重置出站代理？';

  @override
  String get outboundResetBody => '将删除全部九个出站代理键（包括已加密保存的账号与密码）。';

  @override
  String get outboundResetDone => '已重置出站代理';

  @override
  String get outboundResetMenu => '重置出站代理';

  @override
  String get outboundSectionProxy => '代理';

  @override
  String get outboundEnable => '启用出站代理功能';

  @override
  String get outboundApp => '代理应用';

  @override
  String get outboundHostLabel => '地址';

  @override
  String get outboundHostHelper => '仅支持 127.0.0.1 或 ::1';

  @override
  String get outboundUsernameLabel => '账号（可选）';

  @override
  String get outboundPasswordLabel => '密码（可选）';

  @override
  String get outboundHttpFooter =>
      'HTTP CONNECT 不支持 UDP；UDP 会被严格阻断，QUIC 可回退到 TCP。代理应用本身将绕过 DITING。';

  @override
  String get outboundSocksFooter =>
      'SOCKS5 通过 UDP ASSOCIATE 转发 UDP。代理应用本身将绕过 DITING，防止流量环路。';

  @override
  String get outboundStatusOff => '未运行';

  @override
  String get outboundStatusConnecting => '正在连接';

  @override
  String get outboundStatusReady => '代理可用';

  @override
  String get outboundStatusFailed => '连接失败';

  @override
  String get outboundFooterError => '引擎上报的错误会一直保留到下一次隧道启动，便于回看原因。';

  @override
  String get outboundFooterReady => '引擎已确认代理可用；修改配置后需要重启隧道才会重新校验。';

  @override
  String get outboundFooterConnecting => '隧道启动时会校验代理连通性，结果会实时显示在这里。';

  @override
  String get outboundAppsTitle => '选择代理应用';

  @override
  String get outboundAppsIntro =>
      '选择提供本地代理端口的应用。代理应用本身会绕过 DITING。端口由该应用绑定，谛听无法代它监听。';

  @override
  String outboundAppsCount(int count) {
    return '已安装应用（$count）';
  }

  @override
  String get outboundAppsEmpty => '设备上没有可选的代理应用';

  @override
  String get resolutionSingleDesc => '所有查询都发往当前选中的服务商。';

  @override
  String get resolutionSmartDesc => '按历史成功率挑一个，失败后自动换下一个。';

  @override
  String get resolutionParallelDesc => '同时向所有服务商发起，取最先返回的结果。';

  @override
  String get resolutionPrimaryBackupDesc => '主服务商优先，超时后才动备用。';

  @override
  String resolutionProtocolSavedError(String error) {
    return '协议已保存，运行中的服务未能更新：$error';
  }

  @override
  String get resolutionBuiltinProtocol => '内置服务协议';

  @override
  String get resolutionBuiltinNote =>
      '仅切换内置服务商使用的 DNS / DoT / DoH 协议；自定义服务商按自身协议展示。';

  @override
  String get resolutionConfigSection => '模式配置';

  @override
  String get resolutionConfigFooter =>
      '解析模式与竞速服务商保存在当前工作模式的数据集里（普通 / 极速 / 服务器各自独立）。';

  @override
  String get resolutionNotConfigured => '未配置';

  @override
  String resolutionProviderCount(int count) {
    return '$count 个服务商';
  }

  @override
  String get resolutionPickerTitle => '选择解析模式';

  @override
  String get resolutionMinProviders => '至少保留 2 家服务商';

  @override
  String get resolutionSingleHint => '选择一个服务商作为唯一查询出口。';

  @override
  String resolutionRaceHint(int count) {
    return '已选 $count 家服务商，至少需要 2 家。';
  }

  @override
  String get resolutionReady => '已就绪';

  @override
  String get resolutionPending => '待配置';

  @override
  String get resolutionSectionSingle => '查询服务';

  @override
  String get resolutionSectionSmart => '候选服务';

  @override
  String get resolutionSectionParallel => '同时查询的服务';

  @override
  String get resolutionSectionBackup => '依次尝试的服务';

  @override
  String get resolutionNoProviders => '暂无此协议的服务商';

  @override
  String get resolutionMoveUp => '上移';

  @override
  String get resolutionMoveDown => '下移';

  @override
  String get outboundNoApp => '未选择';

  @override
  String get appRulesSaved => '已保存，启动 DNS VPN 后生效';

  @override
  String get appRulesClearAllTooltip => '清空全部放行规则';

  @override
  String get appRulesMasterSection => '总开关';

  @override
  String get appRulesMasterToggle => '启用单应用域名放行';

  @override
  String get appRulesNoConfigured => '暂未配置任何应用独立规则';

  @override
  String appRulesConfiguredSummary(int apps, int domains) {
    return '已配置 $apps 个应用 · 放行 $domains 个域名';
  }

  @override
  String get appRulesMasterFooter =>
      '为指定应用深度定制网络与解析控制：网络层白名单隔离（只放行列出的域名）、DNS 专属黑/白名单与「默认拦截全部外联」。进入某个应用可分别配置，保存后启动 DNS VPN 时下发。';

  @override
  String appRulesAppsCount(int count) {
    return '应用（$count）';
  }

  @override
  String get appRulesNoConfigurableApps => '设备上没有可配置的应用';

  @override
  String get appRulesFooterNoApps => '未读取到任何已安装应用，无法配置应用独立规则。';

  @override
  String get appRulesFooterSave =>
      '保存后写入 app_allowlist_enabled 与 app_allowlist_rules_json，启动 DNS VPN 时下发给引擎。';

  @override
  String get appRulesAddAllowDomain => '添加放行域名';

  @override
  String get appRulesAppSection => '应用';

  @override
  String get appRulesBackToList => '返回应用列表';

  @override
  String get appRulesClearAllTitle => '清空全部放行规则？';

  @override
  String get appRulesClearAllBody => '将删除所有应用的专属放行域名。保存后生效，黑名单与全阻断设置不受影响。';

  @override
  String get appRulesRuleExists => '规则已存在或规则库不可用';

  @override
  String appRulesRuleAdded(String kind) {
    return '已添加$kind规则';
  }

  @override
  String get appRulesDeleteRuleTitle => '删除这条规则？';

  @override
  String get appRulesFullBlockOn => '已开启全外联拦截模式';

  @override
  String get appRulesFullBlockOff => '已关闭全外联拦截模式';

  @override
  String get appRulesAddDnsRule => '添加 DNS 规则';

  @override
  String get appRulesDnsScopeIntro =>
      '这些规则写入规则库的 block_rule / allow_rule，带 appScope 只对本应用生效，并随规则快照的 appRules 下发，不会扩大成全局拦截。';

  @override
  String get appRulesDnsScopeSection => 'DNS 专属黑/白名单';

  @override
  String get appRulesReadingRules => '正在读取规则库';

  @override
  String get appRulesWait => '稍候';

  @override
  String get appRulesRuleDbUnreadable => '读不到规则库';

  @override
  String get appRulesRuleDbUnavailable => '当前环境无法读写规则库';

  @override
  String get appRulesNoScopedRules => '未配置 DNS 专属规则';

  @override
  String get appRulesNoScopedRulesSubtitle => '添加后仅对本应用生效，不影响其他应用';

  @override
  String appRulesScopedCount(int count) {
    return 'DNS 专属黑/白名单（$count）';
  }

  @override
  String appRulesAllowDomainTitle(int count) {
    return '专属放行域名（网络层） ($count)';
  }

  @override
  String get appRulesNoAllowDomains => '未配置网络放行域名';

  @override
  String get appRulesNoAllowDomainsSubtitle => '网络层白名单为空时，该应用不受额外限制';

  @override
  String get appRulesAllowDomainFooter =>
      '这些域名会写入 app_allowlist_rules_json，由引擎在下一次启动隧道时下发给 setAppAllowlist。';

  @override
  String get appRulesIsolationSection => '外联与隔离模式';

  @override
  String get appRulesFullBlockToggle => '默认拦截全部外联';

  @override
  String get appRulesFullBlockToggleSubtitle => '开启后阻断该应用的所有网络连接，仅放行白名单';

  @override
  String get appRulesFullBlockOnTitle => '已开启全阻断模式';

  @override
  String get appRulesFullBlockOnBody => '请确保已添加必要的放行白名单，否则应用可能无法联网。';

  @override
  String get providerMgmtDeleteTitle => '删除 DNS 服务商';

  @override
  String providerMgmtDeleteBody(String name) {
    return '确定删除「$name」吗？删除后无法再作为解析服务使用。';
  }

  @override
  String get providerMgmtTitle => '服务商管理';

  @override
  String get providerMgmtAdd => '新增 DNS 服务商';

  @override
  String get providerMgmtCurrent => '当前用于解析 DNS';

  @override
  String get providerMgmtBuiltin => '内置服务商';

  @override
  String get providerMgmtCustom => '自定义服务商';

  @override
  String get providerMgmtEmptyCustom => '暂无自定义服务商';

  @override
  String get providerMgmtEmptyCustomSubtitle => '点击右上角「+」添加 DoH、DoT 或传统 DNS 服务';

  @override
  String get providerMgmtFooter => '内置服务商由应用维护，只能切换；自定义服务商可编辑或删除。';

  @override
  String get providerMgmtEditTitle => '编辑 DNS 服务商';

  @override
  String get providerMgmtAddressLabel => '地址';

  @override
  String get providerMgmtPortLabel => '端口';

  @override
  String get providerMgmtDohAddressLabel => 'DoH 地址';

  @override
  String get providerMgmtNameRequired => '请填写名称';

  @override
  String get providerMgmtDohRequired => 'DoH 地址需以 https:// 开头';

  @override
  String get providerMgmtAddressRequired => '请填写地址';

  @override
  String get providerMgmtPortRange => '端口需在 1–65535 之间';

  @override
  String get providerMgmtProbeTooltip => '测试该服务是否可用';

  @override
  String providerMgmtProbeOk(int ms) {
    return '可用 · $ms ms';
  }

  @override
  String providerMgmtProbeFailed(String message) {
    return '不可用：$message';
  }

  @override
  String get providerMgmtProbeNoResponse => '无响应';

  @override
  String get notifModeSingle => '单一服务';

  @override
  String get notifModeSmart => '智能选择';

  @override
  String get notifModeParallel => '最快响应';

  @override
  String get notifModeBackup => '依次尝试';

  @override
  String notifRunningMode(String mode, int count) {
    return '运行中 · [$mode] $count 个服务商';
  }

  @override
  String notifRunningProvider(String name) {
    return '运行中 · $name';
  }

  @override
  String notifRunningServer(String name, int port) {
    return '运行中 · $name · 端口 $port';
  }

  @override
  String notifRunningServerMode(String mode, int count, int port) {
    return '运行中 · [$mode] $count 个服务商 · 端口 $port';
  }

  @override
  String platformNoSaveDialog(String error) {
    return '无法打开保存对话框：$error';
  }

  @override
  String platformNoFilePicker(String error) {
    return '无法打开文件选择器：$error';
  }

  @override
  String get platformNoFilePickerShort => '无法打开文件选择器';

  @override
  String get platformNoLocalRead => '当前环境不支持读取本地文件';

  @override
  String platformReadFailed(String error) {
    return '无法读取该文件：$error';
  }

  @override
  String get platformNoSystemPicker => '当前环境不支持系统文件选择器';

  @override
  String updateConnectFailed(String error) {
    return '检查更新失败：无法连接（$error）';
  }

  @override
  String get updateTlsFailed => '检查更新失败：TLS 证书校验不通过';

  @override
  String get updateBadJson => '检查更新失败：服务器返回的内容不是合法 JSON';

  @override
  String get updateRateLimited =>
      '检查更新失败：GitHub 接口限流（未认证请求每小时 60 次），请稍后再试或直接访问项目发布页';

  @override
  String get updateForbidden => '检查更新失败：GitHub 拒绝访问（HTTP 403）';

  @override
  String get updateNotFound => '检查更新失败：仓库或发布页不存在（HTTP 404）';

  @override
  String updateServerError(int status) {
    return '检查更新失败：GitHub 服务异常（HTTP $status）';
  }

  @override
  String updateUnexpectedStatus(int status) {
    return '检查更新失败：GitHub 返回 $status';
  }

  @override
  String get updateResponseNotJson => '检查更新失败：响应不是合法 JSON';

  @override
  String get updateUnexpectedFormat => '检查更新失败：响应格式不符合预期';

  @override
  String get updateMissingTag => '检查更新失败：最新版本缺少 tag_name';

  @override
  String get updateNoApk => '最新版本未提供 Android APK';

  @override
  String get updateBadDownloadUrl => '更新包下载地址无效';

  @override
  String updateApkFileName(String version) {
    return '谛听-$version.apk';
  }

  @override
  String get agentApiEmptyEndpoint => '接口地址为空，请先在「AI 厂商管理」里填写';

  @override
  String get agentApiNoModelListJson => '服务端未返回模型列表（响应不是 JSON 对象）';

  @override
  String get agentApiNoModelListData => '服务端未返回模型列表（响应中缺少 data 字段）';

  @override
  String get agentApiNoModels => '接口未返回任何模型，请手动填写模型名称';

  @override
  String get agentApiKeyEmpty => 'API Key 不能为空';

  @override
  String get agentApiKeyEmptyHint => 'API Key 不能为空，请先在 AI 分析设置中配置';

  @override
  String get agentApiResponseNotJsonObject => '服务端响应不是 JSON 对象';

  @override
  String get agentApiEmptyContent => '模型返回了空内容，请检查模型名称或稍后重试';

  @override
  String agentApiBadUrl(String url) {
    return '接口地址不合法：$url';
  }

  @override
  String get agentApiCancelled => '分析已取消';

  @override
  String get agentApiTimeout => '请求超时：模型服务在限定时间内没有响应';

  @override
  String agentApiUnreachable(String error) {
    return '无法连接模型服务（$error）';
  }

  @override
  String get agentApiTls => 'TLS 握手失败：服务端证书不可信或协议不匹配';

  @override
  String get agentApiInvalidJson => '服务端响应不是合法 JSON';

  @override
  String get agentApiBadKey => 'API Key 无效或已过期';

  @override
  String get agentApiNoAccess => '密钥无权访问该模型，或该地区被限制';

  @override
  String get agentApiModelNotFound => '接口地址或模型名称不存在（404）';

  @override
  String get agentApiRateLimited => '请求过于频繁或额度用尽（429）';

  @override
  String agentApiUnavailable(int status) {
    return '模型服务暂时不可用（$status）';
  }

  @override
  String agentApiRequestFailed(int status) {
    return '请求失败（$status）';
  }

  @override
  String agentApiServerDetail(String message) {
    return '：$message';
  }

  @override
  String get davProbeNoWrite => '服务器可达但无法创建目录，请检查账号是否具备写入权限';

  @override
  String davProbeConnect(String error) {
    return '无法连接到服务器：$error';
  }

  @override
  String get davProbeTls => 'TLS 握手失败：服务器证书不被信任（自签证书需在系统里安装）';

  @override
  String get davProbeHttp => 'HTTP 请求失败，请检查服务器是否支持 WebDAV';

  @override
  String davUploadConnect(String error) {
    return '上传失败：无法连接服务器（$error）';
  }

  @override
  String get davUploadTls => '上传失败：TLS 证书不被信任';

  @override
  String davDownloadHttp(int status) {
    return '下载失败（HTTP $status）';
  }

  @override
  String get davStatus401 => '认证失败：用户名或密码不正确';

  @override
  String get davStatus403 => '服务器拒绝访问：该账号没有读写此目录的权限';

  @override
  String get davStatus404 => '服务器上找不到该目录';

  @override
  String get davStatus405 => '服务器不允许该操作（可能未启用 WebDAV）';

  @override
  String get davStatus409 => '目标目录不存在，无法写入';

  @override
  String get davStatus507 => '服务器存储空间不足';

  @override
  String davStatus5xx(int status) {
    return '服务器内部错误（HTTP $status）';
  }

  @override
  String davStatusOther(int status) {
    return '服务器返回 HTTP $status';
  }

  @override
  String get ipQualityNoExitIp => '无法获取当前出口 IP：网络不可达或探测服务超时';

  @override
  String get ipQualityNoSourceResult => '所有 IP 情报源均未返回结果，请检查网络后重试';

  @override
  String get disclaimerTerm1Title => '一、软件性质';

  @override
  String get disclaimerTerm1Content =>
      '谛听是一款开源的本地域名解析与流量观测工具，不以任何形式提供网络接入服务。软件本身不含任何服务器、节点或订阅内容，也不代替任何网络服务商。';

  @override
  String get disclaimerTerm2Title => '二、使用方式';

  @override
  String get disclaimerTerm2Content =>
      '用户应仅在自有设备与自有网络上使用本软件。将本软件用于任何网络接入、绕过计费或在未授权网络上运行的行为，均超出软件设计用途。';

  @override
  String get disclaimerTerm3Title => '三、责任范围';

  @override
  String get disclaimerTerm3Content =>
      '因使用或无法使用本软件导致的任何直接或间接损失，包括但不限于数据丢失、服务中断、设备损坏，作者与贡献者均不承担责任。';

  @override
  String get disclaimerTerm4Title => '四、第三方组件';

  @override
  String get disclaimerTerm4Content =>
      '本软件的界面组件层移植自 DITING（GPL-3.0-or-later），并使用了 material_ui、material_color_utilities 等开源组件。各组件的许可条款见仓库 NOTICE.md，使用本软件即表示同时接受这些条款。';

  @override
  String get disclaimerTerm5Title => '五、无担保';

  @override
  String get disclaimerTerm5Content =>
      '本软件按「现状」提供，不附带任何明示或暗示的担保，包括但不限于适销性、特定用途适用性与不侵权的担保。';

  @override
  String get disclaimerTerm6Title => '六、责任限制';

  @override
  String get disclaimerTerm6Content =>
      '在法律允许的最大范围内，作者不对任何间接、附带、特殊或后果性损害负责，即使已被告知此类损害的可能性。';

  @override
  String get disclaimerTerm7Title => '七、隐私';

  @override
  String get disclaimerTerm7Content =>
      '本软件默认不收集、不上传任何用户数据。日志与规则仅保存在本地；若用户主动配置 WebDAV 备份，数据将上传至用户自行指定的服务器。';

  @override
  String get disclaimerTerm8Title => '八、许可';

  @override
  String get disclaimerTerm8Content =>
      '本软件以 GPL-3.0-or-later 发布。你可以自由使用、修改与再分发，但衍生作品必须沿用同一许可并保留原始版权声明。';

  @override
  String get disclaimerTerm9Title => '九、条款变更';

  @override
  String get disclaimerTerm9Content =>
      '作者保留随时修改本免责声明的权利。变更后的条款随新版本一同发布，继续使用即视为接受修改后的条款。';

  @override
  String get disclaimerTerm10Title => '十、接受条款';

  @override
  String get disclaimerTerm10Content =>
      '在继续使用本软件前，请确认你已阅读、理解并同意上述全部条款。若不同意，请立即停止使用并卸载本软件。';

  @override
  String get settingsModeSubtitle => '切换普通模式或服务器模式';

  @override
  String get settingsPerformanceSection => '性能优化';

  @override
  String get settingsCacheSubtitle => '缓存已解析的域名，减少重复查询';

  @override
  String get settingsLogModeSubtitle => '选择 DNS 请求日志的记录范围';

  @override
  String get settingsRuntimeSection => '运行行为';

  @override
  String get settingsForegroundSubtitle => '后台隐藏、通知常驻、绕过局域网';

  @override
  String get settingsAutoStartTitle => '启动时自动开启';

  @override
  String get settingsAutoStartSubtitle => '上次未手动关闭时，打开应用自动恢复普通或极速模式';

  @override
  String get settingsVpnWatchdogTitle => 'VPN 看门狗';

  @override
  String get settingsVpnWatchdogSubtitle => 'VPN 通道被其他应用占用时持续监测，释放后自动重新连接';

  @override
  String get settingsDataSection => '数据管理';

  @override
  String get settingsLanguageSubtitle => '选择应用界面语言';

  @override
  String get settingsWizardSubtitle => '查看当前工作模式的架构原理、权限配置与上手指引';

  @override
  String get settingsGuideSection => '上手引导';

  @override
  String get backupErrEmpty => '文件内容为空';

  @override
  String backupErrInvalidJson(String error) {
    return '不是合法的 JSON：$error';
  }

  @override
  String get backupErrRootNotObject => '备份文件的根节点必须是 JSON 对象';

  @override
  String get backupErrNotDiting => '这不是谛听的备份文件：缺少 format 标记';

  @override
  String get backupErrNoVersion => '备份文件缺少版本号';

  @override
  String backupErrVersionTooHigh(String version, int max) {
    return '备份版本 $version 高于本版应用支持的 $max，请升级应用后再导入';
  }

  @override
  String get backupErrNoData => '备份文件缺少 data 段';

  @override
  String get backupErrProvidersNotArray => '服务商分组应为数组';

  @override
  String get backupErrBootstrapNotObject => 'Bootstrap 分组应为对象';

  @override
  String get backupErrCacheNotObject => '缓存分组应为对象';

  @override
  String get backupErrOutboundNotObject => '出站代理分组应为对象';

  @override
  String get backupErrBlockedNotObject => '禁止联网分组应为对象';

  @override
  String get backupErrAppRulesNotObject => '应用独立规则分组应为对象';

  @override
  String get backupErrInspectionNotObject => 'HTTPS 抓包分组应为对象';

  @override
  String get backupErrSubsNotObject => '订阅分组应为对象';

  @override
  String get backupErrNoRuleDbSubs => '本机还没有规则库，无法导入订阅';

  @override
  String get backupErrRulesNotArray => '规则分组应为数组';

  @override
  String get backupErrNoRuleDbRules => '本机还没有规则库，无法导入规则';

  @override
  String get backupErrRewriteNotArray => '覆写规则分组应为数组';

  @override
  String get backupErrNoRuleDbRewrite => '本机还没有规则库，无法导入覆写规则';

  @override
  String get backupErrAddressNotArray => '地址规则分组应为数组';

  @override
  String get backupErrNoRuleDbAddress => '本机还没有规则库，无法导入地址规则';

  @override
  String get agentPasteEmpty => '剪贴板为空';

  @override
  String get agentPasteBoth => '已自动识别并填入服务地址与 API Key';

  @override
  String get agentPasteBaseUrl => '已填入服务地址';

  @override
  String get agentPasteKey => '已填入 API Key';

  @override
  String get agentPasteJson => '已从 JSON 中识别并更新 API 配置';

  @override
  String logDirect(String protocol) {
    return '$protocol 直连';
  }

  @override
  String logDirectWithApp(String protocol, String app) {
    return '$protocol 直连 · $app';
  }

  @override
  String get subsErrUrlUnavailable => '订阅地址不可用';

  @override
  String subsErrTimeout(int seconds) {
    return '下载超时（读取 $seconds 秒）';
  }

  @override
  String get subsErrTls => 'TLS 握手失败，请检查证书或镜像地址';

  @override
  String get subsErrEmptyResponse => '订阅响应为空';

  @override
  String get subsErrUnreachable => '网络不可达';

  @override
  String subsErrUnreachableCode(String code) {
    return '网络不可达：$code';
  }

  @override
  String get subsErrUnsupported => '当前环境不支持网络订阅更新';

  @override
  String subsErrMirrorPlaceholder(String list) {
    return '镜像模板必须包含 $list';
  }

  @override
  String get subsErrRawUrlInvalid => '原始订阅地址格式无效';

  @override
  String get subsErrMirrorScheme => '镜像模板生成的地址必须使用 HTTP 或 HTTPS';

  @override
  String get subsErrEmpty => '订阅地址不能为空';

  @override
  String get subsErrBadFormat => '订阅地址格式无效';

  @override
  String get subsErrNotHttp => '订阅链接必须使用 HTTP 或 HTTPS';

  @override
  String get subsErrNoHost => '订阅地址缺少主机名';

  @override
  String get siteCategoryShopping => '购物';

  @override
  String get siteCategoryVideo => '视频';

  @override
  String get siteCategoryMusic => '音乐';

  @override
  String get siteCategorySocial => '社交';

  @override
  String get siteCategoryDeveloper => '开发者';

  @override
  String get siteCategoryGame => '游戏';

  @override
  String get outboundProxyHostInvalid => '代理地址仅支持 127.0.0.1 或 ::1';

  @override
  String get outboundProxyPortRange => '代理端口必须在 1 到 65535 之间';

  @override
  String get outboundProxyAppRequired => '请选择提供本地代理端口的应用';

  @override
  String get outboundProxySelfNotAllowed => '不能选择 DITING 自身作为代理应用';

  @override
  String get outboundProxyAppMissing => '所选代理应用未安装';

  @override
  String get outboundProxyCredentialsTooLong => '代理账号或密码过长';

  @override
  String get updateDownloadNoPath => '下载失败：未返回安装包路径';

  @override
  String get updateDownloadUnsupported => '当前设备不支持应用内下载，请用浏览器打开下载地址';

  @override
  String updateDownloadFailedCode(String code) {
    return '下载失败（$code）';
  }

  @override
  String dnsLatencySuccessRate(int success, int attempts) {
    return '成功率 $success/$attempts';
  }

  @override
  String get dnsLatencyUnsupported => '当前设备不支持测速';

  @override
  String dnsLatencyChannelFailedCode(String code) {
    return '测速通道调用失败（$code）';
  }

  @override
  String dnsLatencyChannelFailedDetail(String detail) {
    return '测速通道调用失败：$detail';
  }

  @override
  String get fontImportFailed => '无法导入该字体';

  @override
  String get fontReadFailed => '无法读取该字体文件';

  @override
  String get fontParseFailed => '无法解析该字体文件，请确认它是完整的 TTF/OTF';

  @override
  String get fontCustomName => '自定义字体';

  @override
  String get recognitionAvatarTooLarge => '头像体积超限';

  @override
  String get recognitionConfigTooLarge => '名单配置过大';

  @override
  String get taglineRunning => '谛听万象，明察清浊';

  @override
  String get taglineStopped => '收耳静眠，归于无声';

  @override
  String get backupErrProvidersInvalidJson => '服务商配置不是合法 JSON';

  @override
  String get backupErrBootstrapInvalidJson => 'Bootstrap 配置不是合法 JSON';

  @override
  String get backupErrAppearanceNotObject => '外观分组应为对象';

  @override
  String get backupErrSystemNotObject => '系统设置分组应为对象';

  @override
  String get outboundScopeTitle => '代理范围';

  @override
  String get outboundScopeAll => '全部应用';

  @override
  String get outboundScopeApps => '仅选中应用';

  @override
  String get outboundScopeAllFooter => '所有应用的连接以及谛听自身的 DNS 上游查询都经过代理。';

  @override
  String get outboundScopeAppsFooter =>
      '只有选中应用的连接经过代理；其他应用、无法识别归属的连接以及谛听自身的 DNS 上游查询直接连接。';

  @override
  String get outboundTargets => '走代理的应用';

  @override
  String get outboundTargetsTitle => '选择走代理的应用';

  @override
  String get outboundTargetsIntro =>
      '勾选的应用会经代理连接网络，修改后需重启隧道生效。代理应用本身、谛听以及「排除应用」中的应用不经过隧道，无法走代理，因此不在列表中。';

  @override
  String get outboundProxyTargetsRequired => '「仅选中应用」模式下请至少选择一个走代理的应用';

  @override
  String get logDashboardCardHero => '仪表盘标题';

  @override
  String get logDashboardCardTrafficStructure => '流量结构';

  @override
  String logDashboardEditHint(String mode) {
    return '正在编辑「$mode」模式的布局，切换日志模式后各自独立。拖动手柄排序，点右上角移除。';
  }

  @override
  String get logDashboardModeFooter => '这里只列出当前日志模式能显示数据的卡片。';

  @override
  String get logDashboardCardHeroDescription => '页面顶部的标题与一句话说明，随日志模式变化';

  @override
  String get logDashboardCardTrafficMonitorDescription => '上下行实时速率与今日累计流量';

  @override
  String get logDashboardCardRequestOverviewDescription => '今日请求、放行、拦截与缓存命中计数';

  @override
  String get logDashboardCardHighlightDescription => '今日拦截、错误与旁路的重点计数';

  @override
  String get logDashboardCardPrivacyDescription => '说明日志已关闭、不记录任何请求';

  @override
  String get logDashboardCardOffMetricDescription =>
      '缓存条目、缓存命中、竞速与 Bootstrap 次数';

  @override
  String get logDashboardCardPerfDescription => '平均延迟、缓存命中率与竞速、Bootstrap 成功率';

  @override
  String get logDashboardCardAiDescription => '用 AI 研判今日流量，复用上一次的报告';

  @override
  String get logDashboardCardTrafficStructureDescription => '今日请求结果构成的环形图';

  @override
  String get logDashboardCardRecentRequestsDescription => '最近几条请求记录';

  @override
  String get logDashboardCardRecentBlockedDescription => '最近几条拦截与错误记录';

  @override
  String get logDashboardCardCacheDescription => '命中次数最多的缓存域名';

  @override
  String get logDashboardCardRaceDescription => '竞速中胜出最多的上游';

  @override
  String get logDashboardCardBootstrapDescription => 'Bootstrap DNS 的解析次数与成功率';

  @override
  String get logDashboardCardRuleBlocksDescription => '拦截次数最多的规则来源';

  @override
  String get logStatsTitle => '统计';

  @override
  String get logStatsRequests => '请求';

  @override
  String get logStatsTotal => '总请求';

  @override
  String get logStatsData => '数据使用';

  @override
  String get logStatsSaved => '缓存节省';

  @override
  String get logStatsUploaded => '已上传';

  @override
  String get logStatsDownloaded => '已下载';

  @override
  String get logStatsWindow => '统计范围';

  @override
  String get logStatsRecentActivity => '最近的活动';

  @override
  String get logDashboardCardStatsDescription =>
      '按今日、本周、本月或全部历史统计拦截、缓存命中与上下行流量';

  @override
  String get floatingLogOpen => '打开悬浮窗日志';

  @override
  String get floatingLogTitle => '实时请求';

  @override
  String get floatingLogPaused => '已暂停';

  @override
  String get floatingLogSearch => '搜索';

  @override
  String get floatingLogSearchHint => '域名、应用或规则';

  @override
  String get floatingLogPause => '暂停刷新';

  @override
  String get floatingLogResume => '继续刷新';

  @override
  String get floatingLogMinimize => '收起为悬浮球';

  @override
  String get floatingLogPanelSize => '面板大小';

  @override
  String get floatingLogSizeSmall => '小';

  @override
  String get floatingLogSizeMedium => '中';

  @override
  String get floatingLogSizeLarge => '大';

  @override
  String get floatingLogClear => '清空列表';

  @override
  String get floatingLogOpenApp => '打开谛听';

  @override
  String get floatingLogHide => '本次隐藏';

  @override
  String get floatingLogHideHint => '回到应用后再次显示';

  @override
  String get floatingLogCopied => '已复制';

  @override
  String get floatingLogCopyDomain => '复制域名';

  @override
  String get floatingLogCopyRecord => '复制记录';

  @override
  String get floatingLogEmpty => '暂无请求';

  @override
  String get floatingLogEmptyBody => '新的请求会实时出现在这里。';

  @override
  String get floatingLogClearedBody => '列表已清空，新的请求会继续出现。';

  @override
  String get floatingLogNoMatchBody => '换个关键词或筛选条件试试。';

  @override
  String get floatingLogUnavailable => '无法读取日志';

  @override
  String get floatingLogUnavailableBody => '日志数据库尚未创建，请先在应用中启动一次隧道。';

  @override
  String floatingLogShown(int count) {
    return '显示 $count 条';
  }

  @override
  String floatingLogNewRows(int count) {
    return '$count 条新请求';
  }

  @override
  String get floatingLogPermissionTitle => '悬浮窗权限';

  @override
  String get floatingLogPermissionGranted => '已授予';

  @override
  String get floatingLogPermissionMissing => '未授予，点按前往系统设置开启';

  @override
  String get floatingLogOpacity => '面板不透明度';

  @override
  String get floatingLogSizeTitle => '面板大小';

  @override
  String get logRetentionOverlayHowTo => '拖动悬浮球或面板标题栏可移动位置；点按一行展开详情，长按复制域名。';

  @override
  String get permOverlay => '悬浮窗';

  @override
  String get desktopDnsServiceTitle => 'DNS 服务';

  @override
  String get desktopQueriesTitle => '查询指标';

  @override
  String get desktopQueriesTotal => '总查询';

  @override
  String get desktopQueriesSuccess => '成功';

  @override
  String get desktopQueriesFailed => '失败';

  @override
  String get desktopQps => 'QPS';

  @override
  String get desktopCacheTitle => '缓存';

  @override
  String get desktopCacheHits => '命中';

  @override
  String get desktopCacheEvictions => '淘汰';

  @override
  String get desktopFilterTitle => '规则拦截';

  @override
  String get desktopFilterRules => '有效防护规则';

  @override
  String get desktopFilterBlockRate => '拦截比例';

  @override
  String get desktopTakeoverTitle => '系统 DNS 接管';

  @override
  String get desktopTakeoverOn => '已接管';

  @override
  String get desktopTakeoverOff => '未接管';

  @override
  String get desktopFilterPauseTitle => '临时暂停拦截';

  @override
  String get desktopFilterPaused => '已暂停';

  @override
  String get desktopFilterActive => '生效中';

  @override
  String get desktopServiceHostTitle => '后台服务';

  @override
  String get desktopServiceAutoStart => '开机自启';

  @override
  String get desktopServiceNotInstalled => '未安装';

  @override
  String get desktopVersion => '版本';

  @override
  String get desktopProcessId => '进程';

  @override
  String get desktopPerformanceTitle => '性能';

  @override
  String get desktopRuntimeTitle => '运行信息';

  @override
  String get desktopLanAllowed => '局域网';

  @override
  String get desktopListeningOn => '监听';

  @override
  String get desktopStartDns => '启动 DNS';

  @override
  String get desktopStopDns => '停止 DNS';

  @override
  String get desktopStartDnsTitle => '启动 DNS 服务？';

  @override
  String get desktopStartDnsMessage => '启动后本机解析与规则过滤随之生效。';

  @override
  String get desktopStopDnsTitle => '停止 DNS 服务？';

  @override
  String get desktopStopDnsMessage => '停止后本机解析回到系统默认 DNS，接管与规则随之失效。';

  @override
  String get desktopBackendOfflineTitle => '连不上本机服务';

  @override
  String desktopBackendOfflineBody(String address) {
    return '确认谛听服务正在运行，并监听 $address。';
  }

  @override
  String get desktopBackendUnauthorizedTitle => '需要访问令牌';

  @override
  String get desktopBackendUnauthorizedBody => '本机服务已启用 IPC 令牌，填入令牌后才能读取状态。';

  @override
  String desktopActionFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String desktopLastUpdated(String time) {
    return '更新于 $time';
  }

  @override
  String get desktopRetry => '重试';

  @override
  String get desktopRecentQueriesTitle => '最近查询';

  @override
  String get desktopRecentQueriesEmpty => '还没有查询记录';

  @override
  String get desktopLogWindow24h => '近 24 小时';

  @override
  String get desktopLogDomain => '域名';

  @override
  String get desktopLogClient => '客户端';

  @override
  String get desktopLogDomainHint => '域名包含';

  @override
  String get desktopLogClientHint => '客户端 IP 或主机名';

  @override
  String get desktopLogAllTypes => '全部类型';

  @override
  String get desktopLogClear => '清空历史';

  @override
  String get desktopLogClearTitle => '清空查询历史？';

  @override
  String get desktopLogClearBody => '将删除全部内存记录与已落盘的历史日志文件，此操作不可撤销。';

  @override
  String get desktopLogClearDone => '查询历史与统计已清空';

  @override
  String desktopLogClearFailed(String message) {
    return '清空失败：$message';
  }

  @override
  String get desktopLogTopDomains => '高频访问域名';

  @override
  String get desktopLogTopBlocked => '拦截命中排行';

  @override
  String get desktopLogTopClients => '活跃客户端';

  @override
  String get desktopLogNoBlocked => '暂无拦截记录';

  @override
  String get desktopLiveTitle => '实时查询流';

  @override
  String get desktopLiveConnected => '实时监听中';

  @override
  String get desktopLivePaused => '已暂停';

  @override
  String get desktopLiveDisconnected => '未连接';

  @override
  String get desktopLiveDisconnectedBody => '本机事件通道没有连上，实时记录暂停；查询历史与统计仍可正常读取。';

  @override
  String desktopLiveShown(String count) {
    return '符合筛选 $count 条';
  }

  @override
  String get desktopLiveSearchHint => '检索域名或客户端 IP';

  @override
  String get desktopLiveOnlyBlocked => '仅看已拦截';

  @override
  String get desktopLivePause => '暂停';

  @override
  String get desktopLiveResume => '继续';

  @override
  String get desktopLiveClear => '清空';

  @override
  String get desktopLiveEmpty => '还没有推送的查询';

  @override
  String get desktopLiveCaptured => '缓冲区记录';

  @override
  String get desktopLiveBlocked => '已拦截';

  @override
  String get desktopLiveSuccessRate => '成功率';

  @override
  String desktopLiveBufferNote(String count) {
    return '滚动缓冲区上限 $count 条';
  }

  @override
  String get desktopLiveStale => '容灾复用';

  @override
  String get desktopLogConfigTitle => '查询日志与留存策略';

  @override
  String get desktopLogConfigEnabled => '启用查询日志记录';

  @override
  String get desktopLogConfigEnabledBody => '关闭后不再记录任何查询历史与统计，DNS 解析不受影响';

  @override
  String get desktopLogConfigMaxEntries => '内存缓冲条数';

  @override
  String get desktopLogConfigRetentionDays => '落盘留存天数';

  @override
  String get desktopLogConfigFile => '历史记录落盘';

  @override
  String get desktopLogConfigFileBody =>
      '按天写入 JSON-Lines 文件，供历史检索回溯（目录不可写时自动降级为纯内存）';

  @override
  String get desktopLogConfigClients => '记录客户端信息';

  @override
  String get desktopLogConfigClientsBody => '记录发起查询的设备 IP 与主机名；关闭后仅保留域名维度统计';

  @override
  String desktopLogConfigDataDir(String path) {
    return '落盘目录：$path';
  }

  @override
  String get desktopLogConfigSave => '保存策略';

  @override
  String get desktopLogConfigSaved => '查询日志配置已保存并生效';

  @override
  String get desktopLogConfigLoadFailed => '读不到查询日志配置';

  @override
  String get desktopLogConfigInvalid => '缓冲条数与留存天数需为正整数';

  @override
  String get desktopLogPagePrev => '上一页';

  @override
  String get desktopLogPageNext => '下一页';

  @override
  String desktopLogPageInfo(String from, String to, String total) {
    return '第 $from–$to 条，共 $total 条';
  }

  @override
  String get desktopHubResolveSection => '解析服务';

  @override
  String get desktopHubProtectSection => '拦截防护';

  @override
  String get desktopHubUpstream => '上游解析';

  @override
  String get desktopHubUpstreamBody => '调度策略、上游节点、Bootstrap 引导与条件分流';

  @override
  String get desktopUpstreamTitle => '上游解析';

  @override
  String get desktopUpstreamModeTitle => '上游调度策略';

  @override
  String get desktopUpstreamModeBody => '选择多服务器协同工作与容灾模式';

  @override
  String get desktopUpstreamModeSingle => '单服务器模式';

  @override
  String get desktopUpstreamModeSingleBody => '始终固定使用列表中的首选服务器进行解析';

  @override
  String get desktopUpstreamModeBackup => '主备自动容灾';

  @override
  String get desktopUpstreamModeBackupBody => '平时优先使用主服务器，超时或故障时自动切换至备用服务器';

  @override
  String get desktopUpstreamModeRace => '并发极速响应';

  @override
  String get desktopUpstreamModeRaceBody => '同时向全部服务器发送查询，自动采用最快返回的结果，解析延迟最低';

  @override
  String get desktopUpstreamModeSmart => '智能延迟优选';

  @override
  String get desktopUpstreamModeSmartBody => '根据各服务器近期响应速度与稳定性动态评分，智能选用最优质服务器';

  @override
  String get desktopUpstreamNodesTitle => '已配置的 DNS 服务器';

  @override
  String get desktopUpstreamNodesBody => '管理用于解析域名的 DNS 服务器，支持加密传输与智能容灾测速';

  @override
  String desktopUpstreamNodesCount(int count) {
    return '$count 个节点';
  }

  @override
  String get desktopUpstreamAdd => '添加 DNS 服务器';

  @override
  String get desktopUpstreamAddTitle => '添加 DNS 服务器';

  @override
  String get desktopUpstreamEditTitle => '编辑 DNS 服务器';

  @override
  String get desktopUpstreamName => '服务器名称 / 标识';

  @override
  String get desktopUpstreamProtocol => '连接协议';

  @override
  String get desktopUpstreamAddress => '服务器地址 (IP 或域名)';

  @override
  String get desktopUpstreamUrl => '加密解析地址 (URL)';

  @override
  String get desktopUpstreamPin => '证书指纹 (可选，SHA-256)';

  @override
  String get desktopUpstreamPinWarning =>
      '填写指纹后将替代系统 CA 链校验，仅适用于自签或私有 CA 部署的上游。指纹不匹配时该上游将完全不可用。';

  @override
  String get desktopUpstreamPreset => '常用推荐预设';

  @override
  String get desktopUpstreamPresetProvider => '服务商';

  @override
  String get desktopUpstreamPresetProtocol => '解析协议';

  @override
  String get desktopUpstreamStamp => 'DNS 印章 (sdns://)';

  @override
  String get desktopUpstreamStampHint => '粘贴印章';

  @override
  String get desktopUpstreamStampParse => '解析';

  @override
  String get desktopUpstreamStampParsing => '解析中…';

  @override
  String get desktopUpstreamStampEmpty => '请先粘贴 sdns:// 印章';

  @override
  String desktopUpstreamStampFailed(String message) {
    return '印章解析失败：$message';
  }

  @override
  String desktopUpstreamStampParsed(String proto) {
    return '已解析为 $proto';
  }

  @override
  String get desktopUpstreamInvalid => '服务器名称与地址不得为空';

  @override
  String get desktopUpstreamDeleteTitle => '确认删除';

  @override
  String desktopUpstreamDeleteBody(String name) {
    return '确定删除上游 DNS 服务器 [$name] 吗？';
  }

  @override
  String get desktopUpstreamKeepOne => '请至少保留一个 DNS 服务器以维持正常的域名解析服务。';

  @override
  String get desktopUpstreamEmpty => '暂无配置 DNS 服务器';

  @override
  String get desktopUpstreamEmptyBody => '请添加主备 DNS 服务器后保存。';

  @override
  String get desktopUpstreamTest => '测试延迟';

  @override
  String desktopUpstreamTestFailed(String message) {
    return '测试失败：$message';
  }

  @override
  String desktopUpstreamSaveFailed(String message) {
    return '更新 DNS 配置失败：$message';
  }

  @override
  String get desktopUpstreamSaved => 'DNS 服务器配置已更新并即时生效';

  @override
  String get desktopUpstreamLoadFailed => '读取上游配置失败';

  @override
  String get desktopUpstreamBootstrapTitle => 'Bootstrap 引导解析';

  @override
  String get desktopUpstreamBootstrapBody =>
      '建立 DoT（TLS）和 DoH（HTTPS）加密连接前解析上游域名的前置服务器，优先使用纯 IP 地址。';

  @override
  String get desktopUpstreamBootstrapOn => '引导启用';

  @override
  String get desktopUpstreamBootstrapOff => '已停用';

  @override
  String get desktopUpstreamBootstrapAdd => '添加引导';

  @override
  String get desktopUpstreamBootstrapEmpty => '未配置 Bootstrap DNS 服务器';

  @override
  String get desktopUpstreamBootstrapKeepOne =>
      '请至少保留一个 Bootstrap DNS 服务器，避免加密握手域名无法解析。';

  @override
  String get desktopUpstreamBootstrapName => '名称';

  @override
  String get desktopUpstreamBootstrapAddress => 'IP 地址 (可带端口)';

  @override
  String get desktopUpstreamBootstrapInvalid => '请填写名称与 IP 地址';

  @override
  String desktopUpstreamBootstrapDeleteBody(String name) {
    return '确定删除引导服务器 [$name] 吗？';
  }

  @override
  String get desktopUpstreamRoutesTitle => '条件分流路由';

  @override
  String get desktopUpstreamRoutesBody =>
      '为内部私有域名定向指定专用 DNS 服务器，支持 *.internal 这类泛域名';

  @override
  String get desktopUpstreamRoutesAdd => '添加分流规则';

  @override
  String get desktopUpstreamRoutesEmpty => '暂未配置条件分流路由，全部域名请求遵循全局调度模式。';

  @override
  String get desktopUpstreamRouteDomain => '匹配域名或后缀';

  @override
  String get desktopUpstreamRouteServer => '定向 DNS 服务器地址';

  @override
  String get desktopUpstreamRouteInvalid => '请填写匹配域名与目标 DNS 地址';

  @override
  String desktopUpstreamRouteDeleteBody(String domain) {
    return '确定删除匹配域名 [$domain] 的分流规则吗？';
  }

  @override
  String get desktopUpstreamFallbackPolicyTitle => '回退触发条件';

  @override
  String get desktopUpstreamFallbackPolicyBody => '何时改用备用上游：超时、应答码与解析失败';

  @override
  String get desktopUpstreamFallbackPolicyOff => '备用链未开启，触发条件暂不生效。';

  @override
  String get desktopUpstreamFallbackTitle => '独立回退上游';

  @override
  String get desktopUpstreamFallbackBody => '主链路整体失效后整链切换的备用解析链路';

  @override
  String get desktopUpstreamFallbackOff => '未启用';

  @override
  String desktopUpstreamFallbackCount(int count) {
    return '$count 个回退节点';
  }

  @override
  String get desktopUpstreamFallbackNote =>
      '与主链路是两条独立链路：主链路先以独立超时尝试整条链，失败或命中下列响应码后，才整链切换到回退上游。';

  @override
  String get desktopUpstreamFallbackEmpty => '未配置回退上游，DNS 查询量不会因此增加。';

  @override
  String get desktopUpstreamFallbackAdd => '添加回退节点';

  @override
  String get desktopUpstreamFallbackTimeout => '主链路独立超时（毫秒）';

  @override
  String get desktopUpstreamFallbackTimeoutHint =>
      '留空或 0 使用服务端默认 2000ms，取值范围 100–30000。';

  @override
  String get desktopUpstreamFallbackRcode => '触发回退的响应码';

  @override
  String get desktopUpstreamFallbackRcodeHint =>
      '默认仅 SERVFAIL 与 REFUSED。NXDOMAIN 是权威有效判定，勾选它会让「域名不存在」也去问备用上游。';

  @override
  String get desktopUpstreamFallbackOnError => '超时、连接失败等链路故障同样触发回退';

  @override
  String desktopUpstreamWeight(int weight) {
    return '权重 $weight';
  }

  @override
  String get desktopUpstreamPinSet => '指纹固定';

  @override
  String get desktopUpstreamPresetMissing => '该服务商未提供此协议的公开端点，请手动填写';

  @override
  String get desktopUpstreamProbeFailed => '测试失败';

  @override
  String get desktopUpstreamBootstrapAddTitle => '添加 Bootstrap DNS 服务器';

  @override
  String get desktopUpstreamBootstrapEditTitle => '编辑 Bootstrap DNS 服务器';

  @override
  String get desktopHubCache => '解析缓存';

  @override
  String get desktopHubCacheBody => '命中率、容量、TTL 策略、排除规则与落盘持久化';

  @override
  String get desktopCacheEngineTitle => '智能解析加速引擎';

  @override
  String get desktopCacheEngineBody => '自动缓存已访问过的解析结果，下次访问直接返回；上游抖动时复用近期记录兜底。';

  @override
  String get desktopCacheEngineOn => '加速生效中';

  @override
  String get desktopCacheEngineOff => '加速已停用';

  @override
  String get desktopCacheHitRatio => '缓存命中率';

  @override
  String get desktopCacheRefresh => '刷新数据';

  @override
  String get desktopCacheClear => '一键清空缓存';

  @override
  String get desktopCacheClearTitle => '确定清空所有加速缓存？';

  @override
  String desktopCacheClearBody(int count) {
    return '此操作将清空当前全部已缓存的网址记录（共 $count 条）。清空后后续访问将重新通过网络解析。';
  }

  @override
  String get desktopCacheClearDone => '加速缓存已全部清空';

  @override
  String desktopCacheClearFailed(String message) {
    return '清空缓存失败：$message';
  }

  @override
  String get desktopCacheTelemetryTitle => '缓存遥测指标';

  @override
  String desktopCacheTelemetryCapacity(int used, int max) {
    return '容量 $used / $max';
  }

  @override
  String get desktopCacheMisses => '实时联网解析';

  @override
  String get desktopCacheStaleHits => '弱网应急保障';

  @override
  String get desktopCacheNegativeHits => '无效网址拦截';

  @override
  String get desktopCachePrefetchCount => '热点预取刷新';

  @override
  String get desktopCacheTopTitle => '高频访问网址排行';

  @override
  String get desktopCacheTopBody => '本地缓存命中次数最高的前 10 个域名';

  @override
  String get desktopCacheTopEmpty => '暂无高频网址访问记录';

  @override
  String desktopCacheTopHits(int count) {
    return '$count 次';
  }

  @override
  String get desktopCacheConfigTitle => '加速策略设置';

  @override
  String get desktopCacheConfigBody => '有效期规则、弱网容灾与热点预取';

  @override
  String get desktopCacheConfigSave => '保存策略';

  @override
  String get desktopCacheConfigSaved => '加速策略已保存并即时生效';

  @override
  String get desktopCacheFallbackTitle => '弱网回退';

  @override
  String get desktopCacheFallbackBody => '上游抖动时用过期记录兜底，以及先回旧值再刷新的乐观模式';

  @override
  String get desktopCacheModeLabel => '记录有效期计算方式';

  @override
  String get desktopCacheModeLimit => '限制最长有效期（推荐）';

  @override
  String get desktopCacheModeFollow => '完全遵从上游 TTL';

  @override
  String get desktopCacheModeFixed => '强制使用固定有效期';

  @override
  String get desktopCacheMaxTtl => '最长保存时长（秒）';

  @override
  String get desktopCacheMinTtl => '最短保留时长（秒）';

  @override
  String get desktopCacheFixedTtl => '固定有效期（秒）';

  @override
  String get desktopCacheMinTtlEnabled => '应用最短保留时长';

  @override
  String get desktopCacheStaleTitle => '弱网应急保障（旧记录兜底）';

  @override
  String get desktopCacheStaleBody => '上游超时或断网时，复用近期缓存防止网页报错';

  @override
  String get desktopCacheStaleSeconds => '应急保留期（秒）';

  @override
  String get desktopCacheOptimistic => '极速响应';

  @override
  String get desktopCacheOptimisticBody => '先返回缓存，后台静默刷新';

  @override
  String get desktopCacheNegative => '无效网址记忆加速';

  @override
  String get desktopCacheNegativeBody => '记住不存在或错误的域名，避免频繁重复重试';

  @override
  String get desktopCacheNegativeSeconds => '无效记录保留（秒）';

  @override
  String get desktopCachePrefetchTitle => '热点域名主动预取';

  @override
  String get desktopCachePrefetchBody => '在常用域名记录到期前提前回源刷新，避免首次访问等待';

  @override
  String get desktopCachePrefetchThreshold => '命中次数门槛';

  @override
  String get desktopCachePrefetchThresholdHint => '被访问达到该次数的域名才会预取';

  @override
  String get desktopCachePrefetchBefore => '剩余有效期阈值（毫秒）';

  @override
  String get desktopCachePrefetchBeforeHint => '剩余有效期低于该值时触发刷新';

  @override
  String get desktopCacheInvalidNumbers => '秒数与阈值需为正整数';

  @override
  String desktopCacheSaveFailed(String message) {
    return '保存缓存配置失败：$message';
  }

  @override
  String get desktopCacheLoadFailed => '读不到缓存配置';

  @override
  String get desktopCachePersistTitle => '缓存落盘持久化';

  @override
  String get desktopCachePersistBody =>
      '把内存中的解析结果定期写入磁盘，服务重启后可直接读回。默认关闭：读取上次的应答会让「上游已变更但仍命中旧记录」更难察觉。';

  @override
  String get desktopCachePersistOn => '已开启';

  @override
  String get desktopCachePersistOff => '未开启';

  @override
  String get desktopCachePersistInterval => '定时落盘间隔（秒）';

  @override
  String get desktopCachePersistIntervalHint =>
      '取值范围 30–86400；留空或 0 使用默认值 300。服务退出时总会额外写一次。';

  @override
  String get desktopCachePersistPath => '落盘文件';

  @override
  String desktopCachePersistLastError(String message) {
    return '最近一次落盘失败：$message';
  }

  @override
  String desktopCachePersistRecords(int count) {
    return '当前 $count 条可落盘记录';
  }

  @override
  String get desktopCacheSnapshotTitle => '磁盘快照';

  @override
  String get desktopCacheSnapshotBody => '把当前缓存立即写入落盘文件，或从文件读回上次的记录';

  @override
  String get desktopCachePersistDump => '立即落盘';

  @override
  String get desktopCachePersistLoad => '从文件恢复';

  @override
  String desktopCachePersistDumpDone(int count) {
    return '已落盘 $count 条缓存记录';
  }

  @override
  String desktopCachePersistLoadDone(int count) {
    return '已从落盘文件恢复 $count 条缓存记录';
  }

  @override
  String desktopCachePersistDumpFailed(String message) {
    return '落盘失败：$message';
  }

  @override
  String desktopCachePersistLoadFailed(String message) {
    return '恢复失败：$message';
  }

  @override
  String get desktopCachePersistLoadTitle => '确定从落盘文件恢复缓存？';

  @override
  String get desktopCachePersistLoadBody =>
      '文件中仍有效的记录会被读入当前缓存，覆盖同名的现有条目；已过期的记录会被自动忽略。';

  @override
  String get desktopCachePersistToggleOn => '缓存落盘已开启';

  @override
  String get desktopCachePersistToggleOff => '缓存落盘已关闭';

  @override
  String get desktopCachePersistIntervalSaved => '落盘间隔已更新';

  @override
  String get desktopCacheExcludeTitle => '缓存排除规则';

  @override
  String get desktopCacheExcludeBody =>
      '命中规则的域名既不读取也不写入缓存，每次都实时回源。适用于内网域名、动态 IP 探测等「缓存反而出错」的场景。';

  @override
  String get desktopCacheExcludeOff => '未启用';

  @override
  String desktopCacheExcludeCount(int count) {
    return '$count 条规则';
  }

  @override
  String get desktopCacheExcludeLabel => '正则表达式（一行一条，Go RE2 语法）';

  @override
  String get desktopCacheExcludeHint => '例如：\\.local\$';

  @override
  String get desktopCacheExcludeSave => '保存规则';

  @override
  String desktopCacheExcludeSaved(int count) {
    return '已保存 $count 条排除规则';
  }

  @override
  String get desktopCacheExcludeCleared => '已清空排除规则，全部域名重新参与缓存';

  @override
  String desktopCacheExcludeFailed(String message) {
    return '保存排除规则失败：$message';
  }

  @override
  String desktopCacheExcludeHits(int count) {
    return '已拦截 $count 次缓存读写';
  }

  @override
  String get desktopCacheExcludeReset => '撤销修改';

  @override
  String desktopCacheExcludeTooMany(int max) {
    return '规则超过 $max 条，超出部分不会被保存';
  }

  @override
  String desktopCacheExcludeTooLong(int count, int max) {
    return '$count 条规则超过 $max 字符，保存时会被忽略';
  }

  @override
  String get desktopCacheExcludePresetLocal => '内网单标签域';

  @override
  String get desktopCacheExcludePresetPtr => 'PTR 反查';

  @override
  String get desktopCacheExcludePresetProbe => '临时探测域';

  @override
  String get desktopCacheEntriesTitle => '已缓存域名明细';

  @override
  String get desktopCacheEntriesBody => '实时查看分片缓存记录、TTL 有效期与解析 IP';

  @override
  String get desktopCacheEntriesSearch => '搜索网址或记录类型…';

  @override
  String get desktopCacheEntriesEmpty => '未匹配到符合条件的缓存条目';

  @override
  String get desktopCacheEntriesNone => '缓存中暂无记录';

  @override
  String get desktopCacheEntriesLoadFailed => '读取缓存条目失败';

  @override
  String get desktopCacheFilterAll => '全部';

  @override
  String get desktopCacheFilterFresh => '有效记录';

  @override
  String get desktopCacheFilterStale => '应急备用';

  @override
  String get desktopCacheFilterNegative => '无效网址';

  @override
  String get desktopCacheEntryDomain => '网址 / 域名';

  @override
  String get desktopCacheEntryType => '类型';

  @override
  String get desktopCacheEntryStatus => '状态';

  @override
  String get desktopCacheEntryRemaining => '剩余有效期';

  @override
  String get desktopCacheEntryTtl => '初始 TTL';

  @override
  String get desktopCacheEntryHits => '命中次数';

  @override
  String get desktopCacheEntryIps => '解析 IP 列表';

  @override
  String get desktopCacheStatusFresh => '有效';

  @override
  String get desktopCacheStatusStale => '应急备用';

  @override
  String get desktopCacheStatusNegative => '无效网址';

  @override
  String get desktopCacheNoIps => '无';

  @override
  String get desktopHubRewrite => '自定义重写';

  @override
  String get desktopHubRewriteBody => '把域名指向指定 IP、别名或 TXT，本地直接权威应答';

  @override
  String get desktopRewriteTitle => '自定义 DNS 重写';

  @override
  String get desktopRewriteEngineTitle => '自定义 DNS 重写与域名伪装';

  @override
  String get desktopRewriteEngineBody =>
      '匹配规则在上游解析前直接权威应答，无需等待外网请求；支持精确域名与 *.lan 泛域名。';

  @override
  String get desktopRewriteEngineOn => '重写引擎已就绪';

  @override
  String get desktopRewriteEngineOff => '重写引擎已停用';

  @override
  String get desktopRewriteEnabled => '重写已启用';

  @override
  String get desktopRewriteDisabled => '重写已关闭';

  @override
  String get desktopRewriteDefaultTtl => '默认生存期（秒）';

  @override
  String get desktopRewriteTtlSave => '保存';

  @override
  String get desktopRewriteTtlSaved => '默认重写 TTL 已保存';

  @override
  String get desktopRewriteTtlInvalid => 'TTL 需为正整数';

  @override
  String get desktopRewriteToggleOn => '自定义 DNS 重写已开启';

  @override
  String get desktopRewriteToggleOff => '自定义 DNS 重写已关闭';

  @override
  String desktopRewriteSaveFailed(String message) {
    return '保存重写配置失败：$message';
  }

  @override
  String get desktopRewriteLoadFailed => '读不到 DNS 重写配置';

  @override
  String get desktopRewriteRulesTitle => 'DNS 重写规则列表';

  @override
  String get desktopRewriteRulesBody => '当前生效的自定义伪装映射';

  @override
  String desktopRewriteRulesCount(int count) {
    return '$count 条规则';
  }

  @override
  String get desktopRewriteAdd => '添加重写规则';

  @override
  String get desktopRewriteSearch => '搜索域名、目标 IP 或别名…';

  @override
  String get desktopRewriteEmpty => '暂未添加任何 DNS 重写规则，点击上方按钮即可添加';

  @override
  String get desktopRewriteNoMatch => '未找到符合条件的重写规则';

  @override
  String get desktopRewriteResetSearch => '清除检索';

  @override
  String get desktopRewriteDomain => '匹配域名';

  @override
  String get desktopRewriteTypes => '类型';

  @override
  String get desktopRewriteTarget => '重写目标详情';

  @override
  String get desktopRewriteTtl => 'TTL';

  @override
  String get desktopRewriteActions => '操作';

  @override
  String get desktopRewriteEdit => '编辑重写规则';

  @override
  String get desktopRewriteDelete => '删除规则';

  @override
  String desktopRewriteSeconds(int count) {
    return '$count 秒';
  }

  @override
  String get desktopRewriteNoTarget => '无目标';

  @override
  String desktopRewriteRcodeOnly(String rcode) {
    return '仅返回 $rcode，不返回任何记录';
  }

  @override
  String get desktopRewriteDeleteTitle => '删除 DNS 重写规则';

  @override
  String desktopRewriteDeleteBody(String domain) {
    return '确定要删除域名「$domain」的 DNS 重写规则吗？';
  }

  @override
  String desktopRewriteRuleSaved(String domain) {
    return '重写规则「$domain」已保存并生效';
  }

  @override
  String desktopRewriteRuleDeleted(String domain) {
    return '重写规则「$domain」已删除';
  }

  @override
  String desktopRewriteRuleFailed(String message) {
    return '保存重写规则失败：$message';
  }

  @override
  String desktopRewriteDeleteFailed(String message) {
    return '删除规则失败：$message';
  }

  @override
  String get desktopRewriteAddTitle => '添加 DNS 重写与伪装规则';

  @override
  String get desktopRewriteEditTitle => '编辑 DNS 重写规则';

  @override
  String get desktopRewriteDomainLabel => '匹配域名';

  @override
  String get desktopRewriteDomainHint => '如 host.lan 或 *.home.local';

  @override
  String get desktopRewriteDomainHelp =>
      '支持精确域名（如 router.lan）或泛域名（如 *.cluster.internal）';

  @override
  String get desktopRewriteDomainRequired => '请输入匹配域名（支持精准匹配或 *.lan 泛域名）';

  @override
  String get desktopRewriteTargetMode => '应答目标';

  @override
  String get desktopRewriteModeShortcut => '快捷目标';

  @override
  String get desktopRewriteModeRecords => '自定义记录';

  @override
  String get desktopRewriteTargetType => '重写目标类型';

  @override
  String get desktopRewriteTypeIp => 'A / AAAA 地址';

  @override
  String get desktopRewriteTypeCname => 'CNAME 别名';

  @override
  String get desktopRewriteTypeTxt => 'TXT 文本';

  @override
  String get desktopRewriteIpsLabel => 'IPv4 / IPv6 目标解析地址';

  @override
  String get desktopRewriteIpsHelp => '每行一个 IP 地址，支持多 IP 负载均衡返回';

  @override
  String get desktopRewriteCnameLabel => 'CNAME 目标重定向域名';

  @override
  String get desktopRewriteCnameHelp => '系统将自动遵循别名链进行递归解析';

  @override
  String get desktopRewriteTxtLabel => 'TXT 记录内容（每行一条）';

  @override
  String get desktopRewriteRecordsLabel => '自定义记录';

  @override
  String get desktopRewriteRecordAdd => '添加记录';

  @override
  String get desktopRewriteRecordEmpty => '尚未添加记录，点击「添加记录」开始';

  @override
  String get desktopRewriteRecordValueHint => '记录取值';

  @override
  String get desktopRewriteRecordsHelp =>
      '取值语法与 AdGuard 的 dnsrewrite 一致：MX 填「优先级 主机」，SRV 填「优先级 权重 端口 目标」，HTTPS/SVCB 填「优先级 目标 参数…」。仅与匹配记录类型的查询返回这些记录。';

  @override
  String get desktopRewriteRcodeLabel => '应答码覆盖（可选）';

  @override
  String get desktopRewriteRcodeNone => '不覆盖（正常返回记录）';

  @override
  String get desktopRewriteRcodeWarning =>
      '选择失败应答码后，本条规则只返回该错误码，不再返回任何记录；客户端会认为该域名不可用或被拒绝。';

  @override
  String get desktopRewriteTtlLabel => '生存时间 TTL（秒，可选）';

  @override
  String get desktopRewriteTtlHint => '留空则使用全局默认 TTL';

  @override
  String get desktopRewriteNeedIp => '请输入至少一个 IPv4 或 IPv6 目标解析地址';

  @override
  String get desktopRewriteNeedCname => '请输入 CNAME 别名重定向目标域名';

  @override
  String get desktopRewriteNeedTxt => '请输入至少一条 TXT 记录文本';

  @override
  String get desktopRewriteNeedRecord => '请至少添加一条有效记录（类型与取值均不能为空）';

  @override
  String get desktopRewriteChipEmpty => '空';

  @override
  String get desktopZoneSettingsTitle => '区域解析开关与默认 TTL';

  @override
  String get desktopZoneSettingsBody => '开关本地权威区域，并设置没有写明 TTL 的记录使用多久';

  @override
  String get desktopZoneTitle => '本地权威区（zone 文件）';

  @override
  String get desktopZoneBody =>
      '整段声明一个名字空间由本机负责，区内未收录的名字返回权威 NODATA 而非转发上游；适合内网域名与局域网服务发现';

  @override
  String desktopZoneBadge(int zones, int maxZones, int records) {
    return '$zones / $maxZones 区 · $records 个名字';
  }

  @override
  String get desktopZoneRules =>
      '区顶点及其以下所有名字都由本地负责：区里没有的名字会被权威地判为「不存在」，不会漏到公网，同名时也优先于 hosts 条目。因此顶点要写成完整后缀（如 lan.），而不是单条域名。区文件语法遵循 RFC 1035，INCLUDE 指令出于安全考虑一律拒绝。';

  @override
  String get desktopZoneDefaultTtl => '默认 TTL（秒）';

  @override
  String get desktopZoneTtlSaved => '本地权威区默认 TTL 已保存';

  @override
  String get desktopZoneTtlInvalid => 'TTL 需为正整数';

  @override
  String get desktopZoneToggleOn => '本地权威区已启用';

  @override
  String get desktopZoneToggleOff => '本地权威区已停用';

  @override
  String desktopZoneSaveFailed(String message) {
    return '保存本地权威区配置失败：$message';
  }

  @override
  String get desktopZoneLoadFailed => '读不到本地权威区配置';

  @override
  String desktopZoneLimit(int records) {
    return '合计上限 $records 条记录；超出部分会被截断并在区上标注。';
  }

  @override
  String get desktopZoneAdd => '添加区';

  @override
  String get desktopZoneSaveAll => '保存全部';

  @override
  String get desktopZoneSaved => '本地权威区配置已保存并生效';

  @override
  String get desktopZoneEmpty => '尚未配置任何本地权威区';

  @override
  String desktopZoneMaxZones(int max) {
    return '最多支持 $max 个区，请先删除不再使用的区';
  }

  @override
  String get desktopZoneOriginHint => '区顶点，如 lan.';

  @override
  String desktopZoneDeleted(String origin) {
    return '区「$origin」已删除';
  }

  @override
  String get desktopZoneUnnamed => '（未命名）';

  @override
  String get desktopZoneStateDisabled => '已停用';

  @override
  String get desktopZoneStatePending => '待构建';

  @override
  String get desktopZoneStateFailed => '解析失败';

  @override
  String desktopZoneStateTruncated(int count) {
    return '已加载 $count 条（截断）';
  }

  @override
  String desktopZoneStateLoaded(int count) {
    return '已加载 $count 条';
  }

  @override
  String get desktopZoneFailedReason => '该区未被加载';

  @override
  String get desktopZoneExpand => '展开编辑';

  @override
  String get desktopZoneCollapse => '收起';

  @override
  String get desktopZoneDelete => '删除该区';

  @override
  String get desktopZoneContent => '区文件内容';

  @override
  String get desktopZonePreview => '预演解析';

  @override
  String get desktopZonePreviewNote => '用与后端一致的解析路径试跑一次；改动需点「保存全部」才会生效。';

  @override
  String get desktopZonePreviewEmpty => '（空区，无记录）';

  @override
  String desktopZonePreviewMore(int count) {
    return '… 其余 $count 条已省略';
  }

  @override
  String get desktopHubDns64 => 'IPv6 / DNS64';

  @override
  String get desktopHubDns64Body => '为纯 IPv6 网络把仅有 IPv4 记录的目标合成为 AAAA';

  @override
  String get desktopDns64Title => 'IPv6 / DNS64';

  @override
  String get desktopDns64Refresh => '刷新 DNS64 配置';

  @override
  String get desktopDns64CardTitle => 'DNS64 IPv6-only 网络过渡合成';

  @override
  String get desktopDns64CardBody =>
      '遵循 RFC 6052 / RFC 6147，为纯 IPv6 终端自动把仅有 A 记录的目标合成为 AAAA';

  @override
  String get desktopDns64EngineOn => 'DNS64 合成中';

  @override
  String get desktopDns64EngineOff => '功能已停用';

  @override
  String get desktopDns64Description =>
      '当客户端位于纯 IPv6 网络并通过 NAT64 网关访问互联网时，若目标域名只有 IPv4（A）记录而没有原生 IPv6（AAAA）记录，DNS64 引擎会用指定前缀把 IPv4 地址合成映射为 AAAA 返回，让终端仍能端到端访问。';

  @override
  String get desktopDns64PrefixesCardTitle => '合成前缀';

  @override
  String get desktopDns64PrefixesLabel => '用于合成的 IPv6 前缀（每行一个）';

  @override
  String get desktopDns64PrefixesHelper =>
      '每行一个 IPv6 网段。支持 /32、/40、/48、/56、/64、/96；留空时服务使用知名公共前缀 64:ff9b::/96。';

  @override
  String get desktopDns64FillWellKnown => '填入标准前缀';

  @override
  String get desktopDns64NoteTitle => '智能保护机制';

  @override
  String get desktopDns64NoteBody =>
      '服务内置 RFC 6147 排除网段（回环、链路本地、IPv4-mapped 与自身前缀），避免回环与重复嵌套合成；目标已有原生 AAAA 时直接返回原生记录，不做额外合成。';

  @override
  String get desktopDns64Save => '保存 DNS64 配置';

  @override
  String get desktopDns64Saving => '保存中…';

  @override
  String get desktopDns64Saved => 'DNS64 过渡合成配置已更新';

  @override
  String get desktopDns64ToggleOn => 'DNS64 过渡合成已开启';

  @override
  String get desktopDns64ToggleOff => 'DNS64 过渡合成已关闭';

  @override
  String desktopDns64SaveFailed(String message) {
    return '更新 DNS64 配置失败：$message';
  }

  @override
  String get desktopDns64LoadFailed => '读不到 DNS64 配置';

  @override
  String get desktopHubFilterLists => '规则订阅';

  @override
  String get desktopHubFilterListsBody => '在线规则库与本地规则文件，按订阅批量生效';

  @override
  String get desktopFilterListsPageTitle => '规则订阅';

  @override
  String get desktopFilterListsRefresh => '刷新订阅状态';

  @override
  String get desktopFilterSummaryTitle => '规则拦截总览';

  @override
  String get desktopFilterEngineOn => '防护生效中';

  @override
  String get desktopFilterEngineOff => '防护已关闭';

  @override
  String get desktopFilterPausedChip => '已暂停';

  @override
  String get desktopFilterBlocked => '已拦截请求';

  @override
  String get desktopFilterTimes => '次';

  @override
  String get desktopFilterRulesUnit => '条';

  @override
  String get desktopFilterActiveLists => '已启用规则库';

  @override
  String get desktopFilterListsUnit => '个';

  @override
  String desktopFilterPausedRemaining(String remaining) {
    return '拦截已暂停，剩余 $remaining 后自动恢复';
  }

  @override
  String desktopFilterPauseDays(int days) {
    return '$days 天';
  }

  @override
  String desktopFilterPauseHours(int hours, int minutes) {
    return '$hours 小时 $minutes 分';
  }

  @override
  String desktopFilterPauseMinutes(int minutes, int seconds) {
    return '$minutes 分 $seconds 秒';
  }

  @override
  String desktopFilterPauseSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get desktopFilterListsTitle => '规则订阅库';

  @override
  String get desktopFilterListsBody =>
      '支持在线订阅链接与本地规则文本文件；每个规则库独立开关，全部更新会逐个重新拉取。';

  @override
  String desktopFilterListsCount(int count) {
    return '$count 个规则库';
  }

  @override
  String get desktopFilterListUpdateAll => '全部更新';

  @override
  String get desktopFilterListAdd => '添加规则库';

  @override
  String get desktopFilterListsEmpty => '暂无规则订阅库';

  @override
  String get desktopFilterListsEmptyBody =>
      '添加 AdGuard 语法规则链接或本地 Hosts 规则文件后，规则会随订阅自动下载并生效。';

  @override
  String desktopFilterListDefaultName(int index) {
    return '订阅列表 $index';
  }

  @override
  String get desktopFilterListAdded => '规则库已添加并开始下载';

  @override
  String get desktopFilterListAllUpdated => '全部规则库已更新完成';

  @override
  String get desktopFilterListUpdated => '规则库已更新';

  @override
  String desktopFilterActionFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String desktopFilterListToggleOn(String name) {
    return '已启用规则库：$name';
  }

  @override
  String desktopFilterListToggleOff(String name) {
    return '已停用规则库：$name';
  }

  @override
  String get desktopFilterListDeleteTitle => '删除规则库';

  @override
  String desktopFilterListDeleteBody(String name) {
    return '确定要删除规则库「$name」吗？删除后其包含的拦截规则将不再生效。';
  }

  @override
  String get desktopFilterListDeleteConfirm => '确定删除';

  @override
  String get desktopFilterListDeleted => '规则库已删除';

  @override
  String desktopFilterListRules(int count) {
    return '$count 条规则';
  }

  @override
  String get desktopFilterListEnabled => '规则拦截生效中';

  @override
  String get desktopFilterListDisabled => '已暂停拦截';

  @override
  String get desktopFilterListNeverUpdated => '最后更新：未更新';

  @override
  String desktopFilterListUpdatedAt(String time) {
    return '最后更新：$time';
  }

  @override
  String get desktopFilterListRefreshOne => '立即更新此规则库';

  @override
  String get desktopFilterListDelete => '删除此规则库';

  @override
  String get desktopFilterListHealthOk => '已同步';

  @override
  String get desktopFilterListHealthUnchanged => '未变更';

  @override
  String get desktopFilterListHealthCached => '沿用缓存';

  @override
  String get desktopFilterListHealthFailed => '更新失败';

  @override
  String get desktopFilterListHealthOkBody => '本次拉取获取到新内容并已生效';

  @override
  String get desktopFilterListHealthUnchangedBody => '服务端返回 304，本地副本仍然有效';

  @override
  String get desktopFilterListHealthCachedBody => '拉取失败，继续使用上次缓存内容';

  @override
  String get desktopFilterListHealthFailedBody => '拉取失败且无可用缓存';

  @override
  String get desktopFilterListAddTitle => '添加规则订阅库';

  @override
  String get desktopFilterListAddBody => '输入规则库的名称，以及在线订阅网址（URL）或本地文件路径。';

  @override
  String get desktopFilterListNameLabel => '规则库名称';

  @override
  String get desktopFilterListNameHint => '例如：广告拦截通用规则';

  @override
  String get desktopFilterListUrlLabel => '订阅链接 / 文件路径';

  @override
  String get desktopFilterListUrlHint => 'https://… 或本地文件路径';

  @override
  String get desktopFilterListAddConfirm => '添加并下载';

  @override
  String get desktopFilterListNeedUrl => '请输入有效的规则源 URL 或本地文件路径';

  @override
  String get desktopFilterListsLoadFailed => '读不到规则订阅库';

  @override
  String get desktopHubFilterRules => '自定义规则';

  @override
  String get desktopHubFilterRulesBody => '手写 AdGuard 语法规则，保存后立即热重载生效';

  @override
  String get desktopFilterRulesPageTitle => '自定义规则';

  @override
  String get desktopFilterRulesRefresh => '重新读取自定义规则';

  @override
  String get desktopFilterRulesEditorTitle => '自定义规则文本编辑器';

  @override
  String get desktopFilterRulesEditorBody => '编辑用户专属的过滤拦截或放行清单，每行一条';

  @override
  String get desktopFilterRulesSave => '保存规则';

  @override
  String get desktopFilterRulesSaving => '保存中…';

  @override
  String get desktopFilterRulesSaved => '自定义规则已保存生效';

  @override
  String desktopFilterRulesSaveFailed(String message) {
    return '保存自定义规则失败：$message';
  }

  @override
  String get desktopFilterRulesLoadFailed => '读不到自定义规则';

  @override
  String get desktopFilterRulesPlaceholder => '在此输入自定义拦截或信任规则，每行一条…';

  @override
  String desktopFilterRulesLineCount(int count) {
    return '行数统计：$count 条规则';
  }

  @override
  String get desktopFilterRulesHint => '每行一条规则，以 ! 开头的行为注释；修改后点击保存立即热重载生效。';

  @override
  String get desktopFilterGuideTitle => 'AdGuard 语法速查指南';

  @override
  String get desktopFilterGuideBody => '主流广告过滤与信任规则编写格式';

  @override
  String get desktopFilterGuideCommon => '常用格式';

  @override
  String get desktopFilterGuideExempt => '豁免放行';

  @override
  String get desktopFilterGuideCompat => '传统兼容';

  @override
  String get desktopFilterGuidePriority => '强制优先';

  @override
  String get desktopFilterGuideRewrite => '应答重写';

  @override
  String get desktopFilterGuideDomainTitle => '域名与子域名拦截';

  @override
  String get desktopFilterGuideDomainBody =>
      '匹配并拦截 example.com 及其所有子域名（如 ad.example.com）。';

  @override
  String get desktopFilterGuideAllowTitle => '白名单信任放行';

  @override
  String get desktopFilterGuideAllowBody => '即便其他规则命中，也始终允许解析 safe.com。';

  @override
  String get desktopFilterGuideHostsTitle => 'Hosts 文件格式';

  @override
  String get desktopFilterGuideHostsBody => '兼容标准 Hosts 文件屏蔽特定域名的语法。';

  @override
  String get desktopFilterGuideImportantTitle => '最高优先级强力拦截';

  @override
  String get desktopFilterGuideImportantBody => '忽略所有白名单规则，强制拦截该域名。';

  @override
  String get desktopFilterGuideRewriteTitle => '应答重写';

  @override
  String get desktopFilterGuideRewriteBody =>
      '无需上游应答，直接按规则给出结果：支持 IPv4/IPv6 地址、域名（CNAME）、NOERROR;A;1.2.3.4 这类显式写法，以及 REFUSED / NXDOMAIN 等应答码；显式写法还支持 MX、SRV、NS、PTR、TXT、HTTPS、SVCB。优先级高于一切拦截与放行规则，用 @@||nas.lan^\$dnsrewrite 可取消该域名的全部重写。';

  @override
  String get desktopFilterGuideFooter => '提示：每行一条规则，以 ! 开头的行为注释。';

  @override
  String get desktopHubFilterConfig => '拦截方式';

  @override
  String get desktopHubFilterConfigBody => '应答模式、阻断地址、更新周期、临时暂停与高级拦截';

  @override
  String get desktopFilterConfigPageTitle => '拦截方式';

  @override
  String get desktopFilterConfigRefresh => '刷新拦截配置';

  @override
  String get desktopFilterConfigLoadFailed => '读不到拦截配置';

  @override
  String desktopFilterConfigSaveFailed(String message) {
    return '保存拦截配置失败：$message';
  }

  @override
  String get desktopFilterEngineOnMessage => '规则拦截防护已开启';

  @override
  String get desktopFilterEngineOffMessage => '规则拦截防护已关闭';

  @override
  String get desktopFilterModeTitle => '拦截响应处理方式';

  @override
  String get desktopFilterModeBody => '命中拦截规则时向客户端返回的应答';

  @override
  String get desktopFilterModeSave => '保存策略与参数';

  @override
  String get desktopFilterModeSaving => '保存中…';

  @override
  String get desktopFilterModeSaved => '拦截策略配置已保存';

  @override
  String get desktopFilterModeParamsTitle => '规则自动更新与阻断地址';

  @override
  String get desktopFilterModeParamsBody => '被拦截域名得到的应答地址，以及规则列表的自动更新周期';

  @override
  String get desktopFilterModeBlockingIPv4 => '阻断 IPv4 响应地址';

  @override
  String get desktopFilterModeBlockingIPv6 => '阻断 IPv6 响应地址';

  @override
  String get desktopFilterModeInterval => '规则库同步周期（小时）';

  @override
  String get desktopFilterModeIntervalHelper => '默认 24 小时';

  @override
  String get desktopFilterModeInvalid => '同步周期需为正整数，阻断地址不能为空';

  @override
  String get desktopFilterModeNullIp => '立即返回空地址（0.0.0.0 / ::）';

  @override
  String get desktopFilterModeNullIpBody => '以极速终止广告和弹窗资源加载，不会引起浏览器反复重发请求。';

  @override
  String get desktopFilterModeNxdomain => '提示域名不存在（NXDOMAIN）';

  @override
  String get desktopFilterModeNxdomainBody => '告知客户端该网址不存在，部分标准网络软件将放弃进一步连接探测。';

  @override
  String get desktopFilterModeRefused => '明确拒绝请求（REFUSED）';

  @override
  String get desktopFilterModeRefusedBody => '向客户端返回拒绝码，表示请求被 DNS 防火墙安全策略主动阻止。';

  @override
  String get desktopFilterAdvancedTitle => '高级拦截能力';

  @override
  String get desktopFilterAdvancedBody => '针对绕过手法的增强拦截策略，默认关闭，按需开启';

  @override
  String get desktopFilterAdvancedResponseTitle => '响应侧别名链深度复检';

  @override
  String get desktopFilterAdvancedResponseBody =>
      '对上游应答中的 CNAME 目标与 A/AAAA 所属名二次匹配黑名单，拦截「查询域名合法但别名指向黑名单域」的深链绕过；缓存命中的应答同样复检。';

  @override
  String get desktopFilterAdvancedResponseOn => '响应侧别名链复检已开启';

  @override
  String get desktopFilterAdvancedResponseOff => '响应侧别名链复检已关闭';

  @override
  String get desktopFilterAdvancedAllowlistTitle => '仅白名单模式';

  @override
  String get desktopFilterAdvancedAllowlistBody =>
      '开启后仅命中放行规则（@@ 例外）的查询才被放行，其余一律阻断；本地 Hosts / 重写 / 内网域名等本地权威应答不受影响。';

  @override
  String get desktopFilterAdvancedAllowlistWarning =>
      '请先确保已配置充分的放行白名单，否则可能造成大面积域名解析失败。';

  @override
  String get desktopFilterAdvancedAllowlistOn => '仅白名单模式已开启';

  @override
  String get desktopFilterAdvancedAllowlistOff => '仅白名单模式已关闭';

  @override
  String get desktopFilterAdvancedBogusTitle => '伪应答纠正';

  @override
  String get desktopFilterAdvancedBogusBody =>
      '部分网络在域名不存在时返回固定的导航或广告页地址；开启后应答地址落在下方清单内即判定为上游劫持，就地改写为 NXDOMAIN。';

  @override
  String get desktopFilterAdvancedBogusOn => '伪应答纠正已开启';

  @override
  String get desktopFilterAdvancedBogusOff => '伪应答纠正已关闭';

  @override
  String get desktopFilterAdvancedBogusListLabel =>
      '劫持地址清单（一行一条，支持 IP 与 CIDR 网段）';

  @override
  String desktopFilterAdvancedBogusSuspicious(String entries) {
    return '以下条目格式可疑，保存时若无法解析将被服务忽略：$entries';
  }

  @override
  String get desktopFilterAdvancedBogusPresets => '快捷填入：';

  @override
  String get desktopFilterAdvancedBogusReset => '撤销修改';

  @override
  String get desktopFilterAdvancedBogusSave => '保存地址清单';

  @override
  String desktopFilterAdvancedBogusSaved(int count) {
    return '已保存 $count 条劫持地址';
  }

  @override
  String get desktopFilterAdvancedBogusCleared => '劫持地址清单已清空';

  @override
  String get desktopFilterPauseBody => '在指定时长内整体放行全部查询，到期自动恢复（重启服务亦恢复）。';

  @override
  String get desktopFilterPauseDuration => '暂停时长';

  @override
  String get desktopFilterPauseAction => '暂停';

  @override
  String get desktopFilterPauseResume => '立即恢复拦截';

  @override
  String get desktopFilterPauseStarted => '拦截已暂停';

  @override
  String get desktopFilterPauseResumed => '拦截已恢复';

  @override
  String get desktopFilterPauseActiveTitle => '拦截已暂停';

  @override
  String desktopFilterPauseActiveBody(String remaining) {
    return '剩余 $remaining 后自动恢复拦截';
  }

  @override
  String desktopFilterPauseMinutesOnly(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get desktopFilterPauseOneHour => '1 小时';

  @override
  String get desktopFilterPauseEightHours => '8 小时';

  @override
  String get desktopHubFilterSchedule => '时间计划';

  @override
  String get desktopHubFilterScheduleBody => '只在指定时段执行拦截，其余时间自动放行';

  @override
  String get desktopSchedulePageTitle => '时间计划';

  @override
  String get desktopScheduleRefresh => '刷新时间计划';

  @override
  String get desktopScheduleLoadFailed => '读不到时间计划';

  @override
  String get desktopScheduleTitle => '分时拦截 · 时间计划';

  @override
  String get desktopScheduleBody => '仅在指定时段内执行广告拦截，其余时间自动放行';

  @override
  String get desktopScheduleBadgeOff => '未启用 · 拦截常开';

  @override
  String get desktopScheduleBadgeActive => '拦截生效中';

  @override
  String get desktopScheduleBadgePaused => '计划暂停 · 放行全部';

  @override
  String get desktopScheduleEnable => '启用分时拦截';

  @override
  String get desktopScheduleEnableBody => '关闭时拦截始终生效；开启后仅在下列时间窗口内执行拦截。';

  @override
  String get desktopScheduleNoEnabled => '当前无已启用计划，拦截将保持常开。请至少启用一条计划以限制拦截时段。';

  @override
  String get desktopScheduleSave => '保存计划';

  @override
  String get desktopScheduleSaving => '保存中…';

  @override
  String get desktopScheduleSaved => '时间计划已保存并生效';

  @override
  String desktopScheduleSaveFailed(String message) {
    return '保存时间计划失败：$message';
  }

  @override
  String get desktopScheduleAdd => '新增时间计划';

  @override
  String get desktopScheduleName => '计划名称';

  @override
  String get desktopScheduleEnabled => '启用该计划';

  @override
  String get desktopScheduleStart => '生效开始时刻';

  @override
  String get desktopScheduleEnd => '生效结束时刻';

  @override
  String get desktopScheduleEndHelper => '早于开始即跨夜';

  @override
  String get desktopScheduleWeekdays => '生效星期';

  @override
  String get desktopScheduleEveryDay => '每天';

  @override
  String get desktopScheduleDelete => '删除该计划';

  @override
  String get desktopScheduleDeleteTitle => '删除时间计划';

  @override
  String get desktopScheduleDeleteBody => '确定要删除该时间计划吗？保存后不再生效。';

  @override
  String get desktopScheduleDeleteConfirm => '删除';

  @override
  String get desktopWeekdayMon => '一';

  @override
  String get desktopWeekdayTue => '二';

  @override
  String get desktopWeekdayWed => '三';

  @override
  String get desktopWeekdayThu => '四';

  @override
  String get desktopWeekdayFri => '五';

  @override
  String get desktopWeekdaySat => '六';

  @override
  String get desktopWeekdaySun => '日';

  @override
  String get desktopHubFilterServices => '应用拦截';

  @override
  String get desktopHubFilterServicesBody => '内置应用与网站规则，一键整组拦截，可按周计划放行';

  @override
  String get desktopServicesPageTitle => '应用拦截';

  @override
  String get desktopServicesRefresh => '刷新应用拦截';

  @override
  String get desktopServicesLoadFailed => '读不到内置服务目录';

  @override
  String get desktopServicesGroupsTitle => '整组拦截';

  @override
  String get desktopServicesGroupsBody => '一次性开关整组应用与网站，不必逐个点选';

  @override
  String get desktopServicesTitle => '应用与网站拦截';

  @override
  String get desktopServicesBody =>
      '一键拦截常见应用与网站，规则随程序内置、无需联网拉取；可与订阅规则、自定义规则叠加生效。';

  @override
  String desktopServicesCount(int blocked, int total) {
    return '$blocked / $total 项已拦截';
  }

  @override
  String get desktopServicesClearAll => '全部取消';

  @override
  String get desktopServicesCleared => '已取消全部应用拦截';

  @override
  String get desktopServicesSearchHint => '搜索应用名称、域名或规则…';

  @override
  String get desktopServicesGroupFilter => '分组筛选';

  @override
  String get desktopServicesAllGroups => '全部分组';

  @override
  String desktopServicesGroupItem(String name, int count) {
    return '$name ($count)';
  }

  @override
  String desktopServicesGroupChip(String name, int count) {
    return '$name · $count';
  }

  @override
  String desktopServicesActiveRules(int count) {
    return '展开 $count 条规则';
  }

  @override
  String get desktopServicesEmpty => '内置服务目录为空';

  @override
  String get desktopServicesNoMatch => '未找到符合条件的应用';

  @override
  String desktopServicesBlocked(String name) {
    return '已拦截：$name';
  }

  @override
  String desktopServicesUnblocked(String name) {
    return '已取消拦截：$name';
  }

  @override
  String desktopServicesActionFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String desktopServicesGroupOn(String name) {
    return '已整组拦截：$name';
  }

  @override
  String desktopServicesGroupOff(String name) {
    return '已取消整组拦截：$name';
  }

  @override
  String get desktopServicesByGroup => '随分组';

  @override
  String get desktopServicesScheduleInside => '计划内';

  @override
  String get desktopServicesScheduleOutside => '计划外';

  @override
  String desktopServicesRuleCount(String group, int count) {
    return '$group · $count 条规则';
  }

  @override
  String get desktopServicesScheduleEdit => '编辑每周生效计划';

  @override
  String get desktopServicesShowRules => '查看或收起规则';

  @override
  String desktopServicesScheduleTitle(String name) {
    return '$name 的每周生效计划';
  }

  @override
  String get desktopServicesScheduleBody =>
      '仅在命中的时间窗口内拦截该应用，其余时间正常放行。未配置任何计划时恒为拦截；需要某段时间完全不限制时，取消勾选该服务比清空计划更直观。';

  @override
  String get desktopServicesScheduleSave => '保存计划';

  @override
  String desktopServicesScheduleSaved(String name) {
    return '「$name」的每周生效计划已保存';
  }

  @override
  String desktopServicesScheduleRemoved(String name) {
    return '「$name」已恢复为始终拦截';
  }

  @override
  String get desktopHubPrivacy => '安全隐私';

  @override
  String get desktopHubPrivacyBody => '协议加固、ECS 子网隐私与内置重绑定 / hosts 防御';

  @override
  String get desktopPrivacyPageTitle => '安全隐私';

  @override
  String get desktopPrivacyRefresh => '刷新安全隐私配置';

  @override
  String get desktopPrivacyLoadFailed => '读不到安全隐私配置';

  @override
  String desktopPrivacySaveFailed(String message) {
    return '保存失败：$message';
  }

  @override
  String get desktopPrivacyProtocolTitle => '协议隐私与外泄防御';

  @override
  String get desktopPrivacyProtocolBody =>
      '阻断局域网私有 PTR 与单标签域名泄露，防御 ECH 加密绕过与报文侧信道嗅探';

  @override
  String get desktopPrivacyBlockTitle => '记录类型拦截';

  @override
  String get desktopPrivacyBlockBody => 'ECH、ANY 与 IPv6 查询的拦截策略，与协议加固分开设置';

  @override
  String get desktopPrivacyEdeTitle => 'Extended DNS Errors（EDE 错误诊断扩展）';

  @override
  String get desktopPrivacyEdeBody =>
      '向支持的客户端在 OPT 报文中透明返回 RFC 8914 扩展错误代码与原因说明（如策略阻断、速率超限、Rebind 拦截或上游解析故障）。';

  @override
  String get desktopPrivacyEdeOn => 'EDE 错误诊断已开启';

  @override
  String get desktopPrivacyEdeOff => 'EDE 错误诊断已关闭';

  @override
  String get desktopPrivacyPtrTitle => '私有反向 PTR 解析防泄露';

  @override
  String get desktopPrivacyPtrBody =>
      '阻断局域网私有 IP 的反向域名 PTR 查询向公共上游泄露；命中且未在本地绑定的反查直接返回权威 NXDOMAIN。';

  @override
  String get desktopPrivacyPtrOn => '私有 PTR 防泄露已开启';

  @override
  String get desktopPrivacyPtrOff => '私有 PTR 防泄露已关闭';

  @override
  String get desktopPrivacyUnqualifiedTitle => '阻止无点单标签域名外泄';

  @override
  String get desktopPrivacyUnqualifiedBody =>
      '拦截没有顶级域名点分隔的内部单标签请求（如 router、printer），防止拼写错误或搜索域缺失导致内网主机名泄漏至公共递归解析器。';

  @override
  String get desktopPrivacyUnqualifiedOn => '单标签域名防外泄已开启';

  @override
  String get desktopPrivacyUnqualifiedOff => '单标签域名防外泄已关闭';

  @override
  String get desktopPrivacyEchTitle => '剥离 ECH（加密 ClientHello）';

  @override
  String get desktopPrivacyEchBody =>
      '从上游 HTTPS / SVCB 资源记录中过滤剥离 ech 参数，防止客户端用 TLS 1.3 ECH 隐藏真实域名而绕过本地审计。';

  @override
  String get desktopPrivacyEchOn => 'ECH 剥离已开启';

  @override
  String get desktopPrivacyEchOff => 'ECH 剥离已关闭';

  @override
  String get desktopPrivacyAnyTitle => 'ANY 查询最小化';

  @override
  String get desktopPrivacyAnyBody =>
      'ANY 查询常被用于 DNS 放大攻击，也会让按记录类型下发的拦截失效；开启后本机不再转发 ANY，而是直接给出最小化应答。';

  @override
  String get desktopPrivacyAnyOn => 'ANY 查询最小化已开启';

  @override
  String get desktopPrivacyAnyOff => 'ANY 查询最小化已关闭';

  @override
  String get desktopPrivacyAnyModeLabel => '应答形式';

  @override
  String get desktopPrivacyAnyModeNotimp => 'NOTIMP（推荐）';

  @override
  String get desktopPrivacyAnyModeNotimpBody =>
      '明确回应「不支持该查询」，客户端不会把它误当成一次有效解析。';

  @override
  String get desktopPrivacyAnyModeRfc => 'RFC 8482 最小应答';

  @override
  String get desktopPrivacyAnyModeRfcBody =>
      '返回 NOERROR + 一条 HINFO(\"RFC8482\")，语义更准确，但需要客户端理解这一约定。';

  @override
  String get desktopPrivacyAnyModeSaved => 'ANY 最小化应答形式已保存';

  @override
  String get desktopPrivacyIpv6Title => '过滤 IPv6（AAAA）查询';

  @override
  String get desktopPrivacyIpv6Body =>
      '对所有 AAAA 查询秒级应答权威 NODATA，并在 HTTPS 查询中过滤 ipv6hint；在 IPv6 不佳的网络里消除双栈重试导致的卡顿。';

  @override
  String get desktopPrivacyIpv6On => 'IPv6 过滤已开启';

  @override
  String get desktopPrivacyIpv6Off => 'IPv6 过滤已关闭';

  @override
  String get desktopPrivacyPaddingTitle => 'EDNS0 报文填充大小';

  @override
  String get desktopPrivacyPaddingBody => '对加密 DNS 填充至固定块，防范报文长度指纹侧信道分析。';

  @override
  String desktopPrivacyPaddingValue(int size) {
    return '$size 字节';
  }

  @override
  String get desktopPrivacyPaddingSaved => 'EDNS0 填充大小已保存';

  @override
  String get desktopPrivacyEcsTitle => 'EDNS Client Subnet（ECS 策略）';

  @override
  String get desktopPrivacyEcsBody =>
      'ECS 允许向递归解析器携带客户端所在子网以优化 CDN 调度，但未经处理的原生 ECS 会向上游泄露家庭或企业内网真实网段。';

  @override
  String get desktopPrivacyEcsOn => 'ECS 策略已生效';

  @override
  String get desktopPrivacyEcsOff => '策略已停用';

  @override
  String get desktopPrivacyEcsOnMessage => 'ECS 策略已开启';

  @override
  String get desktopPrivacyEcsOffMessage => 'ECS 策略已关闭';

  @override
  String get desktopPrivacyEcsStripTitle => '剥离请求中的真实客户端子网';

  @override
  String get desktopPrivacyEcsStripBody =>
      '开启后转发查询时主动抹除客户端发送的真实出口子网信息，保障家庭或内网各设备的网络隐私。';

  @override
  String get desktopPrivacyEcsStripOn => '真实客户端子网剥离已开启';

  @override
  String get desktopPrivacyEcsStripOff => '真实客户端子网剥离已关闭';

  @override
  String get desktopPrivacyEcsSubnetLabel => '自定义转发子网（CIDR）';

  @override
  String get desktopPrivacyEcsSubnetHelper =>
      '可选。填写公共出口网段向权威 DNS 伪装位置以保持 CDN 调度，留空则完全保密。';

  @override
  String get desktopPrivacyEcsSave => '保存 ECS 策略';

  @override
  String get desktopPrivacyEcsSaved => 'EDNS Client Subnet 客户端子网策略已更新';

  @override
  String get desktopPrivacyDefenceTitle => '内置安全防御模块';

  @override
  String get desktopPrivacyDefenceBody => '重绑定防御与本地 Hosts 解析的运行状态与配置';

  @override
  String get desktopPrivacyRebindTitle => 'DNS 重绑定防御';

  @override
  String get desktopPrivacyRebindBody =>
      '阻断外网域名解析为私有 IP，防止攻击者用 DNS 重绑定访问局域网设备。';

  @override
  String get desktopPrivacyRebindOn => 'DNS 重绑定防御已开启';

  @override
  String get desktopPrivacyRebindOff => 'DNS 重绑定防御已关闭';

  @override
  String desktopPrivacyRebindCount(int count) {
    return '$count 个白名单域名';
  }

  @override
  String get desktopPrivacyRebindAllowlist => '白名单设置';

  @override
  String get desktopPrivacyRebindDialogTitle => 'DNS 重绑定防御白名单域名';

  @override
  String get desktopPrivacyRebindDialogBody =>
      '名单内的域名允许解析为局域网私有 IP（如 192.168.x.x、10.x.x.x、127.0.0.1），支持后缀通配（如 .lan、.local）。每行一个。';

  @override
  String get desktopPrivacyRebindDialogSave => '保存白名单';

  @override
  String get desktopPrivacyRebindSaved => 'DNS 重绑定防御白名单已保存';

  @override
  String get desktopPrivacyHostsTitle => '本地 Hosts 解析器';

  @override
  String get desktopPrivacyHostsBody => '系统与自定义 hosts 映射优先应答，命中后不再向上游查询。';

  @override
  String get desktopPrivacyHostsOn => '本地 Hosts 解析已开启';

  @override
  String get desktopPrivacyHostsOff => '本地 Hosts 解析已关闭';

  @override
  String get desktopPrivacyHostsSystem => '联动系统 hosts 文件';

  @override
  String desktopPrivacyHostsTtl(int seconds) {
    return 'TTL ${seconds}s';
  }

  @override
  String get desktopPrivacyHostsSystemOn => '已联动系统 hosts';

  @override
  String get desktopPrivacyHostsSystemOff => '已停止联动系统 hosts';

  @override
  String get desktopHubPrivacySection => '隐私与加密';

  @override
  String get desktopHubShareSection => '网络共享';

  @override
  String get desktopSafeSearchTitle => '强制安全搜索';

  @override
  String get desktopSafeSearchBody =>
      '把主流搜索引擎重写为强制过滤入口，从 DNS 层确保无法关闭安全搜索。属新增拦截能力，默认关闭。';

  @override
  String desktopSafeSearchEnabled(int count) {
    return '已生效 · $count 家';
  }

  @override
  String get desktopSafeSearchOff => '未启用';

  @override
  String get desktopSafeSearchOn => '强制安全搜索已开启';

  @override
  String get desktopSafeSearchOffMessage => '强制安全搜索已关闭';

  @override
  String get desktopSafeSearchServiceSaved => '安全搜索服务商已更新';

  @override
  String get desktopSafeSearchTtl => '重写应答 TTL（秒）';

  @override
  String get desktopSafeSearchTtlSave => '保存';

  @override
  String get desktopSafeSearchTtlSaved => '安全搜索应答 TTL 已保存';

  @override
  String get desktopSafeSearchTtlInvalid => 'TTL 需为正整数';

  @override
  String get desktopSafeSearchFooter => '未勾选的服务商将直接透传正常解析。';

  @override
  String get desktopSafeSearchTtlCardTitle => '安全搜索改写有效期';

  @override
  String get desktopSafeSearchTtlCardBody => '强制安全搜索的改写记录在本地保留多久，到期后重新向上游确认。';

  @override
  String desktopSafeSearchTtlChip(int seconds) {
    return '当前 ${seconds}s';
  }

  @override
  String get desktopSafeSearchBing => 'Bing';

  @override
  String get desktopSafeSearchDuckDuckGo => 'DuckDuckGo';

  @override
  String get desktopSafeSearchEcosia => 'Ecosia';

  @override
  String get desktopSafeSearchGoogle => 'Google';

  @override
  String get desktopSafeSearchPixabay => 'Pixabay';

  @override
  String get desktopSafeSearchYandex => 'Yandex';

  @override
  String get desktopSafeSearchYoutube => 'YouTube';

  @override
  String get desktopReputationTitle => '恶意网址库（Safe Browsing）';

  @override
  String get desktopReputationOn => '查询中';

  @override
  String get desktopReputationOff => '未启用';

  @override
  String get desktopReputationOnMessage => '恶意网址库查询已开启';

  @override
  String get desktopReputationOffMessage => '恶意网址库查询已关闭';

  @override
  String get desktopReputationBody =>
      '查询时只把域名的 SHA-256 前 2 字节发往第三方哈希前缀服务，对方返回命中的完整摘要，本地再比对；第三方无法从这 2 个字节还原完整域名。查询失败一律放行。';

  @override
  String get desktopReputationLookups => '查询次数';

  @override
  String get desktopReputationBlocked => '命中拦截';

  @override
  String get desktopReputationHitRate => '缓存命中率';

  @override
  String get desktopReputationFailures => '查询失败';

  @override
  String get desktopReputationAnswer => '拦截方式';

  @override
  String get desktopReputationAnswerNullIp => '空地址';

  @override
  String get desktopReputationTimeout => '查询超时（毫秒）';

  @override
  String get desktopReputationCacheSize => '缓存条目上限';

  @override
  String get desktopReputationCacheTtl => '缓存有效期（秒）';

  @override
  String get desktopReputationParamsTitle => '查询参数';

  @override
  String get desktopReputationParamsInvalid => '超时与缓存有效期需为正整数，缓存条目不能为负';

  @override
  String get desktopReputationParamsSave => '保存查询参数';

  @override
  String get desktopReputationParamsSaved => '查询参数已保存';

  @override
  String get desktopReputationFooter => '缓存按 2 字节前缀索引，同一前缀下的域名共享一次查询。';

  @override
  String get desktopParentalTitle => '家长控制';

  @override
  String get desktopParentalBody =>
      '与恶意网址库机制相同，借第三方分类库拦截成人内容域名；两者各自独立开关，可只开家长控制。';

  @override
  String get desktopParentalWarning =>
      '恶意网址库当前未开启。两者互不依赖，但钓鱼与恶意软件站点不在家长控制的分类范围内。';

  @override
  String get desktopParentalOn => '家长控制已开启';

  @override
  String get desktopParentalOff => '家长控制已关闭';

  @override
  String get desktopHubEncrypted => '加密 DNS 服务';

  @override
  String get desktopHubEncryptedBody => '以 DoT / DoH / DoQ 向局域网提供加密解析，含证书与 DDR';

  @override
  String get desktopEncryptedPageTitle => '加密 DNS 服务';

  @override
  String get desktopEncryptedRefresh => '刷新加密 DNS 状态';

  @override
  String get desktopEncryptedLoadFailed => '读不到加密 DNS 服务状态';

  @override
  String desktopEncryptedSaveFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String get desktopEncryptedListenersTitle => '加密 DNS 服务';

  @override
  String get desktopEncryptedListenersBody =>
      '在局域网内以 DoT / DoH / DoQ 提供解析，终端无需明文查询';

  @override
  String get desktopEncryptedEnabled => '已启用';

  @override
  String get desktopEncryptedDisabled => '未启用';

  @override
  String get desktopEncryptedOn => '加密 DNS 服务已开启';

  @override
  String get desktopEncryptedOff => '加密 DNS 服务已关闭';

  @override
  String get desktopEncryptedNoProtocol => '服务总开关已打开，但三种协议都没选中，因此不会有任何监听。';

  @override
  String get desktopEncryptedDot => 'DoT · DNS over TLS';

  @override
  String desktopEncryptedDotBody(int port) {
    return '端口 $port，客户端用 tls:// 连接';
  }

  @override
  String get desktopEncryptedDoh => 'DoH · DNS over HTTPS';

  @override
  String desktopEncryptedDohBody(int port, String path) {
    return '端口 $port，路径 $path';
  }

  @override
  String get desktopEncryptedDoq => 'DoQ · DNS over QUIC';

  @override
  String desktopEncryptedDoqBody(int port) {
    return '端口 $port，UDP 上的加密解析';
  }

  @override
  String desktopEncryptedListening(String address) {
    return '正在监听 $address';
  }

  @override
  String get desktopEncryptedNotListening => '未在监听（服务未启动、证书不可用或端口被占用）';

  @override
  String get desktopEncryptedDotOn => 'DoT 已启用';

  @override
  String get desktopEncryptedDotOff => 'DoT 已停用';

  @override
  String get desktopEncryptedDohOn => 'DoH 已启用';

  @override
  String get desktopEncryptedDohOff => 'DoH 已停用';

  @override
  String get desktopEncryptedDoqOn => 'DoQ 已启用';

  @override
  String get desktopEncryptedDoqOff => 'DoQ 已停用';

  @override
  String get desktopEncryptedUrls => '客户端填写以下任一地址即可使用：';

  @override
  String get desktopEncryptedNetworkTitle => '监听参数';

  @override
  String get desktopEncryptedListenAddress => '监听地址';

  @override
  String get desktopEncryptedListenHint => '留空表示全部网卡';

  @override
  String get desktopEncryptedServerName => '服务器名（客户端连接用）';

  @override
  String get desktopEncryptedDotPort => 'DoT 端口';

  @override
  String get desktopEncryptedDohPort => 'DoH 端口';

  @override
  String get desktopEncryptedDoqPort => 'DoQ 端口';

  @override
  String get desktopEncryptedDohPath => 'DoH 路径';

  @override
  String get desktopEncryptedServerNameHint =>
      '服务器名会被写进证书的 SAN，终端按它连接才不会报证书错误。';

  @override
  String get desktopEncryptedPortInvalid => '端口需为 1–65535 的整数';

  @override
  String get desktopEncryptedReset => '恢复默认';

  @override
  String get desktopEncryptedSaveNetwork => '保存';

  @override
  String get desktopEncryptedNetworkSaved => '监听参数已保存';

  @override
  String get desktopEncryptedCertTitle => '服务端证书';

  @override
  String get desktopEncryptedCertBody => '服务端 TLS 证书的摘要；私钥不会离开本机';

  @override
  String get desktopEncryptedCertSelfSigned => '自签证书';

  @override
  String get desktopEncryptedCertLoaded => '已载入';

  @override
  String get desktopEncryptedCertMissing => '未载入';

  @override
  String get desktopEncryptedCertExpired =>
      '服务端证书已过期：客户端 TLS 握手会全部失败。请立即重新签发或导入有效证书。';

  @override
  String get desktopEncryptedCertExpiresSoon =>
      '服务端自签证书将在 30 天内到期。到期后所有加密查询都会握手失败，建议尽早重新签发。';

  @override
  String get desktopEncryptedCertMissingBody => '尚未配置可用证书，加密监听无法启动。';

  @override
  String get desktopEncryptedCertSubject => '主体';

  @override
  String get desktopEncryptedCertIssuer => '签发者';

  @override
  String get desktopEncryptedCertNotAfter => '有效期至';

  @override
  String get desktopEncryptedCertDays => '剩余天数';

  @override
  String desktopEncryptedCertDaysValue(int days) {
    return '$days 天';
  }

  @override
  String get desktopEncryptedCertDns => '覆盖域名';

  @override
  String get desktopEncryptedCertIps => '覆盖 IP';

  @override
  String desktopEncryptedCertFingerprint(String fingerprint) {
    return 'SHA-256：$fingerprint';
  }

  @override
  String desktopEncryptedCertDir(String dir) {
    return '证书目录：$dir';
  }

  @override
  String get desktopEncryptedCertGenerate => '重新签发';

  @override
  String get desktopEncryptedCertImport => '导入 PEM';

  @override
  String get desktopEncryptedCertGenerated => '证书已生成';

  @override
  String get desktopEncryptedCertImported => '证书已导入';

  @override
  String get desktopEncryptedCertGenerateTitle => '生成自签证书';

  @override
  String get desktopEncryptedCertGenerateBody => '覆盖性动作：已信任旧证书的客户端将全部失效。';

  @override
  String get desktopEncryptedCertKeyType => '密钥类型';

  @override
  String get desktopEncryptedCertCommonName => '通用名（CN）';

  @override
  String get desktopEncryptedCertDnsNames => 'SAN 域名（每行一个）';

  @override
  String get desktopEncryptedCertIpAddresses => 'SAN IP（每行一个）';

  @override
  String get desktopEncryptedCertValidDays => '有效期（天）';

  @override
  String get desktopEncryptedCertGenerateConfirm => '生成';

  @override
  String get desktopEncryptedCertImportTitle => '导入 PEM 证书';

  @override
  String get desktopEncryptedCertImportBody => '粘贴证书链与私钥 PEM 文本，两者必须匹配。';

  @override
  String get desktopEncryptedCertPem => '证书链 PEM';

  @override
  String get desktopEncryptedKeyPem => '私钥 PEM';

  @override
  String get desktopEncryptedCertImportConfirm => '导入';

  @override
  String get desktopEncryptedCertImportInvalid => '证书与私钥都不能为空';

  @override
  String get desktopEncryptedExtrasTitle => '发现与代理';

  @override
  String get desktopEncryptedExtrasBody => '客户端自动发现、反向代理信任与移动端描述文件';

  @override
  String get desktopEncryptedDdrTitle => '指定解析器发现（DDR）';

  @override
  String get desktopEncryptedDdrBody =>
      '应答 _dns.resolver.arpa 探测，让终端自动发现本机的加密解析入口。';

  @override
  String get desktopEncryptedDdrSelfSignedWarning =>
      '当前是自签证书：终端若未预先信任它，开启 DDR 会直接失去 DNS 解析。';

  @override
  String get desktopEncryptedDdrConfirmTitle => '确认开启 DDR？';

  @override
  String get desktopEncryptedDdrConfirmBody =>
      'DDR 会让客户端自动切换解析入口；证书不被信任时，这一步等于让客户端失去 DNS。';

  @override
  String get desktopEncryptedDdrConfirm => '仍要开启';

  @override
  String get desktopEncryptedDdrOn => 'DDR 已开启';

  @override
  String get desktopEncryptedDdrOff => 'DDR 已关闭';

  @override
  String get desktopEncryptedProxyTitle => '反向代理透传';

  @override
  String get desktopEncryptedProxyBody =>
      '仅当 DoH 确实位于自己掌握的反向代理之后才开启；开启后会采信转发头。';

  @override
  String get desktopEncryptedProxyUnrestricted =>
      '可信来源包含 0.0.0.0/0 或 ::/0：任何人都能伪造来源地址。';

  @override
  String get desktopEncryptedProxyOn => '反向代理透传已开启';

  @override
  String get desktopEncryptedProxyOff => '反向代理透传已关闭';

  @override
  String get desktopEncryptedProxySources => '可信代理来源（每行一个 IP 或 CIDR）';

  @override
  String get desktopEncryptedProxyHeader =>
      '自定义转发头（留空则依次尝试 X-Forwarded-For 与 X-Real-IP）';

  @override
  String get desktopEncryptedProxySave => '保存代理配置';

  @override
  String get desktopEncryptedProxySaved => '反向代理配置已保存';

  @override
  String get desktopEncryptedMobileConfigTitle => '移动端描述文件';

  @override
  String get desktopEncryptedMobileConfigBody =>
      '在设备上打开该链接即可安装包含本机加密 DNS 的描述文件。';

  @override
  String get desktopEncryptedMobileConfigOpen => '打开描述文件';

  @override
  String get desktopEncryptedOpenUrl => '在浏览器中打开';

  @override
  String get desktopTrafficPageTitle => '设备与客户端';

  @override
  String get desktopTrafficRefresh => '刷新设备与访问控制';

  @override
  String get desktopTrafficLoadFailed => '读不到设备与访问控制状态';

  @override
  String desktopTrafficSaveFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String get desktopTrafficClientsTitle => '已识别的局域网客户端';

  @override
  String get desktopTrafficClientsBody => '通过 rDNS 或自定义别名识别发起查询的设备';

  @override
  String desktopTrafficClientCount(int count) {
    return '$count 个活跃设备';
  }

  @override
  String get desktopTrafficClientsEmpty => '暂未识别到来自外部或局域网的 DNS 查询设备。';

  @override
  String get desktopTrafficClientUnnamed => '未设置（未知设备）';

  @override
  String desktopTrafficClientQueries(int count) {
    return '累计查询 $count 次';
  }

  @override
  String get desktopTrafficClientNever => '最近活跃：从未';

  @override
  String desktopTrafficClientLastSeen(String time) {
    return '最近活跃 $time';
  }

  @override
  String get desktopTrafficStateBlocked => '已阻断';

  @override
  String get desktopTrafficStateAllowed => '白名单';

  @override
  String get desktopTrafficStateNotAllowed => '未在白名单';

  @override
  String get desktopTrafficStateOpen => '正常放行';

  @override
  String get desktopTrafficAlias => '别名';

  @override
  String get desktopTrafficAliasTitle => '配置客户端设备别名';

  @override
  String get desktopTrafficAliasField => '自定义友好设备名称';

  @override
  String get desktopTrafficAliasHint => '如 客厅电视、工作用笔记本、NAS 存储';

  @override
  String get desktopTrafficAliasBody => '留空保存将清除自定义别名。';

  @override
  String get desktopTrafficAliasSave => '保存别名';

  @override
  String desktopTrafficAliasSaved(String ip) {
    return '客户端 [$ip] 别名已更新';
  }

  @override
  String desktopTrafficAliasCleared(String ip) {
    return '客户端 [$ip] 别名已清除';
  }

  @override
  String get desktopTrafficAllowedAdd => '白名单';

  @override
  String get desktopTrafficAllowedRemove => '已放行';

  @override
  String desktopTrafficAllowedAdded(String ip) {
    return '客户端 [$ip] 已加入白名单';
  }

  @override
  String desktopTrafficAllowedRemoved(String ip) {
    return '客户端 [$ip] 已移出白名单';
  }

  @override
  String get desktopTrafficBlockedAdd => '阻断';

  @override
  String get desktopTrafficBlockedRemove => '已阻断';

  @override
  String desktopTrafficBlockedAdded(String ip) {
    return '客户端 [$ip] 已加入黑名单阻断';
  }

  @override
  String desktopTrafficBlockedRemoved(String ip) {
    return '客户端 [$ip] 已移出黑名单';
  }

  @override
  String get desktopTrafficAccessTitle => '客户端访问控制（ACL）';

  @override
  String get desktopTrafficAccessBody => '限制特定 IP 或 CIDR 网段设备的 DNS 查询权限';

  @override
  String get desktopTrafficAccessOpen => '未限制';

  @override
  String get desktopTrafficAccessAllowOnly => '仅白名单';

  @override
  String get desktopTrafficAccessAllowed => '允许访问白名单';

  @override
  String get desktopTrafficAccessAllowedHint =>
      '例如: 192.168.1.0/24 或 192.168.1.50';

  @override
  String get desktopTrafficAccessAllowedBody =>
      '若填写，则仅允许名单内的客户端解析；留空表示不限制。每行一个 IP 或 CIDR。';

  @override
  String get desktopTrafficAccessBlocked => '显式阻断黑名单';

  @override
  String get desktopTrafficAccessBlockedHint =>
      '例如: 192.168.1.199 或 10.0.0.0/8';

  @override
  String get desktopTrafficAccessBlockedBody =>
      '命中该名单的客户端将被直接拒绝解析请求。每行一个 IP 或 CIDR。';

  @override
  String get desktopTrafficAccessSave => '保存名单';

  @override
  String get desktopTrafficAccessReset => '撤销修改';

  @override
  String get desktopTrafficAccessSaved => '客户端黑白名单已保存';

  @override
  String get desktopTrafficRateLimitTitle => '客户端请求速率限制';

  @override
  String get desktopTrafficRateLimitBody => '基于令牌桶限流，防范局域网 DoS 泛洪与 DNS 放大攻击';

  @override
  String get desktopTrafficRateLimitOn => '限流生效中';

  @override
  String get desktopTrafficRateLimitOff => '限流已停用';

  @override
  String get desktopTrafficRateLimitSavedOn => '速率限制已开启';

  @override
  String get desktopTrafficRateLimitSavedOff => '速率限制已关闭';

  @override
  String get desktopTrafficRate => '速率（令牌/秒）';

  @override
  String get desktopTrafficBurst => '突发容量（次）';

  @override
  String get desktopTrafficIpv4Prefix => 'IPv4 聚合掩码';

  @override
  String get desktopTrafficIpv6Prefix => 'IPv6 聚合掩码';

  @override
  String get desktopTrafficPrefixBody => '单 IP 为 32 / 128；局域网可按需聚合，如 24 / 64。';

  @override
  String get desktopTrafficExempt => '豁免 IP / 网段';

  @override
  String get desktopTrafficExemptBody => '回环与受信任网段不计入限流统计。';

  @override
  String get desktopTrafficRateLimitSave => '保存速率限制';

  @override
  String get desktopTrafficRateInvalid =>
      '速率与突发需大于 0，掩码需在 1–32（IPv4）与 1–128（IPv6）之间';

  @override
  String get desktopGroupsPageTitle => '客户端分组';

  @override
  String get desktopGroupsRefresh => '刷新客户端分组';

  @override
  String get desktopGroupsLoadFailed => '读不到客户端分组配置';

  @override
  String get desktopGroupsTitle => '客户端分组 · 精细策略';

  @override
  String get desktopGroupsBody => '为不同设备组绑定专属订阅规则集与拦截方式，实现精细化管控';

  @override
  String desktopGroupsCount(int enabled, int total) {
    return '$enabled / $total 个启用分组';
  }

  @override
  String get desktopGroupsOn => '分组生效中';

  @override
  String get desktopGroupsOff => '分组未启用';

  @override
  String get desktopGroupsSave => '保存策略';

  @override
  String get desktopGroupsSaved => '客户端分组策略已保存并生效';

  @override
  String get desktopGroupsMaster => '启用客户端分组';

  @override
  String get desktopGroupsMasterBody => '关闭时所有客户端统一使用全局规则；开启后按网段最长前缀匹配分组。';

  @override
  String get desktopGroupsAdd => '新增客户端分组';

  @override
  String get desktopGroupsEmpty => '尚未配置任何分组。未命中分组的客户端将统一使用全局规则（默认组）。';

  @override
  String get desktopGroupsFooter => '采用最长前缀匹配：更具体的网段（如 /24）优先于更宽泛的网段（如 /16）。';

  @override
  String get desktopGroupsOpen => '客户端分组';

  @override
  String get desktopGroupsName => '分组名称';

  @override
  String get desktopGroupsEnabled => '启用该分组';

  @override
  String get desktopGroupsDelete => '删除该分组';

  @override
  String get desktopGroupsDeleteTitle => '删除客户端分组';

  @override
  String get desktopGroupsDeleteBody => '确定要删除该客户端分组吗？保存后不再生效。';

  @override
  String get desktopGroupsMembers => '成员 IP / 网段';

  @override
  String get desktopGroupsMembersHint =>
      '例如:\n192.168.1.0/24\n10.0.0.7\nfd00::/8';

  @override
  String get desktopGroupsMembersBody => '每行一个 IP 或 CIDR，支持 IPv4/IPv6。';

  @override
  String get desktopGroupsBlockMode => '拦截应答方式';

  @override
  String get desktopGroupsModeInherit => '继承全局';

  @override
  String get desktopGroupsModeNullIp => '空 IP（0.0.0.0 / ::）';

  @override
  String get desktopGroupsModeNxdomain => 'NXDOMAIN（域名不存在）';

  @override
  String get desktopGroupsModeRefused => 'REFUSED（拒绝应答）';

  @override
  String get desktopGroupsAllowlistOnly => '仅白名单模式';

  @override
  String get desktopGroupsAllowlistOnlyBody => '开启后该组仅放行命中放行规则（@@）的查询，其余一律阻断';

  @override
  String get desktopGroupsSchedule => '组级时间计划';

  @override
  String get desktopGroupsScheduleBody => '开启后该组按自身窗口拦截；关闭则继承全局时间计划';

  @override
  String get desktopGroupsRuleLists => '绑定的订阅规则集';

  @override
  String get desktopGroupsInheritAll => '继承全部';

  @override
  String get desktopGroupsNoRuleLists => '当前无可用订阅列表，该组将仅应用自定义规则。';

  @override
  String get desktopGroupsRuleListsInherited => '未勾选任何列表 → 继承全部订阅规则。';

  @override
  String get desktopGroupsRuleListsSelected => '该组只应用所选订阅列表。';

  @override
  String get desktopGroupsUpstreams => '专属上游 DNS';

  @override
  String get desktopGroupsInheritChain => '沿用主链路';

  @override
  String get desktopGroupsNoUpstreams => '当前无可选上游，该组将沿用主链路。';

  @override
  String get desktopGroupsUpstreamsInherited => '未勾选任何上游 → 沿用主链路调度策略。';

  @override
  String get desktopGroupsUpstreamsSelected => '该组的查询直接由所选上游解析，不参与全局回退链。';

  @override
  String desktopGroupsNewName(int index) {
    return '新分组 $index';
  }

  @override
  String get desktopGroupsListEnabled => '该订阅已启用';

  @override
  String get desktopGroupsListDisabled => '该订阅已停用';

  @override
  String get desktopToolsPortTitle => '网络诊断与修复';

  @override
  String get desktopToolsPortBody =>
      '排查 53 端口被 ICS 共享或 systemd-resolved stub 占用导致无法启动的问题';

  @override
  String get desktopToolsPortIdle => '尚未检测。点本卡片右上角的检索按钮运行一次端口探测。';

  @override
  String get desktopToolsPortOk => '端口正常可用';

  @override
  String get desktopToolsPortConflict => '检测到端口冲突';

  @override
  String get desktopToolsCheck => '检测端口';

  @override
  String get desktopToolsFix => '一键修复端口占用';

  @override
  String get desktopToolsFixTitle => '修复端口占用？';

  @override
  String get desktopToolsFixBody =>
      '将停止占用 53 端口的系统监听（Windows ICS 共享 / systemd-resolved stub），不会启动或重启 DNS 服务。';

  @override
  String get desktopToolsFixed => '端口冲突已修复';

  @override
  String desktopToolsFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String get desktopToolsSystemListener => '系统占用';

  @override
  String get desktopToolsSelfListener => '谛听自身';

  @override
  String desktopToolsConflictOwner(String process, int pid, String address) {
    return '$process · PID $pid · $address';
  }

  @override
  String desktopToolsConflictService(String service) {
    return '服务：$service';
  }

  @override
  String get desktopToolsPortFooter => '探测只临时占用端口以确认可用性；诊断文本与处置建议来自系统探测本身。';

  @override
  String get desktopToolsRulePageTitle => '规则检测';

  @override
  String get desktopHubDiagnoseSection => '诊断与恢复';

  @override
  String get desktopToolsRuleEntryBody => '模拟一次查询，查看命中规则与处置结论';

  @override
  String get desktopHubQueryLog => '查询日志';

  @override
  String get desktopHubQueryLogBody => '实时查询流、历史记录检索与日志保留策略';

  @override
  String get desktopQueryLogPageTitle => '查询日志';

  @override
  String get desktopToolsRuleInputTitle => '网址拦截模拟测试';

  @override
  String get desktopToolsRuleInputBody => '输入域名快速检测是否命中过滤拦截规则';

  @override
  String get desktopToolsRuleDomain => '测试目标域名';

  @override
  String get desktopToolsRuleDomainHint =>
      '例如: ad.example.com 或 tracker.domain.com';

  @override
  String get desktopToolsRuleQtype => 'DNS 记录类型';

  @override
  String desktopToolsRuleQtypeOption(String type) {
    return '$type 记录';
  }

  @override
  String get desktopToolsRuleExamples => '快速填充示例：';

  @override
  String get desktopToolsRuleRun => '立即模拟检测';

  @override
  String get desktopToolsRuleRunning => '正在执行规则匹配…';

  @override
  String get desktopToolsRuleVerdictTitle => '规则诊断与拦截判定';

  @override
  String get desktopToolsRuleVerdictBody => '规则匹配结果、所属规则库与响应动作';

  @override
  String get desktopToolsRuleIdle => '在上方输入域名并点击「立即模拟检测」以查看规则判定明细';

  @override
  String get desktopToolsRuleBlocked => '已拦截（阻断访问）';

  @override
  String desktopToolsRuleRewritten(String code) {
    return '已重写（$code）';
  }

  @override
  String get desktopToolsRuleAllowed => '已放行（信任名单）';

  @override
  String get desktopToolsRulePassed => '未命中（正常解析）';

  @override
  String get desktopToolsRuleMatched => '命中的防护规则';

  @override
  String get desktopToolsRuleNoMatch => '未命中任何规则';

  @override
  String get desktopToolsRuleList => '来源规则库';

  @override
  String get desktopToolsRuleNoList => '无';

  @override
  String get desktopToolsRuleReason => '处置判定原因';

  @override
  String get desktopToolsRuleNoReason => '正常直连解析';

  @override
  String desktopToolsRuleRewrite(String code) {
    return '\$dnsrewrite 应答：$code';
  }

  @override
  String get desktopToolsRuleRewriteEmpty => '不返回任何记录（权威 NODATA）';

  @override
  String get desktopToolsRuleFooter => '支持 AdGuard、Hosts 及自定义规则即时模拟测试。';

  @override
  String desktopToolsRuleFailed(String message) {
    return '检测失败：$message';
  }

  @override
  String get desktopHubAppSection => '应用与服务';

  @override
  String get desktopAboutProjectSection => '项目与链接';

  @override
  String get desktopAboutDisclaimerSection => '软件说明与免责声明';

  @override
  String get desktopSettingsAppearance => '外观主题';

  @override
  String get desktopSettingsAppearanceEntryBody => '配色方案与深浅模式，即时预览';

  @override
  String get desktopSettingsAppearanceTitle => '外观与界面主题';

  @override
  String get desktopSettingsAppearanceBody => '多套配色方案与深浅模式自由切换，全局即时适配';

  @override
  String get desktopSettingsPalette => '主题配色方案';

  @override
  String get desktopSettingsPaletteBody => '选择符合个人偏好的视觉设计体系，所有界面元素即时协调匹配';

  @override
  String get desktopSettingsMode => '深浅模式';

  @override
  String get desktopSettingsModeBody => '跟随系统时按系统深浅偏好自动同步';

  @override
  String get desktopSettingsAppearanceFooter => '外观偏好与移动端共用同一组键，切换后重启仍生效。';

  @override
  String get desktopSettingsPreview => '桌面预览';

  @override
  String get desktopSettingsPreviewBody => '侧栏、工具栏与卡片都按当前配色和深浅模式渲染，所见即所得。';

  @override
  String desktopSettingsSystemResolved(String mode) {
    return '$mode（跟随系统）';
  }

  @override
  String get desktopServicePageTitle => '服务与连接';

  @override
  String get desktopServiceEntryBody => '后台连接设置、核心服务与开机自启状态';

  @override
  String get desktopServiceConnectionTitle => '后台服务连接设置';

  @override
  String get desktopServiceConnectionBody => '前端客户端与核心服务的通信管道';

  @override
  String get desktopServiceConnectionFooter =>
      '保存后立即用新地址重建连接；「测试连接」检查当前服务是否应答。';

  @override
  String get desktopServiceHost => '服务地址（IP 或主机名）';

  @override
  String get desktopServicePort => '通信端口';

  @override
  String get desktopServiceToken => '访问密钥 / 授权 Token（可选）';

  @override
  String get desktopServiceTokenHint => '留空表示本机无需密码';

  @override
  String get desktopServiceTest => '测试连接';

  @override
  String get desktopServiceSave => '保存配置';

  @override
  String get desktopServiceSaved => '连接设置已保存';

  @override
  String get desktopServiceReachable => '通信正常';

  @override
  String get desktopServiceUnreachable => '连接异常';

  @override
  String get desktopServiceConfigured => '已配置';

  @override
  String get desktopServiceAddressInvalid => '服务地址不能为空，端口需为 1–65535 的整数';

  @override
  String get desktopServiceCoreTitle => '后台核心服务';

  @override
  String get desktopServiceCoreBody => '宿主机上负责 DNS 与拦截的核心服务状态';

  @override
  String get desktopServiceCoreFooter => '安装、启动与开机自启由宿主机托管，本页只读取并显示其真实状态。';

  @override
  String get desktopServiceState => '服务状态';

  @override
  String get desktopServiceAutoStartOn => '已开启';

  @override
  String get desktopServiceAutoStartOff => '未开启';

  @override
  String get desktopServiceAutoStartUnknown => '服务未上报';

  @override
  String get desktopServiceRunning => '运行中';

  @override
  String get desktopServiceStopped => '已停止';

  @override
  String get desktopServiceUnknown => '未知';

  @override
  String get desktopServiceRefresh => '刷新核心服务状态';

  @override
  String get desktopLanWebPageTitle => '局域网控制台';

  @override
  String get desktopLanWebEntryBody => '远程管理开关、访问地址、防火墙放行与管理员凭据';

  @override
  String get desktopHubClientAccess => '客户端访问控制';

  @override
  String get desktopHubClientAccessBody => '哪些局域网客户端可以解析，以及每个客户端的查询限速';

  @override
  String get desktopClientAccessPageTitle => '客户端访问控制';

  @override
  String get desktopLanWebRefresh => '刷新局域网控制台状态';

  @override
  String get desktopLanWebLoadFailed => '读不到局域网控制台状态';

  @override
  String get desktopLanWebAccessTitle => '放行与管理员凭据';

  @override
  String get desktopLanWebAccessBody => '防火墙放行规则与本控制台的登录账号，凭据只影响局域网访问';

  @override
  String get desktopLanWebTitle => '局域网 Web 控制台';

  @override
  String get desktopLanWebOpen => '对外开放中';

  @override
  String get desktopLanWebLocal => '仅本地（127.0.0.1）';

  @override
  String get desktopLanWebEnabledBody => '局域网内的手机或电脑可通过浏览器访问完整控制台进行远程管理。';

  @override
  String get desktopLanWebDisabledBody =>
      '开启后，局域网内的手机或电脑可通过浏览器访问完整控制台，与桌面客户端共享核心数据与配置。';

  @override
  String get desktopLanWebOn => '局域网 Web 管理已开启';

  @override
  String get desktopLanWebOff => '局域网 Web 管理已关闭';

  @override
  String desktopLanWebFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String get desktopLanWebUrls => '局域网访问网址（浏览器直连）';

  @override
  String get desktopLanWebNoUrls => '未探测到可用的局域网网卡 IPv4 地址';

  @override
  String get desktopLanWebPort => 'Web 端口';

  @override
  String get desktopLanWebSavePort => '保存端口';

  @override
  String get desktopLanWebPortInvalid => '请输入有效的端口号（1–65535）';

  @override
  String get desktopLanWebFirewall => '放行防火墙入站规则';

  @override
  String get desktopLanWebFirewallBody => '为 Web 端口添加或清除系统防火墙放行规则';

  @override
  String get desktopLanWebFirewallOn => '已放行防火墙 Web 端口';

  @override
  String get desktopLanWebFirewallOff => '已清除防火墙 Web 端口规则';

  @override
  String get desktopLanWebNoFirewall => '系统未检测到防火墙管理器，端口本就对外开放，无需放行规则。';

  @override
  String get desktopLanWebCredentials => '控制台凭据';

  @override
  String desktopLanWebUser(String user) {
    return '管理员：$user';
  }

  @override
  String get desktopLanWebNoUser => '尚未设置管理员';

  @override
  String get desktopLanWebProtected => '密码保护已启用';

  @override
  String get desktopLanWebUnprotected => '尚未初始化密码，首次进入需设置';

  @override
  String get desktopLanWebChangePassword => '修改管理员密码';

  @override
  String get desktopLanWebSetPassword => '设置初始密码';

  @override
  String get desktopLanWebPasswordSave => '保存';

  @override
  String get desktopLanWebPasswordSaved => '管理员密码已保存';

  @override
  String desktopLanWebChangeBody(String user) {
    return '修改 $user 的密码，保存后已有外部会话将失效。';
  }

  @override
  String desktopLanWebSetupBody(String user) {
    return '为 $user 设置初始密码，之后访问控制台需要登录。';
  }

  @override
  String get desktopLanWebOldPassword => '当前密码';

  @override
  String get desktopLanWebNewPassword => '新密码';

  @override
  String get desktopLanWebConfirmPassword => '确认新密码';

  @override
  String get desktopLanWebPasswordRequired => '新密码不能为空';

  @override
  String get desktopLanWebPasswordMismatch => '两次输入的新密码不一致';

  @override
  String get desktopLanWebOldRequired => '请输入当前密码';

  @override
  String get desktopLanWebFooter => '凭据仅用于局域网控制台登录；桌面客户端仍通过本机接口通信。';

  @override
  String get desktopHubAdapters => '网卡接管';

  @override
  String get desktopHubAdaptersBody => '逐网卡查看网关、DNS 与接管状态，可单个或全部接管';

  @override
  String get desktopHubLanDns => '局域网 DNS 服务';

  @override
  String get desktopHubLanDnsBody => '对外监听 53 端口，供路由器与终端共享解析与拦截';

  @override
  String get desktopAdaptersPageTitle => '网卡接管';

  @override
  String get desktopAdaptersRefresh => '刷新网卡列表';

  @override
  String get desktopAdaptersLoadFailed => '读不到网卡列表';

  @override
  String get desktopAdaptersSectionTitle => '网络连接与保护接管';

  @override
  String get desktopAdaptersSectionBody => '只列出当前正在使用的网络连接，虚拟与离线网卡由服务端排除。';

  @override
  String get desktopAdaptersTakeoverAll => '全部开启保护';

  @override
  String get desktopAdaptersRestoreAll => '恢复系统默认';

  @override
  String get desktopAdaptersProtecting => '保护中';

  @override
  String get desktopAdaptersInactive => '未开启';

  @override
  String get desktopAdaptersConnected => '已连接';

  @override
  String get desktopAdaptersDisconnected => '未连接';

  @override
  String get desktopAdaptersGateway => '默认网关';

  @override
  String get desktopAdaptersNoGateway => '无';

  @override
  String get desktopAdaptersIpMode => 'IP 模式';

  @override
  String get desktopAdaptersDhcp => '自动 (DHCP)';

  @override
  String get desktopAdaptersStatic => '固定静态 IP';

  @override
  String get desktopAdaptersOriginalDns => '原始系统 DNS';

  @override
  String get desktopAdaptersAutoDns => '自动获取 (系统默认)';

  @override
  String get desktopAdaptersEffectiveDns => '当前生效 DNS';

  @override
  String get desktopAdaptersEffectiveLoopback => '127.0.0.1 (本机保护)';

  @override
  String get desktopAdaptersEffectiveSystem => '系统默认未接管';

  @override
  String get desktopAdaptersEmpty => '未发现可用的网络连接';

  @override
  String get desktopAdaptersEmptyBody => '请确认 Wi-Fi 或网线已连接，然后重新检测。';

  @override
  String get desktopAdaptersAllOn => '已接管全部物理网卡';

  @override
  String get desktopAdaptersAllOff => '已恢复系统默认 DNS';

  @override
  String desktopAdaptersAdapterToggled(String name, String state) {
    return '$name：$state';
  }

  @override
  String get desktopAdaptersAdapterOn => '已接管';

  @override
  String get desktopAdaptersAdapterOff => '已恢复';

  @override
  String desktopAdaptersActionFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String get desktopLanDnsPageTitle => '局域网 DNS 服务';

  @override
  String get desktopLanDnsRefresh => '刷新局域网 DNS 状态';

  @override
  String get desktopLanDnsLoadFailed => '读不到局域网 DNS 状态';

  @override
  String get desktopLanDnsServiceTitle => '局域网 DNS 服务';

  @override
  String get desktopLanDnsServiceBody =>
      '开启后，路由器、手机、平板与 NAS 可将首选 DNS 设为本机 IP，共享加速与拦截。';

  @override
  String get desktopLanDnsOnChip => '全网监听 (0.0.0.0)';

  @override
  String get desktopLanDnsOffChip => '仅本机模式';

  @override
  String get desktopLanDnsOn => '局域网 DNS 服务已开启';

  @override
  String get desktopLanDnsOff => '已关闭局域网 DNS 服务，恢复为仅本机监听';

  @override
  String get desktopLanDnsAddressesCardTitle => '监听与访问地址';

  @override
  String get desktopLanDnsAddressesCardBody => '服务实际绑定的地址，以及局域网内其他设备可以填写的地址';

  @override
  String get desktopLanDnsListenTitle => '当前监听地址';

  @override
  String get desktopLanDnsNoListen => '服务当前未监听任何地址';

  @override
  String get desktopLanDnsAddressesTitle => '本机可用的局域网 DNS 地址';

  @override
  String get desktopLanDnsNoAddresses => '未检测到物理活动网卡 IP，请确认已连接 Wi-Fi 或以太网。';

  @override
  String get desktopLanDnsIpv4 => 'IPv4';

  @override
  String get desktopLanDnsIpv6 => 'IPv6';

  @override
  String desktopLanDnsRouterHint(String address) {
    return '把 $address 填进路由器的 DNS 设置即可覆盖全屋设备。';
  }

  @override
  String get desktopLanDnsFirewallTitle => '防火墙入站放行';

  @override
  String get desktopLanDnsFirewallAllowed => '53 端口已放行';

  @override
  String get desktopLanDnsFirewallBlocked => '未放行';

  @override
  String get desktopLanDnsFirewallNone => '无需放行';

  @override
  String get desktopLanDnsFirewallBody =>
      '局域网设备需通过 UDP/TCP 53 端口向本机发送解析请求；被防火墙拦截会导致这些设备断网。';

  @override
  String get desktopLanDnsFirewallNoneBody =>
      '系统未检测到防火墙后端，53 端口已直接对外开放，无需放行规则。';

  @override
  String get desktopLanDnsFirewallStatusOn => '允许局域网设备接入 53 端口';

  @override
  String get desktopLanDnsFirewallStatusOff => '53 端口受限或被拦截';

  @override
  String get desktopLanDnsFirewallAllow => '一键放行入站 53 端口';

  @override
  String get desktopLanDnsFirewallRemove => '移除防火墙入站放行';

  @override
  String get desktopLanDnsFirewallOn => '已放行 53 端口入站规则';

  @override
  String get desktopLanDnsFirewallOff => '已移除 53 端口入站规则';

  @override
  String get desktopLanDnsRouterTitle => '方案 A：路由器全局配置';

  @override
  String get desktopLanDnsRouterBadge => '强烈推荐';

  @override
  String get desktopLanDnsRouterBody =>
      '登录路由器后台（通常为 192.168.1.1），在「局域网 LAN 设置」或「DHCP 服务器」里把主 DNS 改为本机 IP。';

  @override
  String get desktopLanDnsRouterFoot => '保存并重连 Wi-Fi 后，全屋设备统一生效。';

  @override
  String get desktopLanDnsDeviceTitle => '方案 B：单终端独立配置';

  @override
  String get desktopLanDnsDeviceBadge => '独立体验';

  @override
  String get desktopLanDnsDeviceBody =>
      '在手机或电脑的 Wi-Fi 详情里把 IP 设置改为静态，DNS 1 填入本机 IP。';

  @override
  String get desktopLanDnsDeviceFoot => '适用于没有路由器管理权限，或只想让单台设备体验的场景。';

  @override
  String get desktopLanDnsPlaceholder => '192.168.x.x';

  @override
  String desktopLanDnsFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String get desktopLoginTitle => '谛听 DNS 控制台';

  @override
  String get desktopLoginSubtitle => '局域网远程管理服务 · 请验证管理员凭据';

  @override
  String get desktopLoginSetupSubtitle => '初始化管理员密码，守护局域网远程管理安全';

  @override
  String get desktopLoginUserLabel => '管理员账号';

  @override
  String get desktopLoginPasswordLabel => '管理员密码';

  @override
  String get desktopLoginSetupPasswordLabel => '设置初始密码 (至少 4 位)';

  @override
  String get desktopLoginConfirmLabel => '确认管理员密码';

  @override
  String get desktopLoginSubmit => '立即登录';

  @override
  String get desktopLoginSetupSubmit => '完成初始化并进入控制台';

  @override
  String get desktopLoginSecurity => 'SHA-256 加盐哈希保护 · 连续错误自动安全锁定';

  @override
  String get desktopLoginFooter => '谛听 (DITING) DNS 解析加速与安全防护系统';

  @override
  String get desktopLoginChecking => '控制台安全载入中…';

  @override
  String get desktopLoginShowPassword => '显示密码';

  @override
  String get desktopLoginHidePassword => '隐藏密码';

  @override
  String get desktopLoginUserRequired => '请输入用户名';

  @override
  String get desktopLoginPasswordRequired => '请输入密码';

  @override
  String get desktopLoginPasswordTooShort => '密码长度至少为 4 位字符';

  @override
  String get desktopLoginPasswordMismatch => '两次输入的密码不一致';

  @override
  String get desktopLoginSuccess => '身份验证成功，正在进入控制台…';

  @override
  String get desktopLoginSetupSuccess => '管理员密码设置成功，正在进入系统…';

  @override
  String desktopLoginLockout(int seconds) {
    return '安全频控锁定中，请等待 $seconds 秒后再试';
  }

  @override
  String get desktopLoginUnreachable => '连不上本机服务';

  @override
  String get desktopLoginRetry => '重试';

  @override
  String get desktopLoginThemeCycle => '切换深浅模式';

  @override
  String get desktopLoginPaletteCycle => '切换配色方案';

  @override
  String get desktopLoginBackground => '自定义背景';

  @override
  String get desktopLoginBackgroundEnabled => '已启用自定义背景';

  @override
  String get desktopLoginBackgroundTitle => '登录背景';

  @override
  String get desktopLoginBackgroundLocal => '本地上传';

  @override
  String get desktopLoginBackgroundUrl => '网络图片';

  @override
  String get desktopLoginBackgroundChoose => '选择图片';

  @override
  String get desktopLoginBackgroundNoFile => '未选择图片';

  @override
  String get desktopLoginBackgroundUrlLabel => '图片地址';

  @override
  String get desktopLoginBackgroundUrlInvalid =>
      '请输入 http:// 或 https:// 开头的图片地址';

  @override
  String get desktopLoginBackgroundOpacity => '遮罩暗度';

  @override
  String get desktopLoginBackgroundBlur => '毛玻璃模糊';

  @override
  String get desktopLoginBackgroundSave => '保存背景';

  @override
  String get desktopLoginBackgroundReset => '恢复默认背景';

  @override
  String get desktopLoginBackgroundSaved => '登录背景已保存';

  @override
  String get desktopLoginBackgroundResetDone => '已恢复系统默认背景';

  @override
  String get desktopLoginBackgroundNeedImage => '请先选择图片或填写图片地址';

  @override
  String get desktopLoginBackgroundPassword => '管理员密码';

  @override
  String get desktopLoginBackgroundPasswordBody => '局域网远程修改登录背景需要验证管理员密码。';

  @override
  String desktopLoginBackgroundFailed(String message) {
    return '操作失败：$message';
  }

  @override
  String get desktopSettingsSessionSection => '当前会话';

  @override
  String get desktopSettingsLogout => '退出登录';

  @override
  String get desktopSettingsLogoutBody => '清除本机保存的管理员会话，返回登录页';

  @override
  String get desktopSettingsLogoutConfirm => '退出后需要重新输入管理员凭据才能进入控制台。';

  @override
  String get desktopSettingsLogoutDone => '已退出登录';

  @override
  String get desktopToolsEmergencyTitle => '一键恢复系统网络默认';

  @override
  String get desktopToolsEmergencyBody =>
      '当软件异常退出导致无法上网时，按接管前的快照还原系统 DNS，并清理残留回环 DNS 与系统缓存。';

  @override
  String get desktopToolsEmergencyAction => '一键恢复';

  @override
  String get desktopToolsEmergencyBusy => '正在恢复…';

  @override
  String get desktopToolsEmergencyConfirmTitle => '确认执行应急恢复？';

  @override
  String get desktopToolsEmergencyConfirmBody =>
      '将按接管前落盘的快照还原系统 DNS，兜底清理指向本机的残留回环 DNS，再清空系统 DNS 缓存。';

  @override
  String get desktopToolsEmergencyDone => '网络设置已恢复默认';

  @override
  String desktopToolsEmergencyFailed(String message) {
    return '恢复失败：$message';
  }

  @override
  String get desktopToolsEmergencyFooter => '恢复依据是接管前落盘的快照，不会改动网卡驱动本身。';

  @override
  String get desktopLanWebQrCaption => '手机与电脑连同一 Wi-Fi，用相机扫码直达控制台';

  @override
  String get desktopLoginBackgroundPreparing => '正在压缩图片…';

  @override
  String get desktopLoginChangePassword => '修改管理员密码';

  @override
  String get desktopLoginChangeSubtitle => '更新管理员凭据，保存后其他外部会话立即失效';

  @override
  String get desktopLoginOldPasswordLabel => '当前密码';

  @override
  String get desktopLoginNewPasswordLabel => '新密码 (至少 4 位)';

  @override
  String get desktopLoginChangeSubmit => '保存新密码';

  @override
  String get desktopLoginChangeSuccess => '管理员密码已更新，请用新密码登录';

  @override
  String get desktopLoginBackToSignIn => '返回登录';

  @override
  String get desktopLoginOldPasswordRequired => '请输入当前密码';

  @override
  String get desktopTrayTooltip => '谛听 (DITING) DNS 控制台';

  @override
  String get desktopTrayOpenWindow => '打开主界面';

  @override
  String get desktopTrayHideWindow => '隐藏主界面';

  @override
  String get desktopTrayAutoStart => '开机自启动';

  @override
  String get desktopTrayServiceRunning => '核心服务：运行中';

  @override
  String get desktopTrayServiceStopped => '核心服务：已停止';

  @override
  String get desktopTrayServiceUnknown => '核心服务：状态未知';

  @override
  String get desktopTrayServiceStart => '启动核心服务';

  @override
  String get desktopTrayServiceStop => '停止核心服务';

  @override
  String get desktopTrayServiceRestart => '重启核心服务';

  @override
  String get desktopTrayQuit => '退出程序';

  @override
  String get desktopTrayBalloonServiceTitle => '核心服务';

  @override
  String get desktopTrayBalloonServiceStarted => '核心服务已启动';

  @override
  String get desktopTrayBalloonServiceStopped => '核心服务已停止';

  @override
  String get desktopTrayBalloonServiceRestarted => '核心服务已重启';

  @override
  String get desktopTrayBalloonAutoStartTitle => '开机自启动';

  @override
  String get desktopTrayBalloonAutoStartOn => '已开启开机自启动';

  @override
  String get desktopTrayBalloonAutoStartOff => '已关闭开机自启动';

  @override
  String get desktopTrayBalloonFailedPrefix => '操作失败：';

  @override
  String get desktopTrayBalloonMinimized =>
      '谛听已最小化到系统托盘，并在后台继续运行。\n点击托盘图标可重新打开主界面。';

  @override
  String get serverHubUpstreamDescription => '管理解析上游与解析策略';

  @override
  String get serverHubCacheDescription => '调整 DNS 缓存开关、容量与命中策略';

  @override
  String get serverHubRuleControlDescription => '配置规则总开关与拦截响应策略';

  @override
  String get serverNavHome => '首页';

  @override
  String get serverServiceSection => '服务设置';

  @override
  String get serverDomainRules => '域名规则';

  @override
  String get serverDomainRulesDescription => '黑名单、白名单与 Hosts 覆写的快捷入口';

  @override
  String get serverDashboardStatusDescription => '服务运行状态、运行时长与本次运行统计';

  @override
  String get serverDashboardLanDescription => '局域网接入地址、端口与复制入口';

  @override
  String get integrationSection => '系统集成';

  @override
  String get integrationTitle => '小组件与自动化';

  @override
  String get integrationSubtitle => '桌面小组件、深链导入与自动化控制';

  @override
  String get integrationWidgetTitle => '桌面小组件';

  @override
  String get integrationWidgetBody =>
      '长按桌面空白处，进入「小组件」，选择「谛听」即可添加。组件显示保护状态与今日拦截数，点右侧按钮可一键开启或关闭。';

  @override
  String get integrationDeepLinkTitle => '深链导入订阅';

  @override
  String get integrationDeepLinkBody =>
      '在浏览器或其它应用中打开 diting://install-config?url=<订阅地址>，即可直接导入订阅（需先接受首次使用协议）。install-sub 为等价写法。';

  @override
  String get integrationAutomationTitle => '自动化控制';

  @override
  String get integrationAutomationBody =>
      '通过 Tasker、MacroDroid 或 adb 发送以下动作，可启动、停止或切换当前模式：';

  @override
  String get integrationAutomationStart => '启动';

  @override
  String get integrationAutomationStop => '停止';

  @override
  String get integrationAutomationToggle => '切换';

  @override
  String get deepLinkImportInvalid => '深链地址无效，无法导入订阅';

  @override
  String get troubleshootLogsTitle => '日志管理';

  @override
  String get troubleshootLogsViewLogs => '查看并管理日志';

  @override
  String get troubleshootLogsViewLogsBody => '按时间查看运行日志与崩溃日志，可删除或分享';

  @override
  String get troubleshootLogsAll => '全部日志';

  @override
  String troubleshootLogsCount(int count) {
    return '共 $count 个日志文件';
  }

  @override
  String get troubleshootLogsReading => '正在读取日志…';

  @override
  String get troubleshootLogsEmpty => '当前设备没有日志';

  @override
  String get troubleshootLogsEmptyBody => '开启运行日志记录或发生崩溃后，日志会出现在这里。';

  @override
  String get troubleshootLogKindRuntime => '运行日志';

  @override
  String get troubleshootLogKindCrash => '崩溃日志';

  @override
  String get troubleshootLogsRefresh => '刷新';

  @override
  String get troubleshootLogsShare => '分享';

  @override
  String get troubleshootLogsShareAll => '分享全部';

  @override
  String get troubleshootLogsClearAll => '清空全部';

  @override
  String get troubleshootLogsShared => '已打开系统分享';

  @override
  String get troubleshootLogsShareFailed => '分享失败';

  @override
  String get troubleshootLogsDeleted => '已删除该日志';

  @override
  String get troubleshootLogsDeleteFailed => '删除失败';

  @override
  String get troubleshootLogsDeleteTitle => '删除日志';

  @override
  String troubleshootLogsDeleteBody(String name) {
    return '确认删除“$name”吗？该操作不可恢复。';
  }

  @override
  String get troubleshootLogsClearAllTitle => '清空全部日志';

  @override
  String get troubleshootLogsClearAllBody => '确认删除全部运行日志与崩溃日志吗？该操作不可恢复。';

  @override
  String troubleshootLogsClearedAll(int runtime, int crash) {
    return '已清空 $runtime 个运行日志与 $crash 份崩溃日志';
  }

  @override
  String get troubleshootLogsLogContent => '日志内容';

  @override
  String get troubleshootLogsDetailInfo => '日志信息';

  @override
  String get troubleshootLogsFileName => '文件名';

  @override
  String get troubleshootLogsFileType => '类型';

  @override
  String get troubleshootLogsFileSize => '大小';

  @override
  String get troubleshootLogsModifiedAt => '修改时间';

  @override
  String get troubleshootLogsViewContent => '查看日志内容';

  @override
  String get troubleshootLogsViewContentBody => '进入下一层查看完整日志';

  @override
  String get troubleshootLogsEmptyContent => '无法读取该日志内容';

  @override
  String get troubleshootLogsTruncated => '内容过长，仅显示开头部分';

  @override
  String get troubleshootLogsFooter => '日志只保存在本机，分享前请确认其中不含敏感信息。';

  @override
  String get troubleshootEventsTitle => '运行事件';

  @override
  String get troubleshootEventsRecentTitle => '最近运行事件';

  @override
  String get troubleshootEventsRecentBody => '常开记录应用启动、服务与引擎的异常事件，可事后排查。';

  @override
  String get troubleshootEventsEmpty => '暂无运行事件';

  @override
  String get troubleshootEventsEmptyBody => '应用启动、服务或引擎发生异常时会自动记录。';

  @override
  String get troubleshootEventsAll => '全部';

  @override
  String get troubleshootEventsWarnPlus => '警告及以上';

  @override
  String get troubleshootEventsErrorOnly => '仅错误';

  @override
  String get troubleshootEventsModuleAll => '全部模块';

  @override
  String troubleshootEventsCount(int count) {
    return '共 $count 条';
  }

  @override
  String troubleshootEventsAnomaly(int count) {
    return '检测到 $count 条异常';
  }

  @override
  String get troubleshootEventsExport => '导出当前筛选';

  @override
  String get troubleshootEventsStatTotal => '事件总数';

  @override
  String get troubleshootEventsStatError => '错误';

  @override
  String get troubleshootEventsNoMatch => '没有符合筛选条件的事件';

  @override
  String get troubleshootEventsLevel => '级别';

  @override
  String get troubleshootEventsModule => '模块';

  @override
  String get troubleshootEventsOpen => '查看运行事件';

  @override
  String get troubleshootEventsOpenBody => '按级别与模块筛选启动、服务与异常事件';

  @override
  String get troubleshootDetailMode => '详细模式';

  @override
  String get troubleshootDetailModeNote => '详细模式记录所有进程与缓冲区的完整 logcat，更全面但更耗电。';
}
