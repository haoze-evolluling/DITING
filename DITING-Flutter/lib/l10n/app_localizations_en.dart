// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DITING';

  @override
  String get uiBack => 'Back';

  @override
  String get uiCancel => 'Cancel';

  @override
  String get uiClearSearch => 'Clear search';

  @override
  String get uiClose => 'Close';

  @override
  String get uiHidePassword => 'Hide password';

  @override
  String get uiMore => 'More';

  @override
  String get uiNoSearchResults => 'No results';

  @override
  String get uiReset => 'Reset';

  @override
  String get uiSearch => 'Search';

  @override
  String get uiShowLess => 'Show less';

  @override
  String get uiShowMore => 'Show more';

  @override
  String get uiShowPassword => 'Show password';

  @override
  String get uiSort => 'Sort';

  @override
  String get uiSubmit => 'Submit';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageInterfaceSection => 'Interface language';

  @override
  String get languageInterfaceFooter =>
      'Choose the interface language. \"Follow system\" uses the device language and falls back to Chinese for other languages.';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get commonFollowSystem => 'Follow system';

  @override
  String get commonSelectAll => 'Select all';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonInvertSelection => 'Invert selection';

  @override
  String get commonFilter => 'Filter';

  @override
  String get commonSort => 'Sort';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDiscard => 'Don\'t save';

  @override
  String get commonSaveChangesTitle => 'Save changes?';

  @override
  String get commonSaveChangesMessage =>
      'Your changes have not been saved yet. Save them before leaving, or discard them?';

  @override
  String commonSaveChangesMessageFor(String name) {
    return 'The selection for \"$name\" has not been saved yet. Save it before leaving, or discard the changes?';
  }

  @override
  String get commonGrantPermission => 'Grant access';

  @override
  String get palettePurple => 'Iris purple';

  @override
  String get paletteBlue => 'Water lily blue';

  @override
  String get paletteCyan => 'Pool cyan';

  @override
  String get paletteGreen => 'Willow green';

  @override
  String get paletteOrange => 'Dusk ochre';

  @override
  String get paletteRed => 'Poppy red';

  @override
  String get palettePink => 'Sunset pink';

  @override
  String get paletteGold => 'Wheat gold';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get appListUnavailable => 'Can\'t read the app list';

  @override
  String get appListFilterAll => 'All apps';

  @override
  String get appListFilterSystem => 'System apps';

  @override
  String get appListFilterUser => 'User apps';

  @override
  String get appListFilterSelected => 'Selected apps';

  @override
  String get appListSortLabelAsc => 'App name A-Z';

  @override
  String get appListSortLabelDesc => 'App name Z-A';

  @override
  String get appListSortPackageAsc => 'Package A-Z';

  @override
  String get appListSortPackageDesc => 'Package Z-A';

  @override
  String get appListNotRegistered => 'not registered';

  @override
  String appListChannelUnavailable(String detail) {
    return 'App list channel unavailable: $detail';
  }

  @override
  String appListReadFailed(String detail) {
    return 'Failed to read the app list: $detail';
  }

  @override
  String appListReadFailedCode(String code) {
    return 'Failed to read the app list ($code)';
  }

  @override
  String dbWriteUnhealthy(int dropped, int failures) {
    return 'Log writes are failing: $dropped rows dropped and $failures failed opens. See Troubleshooting for details.';
  }

  @override
  String get agreementDeclinedTitle => 'Notice declined';

  @override
  String get agreementDeclinedMessage =>
      'DITING can\'t be used without accepting the notice and disclaimer. You can quit the app, or review the terms again and then decide.';

  @override
  String get agreementReviewAgain => 'Review again';

  @override
  String get agreementTitle => 'Notice and disclaimer';

  @override
  String get agreementDecline => 'Decline and exit';

  @override
  String get agreementAccept => 'Accept and continue';

  @override
  String get agreementMessage =>
      'About the app\nDITING is an open-source tool focused on local DNS resolution optimisation and network rule filtering. It offers three work modes: Normal (full-tunnel control), Turbo (a lightweight pure-Kotlin narrow route) and Standalone server (a LAN service that needs no VPN). Everything runs locally on the device: no remote data upload and no privacy tracking.\n\nHow it works\nNormal and Turbo modes take over DNS resolution through the Android local VPN interface and never connect to a remote VPN server; Standalone server mode needs no VPN permission and listens on local port 1053 for LAN devices. Rules and logs stay on the device. Please understand the impact before enabling advanced extensions.\n\nDisclaimer\nThis software is provided as is. Users must comply with applicable laws and verify the legality and safety of the rules and upstream resolvers they configure. Any illegal use is strictly forbidden, and users bear all consequences of their own configuration or use of this software.';

  @override
  String get homeProviderSingleLabel => 'Resolver';

  @override
  String get homeProviderRaceLabel => 'Racing resolvers';

  @override
  String get homeChartEmptyLabel => 'No samples yet';

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get dashboardDetailTooltip => 'Details';

  @override
  String get dashboardEmptyLabel => 'No dashboard cards yet';

  @override
  String get dashboardEmptyDescription =>
      'Enter edit mode and pick a few cards from \"Add card\".';

  @override
  String get dashboardEnterEditMode => 'Enter edit mode';

  @override
  String get dashboardEditHint =>
      'Drag the handle to reorder, tap the top-right corner to remove; tap \"Done\" when finished.';

  @override
  String get dashboardAllRemovedLabel => 'All cards removed';

  @override
  String get dashboardAllRemovedDescription =>
      'Tap \"Add card\" below to pick one.';

  @override
  String get dashboardAddCard => 'Add card';

  @override
  String get providerSheetSingleTitle => 'Choose a resolver';

  @override
  String get providerSheetRaceTitle => 'Choose racing resolvers';

  @override
  String get providerSheetSingleOptions => 'Available resolvers';

  @override
  String get providerSheetRaceMinimum => 'Pick at least 2';

  @override
  String get providerSheetManage => 'Manage resolvers...';

  @override
  String get providerSheetVisibility => 'Resolver visibility...';

  @override
  String get providerSheetSingleFooter =>
      'Latency comes from the last resolution health record, not a live measurement.';

  @override
  String get providerSheetRaceFooter =>
      'In racing mode every query is sent to all selected resolvers concurrently.';

  @override
  String get powerButtonStop => 'Stop';

  @override
  String get powerButtonStart => 'Start';

  @override
  String get powerButtonStarting => 'Starting';

  @override
  String get homeEditDashboard => 'Edit dashboard';

  @override
  String get homeDone => 'Done';

  @override
  String get homeSwitchWorkMode => 'Switch work mode';

  @override
  String get homeTitleNormal => 'DITING · Normal';

  @override
  String get homeTitleServer => 'DITING · Server';

  @override
  String get homeTitleExpress => 'DITING · Express';

  @override
  String get logRequestsOverview => 'Request overview';

  @override
  String get logTodayRequests => 'Requests today';

  @override
  String get logPassed => 'Passed';

  @override
  String get logFiltered => 'Filtered';

  @override
  String get logCacheHits => 'Cache hits';

  @override
  String get logHighlights => 'Key records';

  @override
  String get logBlocked => 'Blocked';

  @override
  String get logFailed => 'Failed';

  @override
  String get logBypassed => 'Bypassed';

  @override
  String get logOffModeTitle => 'Resolution overview';

  @override
  String get logCacheEntries => 'Live cache entries';

  @override
  String get logCacheHitsTotal => 'Total cache hits';

  @override
  String get logRaceRequests => 'Concurrent race queries';

  @override
  String get logBootstrapAttempts => 'Bootstrap attempts';

  @override
  String get logRecentRequests => 'Recent requests';

  @override
  String get logRecentRequestsEmpty => 'No requests yet';

  @override
  String get logRecentBlocked => 'Recent blocks and errors';

  @override
  String get logRecentBlockedEmpty => 'No blocks or errors yet';

  @override
  String get logCacheHotspots => 'Cache hotspots';

  @override
  String get logCacheHotspotsEmpty => 'No live cache entries';

  @override
  String logExpiresIn(String duration) {
    return 'expires in $duration';
  }

  @override
  String logTimes(String count) {
    return '$count times';
  }

  @override
  String get logRaceWinners => 'Race winners';

  @override
  String get logRaceWinnersEmpty => 'No race data yet';

  @override
  String logAverageWinLatency(String latency) {
    return 'Won in $latency on average';
  }

  @override
  String get logBootstrapDnsEmpty => 'No Bootstrap data yet';

  @override
  String logBootstrapRow(String ip, String latency, String percent) {
    return '$ip · $percent success · $latency';
  }

  @override
  String get logRuleBlocks => 'Rule blocks';

  @override
  String get logRuleBlocksEmpty => 'No rule blocks yet';

  @override
  String logShareRow(String percent, String status) {
    return '$status · $percent of all requests';
  }

  @override
  String get logPrivacyMode => 'Privacy mode is on';

  @override
  String get logLoggingOff => 'Logging off';

  @override
  String get logPrivacyModeBody =>
      'After logging is turned back on the dashboard counts from the requests recorded from then on. Resolution services and cache hotspots keep working meanwhile.';

  @override
  String get logPerfTitle => 'Resolution performance';

  @override
  String get logTodayStats => 'Today';

  @override
  String get logAverageLatency => 'Average resolution time';

  @override
  String get logNoTimingSamples => '— · No timing samples today';

  @override
  String logSampleValue(String count, String value) {
    return '$value · $count samples';
  }

  @override
  String get logCacheHitRate => 'Cache hit rate';

  @override
  String logCacheHitRateValue(String percent) {
    return '$percent · denominator is passed + failed';
  }

  @override
  String get logRaceSuccessRate => 'Race success rate';

  @override
  String get logBootstrapSuccessRate => 'Bootstrap success rate';

  @override
  String logRateValue(String count, String latency, String percent) {
    return '$percent · $count times · $latency';
  }

  @override
  String get dashboardRestoreDefaults => 'Restore defaults';

  @override
  String get dashboardAllCardsAdded => 'All cards are on the dashboard';

  @override
  String get dashboardAllCardsAddedDescription =>
      'To remove one, go back to edit mode and tap the remove button in its top-right corner.';

  @override
  String get dashboardAvailableCards => 'Available cards';

  @override
  String get dashboardOrderHint =>
      'Drag cards in edit mode to change their order.';

  @override
  String get dashboardCardProviderDescription =>
      'The active resolver; open it to switch or adjust the racing list';

  @override
  String get dashboardCardResolutionDescription =>
      'Resolution mode, a one-line summary and the DNS address in effect';

  @override
  String get dashboardCardStatusDescription =>
      'Core state, uptime, active resolver and today\'s queries';

  @override
  String get dashboardCardSpeedDescription =>
      'Live up/down rate curves and today\'s total traffic';

  @override
  String get dashboardCardSiteLatencyDescription =>
      'Measured latency of four custom sites; the detail page tests each category';

  @override
  String get dashboardCardMemoryDescription =>
      'This process\'s PSS split into Java and native heap';

  @override
  String get dashboardCardIntranetDescription =>
      'Current LAN address, listening state and a copy action';

  @override
  String get intranetIpTitle => 'LAN IP';

  @override
  String get intranetCopyAddress => 'Copy address';

  @override
  String get intranetReading => 'Reading…';

  @override
  String get intranetNoActiveNetwork => 'No active network';

  @override
  String get intranetLanAccess => 'LAN access';

  @override
  String get intranetConnectHint =>
      'Connect to Wi-Fi or Ethernet to see a usable address here';

  @override
  String get memoryTitle => 'Memory';

  @override
  String get memoryJavaHeap => 'Java heap';

  @override
  String get memoryNativeHeap => 'Native heap';

  @override
  String get memorySystemAvailable => 'System available';

  @override
  String get speedTitle => 'Network speed';

  @override
  String get speedUpload => 'Upload';

  @override
  String get speedDownload => 'Download';

  @override
  String get speedExpressNoStats => 'Not measured in express mode';

  @override
  String get speedNoChannel => 'No rate channel in this environment';

  @override
  String get resolutionModeTitle => 'Resolution mode';

  @override
  String get resolutionNoProvider => 'No resolver selected';

  @override
  String get resolutionSingleSummary =>
      'Uses only the selected resolver: fastest, but availability depends on it.';

  @override
  String get resolutionSmartSummary =>
      'Picks one by historical success rate and falls back to the next on failure.';

  @override
  String get resolutionParallelSummary =>
      'Asks every resolver at once and takes the first answer.';

  @override
  String get resolutionPrimaryBackupSummary =>
      'Primary first, backups only after a timeout.';

  @override
  String get siteLatencyTesting => 'Testing…';

  @override
  String get siteLatencyNotTested => 'Not tested yet';

  @override
  String get siteLatencyTitle => 'Site latency';

  @override
  String get siteLatencyRetest => 'Test again';

  @override
  String get commonFailed => 'Failed';

  @override
  String get siteLatencyNoReply => 'No reply';

  @override
  String get statusTitle => 'Status';

  @override
  String get statusUptime => 'Uptime';

  @override
  String get statusActiveProvider => 'Active resolver';

  @override
  String get statusNotSelected => 'None';

  @override
  String get statusTodayQueries => 'Queries today';

  @override
  String get statusDetailTitle => 'Status details';

  @override
  String get statusNotTiming => 'Not counting';

  @override
  String get statusCoreSection => 'Core';

  @override
  String get statusWorkMode => 'Work mode';

  @override
  String get statusCoreState => 'Core state';

  @override
  String get statusListenPort => 'Listening port';

  @override
  String get statusNotListening => 'Not listening';

  @override
  String get statusProviderFooter =>
      'Latency is the resolver\'s last measured value, not this device\'s round trip to the target.';

  @override
  String get statusNoProviderHint =>
      'No resolver selected yet. Pick one in resolver management so resolution uses a real upstream.';

  @override
  String get statusTodayCounts => 'Today\'s counts';

  @override
  String get statusCountsFooter =>
      'Counts accumulate from this core start and reset when it restarts or the work mode changes; the reset in server mode clears only the counts, never rules or cache.';

  @override
  String get statusQueries => 'Queries';

  @override
  String get statusBlocked => 'Blocked';

  @override
  String get statusAverageLatency => 'Average latency';

  @override
  String get statusCacheHitRate => 'Cache hit rate';

  @override
  String get statusServerPortReady =>
      'The local DNS port is available; LAN devices can use it as their DNS';

  @override
  String get statusTunnelActive =>
      'This device\'s traffic goes through DITING, so resolution and rules are in effect';

  @override
  String get statusServerPortClosed =>
      'The DNS port is not listening, so server mode is not serving resolution';

  @override
  String get statusCoreStopped =>
      'The core is not running, so this device uses the system\'s default network';

  @override
  String get siteLatencySheetLatency => 'Latency';

  @override
  String get siteLatencySheetCategory => 'Category';

  @override
  String get siteLatencySheetTarget => 'Target';

  @override
  String get siteLatencySheetAverage => 'Average RTT';

  @override
  String get siteLatencySheetMinMax => 'Min / max';

  @override
  String get siteLatencySheetJitter => 'Jitter';

  @override
  String get siteLatencySheetLoss => 'Loss';

  @override
  String get siteLatencySheetDns => 'Resolved address';

  @override
  String get siteLatencySheetLastRun => 'Last test';

  @override
  String get siteLatencySheetNotTested =>
      'Not tested yet. Tap the test button to start.';

  @override
  String get siteLatencySheetNoReply =>
      'None of the three echo requests was answered: the site may be rate limiting or the network is down.';

  @override
  String get siteLatencySheetFallbackFooter =>
      'System ping is unavailable, so these numbers come from the TCP handshake / isReachable: they measure connection setup, not ICMP echo, and read slightly higher than the real round trip.';

  @override
  String get siteLatencySheetIcmpFooter =>
      'Numbers come from ICMP echo via system ping (average of three). This app\'s own traffic bypasses the VPN, so the physical network is measured.';

  @override
  String get trafficStructureLive => 'Live summary';

  @override
  String get trafficStructureFocused => 'Key traffic structure';

  @override
  String get trafficStructureToday => 'Today\'s traffic structure';

  @override
  String get trafficStructureBypass => 'Bypass';

  @override
  String get trafficStructureCache => 'Cache';

  @override
  String get trafficStructureRaceRate => 'Race success rate';

  @override
  String get trafficStructureBootstrapRate => 'Bootstrap success rate';

  @override
  String get trafficStructureBlockedShare => 'Blocked share';

  @override
  String get trafficStructureBlockRate => 'Block rate';

  @override
  String get trafficStructureCacheRate => 'Cache rate';

  @override
  String get dashboardSitesTitle => 'Dashboard sites';

  @override
  String get dashboardSitesCardSection => 'Dashboard card';

  @override
  String get dashboardSitesAtLeastOne => 'Keep at least one site on the card';

  @override
  String get dashboardSitesFooter =>
      'These four cards share one dashboard card, so changes apply immediately; tests run per category from the detail page.';

  @override
  String get trafficMonitorTitle => 'Traffic monitor';

  @override
  String get trafficMonitorToday => 'Proxy traffic today';

  @override
  String get trafficMonitorLiveRate => 'Live rate';

  @override
  String get trafficMonitorNoStats => 'Not measured in this mode';

  @override
  String get memoryDetailTitle => 'Memory details';

  @override
  String get memoryResample => 'Resample';

  @override
  String get memoryProcessPss => 'This process PSS';

  @override
  String get memoryUnavailable => 'Unavailable';

  @override
  String get memoryOther => 'Other';

  @override
  String get memoryComposition => 'Process composition';

  @override
  String get memoryCompositionFooter =>
      'PSS counts shared pages proportionally, so the Java and native heaps add up to less than the PSS; the remainder is code, graphics buffers and shared libraries.';

  @override
  String get memoryOtherCode => 'Other (code / shared libraries)';

  @override
  String get memorySystemSection => 'System memory';

  @override
  String get memorySystemFooter =>
      'System usage = total - available, covering the system and every app; this process is only one part of it.';

  @override
  String get memorySystemUsed => 'System used';

  @override
  String get memoryRecentPss => 'Recent PSS';

  @override
  String get memorySampling => 'Sampling…';

  @override
  String get memoryRecentPssCaption =>
      'This page samples every 2 seconds and keeps at most 60 points; a curve that keeps climbing means memory is not being released.';

  @override
  String get memorySourceFooter =>
      'Data comes from ActivityManager\'s MemoryInfo; the numbers drop noticeably after the app is backgrounded or the system reclaims memory.';

  @override
  String get siteLatencyDetailTitle => 'Latency details';

  @override
  String get siteLatencyTestAll => 'Test all';

  @override
  String get siteLatencyCustomSites => 'Custom dashboard sites';

  @override
  String get siteLatencyConnectivity => 'Site connectivity';

  @override
  String get siteLatencyTestingShort => 'Testing';

  @override
  String get siteLatencyNoTest => 'Not tested';

  @override
  String get siteLatencyInProgress => 'In progress';

  @override
  String get siteLatencyPending => 'Pending';

  @override
  String get siteLatencyAllReachable => 'All reachable';

  @override
  String get siteLatencyTestingEach => 'Testing the sites one by one…';

  @override
  String get siteLatencyPickCategory =>
      'Pick a category and start a test, or tap the top-right corner to test everything.';

  @override
  String get siteLatencyThisRun => 'This run';

  @override
  String get siteLatencyReachable => 'Reachable';

  @override
  String get siteLatencyMeasuredSites => 'Sites tested';

  @override
  String get siteLatencyDetailFooter =>
      'Each site gets three ICMP echo requests and the average is used; when system ping is unavailable the TCP handshake is used instead, marked with *, and reads slightly higher than the real round trip. This app\'s own traffic bypasses the VPN, so the physical network is measured.';

  @override
  String get intranetDetailTitle => 'LAN IP details';

  @override
  String get intranetRefresh => 'Refresh network info';

  @override
  String get intranetLocalAddress => 'Local LAN address';

  @override
  String get intranetUsableAsDns => 'Usable as DNS';

  @override
  String get intranetLocalOnly => 'Local only';

  @override
  String get intranetSameSubnetHint =>
      'Point devices on the same subnet at this address to use local resolution.';

  @override
  String get intranetNetworkOverview => 'Network overview';

  @override
  String get commonEnabled => 'Enabled';

  @override
  String get commonDisabled => 'Disabled';

  @override
  String get intranetDnsServers => 'DNS servers';

  @override
  String get intranetInterfaces => 'Interfaces';

  @override
  String get intranetNoInterface =>
      'The system reports no active network interface: airplane mode may be on or there is no connection.';

  @override
  String get intranetAdapter => 'Adapter';

  @override
  String get intranetGateway => 'Gateway';

  @override
  String get intranetPrivateDnsOff =>
      'System Private DNS is off, so requests are handled locally and by the proxy according to the mode.';

  @override
  String get intranetNoDnsServer =>
      'No DNS server was read: the interface provides none, or there is no diagnostic channel here.';

  @override
  String get intranetPrimaryDns => 'Primary';

  @override
  String get intranetPrivateDns => 'Private DNS';

  @override
  String get intranetPortFooter =>
      'The port is bound only when the service starts, so restart it after changing the port; point devices on the same subnet at the address above to use local resolution.';

  @override
  String get intranetCopyAddressWithPort => 'Copy address (with port)';

  @override
  String get speedDetailTitle => 'Speed details';

  @override
  String get speedCurrentDownload => 'Current download';

  @override
  String get speedSamplingPaused => 'Sampling paused';

  @override
  String get speedLive => 'Live';

  @override
  String get speedSamplingHint =>
      'Sampled once per second; the chart shows the last minute.';

  @override
  String get speedCurrentUpload => 'Current upload';

  @override
  String get speedDownloadPeak => 'Download peak';

  @override
  String get speedUploadPeak => 'Upload peak';

  @override
  String get speedSamples => 'Samples';

  @override
  String get speedTodayTotal => 'Today\'s total';

  @override
  String get speedNoTrafficToday =>
      'The traffic store has no records for today yet.';

  @override
  String get speedTotal => 'Total';

  @override
  String get speedRateFooter =>
      'Rates come from the core data plane\'s live counters and cover only tunneled traffic; this app\'s own probes and speed tests are excluded. Today\'s totals come from the app traffic statistics, the same data as the Traffic page.';

  @override
  String get speedExpressSource =>
      'Express mode bypasses the core data plane, so there is no per-second rate; switch back to normal mode to restore it.';

  @override
  String get speedNoChannelSource =>
      'This environment has no rate channel (desktop or pure Dart tests), so no live rate can be read.';

  @override
  String get speedNoDataInMode => 'No rate data in this mode';

  @override
  String get speedWaitingSample => 'Waiting for the first sample';

  @override
  String get commonNoData => 'No data';

  @override
  String intranetModeNotListening(String mode) {
    return '$mode does not listen on the LAN, so other devices cannot use this as their DNS';
  }

  @override
  String intranetListeningOn(int port) {
    return 'Listening on 0.0.0.0:$port; point other devices\' DNS at the address above';
  }

  @override
  String intranetServiceStopped(int port) {
    return 'Service not started: port $port is bound once it starts';
  }

  @override
  String commonCopied(String text) {
    return 'Copied $text';
  }

  @override
  String intranetGatewaySuffix(String gateway) {
    return ' · Gateway $gateway';
  }

  @override
  String get speedTotalDash => 'Total —';

  @override
  String siteLatencyAliveRatio(int alive, int total) {
    return '$alive / $total reachable';
  }

  @override
  String siteLatencyLastRun(String ago) {
    return 'Last test $ago';
  }

  @override
  String siteLatencyProviderSuffix(String name) {
    return ' · Resolver $name';
  }

  @override
  String siteLatencySitesCount(int count) {
    return '$count sites';
  }

  @override
  String siteLatencyTestCategory(String category) {
    return 'Test $category';
  }

  @override
  String memorySystemShare(String percent) {
    return '$percent of the system';
  }

  @override
  String memorySystemUsedOf(String total, String used) {
    return 'System used $used / $total';
  }

  @override
  String get memoryNoChannel =>
      'Memory data is unavailable here (desktop or pure Dart tests).';

  @override
  String trafficStructureRateValue(
    String count,
    String latency,
    String percent,
  ) {
    return '$percent · $count times · $latency';
  }

  @override
  String trafficStructureShareValue(String count, String percent) {
    return '$percent · $count times';
  }

  @override
  String statusPausedSummary(String core, String mode) {
    return '$mode $core, timing paused';
  }

  @override
  String speedTotalsDown(String percent) {
    return 'Down $percent';
  }

  @override
  String speedTotalsUp(String percent) {
    return 'Up $percent';
  }

  @override
  String speedPeakAverage(String average, String peak) {
    return 'Peak $peak · Average $average';
  }

  @override
  String get intranetConnectHintSentence =>
      'Connect to Wi-Fi or Ethernet to see a usable address here.';

  @override
  String intranetModeNotListeningSentence(String mode) {
    return '$mode does not listen on the LAN, so other devices cannot use this as their DNS.';
  }

  @override
  String intranetPrivateDnsOn(String dns) {
    return 'System Private DNS is on ($dns); system lookups use an encrypted channel and may bypass the local service.';
  }

  @override
  String intranetSecondaryDns(int index) {
    return 'Secondary $index';
  }

  @override
  String intranetCopyAddressSemantics(String address) {
    return 'Copy address $address';
  }

  @override
  String speedTotalAccumulated(String value) {
    return 'Total $value';
  }

  @override
  String dashboardSitesFull(int count) {
    return 'The card holds $count sites; turn one off before adding another.';
  }

  @override
  String dashboardSitesRemaining(int count) {
    return 'You can add $count more sites.';
  }

  @override
  String dashboardSitesMax(int count) {
    return 'The card holds at most $count sites; deselect one first.';
  }

  @override
  String dashboardSitesPosition(int index) {
    return 'Position $index';
  }

  @override
  String siteLatencyFailedCount(int count) {
    return '$count failed';
  }

  @override
  String get siteLatencyDetailFooterLong =>
      'Each site gets three ICMP echo requests and the average is used; when system ping is unavailable the TCP handshake is used instead, marked with *, and reads slightly higher than the real round trip. This app\'s own traffic bypasses the VPN, so the physical network is measured.';

  @override
  String get homeLayerPowerButton => 'Start button';

  @override
  String get homeLayerPoem => 'Home poem';

  @override
  String get bottomBarHome => 'Home';

  @override
  String get bottomBarFeatureHub => 'Feature hub';

  @override
  String get bottomBarLogDashboard => 'Log dashboard';

  @override
  String get bottomBarAppTraffic => 'App traffic';

  @override
  String get bottomBarNetworkTools => 'Network tools';

  @override
  String get bottomBarSettings => 'Settings';

  @override
  String get bottomBarStyleFloating => 'Floating';

  @override
  String get bottomBarStyleDocked => 'Docked';

  @override
  String get tabTransitionNone => 'None';

  @override
  String get tabTransitionFade => 'Fade';

  @override
  String get tabTransitionSlide => 'Slide';

  @override
  String get tabTransitionScale => 'Scale';

  @override
  String get commonOff => 'Off';

  @override
  String get glassModeStandard => 'Standard';

  @override
  String get glassModeUltra => 'Ultra';

  @override
  String get previewBrightnessLight => 'Light';

  @override
  String get previewBrightnessDark => 'Dark';

  @override
  String get resolutionModeSingle => 'Single resolver';

  @override
  String get resolutionModeSmart => 'Smart selection';

  @override
  String get resolutionModeParallel => 'Parallel race';

  @override
  String get resolutionModePrimaryBackup => 'Primary + backup';

  @override
  String get workModeNormalTitle => 'Normal mode';

  @override
  String get workModeNormalBadge => 'Recommended';

  @override
  String get workModeNormalSummary =>
      'Full DNS resolution, block/allow lists, HTTPS inspection and network control';

  @override
  String get workModeServerTitle => 'Server mode';

  @override
  String get workModeServerBadge => 'Lightweight';

  @override
  String get workModeServerSummary =>
      'Pure DNS proxy with resolution acceleration, low power';

  @override
  String get workModeExpressTitle => 'Express mode';

  @override
  String get workModeExpressBadge => 'Express';

  @override
  String get workModeExpressSummary =>
      'Pure Kotlin DNS acceleration and rule filtering, Android 7+ (64-bit)';

  @override
  String get stateStopped => 'Stopped';

  @override
  String get stateStarting => 'Starting';

  @override
  String get stateRunning => 'Running';

  @override
  String get stateStopping => 'Stopping';

  @override
  String get powerStateError => 'Failed to start';

  @override
  String get serverStatusError => 'Error';

  @override
  String get logModeAllLabel => 'Log everything';

  @override
  String get logModeAllDescription =>
      'Requests, cache hits, races and blocks all go to the log';

  @override
  String get logModeBlockedLabel => 'Blocks and errors only';

  @override
  String get logModeBlockedDescription =>
      'Only blocked and failed requests are recorded';

  @override
  String get logModeOffLabel => 'Logging off';

  @override
  String get logModeOffDescription => 'Nothing is recorded, saving space';

  @override
  String get ipv6AutoLabel => 'Auto';

  @override
  String get ipv6AutoDescription => 'Enable depending on the current network';

  @override
  String get ipv6DisableLabel => 'Off';

  @override
  String get ipv6DisableDescription => 'No IPv6 inside the tunnel';

  @override
  String get ipv6PreferLabel => 'Prefer';

  @override
  String get ipv6PreferDescription => 'Prefer IPv6 and fall back when it fails';

  @override
  String get commonToday => 'Today';

  @override
  String get logWindowSevenDays => '7 days';

  @override
  String get logWindowSevenDaysRecent => 'Last 7 days';

  @override
  String get commonAll => 'All';

  @override
  String get trafficWindowWeek => 'This week';

  @override
  String get trafficWindowMonth => 'This month';

  @override
  String get trafficSortTotal => 'By total traffic';

  @override
  String get trafficSortDownload => 'By download traffic';

  @override
  String get trafficSortUpload => 'By upload traffic';

  @override
  String get davStatusIdle => 'Not connected';

  @override
  String get davStatusConnecting => 'Connecting';

  @override
  String get davStatusConnected => 'Connected';

  @override
  String get davStatusFailed => 'Connection failed';

  @override
  String get updateStageIdle => 'Not checked';

  @override
  String get updateStageChecking => 'Checking';

  @override
  String get updateStageUpToDate => 'Up to date';

  @override
  String get updateStageAvailable => 'Update available';

  @override
  String get updateStageDownloading => 'Downloading';

  @override
  String get updateStageDownloaded => 'Downloaded';

  @override
  String get ipQualityStageIdle => 'Not tested';

  @override
  String get ipQualityStageLoading => 'Checking';

  @override
  String get ipQualityStageLoaded => 'Check complete';

  @override
  String get ipQualityStageFailed => 'Check failed';

  @override
  String get subscriptionDeleted => 'Deleted';

  @override
  String get subscriptionDisabled => 'Disabled';

  @override
  String get subscriptionUngrouped => 'Ungrouped';

  @override
  String get providerNotTested => 'Not tested';

  @override
  String get elapsedJustNow => 'just now';

  @override
  String elapsedSecondsAgo(int count) {
    return '${count}s ago';
  }

  @override
  String elapsedMinutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String elapsedHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String elapsedDaysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String providerRaceSummary(String count, String names) {
    return '$count selected: $names';
  }

  @override
  String get rulesDbUnavailable =>
      'The rule database is not readable in this environment';

  @override
  String get agentApiKeyMissing =>
      'No usable API key yet. Fill one in under AI provider management and select that provider.';

  @override
  String get agentNoExtraInfo => '(no extra information)';

  @override
  String get agentNoLegacyDatabase =>
      'The legacy database was not found, so DNS and HTTPS logs cannot be read. Start the service once first.';

  @override
  String get agentExpressNoHttps =>
      'Express mode only accelerates DNS on a narrow route and produces no HTTPS inspection records';

  @override
  String get autoUpdateDisabled => 'Automatic updates are off';

  @override
  String get autoUpdateNoSubscriptions =>
      'No subscriptions to update automatically';

  @override
  String get autoUpdateNotDue => 'Not due yet';

  @override
  String get autoUpdateBusy =>
      'A manual update is running; this round is skipped';

  @override
  String get cleanupGroupRuntime => 'Runtime data';

  @override
  String get cleanupGroupWeights => 'Weight data';

  @override
  String get cleanupGroupRules => 'Rules and subscriptions';

  @override
  String get cleanupGroupStorage => 'Storage and security';

  @override
  String get cleanupGroupGuides => 'Guides and reset';

  @override
  String get backupReadFileFailed => 'The selected file cannot be read';

  @override
  String get caChannelUnavailable => 'The certificate channel is unavailable';

  @override
  String get caInstallUnavailable =>
      'The certificate installer cannot be opened';

  @override
  String get caDownloadDirUnavailable =>
      'The download directory is not writable';

  @override
  String get fontSystemDefault => 'System default';

  @override
  String get diagnosticsChannelUnavailable =>
      'The diagnostics channel is unavailable (no native implementation on this platform)';

  @override
  String get diagnosticsUnsupported => 'This diagnostic is not supported here';

  @override
  String get diagnosticsPingUnsupported => 'Ping probing is not supported here';

  @override
  String get diagnosticsTraceUnsupported =>
      'Route tracing is not supported here';

  @override
  String get diagnosticsDnsUnsupported => 'DNS queries are not supported here';

  @override
  String get diagnosticsEmptyTarget => 'Enter a target to probe';

  @override
  String get diagnosticsTargetHasSpace => 'The target cannot contain spaces';

  @override
  String get diagnosticsAnswerUpstream => 'Upstream resolution';

  @override
  String get diagnosticsAnswerCache => 'Cache hit';

  @override
  String get diagnosticsAnswerRewrite => 'Rewrite rule';

  @override
  String get diagnosticsAnswerBlocked => 'Blocked by a rule';

  @override
  String get diagnosticsAnswerFailed => 'Query failed';

  @override
  String get diagnosticsNoActiveNetwork => 'No active network';

  @override
  String get aiPresetMainland => 'Mainland providers';

  @override
  String get aiPresetOverseas => 'Overseas providers';

  @override
  String get aiPresetAggregator => 'Aggregators and local deployments';

  @override
  String get aiProviderConfigured => 'Configured providers';

  @override
  String get aiProviderExampleName => 'Example provider (edit me)';

  @override
  String get logSubscriptionDeleted => 'Deleted subscription';

  @override
  String get logRaceFastest => 'Fastest response';

  @override
  String get logRaceSmart => 'Smart selection';

  @override
  String get logRaceSequential => 'Try in order';

  @override
  String get logRaceSingle => 'Single resolver';

  @override
  String get providerNoProviderSelected => 'No resolver selected';

  @override
  String get onDemandDisabled => 'On-demand connection is off; nothing changed';

  @override
  String get onDemandServerMode =>
      'Server mode uses no tunnel; nothing changed';

  @override
  String get onDemandUnknownSsid =>
      'The current Wi-Fi cannot be read; nothing changed';

  @override
  String get onDemandSameNetwork =>
      'The network has not changed; the VPN state stays as it is';

  @override
  String get onDemandNoWifi => 'Not on Wi-Fi, so the VPN was disconnected';

  @override
  String get onDemandStarted => 'Matched the allow list; the VPN was started';

  @override
  String get onDemandAlreadyRunning =>
      'Matched the allow list; the VPN is running';

  @override
  String get onDemandStopped =>
      'This network is not on the allow list; the VPN was disconnected';

  @override
  String get onDemandAlreadyStopped =>
      'This network is not on the allow list; the VPN is not running';

  @override
  String get onDemandBusy => 'The VPN is switching state; try again later';

  @override
  String get onDemandNeedsConsent =>
      'Matched the allow list; waiting for system VPN consent';

  @override
  String get speedTestSelectProvider => 'Select at least one resolver to test';

  @override
  String get speedTestEmptyDomain => 'Enter a domain to test';

  @override
  String get imagePickerUnavailable =>
      'No image picker is available on this device';

  @override
  String get serverModeRequired => 'Switch to server mode first';

  @override
  String get serverStartFailed => 'The DNS service failed to start';

  @override
  String get serverStartTimeout => 'The DNS service timed out starting';

  @override
  String get recognitionInvalidConfig =>
      'The cloud roster configuration is invalid';

  @override
  String get recognitionGithubInterrupted =>
      'The connection to GitHub was interrupted; try again later';

  @override
  String get recognitionGithubTimeout =>
      'Connecting to GitHub timed out; check the network and retry';

  @override
  String get recognitionNetworkUnavailable =>
      'No network, so the roster cannot be updated';

  @override
  String get recognitionUpdateFailed => 'The roster update failed';

  @override
  String get subscriptionNotFound =>
      'The subscription does not exist or the database is unavailable';

  @override
  String get subscriptionDatabaseUnavailable =>
      'The subscription database is unavailable';

  @override
  String get subscriptionRuleDbUnavailable =>
      'The rule database is unavailable, so downloaded rules cannot be stored';

  @override
  String get subscriptionUpdateFailed => 'Update failed';

  @override
  String get subscriptionLocalFileUnreadable => 'The local file cannot be read';

  @override
  String get subscriptionLocalRuleDbUnavailable =>
      'The rule database is unavailable, so local rules cannot be stored';

  @override
  String get subscriptionNothingToUpdate => 'No subscriptions to update';

  @override
  String get subscriptionPickRuleFile => 'Pick a rule file';

  @override
  String get subscriptionPickTxtFile =>
      'Pick a rule file with the .txt extension';

  @override
  String get subscriptionLegacyDatabaseMissing =>
      'The subscription database is unavailable (the 1.4.3 database was not found)';

  @override
  String get subscriptionThisFile => 'This file';

  @override
  String get subscriptionThisLink => 'This subscription link';

  @override
  String get subscriptionLocalRuleFile => 'Local rule file';

  @override
  String get webdavEmptyCredentials =>
      'The server address and user name cannot be empty';

  @override
  String get webdavDirectoryCreated =>
      'The directory did not exist and was created';

  @override
  String get webdavUploaded => 'Uploaded to the cloud';

  @override
  String get webdavNoBackup => 'There is no backup file in the cloud yet';

  @override
  String get webdavDownloaded => 'The backup was retrieved from the cloud';

  @override
  String get updateCheckFirst => 'Check for updates first';

  @override
  String get updateDownloadFirst => 'Download the update package first';

  @override
  String get updateInstallerUnavailable =>
      'The system installer cannot be opened; try again later';

  @override
  String get workModeNoDataPlane => 'This work mode has no data plane yet';

  @override
  String get workModeNoVpnConsent => 'VPN consent was not granted';

  @override
  String get workModeStartTimeout => 'The service timed out starting';

  @override
  String get workModeVpnStartFailed => 'The VPN failed to start';

  @override
  String get aiProviderZhipu => 'Zhipu GLM';

  @override
  String get aiProviderMoonshot => 'Kimi (Moonshot)';

  @override
  String get aiProviderDashscope => 'Aliyun Bailian (Qwen)';

  @override
  String get aiProviderVolcengine => 'Volcengine Ark (Doubao)';

  @override
  String get aiProviderQianfan => 'Baidu Qianfan (ERNIE)';

  @override
  String get aiProviderStepfun => 'StepFun';

  @override
  String get aiProviderSiliconflow => 'SiliconFlow';

  @override
  String get aiProviderOllamaLocal => 'Ollama (local)';

  @override
  String rulesReadFailed(String detail) {
    return 'Failed to read app rules: $detail';
  }

  @override
  String autoUpdateChecked(int count) {
    return 'Checked $count subscriptions';
  }

  @override
  String caChannelUnavailableDetail(String detail) {
    return 'The certificate channel is unavailable: $detail';
  }

  @override
  String caReadFailedCode(String code) {
    return 'Failed to read the root certificate ($code)';
  }

  @override
  String caReadFailed(String detail) {
    return 'Failed to read the root certificate: $detail';
  }

  @override
  String agentAnalysisFailed(String detail) {
    return 'Analysis failed: $detail';
  }

  @override
  String diagnosticsFailedCode(String code) {
    return 'The diagnostic failed ($code)';
  }

  @override
  String diagnosticsFailed(String detail) {
    return 'The diagnostic failed: $detail';
  }

  @override
  String subscriptionDeletedWithId(int id) {
    return 'Deleted subscription #$id';
  }

  @override
  String providerLatencyValue(int value) {
    return '${value}ms';
  }

  @override
  String providerRaceSummaryNames(int count, String names) {
    return '$count selected: $names';
  }

  @override
  String get providerNamesSeparator => ', ';

  @override
  String recognitionInvalidConfigKept(String detail) {
    return 'The cloud roster configuration is invalid ($detail); the local cache is kept';
  }

  @override
  String recognitionFetchFailed(String detail) {
    return 'Fetching the cloud roster failed ($detail)';
  }

  @override
  String recognitionUpdateFailedDetail(String detail) {
    return 'The roster update failed: $detail';
  }

  @override
  String subscriptionAlreadyExists(String kind, String what) {
    return '$what already exists as $kind';
  }

  @override
  String subscriptionUpdatedCount(int count) {
    return '$count updated';
  }

  @override
  String subscriptionUnchangedCount(int count) {
    return '$count unchanged';
  }

  @override
  String subscriptionFailedCount(int count) {
    return '$count failed';
  }

  @override
  String subscriptionAlreadyExistsNamed(String kind, String name, String what) {
    return '$what already exists as $kind (\"$name\")';
  }

  @override
  String get commonBypass => 'Bypass';

  @override
  String get commonRewrite => 'Rewrite';

  @override
  String get cleanupLogs => 'Delete request logs';

  @override
  String get cleanupTraffic => 'Delete traffic statistics';

  @override
  String get cleanupCrash => 'Delete crash logs';

  @override
  String get cleanupDnsCache => 'Delete DNS cache';

  @override
  String get cleanupProviderWeights => 'Restore default DNS weights';

  @override
  String get cleanupBootstrapWeights => 'Restore Bootstrap weights';

  @override
  String get cleanupDomainRules => 'Delete all domain rules';

  @override
  String get cleanupAddressRules => 'Delete all address rules';

  @override
  String get cleanupSubscriptions => 'Delete all rule subscriptions';

  @override
  String get cleanupAppRules => 'Reset the app control list';

  @override
  String get cleanupOutboundProxy => 'Reset the outbound proxy settings';

  @override
  String get cleanupCaCertificate => 'Reset the HTTPS inspection certificate';

  @override
  String get cleanupDownloadCache => 'Clear download and temporary caches';

  @override
  String get cleanupCustomBackground => 'Clear the custom background cache';

  @override
  String get cleanupSettingsGuides => 'Reset every onboarding guide';

  @override
  String get cleanupAllData => 'Clear all local data';

  @override
  String cleanupDoneItems(String action, int count, String detail) {
    return '$action: $count items$detail';
  }

  @override
  String cleanupDoneEmpty(String action) {
    return '$action: nothing to clean up';
  }

  @override
  String get blockResponseNxdomain => 'Return NXDOMAIN';

  @override
  String get blockResponseNxdomainDescription =>
      'Answers that the domain does not exist, with a 5-minute negative cache to reduce repeated queries';

  @override
  String get blockResponseNodata => 'Return NODATA';

  @override
  String get blockResponseNodataDescription =>
      'Answers that the domain exists but has no such record, with a 5-minute negative cache';

  @override
  String get blockResponseRefused => 'Return REFUSED';

  @override
  String get blockResponseRefusedDescription =>
      'Answers that the server refused the query, with no cached record';

  @override
  String get blockResponseZeroAddress => 'Return 0.0.0.0 / ::';

  @override
  String get blockResponseZeroAddressDescription =>
      'A answers 0.0.0.0, AAAA answers ::, other types get an empty answer';

  @override
  String get subscriptionSourceRemote => 'Remote subscription';

  @override
  String get subscriptionSourceLocal => 'Local file';

  @override
  String get subscriptionKindDomain => 'Domain list rules';

  @override
  String get subscriptionKindHosts => 'Hosts rules';

  @override
  String logRowDirect(String protocol) {
    return '$protocol direct';
  }

  @override
  String logRowDirectWithPackage(String package, String protocol) {
    return '$protocol direct · $package';
  }

  @override
  String get logRowCacheHit => 'cache hit';

  @override
  String get logRowNoAuthority => 'no authority';

  @override
  String get cachePresetConservativeName => 'Conservative';

  @override
  String get cachePresetConservativeSummary => 'Follow the server\'s TTL';

  @override
  String get cachePresetConservativeDescription =>
      'Uses the TTL the DNS server returns and never extends it. Best for people who switch networks often or need real-time answers.';

  @override
  String get cachePresetStandardName => 'Standard';

  @override
  String get cachePresetStandardSummary =>
      'At most 1 hour, short records at least 1 minute';

  @override
  String get cachePresetStandardDescription =>
      'Cuts repeated queries without letting records lag behind. When resolution fails, records up to 5 minutes old may be reused as a stopgap.';

  @override
  String get cachePresetAggressiveName => 'High hit rate';

  @override
  String get cachePresetAggressiveSummary =>
      'At most 6 hours, short records at least 2 minutes';

  @override
  String get cachePresetAggressiveDescription =>
      'Favours fewer network requests and better usability on weak networks. Domain changes may take longer to show up.';

  @override
  String get cacheDisabledSummary => 'Off · every lookup goes upstream';

  @override
  String get upstreamNameRequired => 'Enter a name';

  @override
  String get upstreamAddressRequired => 'Enter an address';

  @override
  String get upstreamDohNeedsHttps => 'A DoH address must start with https://';

  @override
  String get upstreamDohInvalidUrl => 'The DoH address is not a valid URL';

  @override
  String get upstreamPortRange => 'The port must be between 1 and 65535';

  @override
  String get upstreamIpv6Invalid => 'The IPv6 address is not valid';

  @override
  String get upstreamPresetAliyun => 'Aliyun';

  @override
  String get upstreamPresetTencent => 'Tencent Cloud DNSPod';

  @override
  String get upstreamPresetByteDance => 'ByteDance';

  @override
  String cleanupFailed(String detail) {
    return 'Cleanup failed: $detail';
  }

  @override
  String get cleanupProxyRestored => 'Direct connection restored';

  @override
  String get cleanupCaNeedsReimport =>
      'The certificate must be regenerated and installed again';

  @override
  String get hubCategoryDns => 'DNS services';

  @override
  String get hubProviderManagement => 'Resolver management';

  @override
  String get hubProviderManagementDescription =>
      'Configure and manage DoH, DoT and classic DNS resolvers';

  @override
  String get hubBootstrap => 'Bootstrap DNS';

  @override
  String get hubBootstrapDescription =>
      'Configure the bootstrap DNS nodes used to resolve encrypted upstream hostnames';

  @override
  String get hubResolution => 'Resolution mode';

  @override
  String get hubResolutionDescription =>
      'Pick single, smart, fastest-response or try-in-order resolution';

  @override
  String get hubCache => 'Cache settings';

  @override
  String get hubCacheDescription =>
      'Configure the DNS cache switch, policy and TTL bounds';

  @override
  String get hubCategoryRules => 'Policy and rules';

  @override
  String get hubRuleControl => 'Rule control';

  @override
  String get hubRuleControlDescription =>
      'Manage the blocking switches and online rule subscriptions in one place';

  @override
  String get hubBlocklist => 'Block list';

  @override
  String get hubBlocklistDescription =>
      'Your own blocked domains; matches get the block response';

  @override
  String get hubAllowlist => 'Allow list';

  @override
  String get hubAllowlistDescription =>
      'Your own allowed domains, exempt from every rule';

  @override
  String get hubRewrite => 'Rewrite list';

  @override
  String get hubRewriteDescription =>
      'Point custom domains at a specific IPv4/IPv6 address or CNAME';

  @override
  String get hubCategoryNetwork => 'Network control';

  @override
  String get hubAppTraffic => 'App traffic';

  @override
  String get hubAppTrafficDescription =>
      'Connection counts and up/down traffic per app';

  @override
  String get hubAppRules => 'Per-app rules';

  @override
  String get hubAppRulesDescription =>
      'Give one app its own domain allow list and network rules';

  @override
  String get hubBlockedApps => 'Blocked apps';

  @override
  String get hubBlockedAppsDescription =>
      'Block all outbound traffic of the chosen apps at the local tunnel';

  @override
  String get hubExcludedApps => 'Excluded apps';

  @override
  String get hubExcludedAppsDescription =>
      'Let the chosen apps bypass DITING and use the network directly';

  @override
  String get hubCategoryAdvanced => 'Advanced and diagnostics';

  @override
  String get hubHttpsInspection => 'HTTPS inspection';

  @override
  String get hubHttpsInspectionDescription =>
      'Decrypt and inspect HTTP(S) traffic of selected apps, with domain and URL filtering';

  @override
  String get hubOutboundProxy => 'Outbound proxy';

  @override
  String get hubOutboundProxyDescription =>
      'Forward filtered traffic to a local SOCKS5 or HTTP proxy';

  @override
  String get hubDiagnostics => 'Network diagnostics';

  @override
  String get hubDiagnosticsDescription =>
      'DNS queries, ping latency tests and connectivity diagnostics';

  @override
  String get hubAiAnalysis => 'AI analysis';

  @override
  String get hubAiAnalysisDescription =>
      'Configure an LLM endpoint and key for log review and traffic analysis';

  @override
  String get hubCategoryInterface => 'Interface and settings';

  @override
  String get hubAppearance => 'Appearance';

  @override
  String get hubAppearanceDescription =>
      'Customise the day/night mode, palette, component opacity and wallpaper';

  @override
  String get hubProviderVisibility => 'Resolver visibility';

  @override
  String get hubProviderVisibilityDescription =>
      'Choose which resolvers appear in the home resolver list';

  @override
  String get hubHiddenFeatures => 'Hidden features';

  @override
  String get hubHiddenFeaturesDescription =>
      'Choose which cards the feature hub shows; nothing changes at runtime';

  @override
  String get hubOtherSettings => 'Other settings';

  @override
  String get hubOtherSettingsDescription =>
      'Global options such as language, foreground/background behaviour and notifications';

  @override
  String get hubCategoryData => 'Data and maintenance';

  @override
  String get hubLogs => 'Logs';

  @override
  String get hubLogsDescription =>
      'Live resolution statistics, request details and log export';

  @override
  String get hubBackup => 'Backup and migration';

  @override
  String get hubBackupDescription =>
      'Export and import resolvers, rule subscriptions and personal settings';

  @override
  String get hubDataCleanup => 'Data cleanup';

  @override
  String get hubDataCleanupDescription =>
      'Delete caches, logs or domain and address filter rules';

  @override
  String get hubTroubleshooting => 'Troubleshooting';

  @override
  String get hubTroubleshootingDescription =>
      'Export crash logs and capture runtime logs to send to the developer';

  @override
  String get hubCategoryAbout => 'About DITING';

  @override
  String get hubAbout => 'About';

  @override
  String get hubAboutDescription =>
      'Version information, update checks, source links and contributor lists';

  @override
  String get hubSponsor => 'Sponsor';

  @override
  String get hubSponsorDescription =>
      'Support the ongoing maintenance and development of DITING';

  @override
  String get hubSponsors => 'Sponsors';

  @override
  String get hubSponsorsDescription =>
      'Thanks to everyone who supports the project';

  @override
  String get hubContributors => 'Contributors';

  @override
  String get hubContributorsDescription =>
      'Thanks to everyone who contributed code and ideas';

  @override
  String get fontSizeSmall => 'Small';

  @override
  String get fontSizeStandard => 'Standard';

  @override
  String get fontSizeLarge => 'Large';

  @override
  String get fontSizeExtraLarge => 'Extra large';

  @override
  String get fontSizeFooter =>
      'The text size scales body copy, titles and list rows together without touching system settings; the layout follows it immediately, no restart needed.';

  @override
  String get fontSizePreview => 'Live preview';

  @override
  String get appearancePoem => 'Hear every sound, tell clear from murky';

  @override
  String get appearancePoemBody =>
      'Connectivity, rule matches and device state, all explained on one page.';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get appearanceInterfaceSection => 'Interface';

  @override
  String get appearanceHomeOpacitySubtitle =>
      'Opacity of interactive components and text';

  @override
  String get appearancePureBlackOn =>
      'Dark surfaces collapse to pure black, saving power on OLED';

  @override
  String get appearancePureBlackOff => 'Available once dark mode is on';

  @override
  String get appearanceHomeSection => 'Home content';

  @override
  String get appearanceHomeSentenceSubtitle =>
      'One sentence each for running and stopped';

  @override
  String get appearanceNotification => 'Notification';

  @override
  String get appearanceNotificationSubtitle =>
      'Persistent notification, live rate and custom text';

  @override
  String get appearanceBackgroundSection => 'Background and motion';

  @override
  String get appearanceHapticSubtitle =>
      'A short vibration when switching tabs';

  @override
  String get appearanceBottomBarStyleFloating => 'Floating above the page';

  @override
  String get appearanceBottomBarStyleDocked => 'Docked at the bottom';

  @override
  String get appearanceTabTransitionSubtitle =>
      'Animation used when switching tabs';

  @override
  String get appearanceMotionFooter =>
      'Style, animation and glass only apply to the floating bar; the docked bar stays solid.';

  @override
  String get appearancePaletteGoldLegacy =>
      'Stored value keeps the legacy indigo';

  @override
  String get appearancePaletteFooter =>
      'The palette only supplies a seed; the screen shows the full HCT-derived role set. The legacy app had no custom picker, so there is none here.';

  @override
  String fontFamilySizeSubtitle(String percent) {
    return '$percent% now';
  }

  @override
  String get fontFamilySystemDefault =>
      'Follows the host platform\'s interface font; the safest choice';

  @override
  String get fontFamilyImported => 'Imported third-party font';

  @override
  String get fontFamilyEmpty =>
      'No imported fonts yet. Once imported you can switch here; font files stay on this device.';

  @override
  String get fontFamilyFooter =>
      'Imported fonts only affect this device and fall back to the system default when deleted.';

  @override
  String get fontFamilyLocalOnly =>
      'The choice only affects this device and never changes server-side rules.';

  @override
  String get fontFamilyImportFailed => 'Import failed';

  @override
  String get fontFamilyDeleteTitle => 'Delete font';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String fontFamilyDeleteConfirm(String name) {
    return 'After deleting \"$name\", the interface falls back to the system default font.';
  }

  @override
  String get fontFamilyImport => 'Import font';

  @override
  String get fontFamilyReading => 'Reading the font file…';

  @override
  String get fontFamilyPickFile => 'Pick a TTF / OTF file on this device';

  @override
  String get notificationPersistentSection => 'Persistent notification';

  @override
  String get notificationPersistentFooter =>
      'When off, no persistent notification is shown while the service runs, so the system may reclaim the process sooner.';

  @override
  String get notificationPersistent => 'Persistent notification';

  @override
  String get notificationPersistentSubtitle =>
      'Keeps an unswipeable notification while the service runs';

  @override
  String get notificationShowSpeedSubtitle =>
      'Shows the current up/down rate in the notification';

  @override
  String get notificationStatsSection => 'Notification details';

  @override
  String get notificationStatsEmpty =>
      'No details shown; the notification keeps only the status text';

  @override
  String get notificationStatsFooter =>
      'Counts start when the service starts and do not depend on the log mode. Press and drag an enabled item to reorder it. Speed and server modes have no live rate, so that item is left out there.';

  @override
  String get notificationStatsHidden => 'Hidden items';

  @override
  String get notificationStatTotal => 'Requests';

  @override
  String get notificationStatSpeed => 'Live rate';

  @override
  String get notificationStatTotalSubtitle =>
      'All requests handled in this run (DNS and HTTPS)';

  @override
  String get notificationStatPassedSubtitle =>
      'Requests let through, including rewritten answers';

  @override
  String get notificationStatFilteredSubtitle =>
      'Requests blocked by the filter rules';

  @override
  String get notificationStatFailedSubtitle =>
      'Requests that failed to resolve or be handled';

  @override
  String get notificationStatCachedSubtitle =>
      'Requests answered from the local cache';

  @override
  String get notificationStatRewrittenSubtitle =>
      'Requests that matched a rewrite rule';

  @override
  String get notificationTextRunning => 'When the DNS service is on';

  @override
  String get notificationTextStopped => 'When the DNS service is off';

  @override
  String get notificationTextHint => 'Leave empty to use the default text';

  @override
  String get notificationTextSection => 'Notification text';

  @override
  String get notificationTextFooter =>
      'Empty fields use the default text; the wording only affects the notification, never the service.';

  @override
  String get notificationPermissions => 'Permissions';

  @override
  String get notificationSystemPermission => 'System notification permission';

  @override
  String get notificationSystemPermissionSubtitle =>
      'Opens the system notification settings';

  @override
  String get backgroundTitle => 'App background';

  @override
  String get backgroundSection => 'Custom background';

  @override
  String get backgroundFooter =>
      'Wallpapers stay on this device and are never exported with backups.';

  @override
  String get backgroundEnable => 'Enable custom background';

  @override
  String get backgroundPickFirst => 'Add an image first';

  @override
  String get backgroundBehindPages => 'Puts a wallpaper behind every page';

  @override
  String get backgroundAddImage => 'Add image';

  @override
  String get backgroundAddImageSubtitle => 'Pick one from the gallery';

  @override
  String get backgroundAdded => 'Added wallpapers';

  @override
  String get backgroundAddedFooter => 'Tap to switch, long-press to delete.';

  @override
  String get backgroundEmpty => 'No background image yet';

  @override
  String get backgroundEmptyDescription =>
      'Tap \"Add image\" and pick one from the gallery.';

  @override
  String get backgroundDeleteTitle => 'Delete wallpaper';

  @override
  String get backgroundDeleteConfirm => 'Delete this wallpaper?';

  @override
  String get foregroundTitle => 'Foreground and background';

  @override
  String get foregroundPrivacySection => 'Background and privacy';

  @override
  String get foregroundPrivacyFooter =>
      'Hiding in the background removes the app from the recent tasks list; open it again from the home screen.';

  @override
  String get foregroundHide => 'Hide in background';

  @override
  String get foregroundHideSubtitle => 'Not shown in the recent tasks list';

  @override
  String get foregroundRouting => 'Routing';

  @override
  String get foregroundBypassLan => 'Bypass LAN';

  @override
  String get foregroundBypassLanSubtitle =>
      'Local subnets and this device stay off the tunnel';

  @override
  String get foregroundStability => 'Stability';

  @override
  String get foregroundBatteryFooter =>
      'With battery optimisation off, the system is less likely to reclaim the service process.';

  @override
  String get foregroundIgnoreBattery => 'Ignore battery optimisation';

  @override
  String get foregroundIgnoreBatterySubtitle =>
      'Ask to whitelist this app in the system';

  @override
  String get dayNightTitle => 'Day/night mode';

  @override
  String get dayNightFollowSystemDescription =>
      'Switches together with the system dark mode';

  @override
  String get dayNightFooter =>
      'Pure black only applies in dark mode; its switch lives in the Interface group of Appearance.';

  @override
  String get homeOpacityTitle => 'Home opacity';

  @override
  String get homeOpacityComponents => 'Interactive components';

  @override
  String get homeOpacityComponentsFooter =>
      'Opacity only affects visibility, not the tap targets of these components.';

  @override
  String get homeOpacityText => 'Text';

  @override
  String get bottomBarHomeSubtitle => 'Home and dashboard';

  @override
  String get bottomBarFeatureHubSubtitle => 'Every feature entry point';

  @override
  String get bottomBarLogDashboardSubtitle => 'Log dashboard';

  @override
  String get bottomBarAppTrafficSubtitle => 'App traffic ranking';

  @override
  String get bottomBarNetworkToolsSubtitle => 'Speed tests and diagnostics';

  @override
  String get bottomBarSettingsSubtitle => 'All settings';

  @override
  String get bottomBarMinimumHint => 'Keep at least 2 items in the bottom bar';

  @override
  String get bottomBarCustomTitle => 'Bottom bar';

  @override
  String bottomBarItemsHeader(String count, String max) {
    return 'Bottom bar items ($count/$max)';
  }

  @override
  String bottomBarDragHint(String max) {
    return 'Drag by the handle on the right or long-press a row to reorder; the order is the bottom bar order from left to right. Keep 2 to $max items: the floating bar splits its width evenly and more would squeeze the icons.';
  }

  @override
  String get bottomBarDisabled => 'Not in use';

  @override
  String get bottomBarNewItemFooter =>
      'Newly enabled items go to the far right.';

  @override
  String get bottomBarFeel => 'Feel';

  @override
  String get homeSentenceTitle => 'Home sentences';

  @override
  String get homeSentenceFooter =>
      'Both fields may stay empty; when empty, no sentence is shown in that state. The sentence appears once, below the power button.';

  @override
  String get appearancePaletteTitle => 'Palette';

  @override
  String get appearancePaletteInfoLabel => 'Palette';

  @override
  String get appearancePaletteBody =>
      'The palette only supplies a seed; the screen shows the full HCT-derived role set. The legacy app had no custom picker, so there is none here.';

  @override
  String get dayNightInfoLabel => 'Mode';

  @override
  String get appearanceFontSizeLabel => 'Text size';

  @override
  String appearanceFontSizeCurrent(int percent) {
    return '$percent% now';
  }

  @override
  String get appearanceFontSection => 'Font';

  @override
  String appearanceFontImported(String name) {
    return 'Imported $name';
  }

  @override
  String appearanceFontDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String appearanceBottomBarMax(int max) {
    return 'At most $max bottom bar items';
  }

  @override
  String appearanceBottomBarHeader(int count, int max) {
    return 'Bottom bar items ($count/$max)';
  }

  @override
  String appearanceBottomBarDragBody(int max) {
    return 'Drag by the handle on the right or long-press a row to reorder; the order is the bottom bar order from left to right. Keep 2 to $max items: the floating bar splits its width evenly and more would squeeze the icons.';
  }

  @override
  String appearanceBottomBarSelected(int count) {
    return '$count selected; 2–4 are allowed';
  }

  @override
  String get appearanceHaptic => 'Bottom bar haptics';

  @override
  String get appearancePureBlack => 'Pure black';

  @override
  String get appearanceBottomBarStyle => 'Bottom bar style';

  @override
  String get appearanceTabTransition => 'Tab transition';

  @override
  String get appearanceLiquidGlass => 'Liquid glass';

  @override
  String get fontFamilyTitle => 'Font settings';

  @override
  String get fontSizeRestoreDefaults => 'Restore defaults';

  @override
  String get fontFamilyHapticSubtitle =>
      'A short vibration when switching tabs';

  @override
  String get ruleKindBlockTitle => 'Block list';

  @override
  String get ruleKindBlockSummary => 'Block matching domains';

  @override
  String get ruleKindAllowTitle => 'Allow list';

  @override
  String get ruleKindAllowSummary => 'Let matching domains through';

  @override
  String get ruleKindRewriteTitle => 'Rewrite';

  @override
  String get ruleKindRewriteSummary => 'Rewrite DNS answers';

  @override
  String get ruleSourceUser => 'User defined';

  @override
  String get ruleSourceSubscription => 'Rule subscription';

  @override
  String get ruleSourcePreset => 'Built-in preset';

  @override
  String get rulePatternRequired => 'The rule cannot be empty';

  @override
  String get ruleAllowNeedsAllowlist =>
      'This is an allow rule; add it to the allow list instead';

  @override
  String get ruleAlreadyExists => 'This rule already exists';

  @override
  String get ruleDomainHint => 'Domain, e.g. cdn.example.com';

  @override
  String get ruleTargetRequired => 'The target cannot be empty';

  @override
  String get ruleTargetHint => 'Target, e.g. 10.0.0.8';

  @override
  String get ruleImportant => 'Important';

  @override
  String get ruleReadOnly => 'Read only';

  @override
  String get ruleEdit => 'Edit rule';

  @override
  String get ruleDelete => 'Delete rule';

  @override
  String get batchImportDone => 'Import finished';

  @override
  String get batchAddTitle => 'Add rules in bulk';

  @override
  String get batchTarget => 'Import into';

  @override
  String get batchTargetTable => 'Target rule list';

  @override
  String get batchTargetTableSubtitle =>
      'Imported rules go into the selected list';

  @override
  String get batchPlaceholder =>
      'One rule per line, for example:\n||ads.example.com^\n\nBlank lines are ignored and duplicates are skipped automatically.';

  @override
  String get batchImportable => 'Importable';

  @override
  String get batchDuplicated => 'Duplicated';

  @override
  String get batchInvalid => 'Invalid';

  @override
  String get batchInvalidHeader => 'These rules failed validation';

  @override
  String get batchDuplicateHeader => 'Already present, will be skipped';

  @override
  String get ruleClearCustomTitle => 'Clear custom rules';

  @override
  String get commonClearAll => 'Clear';

  @override
  String get ruleResetDefault => 'Reset the default allow list';

  @override
  String get commonReset => 'Reset';

  @override
  String get rulePresetProtectedTitle => 'Preset rules are protected';

  @override
  String get ruleAllowEditTitle => 'Allow editing the default allow list?';

  @override
  String get ruleAllowEditConfirm => 'Enable anyway';

  @override
  String get ruleTotal => 'Total rules';

  @override
  String get ruleEnabled => 'Enabled';

  @override
  String get ruleRewriteEntries => 'Rewrite entries';

  @override
  String get ruleCustom => 'Custom';

  @override
  String get ruleAllowEditDefault => 'Allow editing the default allow list';

  @override
  String get ruleAllowEditDefaultSubtitle =>
      'When off, preset rules are read-only so the allow list cannot widen by accident';

  @override
  String get ruleNoMatch => 'No matching rules';

  @override
  String get ruleNoMatchDescription => 'Try another keyword or filter';

  @override
  String get ruleAll => 'All';

  @override
  String get formIssuesTitle => 'A few things need fixing';

  @override
  String get formSave => 'Save';

  @override
  String get formProcessing => 'Working…';

  @override
  String get formAdd => 'Add';

  @override
  String get formDelete => 'Delete';

  @override
  String get formHelp => 'Help';

  @override
  String get formGotIt => 'Got it';

  @override
  String get rulePatternHint => 'Rule text, e.g. ||ads.example.com^';

  @override
  String ruleBatchImported(String count, int kind) {
    return 'Imported $count rules into $kind.';
  }

  @override
  String ruleBatchSkippedDuplicates(int count) {
    return 'Skipped $count duplicate rules.';
  }

  @override
  String ruleBatchAllowRejected(int count) {
    return '$count allow rules (with #@#) were not imported: allow rules belong in the allow list.';
  }

  @override
  String ruleBatchImportCount(int count) {
    return 'Import $count';
  }

  @override
  String ruleBatchMoreDuplicates(int count) {
    return 'and $count more';
  }

  @override
  String ruleAddForKind(String kind) {
    return 'Add a $kind rule';
  }

  @override
  String get ruleEditDefaultPreset => 'Edit a default preset rule';

  @override
  String ruleEditForKind(String kind) {
    return 'Edit a $kind rule';
  }

  @override
  String ruleDeletePresetMessage(String pattern) {
    return '\"$pattern\" is a built-in preset rule; resetting the defaults restores it.';
  }

  @override
  String ruleDeleteSubscriptionMessage(String name, String pattern) {
    return '\"$pattern\" comes from the subscription \"$name\" and may return on the next update.';
  }

  @override
  String ruleDeleteUserMessage(String pattern) {
    return 'Delete \"$pattern\"? This cannot be undone.';
  }

  @override
  String ruleClearCustomMessage(String kind) {
    return 'All user-defined $kind rules will be deleted; subscription and preset rules are untouched.';
  }

  @override
  String get ruleResetMessage =>
      'Restores the built-in preset rules; rules you added and subscription rules are kept.';

  @override
  String get rulePresetProtectedMessage =>
      'Default allow list rules are read-only. Turn on \"Allow editing the default allow list\" at the top of the page before changing or deleting them.';

  @override
  String get ruleAllowEditMessage =>
      'The allow list lets traffic through, so changing it may pass traffic that should be blocked. Enable this only if you understand the risk.';

  @override
  String ruleTally(int matched, int enabled) {
    return '$matched total · $enabled enabled';
  }

  @override
  String ruleNoRulesForKind(String kind) {
    return 'No $kind rules yet';
  }

  @override
  String ruleClearCustomForKind(String kind) {
    return 'Clear custom $kind';
  }

  @override
  String get subsPickTxt => 'Pick a rule file with the .txt extension';

  @override
  String get subsNoPersistPermission =>
      'The system did not grant persistent read access, so the file must be picked again on update';

  @override
  String get subsGroupNameRequired => 'The group name cannot be empty';

  @override
  String get subsEdit => 'Edit subscription';

  @override
  String get subsAdd => 'Add subscription';

  @override
  String get subsSaveTooltip => 'Save subscription';

  @override
  String get subsInfoSection => 'Subscription details';

  @override
  String get subsSourceType => 'Source type';

  @override
  String get subsSourceLocalPick => 'Pick a .txt file from storage';

  @override
  String get subsSourceRemoteDownload => 'Download the rule body from a URL';

  @override
  String get subsLocalRuleFile => 'Local rule file';

  @override
  String get subsLocalFileSubscription => 'Local file subscription';

  @override
  String get subsPickFile => 'Pick a rule file';

  @override
  String get subsLocalFileHint => 'Only .txt; tap to pick from storage';

  @override
  String get subsLocalFileRepick => 'Tap to pick another file';

  @override
  String get subsChoose => 'Choose';

  @override
  String get subsNameOptional => 'Name (optional)';

  @override
  String get subsNameEmptyFileName => 'Leave empty to use the file name';

  @override
  String get subsUrl => 'Subscription URL';

  @override
  String get subsNameEmptyUrlTail =>
      'Leave empty to use the last part of the URL';

  @override
  String get subsRuleType => 'Rule type';

  @override
  String get subsKindHostsHint =>
      'Only hosts entries and CNAME rewrites are imported';

  @override
  String get subsKindDomainHint =>
      'Domain rules and allow/block lists are imported';

  @override
  String get subsGroupHint =>
      'Groups only affect filtering and bulk updates on this page; you can change them later.';

  @override
  String get subsNewGroupShort => '+ New';

  @override
  String get subsMirrorTemplateFooter =>
      'A mirror rewrites the subscription URL with its prefix, which speeds up slow sources such as GitHub.';

  @override
  String get subsAddMirrorTemplate => 'Add a mirror template';

  @override
  String get subsAddMirrorTemplateSubtitle =>
      'No templates yet; save a commonly used mirror prefix first';

  @override
  String get subsMirrorFooter =>
      'Downloads try the mirror first and fall back to the original URL when enabled.';

  @override
  String get subsUseMirrorTemplate => 'Use a mirror template';

  @override
  String get subsUseMirrorTemplateSubtitle =>
      'Rewrite the download URL when the source is slow or rate limited';

  @override
  String get subsMirrorTemplate => 'Mirror template';

  @override
  String get subsMirrorFallback => 'Fall back to direct';

  @override
  String get subsMirrorFallbackSubtitle =>
      'Use the original URL when the mirror fails';

  @override
  String get subsEffectiveUrl => 'Requested URL';

  @override
  String get subsNothingToUpdate => 'No remote subscriptions to update';

  @override
  String get subsDeleteTitle => 'Delete subscription';

  @override
  String get subsRenameTitle => 'Rename subscription';

  @override
  String get subsNameRequired => 'The name cannot be empty';

  @override
  String get subsTitle => 'Subscriptions';

  @override
  String get subsUpdateAll => 'Update all';

  @override
  String get subsCount => 'Subscriptions';

  @override
  String get subsRuleCount => 'Stored rules';

  @override
  String get subsAbnormal => 'Errors';

  @override
  String get subsUpdating => 'Updating subscriptions…';

  @override
  String get subsEmptyLabel => 'No subscriptions yet';

  @override
  String get subsEmptyDescription =>
      'Subscriptions maintain rules in bulk: an update downloads the body, parses it into the rule database and blocking follows.';

  @override
  String get subsUpdateFooter =>
      'An update downloads the body, parses it into block/allow and rewrite rules and stores them, replacing what the subscription contributed last time. Element-hiding rules are not injected by this app and are not counted.';

  @override
  String get subsAllGroups => 'All';

  @override
  String get subsNewGroupTitle => 'New group';

  @override
  String get subsEditRemoteHint =>
      'Changing the URL or rule type downloads again immediately and replaces this subscription\'s rules; the source type and local file cannot be changed.';

  @override
  String get subsEditLocalHint =>
      'Local files are read through the system picker and the app only keeps read access; allow/block and hosts subscriptions with the same name do not affect each other.';

  @override
  String get subsAddRemoteHint =>
      'One URL can back both an allow/block and a hosts subscription (uniqueness is URL + type); saving downloads the body once and stores it.';

  @override
  String get subsKindLabel => 'Rule type';

  @override
  String get subsGroupLabel => 'Group';

  @override
  String get subsMirrorTitle => 'Mirror';

  @override
  String subsDeleteMessage(String name) {
    return 'Deleting \"$name\" cannot be undone.\n\nIt also removes every rule this subscription contributed (source tag sub_<id>).';
  }

  @override
  String subsTotal(int count) {
    return '$count subscriptions';
  }

  @override
  String subsGroupTotal(String count, int group) {
    return '$count subscriptions in \"$group\"';
  }

  @override
  String get subsUpdateNow => 'Update now';

  @override
  String get subsReimport => 'Re-import file';

  @override
  String get subsRename => 'Rename';

  @override
  String subsConsecutiveFailures(int count) {
    return 'Failed $count times in a row';
  }

  @override
  String get subsMirrorFallbackShort => 'Mirror · fallback on';

  @override
  String get subsMirrorNoFallback => 'Mirror · no fallback';

  @override
  String get subsLastUpdateFailed => 'Last update failed';

  @override
  String get subsNeverUpdated => 'Never updated successfully';

  @override
  String subsRuleCountValue(String count) {
    return '$count rules';
  }

  @override
  String subsRulesStored(String action, String count) {
    return '$count rules stored; $action the rules this subscription contributed.';
  }

  @override
  String get subsActionRemote => 'an update downloads again and replaces';

  @override
  String get subsActionLocal =>
      're-importing reads the file again and replaces';

  @override
  String get subsPickRuleFile => 'Pick a rule file';

  @override
  String get subsChange => 'Change';

  @override
  String get subsGroupShort => '+ Group';

  @override
  String get subsManageGroupsShort => 'Manage';

  @override
  String get subsManageGroupsTitle => 'Manage groups';

  @override
  String get subsGroupRenameTitle => 'Rename group';

  @override
  String get subsGroupDeleteTitle => 'Delete group';

  @override
  String subsGroupDeleteMessage(String name) {
    return 'Deleting \"$name\" moves its subscriptions to Ungrouped; the subscriptions and their rules are kept.';
  }

  @override
  String get subsGroupDuplicate => 'A group with this name already exists';

  @override
  String subsGroupSubCount(int count) {
    return '$count subscriptions';
  }

  @override
  String get subsGroupsEmpty => 'No groups yet';

  @override
  String get subsGroupsEmptyHint =>
      'Create a group with the button at the top right, then rename or delete it here.';

  @override
  String get subsGroupsFooter =>
      'Groups only affect filtering and bulk updates on this page; deleting a group never deletes subscriptions or rules.';

  @override
  String subsMirrorName(String mirror) {
    return 'Mirror $mirror';
  }

  @override
  String get trafficPackageName => 'Package';

  @override
  String get trafficAppName => 'App name';

  @override
  String get trafficDown => 'Download';

  @override
  String get trafficUp => 'Upload';

  @override
  String get trafficTotal => 'Total';

  @override
  String get trafficShare => 'Share';

  @override
  String get trafficStartDate => 'First day';

  @override
  String get trafficLastUpdate => 'Last updated';

  @override
  String get trafficAttributionFooter =>
      'Traffic is attributed to apps by UID (the upstream TrafficAttributionDialog rule); processes of one app are merged.';

  @override
  String get trafficAttributionTitle => 'How traffic is attributed';

  @override
  String get trafficScopeTitle => 'What is counted';

  @override
  String get trafficScopeBody =>
      'Traffic is attributed by UID: the engine accumulates each app\'s bytes by UID and stores them per day (table app_traffic_daily, keyed by date + package). No package matching is involved, so apps sharing a UID are merged.';

  @override
  String get trafficWhyLowerTitle =>
      'Why the numbers are lower than in system settings';

  @override
  String get trafficWhyLowerBody =>
      'Only traffic that goes through the local tunnel is counted; direct traffic outside the tunnel is not. System settings cover all interfaces.';

  @override
  String get trafficWhyNoRateTitle => 'Why there is no live rate';

  @override
  String get trafficWhyNoRateBody =>
      'A live rate needs a per-second series from the core; the daily table only holds date, package and cumulative bytes, with no rate column. That is why the session window and the live-rate sort are unavailable and there is no rate chart: every number shown is a real byte count.';

  @override
  String get trafficRetentionTitle => 'How long records are kept';

  @override
  String get trafficRetentionBody =>
      'Rows are kept per day and expired ones are removed by the native cleanup policy; the all-history window sums every date still in the table.';

  @override
  String get trafficSystemAppsTitle => 'How system apps are recognised';

  @override
  String get trafficSystemAppsBody =>
      'The traffic table has no system-app flag, so the page uses the same prefix list as the legacy SystemAppClassifier (android, com.android.*, vendor preinstalls and so on). The hide-system-apps switch is stored in traffic_stats_hide_system_apps.';

  @override
  String get trafficUpstreamFooter =>
      'Upstream equivalents are ui/traffic/TrafficAttributionDialog.kt and AppTrafficDetailDialog.kt; the numbers here come from app_traffic_daily.';

  @override
  String get trafficTitle => 'Traffic';

  @override
  String get trafficClearHistory => 'Clear history';

  @override
  String get trafficRefresh => 'Refresh';

  @override
  String get trafficAttribution => 'Attribution';

  @override
  String get trafficLoadFailed => 'Traffic records cannot be read';

  @override
  String get trafficLoading => 'Reading traffic records';

  @override
  String get trafficAppCount => 'Apps';

  @override
  String get trafficAppCountUnit => '';

  @override
  String get trafficNoData => 'No traffic data yet';

  @override
  String get trafficNoMatchingApps => 'No matching apps';

  @override
  String get trafficRankingTitle => 'App traffic ranking';

  @override
  String trafficShareFooter(String range, String window) {
    return 'Shares use the total bytes (download + upload) for $window; $range. Tap a row to see that app\'s breakdown.';
  }

  @override
  String get trafficClearTitle => 'Clear all traffic records?';

  @override
  String get trafficConfirmClear => 'Clear';

  @override
  String get trafficClearBody =>
      'This clears every stored per-app traffic record and cannot be undone.';

  @override
  String get trafficRangeAllHistory => 'covering all history';

  @override
  String get trafficSessionRange => 'This session';

  @override
  String get trafficSessionUnavailable =>
      'The session window needs per-session traffic from the core; only daily records exist here';

  @override
  String get trafficLiveRate => 'By live rate';

  @override
  String get trafficHideSystemApps => 'Hide system apps';

  @override
  String get trafficSearchHint => 'Search by app name or package';

  @override
  String get trafficAllHistory => 'All history';

  @override
  String get trafficLiveRateUnavailable =>
      'The live-rate sort needs per-second rates; the daily table has no rate column';

  @override
  String get trafficHideSystemAppsSubtitle =>
      'Recognised by system flag and vendor preinstall prefixes; hidden apps are left out of the ranking';

  @override
  String trafficWindowLabelDate(String date) {
    return 'Statistics for $date';
  }

  @override
  String trafficWindowLabelRange(String end, String start) {
    return 'Statistics from $start to $end';
  }

  @override
  String trafficShareWindow(String range, String window) {
    return 'Shares use the total bytes (download + upload) for $window; $range. Tap a row to see that app\'s breakdown.';
  }

  @override
  String trafficTotalApps(int count, String total) {
    return '$count apps generated traffic · $total total';
  }

  @override
  String trafficSearchEmpty(String search) {
    return 'No app name or package contains \"$search\".';
  }

  @override
  String trafficHiddenCount(int count) {
    return '$count apps are hidden by \"Hide system apps\"; turn it off to see them.';
  }

  @override
  String get trafficNoRecordsBody =>
      'Traffic is summed per day by the native side; once the tunnel runs and carries traffic, each app\'s download and upload bytes appear here.';

  @override
  String trafficNoRecordsForWindow(String window) {
    return 'No traffic records for \"$window\" yet. Records are summed per day, so try another window or run the tunnel first.';
  }

  @override
  String trafficOptionUnavailable(String label, String reason) {
    return '\"$label\" is unavailable: $reason';
  }

  @override
  String get trafficNoSourceReason => 'no matching data source here';

  @override
  String trafficCleared(int count) {
    return 'Cleared $count traffic records';
  }

  @override
  String trafficClearFailed(String detail) {
    return 'Clearing failed: $detail';
  }

  @override
  String trafficShareBarTooltip(String sort, String value) {
    return 'The bar length is this row\'s share of the window total under \"$sort\" (currently $value), matching the list order.';
  }

  @override
  String get trafficWhyDaemonTitle =>
      'Why do system settings attribute all traffic to DITING?';

  @override
  String get trafficWhyDaemonBody =>
      'Android\'s VPN model attributes proxied outbound traffic to the daemon. DITING does not use traffic behind your back; tap to see what is counted.';

  @override
  String get trafficLiveRateTitle => 'Live rate';

  @override
  String trafficNoLiveRate(String window) {
    return 'This mode does not measure a live rate: express mode\'s narrow route bypasses the engine\'s traffic counters and there is no cumulative table for it. The $window download/upload figures and the ranking below are still real numbers.';
  }

  @override
  String trafficLiveRateBody(String window) {
    return 'Per-second rates from the engine (this session), the same source as the persistent notification. The $window download/upload figures are cumulative bytes from `app_traffic_daily`; the two use different scopes and need not match.';
  }

  @override
  String get trafficSearchPlaceholder => 'Search app or package...';

  @override
  String trafficWindowDown(String window) {
    return '$window download';
  }

  @override
  String trafficWindowUp(String window) {
    return '$window upload';
  }

  @override
  String get obsRequestsTitle => 'Requests';

  @override
  String get obsSource => 'Source';

  @override
  String get obsStatus => 'Status';

  @override
  String get obsRefresh => 'Refresh';

  @override
  String get obsClearFilter => 'Clear filters';

  @override
  String get obsLoadFailed => 'Request records cannot be read';

  @override
  String get obsLoading => 'Reading request records';

  @override
  String get obsNoRecords => 'No request records yet';

  @override
  String get obsNoMatchingRequests => 'No requests match the filter';

  @override
  String get obsNoRecordsBody =>
      'Requests made by apps are recorded here; HTTPS records need traffic inspection enabled.';

  @override
  String get obsResetFilter => 'Reset filters';

  @override
  String get obsRecordsHeader => 'Request records';

  @override
  String get obsRetry => 'Retry';

  @override
  String get obsBypassedDns => 'Direct, bypassing the DNS resolution flow';

  @override
  String get obsBlockedDns =>
      'Blocked by a filter rule before any query was sent';

  @override
  String get obsRewrittenDns =>
      'Matched a rewrite rule and returned the rewritten answer';

  @override
  String get obsErrorDns => 'The lookup failed and produced no answer';

  @override
  String get obsPassedDns => 'Resolved by the rules and answered normally';

  @override
  String get obsPassedHttps => 'Forwarded successfully';

  @override
  String get obsRewrittenHttps =>
      'Matched a rewrite rule and forwarded the rewritten request';

  @override
  String get obsBlockedHttps => 'Blocked by a filter rule before connecting';

  @override
  String get obsBypassedHttps => 'Forwarded without decryption (bypass)';

  @override
  String get obsErrorHttps => 'Handling failed';

  @override
  String get obsNoRuleHttps => 'No rule matched (or none was recorded)';

  @override
  String get obsNone => 'None';

  @override
  String get obsRequestDetailTitle => 'Request details';

  @override
  String get obsCachedChip => 'Cache';

  @override
  String get obsBasicInfo => 'Basics';

  @override
  String get obsTime => 'Time';

  @override
  String get obsProtocol => 'Protocol';

  @override
  String get obsAppPackage => 'Package';

  @override
  String get obsResolved => 'Resolved';

  @override
  String get obsElapsed => 'Elapsed';

  @override
  String get obsBlockingSubscription => 'Blocking subscription';

  @override
  String get obsRuleMatch => 'Rule match';

  @override
  String get obsRule => 'Rule';

  @override
  String get obsHandling => 'Handling';

  @override
  String get obsError => 'Error';

  @override
  String get obsAiAnalysis => 'AI analysis';

  @override
  String get obsRawRecord => 'Raw record';

  @override
  String get obsRawRecordFooter =>
      'The verbatim message field written by the engine.';

  @override
  String get obsFailedHint =>
      'For failed requests, check the matching active connections on the Connections page.';

  @override
  String get obsRulesHint =>
      'Rules added here can be reviewed and undone on the Rules page.';

  @override
  String get obsCacheHit => 'Cache hit';

  @override
  String obsCopied(String text) {
    return 'Copied $text';
  }

  @override
  String get obsCopyAddress => 'Copy address';

  @override
  String get obsCopyDomain => 'Copy domain';

  @override
  String get obsInBlocklist => 'Already blocked';

  @override
  String get obsAddToBlocklist => 'Block it';

  @override
  String get obsInAllowlist => 'Already allowed';

  @override
  String get obsAddToAllowlist => 'Allow it';

  @override
  String get obsIpOnlyFooter =>
      'This record only has an IP address, which domain rules cannot match, so it cannot be added to the lists.';

  @override
  String get obsAnalyzeRequest => 'Analyse this request';

  @override
  String get obsAnalyzeRequestBody =>
      'Use the configured model to judge ownership, risk and next steps';

  @override
  String obsCopiedHost(String host) {
    return 'Copied $host';
  }

  @override
  String obsAddedToKind(String domain, String kind) {
    return 'Added $domain to $kind';
  }

  @override
  String obsAlreadyInKind(String domain, String kind) {
    return '$domain is already in $kind';
  }

  @override
  String obsCurrentFilter(String filter) {
    return 'Filtered by: $filter.';
  }

  @override
  String obsFooterCount(int count, int failed, String filter, String more) {
    return '$count records, $failed failed$filter$more. Tap a row to see the rule match and outcome.';
  }

  @override
  String obsFooterFilter(String filter) {
    return ' (filtered by: $filter)';
  }

  @override
  String get obsFooterMore => '; scroll for more';

  @override
  String get obsFooterAll => '; all loaded';

  @override
  String get obsByApp => 'By app';

  @override
  String get obsViewAppRequests => 'View this app\'s requests';

  @override
  String get obsAppsTitle => 'By app';

  @override
  String get obsAppsHeader => 'Apps';

  @override
  String get obsAppsEmpty => 'No requests attributed to an app yet';

  @override
  String get obsAppsEmptyBody =>
      'Requests that carry a package name are grouped by app here.';

  @override
  String get obsAppsFooter =>
      'Sorted by request count, across all retained request records. Tap an app to see its requests.';

  @override
  String obsAppRequestCount(int count) {
    return '$count requests';
  }

  @override
  String get logsSubStatsTitle => 'Subscription block rate';

  @override
  String get logsRefresh => 'Refresh';

  @override
  String get logsTimeRange => 'Time range';

  @override
  String get logsSubStatsFooter =>
      'The block rate is this subscription\'s blocked requests as a share of all recorded requests (DNS + HTTPS) in the selected range.';

  @override
  String get logsOverview => 'Overview';

  @override
  String get logsSubStatsLoadFailed => 'Block statistics cannot be read';

  @override
  String get logsLoadingStats => 'Loading statistics';

  @override
  String get logsBlockingSubs => 'Blocking subscriptions';

  @override
  String get logsMissingSubColumn =>
      'The database has no subscription tag column';

  @override
  String get logsMissingSubColumnBody =>
      'This database predates subscription block statistics, so log rows have no blockSubscriptionId. New requests can be counted; history cannot be backfilled.';

  @override
  String get logsAllRecordedRequests => 'All recorded requests';

  @override
  String get logsAllRecordedFooter =>
      'DNS and HTTPS logs combined, including passed, blocked and failed.';

  @override
  String get logsNoBlockingSubs => 'No blocking subscriptions';

  @override
  String get logsNoBlockingSubsBody =>
      'Once a blocking subscription is imported and DNS or HTTPS requests arrive, its block rate appears here.';

  @override
  String get logsBlockingSubsFooter =>
      'Sorted by block count; \"Deleted\" means the subscription is gone but its history is kept.';

  @override
  String get logsExpired => 'Expired';

  @override
  String get logsRaceTitle => 'Race statistics';

  @override
  String get logsRaceFooter =>
      'Only races that actually sent DoH requests are counted; cache hits never appear here.';

  @override
  String get logsRaceLoadFailed => 'Race records cannot be read';

  @override
  String get logsLoadingRace => 'Reading race records';

  @override
  String logsRaceSummary(String count, String range) {
    return '$count races in $range.';
  }

  @override
  String get logsRaceEmptyRange => 'No races in the selected range yet.';

  @override
  String get logsRaceRequests => 'Races';

  @override
  String get logsSuccess => 'Succeeded';

  @override
  String get logsAverageElapsed => 'Average time';

  @override
  String get logsStrategyOverview => 'Strategy overview';

  @override
  String get logsStrategyFooter =>
      'Cache hits do not trigger a race and never appear here; the primary hit rate is the share where the primary resolver won and succeeded.';

  @override
  String get logsWinnerProviders => 'Winning resolvers';

  @override
  String get logsNoWinners => 'No winners yet';

  @override
  String get logsNoWinnersBody =>
      'After a successful race the winning resolvers are ranked here by count.';

  @override
  String get logsWinnerFooter =>
      'Sorted by wins; the average time is the mean when that resolver won.';

  @override
  String logsAverageWinLatency(String latency) {
    return 'Won in $latency on average';
  }

  @override
  String get logsSmartPrimary => 'Smart primary';

  @override
  String get logsSmartPrimaryFooter =>
      'Only meaningful for the smart strategy: the primary hit rate counts queries where the primary resolver won; queries rescued by a fallback are excluded.';

  @override
  String logsPrimaryHit(String latency, String percent) {
    return 'Primary hit $percent · average $latency';
  }

  @override
  String get logsDashboardTitle => 'Log dashboard';

  @override
  String get logsModeTooltip => 'Log mode';

  @override
  String get logsRequestsDashboard => 'Request log dashboard';

  @override
  String get logsRequestsDashboardBody =>
      'A live overview of DNS, HTTPS, cache, races and rule blocks';

  @override
  String get logsFocusedDashboard => 'Key request dashboard';

  @override
  String get logsFocusedDashboardBody =>
      'An overview of blocked, failed and bypassed DNS and HTTPS records plus resolution state';

  @override
  String get logsServiceOverview => 'Service and resolution overview';

  @override
  String get logsPrivacyBody =>
      'Privacy mode is on, so no request details are recorded. DNS cache, racing and traffic monitoring keep running.';

  @override
  String get logsCacheTableTitle => 'DNS cache table';

  @override
  String logsCacheLoadFailed(String detail) {
    return 'The cache table cannot be read: $detail';
  }

  @override
  String get logsLoadingCache => 'Reading the cache table';

  @override
  String get logsCacheEmpty => 'The cache table is empty';

  @override
  String get logsCacheNoMatch => 'No matching cache entries';

  @override
  String get logsCacheEmptyBody =>
      'Successful lookups are written to dns_cache; on a fresh install or right after the tunnel starts the table may still be empty.';

  @override
  String logsCurrentSearch(String query) {
    return 'Searching: $query';
  }

  @override
  String get logsLiveCache => 'Live cache entries';

  @override
  String get logsNeverHit => 'Never hit';

  @override
  String logsCacheFooter(String count) {
    return '$count entries sorted by hits and expiry. Entries with less than 30 seconds of TTL are orange. Tap a row for details, to copy the domain, add it to the lists or analyse it with AI.';
  }

  @override
  String get logsBootstrapTitle => 'Bootstrap statistics';

  @override
  String get logsBootstrapFooter =>
      'The success rate is successes ÷ attempts; the average time is weighted by each node\'s attempts.';

  @override
  String get logsBootstrapLoadFailed => 'Bootstrap records cannot be read';

  @override
  String get logsLoadingBootstrap => 'Reading Bootstrap records';

  @override
  String logsBootstrapSummary(String count, String range) {
    return '$count Bootstrap probes in $range.';
  }

  @override
  String get logsBootstrapEmptyRange =>
      'No Bootstrap probes in the selected range yet.';

  @override
  String get logsAttempts => 'Attempts';

  @override
  String get logsSuccessRate => 'Success rate';

  @override
  String get logsNodes => 'Nodes';

  @override
  String get logsNoProbes => 'No probes yet';

  @override
  String get logsNoProbesBody =>
      'Enable \"Bootstrap IP\" and generate lookups; each node\'s attempts and success rate appear here.';

  @override
  String get logsNodesFooter =>
      'Sorted by attempts; values are aggregated over the window.';

  @override
  String get logsCacheDetailTitle => 'Cache details';

  @override
  String get logsCacheExpiringBody =>
      'This entry is about to expire; the next lookup will go upstream again';

  @override
  String get logsCacheValidBody =>
      'The entry is valid; hits are answered without going upstream';

  @override
  String get logsExpiring => 'Expiring';

  @override
  String get logsValid => 'Valid';

  @override
  String logsHitTimes(int count) {
    return '$count hits';
  }

  @override
  String get logsCacheInfo => 'Cache entry';

  @override
  String get logsRecordType => 'Record type';

  @override
  String get logsRemainingTtl => 'Remaining TTL';

  @override
  String get logsOriginalTtl => 'Original TTL';

  @override
  String get logsExpiry => 'Expires at';

  @override
  String get logsHitCount => 'Hits';

  @override
  String get logsLastHit => 'Last hit';

  @override
  String get logsResponseSize => 'Response size';

  @override
  String get logsAnalyzeDomain => 'Analyse this domain';

  @override
  String get logsCacheDetailFooter =>
      'The cache table syncs from engine memory every 10 seconds; this is a snapshot from when the page opened. Rules added here can be reviewed and undone on the Rules page.';

  @override
  String get logsAiInsight => 'AI insight';

  @override
  String get logsNotAnalysed => 'Not analysed';

  @override
  String get logsHasReport => 'Report ready';

  @override
  String get logsAiInsightBody =>
      'Send recent DNS and HTTPS records to the configured model for a summary of anomalies, protection and improvements.';

  @override
  String get logsAnalyseTraffic => 'Analyse recent traffic with AI';

  @override
  String get logsViewFullReport => 'View the full report';

  @override
  String logsModelName(String model) {
    return 'Model $model';
  }

  @override
  String logsSuccessWith(String percent) {
    return '$percent succeeded';
  }

  @override
  String logsAverageWith(String latency) {
    return 'Average $latency';
  }

  @override
  String logsPrimaryHitOnly(String percent) {
    return 'Primary hit $percent';
  }

  @override
  String logsFallbackUses(String count) {
    return '$count fallbacks';
  }

  @override
  String logsBootstrapRow(
    String failures,
    String ip,
    String latency,
    String percent,
  ) {
    return '$ip · $percent succeeded · average $latency$failures';
  }

  @override
  String logsBootstrapFailures(String count) {
    return ' · $count failed';
  }

  @override
  String logsEntryCount(int count) {
    return '$count entries';
  }

  @override
  String logsCacheRow(String count, int size, int ttl) {
    return '$ttl · $count hits · $size B';
  }

  @override
  String logsLastHitAt(String time) {
    return 'Last hit $time';
  }

  @override
  String logsCacheFooterCount(int count) {
    return '$count entries sorted by hits and expiry. Entries with less than 30 seconds of TTL are orange. Tap a row for details, to copy the domain, add it to the lists or analyse it with AI.';
  }

  @override
  String logsSubStatsRow(String count, String percent, String status) {
    return '$status | $count blocks | $percent';
  }

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutMore => 'More';

  @override
  String get aboutProject => 'Project';

  @override
  String get aboutJoinQq => 'Join the QQ group';

  @override
  String aboutQqGroup(String number) {
    return 'Group $number';
  }

  @override
  String get aboutSponsor => 'Sponsor';

  @override
  String get aboutCredits => 'Open-source credits';

  @override
  String get aboutCreditsUi =>
      'UI components and interactions are reused from this project';

  @override
  String get aboutCreditsCore =>
      'The Go tunnel core was initially forked from this project';

  @override
  String get aboutCreditsBody =>
      'Both projects are open source under GPL-3.0, and the copyright of their code and design belongs to their authors. Diting\'s UI layer borrows heavily from FlClash, and its tunnel core derives from an early fork of blockads-android; our sincere thanks to their authors and all contributors.';

  @override
  String get aboutSettings => 'Settings';

  @override
  String get aboutStartupCheck => 'Skip the update check at startup';

  @override
  String get aboutStartupCheckOn =>
      'Updates are not checked automatically at startup; you can check manually anytime';

  @override
  String get aboutStartupCheckOff =>
      'New versions are checked automatically at startup';

  @override
  String get aboutDisclaimerEntry => 'Terms and disclaimer';

  @override
  String get aboutDisclaimerEntryBody =>
      'The full software description, how it works and the disclaimer';

  @override
  String get aboutOtherContributors => 'Other contributors';

  @override
  String get aboutSponsorList => 'Sponsors';

  @override
  String get aboutSponsorListBody => 'Thanks to everyone who supported Diting';

  @override
  String get aboutBuilderList => 'Contributors';

  @override
  String get aboutBuilderListBody =>
      'Thanks to everyone who contributed code and ideas';

  @override
  String get aboutInstallerFailed => 'The system installer cannot be launched';

  @override
  String get aboutAppName => 'Diting';

  @override
  String get aboutTagline =>
      'A local-first DNS accelerator and traffic filter built on Android VpnService: simple, open source and ad-free.';

  @override
  String get aboutChecking => 'Checking…';

  @override
  String get aboutCheckUpdate => 'Check for updates';

  @override
  String get aboutDownloading => 'Downloading…';

  @override
  String get aboutInstall => 'Install';

  @override
  String get aboutDownload => 'Download';

  @override
  String get aboutCheckingRelease => 'Checking GitHub Releases';

  @override
  String aboutUpToDate(String version) {
    return 'You are on the latest version$version';
  }

  @override
  String aboutVersionSuffix(String version) {
    return ' ($version)';
  }

  @override
  String aboutFoundVersion(String version) {
    return 'Version $version found';
  }

  @override
  String aboutCurrentSuffix(String version) {
    return ' (current $version)';
  }

  @override
  String get aboutNew => 'new ';

  @override
  String get aboutNewVersion => 'a new version';

  @override
  String aboutUpdatePackage(String version) {
    return '$version update package';
  }

  @override
  String aboutLinkCopyFallback(String url) {
    return 'The browser could not be opened; the link was copied: $url';
  }

  @override
  String get devStressLogs => 'Log stress test';

  @override
  String devStressLogsBody(int count) {
    return 'Write $count DNS logs into the active log database for real';
  }

  @override
  String get devErrorReport => 'Error reporting self-check';

  @override
  String get devErrorReportBody =>
      'Report a test exception through FlutterError to verify the error pipeline';

  @override
  String get devClearAll => 'Clear all data';

  @override
  String get devClearAllBody =>
      'Delete settings, rules and logs to restore the factory state';

  @override
  String get devVacuum => 'Compact databases';

  @override
  String get devVacuumBody =>
      'Run VACUUM on the three local databases to reclaim space from deleted rows';

  @override
  String get devCancel => 'Cancel';

  @override
  String get devRun => 'Run';

  @override
  String devConfirmBody(String action) {
    return '$action\n\nThis operation really rewrites local data and cannot be undone.';
  }

  @override
  String devActionFailed(String action, String error) {
    return '$action failed: $error';
  }

  @override
  String get devStressNoDb =>
      'Stress test failed: the log database cannot be opened';

  @override
  String devStressDone(String count, String file) {
    return 'Stress test finished: $count rows written to $file';
  }

  @override
  String get devTestException =>
      'Test exception triggered from developer options';

  @override
  String get devErrorReported =>
      'A FlutterError was reported: test exception triggered from developer options';

  @override
  String get devVacuumNoDb =>
      'Compaction failed: there are no database files yet';

  @override
  String devVacuumDone(String files, int kb) {
    return 'Compacted $files, reclaimed $kb KB';
  }

  @override
  String get devRestartNeeded => 'Restart required';

  @override
  String get devLater => 'Later';

  @override
  String get devQuitNow => 'Quit now';

  @override
  String get devClearAllDone =>
      'All data has been cleared; restart the app to start from the factory state.';

  @override
  String get devOptions => 'Developer options';

  @override
  String get devDiagnostics => 'Diagnostics';

  @override
  String get devIpQuality => 'IP quality';

  @override
  String get devIpQualityBody =>
      'Probe the egress address and how three public sources classify it';

  @override
  String get devRequestLogs => 'Request logs';

  @override
  String get devRequestLogsBody =>
      'Live request records merged from http_request_log and dns_log';

  @override
  String get devLogRetention => 'Log retention';

  @override
  String get devLogRetentionBody =>
      'Log capacity limits and what DNS request logs record';

  @override
  String get devTroubleshoot => 'Troubleshooting';

  @override
  String get devTroubleshootBody =>
      'Export crash logs, or capture and export runtime logs manually';

  @override
  String get devDataCleanup => 'Data cleanup';

  @override
  String get devUnlocked => 'Experimental actions unlocked';

  @override
  String get devLocked => 'The actions below are unavailable while off';

  @override
  String get devWarning =>
      'These actions really rewrite local data (log database, prefs, database files), and \"Clear all data\" cannot be undone; do not enable this in production.';

  @override
  String get devRunning => 'Running…';

  @override
  String get sponsorGithub => 'See sponsorship options on GitHub';

  @override
  String get sponsorReadme => 'Read the sponsorship section in the README';

  @override
  String get sponsorReadmeCopied =>
      'The browser could not be opened; the README link was copied';

  @override
  String get sponsorThanks => 'Acknowledgements';

  @override
  String get sponsorThanksBody => 'Thanks to everyone who supports the project';

  @override
  String get sponsorBuildersBody =>
      'Thanks to everyone who shared ideas and helped test';

  @override
  String get sponsorUsage => 'Every contribution goes towards';

  @override
  String get sponsorUsageNewFeatures => 'Ongoing feature development';

  @override
  String get sponsorUsageBugs => 'Fixing bugs';

  @override
  String get sponsorUsageTokens => 'Buying tokens';

  @override
  String get sponsorFreeWays => 'Even without donating, you can';

  @override
  String get sponsorFreeStar => 'Star the project⭐';

  @override
  String get sponsorFreeIssue => 'File an issue';

  @override
  String get sponsorFreePr => 'Open a pull request';

  @override
  String get sponsorFreeShare => 'Share it with others';

  @override
  String get sponsorFooter => 'Thanks to everyone who supports the project!';

  @override
  String get sponsorBuyDrink => 'Buy the author a drink 🧋';

  @override
  String get sponsorNote =>
      'If this project helps you, you are welcome to buy the author a drink. Please add your nickname in the payment note so you can be added to the sponsor list.';

  @override
  String get sponsorAlipay => 'Alipay';

  @override
  String get sponsorWechat => 'WeChat Pay';

  @override
  String get sponsorNickname => 'Add your nickname';

  @override
  String get sponsorScan => 'Scan to sponsor';

  @override
  String sponsorQrCode(String label) {
    return '$label QR code';
  }

  @override
  String get sponsorClose => 'Close';

  @override
  String get sponsorNoteShort =>
      'Please add your nickname in the payment note so you can be added to the sponsor list.';

  @override
  String aboutQqCopied(String number) {
    return 'QQ was not found; the group number was copied: $number';
  }

  @override
  String get disclaimerTitle => 'Disclaimer';

  @override
  String get disclaimerTerms => 'Full terms';

  @override
  String get disclaimerSource =>
      'The authoritative terms are NOTICE.md in the repository and the LICENSE shipped with the app.';

  @override
  String get ipQualityRedetect => 'Check again';

  @override
  String get ipQualityEgress => 'Current egress address';

  @override
  String get ipQualitySources => 'Sources';

  @override
  String get ipQualitySourcesFooter =>
      'Sources often disagree on residential vs. hosting: more hits means more confidence, but one source\'s \"risky\" label is not conclusive.';

  @override
  String get ipQualityQuerying =>
      'Looking up the egress IP and three intelligence sources…';

  @override
  String get ipQualityChecking => 'Checking…';

  @override
  String get ipQualityDetecting => 'Detecting';

  @override
  String get ipQualityFailed => 'Check failed';

  @override
  String get ipQualityNotYet => 'Not checked yet';

  @override
  String get ipQualityDetectingBody =>
      'Fetching the egress IP and querying the sources, please wait';

  @override
  String get ipQualityStartBody =>
      'Tap the button below to check the quality of the current egress IP';

  @override
  String get ipQualityStart => 'Start checking';

  @override
  String ipQualityJudgedAs(String type) {
    return 'Classified as $type';
  }

  @override
  String get ipQualityNotUsed => 'Not used';

  @override
  String get ipQualityUsed => 'Used';

  @override
  String devFooterWarning(int count) {
    return 'These actions work directly on the local databases, prefs and native channels: the stress test really writes $count rows, compaction runs SQLite VACUUM, and clearing all data deletes everything locally and requires a restart.';
  }

  @override
  String get devDataCleanupBody =>
      'Delete logs, weights, rules and cache by category';

  @override
  String get devConfigSection => 'Configuration and resources';

  @override
  String get devCustomResources => 'Custom resources';

  @override
  String get devCustomResourcesBody =>
      'Entry points for configuration resources such as User-Agent and on-demand';

  @override
  String get devUserAgentBody =>
      'The UA sent with subscription downloads and speed tests';

  @override
  String get devOnDemand => 'On-demand connection';

  @override
  String get devOnDemandBody => 'Start the VPN depending on the SSID';

  @override
  String get devWebdav => 'WebDAV sync';

  @override
  String get devWebdavBody => 'Upload backups to your own WebDAV server';

  @override
  String get devUiSection => 'UI and appearance extras';

  @override
  String get devFontFamilyBody => 'Choose the UI font family on its own page';

  @override
  String get devFontSizeBody =>
      'Global text scaling; an inline slider in the appearance settings';

  @override
  String get devTabAnimation => 'Tab animation';

  @override
  String get devTabAnimationBody =>
      'The entrance animation when switching bottom tabs; an inline option in the appearance settings';

  @override
  String get devExperimental => 'Experimental actions';

  @override
  String get devLegacyFooter =>
      'None of the pages under Diagnostics, Configuration and resources or UI and appearance belong to the 1.4.3 interface; they are kept for debugging and component review. The legacy features are still reached through the legacy menus, not this page.';

  @override
  String get unknownRouteTitle => 'Page not found';

  @override
  String get unknownRouteBody => 'This page cannot be found';

  @override
  String get unknownRouteBack => 'Back';

  @override
  String get disclaimerReadFirst => 'Read before use';

  @override
  String get disclaimerIntro =>
      'Diting is an open-source local DNS and traffic observability tool. It does not provide, proxy or relay any network access service, and all data is processed on the device.';

  @override
  String get disclaimerLawful =>
      'Use this software in compliance with the laws of your jurisdiction. Using it on any unauthorised network is at your own risk.';

  @override
  String get disclaimerFirstRun => 'The text confirmed at first launch';

  @override
  String get disclaimerImmutable => 'Not editable';

  @override
  String get devFontFamily => 'Font';

  @override
  String get devFontSize => 'Text size';

  @override
  String get devWarningTitle => 'Developer mode';

  @override
  String get devFooterLegacy =>
      'The pages under Diagnostics, Configuration and resources, and UI and appearance do not belong to the 1.4.3 interface; they are kept for debugging and component review. Legacy features are still reached through the legacy menus, not this page.';

  @override
  String get ipTypeResidential => 'Residential';

  @override
  String get ipTypeMobile => 'Mobile';

  @override
  String get ipTypeBusiness => 'Business';

  @override
  String get ipTypeHosting => 'Hosting';

  @override
  String get ipLevelGood => 'Good';

  @override
  String get ipLevelNormal => 'Fair';

  @override
  String get ipLevelRisky => 'Risky';

  @override
  String get ipStatusOk => 'Matched';

  @override
  String get ipStatusNoType => 'No type';

  @override
  String get ipStatusTimeout => 'Timed out';

  @override
  String get ipStatusRateLimited => 'Rate limited';

  @override
  String get ipStatusMismatch => 'IP mismatch';

  @override
  String get modeSelectTitle => 'Choose a work mode';

  @override
  String get modeContinue => 'Continue';

  @override
  String get modeSwitchNote =>
      'You can choose again in settings at any time; switching stops the current mode\'s service first, so two modes never run together.';

  @override
  String get modeSharedNote =>
      'All three modes share one set of rules and cache; they differ in how they take over traffic: normal mode uses a full tunnel, server mode only serves LAN DNS, and express mode is a pure-Kotlin narrow route.';

  @override
  String get modeNormalFeature1 => 'Full tunnel';

  @override
  String get modeNormalFeature1Body =>
      'The Go stack handles all traffic, with per-app routing';

  @override
  String get modeNormalFeature2 => 'All rule features';

  @override
  String get modeNormalFeature2Body =>
      'Blocklists, allowlists, rewrites and HTTPS inspection are all available';

  @override
  String get modeNormalFeature3 => 'Optional HTTPS inspection';

  @override
  String get modeNormalFeature3Body =>
      'Requires installing and trusting the local CA certificate';

  @override
  String get modeNormalFeature4 => 'Per-app traffic stats';

  @override
  String get modeNormalFeature4Body =>
      'Records upload, download and query counts per app';

  @override
  String get modeServerFeature1 => 'LAN DNS service';

  @override
  String get modeServerFeature1Body =>
      'Listens on 0.0.0.0 for devices on the same subnet';

  @override
  String get modeServerFeature2 => 'No VPN slot needed';

  @override
  String get modeServerFeature2Body =>
      'No tunnel is created locally, so other VPNs can run at the same time';

  @override
  String get modeServerFeature3 => 'Shared rules and cache';

  @override
  String get modeServerFeature3Body =>
      'Uses the same rule library as normal mode';

  @override
  String get modeServerFeature4 => 'Low power';

  @override
  String get modeServerFeature4Body =>
      'Handles DNS queries only, without forwarding traffic';

  @override
  String get modeExpressFeature1 => 'Pure Kotlin';

  @override
  String get modeExpressFeature1Body =>
      'A narrow route, so starting and switching are faster';

  @override
  String get modeExpressFeature2 => 'Four upstream strategies';

  @override
  String get modeExpressFeature2Body =>
      'Single provider / smart / race / primary-backup';

  @override
  String get modeExpressFeature3 => '64-shard LRU cache';

  @override
  String get modeExpressFeature3Body =>
      'A high hit rate with predictable memory use';

  @override
  String get modeExpressFeature4 => 'Works on older systems';

  @override
  String get modeExpressFeature4Body => 'Android 7+ (64-bit required)';

  @override
  String get onboardingTitle => 'Setup';

  @override
  String get onboardingSkip => 'Skip setup';

  @override
  String get onboardingPrev => 'Back';

  @override
  String get onboardingStart => 'Get started';

  @override
  String get onboardingNext => 'Next';

  @override
  String onboardingChosen(String mode) {
    return 'You chose $mode';
  }

  @override
  String get onboardingChangeable => 'You can change it later';

  @override
  String get onboardingChangeableBody =>
      'Settings → choose the work mode again at any time. Switching stops the current mode\'s service first.';

  @override
  String get onboardingSharedRules => 'Rules and cache are shared';

  @override
  String get onboardingSharedRulesBody =>
      'All three modes share one set of lists and DNS cache, so nothing needs to be configured twice.';

  @override
  String get onboardingExclusive => 'Modes are exclusive';

  @override
  String get onboardingExclusiveBody =>
      'Only one mode runs at a time; leaving stops the previous one first.';

  @override
  String get permVpn => 'VPN connection';

  @override
  String get permNotification => 'Notifications';

  @override
  String get permAppList => 'App list';

  @override
  String get permBattery => 'Ignore battery optimisation';

  @override
  String get permRequired => 'Required';

  @override
  String get permOptional => 'Optional';

  @override
  String get permVpnNormalBody =>
      'Creates the local tunnel that handles traffic; denying it prevents startup';

  @override
  String get permNotificationBody =>
      'The foreground service needs a persistent notification; denying it lets the system reclaim the service';

  @override
  String get permAppListBody =>
      'Per-app routing and stats; denying it leaves only domain rules';

  @override
  String get permBatteryBody =>
      'Prevents the app from being killed; denying it may drop the tunnel after long standby';

  @override
  String get permBatteryServerBody =>
      'Prevents the app from being killed; denying it makes the LAN service intermittent';

  @override
  String get permVpnExpressBody =>
      'Creates the narrow-route tunnel; denying it prevents startup';

  @override
  String get permNeeded => 'These permissions are needed';

  @override
  String get permAllLocal =>
      'All permissions are used on this device only; no data is uploaded.';

  @override
  String permGrantedCount(String granted, String total) {
    return '$granted of $total granted; all permissions are used on this device only and no data is uploaded.';
  }

  @override
  String get onboardingTipNormal1 =>
      'Tap the big button on the home page to start the service; the system VPN prompt appears the first time.';

  @override
  String get onboardingTipNormal2 =>
      'Maintain the blocklists and allowlists under Feature hub → Rules and subscriptions.';

  @override
  String get onboardingTipNormal3 =>
      'The home page sentence and opacity can both be changed in settings.';

  @override
  String get onboardingTipServer1 =>
      'After starting, point devices on the same subnet to the address shown under LAN access.';

  @override
  String get onboardingTipServer2 =>
      'The port can be changed on the Server mode page; the default is 5353.';

  @override
  String get onboardingTipServer3 =>
      'This mode creates no VPN, so it can run alongside other VPNs.';

  @override
  String get onboardingTipExpress1 =>
      'Express mode starts faster but is a subset of normal mode.';

  @override
  String get onboardingTipExpress2 => 'Racing needs at least two providers.';

  @override
  String get onboardingTipExpress3 =>
      'Switch back to normal mode when you need HTTPS inspection or app control.';

  @override
  String get onboardingReady => 'You are ready';

  @override
  String get onboardingReadyBody =>
      'Here are the three most useful tips to start with.';

  @override
  String onboardingTipIndex(String index) {
    return 'Tip $index';
  }

  @override
  String permStillDenied(String name) {
    return '$name is still denied; allow it in system settings and return to this page';
  }

  @override
  String get permGranted => 'Granted';

  @override
  String get permDenied => 'Denied';

  @override
  String get permUnknown => 'Unknown';

  @override
  String get permGrant => 'Grant';

  @override
  String get toolSpeedTest => 'Speed test';

  @override
  String get toolPing => 'Ping test';

  @override
  String get toolDnsLookup => 'DNS lookup';

  @override
  String get toolTraceroute => 'Traceroute';

  @override
  String get toolDiagnostics => 'Network diagnostics';

  @override
  String get toolRefreshInfo => 'Refresh network info';

  @override
  String get toolActiveInterface => 'Active interface';

  @override
  String get toolLocalAddress => 'Local address';

  @override
  String get toolDnsServers => 'DNS servers';

  @override
  String get toolCountUnit => '';

  @override
  String toolPrivateDnsProbe(String dns) {
    return 'Probes use the physical network (this app\'s traffic bypasses the tunnel); system private DNS: $dns';
  }

  @override
  String get toolPhysicalProbe =>
      'Probes use the physical network: this app\'s traffic is excluded from the tunnel, so all four tools measure real latency on the physical link.';

  @override
  String get toolInputHostOrIp => 'Enter an IP or domain';

  @override
  String get toolPingCount4 => '4 pings';

  @override
  String get toolPingCount10 => '10 pings';

  @override
  String get toolPingOptions => 'Probe options';

  @override
  String get toolViaTunnel => 'Resolve through the Go tunnel';

  @override
  String get toolViaTunnelPingBody =>
      'Domains are resolved by the running Go tunnel (rewrites and filter rules apply), while probes still use the physical network';

  @override
  String get toolStartPing => 'Start ping';

  @override
  String get toolPinging => 'Probing…';

  @override
  String get toolTcpFallback =>
      'ICMP is restricted, so a TCP fallback was used. That latency is connection setup time and cannot be compared directly with ICMP round trips.';

  @override
  String get toolPingFailed => 'Probe failed: no reply received';

  @override
  String get toolTarget => 'Target';

  @override
  String get toolResolvedAddress => 'Resolved address';

  @override
  String get toolAddressFamily => 'Address family';

  @override
  String get toolSentReceived => 'Sent / received';

  @override
  String get toolPacketLoss => 'Packet loss';

  @override
  String get toolMinAvgMax => 'Min / avg / max';

  @override
  String get toolJitter => 'Jitter';

  @override
  String get toolJitterFooter =>
      'Jitter is the mean absolute deviation of each reply from the average.';

  @override
  String toolPacketN(String n) {
    return 'Packet $n';
  }

  @override
  String get toolTimeout => 'Timed out';

  @override
  String toolPingSummary(String failed, String sent) {
    return '$sent probes sent, $failed failed.';
  }

  @override
  String get toolPingFooter =>
      'Ping runs natively: it prefers the system ping binary and falls back to address reachability plus TCP handshake timing, which is always labelled.';

  @override
  String get toolDnsSystem => 'Follow system';

  @override
  String get toolDnsCustom => 'Custom';

  @override
  String get toolCustomDnsError => 'Enter a custom DNS server IP';

  @override
  String get toolInputDomain => 'Enter the domain to resolve';

  @override
  String get toolCustomDnsHint => 'Custom DNS server IP (e.g. 1.1.1.1)';

  @override
  String get toolQueryOptions => 'Query options';

  @override
  String get toolViaTunnelDnsBody =>
      'When on, the tunnel engine resolves it with block rules and cache applied; when off, the system resolver is asked directly';

  @override
  String get toolStartQuery => 'Start lookup';

  @override
  String get toolQuerying => 'Querying…';

  @override
  String get toolQueryDomain => 'Queried domain';

  @override
  String get toolRecordType => 'Record type';

  @override
  String get toolAnswerSource => 'Answer source';

  @override
  String get toolElapsed => 'Elapsed';

  @override
  String get toolAnswerCount => 'Answers';

  @override
  String get toolDnsBlockedBody =>
      'This domain was blocked by a tunnel rule, so there is no real upstream answer.';

  @override
  String get toolDnsNoAnswers =>
      'No answer records were returned. If the source is \"blocked by rules\", this domain is blocked by a local rule.';

  @override
  String get toolDnsFooter =>
      '\"Resolve through the tunnel\" queries this app\'s resolution path (rules and cache included) and lets the tunnel pick the server; when off you can follow the system or name a DNS server, and the results may differ.';

  @override
  String get toolTunnelEngine => 'Tunnel engine';

  @override
  String get toolSpeedChecking => 'Checking the speed test channel…';

  @override
  String get toolSpeedUnsupported =>
      'This device cannot run the speed test: there is no native channel for measuring DNS query time, so no simulated timings are shown.';

  @override
  String get toolSpeedDomainHint => 'Domain used for the speed test';

  @override
  String get toolSpeedProviders => 'Speed test providers';

  @override
  String toolNoProviders(String protocol) {
    return 'No $protocol DNS providers yet';
  }

  @override
  String get toolNoProvidersBody =>
      'Add one under Provider management to include it';

  @override
  String get toolSpeedSelectionNote =>
      'Choose one or more providers; this selection only affects the DNS speed test and does not change race mode.';

  @override
  String get toolTestQueryTime => 'Measure query time';

  @override
  String get toolSpeedRunning => 'Testing…';

  @override
  String get toolSpeedEmpty =>
      'No results yet. Pick providers and tap the button above; this app sends three real DNS queries to each provider and records the round trips.';

  @override
  String get toolSpeedResults => 'Query time results';

  @override
  String toolSpeedResultsFooter(String domain) {
    return 'Results are sorted by success first, then by average time ascending; they only reflect the network at query time. The current domain is \"$domain\".';
  }

  @override
  String get toolSpeedFooter =>
      'The speed test runs natively: real DoH / DoT / plaintext DNS queries are sent to each provider, and only samples with a successful answer count towards the timing.';

  @override
  String get toolFastest => 'Fastest';

  @override
  String toolSampleCount(String count, String rate) {
    return '$rate · $count samples';
  }

  @override
  String toolAllFailed(String count) {
    return 'All failed ($count attempts)';
  }

  @override
  String get toolTraceOptions => 'Trace options';

  @override
  String get toolStartTrace => 'Start trace';

  @override
  String get toolTracing => 'Tracing…';

  @override
  String get toolTraceFailed => 'Trace failed: no response received';

  @override
  String get toolTraceCancelled => 'The trace was cancelled.';

  @override
  String get toolHopCount => 'Hops';

  @override
  String toolHopCountValue(String count, String max) {
    return '$count / max $max';
  }

  @override
  String get toolNoResponse => 'No response';

  @override
  String get toolTraceFooter =>
      'An asterisk means that hop did not reply in time; it does not mean the link is down, since many routers ignore probes. A green row marks the destination.';

  @override
  String get toolTraceHops15 => '15 hops';

  @override
  String get toolTraceHops30 => '30 hops';

  @override
  String get uaDeleteTitle => 'Delete User-Agent';

  @override
  String get uaDeleteBody =>
      'Delete this entry? Only the candidate is removed; the currently selected UA is unaffected.';

  @override
  String get uaAdd => 'Add User-Agent';

  @override
  String get uaEdit => 'Edit User-Agent';

  @override
  String get uaNote =>
      'The UA is sent with subscription downloads, ruleset fetches and subscription speed tests; some servers reject requests by UA, and changing it here works around that.';

  @override
  String get uaCurrent => 'Current selection';

  @override
  String get uaNoOverride => 'No override';

  @override
  String get uaNoOverrideBody => 'Use the UA from the subscription or the core';

  @override
  String get uaBuiltin => 'Built-in';

  @override
  String get uaCustom => 'Custom';

  @override
  String get uaBuiltinNote =>
      'Built-in UAs cannot be deleted: removing one makes the core fall back to its default, which looks like the setting stopped working.';

  @override
  String get uaHint => 'e.g. clash-verge/v2.0.0';

  @override
  String get uaEmptyError => 'The UA cannot be empty';

  @override
  String get uaDuplicateError => 'That UA already exists';

  @override
  String get ssidInvalid => 'The SSID cannot be empty or already exist';

  @override
  String get ssidAdd => 'Add SSID';

  @override
  String get ssidEdit => 'Edit SSID';

  @override
  String get ssidSave => 'Save SSID';

  @override
  String get ssidHint =>
      'Case sensitive; must match the name in the system Wi-Fi list exactly';

  @override
  String get ssidExample => 'e.g. Home-5G';

  @override
  String get ssidEmptyError => 'The SSID cannot be empty';

  @override
  String get ssidConnection => 'Connection';

  @override
  String get ssidCellular => 'Cellular';

  @override
  String get ssidCellularBody => 'Start the VPN on this network too';

  @override
  String get ssidWifiBody => 'Start the VPN when connected to this SSID';

  @override
  String get ssidBothOff =>
      'Turning both off excludes this SSID from the allowlist, so the VPN will not start.';

  @override
  String get ssidDelay => 'Delay';

  @override
  String get ssidStartDelay => 'Start delay';

  @override
  String get ssidStartDelayBody =>
      'Wait for the network before starting the VPN';

  @override
  String get ssidImmediate => 'Connect immediately';

  @override
  String get odTitle => 'On-demand connection';

  @override
  String get odApplyNow => 'Apply now';

  @override
  String get odEnable => 'Enable on-demand connection';

  @override
  String get odEnableBody => 'Start the VPN automatically on allowlisted SSIDs';

  @override
  String get odDisableBody =>
      'When off, the VPN stays on and does not follow network changes';

  @override
  String get odNote =>
      'When enabled, the VPN starts automatically only on allowlisted SSIDs and stays off elsewhere, which is both more power-friendly and more predictable. Automatic decisions only act on network changes and never override the manual switch; tap \"Apply now\" to re-evaluate for the current network immediately.';

  @override
  String get odAllowlist => 'SSID allowlist';

  @override
  String get odNoSsid => 'No SSIDs yet';

  @override
  String get odNoSsidBody =>
      'On-demand connection never triggers without an allowlist';

  @override
  String get odDelayNote =>
      'The delay lets Wi-Fi finish authentication and DHCP; starting the VPN too early sends the first requests over a network that is not ready.';

  @override
  String get odCellular => 'Cellular';

  @override
  String get odKindsNone => 'Disabled';

  @override
  String odDelayValue(String ms) {
    return 'Delayed $ms ms';
  }

  @override
  String get odStateDisabled => 'On-demand connection is off';

  @override
  String get odStateUnknown =>
      'The current Wi-Fi cannot be read, so the allowlist never triggers';

  @override
  String get odStateNoWifi => 'Not on Wi-Fi, so the VPN stays off';

  @override
  String odStateMatched(String ssid) {
    return 'Matched $ssid; the VPN starts automatically';
  }

  @override
  String get odStateUnmatched =>
      'The current Wi-Fi is not allowlisted, so the VPN stays off';

  @override
  String get odDisabledHint =>
      'On-demand connection is off; the VPN no longer follows network changes';

  @override
  String get odPillDisabled => 'Disabled';

  @override
  String get odPillUnknown => 'Unknown';

  @override
  String get odPillNoWifi => 'Not on Wi-Fi';

  @override
  String get odPillWillStart => 'VPN will start';

  @override
  String get odPillWillNotStart => 'VPN will not start';

  @override
  String get odDecision => 'Current decision';

  @override
  String get odDecisionFooter =>
      'The decision is computed from the current network: read it again after switching Wi-Fi. SSIDs are case sensitive.';

  @override
  String get odCurrentNetwork => 'Current network';

  @override
  String get odWifiName => 'Wi-Fi name';

  @override
  String get odReadAgain => 'Read again';

  @override
  String get odPermission => 'Read permission';

  @override
  String get odPermissionBody =>
      'Reading the Wi-Fi name requires the location permission since Android 10';

  @override
  String get odNotGranted => 'Not granted';

  @override
  String get odWifiUnreadable =>
      'The Wi-Fi name cannot be read right now: grant the location permission in system settings and read it again.';

  @override
  String get odSsidPrivacy =>
      'SSIDs are only used to match the allowlist and are never uploaded; manually added SSIDs still work when reading fails.';

  @override
  String get odBatteryJoined => 'Added';

  @override
  String get odBatteryNotJoined => 'Not added';

  @override
  String get odBatteryUnavailable => 'Unavailable';

  @override
  String get odPrerequisites => 'Prerequisites';

  @override
  String get odIgnoreBattery => 'Ignore battery optimisation';

  @override
  String get odBatteryOk =>
      'The system will not freeze the VPN process in the background';

  @override
  String get odBatteryAsk =>
      'Without it the background VPN may be frozen; tap to request';

  @override
  String get odBatteryNoChannel =>
      'This build has no battery optimisation channel';

  @override
  String get odBatteryFooter =>
      'Tapping \"Not added\" opens the system authorisation page; the real state is re-read on return, and cancelling leaves it unchanged.';

  @override
  String get odBatteryJoinedHint =>
      'Added to the battery optimisation allowlist';

  @override
  String get odBatteryStillOff =>
      'Still not added; the VPN may be frozen by the system';

  @override
  String get odBatteryUnsupportedHint =>
      'This build does not support that permission';

  @override
  String get odCapNoPermission =>
      'Cannot read: the location permission is required';

  @override
  String odCapCurrent(String name) {
    return 'Connected to $name';
  }

  @override
  String get customResourcesTitle => 'Custom resources';

  @override
  String get customResourcesNote =>
      'These resources are referenced by name: renaming one breaks the reference, while editing content takes effect the next time the configuration loads. They are not part of the 1.4.3 interface and are kept here for debugging.';

  @override
  String get customResourcesSection => 'Resources';

  @override
  String get configDelete => 'Delete';

  @override
  String get configCancel => 'Cancel';

  @override
  String get configNotSet => 'Not set';

  @override
  String configItemCount(int count) {
    return '$count items';
  }

  @override
  String odEditSsidTooltip(String ssid) {
    return 'Edit $ssid';
  }

  @override
  String odDeleteSsidTooltip(String ssid) {
    return 'Delete $ssid';
  }

  @override
  String serverSwitched(String name) {
    return 'Switched to $name; restart the service to apply';
  }

  @override
  String serverSelected(String name) {
    return 'Selected $name';
  }

  @override
  String serverAdded(String name) {
    return 'Added $name';
  }

  @override
  String serverSaved(String name) {
    return 'Saved $name';
  }

  @override
  String serverDeleteConfirm(String name) {
    return 'Delete $name?';
  }

  @override
  String get serverDeleteBody =>
      'If it is in use, the first built-in provider is used after deletion.';

  @override
  String serverDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String get serverUpstreamTitle => 'Upstream servers';

  @override
  String get serverAddCustom => 'Add a custom provider';

  @override
  String serverCurrentUpstream(String name, String protocol) {
    return 'Currently resolving DNS: ($protocol) $name';
  }

  @override
  String get serverBuiltinProviders => 'Built-in DNS providers';

  @override
  String get serverNoBuiltin => 'No built-in providers';

  @override
  String get serverCustomProviders => 'Custom DNS providers';

  @override
  String get serverNoCustom => 'No custom providers';

  @override
  String get serverNoCustomBody =>
      'Tap the plus button to add a DoH / DoT / plaintext DNS upstream';

  @override
  String get serverUpstreamFooter =>
      'Server mode uses a single upstream; switch to normal or express mode for racing. Built-in providers are maintained by the app and can only be selected; long-press a custom one to edit or delete it.';

  @override
  String serverEditName(String name) {
    return 'Edit $name';
  }

  @override
  String serverDeleteName(String name) {
    return 'Delete $name';
  }

  @override
  String get serverEditCustom => 'Edit custom provider';

  @override
  String get serverSave => 'Save';

  @override
  String get serverName => 'Name';

  @override
  String get serverDohAddress => 'DoH address';

  @override
  String get serverAddress => 'Server address';

  @override
  String get serverDohPrefix => 'Must start with https://';

  @override
  String get serverAddressHint => 'IPv4 or IPv6; IPv6 can be entered as [::1]';

  @override
  String get serverPort => 'Port';

  @override
  String get serverPortHint => 'DNS usually uses 53, DoT usually 853';

  @override
  String get serverUnavailable => 'Unavailable on this device';

  @override
  String get serverBatteryJoined =>
      'Added to the battery optimisation allowlist';

  @override
  String get serverBatteryNotJoined =>
      'Not in the battery optimisation allowlist yet';

  @override
  String get serverClearCache => 'Clear cache';

  @override
  String get serverClear => 'Clear';

  @override
  String get serverClearCacheBody =>
      'Cached answers will be cleared, so the next lookup goes upstream again.';

  @override
  String get serverCacheCleared => 'Cache cleared';

  @override
  String get serverCacheClearFailed =>
      'Clearing failed: start the DNS service first';

  @override
  String serverCacheOn(String preset) {
    return '$preset · cache hits no longer go upstream';
  }

  @override
  String get serverCacheOff => 'Off · every lookup goes to the upstream DNS';

  @override
  String get serverModeSettings => 'Mode settings';

  @override
  String get serverProxySettings => 'Proxy and resolution';

  @override
  String get serverCacheSettings => 'Cache settings';

  @override
  String get serverRuleControl => 'Rule control';

  @override
  String get serverRuleControlOn =>
      'On · matched rules return the blocking policy';

  @override
  String get serverRuleControlOff =>
      'Off · a separate filter rule library is used';

  @override
  String get serverListenPort => 'Local listen port';

  @override
  String get serverListenPortBody =>
      'The port the DNS service listens on; the default is 1053';

  @override
  String get serverRuleManagement => 'Rule management';

  @override
  String get serverBlocklist => 'Blocklist';

  @override
  String get serverBlocklistBody =>
      'Manage domain blocking rules in a separate library';

  @override
  String get serverAllowlist => 'Allowlist';

  @override
  String get serverAllowlistBody =>
      'Manage domain allow rules in a separate library';

  @override
  String get serverHosts => 'Hosts overrides';

  @override
  String get serverHostsBody =>
      'Resolve chosen domains to a configured IP or CNAME';

  @override
  String get serverRulesFooter =>
      'These three tables only affect the server mode rule library and never override normal mode rules.';

  @override
  String get serverDataReset => 'Data and reset';

  @override
  String get serverResetStats => 'Reset runtime statistics';

  @override
  String get serverResetStatsBody => 'Clear the statistics for this run';

  @override
  String get serverBackground => 'Background stability';

  @override
  String get serverBackgroundBody =>
      'The system freezes apps outside the power-saving allowlist; add this app to it so the DNS service keeps answering LAN queries with the screen off.';

  @override
  String get serverRunMode => 'Run mode';

  @override
  String get serverWizard => 'Setup guide';

  @override
  String get serverWizardBody =>
      'See how server mode works, how to configure the LAN and how to get ready';

  @override
  String get serverReselectMode => 'Choose the work mode again';

  @override
  String get serverReselectModeBody =>
      'Review every work mode and choose again';

  @override
  String get serverBatteryIgnored => 'Battery optimisation ignored';

  @override
  String get serverBatteryIgnoredShort => 'Ignored';

  @override
  String get serverBatteryKeepAlive =>
      'Keeps the DNS service running in the background';

  @override
  String get serverIgnoreBattery => 'Ignore battery optimisation';

  @override
  String get serverCachePresetConservative => 'Conservative';

  @override
  String get serverCachePresetHighHit => 'High hit rate';

  @override
  String get serverCachePresetStandard => 'Standard';

  @override
  String get serverNavOverview => 'Overview';

  @override
  String get serverPortInvalid => 'Enter a number';

  @override
  String serverPortRange(String max, String min) {
    return 'Range $min–$max';
  }

  @override
  String serverPortChanged(String port) {
    return 'The port is now $port; restart the service to apply';
  }

  @override
  String get serverResetConfirm => 'Reset';

  @override
  String get serverResetStatsConfirmBody =>
      'All statistics for this run will be cleared. Continue?';

  @override
  String get serverStatsReset => 'Runtime statistics reset';

  @override
  String get serverOverviewTitle => 'Diting · Server mode';

  @override
  String get serverSwitchMode => 'Switch work mode';

  @override
  String get serverChangePort => 'Change the listen port';

  @override
  String get serverCurrentUpstreamCard => 'Current upstream';

  @override
  String get serverLanAccess => 'LAN access';

  @override
  String get serverLanBody =>
      'Point devices on the same subnet at the address above; the port is bound only at startup, so restart the service after changing it.';

  @override
  String get serverNoNetwork => 'No network';

  @override
  String get serverLanConnectHint =>
      'An available address appears here once you are on Wi-Fi or Ethernet';

  @override
  String get serverLanPointHint =>
      'Point other LAN devices\' DNS at this address';

  @override
  String serverCopied(String text) {
    return 'Copied $text';
  }

  @override
  String get serverServiceStatus => 'Service status';

  @override
  String get serverTotalQueries => 'Total queries';

  @override
  String get serverCacheHits => 'Cache hits';

  @override
  String get serverBlocked => 'Blocked';

  @override
  String get serverAverageLatency => 'Average latency';

  @override
  String get serverUptime => 'Uptime';

  @override
  String get serverResetStatsBodyShort =>
      'Clear every counter for this run without touching rules or cache';

  @override
  String get serverModeSettingsBody =>
      'Cache, rules, background stability and run mode';

  @override
  String get serverModeNote =>
      'Server mode creates no VPN tunnel: it only listens on a DNS port locally, so it coexists with other VPNs and takes no VPN slot; this device\'s own app queries do not go through it automatically.';

  @override
  String get serverBusyStarting => 'Starting';

  @override
  String get serverBusyStopping => 'Stopping';

  @override
  String get serverRunning => 'Stop';

  @override
  String get serverStopped => 'Start';

  @override
  String serverListening(String port) {
    return 'Listening on 0.0.0.0:$port';
  }

  @override
  String get serverStatusStopped => 'Server mode is stopped';

  @override
  String get serverStatusStarting => 'Starting the service...';

  @override
  String get serverStatusRunning => 'Server mode is running';

  @override
  String get serverStatusStopping => 'Stopping the service...';

  @override
  String get serverStatusErrorText =>
      'Service error: the port may already be in use';

  @override
  String get troubleshootTitle => 'Troubleshooting';

  @override
  String get troubleshootRuntimeLogs => 'Runtime logs';

  @override
  String get troubleshootRecordLogs => 'Record runtime logs';

  @override
  String get troubleshootExportLogs => 'Export runtime logs';

  @override
  String get troubleshootClearLogs => 'Clear runtime logs';

  @override
  String get troubleshootClearLogsBody =>
      'Delete every runtime log file recorded locally';

  @override
  String get troubleshootRecordNote =>
      'Off by default. While on, a status notification is shown and recording stops when the app closes or you turn it off; logs stay on this device and are never uploaded automatically.';

  @override
  String get troubleshootLocalDb => 'Local database';

  @override
  String get troubleshootWriteStatus => 'Log write status';

  @override
  String get troubleshootWriteStatusNote =>
      'Logs, race records and traffic statistics are written straight into the local database in the background. Dropped rows or open failures usually mean the database was locked for a long time; tap to read again, and export the runtime logs if it keeps happening.';

  @override
  String get troubleshootCrashLogs => 'Crash logs';

  @override
  String get troubleshootExportCrashes => 'Export crash logs';

  @override
  String get troubleshootClearCrashes => 'Clear crash logs';

  @override
  String get troubleshootClearCrashesBody =>
      'Delete every crash file recorded locally';

  @override
  String get troubleshootCrashNote =>
      'When an uncaught exception happens, diagnostics and key logs are saved on the device only; export them to report the problem.';

  @override
  String get troubleshootCaptureWarning =>
      'Capturing runtime logs keeps reading and writing a few files, which may raise power use, increase storage usage or have other unknown effects, so turn it off when done. The exported file can be sent to the developer; describing the symptom and when it happened helps pinpoint the cause.';

  @override
  String get troubleshootReadingStatus => 'Reading capture status…';

  @override
  String troubleshootRecording(String size) {
    return 'Recording, using $size; tap again to stop';
  }

  @override
  String troubleshootStoppedWithLogs(String size) {
    return 'Stopped; $size of logs are available to export';
  }

  @override
  String get troubleshootStoppedNoLogs =>
      'Stopped; runtime logs are only recorded while on';

  @override
  String get troubleshootReadingLogs => 'Reading local logs…';

  @override
  String get troubleshootNoLogs => 'There are no runtime logs on this device';

  @override
  String troubleshootLogCount(int count, String size) {
    return '$count files, $size; tap to export';
  }

  @override
  String get troubleshootReadingHealth => 'Reading write status…';

  @override
  String get troubleshootHealthy => 'Healthy, no logs were dropped';

  @override
  String troubleshootHealthyDetail(String detail, String mode) {
    return 'Healthy, no logs were dropped ($mode · $detail)';
  }

  @override
  String troubleshootDropped(
    int dropped,
    String failed,
    int reason,
    String split,
  ) {
    return '$dropped logs dropped$split, $failed open failures$reason';
  }

  @override
  String get troubleshootOverflow => 'Queue overflow';

  @override
  String get troubleshootTableMissing => 'Missing table';

  @override
  String get troubleshootNoDatabase => 'No database';

  @override
  String get troubleshootClosed => 'Unfinished when stopped';

  @override
  String get troubleshootReadingCrashes => 'Reading crash logs on this device…';

  @override
  String get troubleshootNoCrashes => 'There are no crash logs on this device';

  @override
  String troubleshootCrashCount(int count) {
    return '$count crash logs recorded; tap to export';
  }

  @override
  String get troubleshootStoppedToast => 'Stopped recording runtime logs';

  @override
  String get troubleshootStartTitle => 'Start capturing runtime logs';

  @override
  String get troubleshootCancel => 'Cancel';

  @override
  String get troubleshootConfirmStart => 'Start';

  @override
  String get troubleshootStartBody =>
      'This feature mainly helps the developer diagnose problems: while on, the app\'s runtime logs are recorded continuously to local storage.\n\nCapturing may raise power use, increase storage usage or have other unknown effects. Unless you are troubleshooting, turn it off when done.\n\nLogs stay on this device and recording stops when you turn it off; you can export and send them to the developer yourself.';

  @override
  String get troubleshootStartedToast => 'Started recording runtime logs';

  @override
  String get troubleshootStartFailedToast =>
      'Cannot start capturing logs; try again later';

  @override
  String get troubleshootNoExportableLogs =>
      'There are no runtime logs to export';

  @override
  String get troubleshootExportFailed =>
      'Export failed: there is no writable export directory';

  @override
  String troubleshootExported(String path) {
    return 'Exported to $path';
  }

  @override
  String get troubleshootConfirm => 'Confirm';

  @override
  String get troubleshootClearLogsConfirm =>
      'Clear all saved runtime logs? This cannot be undone.';

  @override
  String troubleshootClearedLogs(String count) {
    return 'Cleared $count log files';
  }

  @override
  String get troubleshootNoClearableLogs =>
      'There are no runtime logs to clear';

  @override
  String get troubleshootNoExportableCrashes =>
      'There are no crash logs to export';

  @override
  String get troubleshootClearCrashesConfirm => 'Clear all saved crash logs?';

  @override
  String troubleshootClearedCrashes(String count) {
    return 'Cleared $count crash logs';
  }

  @override
  String get troubleshootNoClearableCrashes =>
      'There are no crash logs to clear';

  @override
  String get bypassAddTitle => 'Add a bypass domain';

  @override
  String get bypassAdd => 'Add';

  @override
  String get bypassSuffix => 'Domain suffix';

  @override
  String get bypassSuffixBody =>
      'Matches the suffix and its subdomains; excluded from HTTPS decryption';

  @override
  String get mirrorGlobal => 'Global mirror';

  @override
  String get mirrorDefault => 'Download through the mirror by default';

  @override
  String get mirrorNeedTemplate => 'Add a template before enabling this';

  @override
  String get mirrorTemplateNote =>
      'Subscription downloads and app updates both go through the chosen template';

  @override
  String get mirrorTemplate => 'Template in use';

  @override
  String get mirrorNote =>
      'When on, subscriptions without their own mirror, update checks and package downloads all try the mirror first and fall back to the original address if it fails. Subscriptions with their own mirror keep their own settings.';

  @override
  String get hiddenFeaturesTitle => 'Hidden features';

  @override
  String get hiddenFeaturesReset => 'Show everything again';

  @override
  String get hiddenFeaturesNote =>
      'Choose which cards the feature hub shows. Turning a switch off hides that card from the hub; everything is shown by default. Hiding only changes the UI and never affects background behaviour or rule enforcement. The setting is stored on this device and survives restarts.';

  @override
  String get hiddenFeaturesFooter =>
      'The \"Hidden features\" card always stays so you can restore cards from here at any time.';

  @override
  String get cacheSettingsTitle => 'Cache settings';

  @override
  String get cacheSection => 'Cache';

  @override
  String get cacheLocalDns => 'Local DNS cache';

  @override
  String get cacheOffNote => 'When off, every lookup goes to the upstream DNS';

  @override
  String get cachePresetSection => 'Cache preset';

  @override
  String get cachePresetNote =>
      'Standard is recommended. Presets set the maximum TTL, minimum TTL and failure fallback automatically, so no manual seconds are needed.';

  @override
  String get recognitionSponsorTitle => 'Sponsors';

  @override
  String get recognitionSponsorIntro =>
      'Thanks to everyone who supports Diting! The list is ordered by sponsorship time, earliest first, and the button in the corner reverses it; the amount is not shown because every contribution matters equally.';

  @override
  String get recognitionSponsorSection => 'Sponsors';

  @override
  String get recognitionBuilderTitle => 'Contributors';

  @override
  String get recognitionBuilderIntro =>
      'Thanks to everyone who suggested ideas and helped test Diting! Names are sorted alphabetically, with Chinese names sorted by pinyin.';

  @override
  String get recognitionBuilderSection => 'Contributors';

  @override
  String get providerVisibilityTitle => 'Provider visibility';

  @override
  String get providerVisibilityNote =>
      'With race mode off, the resolver picker on the home page only shows the providers selected here. The one currently in use is always kept.';

  @override
  String providerVisibilityProtocol(String protocol) {
    return '$protocol providers';
  }

  @override
  String providerVisibilityAll(String protocol) {
    return 'All $protocol providers';
  }

  @override
  String get providerVisibilityNone => 'Hide this provider type';

  @override
  String get providerVisibilityAllOn => 'Show every provider of this type';

  @override
  String providerVisibilityCount(String count) {
    return '$count providers selected';
  }

  @override
  String get markdownCopyCode => 'Copy code';

  @override
  String get markdownCodeCopied => 'Code copied to the clipboard';

  @override
  String get recognitionUpdated => 'The list was updated';

  @override
  String get recognitionRefresh => 'Refresh the list';

  @override
  String get recognitionSortAsc => 'Sort oldest first';

  @override
  String get recognitionSortDesc => 'Sort newest first';

  @override
  String get recognitionEmpty => 'No list yet';

  @override
  String get recognitionLoadFailed => 'The list could not be loaded';

  @override
  String get recognitionEmptyBody =>
      'The list is delivered from the cloud; tap to fetch it.';

  @override
  String get recognitionLoad => 'Load the list';

  @override
  String get recognitionRetry => 'Retry';

  @override
  String get recognitionNoMembers => 'No members yet';

  @override
  String get recognitionNoMembersBody =>
      'The list updates with the cloud configuration; check back later.';

  @override
  String get recognitionRefreshShort => 'Refresh';

  @override
  String get recognitionCached => 'Showing the locally cached list';

  @override
  String recognitionLastUpdate(String time) {
    return 'Last updated: $time';
  }

  @override
  String get recognitionCloudNote =>
      'The list comes from the cloud and is checked for updates when you open the page';

  @override
  String appRulesAllowCount(String count, int package) {
    return '$package · $count allowed domains';
  }

  @override
  String get appRulesConfigured => 'Configured';

  @override
  String get appRulesSystem => 'System';

  @override
  String get appRulesIncludeSub => 'Includes subdomains';

  @override
  String get appRulesDelete => 'Delete';

  @override
  String get appRulesAddDomainTitle => 'Add an allowed domain';

  @override
  String get appRulesCancel => 'Cancel';

  @override
  String get appRulesAdd => 'Add';

  @override
  String get appRulesDomain => 'Domain';

  @override
  String get appRulesDomainHint =>
      'Enter the bare domain only; subdomains are included, so no wildcard or @@ prefix is needed';

  @override
  String get appRulesAllowlistRow => 'Allowlist (allowed)';

  @override
  String get appRulesBlocklistRow => 'Blocklist (blocked)';

  @override
  String get appRulesImportant => 'Important';

  @override
  String get appRulesDisable => 'Disable';

  @override
  String get appRulesEnable => 'Enable';

  @override
  String get appRulesAddRuleTitle => 'Add a DNS rule';

  @override
  String get appRulesRuleDomainHint =>
      'Enter the bare domain only; it applies to this app only';

  @override
  String get appRulesBlocklist => 'Blocklist';

  @override
  String get appRulesAllowlist => 'Allowlist';

  @override
  String get logRetentionTitle => 'Log mode';

  @override
  String get logRetentionDnsLogs => 'DNS request logs';

  @override
  String get logRetentionOffNote =>
      'Turning this off does not delete existing logs; turn it back on to keep reading them.';

  @override
  String get logRetentionOverlay => 'Floating window';

  @override
  String get logRetentionOverlayLogs => 'Floating window logs';

  @override
  String get logRetentionOverlayBody =>
      'Shows a floating bubble while the VPN runs in the background; tap it to see live requests';

  @override
  String get logRetentionOverlayNote =>
      'The bubble hides automatically when the app returns to the foreground. Normal mode only.';

  @override
  String get logRetentionCleanup => 'Automatic cleanup';

  @override
  String logRetentionKeepDays(String days) {
    return 'Keep $days days';
  }

  @override
  String get logRetentionCleanupNote =>
      'Request logs older than the selected age are cleaned up hourly by the tunnel service (the first run is 30 seconds after start). Turning logs off does not delete existing records.';

  @override
  String get appBlockTitle => 'Apps blocked from the internet';

  @override
  String get appBlockInfo =>
      'Blocks all network access for the selected apps by UID through the local VPN. Apps sharing the same UID are affected too.';

  @override
  String get appBlockToggle => 'Block the internet';

  @override
  String get appBlockToggleEmpty =>
      'No apps selected yet; enabling blocks nothing';

  @override
  String get appBlockSelection => 'Blocked apps';

  @override
  String get appExcludeTitle => 'Excluded apps';

  @override
  String get appExcludeInfo =>
      'Excluded apps use the system DNS and take no part in this app\'s filtering, cache, logs or statistics.';

  @override
  String get appExcludeSelection => 'Excluded apps';

  @override
  String get appSelectionSaved =>
      'Saved; it takes effect once the DNS VPN starts';

  @override
  String get appSelectionSaveTitle => 'Save changes?';

  @override
  String appSelectionSaveBody(String title) {
    return 'The selection for \"$title\" is not saved. Save it before leaving, or discard the changes?';
  }

  @override
  String get appSelectionSwitch => 'Switch';

  @override
  String get appSelectionNoAppsYet => 'No apps selected yet';

  @override
  String appSelectionCount(String count) {
    return '$count apps selected';
  }

  @override
  String get appSelectionNoAppsAvailable =>
      'There are no selectable apps on this device';

  @override
  String get appSelectionNoMatch => 'No matching apps';

  @override
  String get appSelectionSave => 'Save';

  @override
  String get appSelectionNothingRead =>
      'No installed apps could be read, so any selection saved here matches nothing.';

  @override
  String get appSelectionExclusiveNote =>
      'Selecting an app clears its selection under Excluded apps, Blocked apps, HTTPS inspection and per-app rules.';

  @override
  String get bootstrapTitle => 'Bootstrap resolution';

  @override
  String get bootstrapAdd => 'Add a Bootstrap IP';

  @override
  String get bootstrapGlobal => 'Global switch';

  @override
  String get bootstrapEnable => 'Enable Bootstrap IP';

  @override
  String get bootstrapEnableBody =>
      'Resolves encrypted provider domains with a separate recursive DNS, with weighted selection and automatic fallback';

  @override
  String get bootstrapEnableNote =>
      'When on, Bootstrap IPs are chosen dynamically with a weighted algorithm; when off, encrypted upstream domains are resolved through the system DNS.';

  @override
  String get bootstrapBuiltin => 'Built-in Bootstrap IPs';

  @override
  String get bootstrapCustom => 'Custom Bootstrap IPs';

  @override
  String get bootstrapNoCustom =>
      'No custom Bootstrap IPs yet. Tap \"Add\" in the corner to create one.';

  @override
  String bootstrapNoSample(String ip) {
    return '$ip · no samples';
  }

  @override
  String bootstrapAverage(String ms) {
    return ' · average ${ms}ms';
  }

  @override
  String bootstrapFailures(String count) {
    return ' · $count failed';
  }

  @override
  String bootstrapStats(
    String failures,
    String ip,
    String latency,
    String samples,
    String success,
  ) {
    return '$ip$latency · $samples samples · $success% succeeded$failures';
  }

  @override
  String get bootstrapInvalidIp => 'Enter a valid IPv4 or IPv6 address';

  @override
  String get bootstrapNameOptional => 'Name (optional)';

  @override
  String get bootstrapIpAddress => 'IP address';

  @override
  String get caCertTitle => 'CA certificate settings';

  @override
  String get caCertStatusMissing =>
      'Not generated yet: the engine has not produced ca.crt';

  @override
  String get caCertStatusUntrusted =>
      'Generated, but not installed in the system trust store';

  @override
  String get caCertStatusTrusted => 'Generated and trusted by the system';

  @override
  String get caCertSectionStatus => 'Certificate status';

  @override
  String get caCertRootStatus => 'Root certificate status';

  @override
  String get caCertVerified => 'Verified';

  @override
  String get caCertUnverified => 'Not verified';

  @override
  String get caCertReadFailed => 'Read failed';

  @override
  String get caCertStatusFooter =>
      'Traffic inspection only works with a verified root certificate; apps that use certificate pinning (SSL Pinning) are bypassed automatically.';

  @override
  String get caCertSectionActions => 'Certificate actions';

  @override
  String get caCertGuide => 'Install and remove guide';

  @override
  String get caCertGuideSubtitle =>
      'How to install, remove and stay safe with the system certificate on each device';

  @override
  String get caCertInstall => 'Install root certificate';

  @override
  String get caCertInstallSubtitle =>
      'Hands off to the system installer; Android 11 and later still need a manual confirmation in Settings';

  @override
  String get caCertInstalled => 'Installed';

  @override
  String get caCertNotInstalled => 'Not installed';

  @override
  String get caCertSaveToDownloads => 'Save certificate to Downloads';

  @override
  String get caCertSaveToDownloadsSubtitle =>
      'The .crt in Downloads can be installed by hand from system settings';

  @override
  String get caCertFingerprint => 'Certificate fingerprint';

  @override
  String get caCertNoFingerprint =>
      'There is no fingerprint until a certificate is generated';

  @override
  String get caCertFingerprintSubtitle =>
      'SHA-256 (tap to see the full fingerprint)';

  @override
  String get caCertViewPem => 'View certificate';

  @override
  String get caCertViewPemSubtitle =>
      'Shown as copyable PEM text so it can be installed elsewhere';

  @override
  String get caCertSectionManage => 'Certificate management';

  @override
  String get caCertRegenerate => 'Regenerate root certificate';

  @override
  String get caCertRegenerateSubtitle =>
      'Revokes the current private key and creates a new certificate; reinstall afterwards';

  @override
  String get caCertNoCertificate =>
      'No certificate is available yet; tap \"Regenerate root certificate\" first';

  @override
  String get caCertInstallDialogBody =>
      'Android only lets the user install a root certificate into the \"CA certificate\" section by hand; the app cannot write to the system trust store silently.\n\nTapping \"Continue\" first saves a certificate file to Downloads and then tries to open the system installer. If the installer only points at Settings, pick that file manually under \"Settings → Security → Encryption & credentials → Install a certificate → CA certificate\".';

  @override
  String caCertSavedTo(String name) {
    return 'The certificate was saved to $name.';
  }

  @override
  String get caCertDownloadsDir => 'Downloads';

  @override
  String caCertSaveFailed(String error) {
    return 'Saving the certificate file failed ($error).';
  }

  @override
  String get caCertOpenedInstaller =>
      'The system certificate installer was opened.';

  @override
  String get caCertOpenedSettings =>
      'This system has no certificate installer, so security settings were opened.';

  @override
  String get caCertInstallerUnavailable =>
      'Could not open the certificate installer.';

  @override
  String get caCertManualHint =>
      'If the screen only points at Settings, select it manually under \"Encryption & credentials → Install a certificate → CA certificate\".';

  @override
  String caCertSavedHint(String name) {
    return 'Saved to $name; select it under \"Encryption & credentials → Install a certificate\"';
  }

  @override
  String get caCertDownloadsFailed => 'Could not write to Downloads';

  @override
  String get caCertRegenerateTitle => 'Regenerate the root certificate?';

  @override
  String get caCertRegenerateBody =>
      'The existing ca.crt / ca.key and the blocklist cache are deleted. The installed certificate stops working immediately, every previously trusted connection needs the new certificate, and HTTPS inspection is turned off automatically.';

  @override
  String get caCertRegenerateAction => 'Regenerate';

  @override
  String caCertGenerateFailed(String error) {
    return 'Generation failed: $error';
  }

  @override
  String get caCertGenerated =>
      'A new certificate was generated; install it from system settings';

  @override
  String get caCertFingerprintTitle => 'Certificate fingerprint (SHA-256)';

  @override
  String get caCertFingerprintCopied => 'Fingerprint copied';

  @override
  String get caCertPemTitle => 'Root certificate PEM';

  @override
  String get caCertPemCopied => 'Certificate copied';

  @override
  String get caCertGuideTitle => 'CA certificate guide';

  @override
  String get caCertWhyTitle => 'Why installation is required';

  @override
  String get caCertWhyBody =>
      'HTTPS traffic inspection needs a local decryption channel on the device. The system only trusts root certificates installed by hand in the \"user\" certificate store, and the app cannot tap that step for you.';

  @override
  String get caCertStepsTitle => 'Installation steps';

  @override
  String get caCertStep1 =>
      '1. Tap \"Install root certificate\" in \"CA certificate settings\"; the app saves the file to Downloads and hands it to the system installer.';

  @override
  String get caCertStep2 =>
      '2. Since Android 11 the system installer usually only points at Settings; that is a platform limit, not an app fault. Select the .crt file from Downloads under \"Settings → Security → Encryption & credentials → Install a certificate → CA certificate\".';

  @override
  String get caCertStep3 =>
      '3. The system asks for the screen lock or fingerprint; installation is impossible without one, so set a PIN first.';

  @override
  String get caCertStep4 =>
      '4. Come back to this page; the status should read \"Verified\". If not, leave and reopen the page to check again.';

  @override
  String get caCertWhichAppsTitle => 'Which apps can be inspected';

  @override
  String get caCertWhichAppsBody =>
      'The system only trusts root certificates in the \"user\" store, and apps with targetSdk 24 (Android 7.0) or later do not trust user certificates by default. Only apps whose network security config allows user CAs can have their HTTPS decrypted and read in plain text.';

  @override
  String get caCertWhichAppsWarning =>
      'HTTPS requests from other apps are recorded as \"failed / client_tls\" because of certificate pinning or system policy. That is expected; add those apps to the bypass rules.';

  @override
  String get caCertRiskTitle => 'Removal and risks';

  @override
  String get caCertRiskWarning =>
      'Once the root certificate is in the user trust store, any software holding the matching private key can decrypt this device\'s traffic. When you no longer need it, delete it in system settings and tap \"Regenerate root certificate\" here to revoke the old key.';

  @override
  String get caCertRiskPinning =>
      'Some apps use certificate pinning (SSL Pinning) and still fail to connect after the certificate is installed; add them to the bypass rules instead of reinstalling the certificate over and over.';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonUnknownReason => 'Unknown reason';

  @override
  String get autoUpdateTitle => 'Auto-update settings';

  @override
  String get autoUpdateSection => 'Auto-update';

  @override
  String get autoUpdateRulesSwitch => 'Auto-update rule subscriptions';

  @override
  String get autoUpdateRulesSwitchSubtitle =>
      'Checks for due subscriptions on launch, when returning to the foreground, or at the set time';

  @override
  String get autoUpdateIntervalSection => 'Update frequency';

  @override
  String autoUpdateEveryHours(int hours) {
    return 'Every $hours hours';
  }

  @override
  String get autoUpdateCustomInterval => 'Custom interval';

  @override
  String get autoUpdateCustomHint =>
      'Enter an interval between 1 and 168 hours';

  @override
  String get autoUpdateTimedSection => 'Update at a set time';

  @override
  String autoUpdateDailyAt(String time) {
    return 'Every day at $time';
  }

  @override
  String autoUpdateEveryOtherDayAt(String time) {
    return 'Every other day at $time';
  }

  @override
  String get autoUpdateTimedPickHint => 'Tap to pick the time';

  @override
  String get autoUpdateTimedChangeHint => 'Tap to change the time';

  @override
  String get autoUpdateIntervalFooter =>
      'Settings are stored in the dataset of the current work mode (normal, speed and server each keep their own). Timed updates follow the phone\'s clock and time zone; if the chosen time has already passed today, counting starts from the next one. There is no background task queue: while the app is in the foreground the update runs on time, otherwise it catches up on the next launch or return to the foreground, and never runs while the process is closed.';

  @override
  String get autoUpdateStatusSection => 'Run status';

  @override
  String get autoUpdateNext => 'Next update';

  @override
  String get autoUpdateLast => 'Last auto-update';

  @override
  String get autoUpdateNoRunYet => 'No auto-update has run in this session';

  @override
  String autoUpdateRunCount(int count) {
    return ' ($count subscriptions)';
  }

  @override
  String get autoUpdateStatusFooter =>
      'With an interval, each subscription\'s last attempt is compared with the interval; with a set time, a subscription is due when it has not been attempted since the most recent scheduled time. A manual update in progress makes this round step aside.';

  @override
  String get autoUpdateGroupsSection => 'Per-group auto-update';

  @override
  String get autoUpdateReadingGroups => 'Reading groups…';

  @override
  String get autoUpdateNoGroups => 'No groups yet';

  @override
  String get autoUpdateNoGroupsSubtitle =>
      'Create a group on the rule subscription page to toggle it here';

  @override
  String get autoUpdateGroupsFooter =>
      'Only remote subscriptions in enabled groups are updated automatically; stored in the `subscription_group` table.';

  @override
  String get autoUpdateReadingSubs => 'Reading subscriptions…';

  @override
  String get autoUpdateNoCandidates =>
      'No subscription can be auto-updated (it must be remote, enabled, and in an enabled group)';

  @override
  String get autoUpdateDueNow =>
      'Due now: it runs right away while the app is in the foreground';

  @override
  String autoUpdateRemainingHours(int hours, int minutes) {
    return 'in $hours h $minutes min';
  }

  @override
  String autoUpdateRemainingMinutes(int minutes) {
    return 'in $minutes min';
  }

  @override
  String autoUpdateNextAt(String moment, String left) {
    return '$moment ($left)';
  }

  @override
  String autoUpdateMoment(int month, int day, String time) {
    return '$month/$day $time';
  }

  @override
  String get autoUpdateIntervalLabel => 'Update interval (hours)';

  @override
  String get autoUpdateIntervalHelper => '1–168 hours';

  @override
  String get mirrorTplTitle => 'Mirror templates';

  @override
  String get mirrorTplAdd => 'Add template';

  @override
  String get mirrorTplIntro =>
      'Save the mirrors you use often. With the global mirror on, subscriptions and app updates use the selected template by default; a single subscription can also pick its own template.';

  @override
  String get mirrorTplActions => 'Actions';

  @override
  String get mirrorTplFormatExample => 'Mirror format example';

  @override
  String get mirrorTplFormatExampleSubtitle =>
      'See how placeholders make up a mirror address';

  @override
  String get mirrorTplSaved => 'Saved templates';

  @override
  String get mirrorTplReadFailed => 'Could not read mirror templates';

  @override
  String get mirrorTplReadFailedSubtitle =>
      'The legacy database is not ready or the table is unavailable';

  @override
  String mirrorTplSavedCount(int count) {
    return 'Saved templates ($count)';
  }

  @override
  String get mirrorTplReading => 'Reading mirror templates…';

  @override
  String get mirrorTplEmpty =>
      'No templates yet. Tap \"Add template\" in the top right to start.';

  @override
  String get mirrorTplDuplicate =>
      'A template with this name already exists; choose another name';

  @override
  String get mirrorTplDuplicateSave =>
      'Save failed: the name matches an existing template';

  @override
  String get mirrorTplFormatTitle => 'Mirror format';

  @override
  String get mirrorTplFormatIntro =>
      'A mirror address is a fixed prefix plus placeholders; the placeholders are replaced with the real link when a subscription is downloaded.';

  @override
  String mirrorTplFormatUrl(String token) {
    return '$token: full subscription URL';
  }

  @override
  String mirrorTplFormatScheme(String token) {
    return '$token: http or https';
  }

  @override
  String mirrorTplFormatUrlEncoded(String token) {
    return '$token: full URL-encoded address';
  }

  @override
  String mirrorTplFormatHost(String token) {
    return '$token: subscription host';
  }

  @override
  String mirrorTplFormatPath(String token) {
    return '$token: path part';
  }

  @override
  String mirrorTplFormatPathAndQuery(String token) {
    return '$token: path and query';
  }

  @override
  String mirrorTplFormatSample(String token) {
    return 'Example: https://ghproxy.example.com/$token';
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
    return 'Available placeholders: $url, $scheme, $urlEncoded, $host, $path, $pathAndQuery';
  }

  @override
  String get mirrorTplNameLabel => 'Template name';

  @override
  String get mirrorTplNameHint => 'For example: GitHub mirror';

  @override
  String get mirrorTplAddressLabel => 'Template address';

  @override
  String get mirrorTplInvalid =>
      'Must use HTTP(S) and contain at least one placeholder';

  @override
  String get mirrorTplAddTitle => 'Add mirror template';

  @override
  String get mirrorTplEditTitle => 'Edit mirror template';

  @override
  String get commonEdit => 'Edit';

  @override
  String get ruleControlUrlNotReadyCa =>
      'Not ready · install and verify the CA root certificate first';

  @override
  String get ruleControlUrlNotReadyInspection =>
      'Not ready · turn it on in HTTPS traffic inspection';

  @override
  String get ruleControlUrlNotReadyApps =>
      'Not ready · pick target apps in HTTPS traffic inspection';

  @override
  String get ruleControlUrlPaused =>
      'Paused · URL filtering and redirects for decrypted traffic are off';

  @override
  String get ruleControlUrlRunning =>
      'Running · decrypted traffic is matched against URL block, allow and redirect rules';

  @override
  String get ruleControlIntro =>
      'One place for the master switches of domain filtering, URL rules and rule overrides, the block policy and online rule subscriptions. Block, allow and override lists are still managed separately in the hub.';

  @override
  String get ruleControlFilterSection => 'Filtering and override control';

  @override
  String get ruleControlDomainRules => 'Enable domain rules';

  @override
  String get ruleControlDomainRulesOn =>
      'Blocks, allows and overrides IPv4/IPv6 at the DNS stage';

  @override
  String get ruleControlDomainRulesOff =>
      'DNS domain filtering is off; every query is passed through';

  @override
  String get ruleControlUrlRules => 'URL rules and content filtering';

  @override
  String get ruleControlNotReady => 'Not ready';

  @override
  String get ruleControlPolicySection => 'Block policy';

  @override
  String get ruleControlBlockResponse => 'Block response';

  @override
  String ruleControlDynamicSummary(String mode) {
    return 'Dynamic policy: NODATA first, then $mode for frequent requests';
  }

  @override
  String get ruleControlSubsSection => 'Subscriptions and updates';

  @override
  String get ruleControlSubsSubtitle =>
      'Manage domain rule and IPv4/IPv6 override sources and groups';

  @override
  String ruleControlCount(int count) {
    return '$count';
  }

  @override
  String ruleControlAutoUpdateOn(int hours) {
    return 'On · auto-updates every $hours hours';
  }

  @override
  String ruleControlAutoUpdateDaily(String time) {
    return 'On · auto-updates every day at $time';
  }

  @override
  String ruleControlAutoUpdateEveryOtherDay(String time) {
    return 'On · auto-updates every other day at $time';
  }

  @override
  String get ruleControlAutoUpdateOff => 'Auto-update is off';

  @override
  String get ruleControlMirrorSubtitle =>
      'Manage download mirrors that can be picked when adding a subscription';

  @override
  String get blockResponseFixedSection => 'Fixed response';

  @override
  String get blockResponseFixedFooter =>
      'While the dynamic policy is on it overrides the choice above: NODATA first, then NXDOMAIN for frequent requests.';

  @override
  String get blockResponseDynamicSection => 'Dynamic policy';

  @override
  String get blockResponseEnableDynamic => 'Enable dynamic policy';

  @override
  String get blockResponseEnableDynamicSubtitle =>
      'All record types of a domain share one counter';

  @override
  String get blockResponseParameters => 'Dynamic parameters';

  @override
  String blockResponseParamsSummary(int threshold, int window, int duration) {
    return '$threshold requests / $window s / hold $duration s';
  }

  @override
  String get blockResponseDynamicFooter =>
      'Well-behaved clients cache the NODATA answer. The dynamic policy mainly targets clients that keep retrying or ignore negative caching.';

  @override
  String get blockResponseThresholdError =>
      'Requests must be between 2 and 100';

  @override
  String get blockResponseWindowError =>
      'The counting window must be between 10 and 300 seconds';

  @override
  String get blockResponseDurationError =>
      'The hold time must be between 60 and 3600 seconds';

  @override
  String get blockResponseThresholdLabel => 'Requests';

  @override
  String get blockResponseThresholdHelper => '2–100; upgrades from request N+1';

  @override
  String get blockResponseWindowLabel => 'Counting window (seconds)';

  @override
  String get blockResponseWindowHelper => '10–300 seconds';

  @override
  String get blockResponseDurationLabel => 'NXDOMAIN hold time (seconds)';

  @override
  String get blockResponseDurationHelper =>
      '60–3600 seconds; timed from the first upgrade';

  @override
  String get httpInspCheckingCa => 'Checking the root certificate…';

  @override
  String get httpInspNoAppsHint =>
      'No target app selected; only DNS filtering stays on';

  @override
  String httpInspSelectedHint(int count) {
    return '$count apps selected; everything else is forwarded directly';
  }

  @override
  String get httpInspScopeSection => 'Scope';

  @override
  String get httpInspEnable => 'Enable HTTPS inspection';

  @override
  String get httpInspTargetApps => 'Target apps';

  @override
  String get httpInspNoApps => 'No app selected';

  @override
  String httpInspSelectedApps(int count) {
    return '$count apps selected';
  }

  @override
  String get httpInspCaCert => 'CA certificate';

  @override
  String get httpInspCaReady =>
      'The certificate is installed and the fingerprint matches; view or reset it';

  @override
  String get httpInspContentSection => 'Decrypted content filtering';

  @override
  String get httpInspUrlRules => 'Enable URL rules and redirects';

  @override
  String get httpInspNeedEnable => 'Enable HTTPS inspection first';

  @override
  String get httpInspUrlPaused =>
      'Paused · decrypted requests pass through without URL rules or CNAME redirects';

  @override
  String get httpInspUrlOn =>
      'Applies URL blocking, allow rules and CNAME redirects to decrypted traffic';

  @override
  String get httpInspProtocolSection => 'Protocol and compatibility';

  @override
  String get httpInspBlockHttp3 => 'Block HTTP/3 (QUIC)';

  @override
  String get httpInspBlockHttp3Subtitle =>
      'Blocking QUIC pushes traffic back to TCP so it can be decrypted; turn it off if something breaks';

  @override
  String get httpInspBlockDot => 'Block encrypted DNS (DoT)';

  @override
  String get httpInspBlockDotSubtitle =>
      'Blocks TCP port 853 so domain rules cannot be bypassed';

  @override
  String get httpInspRequestLogs => 'Request logs';

  @override
  String get httpInspRequestLogsSubtitle =>
      'See decrypted requests and automatic bypasses';

  @override
  String get httpInspBypassFooter =>
      'Stored in https_bypass_rules and merged with the built-in list in assets/https_passthrough.txt for the engine\'s setExtraPassthroughSuffixes.';

  @override
  String httpInspBypassTitle(int count) {
    return 'HTTPS bypass rules ($count)';
  }

  @override
  String get httpInspBypassEmpty => 'No custom bypass rules';

  @override
  String get httpInspBypassEmptySubtitle =>
      'The built-in pass list always applies; these are extra domain suffixes';

  @override
  String get httpInspBypassRowSubtitle => 'Passed through without decryption';

  @override
  String get httpInspCaRequiredTitle => 'Install the root certificate first';

  @override
  String get httpInspGoInstall => 'Go install';

  @override
  String get httpInspCaReadingBody =>
      'The root certificate status is still loading; try again in a moment.';

  @override
  String httpInspCaRequiredBody(String problem) {
    return 'HTTPS inspection hands decrypted plain text back to the app, so the system trust chain must accept DITING\'s root certificate. The current state is \"$problem\", so target apps cannot be picked yet.\n\nOpen the CA certificate page to generate and install it?';
  }

  @override
  String get httpInspCaMissing =>
      'No root certificate yet: generate one on the CA certificate page';

  @override
  String get httpInspCaNotInstalled =>
      'The certificate exists but is not in the system trust store';

  @override
  String get httpInspCaReadyShort => 'The certificate is ready';

  @override
  String get httpInspNeedDomainRulesTitle => 'Domain rules also need to be on';

  @override
  String get httpInspEnableAll => 'Turn both on';

  @override
  String get httpInspNeedDomainRulesBody =>
      'HTTPS inspection decrypts traffic and domain rules decide what happens to it. Domain rules are off right now, so inspection alone blocks nothing.\n\nTurn domain rules on as well?';

  @override
  String get httpInspAppsTitle => 'Choose apps to inspect';

  @override
  String get httpInspSelectVisible => 'Select all shown';

  @override
  String get httpInspDeselectVisible => 'Deselect all shown';

  @override
  String get httpInspAppsIntro =>
      'Once the Go tunnel takes over traffic, HTTPS inspection only inspects HTTP(S) requests from the selected apps; others are forwarded directly. Selecting an app clears its excluded, blocked and per-app rule state.';

  @override
  String httpInspAppsCount(int selected, int visible) {
    return '$selected apps selected ($visible shown)';
  }

  @override
  String get commonLater => 'Later';

  @override
  String get ruleControlSubsTitle => 'Rule subscriptions';

  @override
  String get cleanupIntro =>
      'These actions delete data on this device immediately and cannot be undone. Back up important rules or settings first.';

  @override
  String cleanupRunning(String title) {
    return 'Running: $title';
  }

  @override
  String get cleanupDescLogs =>
      'Clears DNS and HTTP request logs, race statistics and bootstrap resolution logs';

  @override
  String get cleanupDescTraffic =>
      'Clears the traffic history and live counters of every app';

  @override
  String get cleanupDescCrash =>
      'Clears all Java and native crash logs stored locally';

  @override
  String get cleanupDescDnsCache =>
      'Drops cached answers so the next visit queries again';

  @override
  String get cleanupDescProviderWeights =>
      'Clears the health samples of smart selection so traffic follows the default weights again';

  @override
  String get cleanupDescBootstrapWeights =>
      'Clears bootstrap DNS health samples so the default weights apply again';

  @override
  String get cleanupDescDomainRules =>
      'Clears domain block, allow and IPv4/IPv6 override rules plus their subscriptions, restoring the preset allowlist';

  @override
  String get cleanupDescAddressRules =>
      'Clears URL block, allow and CNAME override rules without touching domain rules';

  @override
  String get cleanupDescSubscriptions =>
      'Clears every remote and local rule subscription, subscription group and auto-update task';

  @override
  String get cleanupDescAppRules =>
      'Empties the per-app exclusions, blocked apps, app allowlists and capture lists';

  @override
  String get cleanupDescOutboundProxy =>
      'Clears the outbound proxy protocol, server and credentials, restoring direct connections';

  @override
  String get cleanupDescCaCertificate =>
      'Clears the locally generated MITM CA root certificate and private key';

  @override
  String get cleanupDescDownloadCache =>
      'Deletes update packages, downloaded temporary files and the app cache';

  @override
  String get cleanupDescCustomBackground =>
      'Clears the custom wallpaper cache and its stored path, restoring the default background';

  @override
  String get cleanupDescSettingsGuides =>
      'Shows every first-run guide again and asks for the terms once more';

  @override
  String get cleanupDescAllData =>
      'Deep-clears every log, cache, rule, subscription, certificate and setting, then exits the app';

  @override
  String get cleanupConfirmLogs =>
      'Delete all DNS and HTTP request logs, race statistics and bootstrap DNS statistics?';

  @override
  String get cleanupConfirmTraffic =>
      'Clear the traffic history and live counters of every app?';

  @override
  String get cleanupConfirmCrash =>
      'Delete all local crash logs and crash statistics?';

  @override
  String get cleanupConfirmDnsCache =>
      'Delete the whole local DNS cache? The next visit to a domain will query again.';

  @override
  String get cleanupConfirmProviderWeights =>
      'Clear every provider health sample and restore the default race weights?';

  @override
  String get cleanupConfirmBootstrapWeights =>
      'Clear the bootstrap DNS health samples and restore the default weights?';

  @override
  String get cleanupConfirmDomainRules =>
      'Delete every domain rule? Domain block, allow and IPv4/IPv6 override rules and their subscriptions are removed; address rules are untouched.';

  @override
  String get cleanupConfirmAddressRules =>
      'Delete every address rule? URL block, allow and CNAME override rules are removed; domain rules are untouched.';

  @override
  String get cleanupConfirmSubscriptions =>
      'Delete every rule subscription? All subscription links, groups and imported rules are removed; rules added by hand are untouched.';

  @override
  String get cleanupConfirmAppRules =>
      'Reset every app control list? Per-app proxy exclusions, blocked apps, app allowlists and HTTP/HTTPS capture apps are cleared and restored to defaults.';

  @override
  String get cleanupConfirmOutboundProxy =>
      'Reset the outbound proxy? The proxy is disabled and its server address, port and credentials are cleared.';

  @override
  String get cleanupConfirmCaCertificate =>
      'Clear the locally generated HTTPS capture CA certificate and private key? If the system already trusts it, you must generate and install a new one before capturing again.';

  @override
  String get cleanupConfirmDownloadCache =>
      'Delete downloaded update packages and temporary cache files?';

  @override
  String get cleanupConfirmCustomBackground =>
      'Clear the custom wallpaper cache and restore the default background?';

  @override
  String get cleanupConfirmSettingsGuides =>
      'Reset every first-run guide and the terms agreement? No setting, rule, cache, log or certificate is deleted. The app exits afterwards; the next launch asks for the terms again and shows all guides once more.';

  @override
  String get cleanupConfirmAllData =>
      'Run the full data cleanup? Logs, traffic statistics, crash records, DNS cache, provider weights, domain and address rules, rule subscriptions, temporary caches and capture certificates are cleared in turn. Every custom setting and rule is wiped, the guides are reset, and the app exits when it finishes.';

  @override
  String get cleanupRestartTitle => 'Restart required';

  @override
  String get cleanupRestartBody =>
      'Cleanup finished. The first-run guides and the terms were reset; restart the app for it to take effect.';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get transferTitle => 'Backup and migration';

  @override
  String get transferMetricProviders => 'DNS providers';

  @override
  String get transferMetricSubs => 'Rule subscriptions';

  @override
  String get transferMetricCustomRules => 'Custom rules';

  @override
  String get transferMetricListedApps => 'Listed apps';

  @override
  String get transferSectionAppConfig => 'App configuration';

  @override
  String get transferSectionRules => 'Rules and subscriptions';

  @override
  String get transferSectionAppControl => 'App control and traffic';

  @override
  String get transferSectionPersonal => 'Personalization and general';

  @override
  String get transferDeselectAll => 'Deselect all';

  @override
  String get transferImportExportSection => 'Import and export';

  @override
  String get transferExportJson => 'Export app configuration (JSON)';

  @override
  String get transferExportHintNone => 'Select the groups to export first';

  @override
  String transferExportHintCount(int count) {
    return 'Save the $count selected groups to a JSON file';
  }

  @override
  String get transferImportJson => 'Import app configuration (JSON)';

  @override
  String get transferImportSubtitle =>
      'Merges a backup file and skips items this device already has';

  @override
  String get transferImportExportFooter =>
      'The exported file contains your personal settings, so keep it safe. Importing merges the settings and skips items that already exist. Outbound proxy credentials are not part of a backup.';

  @override
  String get transferCloudSection => 'Cloud backup';

  @override
  String get transferWebdav => 'WebDAV sync';

  @override
  String get transferWebdavSubtitle =>
      'Sync the configuration file to your own WebDAV server';

  @override
  String get transferBusyExporting => 'Building the backup file…';

  @override
  String get transferBusySaving => 'Waiting for a save location…';

  @override
  String get transferBusyPickingImport => 'Waiting for a backup file…';

  @override
  String get transferExportEmpty =>
      'The selected groups have nothing to export';

  @override
  String get transferExportCancelled => 'Save cancelled';

  @override
  String transferExportDone(int groups, int items) {
    return 'Exported $groups groups, $items items in total';
  }

  @override
  String transferExportSkipped(int count) {
    return '; $count items skipped';
  }

  @override
  String get transferExportFailed => 'Export failed';

  @override
  String get transferImportCancelled => 'Import cancelled';

  @override
  String get transferImportTitle => 'Import app configuration';

  @override
  String get transferImportFailedChip => 'Import failed';

  @override
  String get transferImportDoneChip => 'Import finished';

  @override
  String transferImportSummary(int added, int updated, int skipped) {
    return 'Import summary: $added added, $updated updated, $skipped skipped';
  }

  @override
  String transferSourceFile(String name) {
    return 'Source file: $name';
  }

  @override
  String transferExportedAt(String time) {
    return 'Backup exported at $time';
  }

  @override
  String transferOutcomeRow(String group, String detail) {
    return '  + $group · $detail';
  }

  @override
  String transferFailedGroupRow(String group, String error) {
    return '  ! $group: $error';
  }

  @override
  String get transferNothingChanged =>
      '  (Every item in the backup already exists here; nothing to change)';

  @override
  String transferSubscriptionsNote(int count) {
    return 'Contains $count subscriptions; open subscription management to update their rules.';
  }

  @override
  String get transferDone => 'Done';

  @override
  String transferOutcomeAdded(int count) {
    return '$count added';
  }

  @override
  String transferOutcomeUpdated(int count) {
    return '$count updated';
  }

  @override
  String transferOutcomeSkipped(int count) {
    return '$count skipped';
  }

  @override
  String get transferNoChange => 'No changes';

  @override
  String get transferOutcomeSeparator => ', ';

  @override
  String get webdavClearConfig => 'Clear settings';

  @override
  String get webdavTest => 'Test connection';

  @override
  String get webdavServer => 'Server';

  @override
  String get webdavUsername => 'Username';

  @override
  String get webdavPassword => 'Password';

  @override
  String get webdavPath => 'Remote path';

  @override
  String get webdavUpload => 'Upload backup';

  @override
  String get webdavDownload => 'Download and restore';

  @override
  String webdavFooter(String hint) {
    return '\"Test connection\" sends a real WebDAV request: PROPFIND probes the folder and creates it when missing. Upload and download use the same backup format as \"Backup and migration\". ${hint}The password is kept in memory only and never written to disk.';
  }

  @override
  String get webdavFooterConnected =>
      'Once connected you can upload or restore. ';

  @override
  String get webdavNoConfig =>
      'There is no configuration to back up on this device';

  @override
  String get webdavUploadFailed => 'Upload failed';

  @override
  String get webdavNoCloudBackup =>
      'There is no backup in the cloud to restore';

  @override
  String get webdavRestoreTitle => 'Restore configuration from the cloud';

  @override
  String get webdavRestoreFailed => 'Restore failed';

  @override
  String get webdavRestoreDone => 'Restore finished';

  @override
  String webdavRestoreSummary(int added, int updated, int skipped) {
    return 'Restore summary: $added added, $updated updated, $skipped skipped';
  }

  @override
  String webdavOutcomeRow(String group, int added, int skipped) {
    return '  + $group · $added added, $skipped skipped';
  }

  @override
  String get webdavNothingChanged =>
      '  (The cloud backup matches this device; nothing to change)';

  @override
  String get webdavHintIdle =>
      'Fill in the server details to test the connection';

  @override
  String get webdavHintConnecting => 'Handshaking, please wait';

  @override
  String get webdavHintConnected =>
      'You can upload a backup or restore from the cloud';

  @override
  String get webdavHintFailed =>
      'Check the address, account and certificate, then retry';

  @override
  String get backupGroupProviders => 'Custom DNS providers';

  @override
  String get backupGroupProvidersDesc =>
      'DoH and DoT providers and resolution settings';

  @override
  String get backupGroupBootstrap => 'Custom bootstrap IPs';

  @override
  String get backupGroupBootstrapDesc =>
      'Bootstrap DNS nodes and their switches';

  @override
  String get backupGroupCache => 'DNS cache policy';

  @override
  String get backupGroupCacheDesc =>
      'DNS cache switches, presets and TTL limits';

  @override
  String get backupGroupOutbound => 'Outbound proxy settings';

  @override
  String get backupGroupOutboundDesc =>
      'SOCKS5 / HTTP proxy and proxied apps, without credentials';

  @override
  String get backupGroupSubscriptions => 'Online rule subscriptions';

  @override
  String get backupGroupSubscriptionsDesc =>
      'Subscription links, mirrors and auto-update';

  @override
  String get backupGroupDomainRules => 'Custom blocked domain rules';

  @override
  String get backupGroupDomainRulesDesc =>
      'Blocked domains added by hand and their switches';

  @override
  String get backupGroupRewriteDomain => 'Custom domain rewrite rules';

  @override
  String get backupGroupRewriteDomainDesc =>
      'IPv4 / IPv6 domain override rules';

  @override
  String get backupGroupRewriteCname => 'Custom CNAME rewrite rules';

  @override
  String get backupGroupRewriteCnameDesc => 'CNAME override rules';

  @override
  String get backupGroupAddressRules => 'Custom blocked address rules';

  @override
  String get backupGroupAddressRulesDesc => 'URL path blocking rules';

  @override
  String get backupGroupExcluded => 'Excluded apps';

  @override
  String get backupGroupExcludedDesc =>
      'Apps that bypass filtering and use the system DNS';

  @override
  String get backupGroupBlocked => 'Blocked apps';

  @override
  String get backupGroupBlockedDesc =>
      'Apps that cannot go online while the service runs';

  @override
  String get backupGroupAllowlist => 'Per-app rules and allow lists';

  @override
  String get backupGroupAllowlistDesc =>
      'Per-app pass rules and domain allowlists';

  @override
  String get backupGroupHttpInspection => 'HTTPS capture settings';

  @override
  String get backupGroupHttpInspectionDesc =>
      'Capture switches and target apps';

  @override
  String get backupGroupAppearance => 'Appearance and personalization';

  @override
  String get backupGroupAppearanceDesc =>
      'Theme, component opacity and taglines';

  @override
  String get backupGroupSystem => 'System and general settings';

  @override
  String get backupGroupSystemDesc =>
      'LAN bypass, log mode, language and notifications';

  @override
  String webdavUploadedCount(int groups, int items) {
    return 'Uploaded $groups groups, $items items in total';
  }

  @override
  String get agentApiEnabled => 'AI analysis is on';

  @override
  String get agentApiDisabled => 'AI analysis is off';

  @override
  String get agentApiNoProvider =>
      'No AI provider configured yet; add one and fill in the API key under \"AI provider management\" first.';

  @override
  String agentApiCurrentProvider(String name, String model) {
    return 'Current provider: $name · $model';
  }

  @override
  String get agentApiNoModel => 'No model selected';

  @override
  String get agentApiKeyConfigured => 'Key configured';

  @override
  String agentApiTemperature(String value) {
    return 'Temperature $value';
  }

  @override
  String get agentApiProviderChip => 'Requests go to your provider';

  @override
  String get agentApiReadyHintOn =>
      'Once the provider and key are filled in, the log pages can start an analysis directly.';

  @override
  String get agentApiReadyHintOff =>
      'Turn it on to start an analysis straight from the log pages.';

  @override
  String get agentApiSectionProvider => 'Provider and parameters';

  @override
  String agentApiProvidersSubtitle(int count) {
    return '$count providers configured · choose the endpoint and model';
  }

  @override
  String get agentParamsSubtitle => 'System prompt and sampling temperature';

  @override
  String get agentApiSectionTest => 'Feature test';

  @override
  String get agentApiTestDomain => 'Analyse a domain';

  @override
  String get agentApiTestDomainSubtitle =>
      'Calls the model with a sample domain to check risks and recommended actions';

  @override
  String get agentApiTestTraffic => 'Analyse recent traffic';

  @override
  String get agentApiTestTrafficSubtitle =>
      'Summarises recent DNS and HTTPS records and calls the model';

  @override
  String get agentApiTestFooterReady =>
      'Both entries really call your provider and consume quota.';

  @override
  String get agentApiTestFooterNotReady =>
      'The configuration is incomplete (off, or no API key); tapping asks you to finish it first.';

  @override
  String get agentApiSectionEntries => 'Where to analyse';

  @override
  String get agentApiCacheTable => 'DNS cache table';

  @override
  String get agentApiCacheTableSubtitle =>
      'Tap any row to analyse that domain\'s security risk';

  @override
  String get agentApiRequests => 'Request records';

  @override
  String get agentApiRequestsSubtitle =>
      'Open a request\'s details; the domain can be analysed at the bottom';

  @override
  String get agentApiDashboard => 'Log dashboard';

  @override
  String get agentApiDashboardSubtitle =>
      'The \"AI review\" card analyses recent traffic as a whole';

  @override
  String get agentApiEntriesFooter =>
      'A domain in the report can be written to the allow or block list in one tap; it takes effect once the DNS VPN starts.';

  @override
  String get agentApiSectionReset => 'Reset settings';

  @override
  String get agentApiResetItem => 'Restore factory defaults';

  @override
  String get agentApiResetSubtitle =>
      'Clears providers, API keys, prompts and temperature';

  @override
  String get agentApiFooter =>
      'AI analysis only helps you judge; it never changes rules by itself. Requests are handled by the provider you configured and the key stays on this device.';

  @override
  String get agentApiResetTitle => 'Restore the default settings?';

  @override
  String get agentApiResetBody =>
      'This restores every AI analysis parameter, API key and system prompt to its default.';

  @override
  String get agentApiResetConfirm => 'Restore';

  @override
  String get agentProvidersTitle => 'AI provider management';

  @override
  String get agentProvidersAdd => 'Add custom provider';

  @override
  String get agentProvidersIntro =>
      'Picking a preset below pre-fills the endpoint; choose the model from the provider\'s real list via \"Fetch models\" in the editor. Leaving the API key empty while editing keeps the existing key. Keys are stored on this device with the same obfuscation as before, with no extra plain text.';

  @override
  String get agentProvidersMine => 'My providers';

  @override
  String get agentProvidersEmpty => 'No providers yet';

  @override
  String get agentProvidersEmptySubtitle =>
      'Pick one from the presets below, or add a custom provider from the top right';

  @override
  String agentProvidersRow(String model, String baseUrl, String key) {
    return '$model · $baseUrl · $key';
  }

  @override
  String get agentProvidersKeyConfigured => 'Key configured';

  @override
  String get agentProvidersKeyMissing => 'Key missing';

  @override
  String get agentProvidersFooter =>
      'Tap a row to make that provider active; switching also syncs the endpoint, key and model into the four legacy flat keys so the new and old screens never disagree.';

  @override
  String get agentProvidersAdded => 'Added';

  @override
  String get agentProvidersDeleteTitle => 'Delete provider';

  @override
  String agentProvidersDeleteBody(String name) {
    return 'Delete \"$name\"? Its API key is removed from this device as well.';
  }

  @override
  String get agentEditorAddTitle => 'Add provider';

  @override
  String get agentEditorEditTitle => 'Edit provider';

  @override
  String get agentEditorPaste => 'Read from clipboard';

  @override
  String get agentEditorName => 'Provider name';

  @override
  String get agentEditorBaseUrl => 'Endpoint URL';

  @override
  String get agentEditorModel => 'Model name';

  @override
  String get agentEditorModelHint =>
      'Tap \"Fetch models\" to pick from the provider\'s list';

  @override
  String get agentEditorKeyKeep => 'Leave empty to keep the current key';

  @override
  String get agentEditorKeyLocal =>
      'Stored on this device only (same obfuscation as before)';

  @override
  String get agentEditorFetching => 'Requesting…';

  @override
  String get agentEditorFetch => 'Fetch models';

  @override
  String get agentEditorTest => 'Test connection';

  @override
  String get agentEditorErrorRequired =>
      'Fill in a name, an http(s) endpoint and a model name';

  @override
  String get agentEditorErrorBaseUrl => 'Fill in the endpoint URL first';

  @override
  String get agentEditorErrorTestNeeds =>
      'Testing needs an endpoint URL and a model name';

  @override
  String agentEditorFetched(int count) {
    return 'Fetched $count models; pick one from the chips below';
  }

  @override
  String agentEditorFetchFailed(String error) {
    return 'Fetching models failed: $error';
  }

  @override
  String agentEditorConnected(String model) {
    return 'Connected: $model';
  }

  @override
  String agentEditorUsage(int tokens) {
    return ', $tokens tokens used';
  }

  @override
  String agentEditorConnectFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get agentParamsTitle => 'Parameters and prompt';

  @override
  String get agentParamsPromptSection => 'System prompt';

  @override
  String get agentParamsPromptItem => 'System prompt';

  @override
  String get agentParamsPromptUnset =>
      'Not set (each analysis scenario uses its built-in prompt)';

  @override
  String get agentParamsPromptFooter =>
      'When empty, domain and traffic analysis each use their own built-in prompt; once filled in, both use this one.';

  @override
  String get agentParamsPromptHint =>
      'For example: you are a network security and DNS threat intelligence expert…';

  @override
  String get agentParamsTemperatureSection => 'Sampling temperature';

  @override
  String get agentParamsTemperatureItem => 'Randomness and creativity';

  @override
  String get agentParamsTemperatureFooter =>
      'For security judgements 0.2–0.4 is recommended: the lower the temperature, the steadier and more restrained the answer.';

  @override
  String get agentParamsTemperatureStrict =>
      'Precise (good for security analysis and structured output)';

  @override
  String get agentParamsTemperatureBalanced =>
      'Balanced (recommended for everyday analysis)';

  @override
  String get agentParamsTemperatureWild =>
      'Loose and varied (richer, freer answers)';

  @override
  String get agentParamsTemplateSecurity => 'Security threat analysis';

  @override
  String get agentParamsTemplateTechnical => 'Minimal technical review';

  @override
  String get agentParamsTemplatePrivacy => 'Privacy and telemetry review';

  @override
  String get agentSheetCopied => 'Report copied to the clipboard';

  @override
  String agentSheetRuleAdded(String kind) {
    return 'Added to $kind; it takes effect once the DNS VPN starts';
  }

  @override
  String agentSheetRuleExists(String kind) {
    return 'This domain is already in $kind';
  }

  @override
  String get agentSheetFooter =>
      'AI only helps you judge and never changes rules by itself; the report is for reference. Requests go to the provider you configured and the key stays on this device.';

  @override
  String get agentSheetDisabledTitle => 'AI analysis is turned off';

  @override
  String get agentSheetDisabledBody =>
      'The AI analysis service is disabled. You can turn it on right here or manage it on the settings page.';

  @override
  String get agentSheetEnableAndStart => 'Turn on AI analysis and continue';

  @override
  String get agentSheetNoKeyTitle => 'No API key configured';

  @override
  String get agentSheetNoKeyBody =>
      'Configure an OpenAI-compatible API key before using AI domain and traffic analysis.';

  @override
  String get agentSheetGoConfigure => 'Configure';

  @override
  String get agentSheetRunning => 'AI analysis in progress…';

  @override
  String agentSheetModel(String model) {
    return 'Model $model';
  }

  @override
  String get agentSheetUnknown => 'Unknown';

  @override
  String get agentSheetFailed => 'Analysis failed';

  @override
  String get agentSheetUnknownError => 'Unknown error';

  @override
  String get agentSheetCheckSettings => 'Check settings';

  @override
  String get agentSheetNotStarted => 'Not analysed yet';

  @override
  String get agentSheetSuperseded =>
      'The result was replaced by a newer analysis';

  @override
  String get agentSheetStartHint => 'Tap the button below to start.';

  @override
  String get agentSheetSupersededHint =>
      'Another analysis replaced this session; running it again brings the result back.';

  @override
  String get agentSheetStart => 'Start analysis';

  @override
  String get agentSheetHideDigest => 'Hide the prompt summary';

  @override
  String get agentSheetShowDigest => 'Show the prompt summary';

  @override
  String get agentSheetAddBlock => 'Add to block list';

  @override
  String get agentSheetCopyResult => 'Copy report';

  @override
  String get agentSheetReanalyze => 'Analyse again';

  @override
  String get agentTargetDomainTitle => 'Domain security analysis';

  @override
  String get agentTargetTrafficTitle => 'Network traffic analysis';

  @override
  String get agentTargetTrafficSubtitle =>
      'Based on recent DNS and HTTPS monitoring data';

  @override
  String get agentApiChipKeyMissing => 'API key missing';

  @override
  String get agentSheetAddAllowlist => 'Add to allowlist';

  @override
  String get featureHubLongPress => 'Long-press';

  @override
  String get outboundSaved =>
      'Outbound proxy settings saved; they take effect once the tunnel starts';

  @override
  String outboundSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get outboundResetTitle => 'Reset the outbound proxy?';

  @override
  String get outboundResetBody =>
      'Deletes all nine outbound proxy keys, including the encrypted username and password.';

  @override
  String get outboundResetDone => 'Outbound proxy reset';

  @override
  String get outboundResetMenu => 'Reset outbound proxy';

  @override
  String get outboundSectionProxy => 'Proxy';

  @override
  String get outboundEnable => 'Enable the outbound proxy';

  @override
  String get outboundApp => 'Proxy app';

  @override
  String get outboundHostLabel => 'Address';

  @override
  String get outboundHostHelper => 'Only 127.0.0.1 or ::1 is supported';

  @override
  String get outboundUsernameLabel => 'Username (optional)';

  @override
  String get outboundPasswordLabel => 'Password (optional)';

  @override
  String get outboundHttpFooter =>
      'HTTP CONNECT does not support UDP; UDP is blocked outright and QUIC can fall back to TCP. The proxy app itself bypasses DITING.';

  @override
  String get outboundSocksFooter =>
      'SOCKS5 forwards UDP through UDP ASSOCIATE. The proxy app itself bypasses DITING so traffic cannot loop.';

  @override
  String get outboundStatusOff => 'Not running';

  @override
  String get outboundStatusConnecting => 'Connecting';

  @override
  String get outboundStatusReady => 'Proxy available';

  @override
  String get outboundStatusFailed => 'Connection failed';

  @override
  String get outboundFooterError =>
      'An error reported by the engine stays until the next tunnel start so you can look back at the cause.';

  @override
  String get outboundFooterReady =>
      'The engine confirmed the proxy works; after changing the settings the tunnel must restart to check again.';

  @override
  String get outboundFooterConnecting =>
      'The tunnel checks proxy connectivity when it starts and shows the result here live.';

  @override
  String get outboundAppsTitle => 'Choose the proxy app';

  @override
  String get outboundAppsIntro =>
      'Pick the app that provides the local proxy port. The proxy app itself bypasses DITING; it owns the port and DITING cannot listen for it.';

  @override
  String outboundAppsCount(int count) {
    return 'Installed apps ($count)';
  }

  @override
  String get outboundAppsEmpty =>
      'There are no proxy apps to pick on this device';

  @override
  String get resolutionSingleDesc =>
      'Every query goes to the selected provider.';

  @override
  String get resolutionSmartDesc =>
      'Picks one by past success rate and moves on to the next if it fails.';

  @override
  String get resolutionParallelDesc =>
      'Asks every provider at once and keeps the first answer.';

  @override
  String get resolutionPrimaryBackupDesc =>
      'Prefers the primary provider and only uses the backups after a timeout.';

  @override
  String resolutionProtocolSavedError(String error) {
    return 'The protocol was saved but the running service could not be updated: $error';
  }

  @override
  String get resolutionBuiltinProtocol => 'Built-in service protocol';

  @override
  String get resolutionBuiltinNote =>
      'Only switches the DNS / DoT / DoH protocol used by built-in providers; custom providers keep their own protocol.';

  @override
  String get resolutionConfigSection => 'Mode configuration';

  @override
  String get resolutionConfigFooter =>
      'The resolution mode and race providers are stored in the dataset of the current work mode (normal, speed and server each keep their own).';

  @override
  String get resolutionNotConfigured => 'Not configured';

  @override
  String resolutionProviderCount(int count) {
    return '$count providers';
  }

  @override
  String get resolutionPickerTitle => 'Choose the resolution mode';

  @override
  String get resolutionMinProviders => 'Keep at least 2 providers';

  @override
  String get resolutionSingleHint => 'Pick one provider as the only way out.';

  @override
  String resolutionRaceHint(int count) {
    return '$count providers selected; at least 2 are required.';
  }

  @override
  String get resolutionReady => 'Ready';

  @override
  String get resolutionPending => 'Needs setup';

  @override
  String get resolutionSectionSingle => 'Query provider';

  @override
  String get resolutionSectionSmart => 'Candidate providers';

  @override
  String get resolutionSectionParallel => 'Providers queried in parallel';

  @override
  String get resolutionSectionBackup => 'Providers tried in order';

  @override
  String get resolutionNoProviders => 'No provider uses this protocol';

  @override
  String get resolutionMoveUp => 'Move up';

  @override
  String get resolutionMoveDown => 'Move down';

  @override
  String get outboundNoApp => 'Not selected';

  @override
  String get appRulesSaved => 'Saved; it takes effect once the DNS VPN starts';

  @override
  String get appRulesClearAllTooltip => 'Clear every allow rule';

  @override
  String get appRulesMasterSection => 'Master switch';

  @override
  String get appRulesMasterToggle => 'Enable per-app domain allow lists';

  @override
  String get appRulesNoConfigured => 'No per-app rules configured yet';

  @override
  String appRulesConfiguredSummary(int apps, int domains) {
    return '$apps apps configured · $domains domains allowed';
  }

  @override
  String get appRulesMasterFooter =>
      'Deep customisation of network and resolution control for specific apps: network-level allowlist isolation (only the listed domains pass), DNS-only block and allow lists, and \"block all outbound by default\". Open an app to configure each part; the settings are pushed when the DNS VPN starts.';

  @override
  String appRulesAppsCount(int count) {
    return 'Apps ($count)';
  }

  @override
  String get appRulesNoConfigurableApps =>
      'There are no configurable apps on this device';

  @override
  String get appRulesFooterNoApps =>
      'No installed apps could be read, so per-app rules cannot be configured.';

  @override
  String get appRulesFooterSave =>
      'Saving writes app_allowlist_enabled and app_allowlist_rules_json, which are pushed to the engine when the DNS VPN starts.';

  @override
  String get appRulesAddAllowDomain => 'Add an allowed domain';

  @override
  String get appRulesAppSection => 'App';

  @override
  String get appRulesBackToList => 'Back to the app list';

  @override
  String get appRulesClearAllTitle => 'Clear every allow rule?';

  @override
  String get appRulesClearAllBody =>
      'Deletes the allowed domains of every app. It takes effect on save; block lists and full-block settings are untouched.';

  @override
  String get appRulesRuleExists =>
      'The rule already exists or the rule database is unavailable';

  @override
  String appRulesRuleAdded(String kind) {
    return 'Added a $kind rule';
  }

  @override
  String get appRulesDeleteRuleTitle => 'Delete this rule?';

  @override
  String get appRulesFullBlockOn => 'Block-all-outbound mode is on';

  @override
  String get appRulesFullBlockOff => 'Block-all-outbound mode is off';

  @override
  String get appRulesAddDnsRule => 'Add a DNS rule';

  @override
  String get appRulesDnsScopeIntro =>
      'These rules are written to block_rule / allow_rule with an appScope, so they only apply to this app and are pushed with the appRules part of the rule snapshot instead of becoming global blocks.';

  @override
  String get appRulesDnsScopeSection => 'DNS-only block and allow lists';

  @override
  String get appRulesReadingRules => 'Reading the rule database';

  @override
  String get appRulesWait => 'One moment';

  @override
  String get appRulesRuleDbUnreadable => 'Cannot read the rule database';

  @override
  String get appRulesRuleDbUnavailable =>
      'This environment cannot read or write the rule database';

  @override
  String get appRulesNoScopedRules => 'No DNS-only rules configured';

  @override
  String get appRulesNoScopedRulesSubtitle =>
      'Added rules apply to this app only and never to others';

  @override
  String appRulesScopedCount(int count) {
    return 'DNS-only block and allow lists ($count)';
  }

  @override
  String appRulesAllowDomainTitle(int count) {
    return 'Allowed domains (network level) ($count)';
  }

  @override
  String get appRulesNoAllowDomains => 'No network allow domains configured';

  @override
  String get appRulesNoAllowDomainsSubtitle =>
      'While the network allowlist is empty this app is not restricted further';

  @override
  String get appRulesAllowDomainFooter =>
      'These domains are written to app_allowlist_rules_json and pushed to setAppAllowlist the next time the tunnel starts.';

  @override
  String get appRulesIsolationSection => 'Outbound and isolation';

  @override
  String get appRulesFullBlockToggle => 'Block all outbound by default';

  @override
  String get appRulesFullBlockToggleSubtitle =>
      'Blocks every network connection of this app except the allowlist';

  @override
  String get appRulesFullBlockOnTitle => 'Full block is on';

  @override
  String get appRulesFullBlockOnBody =>
      'Make sure the necessary allowlist entries exist, or the app may not be able to go online.';

  @override
  String get providerMgmtDeleteTitle => 'Delete DNS provider';

  @override
  String providerMgmtDeleteBody(String name) {
    return 'Delete \"$name\"? It can no longer be used for resolution afterwards.';
  }

  @override
  String get providerMgmtTitle => 'Provider management';

  @override
  String get providerMgmtAdd => 'Add DNS provider';

  @override
  String get providerMgmtCurrent => 'Currently resolving DNS';

  @override
  String get providerMgmtBuiltin => 'Built-in providers';

  @override
  String get providerMgmtCustom => 'Custom providers';

  @override
  String get providerMgmtEmptyCustom => 'No custom providers yet';

  @override
  String get providerMgmtEmptyCustomSubtitle =>
      'Tap \"+\" in the top right to add a DoH, DoT or plain DNS provider';

  @override
  String get providerMgmtFooter =>
      'Built-in providers are maintained by the app and can only be selected; custom ones can be edited or deleted.';

  @override
  String get providerMgmtEditTitle => 'Edit DNS provider';

  @override
  String get providerMgmtAddressLabel => 'Address (host:port)';

  @override
  String get providerMgmtNameRequired => 'Fill in a name';

  @override
  String get providerMgmtDohRequired =>
      'A DoH address must start with https://';

  @override
  String get providerMgmtHostPortRequired =>
      'Enter an address in host:port form';

  @override
  String get notifModeSingle => 'Single provider';

  @override
  String get notifModeSmart => 'Smart pick';

  @override
  String get notifModeParallel => 'Fastest answer';

  @override
  String get notifModeBackup => 'Try in order';

  @override
  String notifRunningMode(String mode, int count) {
    return 'Running · [$mode] $count providers';
  }

  @override
  String notifRunningProvider(String name) {
    return 'Running · $name';
  }

  @override
  String notifRunningServer(String name, int port) {
    return 'Running · $name · port $port';
  }

  @override
  String platformNoSaveDialog(String error) {
    return 'Could not open the save dialog: $error';
  }

  @override
  String platformNoFilePicker(String error) {
    return 'Could not open the file picker: $error';
  }

  @override
  String get platformNoFilePickerShort => 'Could not open the file picker';

  @override
  String get platformNoLocalRead => 'This environment cannot read local files';

  @override
  String platformReadFailed(String error) {
    return 'Could not read that file: $error';
  }

  @override
  String get platformNoSystemPicker =>
      'This environment has no system file picker';

  @override
  String updateConnectFailed(String error) {
    return 'Update check failed: cannot connect ($error)';
  }

  @override
  String get updateTlsFailed =>
      'Update check failed: TLS certificate verification failed';

  @override
  String get updateBadJson =>
      'Update check failed: the server did not return valid JSON';

  @override
  String get updateRateLimited =>
      'Update check failed: the GitHub API is rate limited (60 unauthenticated requests per hour). Try again later or open the releases page directly';

  @override
  String get updateForbidden =>
      'Update check failed: GitHub refused the request (HTTP 403)';

  @override
  String get updateNotFound =>
      'Update check failed: the repository or release page does not exist (HTTP 404)';

  @override
  String updateServerError(int status) {
    return 'Update check failed: GitHub is having problems (HTTP $status)';
  }

  @override
  String updateUnexpectedStatus(int status) {
    return 'Update check failed: GitHub returned $status';
  }

  @override
  String get updateResponseNotJson =>
      'Update check failed: the response is not valid JSON';

  @override
  String get updateUnexpectedFormat =>
      'Update check failed: the response has an unexpected shape';

  @override
  String get updateMissingTag =>
      'Update check failed: the latest release has no tag_name';

  @override
  String get updateNoApk => 'The latest release has no Android APK';

  @override
  String get updateBadDownloadUrl => 'The update download URL is invalid';

  @override
  String updateApkFileName(String version) {
    return 'DITING-$version.apk';
  }

  @override
  String get agentApiEmptyEndpoint =>
      'The endpoint URL is empty; fill it in under AI provider management first';

  @override
  String get agentApiNoModelListJson =>
      'The server did not return a model list (the response is not a JSON object)';

  @override
  String get agentApiNoModelListData =>
      'The server did not return a model list (the data field is missing)';

  @override
  String get agentApiNoModels =>
      'The endpoint returned no models; type the model name by hand';

  @override
  String get agentApiKeyEmpty => 'The API key cannot be empty';

  @override
  String get agentApiKeyEmptyHint =>
      'The API key cannot be empty; configure it in the AI analysis settings first';

  @override
  String get agentApiResponseNotJsonObject =>
      'The server response is not a JSON object';

  @override
  String get agentApiEmptyContent =>
      'The model returned nothing; check the model name or try again later';

  @override
  String agentApiBadUrl(String url) {
    return 'Invalid endpoint URL: $url';
  }

  @override
  String get agentApiCancelled => 'Analysis cancelled';

  @override
  String get agentApiTimeout =>
      'Request timed out: the model service did not answer in time';

  @override
  String agentApiUnreachable(String error) {
    return 'Could not reach the model service ($error)';
  }

  @override
  String get agentApiTls =>
      'TLS handshake failed: the server certificate is untrusted or the protocol does not match';

  @override
  String get agentApiInvalidJson => 'The server response is not valid JSON';

  @override
  String get agentApiBadKey => 'The API key is invalid or expired';

  @override
  String get agentApiNoAccess =>
      'The key cannot access this model, or the region is restricted';

  @override
  String get agentApiModelNotFound =>
      'The endpoint or model name does not exist (404)';

  @override
  String get agentApiRateLimited =>
      'Too many requests or the quota is exhausted (429)';

  @override
  String agentApiUnavailable(int status) {
    return 'The model service is unavailable right now ($status)';
  }

  @override
  String agentApiRequestFailed(int status) {
    return 'Request failed ($status)';
  }

  @override
  String agentApiServerDetail(String message) {
    return ': $message';
  }

  @override
  String get davProbeNoWrite =>
      'The server is reachable but the folder cannot be created; check that the account may write there';

  @override
  String davProbeConnect(String error) {
    return 'Could not connect to the server: $error';
  }

  @override
  String get davProbeTls =>
      'TLS handshake failed: the server certificate is not trusted (self-signed certificates must be installed in the system)';

  @override
  String get davProbeHttp =>
      'The HTTP request failed; check that the server supports WebDAV';

  @override
  String davUploadConnect(String error) {
    return 'Upload failed: could not reach the server ($error)';
  }

  @override
  String get davUploadTls =>
      'Upload failed: the TLS certificate is not trusted';

  @override
  String davDownloadHttp(int status) {
    return 'Download failed (HTTP $status)';
  }

  @override
  String get davStatus401 =>
      'Authentication failed: the username or password is wrong';

  @override
  String get davStatus403 =>
      'The server refused access: this account may not read or write that folder';

  @override
  String get davStatus404 => 'That folder does not exist on the server';

  @override
  String get davStatus405 =>
      'The server does not allow that operation (WebDAV may be off)';

  @override
  String get davStatus409 =>
      'The target folder does not exist, so nothing can be written';

  @override
  String get davStatus507 => 'The server is out of storage space';

  @override
  String davStatus5xx(int status) {
    return 'Server error (HTTP $status)';
  }

  @override
  String davStatusOther(int status) {
    return 'The server returned HTTP $status';
  }

  @override
  String get ipQualityNoExitIp =>
      'Could not get the current exit IP: the network is unreachable or the probe timed out';

  @override
  String get ipQualityNoSourceResult =>
      'No IP intelligence source returned a result; check the network and try again';

  @override
  String get disclaimerTerm1Title => '1. Nature of the software';

  @override
  String get disclaimerTerm1Content =>
      'DITING is an open-source local domain resolution and traffic observation tool; it does not provide network access of any kind. The software ships with no servers, nodes or subscription content, and does not stand in for any network service provider.';

  @override
  String get disclaimerTerm2Title => '2. How it may be used';

  @override
  String get disclaimerTerm2Content =>
      'Use the software only on devices and networks you own. Using it for network access, to bypass billing, or on networks you are not authorised to use falls outside its intended purpose.';

  @override
  String get disclaimerTerm3Title => '3. Scope of responsibility';

  @override
  String get disclaimerTerm3Content =>
      'The authors and contributors accept no liability for any direct or indirect loss arising from the use of, or inability to use, this software, including but not limited to data loss, service interruption and device damage.';

  @override
  String get disclaimerTerm4Title => '4. Third-party components';

  @override
  String get disclaimerTerm4Content =>
      'The UI component layer is ported from DITING (GPL-3.0-or-later) and uses open-source components such as material_ui and material_color_utilities. The licence of each component is listed in NOTICE.md in the repository; using this software means accepting those terms as well.';

  @override
  String get disclaimerTerm5Title => '5. No warranty';

  @override
  String get disclaimerTerm5Content =>
      'The software is provided \"as is\", without any express or implied warranty, including but not limited to the warranties of merchantability, fitness for a particular purpose and non-infringement.';

  @override
  String get disclaimerTerm6Title => '6. Limitation of liability';

  @override
  String get disclaimerTerm6Content =>
      'To the fullest extent permitted by law, the authors are not liable for any indirect, incidental, special or consequential damage, even if advised of the possibility of such damage.';

  @override
  String get disclaimerTerm7Title => '7. Privacy';

  @override
  String get disclaimerTerm7Content =>
      'By default the software collects and uploads no user data. Logs and rules stay on the device; if you configure a WebDAV backup yourself, the data is uploaded to the server you specify.';

  @override
  String get disclaimerTerm8Title => '8. Licence';

  @override
  String get disclaimerTerm8Content =>
      'The software is released under GPL-3.0-or-later. You may use, modify and redistribute it freely, but derivative works must keep the same licence and the original copyright notices.';

  @override
  String get disclaimerTerm9Title => '9. Changes to these terms';

  @override
  String get disclaimerTerm9Content =>
      'The authors may revise this disclaimer at any time. Revised terms ship with new versions, and continued use means you accept them.';

  @override
  String get disclaimerTerm10Title => '10. Accepting the terms';

  @override
  String get disclaimerTerm10Content =>
      'Before continuing, confirm that you have read, understood and agreed to all of the terms above. If you do not agree, stop using the software and uninstall it.';

  @override
  String get settingsModeSubtitle => 'Switch between normal and server mode';

  @override
  String get settingsPerformanceSection => 'Performance';

  @override
  String get settingsCacheSubtitle =>
      'Cache resolved domains to avoid repeated lookups';

  @override
  String get settingsLogModeSubtitle =>
      'Choose how much of the DNS request log is recorded';

  @override
  String get settingsRuntimeSection => 'Runtime behaviour';

  @override
  String get settingsForegroundSubtitle =>
      'Hide in the background, keep the notification, bypass the LAN';

  @override
  String get settingsAutoStartTitle => 'Start on launch';

  @override
  String get settingsAutoStartSubtitle =>
      'Restore normal or express mode when the app opens, unless you stopped it';

  @override
  String get settingsVpnWatchdogTitle => 'VPN watchdog';

  @override
  String get settingsVpnWatchdogSubtitle =>
      'Watch the VPN slot while another app holds it and reconnect once it is free';

  @override
  String get settingsDataSection => 'Data';

  @override
  String get settingsLanguageSubtitle => 'Choose the app language';

  @override
  String get settingsWizardSubtitle =>
      'See how the current work mode works, its permissions and a getting-started guide';

  @override
  String get backupErrEmpty => 'The file is empty';

  @override
  String backupErrInvalidJson(String error) {
    return 'Not valid JSON: $error';
  }

  @override
  String get backupErrRootNotObject =>
      'The root of a backup file must be a JSON object';

  @override
  String get backupErrNotDiting =>
      'This is not a DITING backup: it has neither a format marker nor a formatVersion number';

  @override
  String get backupErrNoVersion => 'The backup file has no version number';

  @override
  String backupErrVersionTooHigh(String version, int max) {
    return 'The backup version $version is higher than the supported $max; update the app before importing';
  }

  @override
  String get backupErrNoData => 'The backup file has no data section';

  @override
  String get backupErrProvidersNotArray =>
      'The providers section must be an array';

  @override
  String get backupErrBootstrapNotObject =>
      'The Bootstrap section must be an object';

  @override
  String get backupErrCacheNotObject => 'The cache section must be an object';

  @override
  String get backupErrOutboundNotObject =>
      'The outbound proxy section must be an object';

  @override
  String get backupErrBlockedNotObject =>
      'The blocked apps section must be an object';

  @override
  String get backupErrAppRulesNotObject =>
      'The per-app rules section must be an object';

  @override
  String get backupErrInspectionNotObject =>
      'The HTTPS capture section must be an object';

  @override
  String get backupErrSubsNotObject =>
      'The subscriptions section must be an object';

  @override
  String get backupErrNoRuleDbSubs =>
      'This device has no rule database yet, so subscriptions cannot be imported';

  @override
  String get backupErrRulesNotArray => 'The rules section must be an array';

  @override
  String get backupErrNoRuleDbRules =>
      'This device has no rule database yet, so rules cannot be imported';

  @override
  String get backupErrRewriteNotArray =>
      'The override rules section must be an array';

  @override
  String get backupErrNoRuleDbRewrite =>
      'This device has no rule database yet, so override rules cannot be imported';

  @override
  String get backupErrAddressNotArray =>
      'The address rules section must be an array';

  @override
  String get backupErrNoRuleDbAddress =>
      'This device has no rule database yet, so address rules cannot be imported';

  @override
  String get agentPasteEmpty => 'The clipboard is empty';

  @override
  String get agentPasteBoth =>
      'Recognised and filled in the endpoint and API key';

  @override
  String get agentPasteBaseUrl => 'Endpoint filled in';

  @override
  String get agentPasteKey => 'API key filled in';

  @override
  String get agentPasteJson =>
      'Recognised the API settings from the JSON and updated them';

  @override
  String logDirect(String protocol) {
    return '$protocol direct';
  }

  @override
  String logDirectWithApp(String protocol, String app) {
    return '$protocol direct · $app';
  }

  @override
  String get subsErrUrlUnavailable => 'The subscription URL is not usable';

  @override
  String subsErrTimeout(int seconds) {
    return 'Download timed out (read $seconds s)';
  }

  @override
  String get subsErrTls =>
      'TLS handshake failed; check the certificate or the mirror address';

  @override
  String get subsErrEmptyResponse => 'The subscription response was empty';

  @override
  String get subsErrUnreachable => 'Network unreachable';

  @override
  String subsErrUnreachableCode(String code) {
    return 'Network unreachable: $code';
  }

  @override
  String get subsErrUnsupported =>
      'This environment cannot update online subscriptions';

  @override
  String subsErrMirrorPlaceholder(String list) {
    return 'A mirror template must contain $list';
  }

  @override
  String get subsErrRawUrlInvalid =>
      'The original subscription URL is not valid';

  @override
  String get subsErrMirrorScheme =>
      'The address built from the mirror template must use HTTP or HTTPS';

  @override
  String get subsErrEmpty => 'The subscription URL cannot be empty';

  @override
  String get subsErrBadFormat => 'The subscription URL is not valid';

  @override
  String get subsErrNotHttp => 'A subscription link must use HTTP or HTTPS';

  @override
  String get subsErrNoHost => 'The subscription URL has no host name';

  @override
  String get siteCategoryShopping => 'Shopping';

  @override
  String get siteCategoryVideo => 'Video';

  @override
  String get siteCategoryMusic => 'Music';

  @override
  String get siteCategorySocial => 'Social';

  @override
  String get siteCategoryDeveloper => 'Developer';

  @override
  String get siteCategoryGame => 'Games';

  @override
  String get outboundProxyHostInvalid =>
      'The proxy address must be 127.0.0.1 or ::1';

  @override
  String get outboundProxyPortRange =>
      'The proxy port must be between 1 and 65535';

  @override
  String get outboundProxyAppRequired =>
      'Pick the app that provides the local proxy port';

  @override
  String get outboundProxySelfNotAllowed =>
      'DITING cannot be its own proxy app';

  @override
  String get outboundProxyAppMissing =>
      'The selected proxy app is not installed';

  @override
  String get outboundProxyCredentialsTooLong =>
      'The proxy username or password is too long';

  @override
  String get updateDownloadNoPath =>
      'Download failed: no package path was returned';

  @override
  String get updateDownloadUnsupported =>
      'This device cannot download inside the app; open the download URL in a browser';

  @override
  String updateDownloadFailedCode(String code) {
    return 'Download failed ($code)';
  }

  @override
  String dnsLatencySuccessRate(int success, int attempts) {
    return 'Success $success/$attempts';
  }

  @override
  String get dnsLatencyUnsupported =>
      'This device does not support latency tests';

  @override
  String dnsLatencyChannelFailedCode(String code) {
    return 'The latency channel failed ($code)';
  }

  @override
  String dnsLatencyChannelFailedDetail(String detail) {
    return 'The latency channel failed: $detail';
  }

  @override
  String get fontImportFailed => 'Could not import that font';

  @override
  String get fontReadFailed => 'Could not read that font file';

  @override
  String get fontParseFailed =>
      'Could not parse that font file; make sure it is a complete TTF/OTF';

  @override
  String get fontCustomName => 'Custom font';

  @override
  String get recognitionAvatarTooLarge => 'The avatar file is too large';

  @override
  String get recognitionConfigTooLarge => 'The list configuration is too large';

  @override
  String get taglineRunning => 'Listen to all things, tell clear from murky';

  @override
  String get taglineStopped => 'Ears at rest, back to silence';

  @override
  String get backupErrProvidersInvalidJson =>
      'The provider configuration is not valid JSON';

  @override
  String get backupErrBootstrapInvalidJson =>
      'The Bootstrap configuration is not valid JSON';

  @override
  String get backupErrAppearanceNotObject =>
      'The appearance section must be an object';

  @override
  String get backupErrSystemNotObject =>
      'The system settings section must be an object';

  @override
  String get outboundScopeTitle => 'Proxy scope';

  @override
  String get outboundScopeAll => 'All apps';

  @override
  String get outboundScopeApps => 'Selected apps';

  @override
  String get outboundScopeAllFooter =>
      'Connections from every app and DITING\'s own upstream DNS queries go through the proxy.';

  @override
  String get outboundScopeAppsFooter =>
      'Only connections from the selected apps go through the proxy. Other apps, connections whose owner cannot be identified and DITING\'s own upstream DNS queries connect directly.';

  @override
  String get outboundTargets => 'Apps using the proxy';

  @override
  String get outboundTargetsTitle => 'Choose apps that use the proxy';

  @override
  String get outboundTargetsIntro =>
      'Checked apps connect through the proxy; restart the tunnel after a change. The proxy app, DITING and apps in Excluded apps bypass the tunnel and cannot use the proxy, so they are not listed.';

  @override
  String get outboundProxyTargetsRequired =>
      'Pick at least one app to use the proxy in Selected apps mode';

  @override
  String get logDashboardCardHero => 'Dashboard title';

  @override
  String get logDashboardCardTrafficStructure => 'Traffic structure';

  @override
  String logDashboardEditHint(String mode) {
    return 'Editing the layout for $mode; each log mode keeps its own. Drag the handle to reorder, tap the top-right badge to remove.';
  }

  @override
  String get logDashboardModeFooter =>
      'Only cards that have data in the current log mode are listed.';

  @override
  String get logDashboardCardHeroDescription =>
      'Title and one-line summary at the top, following the log mode';

  @override
  String get logDashboardCardTrafficMonitorDescription =>
      'Live up and down rates and today\'s traffic';

  @override
  String get logDashboardCardRequestOverviewDescription =>
      'Today\'s requests, passed, blocked and cache hits';

  @override
  String get logDashboardCardHighlightDescription =>
      'Today\'s blocks, errors and bypasses';

  @override
  String get logDashboardCardPrivacyDescription =>
      'Explains that logging is off and nothing is recorded';

  @override
  String get logDashboardCardOffMetricDescription =>
      'Cache entries, cache hits, race and bootstrap counts';

  @override
  String get logDashboardCardPerfDescription =>
      'Average latency, cache hit rate, race and bootstrap success';

  @override
  String get logDashboardCardAiDescription =>
      'AI review of today\'s traffic, reusing the last report';

  @override
  String get logDashboardCardTrafficStructureDescription =>
      'Ring chart of today\'s request results';

  @override
  String get logDashboardCardRecentRequestsDescription =>
      'The latest request records';

  @override
  String get logDashboardCardRecentBlockedDescription =>
      'The latest blocks and errors';

  @override
  String get logDashboardCardCacheDescription => 'Most-hit cached domains';

  @override
  String get logDashboardCardRaceDescription =>
      'Upstreams that win races most often';

  @override
  String get logDashboardCardBootstrapDescription =>
      'Bootstrap DNS lookups and success rate';

  @override
  String get logDashboardCardRuleBlocksDescription =>
      'Rule sources that block the most';

  @override
  String get logStatsTitle => 'Statistics';

  @override
  String get logStatsRequests => 'Requests';

  @override
  String get logStatsTotal => 'Total';

  @override
  String get logStatsData => 'Data usage';

  @override
  String get logStatsSaved => 'Saved by cache';

  @override
  String get logStatsUploaded => 'Uploaded';

  @override
  String get logStatsDownloaded => 'Downloaded';

  @override
  String get logStatsWindow => 'Time range';

  @override
  String get logStatsRecentActivity => 'Recent activity';

  @override
  String get logDashboardCardStatsDescription =>
      'Blocks, cache hits and traffic for today, this week, this month or all history';

  @override
  String get floatingLogOpen => 'Open floating logs';

  @override
  String get floatingLogTitle => 'Live requests';

  @override
  String get floatingLogPaused => 'Paused';

  @override
  String get floatingLogSearch => 'Search';

  @override
  String get floatingLogSearchHint => 'Domain, app or rule';

  @override
  String get floatingLogPause => 'Pause updates';

  @override
  String get floatingLogResume => 'Resume updates';

  @override
  String get floatingLogMinimize => 'Collapse to bubble';

  @override
  String get floatingLogPanelSize => 'Panel size';

  @override
  String get floatingLogSizeSmall => 'Small';

  @override
  String get floatingLogSizeMedium => 'Medium';

  @override
  String get floatingLogSizeLarge => 'Large';

  @override
  String get floatingLogClear => 'Clear list';

  @override
  String get floatingLogOpenApp => 'Open DITING';

  @override
  String get floatingLogHide => 'Hide for now';

  @override
  String get floatingLogHideHint => 'Shows again after you return to the app';

  @override
  String get floatingLogCopied => 'Copied';

  @override
  String get floatingLogCopyDomain => 'Copy domain';

  @override
  String get floatingLogCopyRecord => 'Copy record';

  @override
  String get floatingLogEmpty => 'No requests yet';

  @override
  String get floatingLogEmptyBody => 'New requests appear here as they happen.';

  @override
  String get floatingLogClearedBody =>
      'List cleared; new requests will keep appearing.';

  @override
  String get floatingLogNoMatchBody => 'Try another keyword or filter.';

  @override
  String get floatingLogUnavailable => 'Logs unavailable';

  @override
  String get floatingLogUnavailableBody =>
      'The log database does not exist yet. Start the tunnel from the app once.';

  @override
  String floatingLogShown(int count) {
    return '$count shown';
  }

  @override
  String floatingLogNewRows(int count) {
    return '$count new';
  }

  @override
  String get floatingLogPermissionTitle => 'Overlay permission';

  @override
  String get floatingLogPermissionGranted => 'Granted';

  @override
  String get floatingLogPermissionMissing =>
      'Not granted. Tap to open system settings';

  @override
  String get floatingLogOpacity => 'Panel opacity';

  @override
  String get floatingLogSizeTitle => 'Panel size';

  @override
  String get logRetentionOverlayHowTo =>
      'Drag the bubble or the panel\'s title bar to move it. Tap a row for details; long-press to copy the domain.';

  @override
  String get permOverlay => 'Overlay';
}
