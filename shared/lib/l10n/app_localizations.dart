// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
  ];

  String get ruleTestTitle;

  String get ruleTestEnterSubtitle;

  String get ruleTestIntro;

  String get ruleTestDomainLabel;

  String get ruleTestDomainHint;

  String get ruleTestQtype;

  String get ruleTestRun;

  String get ruleTestResultTitle;

  String get ruleTestActionBlock;

  String get ruleTestActionAllow;

  String get ruleTestActionPass;

  String get ruleTestMatchedRule;

  String get ruleTestReason;

  String get ruleTestRewriteTitle;

  String get ruleTestNoRewrite;

  String get ruleTestInvalidDomain;

  String get ruleTestFailed;

  String get ruleTestEmptyHint;

  String get subscriptionHealthOk;

  String get subscriptionHealthUnchanged;

  String get subscriptionHealthCached;

  String get subscriptionHealthFailed;

  String get blockPauseTitle;

  String get blockPauseEntrySubtitle;

  String get blockPauseIntro;

  String get blockPauseRunningLabel;

  String get blockPauseInactive;

  String get blockPauseStatusActiveHint;

  String get blockPauseStatusPausedHint;

  String get blockPauseResume;

  String get blockPauseControlSectionTitle;

  String get blockPauseDurationTitle;

  String get blockPauseDurationSubtitle;

  String blockPausePresetOption(int minutes);

  String get blockPauseCustomOption;

  String get blockPauseCustomTitle;

  String blockPauseMinutesValue(int minutes);

  String get blockPauseMinutesLabel;

  String get blockPauseMinutesHelper;

  String get blockPauseMinutesInvalid;

  String get blockPauseAllowlistTitle;

  String get blockPauseAllowlistSubtitle;

  String get blockPauseFailed;

  String get hitRankingTitle;

  String get hitRankingEntrySubtitle;

  String get hitRankingDomains;

  String get hitRankingDomainsFooter;

  String get hitRankingExplainHint;

  String get hitRankingReasons;

  String get hitRankingEmpty;

  String get hitRankingEmptyBody;

  String get hitRankingLoadFailed;

  String get hitRankingFooter;

  String hitRankingTotal(int count);

  String get healthTitle;

  String get healthEntrySubtitle;

  String get healthIntro;

  String get healthIntroShort;

  String get healthScoreLabel;

  String get healthLevelOk;

  String get healthLevelWarning;

  String get healthLevelCritical;

  String get healthDimensionsTitle;

  String get healthDimPermissions;

  String get healthDimDns;

  String get healthDimFilter;

  String get healthDimCache;

  String get healthAdviceTitle;

  String get healthAdviceGrantPermissions;

  String get healthAdviceStartProtection;

  String get healthAdviceImportRules;

  String get healthAdviceUpdateSubscriptions;

  String get healthAdviceLowCache;

  String get healthAdviceNoBlocking;

  String get healthAdviceAllGood;

  String get healthLoading;

  String get healthLoadFailed;

  String get searchTitle;

  String get searchHint;

  String get searchEmptyTitle;

  String get searchEmptyBody;

  String get searchNoResults;

  String get searchGroupTools;

  String get flowTitle;

  String get flowLiveTab;

  String get flowEntrySubtitle;

  String get flowAppsSection;

  String get flowRefresh;

  String get flowEmptyBody;

  String get flowStatusActive;

  String get flowStatusFailed;

  String get flowStatusClosed;

  String get appTitle;

  String get uiBack;

  String get uiCancel;

  String get uiClearSearch;

  String get uiClose;

  String get uiHidePassword;

  String get uiMore;

  String get uiNoSearchResults;

  String get uiReset;

  String get uiSearch;

  String get uiShowLess;

  String get uiShowMore;

  String get uiShowPassword;

  String get uiSort;

  String get uiSubmit;

  String get languageTitle;

  String get languageInterfaceSection;

  String get languageInterfaceFooter;

  String get languageChinese;

  String get languageEnglish;

  String get commonFollowSystem;

  String get commonSelectAll;

  String get commonClear;

  String get commonInvertSelection;

  String get commonFilter;

  String get commonSort;

  String get commonSave;

  String get commonDiscard;

  String get commonSaveChangesTitle;

  String get commonSaveChangesMessage;

  String commonSaveChangesMessageFor(String name);

  String get commonGrantPermission;

  String get palettePurple;

  String get paletteBlue;

  String get paletteCyan;

  String get paletteGreen;

  String get paletteOrange;

  String get paletteRed;

  String get palettePink;

  String get paletteGold;

  String get themeModeLight;

  String get themeModeDark;

  String get appListUnavailable;

  String get appListFilterAll;

  String get appListFilterSystem;

  String get appListFilterUser;

  String get appListFilterSelected;

  String get appListSortLabelAsc;

  String get appListSortLabelDesc;

  String get appListSortPackageAsc;

  String get appListSortPackageDesc;

  String get appListNotRegistered;

  String appListChannelUnavailable(String detail);

  String appListReadFailed(String detail);

  String appListReadFailedCode(String code);

  String dbWriteUnhealthy(int dropped, int failures);

  String get agreementDeclinedTitle;

  String get agreementDeclinedMessage;

  String get agreementReviewAgain;

  String get agreementTitle;

  String get agreementDecline;

  String get agreementAccept;

  String get agreementMessage;

  String get homeProviderSingleLabel;

  String get homeProviderRaceLabel;

  String get homeChartEmptyLabel;

  String durationHours(int hours);

  String durationMinutes(int minutes);

  String durationSeconds(int seconds);

  String get dashboardDetailTooltip;

  String get dashboardEmptyLabel;

  String get dashboardEmptyDescription;

  String get dashboardEnterEditMode;

  String get dashboardEditHint;

  String get dashboardAllRemovedLabel;

  String get dashboardAllRemovedDescription;

  String get dashboardAddCard;

  String get providerSheetSingleTitle;

  String get providerSheetRaceTitle;

  String get providerSheetSingleOptions;

  String get providerSheetRaceMinimum;

  String get providerSheetManage;

  String get providerSheetVisibility;

  String get providerSheetActions;

  String get providerSheetSingleFooter;

  String get providerSheetRaceFooter;

  String get providerSheetSearchHint;

  String get providerSheetDone;

  String get powerButtonStop;

  String get powerButtonStart;

  String get powerButtonStarting;

  String get homeEditDashboard;

  String get homeDone;

  String get homeSwitchWorkMode;

  String get homeTitleNormal;

  String get homeTitleExpress;

  String get homeTitleServer;

  String get logRequestsOverview;

  String get logTodayRequests;

  String get logPassed;

  String get logFiltered;

  String get logCacheHits;

  String get logHighlights;

  String get logBlocked;

  String get logFailed;

  String get logBypassed;

  String get logOffModeTitle;

  String get logCacheEntries;

  String get logCacheHitsTotal;

  String get logRaceRequests;

  String get logBootstrapAttempts;

  String get logRecentRequests;

  String get logRecentRequestsEmpty;

  String get logRecentBlocked;

  String get logRecentBlockedEmpty;

  String get logCacheHotspots;

  String get logCacheHotspotsEmpty;

  String logExpiresIn(String duration);

  String logTimes(String count);

  String get logRaceWinners;

  String get logRaceWinnersEmpty;

  String logAverageWinLatency(String latency);

  String get logBootstrapDnsEmpty;

  String logBootstrapRow(String ip, String latency, String percent);

  String get logRuleBlocks;

  String get logRuleBlocksEmpty;

  String logShareRow(String percent, String status);

  String get logPrivacyMode;

  String get logLoggingOff;

  String get logPrivacyModeBody;

  String get logPerfTitle;

  String get logTodayStats;

  String get logAverageLatency;

  String get logNoTimingSamples;

  String logSampleValue(String count, String value);

  String get logCacheHitRate;

  String logCacheHitRateValue(String percent);

  String get logRaceSuccessRate;

  String get logBootstrapSuccessRate;

  String logRateValue(String count, String latency, String percent);

  String get dashboardRestoreDefaults;

  String get dashboardAllCardsAdded;

  String get dashboardAllCardsAddedDescription;

  String get dashboardAvailableCards;

  String get dashboardOrderHint;

  String get dashboardCardProviderDescription;

  String get dashboardCardResolutionDescription;

  String get dashboardCardStatusDescription;

  String get dashboardCardSpeedDescription;

  String get dashboardCardSiteLatencyDescription;

  String get dashboardCardMemoryDescription;

  String get dashboardCardIntranetDescription;

  String get intranetIpTitle;

  String get intranetCopyAddress;

  String get intranetReading;

  String get intranetNoActiveNetwork;

  String get intranetLanAccess;

  String get intranetConnectHint;

  String get memoryTitle;

  String get memoryJavaHeap;

  String get memoryNativeHeap;

  String get memorySystemAvailable;

  String get speedTitle;

  String get speedUpload;

  String get speedDownload;

  String get speedNoChannel;

  String get resolutionModeTitle;

  String get resolutionNoProvider;

  String get resolutionSingleSummary;

  String get resolutionSmartSummary;

  String get resolutionParallelSummary;

  String get resolutionPrimaryBackupSummary;

  String get siteLatencyTesting;

  String get siteLatencyNotTested;

  String get siteLatencyTitle;

  String get siteLatencyRetest;

  String get commonFailed;

  String get siteLatencyNoReply;

  String get statusTitle;

  String get statusUptime;

  String get statusActiveProvider;

  String get statusNotSelected;

  String get statusTodayQueries;

  String get statusDetailTitle;

  String get statusNotTiming;

  String get statusCoreSection;

  String get statusWorkMode;

  String get statusCoreState;

  String get statusListenPort;

  String get statusNotListening;

  String get statusProviderFooter;

  String get statusNoProviderHint;

  String get statusTodayCounts;

  String get statusCountsFooter;

  String get statusQueries;

  String get statusBlocked;

  String get statusAverageLatency;

  String get statusCacheHitRate;

  String get statusTunnelActive;

  String get statusCoreStopped;

  String get siteLatencySheetLatency;

  String get siteLatencySheetCategory;

  String get siteLatencySheetTarget;

  String get siteLatencySheetAverage;

  String get siteLatencySheetMinMax;

  String get siteLatencySheetJitter;

  String get siteLatencySheetLoss;

  String get siteLatencySheetDns;

  String get siteLatencySheetLastRun;

  String get siteLatencySheetNotTested;

  String get siteLatencySheetNoReply;

  String get siteLatencySheetFallbackFooter;

  String get siteLatencySheetIcmpFooter;

  String get trafficStructureLive;

  String get trafficStructureFocused;

  String get trafficStructureToday;

  String get trafficStructureBypass;

  String get trafficStructureCache;

  String get trafficStructureRaceRate;

  String get trafficStructureBootstrapRate;

  String get trafficStructureBlockedShare;

  String get trafficStructureBlockRate;

  String get trafficStructureCacheRate;

  String get dashboardSitesTitle;

  String get dashboardSitesCardSection;

  String get dashboardSitesAtLeastOne;

  String get dashboardSitesFooter;

  String get trafficMonitorTitle;

  String get trafficMonitorToday;

  String get trafficMonitorLiveRate;

  String get trafficMonitorNoStats;

  String get memoryDetailTitle;

  String get memoryResample;

  String get memoryProcessPss;

  String get memoryUnavailable;

  String get memoryOther;

  String get memoryComposition;

  String get memoryCompositionFooter;

  String get memoryOtherCode;

  String get memorySystemSection;

  String get memorySystemFooter;

  String get memorySystemUsed;

  String get memoryRecentPss;

  String get memorySampling;

  String get memoryRecentPssCaption;

  String get memorySourceFooter;

  String get siteLatencyDetailTitle;

  String get siteLatencyTestAll;

  String get siteLatencyCustomSites;

  String get siteLatencyConnectivity;

  String get siteLatencyTestingShort;

  String get siteLatencyNoTest;

  String get siteLatencyInProgress;

  String get siteLatencyPending;

  String get siteLatencyAllReachable;

  String get siteLatencyTestingEach;

  String get siteLatencyPickCategory;

  String get siteLatencyThisRun;

  String get siteLatencyReachable;

  String get siteLatencyMeasuredSites;

  String get siteLatencyDetailFooter;

  String get intranetDetailTitle;

  String get intranetRefresh;

  String get intranetLocalAddress;

  String get intranetUsableAsDns;

  String get intranetLocalOnly;

  String get intranetSameSubnetHint;

  String get intranetNetworkOverview;

  String get commonEnabled;

  String get commonDisabled;

  String get intranetDnsServers;

  String get intranetInterfaces;

  String get intranetNoInterface;

  String get intranetAdapter;

  String get intranetGateway;

  String get intranetPrivateDnsOff;

  String get intranetNoDnsServer;

  String get intranetPrimaryDns;

  String get intranetPrivateDns;

  String get intranetPortFooter;

  String get intranetCopyAddressWithPort;

  String get speedDetailTitle;

  String get speedCurrentDownload;

  String get speedSamplingPaused;

  String get speedLive;

  String get speedSamplingHint;

  String get speedCurrentUpload;

  String get speedDownloadPeak;

  String get speedUploadPeak;

  String get speedSamples;

  String get speedTodayTotal;

  String get speedNoTrafficToday;

  String get speedTotal;

  String get speedRateFooter;

  String get speedNoChannelSource;

  String get speedNoDataInMode;

  String get speedWaitingSample;

  String get commonNoData;

  String get commonPendingTitle;

  String get commonPendingBody;

  String get homePowerPending;

  String intranetModeNotListening(String mode);

  String intranetListeningOn(int port);

  String intranetServiceStopped(int port);

  String commonCopied(String text);

  String intranetGatewaySuffix(String gateway);

  String get speedTotalDash;

  String siteLatencyAliveRatio(int alive, int total);

  String siteLatencyLastRun(String ago);

  String siteLatencyProviderSuffix(String name);

  String siteLatencySitesCount(int count);

  String siteLatencyTestCategory(String category);

  String memorySystemShare(String percent);

  String memorySystemUsedOf(String total, String used);

  String get memoryNoChannel;

  String trafficStructureRateValue(
    String count,
    String latency,
    String percent,
  );

  String trafficStructureShareValue(String count, String percent);

  String statusPausedSummary(String core, String mode);

  String speedTotalsDown(String percent);

  String speedTotalsUp(String percent);

  String speedPeakAverage(String average, String peak);

  String get intranetConnectHintSentence;

  String intranetModeNotListeningSentence(String mode);

  String intranetPrivateDnsOn(String dns);

  String intranetSecondaryDns(int index);

  String intranetCopyAddressSemantics(String address);

  String speedTotalAccumulated(String value);

  String dashboardSitesFull(int count);

  String dashboardSitesRemaining(int count);

  String dashboardSitesMax(int count);

  String dashboardSitesPosition(int index);

  String siteLatencyFailedCount(int count);

  String get siteLatencyDetailFooterLong;

  String get homeLayerPowerButton;

  String get homeLayerPoem;

  String get bottomBarHome;

  String get bottomBarFeatureHub;

  String get bottomBarLogDashboard;

  String get bottomBarAppTraffic;

  String get bottomBarNetworkTools;

  String get bottomBarSettings;

  String get bottomBarStyleFloating;

  String get bottomBarStyleDocked;

  String get tabTransitionNone;

  String get tabTransitionFade;

  String get tabTransitionSlide;

  String get tabTransitionScale;

  String get commonOff;

  String get glassModeStandard;

  String get glassModeUltra;

  String get previewBrightnessLight;

  String get previewBrightnessDark;

  String get resolutionModeSingle;

  String get resolutionModeSmart;

  String get resolutionModeParallel;

  String get resolutionModePrimaryBackup;

  String get workModeNormalTitle;

  String get workModeNormalBadge;

  String get workModeNormalSummary;

  String get workModeServerTitle;

  String get workModeServerBadge;

  String get workModeServerSummary;

  String get workModeExpressTitle;

  String get workModeExpressBadge;

  String get workModeExpressSummary;

  String get workModeSettingTitle;

  String get workModeGuideTitle;

  String get commonName;

  String get commonPort;

  String get stateStopped;

  String get stateStarting;

  String get stateRunning;

  String get stateStopping;

  String get powerStateError;

  String get logModeAllLabel;

  String get logModeAllDescription;

  String get logModeBlockedLabel;

  String get logModeBlockedDescription;

  String get logModeOffLabel;

  String get logModeOffDescription;

  String get tunnelIpv6Title;

  String get tunnelIpv6Subtitle;

  String get dnsAaaaTitle;

  String get dnsAaaaSubtitle;

  String get routeIncludeTitle;

  String get routeIncludeSubtitle;

  String get routeExcludeTitle;

  String get routeExcludeSubtitle;

  String get routeIncludeAll;

  String get routeCidrAddTitle;

  String get routeCidrLabel;

  String get routeCidrHint;

  String get routeCidrInvalid;

  String get routeCidrDuplicate;

  String get routeCidrEmpty;

  String get routeCidrEmptySubtitle;

  String routeCidrCount(int count);

  String get routeCidrFooter;

  String get commonToday;

  String get logWindowSevenDays;

  String get logWindowSevenDaysRecent;

  String get commonAll;

  String get trafficWindowWeek;

  String get trafficWindowMonth;

  String get trafficSortTotal;

  String get trafficSortDownload;

  String get trafficSortUpload;

  String get davStatusIdle;

  String get davStatusConnecting;

  String get davStatusConnected;

  String get davStatusFailed;

  String get updateStageIdle;

  String get updateStageChecking;

  String get updateStageUpToDate;

  String get updateStageAvailable;

  String get updateStageDownloading;

  String get updateStageDownloaded;

  String get ipQualityStageIdle;

  String get ipQualityStageLoading;

  String get ipQualityStageLoaded;

  String get ipQualityStageFailed;

  String get subscriptionDeleted;

  String get subscriptionDisabled;

  String get subscriptionUngrouped;

  String get providerNotTested;

  String get elapsedJustNow;

  String elapsedSecondsAgo(int count);

  String elapsedMinutesAgo(int count);

  String elapsedHoursAgo(int count);

  String elapsedDaysAgo(int count);

  String providerRaceSummary(String count, String names);

  String get rulesDbUnavailable;

  String get agentApiKeyMissing;

  String get agentNoExtraInfo;

  String get agentNoLegacyDatabase;

  String get autoUpdateDisabled;

  String get autoUpdateNoSubscriptions;

  String get autoUpdateNotDue;

  String get autoUpdateBusy;

  String get cleanupGroupRuntime;

  String get cleanupGroupWeights;

  String get cleanupGroupRules;

  String get cleanupGroupStorage;

  String get cleanupGroupGuides;

  String get backupReadFileFailed;

  String get caChannelUnavailable;

  String get caInstallUnavailable;

  String get caDownloadDirUnavailable;

  String get fontSystemDefault;

  String get diagnosticsChannelUnavailable;

  String get diagnosticsUnsupported;

  String get diagnosticsPingUnsupported;

  String get diagnosticsTraceUnsupported;

  String get diagnosticsDnsUnsupported;

  String get diagnosticsEmptyTarget;

  String get diagnosticsTargetHasSpace;

  String get diagnosticsAnswerUpstream;

  String get diagnosticsAnswerCache;

  String get diagnosticsAnswerRewrite;

  String get diagnosticsAnswerBlocked;

  String get diagnosticsAnswerFailed;

  String get diagnosticsNoActiveNetwork;

  String get aiPresetMainland;

  String get aiPresetOverseas;

  String get aiPresetAggregator;

  String get aiProviderConfigured;

  String get aiProviderExampleName;

  String get logSubscriptionDeleted;

  String get logRaceFastest;

  String get logRaceSmart;

  String get logRaceSequential;

  String get logRaceSingle;

  String get providerNoProviderSelected;

  String get onDemandDisabled;

  String get onDemandUnknownSsid;

  String get onDemandSameNetwork;

  String get onDemandNoWifi;

  String get onDemandStarted;

  String get onDemandAlreadyRunning;

  String get onDemandStopped;

  String get onDemandAlreadyStopped;

  String get onDemandBusy;

  String get onDemandNeedsConsent;

  String get speedTestSelectProvider;

  String get speedTestEmptyDomain;

  String get imagePickerUnavailable;

  String get recognitionInvalidConfig;

  String get recognitionGithubInterrupted;

  String get recognitionGithubTimeout;

  String get recognitionNetworkUnavailable;

  String get recognitionUpdateFailed;

  String get subscriptionNotFound;

  String get subscriptionDatabaseUnavailable;

  String get subscriptionRuleDbUnavailable;

  String get subscriptionUpdateFailed;

  String get subscriptionLocalFileUnreadable;

  String get subscriptionLocalRuleDbUnavailable;

  String get subscriptionNothingToUpdate;

  String get subscriptionPickRuleFile;

  String get subscriptionPickTxtFile;

  String get subscriptionLegacyDatabaseMissing;

  String get subscriptionThisFile;

  String get subscriptionThisLink;

  String get subscriptionLocalRuleFile;

  String get webdavEmptyCredentials;

  String get webdavDirectoryCreated;

  String get webdavUploaded;

  String get webdavNoBackup;

  String get webdavDownloaded;

  String get updateCheckFirst;

  String get updateDownloadFirst;

  String get updateInstallerUnavailable;

  String get workModeNoDataPlane;

  String get workModeNoVpnConsent;

  String get workModeStartTimeout;

  String get workModeVpnStartFailed;

  String get aiProviderZhipu;

  String get aiProviderMoonshot;

  String get aiProviderDashscope;

  String get aiProviderVolcengine;

  String get aiProviderQianfan;

  String get aiProviderStepfun;

  String get aiProviderSiliconflow;

  String get aiProviderOllamaLocal;

  String rulesReadFailed(String detail);

  String autoUpdateChecked(int count);

  String caChannelUnavailableDetail(String detail);

  String caReadFailedCode(String code);

  String caReadFailed(String detail);

  String agentAnalysisFailed(String detail);

  String diagnosticsFailedCode(String code);

  String diagnosticsFailed(String detail);

  String subscriptionDeletedWithId(int id);

  String providerLatencyValue(int value);

  String providerRaceSummaryNames(int count, String names);

  String get providerNamesSeparator;

  String recognitionInvalidConfigKept(String detail);

  String recognitionFetchFailed(String detail);

  String recognitionUpdateFailedDetail(String detail);

  String subscriptionAlreadyExists(String kind, String what);

  String subscriptionUpdatedCount(int count);

  String subscriptionUnchangedCount(int count);

  String subscriptionFailedCount(int count);

  String subscriptionSkippedCount(int count);

  String subscriptionAlreadyExistsNamed(String kind, String name, String what);

  String get commonBypass;

  String get commonRewrite;

  String get cleanupLogs;

  String get cleanupTraffic;

  String get cleanupCrash;

  String get cleanupDnsCache;

  String get cleanupProviderWeights;

  String get cleanupBootstrapWeights;

  String get cleanupDomainRules;

  String get cleanupAddressRules;

  String get cleanupSubscriptions;

  String get cleanupAppRules;

  String get cleanupOutboundProxy;

  String get cleanupCaCertificate;

  String get cleanupDownloadCache;

  String get cleanupCustomBackground;

  String get cleanupRuntimeLogs;

  String get cleanupAutomationEvents;

  String get cleanupRuleVersions;

  String get cleanupMirrorTemplates;

  String get cleanupRecognitionMembers;

  String get cleanupSettingsGuides;

  String get cleanupAllData;

  String cleanupDoneItems(String action, int count, String detail);

  String cleanupDoneEmpty(String action);

  String get blockResponseNxdomain;

  String get blockResponseNxdomainDescription;

  String get blockResponseNodata;

  String get blockResponseNodataDescription;

  String get blockResponseRefused;

  String get blockResponseRefusedDescription;

  String get blockResponseZeroAddress;

  String get blockResponseZeroAddressDescription;

  String get subscriptionSourceRemote;

  String get subscriptionSourceLocal;

  String get subscriptionKindDomain;

  String get subscriptionKindHosts;

  String logRowDirect(String protocol);

  String logRowDirectWithPackage(String package, String protocol);

  String get logRowCacheHit;

  String get logRowNoAuthority;

  String get cachePresetConservativeName;

  String get cachePresetConservativeSummary;

  String get cachePresetStandardName;

  String get cachePresetStandardSummary;

  String get cachePresetAggressiveName;

  String get cachePresetAggressiveSummary;

  String get cachePresetCustomName;

  String get cachePresetCustomSummary;

  String cachePresetMultiplier(String value);

  String cachePresetExample(int upstream, int cached);

  String get cachePresetRecommended;

  String get cacheDisabledSummary;

  String get upstreamNameRequired;

  String get upstreamAddressRequired;

  String get upstreamDohNeedsHttps;

  String get upstreamDohInvalidUrl;

  String get upstreamPortRange;

  String get upstreamIpv6Invalid;

  String get upstreamPresetAliyun;

  String get upstreamPresetTencent;

  String get upstreamPresetByteDance;

  String cleanupFailed(String detail);

  String get cleanupProxyRestored;

  String get cleanupCaNeedsReimport;

  String get hubCategoryDns;

  String get hubModuleMore;

  String get hubProviderManagement;

  String get hubProviderManagementDescription;

  String get hubBootstrap;

  String get hubBootstrapDescription;

  String get hubResolution;

  String get hubResolutionDescription;

  String get hubCache;

  String get hubCacheDescription;

  String get hubCategoryRules;

  String get hubRuleControl;

  String get hubRuleControlDescription;

  String get hubBlocklist;

  String get hubBlocklistDescription;

  String get hubAllowlist;

  String get hubAllowlistDescription;

  String get hubRewrite;

  String get hubRewriteDescription;

  String get hubCategoryNetwork;

  String get hubAppTraffic;

  String get hubAppTrafficDescription;

  String get hubAppRules;

  String get hubAppRulesDescription;

  String get hubBlockedApps;

  String get hubBlockedAppsDescription;

  String get hubExcludedApps;

  String get hubExcludedAppsDescription;

  String get hubCategoryAdvanced;

  String get hubHttpsInspection;

  String get hubHttpsInspectionDescription;

  String get hubOutboundProxy;

  String get hubOutboundProxyDescription;

  String get hubDiagnostics;

  String get hubDiagnosticsDescription;

  String get hubAiAnalysis;

  String get hubAiAnalysisDescription;

  String get hubCategoryInterface;

  String get hubAppearance;

  String get hubAppearanceDescription;

  String get hubProviderVisibility;

  String get hubProviderVisibilityDescription;

  String get hubHiddenFeatures;

  String get hubHiddenFeaturesDescription;

  String get hubOtherSettings;

  String get hubOtherSettingsDescription;

  String get hubCategoryData;

  String get hubLogs;

  String get hubLogsDescription;

  String get hubBackup;

  String get hubBackupDescription;

  String get hubDataCleanup;

  String get hubDataCleanupDescription;

  String get hubTroubleshooting;

  String get hubTroubleshootingDescription;

  String get hubCategoryNetworkTools;

  String get hubCategoryAutomation;

  String get hubCategoryIntegration;

  String get hubCategorySubscription;

  String get hubDnsLeak;

  String get hubAutoUpdateDescription;

  String get hubCategoryAbout;

  String get hubAbout;

  String get hubAboutDescription;

  String get hubSponsor;

  String get hubSponsorDescription;

  String get hubSponsors;

  String get hubSponsorsDescription;

  String get fontSizeSmall;

  String get fontSizeStandard;

  String get fontSizeLarge;

  String get fontSizeExtraLarge;

  String get fontSizeFooter;

  String get fontSizePreview;

  String get fontSizePresets;

  String get appearancePoem;

  String get appearancePoemBody;

  String get appearanceTitle;

  String get appearanceThemeSection;

  String get appearanceLayoutSection;

  String get appearanceHomeNotificationSection;

  String get appearanceFeedbackMotionTitle;

  String get appearanceFeedbackMotionSubtitle;

  String get appearanceFeedbackSection;

  String get appearanceMotionSection;

  String get appearanceInterfaceSection;

  String get appearanceHomeOpacitySubtitle;

  String get appearancePureBlackOn;

  String get appearancePureBlackOff;

  String get appearanceHomeSection;

  String get appearanceHomeSentenceSubtitle;

  String get appearanceNotification;

  String get appearanceNotificationSubtitle;

  String get appearanceBackgroundSection;

  String get appearanceHapticSubtitle;

  String get appearanceBottomBarStyleFloating;

  String get appearanceBottomBarStyleDocked;

  String get appearanceTabTransitionSubtitle;

  String get appearanceMotionFooter;

  String get appearancePaletteGoldLegacy;

  String get appearancePaletteFooter;

  String get launcherIconTitle;

  String get launcherIconInfoLabel;

  String get launcherIconDefault;

  String get launcherIconDefaultDescription;

  String get launcherIconAdguard;

  String get launcherIconAdguardDescription;

  String get launcherIconFooter;

  String get launcherIconApplied;

  String get launcherIconApplyFailed;

  String fontFamilySizeSubtitle(String percent);

  String get fontFamilySystemDefault;

  String get fontFamilyImported;

  String get fontFamilyEmpty;

  String get fontFamilyFooter;

  String get fontFamilyLocalOnly;

  String get fontFamilyImportFailed;

  String get fontFamilyDeleteTitle;

  String get commonCancel;

  String get commonDelete;

  String fontFamilyDeleteConfirm(String name);

  String get fontFamilyImport;

  String get fontFamilyReading;

  String get fontFamilyPickFile;

  String get notificationPersistentSection;

  String get notificationPersistentFooter;

  String get notificationPersistent;

  String get notificationPersistentSubtitle;

  String get notificationShowSpeedSubtitle;

  String get notificationStatsSection;

  String get notificationStatsEmpty;

  String get notificationStatsFooter;

  String get notificationStatsHidden;

  String get notificationStatTotal;

  String get notificationStatSpeed;

  String get notificationStatTotalSubtitle;

  String get notificationStatPassedSubtitle;

  String get notificationStatFilteredSubtitle;

  String get notificationStatFailedSubtitle;

  String get notificationStatCachedSubtitle;

  String get notificationStatRewrittenSubtitle;

  String get notificationTextRunning;

  String get notificationTextStopped;

  String get notificationTextHint;

  String get notificationTextSection;

  String get notificationTextFooter;

  String get notificationPermissions;

  String get notificationSystemPermission;

  String get notificationSystemPermissionSubtitle;

  String get backgroundTitle;

  String get backgroundSection;

  String get backgroundFooter;

  String get backgroundEnable;

  String get backgroundPickFirst;

  String get backgroundBehindPages;

  String get backgroundAddImage;

  String get backgroundAddImageSubtitle;

  String get backgroundAdded;

  String get backgroundAddedFooter;

  String get backgroundEmpty;

  String get backgroundEmptyDescription;

  String get backgroundDeleteTitle;

  String get backgroundDeleteConfirm;

  String get foregroundTitle;

  String get foregroundPrivacySection;

  String get foregroundPrivacyFooter;

  String get foregroundHide;

  String get foregroundHideSubtitle;

  String get foregroundRouting;

  String get foregroundBypassLan;

  String get foregroundBypassLanSubtitle;

  String get foregroundStability;

  String get foregroundBatteryFooter;

  String get foregroundIgnoreBattery;

  String get foregroundIgnoreBatterySubtitle;

  String get rootTakeoverSection;

  String get rootTakeoverTitle;

  String get rootTakeoverSubtitle;

  String get rootTakeoverTunnelModesOnly;

  String get rootTakeoverFooter;

  String get rootTakeoverProbeTitle;

  String get rootTakeoverProbeChecking;

  String get rootTakeoverProbeAvailable;

  String rootTakeoverProbeUnavailable(String message);

  String get rootTakeoverProbeUnavailableNoReason;

  String get rootTakeoverProbeUnsupported;

  String get rootTakeoverRunning;

  String get dayNightTitle;

  String get dayNightFollowSystemDescription;

  String get dayNightFooter;

  String get homeOpacityTitle;

  String get homeOpacityComponents;

  String get homeOpacityComponentsFooter;

  String get homeOpacityText;

  String get bottomBarHomeSubtitle;

  String get bottomBarFeatureHubSubtitle;

  String get bottomBarLogDashboardSubtitle;

  String get bottomBarAppTrafficSubtitle;

  String get bottomBarNetworkToolsSubtitle;

  String get bottomBarSettingsSubtitle;

  String get bottomBarMinimumHint;

  String get bottomBarCustomTitle;

  String bottomBarItemsHeader(String count, String max);

  String bottomBarDragHint(String max);

  String get bottomBarDisabled;

  String get bottomBarNewItemFooter;

  String get bottomBarFeel;

  String get homeSentenceTitle;

  String get homeSentenceFooter;

  String get appearancePaletteTitle;

  String get appearancePaletteInfoLabel;

  String get appearancePaletteBody;

  String get dayNightInfoLabel;

  String get appearanceFontSizeLabel;

  String appearanceFontSizeCurrent(int percent);

  String get appearanceFontSection;

  String appearanceFontImported(String name);

  String appearanceFontDeleted(String name);

  String appearanceBottomBarMax(int max);

  String appearanceBottomBarHeader(int count, int max);

  String appearanceBottomBarDragBody(int max);

  String appearanceBottomBarSelected(int count);

  String get appearanceHaptic;

  String get appearancePureBlack;

  String get appearanceBottomBarStyle;

  String get appearanceTabTransition;

  String get appearanceLiquidGlass;

  String get fontFamilyTitle;

  String get fontSizeRestoreDefaults;

  String get fontFamilyHapticSubtitle;

  String get ruleKindBlockTitle;

  String get ruleKindBlockSummary;

  String get ruleKindAllowTitle;

  String get ruleKindAllowSummary;

  String get ruleKindRewriteTitle;

  String get ruleKindRewriteSummary;

  String get ruleSourceUser;

  String get ruleSourceSubscription;

  String get ruleSourcePreset;

  String get rulePatternRequired;

  String get ruleAllowNeedsAllowlist;

  String get ruleAlreadyExists;

  String get ruleDomainHint;

  String get ruleTargetRequired;

  String get ruleTargetHint;

  String get ruleImportant;

  String get ruleReadOnly;

  String get ruleEdit;

  String get ruleDelete;

  String get batchImportDone;

  String get batchAddTitle;

  String get batchTarget;

  String get batchTargetTable;

  String get batchTargetTableSubtitle;

  String get batchPlaceholder;

  String get batchImportable;

  String get batchDuplicated;

  String get batchInvalid;

  String get batchInvalidHeader;

  String get batchDuplicateHeader;

  String get ruleClearCustomTitle;

  String get commonClearAll;

  String get ruleResetDefault;

  String get commonReset;

  String get rulePresetProtectedTitle;

  String get ruleAllowEditTitle;

  String get ruleAllowEditConfirm;

  String get ruleTotal;

  String get ruleEnabled;

  String get ruleRewriteEntries;

  String get ruleCustom;

  String get ruleAllowEditDefault;

  String get ruleAllowEditDefaultSubtitle;

  String get ruleNoMatch;

  String get ruleNoMatchDescription;

  String get ruleAll;

  String get formIssuesTitle;

  String get formSave;

  String get formProcessing;

  String get formAdd;

  String get formDelete;

  String get formHelp;

  String get formGotIt;

  String get rulePatternHint;

  String ruleBatchImported(String count, int kind);

  String ruleBatchSkippedDuplicates(int count);

  String ruleBatchAllowRejected(int count);

  String ruleBatchImportCount(int count);

  String ruleBatchMoreDuplicates(int count);

  String ruleAddForKind(String kind);

  String get ruleEditDefaultPreset;

  String ruleEditForKind(String kind);

  String ruleDeletePresetMessage(String pattern);

  String ruleDeleteSubscriptionMessage(String name, String pattern);

  String ruleDeleteUserMessage(String pattern);

  String ruleClearCustomMessage(String kind);

  String get ruleResetMessage;

  String get rulePresetProtectedMessage;

  String get ruleAllowEditMessage;

  String ruleTally(int matched, int enabled);

  String ruleNoRulesForKind(String kind);

  String ruleClearCustomForKind(String kind);

  String get subsPickTxt;

  String get subsNoPersistPermission;

  String get subsGroupNameRequired;

  String get subsEdit;

  String get subsAdd;

  String get subsSaveTooltip;

  String get subsInfoSection;

  String get subsSourceType;

  String get subsSourceLocalPick;

  String get subsSourceRemoteDownload;

  String get subsLocalRuleFile;

  String get subsLocalFileSubscription;

  String get subsPickFile;

  String get subsLocalFileHint;

  String get subsLocalFileRepick;

  String get subsChoose;

  String get subsNameOptional;

  String get subsNameEmptyFileName;

  String get subsUrl;

  String get subsNameEmptyUrlTail;

  String get subsRuleType;

  String get subsKindHostsHint;

  String get subsKindDomainHint;

  String get subsGroupHint;

  String get subsNewGroupShort;

  String get subsMirrorTemplateFooter;

  String get subsAddMirrorTemplate;

  String get subsAddMirrorTemplateSubtitle;

  String get subsMirrorFooter;

  String get subsUseMirrorTemplate;

  String get subsUseMirrorTemplateSubtitle;

  String get subsMirrorTemplate;

  String get subsMirrorFallback;

  String get subsMirrorFallbackSubtitle;

  String get subsEffectiveUrl;

  String get subsNothingToUpdate;

  String get subsDeleteTitle;

  String get subsRenameTitle;

  String get subsNameRequired;

  String get subsTitle;

  String get subsUpdateAll;

  String get subsCount;

  String get subsRuleCount;

  String get subsAbnormal;

  String get subsUpdating;

  String get subsEmptyLabel;

  String get subsEmptyDescription;

  String get subsUpdateFooter;

  String get subsAllGroups;

  String get subsNewGroupTitle;

  String get subsEditRemoteHint;

  String get subsEditLocalHint;

  String get subsAddRemoteHint;

  String get subsKindLabel;

  String get subsGroupLabel;

  String get subsMirrorTitle;

  String subsDeleteMessage(String name);

  String subsTotal(int count);

  String subsGroupTotal(String count, int group);

  String get subsUpdateNow;

  String get subsReimport;

  String get subsRename;

  String subsConsecutiveFailures(int count);

  String get subsMirrorFallbackShort;

  String get subsMirrorNoFallback;

  String get subsLastUpdateFailed;

  String get subsNeverUpdated;

  String subsRuleCountValue(String count);

  String subsRulesStored(String action, String count);

  String get subsActionRemote;

  String get subsActionLocal;

  String get subsPickRuleFile;

  String get subsChange;

  String get subsGroupShort;

  String get subsManageGroupsShort;

  String get subsManageGroupsTitle;

  String get subsGroupsList;

  String get subsGroupRenameTitle;

  String get subsGroupDeleteTitle;

  String subsGroupDeleteMessage(String name);

  String get subsGroupDuplicate;

  String subsGroupSubCount(int count);

  String get subsGroupsEmpty;

  String get subsGroupsEmptyHint;

  String get subsGroupsFooter;

  String subsMirrorName(String mirror);

  String get trafficPackageName;

  String get trafficAppName;

  String get trafficDown;

  String get trafficUp;

  String get trafficTotal;

  String get trafficShare;

  String get trafficStartDate;

  String get trafficLastUpdate;

  String get trafficAttributionFooter;

  String get trafficAttributionTitle;

  String get trafficScopeTitle;

  String get trafficScopeBody;

  String get trafficWhyLowerTitle;

  String get trafficWhyLowerBody;

  String get trafficWhyNoRateTitle;

  String get trafficWhyNoRateBody;

  String get trafficRetentionTitle;

  String get trafficRetentionBody;

  String get trafficSystemAppsTitle;

  String get trafficSystemAppsBody;

  String get trafficUpstreamFooter;

  String get trafficTitle;

  String get trafficClearHistory;

  String get trafficRefresh;

  String get trafficAttribution;

  String get trafficLoadFailed;

  String get trafficLoading;

  String get trafficAppCount;

  String get trafficAppCountUnit;

  String get trafficNoData;

  String get trafficNoMatchingApps;

  String get trafficRankingTitle;

  String trafficShareFooter(String range, String window);

  String get trafficClearTitle;

  String get trafficConfirmClear;

  String get trafficClearBody;

  String get trafficRangeAllHistory;

  String get trafficSessionRange;

  String get trafficSessionUnavailable;

  String get trafficLiveRate;

  String get trafficHideSystemApps;

  String get trafficSearchHint;

  String get trafficAllHistory;

  String get trafficLiveRateUnavailable;

  String get trafficHideSystemAppsSubtitle;

  String trafficWindowLabelDate(String date);

  String trafficWindowLabelRange(String end, String start);

  String trafficShareWindow(String range, String window);

  String trafficTotalApps(int count, String total);

  String trafficSearchEmpty(String search);

  String trafficHiddenCount(int count);

  String get trafficNoRecordsBody;

  String trafficNoRecordsForWindow(String window);

  String trafficOptionUnavailable(String label, String reason);

  String get trafficNoSourceReason;

  String trafficCleared(int count);

  String trafficClearFailed(String detail);

  String trafficShareBarTooltip(String sort, String value);

  String get trafficWhyDaemonTitle;

  String get trafficWhyDaemonBody;

  String get trafficLiveRateTitle;

  String trafficNoLiveRate(String window);

  String trafficLiveRateBody(String window);

  String get trafficSearchPlaceholder;

  String trafficWindowDown(String window);

  String trafficWindowUp(String window);

  String get trafficTotalDown;

  String get trafficTotalUp;

  String get obsRequestsTitle;

  String get obsSource;

  String get obsStatus;

  String get obsRefresh;

  String get obsClearFilter;

  String get obsLoadFailed;

  String get obsLoading;

  String get obsNoRecords;

  String get obsNoMatchingRequests;

  String get obsNoRecordsBody;

  String get obsResetFilter;

  String get obsRecordsHeader;

  String get obsRetry;

  String get obsBypassedDns;

  String get obsBlockedDns;

  String get obsRewrittenDns;

  String get obsErrorDns;

  String get obsPassedDns;

  String get obsPassedHttps;

  String get obsRewrittenHttps;

  String get obsBlockedHttps;

  String get obsBypassedHttps;

  String get obsErrorHttps;

  String get obsNoRuleHttps;

  String get obsNone;

  String get obsRequestDetailTitle;

  String get obsCachedChip;

  String get obsBasicInfo;

  String get obsTime;

  String get obsProtocol;

  String get obsAppPackage;

  String get obsResolved;

  String get obsElapsed;

  String get obsBlockingSubscription;

  String get obsRuleMatch;

  String get obsRule;

  String get obsHandling;

  String get obsError;

  String get obsAiAnalysis;

  String get obsRawRecord;

  String get obsRawRecordFooter;

  String get obsFailedHint;

  String get obsRulesHint;

  String get obsCacheHit;

  String obsCopied(String text);

  String get obsCopyAddress;

  String get obsCopyDomain;

  String get obsInBlocklist;

  String get obsAddToBlocklist;

  String get obsInAllowlist;

  String get obsAddToAllowlist;

  String get obsIpOnlyFooter;

  String get obsAnalyzeRequest;

  String get obsAnalyzeRequestBody;

  String obsCopiedHost(String host);

  String obsAddedToKind(String domain, String kind);

  String obsAlreadyInKind(String domain, String kind);

  String obsCurrentFilter(String filter);

  String obsFooterCount(int count, int failed, String filter, String more);

  String obsFooterFilter(String filter);

  String get obsFooterMore;

  String get obsFooterAll;

  String get obsByApp;

  String get obsViewAppRequests;

  String get obsAppsTitle;

  String get obsAppsHeader;

  String get obsAppsEmpty;

  String get obsAppsEmptyBody;

  String get obsAppsFooter;

  String obsAppRequestCount(int count);

  String get obsExportLogs;

  String get obsExportTitle;

  String get obsExportRangeSection;

  String get obsExportRangeAll;

  String get obsExportRangeHour;

  String get obsExportRangeDay;

  String get obsExportRangeWeek;

  String get obsExportRangeCustom;

  String get obsExportCustomRange;

  String get obsExportPickRange;

  String get obsExportScopeSection;

  String get obsExportIntro;

  String get obsExportDnsOnlyNote;

  String get obsExportApps;

  String get obsExportAllApps;

  String obsExportSelectedApps(int count);

  String obsExportSelectedColumns(int count);

  String get obsExportAppPickerTitle;

  String get obsExportAppPickerDone;

  String get obsExportColumnsSection;

  String get obsExportColumnTime;

  String get obsExportColumnSource;

  String get obsExportColumnStatus;

  String get obsExportColumnAppName;

  String get obsExportColumnPackage;

  String get obsExportColumnHost;

  String get obsExportColumnProtocol;

  String get obsExportColumnRule;

  String get obsExportColumnElapsed;

  String get obsExportColumnCached;

  String get obsExportColumnSubscription;

  String get obsExportColumnMessage;

  String get obsExportCachedYes;

  String get obsExportCachedNo;

  String get obsExportLimit;

  String obsExportLimitHint(int max);

  String get obsExportAction;

  String get obsExportBusy;

  String obsExportDone(int count);

  String get obsExportEmpty;

  String get obsExportCancelled;

  String get obsExportFailed;

  String obsExportTruncated(int count);

  String get obsExportFooter;

  String get obsExportAtLeastOneColumn;

  String obsExportInvalidLimit(int max);

  String get logsSubStatsTitle;

  String get logsRefresh;

  String get logsTimeRange;

  String get logsSubStatsFooter;

  String get logsOverview;

  String get logsSubStatsLoadFailed;

  String get logsLoadingStats;

  String get logsBlockingSubs;

  String get logsMissingSubColumn;

  String get logsMissingSubColumnBody;

  String get logsAllRecordedRequests;

  String get logsBlockedRequests;

  String get logsAllRecordedFooter;

  String get logsNoBlockingSubs;

  String get logsNoBlockingSubsBody;

  String get logsBlockingSubsFooter;

  String get logsExpired;

  String get logsRaceTitle;

  String get logsRaceFooter;

  String get logsRaceLoadFailed;

  String get logsLoadingRace;

  String logsRaceSummary(String range, String count);

  String get logsRaceEmptyRange;

  String get logsRaceRequests;

  String get logsSuccess;

  String get logsAverageElapsed;

  String get logsStrategyOverview;

  String get logsStrategyFooter;

  String get logsWinnerProviders;

  String get logsNoWinners;

  String get logsNoWinnersBody;

  String get logsWinnerFooter;

  String logsAverageWinLatency(String latency);

  String get logsSmartPrimary;

  String get logsSmartPrimaryFooter;

  String logsPrimaryHit(String percent, String latency);

  String get logsDashboardTitle;

  String get logsModeTooltip;

  String get logsRequestsDashboard;

  String get logsRequestsDashboardBody;

  String get logsFocusedDashboard;

  String get logsFocusedDashboardBody;

  String get logsServiceOverview;

  String get logsPrivacyBody;

  String get logsCacheTableTitle;

  String logsCacheLoadFailed(String detail);

  String get logsLoadingCache;

  String get logsCacheEmpty;

  String get logsCacheNoMatch;

  String get logsCacheEmptyBody;

  String logsCurrentSearch(String query);

  String get logsLiveCache;

  String get logsNeverHit;

  String logsCacheFooter(String count);

  String get logsBootstrapTitle;

  String get logsBootstrapFooter;

  String get logsBootstrapLoadFailed;

  String get logsLoadingBootstrap;

  String logsBootstrapSummary(String range, String count);

  String get logsBootstrapEmptyRange;

  String get logsAttempts;

  String get logsSuccessRate;

  String get logsNodes;

  String get logsNoProbes;

  String get logsNoProbesBody;

  String get logsNodesFooter;

  String get logsCacheDetailTitle;

  String get logsCacheExpiringBody;

  String get logsCacheValidBody;

  String get logsExpiring;

  String get logsValid;

  String logsHitTimes(int count);

  String get logsCacheInfo;

  String get logsRecordType;

  String get logsRemainingTtl;

  String get logsOriginalTtl;

  String get logsExpiry;

  String get logsHitCount;

  String get logsLastHit;

  String get logsResponseSize;

  String get logsAnalyzeDomain;

  String get logsCacheDetailFooter;

  String get logsAiInsight;

  String get logsNotAnalysed;

  String get logsHasReport;

  String get logsAiInsightBody;

  String get logsAnalyseTraffic;

  String get logsViewFullReport;

  String logsModelName(String model);

  String logsSuccessWith(String percent);

  String logsAverageWith(String latency);

  String logsPrimaryHitOnly(String percent);

  String logsFallbackUses(String count);

  String logsBootstrapRow(
    String ip,
    String percent,
    String latency,
    String failures,
  );

  String logsBootstrapFailures(String count);

  String logsEntryCount(int count);

  String logsCacheRow(String ttl, int count, int size);

  String logsLastHitAt(String time);

  String logsCacheFooterCount(int count);

  String logsSubStatsRow(String status, String count);

  String get aboutTitle;

  String get aboutMore;

  String get aboutProject;

  String get aboutJoinQq;

  String aboutQqGroup(String number);

  String get aboutSponsor;

  String get aboutSupport;

  String get aboutCredits;

  String get aboutCreditsUi;

  String get aboutCreditsCore;

  String get aboutCreditsBody;

  String get aboutSettings;

  String get aboutStartupCheck;

  String get aboutStartupCheckOn;

  String get aboutStartupCheckOff;

  String get aboutDisclaimerEntry;

  String get aboutDisclaimerEntryBody;

  String get aboutLegal;

  String get aboutSponsorList;

  String get aboutSponsorListBody;

  String get aboutInstallerFailed;

  String get aboutAppName;

  String get aboutTagline;

  String get aboutChecking;

  String get aboutCheckUpdate;

  String get aboutDownloading;

  String get aboutInstall;

  String get aboutDownload;

  String get aboutCheckingRelease;

  String aboutUpToDate(String version);

  String aboutVersionSuffix(String version);

  String aboutFoundVersion(String version);

  String aboutCurrentSuffix(String version);

  String get aboutNew;

  String get aboutNewVersion;

  String aboutUpdatePackage(String version);

  String aboutLinkCopyFallback(String url);

  String get devStressLogs;

  String devStressLogsBody(int count);

  String get devErrorReport;

  String get devErrorReportBody;

  String get devClearAll;

  String get devClearAllBody;

  String get devVacuum;

  String get devVacuumBody;

  String get devStorageTitle;

  String get devStorageV2Ready;

  String get devStorageV2Pending;

  String devStorageV2Detail(String state, String date);

  String devStorageV2Error(String error);

  String devStorageV2Files(int kb);

  String get storageV2Title;

  String get storageV2Preparing;

  String storageV2Progress(String database, int current, int total);

  String get storageV2Verifying;

  String get storageV2Cleaning;

  String get storageV2NeedStop;

  String get storageV2StopAndRetry;

  String get storageV2Retry;

  String get storageV2Discard;

  String storageV2Failed(String error);

  String get storageV2DiscardTitle;

  String get storageV2DiscardConfirm;

  String get devCancel;

  String get devRun;

  String devConfirmBody(String action);

  String devActionFailed(String action, String error);

  String get devStressNoDb;

  String devStressDone(String count, String file);

  String get devTestException;

  String get devErrorReported;

  String get devVacuumNoDb;

  String devVacuumDone(String files, int kb);

  String get devRestartNeeded;

  String get devLater;

  String get devQuitNow;

  String get devClearAllDone;

  String get devOptions;

  String get devDiagnostics;

  String get devIpQuality;

  String get devIpQualityBody;

  String get devRequestLogs;

  String get devRequestLogsBody;

  String get devLogRetention;

  String get devLogRetentionBody;

  String get devTroubleshoot;

  String get devTroubleshootBody;

  String get devDataCleanup;

  String get devUnlocked;

  String get devLocked;

  String get devWarning;

  String get devRunning;

  String get sponsorGithub;

  String get sponsorReadme;

  String get sponsorReadmeCopied;

  String get sponsorUsage;

  String get sponsorUsageNewFeatures;

  String get sponsorUsageBugs;

  String get sponsorUsageTokens;

  String get sponsorFreeWays;

  String get sponsorFreeStar;

  String get sponsorFreeIssue;

  String get sponsorFreePr;

  String get sponsorFreeShare;

  String get sponsorFooter;

  String get sponsorBuyDrink;

  String get sponsorSupportKicker;

  String get sponsorNote;

  String get sponsorAlipay;

  String get sponsorWechat;

  String get sponsorNickname;

  String get sponsorScan;

  String sponsorQrCode(String label);

  String get sponsorClose;

  String get sponsorNoteShort;

  String aboutQqCopied(String number);

  String get disclaimerTitle;

  String get disclaimerTerms;

  String get disclaimerSource;

  String get ipQualityRedetect;

  String get ipQualityEgress;

  String get ipQualitySources;

  String get ipQualitySourcesFooter;

  String get ipQualityQuerying;

  String get ipQualityChecking;

  String get ipQualityDetecting;

  String get ipQualityFailed;

  String get ipQualityNotYet;

  String get ipQualityDetectingBody;

  String get ipQualityStartBody;

  String get ipQualityStart;

  String ipQualityJudgedAs(String type);

  String get ipQualityNotUsed;

  String get ipQualityUsed;

  String devFooterWarning(int count);

  String get devDataCleanupBody;

  String get devConfigSection;

  String get devCustomResources;

  String get devCustomResourcesBody;

  String get devUserAgentBody;

  String get devOnDemand;

  String get devOnDemandBody;

  String get devWebdav;

  String get devWebdavBody;

  String get devUiSection;

  String get devFontFamilyBody;

  String get devFontSizeBody;

  String get devTabAnimation;

  String get devTabAnimationBody;

  String get devExperimental;

  String get devLegacyFooter;

  String get unknownRouteTitle;

  String get unknownRouteBody;

  String get unknownRouteBack;

  String get disclaimerReadFirst;

  String get disclaimerIntro;

  String get disclaimerLawful;

  String get disclaimerFirstRun;

  String get disclaimerImmutable;

  String get devFontFamily;

  String get devFontSize;

  String get devWarningTitle;

  String get devFooterLegacy;

  String get devFooterMoved;

  String get ipTypeResidential;

  String get ipTypeMobile;

  String get ipTypeBusiness;

  String get ipTypeHosting;

  String get ipLevelGood;

  String get ipLevelNormal;

  String get ipLevelRisky;

  String get ipStatusOk;

  String get ipStatusNoType;

  String get ipStatusTimeout;

  String get ipStatusRateLimited;

  String get ipStatusMismatch;

  String get modeSelectTitle;

  String get modeContinue;

  String get modeSwitchNote;

  String get modeSharedNote;

  String get modeNormalFeature1;

  String get modeNormalFeature1Body;

  String get modeNormalFeature2;

  String get modeNormalFeature2Body;

  String get modeNormalFeature3;

  String get modeNormalFeature3Body;

  String get modeNormalFeature4;

  String get modeNormalFeature4Body;

  String get modeExpressFeature1;

  String get modeExpressFeature1Body;

  String get modeExpressFeature2;

  String get modeExpressFeature2Body;

  String get modeExpressFeature3;

  String get modeExpressFeature3Body;

  String get modeExpressFeature4;

  String get modeExpressFeature4Body;

  String get onboardingTitle;

  String get onboardingSkip;

  String get onboardingPrev;

  String get onboardingStart;

  String get onboardingNext;

  String onboardingChosen(String mode);

  String get onboardingChangeable;

  String get onboardingChangeableBody;

  String get onboardingSharedRules;

  String get onboardingSharedRulesBody;

  String get onboardingExclusive;

  String get onboardingExclusiveBody;

  String get permVpn;

  String get permNotification;

  String get permAppList;

  String get permBattery;

  String get permRequired;

  String get permOptional;

  String get permVpnNormalBody;

  String get permNotificationBody;

  String get permAppListBody;

  String get permBatteryBody;

  String get permVpnExpressBody;

  String get permNeeded;

  String get permAllLocal;

  String permGrantedCount(String granted, String total);

  String get onboardingTipNormal1;

  String get onboardingTipNormal2;

  String get onboardingTipNormal3;

  String get onboardingTipExpress1;

  String get onboardingTipExpress2;

  String get onboardingTipExpress3;

  String get onboardingReady;

  String get onboardingReadyBody;

  String onboardingTipIndex(String index);

  String permStillDenied(String name);

  String get permGranted;

  String get permDenied;

  String get permUnknown;

  String get permGrant;

  String get toolSpeedTest;

  String get toolPing;

  String get toolDnsLookup;

  String get toolTraceroute;

  String get toolSpeedTestDesc;

  String get toolPingDesc;

  String get toolDnsLookupDesc;

  String get toolTracerouteDesc;

  String get toolDiagnostics;

  String get toolToolsSection;

  String get toolOverviewTitle;

  String get toolNotRunTitle;

  String get toolSpeedEmptyTitle;

  String get toolPingEmpty;

  String get toolDnsEmpty;

  String get toolTraceEmpty;

  String get toolPingResults;

  String get toolPingReplies;

  String get toolDnsResults;

  String get toolDnsAnswers;

  String get toolTraceResults;

  String get toolTraceHops;

  String get toolRefreshInfo;

  String get toolActiveInterface;

  String get toolLocalAddress;

  String get toolDnsServers;

  String get toolCountUnit;

  String toolPrivateDnsProbe(String dns);

  String get toolPhysicalProbe;

  String get toolInputHostOrIp;

  String get toolPingCount4;

  String get toolPingCount10;

  String get toolPingOptions;

  String get toolViaTunnel;

  String get toolViaTunnelPingBody;

  String get toolStartPing;

  String get toolPinging;

  String get toolTcpFallback;

  String get toolPingFailed;

  String get toolTarget;

  String get toolResolvedAddress;

  String get toolAddressFamily;

  String get toolSentReceived;

  String get toolPacketLoss;

  String get toolMinAvgMax;

  String get toolJitter;

  String get toolJitterFooter;

  String toolPacketN(String n);

  String get toolTimeout;

  String toolPingSummary(String failed, String sent);

  String get toolPingFooter;

  String get toolDnsSystem;

  String get toolDnsCustom;

  String get toolCustomDnsError;

  String get toolInputDomain;

  String get toolCustomDnsHint;

  String get toolQueryOptions;

  String get toolViaTunnelDnsBody;

  String get toolStartQuery;

  String get toolQuerying;

  String get toolQueryDomain;

  String get toolRecordType;

  String get toolAnswerSource;

  String get toolElapsed;

  String get toolAnswerCount;

  String get toolDnsBlockedBody;

  String get toolDnsNoAnswers;

  String get toolDnsFooter;

  String get toolTunnelEngine;

  String get toolSpeedChecking;

  String get toolSpeedUnsupported;

  String get toolSpeedDomainHint;

  String get toolSpeedProviders;

  String toolNoProviders(String protocol);

  String get toolNoProvidersBody;

  String get toolSpeedSelectionNote;

  String get toolTestQueryTime;

  String get toolSpeedRunning;

  String get toolSpeedEmpty;

  String get toolSpeedResults;

  String toolSpeedResultsFooter(String domain);

  String get toolSpeedFooter;

  String get toolFastest;

  String toolSampleCount(String count, String rate);

  String toolAllFailed(String count);

  String get toolTraceOptions;

  String get toolStartTrace;

  String get toolTracing;

  String get toolTraceFailed;

  String get toolTraceCancelled;

  String get toolHopCount;

  String toolHopCountValue(String count, String max);

  String get toolNoResponse;

  String get toolTraceFooter;

  String get toolTraceHops15;

  String get toolTraceHops30;

  String get uaDeleteTitle;

  String get uaDeleteBody;

  String get uaAdd;

  String get uaEdit;

  String get uaNote;

  String get uaCurrent;

  String get uaAll;

  String get uaNoOverride;

  String get uaNoOverrideBody;

  String get uaBuiltin;

  String get uaCustom;

  String get uaBuiltinNote;

  String get uaHint;

  String get uaNameLabel;

  String get uaNameHint;

  String get uaEmptyError;

  String get uaDuplicateError;

  String get ssidInvalid;

  String get ssidAdd;

  String get ssidEdit;

  String get ssidSave;

  String get ssidHint;

  String get ssidExample;

  String get ssidEmptyError;

  String get ssidConnection;

  String get ssidCellular;

  String get ssidCellularBody;

  String get ssidWifiBody;

  String get ssidBothOff;

  String get ssidDelay;

  String get ssidStartDelay;

  String get ssidStartDelayBody;

  String get ssidImmediate;

  String get odTitle;

  String get odApplyNow;

  String get odEnable;

  String get odEnableBody;

  String get odDisableBody;

  String get odNote;

  String get odAllowlist;

  String get odNoSsid;

  String get odNoSsidBody;

  String get odDelayNote;

  String get odCellular;

  String get odKindsNone;

  String odDelayValue(String ms);

  String get odStateDisabled;

  String get odStateUnknown;

  String get odStateNoWifi;

  String odStateMatched(String ssid);

  String get odStateUnmatched;

  String get odDisabledHint;

  String get odPillDisabled;

  String get odPillUnknown;

  String get odPillNoWifi;

  String get odPillWillStart;

  String get odPillWillNotStart;

  String get odDecision;

  String get odDecisionFooter;

  String get odCurrentNetwork;

  String get odWifiName;

  String get odReadAgain;

  String get odPermission;

  String get odPermissionBody;

  String get odNotGranted;

  String get odWifiUnreadable;

  String get odSsidPrivacy;

  String get odBatteryJoined;

  String get odBatteryNotJoined;

  String get odBatteryUnavailable;

  String get odPrerequisites;

  String get odIgnoreBattery;

  String get odBatteryOk;

  String get odBatteryAsk;

  String get odBatteryNoChannel;

  String get odBatteryFooter;

  String get odBatteryJoinedHint;

  String get odBatteryStillOff;

  String get odBatteryUnsupportedHint;

  String get odCapNoPermission;

  String odCapCurrent(String name);

  String get customResourcesTitle;

  String get configDelete;

  String get configCancel;

  String get configNotSet;

  String configItemCount(int count);

  String odEditSsidTooltip(String ssid);

  String odDeleteSsidTooltip(String ssid);

  String get troubleshootTitle;

  String get troubleshootRuntimeLogs;

  String get troubleshootRecordLogs;

  String get troubleshootExportLogs;

  String get troubleshootClearLogs;

  String get troubleshootClearLogsBody;

  String get troubleshootRecordNote;

  String get troubleshootLocalDb;

  String get troubleshootWriteStatus;

  String get troubleshootWriteStatusNote;

  String get troubleshootCrashLogs;

  String get troubleshootExportCrashes;

  String get troubleshootClearCrashes;

  String get troubleshootClearCrashesBody;

  String get troubleshootCrashNote;

  String get troubleshootCaptureWarning;

  String get troubleshootReadingStatus;

  String troubleshootRecording(String size);

  String troubleshootStoppedWithLogs(String size);

  String get troubleshootStoppedNoLogs;

  String get troubleshootReadingLogs;

  String get troubleshootNoLogs;

  String troubleshootLogCount(int count, String size);

  String get troubleshootReadingHealth;

  String get troubleshootHealthy;

  String troubleshootHealthyDetail(String detail, String mode);

  String troubleshootDropped(
    int dropped,
    String failed,
    int reason,
    String split,
  );

  String get troubleshootOverflow;

  String get troubleshootTableMissing;

  String get troubleshootNoDatabase;

  String get troubleshootClosed;

  String get troubleshootReadingCrashes;

  String get troubleshootNoCrashes;

  String troubleshootCrashCount(int count);

  String get troubleshootStoppedToast;

  String get troubleshootStartTitle;

  String get troubleshootCancel;

  String get troubleshootConfirmStart;

  String get troubleshootStartBody;

  String get troubleshootStartedToast;

  String get troubleshootStartFailedToast;

  String get troubleshootNoExportableLogs;

  String get troubleshootExportFailed;

  String troubleshootExported(String path);

  String get troubleshootConfirm;

  String get troubleshootClearLogsConfirm;

  String troubleshootClearedLogs(String count);

  String get troubleshootNoClearableLogs;

  String get troubleshootNoExportableCrashes;

  String get troubleshootClearCrashesConfirm;

  String troubleshootClearedCrashes(String count);

  String get troubleshootNoClearableCrashes;

  String get bypassAddTitle;

  String get bypassAdd;

  String get bypassSuffix;

  String get bypassSuffixBody;

  String get mirrorGlobal;

  String get mirrorDefault;

  String get mirrorNeedTemplate;

  String get mirrorTemplateNote;

  String get mirrorTemplate;

  String get mirrorNote;

  String get hiddenFeaturesTitle;

  String get hiddenFeaturesReset;

  String get hiddenFeaturesNote;

  String get hiddenFeaturesFooter;

  String get cacheSettingsTitle;

  String get cacheSection;

  String get cacheLocalDns;

  String get cacheOffNote;

  String get cachePresetSection;

  String get cachePresetNote;

  String get cacheCustomScaleLabel;

  String get cacheCustomScaleHint;

  String get recognitionSponsorTitle;

  String get recognitionSponsorIntro;

  String get recognitionSponsorSection;

  String get providerVisibilityTitle;

  String get providerVisibilityNote;

  String providerVisibilityProtocol(String protocol);

  String providerVisibilityAll(String protocol);

  String get providerVisibilityNone;

  String get providerVisibilityAllOn;

  String providerVisibilityCount(String count);

  String get markdownCopyCode;

  String get markdownCodeCopied;

  String get recognitionUpdated;

  String get recognitionRefresh;

  String get recognitionSortAsc;

  String get recognitionSortDesc;

  String get recognitionEmpty;

  String get recognitionLoadFailed;

  String get recognitionEmptyBody;

  String get recognitionLoad;

  String get recognitionRetry;

  String get recognitionNoMembers;

  String get recognitionNoMembersBody;

  String get recognitionRefreshShort;

  String get recognitionCached;

  String recognitionLastUpdate(String time);

  String get recognitionCloudNote;

  String appRulesAllowCount(String count, int package);

  String get appRulesConfigured;

  String get appRulesSystem;

  String get appRulesIncludeSub;

  String get appRulesDelete;

  String get appRulesAddDomainTitle;

  String get appRulesCancel;

  String get appRulesAdd;

  String get appRulesDomain;

  String get appRulesDomainHint;

  String get appRulesAllowlistRow;

  String get appRulesBlocklistRow;

  String get appRulesImportant;

  String get appRulesDisable;

  String get appRulesEnable;

  String get appRulesAddRuleTitle;

  String get appRulesRuleDomainHint;

  String get appRulesBlocklist;

  String get appRulesAllowlist;

  String get logRetentionTitle;

  String get logRetentionDnsLogs;

  String get logRetentionOffNote;

  String get logRetentionOverlay;

  String get logRetentionOverlayLogs;

  String get logRetentionOverlayBody;

  String get logRetentionOverlayNote;

  String get logRetentionCleanup;

  String logRetentionKeepDays(String days);

  String get logRetentionCleanupNote;

  String get appBlockTitle;

  String get appBlockInfo;

  String get appBlockToggle;

  String get appBlockToggleEmpty;

  String get appBlockSelection;

  String get appExcludeTitle;

  String get appExcludeInfo;

  String get appExcludeSelection;

  String get appSelectionSaved;

  String get appSelectionSaveTitle;

  String appSelectionSaveBody(String title);

  String get appSelectionSwitch;

  String get appSelectionNoAppsYet;

  String appSelectionCount(String count);

  String get appSelectionNoAppsAvailable;

  String get appSelectionNoMatch;

  String get appSelectionSave;

  String get appSelectionNothingRead;

  String get appSelectionExclusiveNote;

  String get bootstrapTitle;

  String get bootstrapAdd;

  String get bootstrapGlobal;

  String get bootstrapEnable;

  String get bootstrapEnableBody;

  String get bootstrapEnableNote;

  String get bootstrapBuiltin;

  String get bootstrapCustom;

  String get bootstrapNoCustom;

  String bootstrapNoSample(String ip);

  String bootstrapAverage(String ms);

  String bootstrapFailures(String count);

  String bootstrapStats(
    String failures,
    String ip,
    String latency,
    String samples,
    String success,
  );

  String get bootstrapInvalidIp;

  String get bootstrapNameOptional;

  String get bootstrapIpAddress;

  String get caCertTitle;

  String get caCertStatusMissing;

  String get caCertStatusUntrusted;

  String get caCertStatusTrusted;

  String get caCertSectionStatus;

  String get caCertRootStatus;

  String get caCertVerified;

  String get caCertUnverified;

  String get caCertReadFailed;

  String get caCertStatusFooter;

  String get caCertSectionActions;

  String get caCertGuide;

  String get caCertGuideSubtitle;

  String get caCertInstall;

  String get caCertInstallSubtitle;

  String get caCertInstalled;

  String get caCertNotInstalled;

  String get caCertSaveToDownloads;

  String get caCertSaveToDownloadsSubtitle;

  String get caCertFingerprint;

  String get caCertNoFingerprint;

  String get caCertFingerprintSubtitle;

  String get caCertViewPem;

  String get caCertViewPemSubtitle;

  String get caCertSectionManage;

  String get caCertRegenerate;

  String get caCertRegenerateSubtitle;

  String get caCertNoCertificate;

  String get caCertInstallDialogBody;

  String caCertSavedTo(String name);

  String get caCertDownloadsDir;

  String caCertSaveFailed(String error);

  String get caCertOpenedInstaller;

  String get caCertOpenedSettings;

  String get caCertInstallerUnavailable;

  String get caCertManualHint;

  String caCertSavedHint(String name);

  String get caCertDownloadsFailed;

  String get caCertRegenerateTitle;

  String get caCertRegenerateBody;

  String get caCertRegenerateAction;

  String caCertGenerateFailed(String error);

  String get caCertGenerated;

  String get caCertFingerprintTitle;

  String get caCertFingerprintCopied;

  String get caCertPemTitle;

  String get caCertPemCopied;

  String get caCertGuideTitle;

  String get caCertWhyTitle;

  String get caCertWhyBody;

  String get caCertStepsTitle;

  String get caCertStep1;

  String get caCertStep2;

  String get caCertStep3;

  String get caCertStep4;

  String get caCertWhichAppsTitle;

  String get caCertWhichAppsBody;

  String get caCertWhichAppsWarning;

  String get caCertRiskTitle;

  String get caCertRiskWarning;

  String get caCertRiskPinning;

  String get commonCopy;

  String get commonContinue;

  String get commonUnknownReason;

  String get autoUpdateTitle;

  String get autoUpdateSection;

  String get autoUpdateRulesSwitch;

  String get autoUpdateRulesSwitchSubtitle;

  String get autoUpdateIntervalSection;

  String autoUpdateEveryHours(int hours);

  String get autoUpdateCustomInterval;

  String get autoUpdateCustomHint;

  String get autoUpdateTimedSection;

  String autoUpdateDailyAt(String time);

  String autoUpdateEveryOtherDayAt(String time);

  String get autoUpdateTimedPickHint;

  String get autoUpdateTimedChangeHint;

  String get autoUpdateIntervalFooter;

  String get autoUpdateStatusSection;

  String get autoUpdateNext;

  String get autoUpdateLast;

  String get autoUpdateNoRunYet;

  String autoUpdateRunCount(int count);

  String get autoUpdateStatusFooter;

  String get autoUpdateGroupsSection;

  String get autoUpdateReadingGroups;

  String get autoUpdateNoGroups;

  String get autoUpdateNoGroupsSubtitle;

  String get autoUpdateGroupsFooter;

  String get autoUpdateReadingSubs;

  String get autoUpdateNoCandidates;

  String get autoUpdateDueNow;

  String autoUpdateRemainingHours(int hours, int minutes);

  String autoUpdateRemainingMinutes(int minutes);

  String autoUpdateNextAt(String moment, String left);

  String autoUpdateMoment(int month, int day, String time);

  String get autoUpdateIntervalLabel;

  String get autoUpdateIntervalHelper;

  String get mirrorTplTitle;

  String get mirrorTplAdd;

  String get mirrorTplIntro;

  String get mirrorTplActions;

  String get mirrorTplFormatExample;

  String get mirrorTplFormatExampleSubtitle;

  String get mirrorTplSaved;

  String get mirrorTplReadFailed;

  String get mirrorTplReadFailedSubtitle;

  String mirrorTplSavedCount(int count);

  String get mirrorTplReading;

  String get mirrorTplEmpty;

  String get mirrorTplDuplicate;

  String get mirrorTplDuplicateSave;

  String get mirrorTplFormatTitle;

  String get mirrorTplFormatIntro;

  String mirrorTplFormatUrl(String token);

  String mirrorTplFormatScheme(String token);

  String mirrorTplFormatUrlEncoded(String token);

  String mirrorTplFormatHost(String token);

  String mirrorTplFormatPath(String token);

  String mirrorTplFormatPathAndQuery(String token);

  String mirrorTplFormatSample(String token);

  String mirrorTplFormatPlaceholders(
    String url,
    String scheme,
    String urlEncoded,
    String host,
    String path,
    String pathAndQuery,
  );

  String get mirrorTplNameLabel;

  String get mirrorTplNameHint;

  String get mirrorTplAddressLabel;

  String get mirrorTplInvalid;

  String get mirrorTplAddTitle;

  String get mirrorTplEditTitle;

  String get commonEdit;

  String get ruleControlUrlNotReadyCa;

  String get ruleControlUrlNotReadyInspection;

  String get ruleControlUrlNotReadyApps;

  String get ruleControlUrlPaused;

  String get ruleControlUrlRunning;

  String get ruleControlIntro;

  String get ruleControlIntroLimited;

  String get ruleControlFilterSection;

  String get ruleControlDomainRules;

  String get ruleControlDomainRulesOn;

  String get ruleControlDomainRulesOff;

  String get ruleControlUrlRules;

  String get ruleControlNotReady;

  String get ruleControlPolicySection;

  String get ruleControlDiagnosticsSection;

  String get ruleControlControlSection;

  String get ruleControlDomainSection;

  String get ruleControlBlockResponse;

  String ruleControlDynamicSummary(String mode);

  String get ruleControlNetworkPrivacySection;

  String get ruleControlInterfacesSection;

  String get ruleControlSubsSection;

  String get ruleControlSubsSubtitle;

  String ruleControlCount(int count);

  String ruleControlAutoUpdateOn(int hours);

  String ruleControlAutoUpdateDaily(String time);

  String ruleControlAutoUpdateEveryOtherDay(String time);

  String get ruleControlAutoUpdateOff;

  String get ruleControlMirrorSubtitle;

  String get blockResponseFixedSection;

  String get blockResponseFixedFooter;

  String get blockResponseDynamicSection;

  String get blockResponseEnableDynamic;

  String get blockResponseEnableDynamicSubtitle;

  String get blockResponseParameters;

  String blockResponseParamsSummary(int threshold, int window, int duration);

  String get blockResponseDynamicFooter;

  String get blockResponseThresholdError;

  String get blockResponseWindowError;

  String get blockResponseDurationError;

  String get blockResponseThresholdLabel;

  String get blockResponseThresholdHelper;

  String get blockResponseWindowLabel;

  String get blockResponseWindowHelper;

  String get blockResponseDurationLabel;

  String get blockResponseDurationHelper;

  String get httpInspCheckingCa;

  String get httpInspNoAppsHint;

  String httpInspSelectedHint(int count);

  String get httpInspScopeSection;

  String get httpInspEnable;

  String get httpInspTargetApps;

  String get httpInspNoApps;

  String httpInspSelectedApps(int count);

  String get httpInspCaCert;

  String get httpInspCaReady;

  String get httpInspContentSection;

  String get httpInspUrlRules;

  String get httpInspNeedEnable;

  String get httpInspUrlPaused;

  String get httpInspUrlOn;

  String get httpInspProtocolSection;

  String get httpInspBlockHttp3;

  String get httpInspBlockHttp3Subtitle;

  String get httpInspBlockDot;

  String get httpInspBlockDotSubtitle;

  String get httpInspRequestLogs;

  String get httpInspRequestLogsSubtitle;

  String get httpInspBypassFooter;

  String httpInspBypassTitle(int count);

  String get httpInspBypassEmpty;

  String get httpInspBypassEmptySubtitle;

  String get httpInspBypassRowSubtitle;

  String get httpInspCaRequiredTitle;

  String get httpInspGoInstall;

  String get httpInspCaReadingBody;

  String httpInspCaRequiredBody(String problem);

  String get httpInspCaMissing;

  String get httpInspCaNotInstalled;

  String get httpInspCaReadyShort;

  String get httpInspNeedDomainRulesTitle;

  String get httpInspEnableAll;

  String get httpInspNeedDomainRulesBody;

  String get httpInspAppsTitle;

  String get httpInspSelectVisible;

  String get httpInspDeselectVisible;

  String get httpInspAppsIntro;

  String httpInspAppsCount(int selected, int visible);

  String get commonLater;

  String get ruleControlSubsTitle;

  String get cleanupIntro;

  String cleanupRunning(String title);

  String get cleanupCategorySection;

  String get cleanupCategoryItemsSection;

  String cleanupCategoryItemsCount(int count);

  String get cleanupDangerSection;

  String get cleanupDescLogs;

  String get cleanupDescTraffic;

  String get cleanupDescCrash;

  String get cleanupDescDnsCache;

  String get cleanupDescProviderWeights;

  String get cleanupDescBootstrapWeights;

  String get cleanupDescDomainRules;

  String get cleanupDescAddressRules;

  String get cleanupDescSubscriptions;

  String get cleanupDescAppRules;

  String get cleanupDescOutboundProxy;

  String get cleanupDescCaCertificate;

  String get cleanupDescDownloadCache;

  String get cleanupDescCustomBackground;

  String get cleanupDescRuntimeLogs;

  String get cleanupDescAutomationEvents;

  String get cleanupDescRuleVersions;

  String get cleanupDescMirrorTemplates;

  String get cleanupDescRecognitionMembers;

  String get cleanupDescSettingsGuides;

  String get cleanupDescAllData;

  String get cleanupConfirmLogs;

  String get cleanupConfirmTraffic;

  String get cleanupConfirmCrash;

  String get cleanupConfirmDnsCache;

  String get cleanupConfirmProviderWeights;

  String get cleanupConfirmBootstrapWeights;

  String get cleanupConfirmDomainRules;

  String get cleanupConfirmAddressRules;

  String get cleanupConfirmSubscriptions;

  String get cleanupConfirmAppRules;

  String get cleanupConfirmOutboundProxy;

  String get cleanupConfirmCaCertificate;

  String get cleanupConfirmDownloadCache;

  String get cleanupConfirmCustomBackground;

  String get cleanupConfirmRuntimeLogs;

  String get cleanupConfirmAutomationEvents;

  String get cleanupConfirmRuleVersions;

  String get cleanupConfirmMirrorTemplates;

  String get cleanupConfirmRecognitionMembers;

  String get cleanupConfirmSettingsGuides;

  String get cleanupConfirmAllData;

  String get cleanupRestartTitle;

  String get cleanupRestartBody;

  String get commonConfirm;

  String get transferTitle;

  String get transferMetricProviders;

  String get transferMetricSubs;

  String get transferMetricCustomRules;

  String get transferMetricListedApps;

  String get transferSectionAppConfig;

  String get transferSectionRules;

  String get transferSectionAppControl;

  String get transferSectionPersonal;

  String get transferDeselectAll;

  String get transferImportExportSection;

  String get transferExportJson;

  String get transferExportHintNone;

  String transferExportHintCount(int count);

  String get transferImportJson;

  String get transferImportSubtitle;

  String get transferImportExportFooter;

  String get transferCloudSection;

  String get transferWebdav;

  String get transferWebdavSubtitle;

  String get transferBusyExporting;

  String get transferBusySaving;

  String get transferBusyPickingImport;

  String get transferExportEmpty;

  String get transferExportCancelled;

  String transferExportDone(int groups, int items);

  String transferExportSkipped(int count);

  String get transferExportFailed;

  String get transferImportCancelled;

  String get transferImportTitle;

  String get transferImportFailedChip;

  String get transferImportDoneChip;

  String transferImportSummary(int added, int updated, int skipped);

  String transferSourceFile(String name);

  String transferExportedAt(String time);

  String transferOutcomeRow(String group, String detail);

  String transferFailedGroupRow(String group, String error);

  String get transferNothingChanged;

  String transferSubscriptionsNote(int count);

  String get transferDone;

  String transferOutcomeAdded(int count);

  String transferOutcomeUpdated(int count);

  String transferOutcomeSkipped(int count);

  String get transferNoChange;

  String get transferOutcomeSeparator;

  String get webdavClearConfig;

  String get webdavTest;

  String get webdavServer;

  String get webdavUsername;

  String get webdavPassword;

  String get webdavPath;

  String get webdavUpload;

  String get webdavDownload;

  String webdavFooter(String hint);

  String get webdavFooterConnected;

  String get webdavNoConfig;

  String get webdavUploadFailed;

  String get webdavNoCloudBackup;

  String get webdavRestoreTitle;

  String get webdavRestoreFailed;

  String get webdavRestoreDone;

  String webdavRestoreSummary(int added, int updated, int skipped);

  String webdavOutcomeRow(String group, int added, int skipped);

  String get webdavNothingChanged;

  String get webdavHintIdle;

  String get webdavHintConnecting;

  String get webdavHintConnected;

  String get webdavHintFailed;

  String get backupGroupProviders;

  String get backupGroupProvidersDesc;

  String get backupGroupBootstrap;

  String get backupGroupBootstrapDesc;

  String get backupGroupCache;

  String get backupGroupCacheDesc;

  String get backupGroupOutbound;

  String get backupGroupOutboundDesc;

  String get backupGroupSubscriptions;

  String get backupGroupSubscriptionsDesc;

  String get backupGroupDomainRules;

  String get backupGroupDomainRulesDesc;

  String get backupGroupRewriteDomain;

  String get backupGroupRewriteDomainDesc;

  String get backupGroupRewriteCname;

  String get backupGroupRewriteCnameDesc;

  String get backupGroupAddressRules;

  String get backupGroupAddressRulesDesc;

  String get backupGroupExcluded;

  String get backupGroupExcludedDesc;

  String get backupGroupBlocked;

  String get backupGroupBlockedDesc;

  String get backupGroupAllowlist;

  String get backupGroupAllowlistDesc;

  String get backupGroupHttpInspection;

  String get backupGroupHttpInspectionDesc;

  String get backupGroupAppearance;

  String get backupGroupAppearanceDesc;

  String get backupGroupSystem;

  String get backupGroupSystemDesc;

  String webdavUploadedCount(int groups, int items);

  String get agentApiEnabled;

  String get agentApiDisabled;

  String get agentApiNoProvider;

  String agentApiCurrentProvider(String name, String model);

  String get agentApiNoModel;

  String get agentApiKeyConfigured;

  String agentApiTemperature(String value);

  String get agentApiProviderChip;

  String get agentApiReadyHintOn;

  String get agentApiReadyHintOff;

  String get agentApiSectionProvider;

  String agentApiProvidersSubtitle(int count);

  String get agentParamsSubtitle;

  String get agentApiSectionTest;

  String get agentApiTestDomain;

  String get agentApiTestDomainSubtitle;

  String get agentApiTestTraffic;

  String get agentApiTestTrafficSubtitle;

  String get agentApiTestFooterReady;

  String get agentApiTestFooterNotReady;

  String get agentApiSectionEntries;

  String get agentApiCacheTable;

  String get agentApiCacheTableSubtitle;

  String get agentApiRequests;

  String get agentApiRequestsSubtitle;

  String get agentApiDashboard;

  String get agentApiDashboardSubtitle;

  String get agentApiEntriesFooter;

  String get agentApiSectionReset;

  String get agentApiResetItem;

  String get agentApiResetSubtitle;

  String get agentApiFooter;

  String get agentApiResetTitle;

  String get agentApiResetBody;

  String get agentApiResetConfirm;

  String get agentProvidersTitle;

  String get agentProvidersAdd;

  String get agentProvidersIntro;

  String get agentProvidersMine;

  String get agentProvidersEmpty;

  String get agentProvidersEmptySubtitle;

  String agentProvidersRow(String model, String baseUrl, String key);

  String get agentProvidersKeyConfigured;

  String get agentProvidersKeyMissing;

  String get agentProvidersFooter;

  String get agentProvidersAdded;

  String get agentProvidersDeleteTitle;

  String agentProvidersDeleteBody(String name);

  String get agentEditorAddTitle;

  String get agentEditorEditTitle;

  String get agentEditorPaste;

  String get agentEditorName;

  String get agentEditorBaseUrl;

  String get agentEditorModel;

  String get agentEditorModelHint;

  String get agentEditorKeyKeep;

  String get agentEditorKeyLocal;

  String get agentEditorFetching;

  String get agentEditorFetch;

  String get agentEditorTest;

  String get agentEditorErrorRequired;

  String get agentEditorErrorBaseUrl;

  String get agentEditorErrorTestNeeds;

  String agentEditorFetched(int count);

  String agentEditorFetchFailed(String error);

  String agentEditorConnected(String model);

  String agentEditorUsage(int tokens);

  String agentEditorConnectFailed(String error);

  String get agentParamsTitle;

  String get agentParamsPromptSection;

  String get agentParamsPromptItem;

  String get agentParamsPromptUnset;

  String get agentParamsPromptFooter;

  String get agentParamsPromptHint;

  String get agentParamsTemperatureSection;

  String get agentParamsTemperatureItem;

  String get agentParamsTemperatureFooter;

  String get agentParamsTemperatureStrict;

  String get agentParamsTemperatureBalanced;

  String get agentParamsTemperatureWild;

  String get agentParamsTemplateSecurity;

  String get agentParamsTemplateTechnical;

  String get agentParamsTemplatePrivacy;

  String get agentSheetCopied;

  String agentSheetRuleAdded(String kind);

  String agentSheetRuleExists(String kind);

  String get agentSheetFooter;

  String get agentSheetDisabledTitle;

  String get agentSheetDisabledBody;

  String get agentSheetEnableAndStart;

  String get agentSheetNoKeyTitle;

  String get agentSheetNoKeyBody;

  String get agentSheetGoConfigure;

  String get agentSheetRunning;

  String agentSheetModel(String model);

  String get agentSheetUnknown;

  String get agentSheetFailed;

  String get agentSheetUnknownError;

  String get agentSheetCheckSettings;

  String get agentSheetNotStarted;

  String get agentSheetSuperseded;

  String get agentSheetStartHint;

  String get agentSheetSupersededHint;

  String get agentSheetStart;

  String get agentSheetHideDigest;

  String get agentSheetShowDigest;

  String get agentSheetAddBlock;

  String get agentSheetCopyResult;

  String get agentSheetReanalyze;

  String get agentTargetDomainTitle;

  String get agentTargetTrafficTitle;

  String get agentTargetTrafficSubtitle;

  String get agentApiChipKeyMissing;

  String get agentSheetAddAllowlist;

  String get featureHubLongPress;

  String get outboundSaved;

  String outboundSaveFailed(String error);

  String get outboundResetTitle;

  String get outboundResetBody;

  String get outboundResetDone;

  String get outboundResetMenu;

  String get outboundSectionProxy;

  String get outboundProxyServerSection;

  String get outboundEnable;

  String get outboundApp;

  String get outboundHostLabel;

  String get outboundHostHelper;

  String get outboundUsernameLabel;

  String get outboundPasswordLabel;

  String get outboundHttpFooter;

  String get outboundSocksFooter;

  String get outboundStatusOff;

  String get outboundStatusConnecting;

  String get outboundStatusReady;

  String get outboundStatusFailed;

  String get outboundFooterError;

  String get outboundFooterReady;

  String get outboundFooterConnecting;

  String get outboundAppsTitle;

  String get outboundAppsIntro;

  String outboundAppsCount(int count);

  String get outboundAppsEmpty;

  String get resolutionSingleDesc;

  String get resolutionSmartDesc;

  String get resolutionParallelDesc;

  String get resolutionPrimaryBackupDesc;

  String resolutionProtocolSavedError(String error);

  String get resolutionBuiltinProtocol;

  String get resolutionBuiltinNote;

  String get resolutionCurrentSection;

  String get resolutionBuiltinSection;

  String get resolutionConfigSection;

  String get resolutionConfigFooter;

  String get resolutionNotConfigured;

  String resolutionProviderCount(int count);

  String get resolutionPickerTitle;

  String get resolutionMinProviders;

  String get resolutionSingleHint;

  String resolutionRaceHint(int count);

  String get resolutionReady;

  String get resolutionPending;

  String get resolutionSectionSingle;

  String get resolutionSectionSmart;

  String get resolutionSectionParallel;

  String get resolutionSectionBackup;

  String get resolutionNoProviders;

  String get resolutionMoveUp;

  String get resolutionMoveDown;

  String get outboundNoApp;

  String get appRulesSaved;

  String get appRulesClearAllTooltip;

  String get appRulesMasterSection;

  String get appRulesMasterToggle;

  String get appRulesNoConfigured;

  String appRulesConfiguredSummary(int apps, int domains);

  String get appRulesMasterFooter;

  String appRulesAppsCount(int count);

  String get appRulesNoConfigurableApps;

  String get appRulesFooterNoApps;

  String get appRulesFooterSave;

  String get appRulesAddAllowDomain;

  String get appRulesAppSection;

  String get appRulesBackToList;

  String get appRulesClearAllTitle;

  String get appRulesClearAllBody;

  String get appRulesRuleExists;

  String appRulesRuleAdded(String kind);

  String get appRulesDeleteRuleTitle;

  String get appRulesFullBlockOn;

  String get appRulesFullBlockOff;

  String get appRulesAddDnsRule;

  String get appRulesDnsScopeIntro;

  String get appRulesDnsScopeSection;

  String get appRulesReadingRules;

  String get appRulesWait;

  String get appRulesRuleDbUnreadable;

  String get appRulesRuleDbUnavailable;

  String get appRulesNoScopedRules;

  String get appRulesNoScopedRulesSubtitle;

  String appRulesScopedCount(int count);

  String appRulesAllowDomainTitle(int count);

  String get appRulesNoAllowDomains;

  String get appRulesNoAllowDomainsSubtitle;

  String get appRulesAllowDomainFooter;

  String get appRulesIsolationSection;

  String get appRulesFullBlockToggle;

  String get appRulesFullBlockToggleSubtitle;

  String get appRulesFullBlockOnTitle;

  String get appRulesFullBlockOnBody;

  String get providerMgmtDeleteTitle;

  String providerMgmtDeleteBody(String name);

  String get providerMgmtTitle;

  String get providerMgmtAdd;

  String get providerMgmtCurrent;

  String get providerMgmtBuiltin;

  String get providerMgmtCustom;

  String get providerMgmtEmptyCustom;

  String get providerMgmtEmptyCustomSubtitle;

  String get providerMgmtFooter;

  String get providerMgmtEditTitle;

  String get providerMgmtAddressLabel;

  String get providerMgmtPortLabel;

  String get providerMgmtDohAddressLabel;

  String get providerMgmtNameRequired;

  String get providerMgmtDohRequired;

  String get providerMgmtAddressRequired;

  String get providerMgmtPortRange;

  String get providerMgmtProbeTooltip;

  String providerMgmtProbeOk(int ms);

  String providerMgmtProbeFailed(String message);

  String get providerMgmtProbeNoResponse;

  String get notifModeSingle;

  String get notifModeSmart;

  String get notifModeParallel;

  String get notifModeBackup;

  String notifRunningMode(String mode, int count);

  String notifRunningProvider(String name);

  String platformNoSaveDialog(String error);

  String platformNoFilePicker(String error);

  String get platformNoFilePickerShort;

  String get platformNoLocalRead;

  String platformReadFailed(String error);

  String get platformNoSystemPicker;

  String updateConnectFailed(String error);

  String get updateTlsFailed;

  String get updateBadJson;

  String get updateRateLimited;

  String get updateForbidden;

  String get updateNotFound;

  String updateServerError(int status);

  String updateUnexpectedStatus(int status);

  String get updateResponseNotJson;

  String get updateUnexpectedFormat;

  String get updateMissingTag;

  String get updateNoApk;

  String get updateBadDownloadUrl;

  String updateApkFileName(String version);

  String get agentApiEmptyEndpoint;

  String get agentApiNoModelListJson;

  String get agentApiNoModelListData;

  String get agentApiNoModels;

  String get agentApiKeyEmpty;

  String get agentApiKeyEmptyHint;

  String get agentApiResponseNotJsonObject;

  String get agentApiEmptyContent;

  String agentApiBadUrl(String url);

  String get agentApiCancelled;

  String get agentApiTimeout;

  String agentApiUnreachable(String error);

  String get agentApiTls;

  String get agentApiInvalidJson;

  String get agentApiBadKey;

  String get agentApiNoAccess;

  String get agentApiModelNotFound;

  String get agentApiRateLimited;

  String agentApiUnavailable(int status);

  String agentApiRequestFailed(int status);

  String agentApiServerDetail(String message);

  String get davProbeNoWrite;

  String davProbeConnect(String error);

  String get davProbeTls;

  String get davProbeHttp;

  String davUploadConnect(String error);

  String get davUploadTls;

  String davDownloadHttp(int status);

  String get davStatus401;

  String get davStatus403;

  String get davStatus404;

  String get davStatus405;

  String get davStatus409;

  String get davStatus507;

  String davStatus5xx(int status);

  String davStatusOther(int status);

  String get ipQualityNoExitIp;

  String get ipQualityNoSourceResult;

  String get disclaimerTerm1Title;

  String get disclaimerTerm1Content;

  String get disclaimerTerm2Title;

  String get disclaimerTerm2Content;

  String get disclaimerTerm3Title;

  String get disclaimerTerm3Content;

  String get disclaimerTerm4Title;

  String get disclaimerTerm4Content;

  String get disclaimerTerm5Title;

  String get disclaimerTerm5Content;

  String get disclaimerTerm6Title;

  String get disclaimerTerm6Content;

  String get disclaimerTerm7Title;

  String get disclaimerTerm7Content;

  String get disclaimerTerm8Title;

  String get disclaimerTerm8Content;

  String get disclaimerTerm9Title;

  String get disclaimerTerm9Content;

  String get disclaimerTerm10Title;

  String get disclaimerTerm10Content;

  String get settingsModeSubtitle;

  String get settingsLogModeSubtitle;

  String get settingsRunSection;

  String get settingsForegroundSubtitle;

  String get settingsAutoStartTitle;

  String get settingsAutoStartSubtitle;

  String get settingsVpnWatchdogTitle;

  String get settingsVpnWatchdogSubtitle;

  String get settingsSystemSection;

  String get settingsLanguageSubtitle;

  String get settingsWizardSubtitle;

  String get settingsGuideSection;

  String get backupErrEmpty;

  String backupErrInvalidJson(String error);

  String get backupErrRootNotObject;

  String get backupErrNotDiting;

  String get backupErrNoVersion;

  String backupErrVersionTooHigh(String version, int max);

  String get backupErrNoData;

  String get backupErrProvidersNotArray;

  String get backupErrBootstrapNotObject;

  String get backupErrCacheNotObject;

  String get backupErrOutboundNotObject;

  String get backupErrBlockedNotObject;

  String get backupErrAppRulesNotObject;

  String get backupErrInspectionNotObject;

  String get backupErrSubsNotObject;

  String get backupErrNoRuleDbSubs;

  String get backupErrRulesNotArray;

  String get backupErrNoRuleDbRules;

  String get backupErrRewriteNotArray;

  String get backupErrNoRuleDbRewrite;

  String get backupErrAddressNotArray;

  String get backupErrNoRuleDbAddress;

  String get agentPasteEmpty;

  String get agentPasteBoth;

  String get agentPasteBaseUrl;

  String get agentPasteKey;

  String get agentPasteJson;

  String logDirect(String protocol);

  String logDirectWithApp(String protocol, String app);

  String get subsErrUrlUnavailable;

  String subsErrTimeout(int seconds);

  String get subsErrTls;

  String get subsErrEmptyResponse;

  String get subsLargeConfirmTitle;

  String subsLargeConfirmMessage(String mb);

  String get subsLargeConfirmAction;

  String get subsErrUnreachable;

  String subsErrUnreachableCode(String code);

  String get subsErrUnsupported;

  String subsErrMirrorPlaceholder(String list);

  String get subsErrRawUrlInvalid;

  String get subsErrMirrorScheme;

  String get subsErrEmpty;

  String get subsErrBadFormat;

  String get subsErrNotHttp;

  String get subsErrNoHost;

  String get siteCategoryShopping;

  String get siteCategoryVideo;

  String get siteCategoryMusic;

  String get siteCategorySocial;

  String get siteCategoryDeveloper;

  String get siteCategoryGame;

  String get outboundProxyHostInvalid;

  String get outboundProxyPortRange;

  String get outboundProxyAppRequired;

  String get outboundProxySelfNotAllowed;

  String get outboundProxyAppMissing;

  String get outboundProxyCredentialsTooLong;

  String get updateDownloadNoPath;

  String get updateDownloadUnsupported;

  String updateDownloadFailedCode(String code);

  String dnsLatencySuccessRate(int success, int attempts);

  String get dnsLatencyUnsupported;

  String dnsLatencyChannelFailedCode(String code);

  String dnsLatencyChannelFailedDetail(String detail);

  String get fontImportFailed;

  String get fontReadFailed;

  String get fontParseFailed;

  String get fontCustomName;

  String get recognitionAvatarTooLarge;

  String get recognitionConfigTooLarge;

  String get taglineRunning;

  String get taglineStopped;

  String get backupErrProvidersInvalidJson;

  String get backupErrBootstrapInvalidJson;

  String get backupErrAppearanceNotObject;

  String get backupErrSystemNotObject;

  String get outboundScopeTitle;

  String get outboundScopeAll;

  String get outboundScopeApps;

  String get outboundScopeAllFooter;

  String get outboundScopeAppsFooter;

  String get outboundTargets;

  String get outboundTargetsTitle;

  String get outboundTargetsIntro;

  String get outboundProxyTargetsRequired;

  String get logDashboardCardHero;

  String get logDashboardCardTrafficStructure;

  String logDashboardEditHint(String mode);

  String get logDashboardModeFooter;

  String get logDashboardCardHeroDescription;

  String get logDashboardCardTrafficMonitorDescription;

  String get logDashboardCardRequestOverviewDescription;

  String get logDashboardCardHighlightDescription;

  String get logDashboardCardPrivacyDescription;

  String get logDashboardCardOffMetricDescription;

  String get logDashboardCardPerfDescription;

  String get logDashboardCardAiDescription;

  String get logDashboardCardTrafficStructureDescription;

  String get logDashboardCardRecentRequestsDescription;

  String get logDashboardCardRecentBlockedDescription;

  String get logDashboardCardCacheDescription;

  String get logDashboardCardRaceDescription;

  String get logDashboardCardBootstrapDescription;

  String get logDashboardCardRuleBlocksDescription;

  String get logStatsTitle;

  String get logStatsRequests;

  String get logStatsTotal;

  String get logStatsData;

  String get logStatsSaved;

  String get logStatsUploaded;

  String get logStatsDownloaded;

  String get logStatsWindow;

  String get logStatsRecentActivity;

  String get logDashboardCardStatsDescription;

  String get floatingLogOpen;

  String get floatingLogTitle;

  String get floatingLogPaused;

  String get floatingLogSearch;

  String get floatingLogSearchHint;

  String get floatingLogPause;

  String get floatingLogResume;

  String get floatingLogMinimize;

  String get floatingLogPanelSize;

  String get floatingLogSizeSmall;

  String get floatingLogSizeMedium;

  String get floatingLogSizeLarge;

  String get floatingLogClear;

  String get floatingLogOpenApp;

  String get floatingLogHide;

  String get floatingLogHideHint;

  String get floatingLogCopied;

  String get floatingLogCopyDomain;

  String get floatingLogCopyRecord;

  String get floatingLogEmpty;

  String get floatingLogEmptyBody;

  String get floatingLogClearedBody;

  String get floatingLogNoMatchBody;

  String get floatingLogUnavailable;

  String get floatingLogUnavailableBody;

  String floatingLogShown(int count);

  String floatingLogNewRows(int count);

  String get floatingLogPermissionTitle;

  String get floatingLogPermissionGranted;

  String get floatingLogPermissionMissing;

  String get floatingLogOpacity;

  String get floatingLogSizeTitle;

  String get logRetentionOverlayHowTo;

  String get permOverlay;

  String get desktopDnsServiceTitle;

  String get desktopQueriesTitle;

  String get desktopQueriesTotal;

  String get desktopQueriesSuccess;

  String get desktopQueriesFailed;

  String get desktopQps;

  String get desktopCacheTitle;

  String get desktopCacheHits;

  String get desktopCacheEvictions;

  String get desktopFilterTitle;

  String get desktopFilterRules;

  String get desktopFilterBlockRate;

  String get desktopTakeoverTitle;

  String get desktopTakeoverOn;

  String get desktopTakeoverOff;

  String get desktopFilterPauseTitle;

  String get desktopFilterPaused;

  String get desktopFilterActive;

  String get desktopServiceHostTitle;

  String get desktopServiceAutoStart;

  String get desktopServiceNotInstalled;

  String get desktopVersion;

  String get desktopProcessId;

  String get desktopPerformanceTitle;

  String get desktopRuntimeTitle;

  String get desktopLanAllowed;

  String get desktopListeningOn;

  String get desktopStartDns;

  String get desktopStopDns;

  String get desktopStartDnsTitle;

  String get desktopStartDnsMessage;

  String get desktopStopDnsTitle;

  String get desktopStopDnsMessage;

  String get desktopBackendOfflineTitle;

  String desktopBackendOfflineBody(String address);

  String get desktopBackendUnauthorizedTitle;

  String get desktopBackendUnauthorizedBody;

  String desktopActionFailed(String message);

  String desktopLastUpdated(String time);

  String get desktopRetry;

  String get desktopRecentQueriesTitle;

  String get desktopRecentQueriesEmpty;

  String get desktopLogWindow24h;

  String get desktopLogDomain;

  String get desktopLogClient;

  String get desktopLogDomainHint;

  String get desktopLogClientHint;

  String get desktopLogAllTypes;

  String get desktopLogClear;

  String get desktopLogClearTitle;

  String get desktopLogClearBody;

  String get desktopLogClearDone;

  String desktopLogClearFailed(String message);

  String get desktopLogTopDomains;

  String get desktopLogTopBlocked;

  String get desktopLogTopClients;

  String get desktopLogNoBlocked;

  String get desktopLiveTitle;

  String get desktopLiveConnected;

  String get desktopLivePaused;

  String get desktopLiveDisconnected;

  String get desktopLiveDisconnectedBody;

  String desktopLiveShown(String count);

  String get desktopLiveSearchHint;

  String get desktopLiveOnlyBlocked;

  String get desktopLivePause;

  String get desktopLiveResume;

  String get desktopLiveClear;

  String get desktopLiveEmpty;

  String get desktopLiveCaptured;

  String get desktopLiveBlocked;

  String get desktopLiveSuccessRate;

  String desktopLiveBufferNote(String count);

  String get desktopLiveStale;

  String get desktopLogConfigTitle;

  String get desktopLogConfigEnabled;

  String get desktopLogConfigEnabledBody;

  String get desktopLogConfigMaxEntries;

  String get desktopLogConfigRetentionDays;

  String get desktopLogConfigFile;

  String get desktopLogConfigFileBody;

  String get desktopLogConfigClients;

  String get desktopLogConfigClientsBody;

  String desktopLogConfigDataDir(String path);

  String get desktopLogConfigSave;

  String get desktopLogConfigSaved;

  String get desktopLogConfigLoadFailed;

  String get desktopLogConfigInvalid;

  String get desktopLogPagePrev;

  String get desktopLogPageNext;

  String desktopLogPageInfo(String from, String to, String total);

  String get desktopHubResolveSection;

  String get desktopHubProtectSection;

  String get desktopHubUpstream;

  String get desktopHubUpstreamBody;

  String get desktopUpstreamTitle;

  String get desktopUpstreamModeTitle;

  String get desktopUpstreamModeBody;

  String get desktopUpstreamModeSingle;

  String get desktopUpstreamModeSingleBody;

  String get desktopUpstreamModeBackup;

  String get desktopUpstreamModeBackupBody;

  String get desktopUpstreamModeRace;

  String get desktopUpstreamModeRaceBody;

  String get desktopUpstreamModeSmart;

  String get desktopUpstreamModeSmartBody;

  String get desktopUpstreamNodesTitle;

  String get desktopUpstreamNodesBody;

  String desktopUpstreamNodesCount(int count);

  String get desktopUpstreamAdd;

  String get desktopUpstreamAddTitle;

  String get desktopUpstreamEditTitle;

  String get desktopUpstreamName;

  String get desktopUpstreamProtocol;

  String get desktopUpstreamAddress;

  String get desktopUpstreamUrl;

  String get desktopUpstreamPin;

  String get desktopUpstreamPinWarning;

  String get desktopUpstreamPreset;

  String get desktopUpstreamPresetProvider;

  String get desktopUpstreamPresetProtocol;

  String get desktopUpstreamStamp;

  String get desktopUpstreamStampHint;

  String get desktopUpstreamStampParse;

  String get desktopUpstreamStampParsing;

  String get desktopUpstreamStampEmpty;

  String desktopUpstreamStampFailed(String message);

  String desktopUpstreamStampParsed(String proto);

  String get desktopUpstreamInvalid;

  String get desktopUpstreamDeleteTitle;

  String desktopUpstreamDeleteBody(String name);

  String get desktopUpstreamKeepOne;

  String get desktopUpstreamEmpty;

  String get desktopUpstreamEmptyBody;

  String get desktopUpstreamTest;

  String desktopUpstreamTestFailed(String message);

  String desktopUpstreamSaveFailed(String message);

  String get desktopUpstreamSaved;

  String get desktopUpstreamLoadFailed;

  String get desktopUpstreamBootstrapTitle;

  String get desktopUpstreamBootstrapBody;

  String get desktopUpstreamBootstrapOn;

  String get desktopUpstreamBootstrapOff;

  String get desktopUpstreamBootstrapAdd;

  String get desktopUpstreamBootstrapEmpty;

  String get desktopUpstreamBootstrapKeepOne;

  String get desktopUpstreamBootstrapName;

  String get desktopUpstreamBootstrapAddress;

  String get desktopUpstreamBootstrapInvalid;

  String desktopUpstreamBootstrapDeleteBody(String name);

  String get desktopUpstreamRoutesTitle;

  String get desktopUpstreamRoutesBody;

  String get desktopUpstreamRoutesAdd;

  String get desktopUpstreamRoutesEmpty;

  String get desktopUpstreamRouteDomain;

  String get desktopUpstreamRouteServer;

  String get desktopUpstreamRouteInvalid;

  String desktopUpstreamRouteDeleteBody(String domain);

  String get desktopUpstreamFallbackPolicyTitle;

  String get desktopUpstreamFallbackPolicyBody;

  String get desktopUpstreamFallbackPolicyOff;

  String get desktopUpstreamFallbackTitle;

  String get desktopUpstreamFallbackBody;

  String get desktopUpstreamFallbackOff;

  String desktopUpstreamFallbackCount(int count);

  String get desktopUpstreamFallbackNote;

  String get desktopUpstreamFallbackEmpty;

  String get desktopUpstreamFallbackAdd;

  String get desktopUpstreamFallbackTimeout;

  String get desktopUpstreamFallbackTimeoutHint;

  String get desktopUpstreamFallbackRcode;

  String get desktopUpstreamFallbackRcodeHint;

  String get desktopUpstreamFallbackOnError;

  String desktopUpstreamWeight(int weight);

  String get desktopUpstreamPinSet;

  String get desktopUpstreamPresetMissing;

  String get desktopUpstreamProbeFailed;

  String get desktopUpstreamBootstrapAddTitle;

  String get desktopUpstreamBootstrapEditTitle;

  String get desktopHubCache;

  String get desktopHubCacheBody;

  String get desktopCacheEngineTitle;

  String get desktopCacheEngineBody;

  String get desktopCacheEngineOn;

  String get desktopCacheEngineOff;

  String get desktopCacheHitRatio;

  String get desktopCacheRefresh;

  String get desktopCacheClear;

  String get desktopCacheClearTitle;

  String desktopCacheClearBody(int count);

  String get desktopCacheClearDone;

  String desktopCacheClearFailed(String message);

  String get desktopCacheTelemetryTitle;

  String desktopCacheTelemetryCapacity(int used, int max);

  String get desktopCacheMisses;

  String get desktopCacheStaleHits;

  String get desktopCacheNegativeHits;

  String get desktopCachePrefetchCount;

  String get desktopCacheTopTitle;

  String get desktopCacheTopBody;

  String get desktopCacheTopEmpty;

  String desktopCacheTopHits(int count);

  String get desktopCacheConfigTitle;

  String get desktopCacheConfigBody;

  String get desktopCacheConfigSave;

  String get desktopCacheConfigSaved;

  String get desktopCacheFallbackTitle;

  String get desktopCacheFallbackBody;

  String get desktopCacheModeLabel;

  String get desktopCacheModeLimit;

  String get desktopCacheModeFollow;

  String get desktopCacheModeFixed;

  String get desktopCacheMaxTtl;

  String get desktopCacheMinTtl;

  String get desktopCacheFixedTtl;

  String get desktopCacheMinTtlEnabled;

  String get desktopCacheStaleTitle;

  String get desktopCacheStaleBody;

  String get desktopCacheStaleSeconds;

  String get desktopCacheOptimistic;

  String get desktopCacheOptimisticBody;

  String get desktopCacheNegative;

  String get desktopCacheNegativeBody;

  String get desktopCacheNegativeSeconds;

  String get desktopCachePrefetchTitle;

  String get desktopCachePrefetchBody;

  String get desktopCachePrefetchThreshold;

  String get desktopCachePrefetchThresholdHint;

  String get desktopCachePrefetchBefore;

  String get desktopCachePrefetchBeforeHint;

  String get desktopCacheInvalidNumbers;

  String desktopCacheSaveFailed(String message);

  String get desktopCacheLoadFailed;

  String get desktopCachePersistTitle;

  String get desktopCachePersistBody;

  String get desktopCachePersistOn;

  String get desktopCachePersistOff;

  String get desktopCachePersistInterval;

  String get desktopCachePersistIntervalHint;

  String get desktopCachePersistPath;

  String desktopCachePersistLastError(String message);

  String desktopCachePersistRecords(int count);

  String get desktopCacheSnapshotTitle;

  String get desktopCacheSnapshotBody;

  String get desktopCachePersistDump;

  String get desktopCachePersistLoad;

  String desktopCachePersistDumpDone(int count);

  String desktopCachePersistLoadDone(int count);

  String desktopCachePersistDumpFailed(String message);

  String desktopCachePersistLoadFailed(String message);

  String get desktopCachePersistLoadTitle;

  String get desktopCachePersistLoadBody;

  String get desktopCachePersistToggleOn;

  String get desktopCachePersistToggleOff;

  String get desktopCachePersistIntervalSaved;

  String get desktopCacheExcludeTitle;

  String get desktopCacheExcludeBody;

  String get desktopCacheExcludeOff;

  String desktopCacheExcludeCount(int count);

  String get desktopCacheExcludeLabel;

  String get desktopCacheExcludeHint;

  String get desktopCacheExcludeSave;

  String desktopCacheExcludeSaved(int count);

  String get desktopCacheExcludeCleared;

  String desktopCacheExcludeFailed(String message);

  String desktopCacheExcludeHits(int count);

  String get desktopCacheExcludeReset;

  String desktopCacheExcludeTooMany(int max);

  String desktopCacheExcludeTooLong(int count, int max);

  String get desktopCacheExcludePresetLocal;

  String get desktopCacheExcludePresetPtr;

  String get desktopCacheExcludePresetProbe;

  String get desktopCacheEntriesTitle;

  String get desktopCacheEntriesBody;

  String get desktopCacheEntriesSearch;

  String get desktopCacheEntriesEmpty;

  String get desktopCacheEntriesNone;

  String get desktopCacheEntriesLoadFailed;

  String get desktopCacheFilterAll;

  String get desktopCacheFilterFresh;

  String get desktopCacheFilterStale;

  String get desktopCacheFilterNegative;

  String get desktopCacheEntryDomain;

  String get desktopCacheEntryType;

  String get desktopCacheEntryStatus;

  String get desktopCacheEntryRemaining;

  String get desktopCacheEntryTtl;

  String get desktopCacheEntryHits;

  String get desktopCacheEntryIps;

  String get desktopCacheStatusFresh;

  String get desktopCacheStatusStale;

  String get desktopCacheStatusNegative;

  String get desktopCacheNoIps;

  String get desktopHubRewrite;

  String get desktopHubRewriteBody;

  String get desktopRewriteTitle;

  String get desktopRewriteEngineTitle;

  String get desktopRewriteEngineBody;

  String get desktopRewriteEngineOn;

  String get desktopRewriteEngineOff;

  String get desktopRewriteEnabled;

  String get desktopRewriteDisabled;

  String get desktopRewriteDefaultTtl;

  String get desktopRewriteTtlSave;

  String get desktopRewriteTtlSaved;

  String get desktopRewriteTtlInvalid;

  String get desktopRewriteToggleOn;

  String get desktopRewriteToggleOff;

  String desktopRewriteSaveFailed(String message);

  String get desktopRewriteLoadFailed;

  String get desktopRewriteRulesTitle;

  String get desktopRewriteRulesBody;

  String desktopRewriteRulesCount(int count);

  String get desktopRewriteAdd;

  String get desktopRewriteSearch;

  String get desktopRewriteEmpty;

  String get desktopRewriteNoMatch;

  String get desktopRewriteResetSearch;

  String get desktopRewriteDomain;

  String get desktopRewriteTypes;

  String get desktopRewriteTarget;

  String get desktopRewriteTtl;

  String get desktopRewriteActions;

  String get desktopRewriteEdit;

  String get desktopRewriteDelete;

  String desktopRewriteSeconds(int count);

  String get desktopRewriteNoTarget;

  String desktopRewriteRcodeOnly(String rcode);

  String get desktopRewriteDeleteTitle;

  String desktopRewriteDeleteBody(String domain);

  String desktopRewriteRuleSaved(String domain);

  String desktopRewriteRuleDeleted(String domain);

  String desktopRewriteRuleFailed(String message);

  String desktopRewriteDeleteFailed(String message);

  String get desktopRewriteAddTitle;

  String get desktopRewriteEditTitle;

  String get desktopRewriteDomainLabel;

  String get desktopRewriteDomainHint;

  String get desktopRewriteDomainHelp;

  String get desktopRewriteDomainRequired;

  String get desktopRewriteTargetMode;

  String get desktopRewriteModeShortcut;

  String get desktopRewriteModeRecords;

  String get desktopRewriteTargetType;

  String get desktopRewriteTypeIp;

  String get desktopRewriteTypeCname;

  String get desktopRewriteTypeTxt;

  String get desktopRewriteIpsLabel;

  String get desktopRewriteIpsHelp;

  String get desktopRewriteCnameLabel;

  String get desktopRewriteCnameHelp;

  String get desktopRewriteTxtLabel;

  String get desktopRewriteRecordsLabel;

  String get desktopRewriteRecordAdd;

  String get desktopRewriteRecordEmpty;

  String get desktopRewriteRecordValueHint;

  String get desktopRewriteRecordsHelp;

  String get desktopRewriteRcodeLabel;

  String get desktopRewriteRcodeNone;

  String get desktopRewriteRcodeWarning;

  String get desktopRewriteTtlLabel;

  String get desktopRewriteTtlHint;

  String get desktopRewriteNeedIp;

  String get desktopRewriteNeedCname;

  String get desktopRewriteNeedTxt;

  String get desktopRewriteNeedRecord;

  String get desktopRewriteChipEmpty;

  String get desktopZoneSettingsTitle;

  String get desktopZoneSettingsBody;

  String get desktopZoneTitle;

  String get desktopZoneBody;

  String desktopZoneBadge(int zones, int maxZones, int records);

  String get desktopZoneRules;

  String get desktopZoneDefaultTtl;

  String get desktopZoneTtlSaved;

  String get desktopZoneTtlInvalid;

  String get desktopZoneToggleOn;

  String get desktopZoneToggleOff;

  String desktopZoneSaveFailed(String message);

  String get desktopZoneLoadFailed;

  String desktopZoneLimit(int records);

  String get desktopZoneAdd;

  String get desktopZoneSaveAll;

  String get desktopZoneSaved;

  String get desktopZoneEmpty;

  String desktopZoneMaxZones(int max);

  String get desktopZoneOriginHint;

  String desktopZoneDeleted(String origin);

  String get desktopZoneUnnamed;

  String get desktopZoneStateDisabled;

  String get desktopZoneStatePending;

  String get desktopZoneStateFailed;

  String desktopZoneStateTruncated(int count);

  String desktopZoneStateLoaded(int count);

  String get desktopZoneFailedReason;

  String get desktopZoneExpand;

  String get desktopZoneCollapse;

  String get desktopZoneDelete;

  String get desktopZoneContent;

  String get desktopZonePreview;

  String get desktopZonePreviewNote;

  String get desktopZonePreviewEmpty;

  String desktopZonePreviewMore(int count);

  String get desktopHubDns64;

  String get desktopHubDns64Body;

  String get desktopDns64Title;

  String get desktopDns64Refresh;

  String get desktopDns64CardTitle;

  String get desktopDns64CardBody;

  String get desktopDns64EngineOn;

  String get desktopDns64EngineOff;

  String get desktopDns64Description;

  String get desktopDns64PrefixesCardTitle;

  String get desktopDns64PrefixesLabel;

  String get desktopDns64PrefixesHelper;

  String get desktopDns64FillWellKnown;

  String get desktopDns64NoteTitle;

  String get desktopDns64NoteBody;

  String get desktopDns64Save;

  String get desktopDns64Saving;

  String get desktopDns64Saved;

  String get desktopDns64ToggleOn;

  String get desktopDns64ToggleOff;

  String desktopDns64SaveFailed(String message);

  String get desktopDns64LoadFailed;

  String get desktopHubFilterLists;

  String get desktopHubFilterListsBody;

  String get desktopFilterListsPageTitle;

  String get desktopFilterListsRefresh;

  String get desktopFilterSummaryTitle;

  String get desktopFilterEngineOn;

  String get desktopFilterEngineOff;

  String get desktopFilterPausedChip;

  String get desktopFilterBlocked;

  String get desktopFilterTimes;

  String get desktopFilterRulesUnit;

  String get desktopFilterActiveLists;

  String get desktopFilterListsUnit;

  String desktopFilterPausedRemaining(String remaining);

  String desktopFilterPauseDays(int days);

  String desktopFilterPauseHours(int hours, int minutes);

  String desktopFilterPauseMinutes(int minutes, int seconds);

  String desktopFilterPauseSeconds(int seconds);

  String get desktopFilterListsTitle;

  String get desktopFilterListsBody;

  String desktopFilterListsCount(int count);

  String get desktopFilterListUpdateAll;

  String get desktopFilterListAdd;

  String get desktopFilterListsEmpty;

  String get desktopFilterListsEmptyBody;

  String desktopFilterListDefaultName(int index);

  String get desktopFilterListAdded;

  String get desktopFilterListAllUpdated;

  String get desktopFilterListUpdated;

  String desktopFilterActionFailed(String message);

  String desktopFilterListToggleOn(String name);

  String desktopFilterListToggleOff(String name);

  String get desktopFilterListDeleteTitle;

  String desktopFilterListDeleteBody(String name);

  String get desktopFilterListDeleteConfirm;

  String get desktopFilterListDeleted;

  String desktopFilterListRules(int count);

  String get desktopFilterListEnabled;

  String get desktopFilterListDisabled;

  String get desktopFilterListNeverUpdated;

  String desktopFilterListUpdatedAt(String time);

  String get desktopFilterListRefreshOne;

  String get desktopFilterListDelete;

  String get desktopFilterListHealthOk;

  String get desktopFilterListHealthUnchanged;

  String get desktopFilterListHealthCached;

  String get desktopFilterListHealthFailed;

  String get desktopFilterListHealthOkBody;

  String get desktopFilterListHealthUnchangedBody;

  String get desktopFilterListHealthCachedBody;

  String get desktopFilterListHealthFailedBody;

  String get desktopFilterListAddTitle;

  String get desktopFilterListAddBody;

  String get desktopFilterListNameLabel;

  String get desktopFilterListNameHint;

  String get desktopFilterListUrlLabel;

  String get desktopFilterListUrlHint;

  String get desktopFilterListAddConfirm;

  String get desktopFilterListNeedUrl;

  String get desktopFilterListsLoadFailed;

  String get desktopHubFilterRules;

  String get desktopHubFilterRulesBody;

  String get desktopFilterRulesPageTitle;

  String get desktopFilterRulesRefresh;

  String get desktopFilterRulesEditorTitle;

  String get desktopFilterRulesEditorBody;

  String get desktopFilterRulesSave;

  String get desktopFilterRulesSaving;

  String get desktopFilterRulesSaved;

  String desktopFilterRulesSaveFailed(String message);

  String get desktopFilterRulesLoadFailed;

  String get desktopFilterRulesPlaceholder;

  String desktopFilterRulesLineCount(int count);

  String get desktopFilterRulesHint;

  String get desktopFilterGuideTitle;

  String get desktopFilterGuideBody;

  String get desktopFilterGuideCommon;

  String get desktopFilterGuideExempt;

  String get desktopFilterGuideCompat;

  String get desktopFilterGuidePriority;

  String get desktopFilterGuideRewrite;

  String get desktopFilterGuideDomainTitle;

  String get desktopFilterGuideDomainBody;

  String get desktopFilterGuideAllowTitle;

  String get desktopFilterGuideAllowBody;

  String get desktopFilterGuideHostsTitle;

  String get desktopFilterGuideHostsBody;

  String get desktopFilterGuideImportantTitle;

  String get desktopFilterGuideImportantBody;

  String get desktopFilterGuideRewriteTitle;

  String get desktopFilterGuideRewriteBody;

  String get desktopFilterGuideFooter;

  String get desktopHubFilterConfig;

  String get desktopHubFilterConfigBody;

  String get desktopFilterConfigPageTitle;

  String get desktopFilterConfigRefresh;

  String get desktopFilterConfigLoadFailed;

  String desktopFilterConfigSaveFailed(String message);

  String get desktopFilterEngineOnMessage;

  String get desktopFilterEngineOffMessage;

  String get desktopFilterModeTitle;

  String get desktopFilterModeBody;

  String get desktopFilterModeSave;

  String get desktopFilterModeSaving;

  String get desktopFilterModeSaved;

  String get desktopFilterModeParamsTitle;

  String get desktopFilterModeParamsBody;

  String get desktopFilterModeBlockingIPv4;

  String get desktopFilterModeBlockingIPv6;

  String get desktopFilterModeInterval;

  String get desktopFilterModeIntervalHelper;

  String get desktopFilterModeInvalid;

  String get desktopFilterModeNullIp;

  String get desktopFilterModeNullIpBody;

  String get desktopFilterModeNxdomain;

  String get desktopFilterModeNxdomainBody;

  String get desktopFilterModeRefused;

  String get desktopFilterModeRefusedBody;

  String get desktopFilterAdvancedTitle;

  String get desktopFilterAdvancedBody;

  String get desktopFilterAdvancedResponseTitle;

  String get desktopFilterAdvancedResponseBody;

  String get desktopFilterAdvancedResponseOn;

  String get desktopFilterAdvancedResponseOff;

  String get desktopFilterAdvancedAllowlistTitle;

  String get desktopFilterAdvancedAllowlistBody;

  String get desktopFilterAdvancedAllowlistWarning;

  String get desktopFilterAdvancedAllowlistOn;

  String get desktopFilterAdvancedAllowlistOff;

  String get desktopFilterAdvancedBogusTitle;

  String get desktopFilterAdvancedBogusBody;

  String get desktopFilterAdvancedBogusOn;

  String get desktopFilterAdvancedBogusOff;

  String get desktopFilterAdvancedBogusListLabel;

  String desktopFilterAdvancedBogusSuspicious(String entries);

  String get desktopFilterAdvancedBogusPresets;

  String get desktopFilterAdvancedBogusReset;

  String get desktopFilterAdvancedBogusSave;

  String desktopFilterAdvancedBogusSaved(int count);

  String get desktopFilterAdvancedBogusCleared;

  String get desktopFilterPauseBody;

  String get desktopFilterPauseDuration;

  String get desktopFilterPauseAction;

  String get desktopFilterPauseResume;

  String get desktopFilterPauseStarted;

  String get desktopFilterPauseResumed;

  String get desktopFilterPauseActiveTitle;

  String desktopFilterPauseActiveBody(String remaining);

  String desktopFilterPauseMinutesOnly(int minutes);

  String get desktopFilterPauseOneHour;

  String get desktopFilterPauseEightHours;

  String get desktopHubFilterSchedule;

  String get desktopHubFilterScheduleBody;

  String get desktopSchedulePageTitle;

  String get desktopScheduleRefresh;

  String get desktopScheduleLoadFailed;

  String get desktopScheduleTitle;

  String get desktopScheduleBody;

  String get desktopScheduleBadgeOff;

  String get desktopScheduleBadgeActive;

  String get desktopScheduleBadgePaused;

  String get desktopScheduleEnable;

  String get desktopScheduleEnableBody;

  String get desktopScheduleNoEnabled;

  String get desktopScheduleSave;

  String get desktopScheduleSaving;

  String get desktopScheduleSaved;

  String desktopScheduleSaveFailed(String message);

  String get desktopScheduleAdd;

  String get desktopScheduleName;

  String get desktopScheduleEnabled;

  String get desktopScheduleStart;

  String get desktopScheduleEnd;

  String get desktopScheduleEndHelper;

  String get desktopScheduleWeekdays;

  String get desktopScheduleEveryDay;

  String get desktopScheduleDelete;

  String get desktopScheduleDeleteTitle;

  String get desktopScheduleDeleteBody;

  String get desktopScheduleDeleteConfirm;

  String get desktopWeekdayMon;

  String get desktopWeekdayTue;

  String get desktopWeekdayWed;

  String get desktopWeekdayThu;

  String get desktopWeekdayFri;

  String get desktopWeekdaySat;

  String get desktopWeekdaySun;

  String get desktopHubFilterServices;

  String get desktopHubFilterServicesBody;

  String get desktopServicesPageTitle;

  String get desktopServicesRefresh;

  String get desktopServicesLoadFailed;

  String get desktopServicesGroupsTitle;

  String get desktopServicesGroupsBody;

  String get desktopServicesTitle;

  String get desktopServicesBody;

  String desktopServicesCount(int blocked, int total);

  String get desktopServicesClearAll;

  String get desktopServicesCleared;

  String get desktopServicesSearchHint;

  String get desktopServicesGroupFilter;

  String get desktopServicesAllGroups;

  String desktopServicesGroupItem(String name, int count);

  String desktopServicesGroupChip(String name, int count);

  String desktopServicesActiveRules(int count);

  String get desktopServicesEmpty;

  String get desktopServicesNoMatch;

  String desktopServicesBlocked(String name);

  String desktopServicesUnblocked(String name);

  String desktopServicesActionFailed(String message);

  String desktopServicesGroupOn(String name);

  String desktopServicesGroupOff(String name);

  String get desktopServicesByGroup;

  String get desktopServicesScheduleInside;

  String get desktopServicesScheduleOutside;

  String desktopServicesRuleCount(String group, int count);

  String get desktopServicesScheduleEdit;

  String get desktopServicesShowRules;

  String desktopServicesScheduleTitle(String name);

  String get desktopServicesScheduleBody;

  String get desktopServicesScheduleSave;

  String desktopServicesScheduleSaved(String name);

  String desktopServicesScheduleRemoved(String name);

  String get desktopHubPrivacy;

  String get desktopHubPrivacyBody;

  String get desktopPrivacyPageTitle;

  String get desktopPrivacyRefresh;

  String get desktopPrivacyLoadFailed;

  String desktopPrivacySaveFailed(String message);

  String get desktopPrivacyProtocolTitle;

  String get desktopPrivacyProtocolBody;

  String get desktopPrivacyBlockTitle;

  String get desktopPrivacyBlockBody;

  String get desktopPrivacyEdeTitle;

  String get desktopPrivacyEdeBody;

  String get desktopPrivacyEdeOn;

  String get desktopPrivacyEdeOff;

  String get desktopPrivacyPtrTitle;

  String get desktopPrivacyPtrBody;

  String get desktopPrivacyPtrOn;

  String get desktopPrivacyPtrOff;

  String get desktopPrivacyUnqualifiedTitle;

  String get desktopPrivacyUnqualifiedBody;

  String get desktopPrivacyUnqualifiedOn;

  String get desktopPrivacyUnqualifiedOff;

  String get desktopPrivacyEchTitle;

  String get desktopPrivacyEchBody;

  String get desktopPrivacyEchOn;

  String get desktopPrivacyEchOff;

  String get desktopPrivacyAnyTitle;

  String get desktopPrivacyAnyBody;

  String get desktopPrivacyAnyOn;

  String get desktopPrivacyAnyOff;

  String get desktopPrivacyAnyModeLabel;

  String get desktopPrivacyAnyModeNotimp;

  String get desktopPrivacyAnyModeNotimpBody;

  String get desktopPrivacyAnyModeRfc;

  String get desktopPrivacyAnyModeRfcBody;

  String get desktopPrivacyAnyModeSaved;

  String get desktopPrivacyIpv6Title;

  String get desktopPrivacyIpv6Body;

  String get desktopPrivacyIpv6On;

  String get desktopPrivacyIpv6Off;

  String get desktopPrivacyPaddingTitle;

  String get desktopPrivacyPaddingBody;

  String desktopPrivacyPaddingValue(int size);

  String get desktopPrivacyPaddingSaved;

  String get desktopPrivacyEcsTitle;

  String get desktopPrivacyEcsBody;

  String get desktopPrivacyEcsOn;

  String get desktopPrivacyEcsOff;

  String get desktopPrivacyEcsOnMessage;

  String get desktopPrivacyEcsOffMessage;

  String get desktopPrivacyEcsStripTitle;

  String get desktopPrivacyEcsStripBody;

  String get desktopPrivacyEcsStripOn;

  String get desktopPrivacyEcsStripOff;

  String get desktopPrivacyEcsSubnetLabel;

  String get desktopPrivacyEcsSubnetHelper;

  String get desktopPrivacyEcsSave;

  String get desktopPrivacyEcsSaved;

  String get desktopPrivacyDefenceTitle;

  String get desktopPrivacyDefenceBody;

  String get desktopPrivacyRebindTitle;

  String get desktopPrivacyRebindBody;

  String get desktopPrivacyRebindOn;

  String get desktopPrivacyRebindOff;

  String desktopPrivacyRebindCount(int count);

  String get desktopPrivacyRebindAllowlist;

  String get desktopPrivacyRebindDialogTitle;

  String get desktopPrivacyRebindDialogBody;

  String get desktopPrivacyRebindDialogSave;

  String get desktopPrivacyRebindSaved;

  String get desktopPrivacyHostsTitle;

  String get desktopPrivacyHostsBody;

  String get desktopPrivacyHostsOn;

  String get desktopPrivacyHostsOff;

  String get desktopPrivacyHostsSystem;

  String desktopPrivacyHostsTtl(int seconds);

  String get desktopPrivacyHostsSystemOn;

  String get desktopPrivacyHostsSystemOff;

  String get desktopHubPrivacySection;

  String get desktopHubShareSection;

  String get desktopSafeSearchTitle;

  String get desktopSafeSearchBody;

  String desktopSafeSearchEnabled(int count);

  String get desktopSafeSearchOff;

  String get desktopSafeSearchOn;

  String get desktopSafeSearchOffMessage;

  String get desktopSafeSearchServiceSaved;

  String get desktopSafeSearchTtl;

  String get desktopSafeSearchTtlSave;

  String get desktopSafeSearchTtlSaved;

  String get desktopSafeSearchTtlInvalid;

  String get desktopSafeSearchFooter;

  String get desktopSafeSearchTtlCardTitle;

  String get desktopSafeSearchTtlCardBody;

  String desktopSafeSearchTtlChip(int seconds);

  String get desktopSafeSearchBing;

  String get desktopSafeSearchDuckDuckGo;

  String get desktopSafeSearchEcosia;

  String get desktopSafeSearchGoogle;

  String get desktopSafeSearchPixabay;

  String get desktopSafeSearchYandex;

  String get desktopSafeSearchYoutube;

  String get desktopReputationTitle;

  String get desktopReputationOn;

  String get desktopReputationOff;

  String get desktopReputationOnMessage;

  String get desktopReputationOffMessage;

  String get desktopReputationBody;

  String get desktopReputationLookups;

  String get desktopReputationBlocked;

  String get desktopReputationHitRate;

  String get desktopReputationFailures;

  String get desktopReputationAnswer;

  String get desktopReputationAnswerNullIp;

  String get desktopReputationTimeout;

  String get desktopReputationCacheSize;

  String get desktopReputationCacheTtl;

  String get desktopReputationParamsTitle;

  String get desktopReputationParamsInvalid;

  String get desktopReputationParamsSave;

  String get desktopReputationParamsSaved;

  String get desktopReputationFooter;

  String get desktopParentalTitle;

  String get desktopParentalBody;

  String get desktopParentalWarning;

  String get desktopParentalOn;

  String get desktopParentalOff;

  String get desktopHubEncrypted;

  String get desktopHubEncryptedBody;

  String get desktopEncryptedPageTitle;

  String get desktopEncryptedRefresh;

  String get desktopEncryptedLoadFailed;

  String desktopEncryptedSaveFailed(String message);

  String get desktopEncryptedListenersTitle;

  String get desktopEncryptedListenersBody;

  String get desktopEncryptedEnabled;

  String get desktopEncryptedDisabled;

  String get desktopEncryptedOn;

  String get desktopEncryptedOff;

  String get desktopEncryptedNoProtocol;

  String get desktopEncryptedDot;

  String desktopEncryptedDotBody(int port);

  String get desktopEncryptedDoh;

  String desktopEncryptedDohBody(int port, String path);

  String desktopEncryptedListening(String address);

  String get desktopEncryptedNotListening;

  String get desktopEncryptedDotOn;

  String get desktopEncryptedDotOff;

  String get desktopEncryptedDohOn;

  String get desktopEncryptedDohOff;

  String get desktopEncryptedUrls;

  String get desktopEncryptedNetworkTitle;

  String get desktopEncryptedListenAddress;

  String get desktopEncryptedListenHint;

  String get desktopEncryptedServerName;

  String get desktopEncryptedDotPort;

  String get desktopEncryptedDohPort;

  String get desktopEncryptedDohPath;

  String get desktopEncryptedServerNameHint;

  String get desktopEncryptedPortInvalid;

  String get desktopEncryptedReset;

  String get desktopEncryptedSaveNetwork;

  String get desktopEncryptedNetworkSaved;

  String get desktopEncryptedCertTitle;

  String get desktopEncryptedCertBody;

  String get desktopEncryptedCertSelfSigned;

  String get desktopEncryptedCertLoaded;

  String get desktopEncryptedCertMissing;

  String get desktopEncryptedCertExpired;

  String get desktopEncryptedCertExpiresSoon;

  String get desktopEncryptedCertMissingBody;

  String get desktopEncryptedCertSubject;

  String get desktopEncryptedCertIssuer;

  String get desktopEncryptedCertNotAfter;

  String get desktopEncryptedCertDays;

  String desktopEncryptedCertDaysValue(int days);

  String get desktopEncryptedCertDns;

  String get desktopEncryptedCertIps;

  String desktopEncryptedCertFingerprint(String fingerprint);

  String desktopEncryptedCertDir(String dir);

  String get desktopEncryptedCertGenerate;

  String get desktopEncryptedCertImport;

  String get desktopEncryptedCertGenerated;

  String get desktopEncryptedCertImported;

  String get desktopEncryptedCertGenerateTitle;

  String get desktopEncryptedCertGenerateBody;

  String get desktopEncryptedCertKeyType;

  String get desktopEncryptedCertCommonName;

  String get desktopEncryptedCertDnsNames;

  String get desktopEncryptedCertIpAddresses;

  String get desktopEncryptedCertValidDays;

  String get desktopEncryptedCertGenerateConfirm;

  String get desktopEncryptedCertImportTitle;

  String get desktopEncryptedCertImportBody;

  String get desktopEncryptedCertPem;

  String get desktopEncryptedKeyPem;

  String get desktopEncryptedCertImportConfirm;

  String get desktopEncryptedCertImportInvalid;

  String get desktopEncryptedExtrasTitle;

  String get desktopEncryptedExtrasBody;

  String get desktopEncryptedDdrTitle;

  String get desktopEncryptedDdrBody;

  String get desktopEncryptedDdrSelfSignedWarning;

  String get desktopEncryptedDdrConfirmTitle;

  String get desktopEncryptedDdrConfirmBody;

  String get desktopEncryptedDdrConfirm;

  String get desktopEncryptedDdrOn;

  String get desktopEncryptedDdrOff;

  String get desktopEncryptedProxyTitle;

  String get desktopEncryptedProxyBody;

  String get desktopEncryptedProxyUnrestricted;

  String get desktopEncryptedProxyOn;

  String get desktopEncryptedProxyOff;

  String get desktopEncryptedProxySources;

  String get desktopEncryptedProxyHeader;

  String get desktopEncryptedProxySave;

  String get desktopEncryptedProxySaved;

  String get desktopEncryptedMobileConfigTitle;

  String get desktopEncryptedMobileConfigBody;

  String get desktopEncryptedMobileConfigOpen;

  String get desktopEncryptedOpenUrl;

  String get desktopTrafficPageTitle;

  String get desktopTrafficRefresh;

  String get desktopTrafficLoadFailed;

  String desktopTrafficSaveFailed(String message);

  String get desktopTrafficClientsTitle;

  String get desktopTrafficClientsBody;

  String desktopTrafficClientCount(int count);

  String get desktopTrafficClientsEmpty;

  String get desktopTrafficClientUnnamed;

  String desktopTrafficClientQueries(int count);

  String get desktopTrafficClientNever;

  String desktopTrafficClientLastSeen(String time);

  String get desktopTrafficStateBlocked;

  String get desktopTrafficStateAllowed;

  String get desktopTrafficStateNotAllowed;

  String get desktopTrafficStateOpen;

  String get desktopTrafficAlias;

  String get desktopTrafficAliasTitle;

  String get desktopTrafficAliasField;

  String get desktopTrafficAliasHint;

  String get desktopTrafficAliasBody;

  String get desktopTrafficAliasSave;

  String desktopTrafficAliasSaved(String ip);

  String desktopTrafficAliasCleared(String ip);

  String get desktopTrafficAllowedAdd;

  String get desktopTrafficAllowedRemove;

  String desktopTrafficAllowedAdded(String ip);

  String desktopTrafficAllowedRemoved(String ip);

  String get desktopTrafficBlockedAdd;

  String get desktopTrafficBlockedRemove;

  String desktopTrafficBlockedAdded(String ip);

  String desktopTrafficBlockedRemoved(String ip);

  String get desktopTrafficAccessTitle;

  String get desktopTrafficAccessBody;

  String get desktopTrafficAccessOpen;

  String get desktopTrafficAccessAllowOnly;

  String get desktopTrafficAccessAllowed;

  String get desktopTrafficAccessAllowedHint;

  String get desktopTrafficAccessAllowedBody;

  String get desktopTrafficAccessBlocked;

  String get desktopTrafficAccessBlockedHint;

  String get desktopTrafficAccessBlockedBody;

  String get desktopTrafficAccessSave;

  String get desktopTrafficAccessReset;

  String get desktopTrafficAccessSaved;

  String get desktopTrafficRateLimitTitle;

  String get desktopTrafficRateLimitBody;

  String get desktopTrafficRateLimitOn;

  String get desktopTrafficRateLimitOff;

  String get desktopTrafficRateLimitSavedOn;

  String get desktopTrafficRateLimitSavedOff;

  String get desktopTrafficRate;

  String get desktopTrafficBurst;

  String get desktopTrafficIpv4Prefix;

  String get desktopTrafficIpv6Prefix;

  String get desktopTrafficPrefixBody;

  String get desktopTrafficExempt;

  String get desktopTrafficExemptBody;

  String get desktopTrafficRateLimitSave;

  String get desktopTrafficRateInvalid;

  String get desktopGroupsPageTitle;

  String get desktopGroupsRefresh;

  String get desktopGroupsLoadFailed;

  String get desktopGroupsTitle;

  String get desktopGroupsBody;

  String desktopGroupsCount(int enabled, int total);

  String get desktopGroupsOn;

  String get desktopGroupsOff;

  String get desktopGroupsSave;

  String get desktopGroupsSaved;

  String get desktopGroupsMaster;

  String get desktopGroupsMasterBody;

  String get desktopGroupsAdd;

  String get desktopGroupsEmpty;

  String get desktopGroupsFooter;

  String get desktopGroupsOpen;

  String get desktopGroupsName;

  String get desktopGroupsEnabled;

  String get desktopGroupsDelete;

  String get desktopGroupsDeleteTitle;

  String get desktopGroupsDeleteBody;

  String get desktopGroupsMembers;

  String get desktopGroupsMembersHint;

  String get desktopGroupsMembersBody;

  String get desktopGroupsBlockMode;

  String get desktopGroupsModeInherit;

  String get desktopGroupsModeNullIp;

  String get desktopGroupsModeNxdomain;

  String get desktopGroupsModeRefused;

  String get desktopGroupsAllowlistOnly;

  String get desktopGroupsAllowlistOnlyBody;

  String get desktopGroupsSchedule;

  String get desktopGroupsScheduleBody;

  String get desktopGroupsRuleLists;

  String get desktopGroupsInheritAll;

  String get desktopGroupsNoRuleLists;

  String get desktopGroupsRuleListsInherited;

  String get desktopGroupsRuleListsSelected;

  String get desktopGroupsUpstreams;

  String get desktopGroupsInheritChain;

  String get desktopGroupsNoUpstreams;

  String get desktopGroupsUpstreamsInherited;

  String get desktopGroupsUpstreamsSelected;

  String desktopGroupsNewName(int index);

  String get desktopGroupsListEnabled;

  String get desktopGroupsListDisabled;

  String get desktopToolsPortTitle;

  String get desktopToolsPortBody;

  String get desktopToolsPortIdle;

  String get desktopToolsPortOk;

  String get desktopToolsPortConflict;

  String get desktopToolsCheck;

  String get desktopToolsFix;

  String get desktopToolsFixTitle;

  String get desktopToolsFixBody;

  String get desktopToolsFixed;

  String desktopToolsFailed(String message);

  String get desktopToolsSystemListener;

  String get desktopToolsSelfListener;

  String desktopToolsConflictOwner(String process, int pid, String address);

  String desktopToolsConflictService(String service);

  String get desktopToolsPortFooter;

  String get desktopToolsRulePageTitle;

  String get desktopHubDiagnoseSection;

  String get desktopToolsRuleEntryBody;

  String get desktopHubQueryLog;

  String get desktopHubQueryLogBody;

  String get desktopQueryLogPageTitle;

  String get desktopToolsRuleInputTitle;

  String get desktopToolsRuleInputBody;

  String get desktopToolsRuleDomain;

  String get desktopToolsRuleDomainHint;

  String get desktopToolsRuleQtype;

  String desktopToolsRuleQtypeOption(String type);

  String get desktopToolsRuleExamples;

  String get desktopToolsRuleRun;

  String get desktopToolsRuleRunning;

  String get desktopToolsRuleVerdictTitle;

  String get desktopToolsRuleVerdictBody;

  String get desktopToolsRuleIdle;

  String get desktopToolsRuleBlocked;

  String desktopToolsRuleRewritten(String code);

  String get desktopToolsRuleAllowed;

  String get desktopToolsRulePassed;

  String get desktopToolsRuleMatched;

  String get desktopToolsRuleNoMatch;

  String get desktopToolsRuleList;

  String get desktopToolsRuleNoList;

  String get desktopToolsRuleReason;

  String get desktopToolsRuleNoReason;

  String desktopToolsRuleRewrite(String code);

  String get desktopToolsRuleRewriteEmpty;

  String get desktopToolsRuleFooter;

  String desktopToolsRuleFailed(String message);

  String get desktopHubAppSection;

  String get desktopAboutProjectSection;

  String get desktopAboutDisclaimerSection;

  String get desktopSettingsAppearance;

  String get desktopSettingsAppearanceEntryBody;

  String get desktopSettingsAppearanceTitle;

  String get desktopSettingsAppearanceBody;

  String get desktopSettingsPalette;

  String get desktopSettingsPaletteBody;

  String get desktopSettingsMode;

  String get desktopSettingsModeBody;

  String get desktopSettingsAppearanceFooter;

  String get desktopSettingsPreview;

  String get desktopSettingsPreviewBody;

  String desktopSettingsSystemResolved(String mode);

  String get desktopServicePageTitle;

  String get desktopServiceEntryBody;

  String get desktopServiceConnectionTitle;

  String get desktopServiceConnectionBody;

  String get desktopServiceConnectionFooter;

  String get desktopServiceHost;

  String get desktopServicePort;

  String get desktopServiceToken;

  String get desktopServiceTokenHint;

  String get desktopServiceTest;

  String get desktopServiceSave;

  String get desktopServiceSaved;

  String get desktopServiceReachable;

  String get desktopServiceUnreachable;

  String get desktopServiceConfigured;

  String get desktopServiceAddressInvalid;

  String get desktopServiceCoreTitle;

  String get desktopServiceCoreBody;

  String get desktopServiceCoreFooter;

  String get desktopServiceState;

  String get desktopServiceAutoStartOn;

  String get desktopServiceAutoStartOff;

  String get desktopServiceAutoStartUnknown;

  String get desktopServiceRunning;

  String get desktopServiceStopped;

  String get desktopServiceUnknown;

  String get desktopServiceRefresh;

  String get desktopLanWebPageTitle;

  String get desktopLanWebEntryBody;

  String get desktopHubClientAccess;

  String get desktopHubClientAccessBody;

  String get desktopClientAccessPageTitle;

  String get desktopLanWebRefresh;

  String get desktopLanWebLoadFailed;

  String get desktopLanWebAccessTitle;

  String get desktopLanWebAccessBody;

  String get desktopLanWebTitle;

  String get desktopLanWebOpen;

  String get desktopLanWebLocal;

  String get desktopLanWebEnabledBody;

  String get desktopLanWebDisabledBody;

  String get desktopLanWebOn;

  String get desktopLanWebOff;

  String desktopLanWebFailed(String message);

  String get desktopLanWebUrls;

  String get desktopLanWebNoUrls;

  String get desktopLanWebPort;

  String get desktopLanWebSavePort;

  String get desktopLanWebPortInvalid;

  String get desktopLanWebFirewall;

  String get desktopLanWebFirewallBody;

  String get desktopLanWebFirewallOn;

  String get desktopLanWebFirewallOff;

  String get desktopLanWebNoFirewall;

  String get desktopLanWebCredentials;

  String desktopLanWebUser(String user);

  String get desktopLanWebNoUser;

  String get desktopLanWebProtected;

  String get desktopLanWebUnprotected;

  String get desktopLanWebChangePassword;

  String get desktopLanWebSetPassword;

  String get desktopLanWebPasswordSave;

  String get desktopLanWebPasswordSaved;

  String desktopLanWebChangeBody(String user);

  String desktopLanWebSetupBody(String user);

  String get desktopLanWebOldPassword;

  String get desktopLanWebNewPassword;

  String get desktopLanWebConfirmPassword;

  String get desktopLanWebPasswordRequired;

  String get desktopLanWebPasswordMismatch;

  String get desktopLanWebOldRequired;

  String get desktopLanWebFooter;

  String get desktopHubAdapters;

  String get desktopHubAdaptersBody;

  String get desktopHubLanDns;

  String get desktopHubLanDnsBody;

  String get desktopAdaptersPageTitle;

  String get desktopAdaptersRefresh;

  String get desktopAdaptersLoadFailed;

  String get desktopAdaptersSectionTitle;

  String get desktopAdaptersSectionBody;

  String get desktopAdaptersTakeoverAll;

  String get desktopAdaptersRestoreAll;

  String get desktopAdaptersProtecting;

  String get desktopAdaptersInactive;

  String get desktopAdaptersConnected;

  String get desktopAdaptersDisconnected;

  String get desktopAdaptersGateway;

  String get desktopAdaptersNoGateway;

  String get desktopAdaptersIpMode;

  String get desktopAdaptersDhcp;

  String get desktopAdaptersStatic;

  String get desktopAdaptersOriginalDns;

  String get desktopAdaptersAutoDns;

  String get desktopAdaptersEffectiveDns;

  String get desktopAdaptersEffectiveLoopback;

  String get desktopAdaptersEffectiveSystem;

  String get desktopAdaptersEmpty;

  String get desktopAdaptersEmptyBody;

  String get desktopAdaptersAllOn;

  String get desktopAdaptersAllOff;

  String desktopAdaptersAdapterToggled(String name, String state);

  String get desktopAdaptersAdapterOn;

  String get desktopAdaptersAdapterOff;

  String desktopAdaptersActionFailed(String message);

  String get desktopLanDnsPageTitle;

  String get desktopLanDnsRefresh;

  String get desktopLanDnsLoadFailed;

  String get desktopLanDnsServiceTitle;

  String get desktopLanDnsServiceBody;

  String get desktopLanDnsOnChip;

  String get desktopLanDnsOffChip;

  String get desktopLanDnsOn;

  String get desktopLanDnsOff;

  String get desktopLanDnsAddressesCardTitle;

  String get desktopLanDnsAddressesCardBody;

  String get desktopLanDnsListenTitle;

  String get desktopLanDnsNoListen;

  String get desktopLanDnsAddressesTitle;

  String get desktopLanDnsNoAddresses;

  String get desktopLanDnsIpv4;

  String get desktopLanDnsIpv6;

  String desktopLanDnsRouterHint(String address);

  String get desktopLanDnsFirewallTitle;

  String get desktopLanDnsFirewallAllowed;

  String get desktopLanDnsFirewallBlocked;

  String get desktopLanDnsFirewallNone;

  String get desktopLanDnsFirewallBody;

  String get desktopLanDnsFirewallNoneBody;

  String get desktopLanDnsFirewallStatusOn;

  String get desktopLanDnsFirewallStatusOff;

  String get desktopLanDnsFirewallAllow;

  String get desktopLanDnsFirewallRemove;

  String get desktopLanDnsFirewallOn;

  String get desktopLanDnsFirewallOff;

  String get desktopLanDnsRouterTitle;

  String get desktopLanDnsRouterBadge;

  String get desktopLanDnsRouterBody;

  String get desktopLanDnsRouterFoot;

  String get desktopLanDnsDeviceTitle;

  String get desktopLanDnsDeviceBadge;

  String get desktopLanDnsDeviceBody;

  String get desktopLanDnsDeviceFoot;

  String get desktopLanDnsPlaceholder;

  String desktopLanDnsFailed(String message);

  String get desktopLoginTitle;

  String get desktopLoginSubtitle;

  String get desktopLoginSetupSubtitle;

  String get desktopLoginUserLabel;

  String get desktopLoginPasswordLabel;

  String get desktopLoginSetupPasswordLabel;

  String get desktopLoginConfirmLabel;

  String get desktopLoginSubmit;

  String get desktopLoginSetupSubmit;

  String get desktopLoginSecurity;

  String get desktopLoginFooter;

  String get desktopLoginChecking;

  String get desktopLoginShowPassword;

  String get desktopLoginHidePassword;

  String get desktopLoginUserRequired;

  String get desktopLoginPasswordRequired;

  String get desktopLoginPasswordTooShort;

  String get desktopLoginPasswordMismatch;

  String get desktopLoginSuccess;

  String get desktopLoginSetupSuccess;

  String desktopLoginLockout(int seconds);

  String get desktopLoginUnreachable;

  String get desktopLoginRetry;

  String get desktopLoginThemeCycle;

  String get desktopLoginPaletteCycle;

  String get desktopLoginBackground;

  String get desktopLoginBackgroundEnabled;

  String get desktopLoginBackgroundTitle;

  String get desktopLoginBackgroundLocal;

  String get desktopLoginBackgroundUrl;

  String get desktopLoginBackgroundChoose;

  String get desktopLoginBackgroundNoFile;

  String get desktopLoginBackgroundUrlLabel;

  String get desktopLoginBackgroundUrlInvalid;

  String get desktopLoginBackgroundOpacity;

  String get desktopLoginBackgroundBlur;

  String get desktopLoginBackgroundSave;

  String get desktopLoginBackgroundReset;

  String get desktopLoginBackgroundSaved;

  String get desktopLoginBackgroundResetDone;

  String get desktopLoginBackgroundNeedImage;

  String get desktopLoginBackgroundPassword;

  String get desktopLoginBackgroundPasswordBody;

  String desktopLoginBackgroundFailed(String message);

  String get desktopSettingsSessionSection;

  String get desktopSettingsLogout;

  String get desktopSettingsLogoutBody;

  String get desktopSettingsLogoutConfirm;

  String get desktopSettingsLogoutDone;

  String get desktopToolsEmergencyTitle;

  String get desktopToolsEmergencyBody;

  String get desktopToolsEmergencyAction;

  String get desktopToolsEmergencyBusy;

  String get desktopToolsEmergencyConfirmTitle;

  String get desktopToolsEmergencyConfirmBody;

  String get desktopToolsEmergencyDone;

  String desktopToolsEmergencyFailed(String message);

  String get desktopToolsEmergencyFooter;

  String get desktopLanWebQrCaption;

  String get desktopLoginBackgroundPreparing;

  String get desktopLoginChangePassword;

  String get desktopLoginChangeSubtitle;

  String get desktopLoginOldPasswordLabel;

  String get desktopLoginNewPasswordLabel;

  String get desktopLoginChangeSubmit;

  String get desktopLoginChangeSuccess;

  String get desktopLoginBackToSignIn;

  String get desktopLoginOldPasswordRequired;

  String get desktopTrayTooltip;

  String get desktopTrayOpenWindow;

  String get desktopTrayHideWindow;

  String get desktopTrayAutoStart;

  String get desktopTrayServiceRunning;

  String get desktopTrayServiceStopped;

  String get desktopTrayServiceUnknown;

  String get desktopTrayServiceStart;

  String get desktopTrayServiceStop;

  String get desktopTrayServiceRestart;

  String get desktopTrayQuit;

  String get desktopTrayBalloonServiceTitle;

  String get desktopTrayBalloonServiceStarted;

  String get desktopTrayBalloonServiceStopped;

  String get desktopTrayBalloonServiceRestarted;

  String get desktopTrayBalloonAutoStartTitle;

  String get desktopTrayBalloonAutoStartOn;

  String get desktopTrayBalloonAutoStartOff;

  String get desktopTrayBalloonFailedPrefix;

  String get desktopTrayBalloonMinimized;

  String get deepLinkImportInvalid;

  String get troubleshootLogsTitle;

  String get troubleshootLogsViewLogs;

  String get troubleshootLogsViewLogsBody;

  String get troubleshootLogsAll;

  String troubleshootLogsCount(int count);

  String get troubleshootLogsReading;

  String get troubleshootLogsEmpty;

  String get troubleshootLogsEmptyBody;

  String get troubleshootLogKindRuntime;

  String get troubleshootLogKindCrash;

  String get troubleshootLogsRefresh;

  String get troubleshootLogsShare;

  String get troubleshootLogsShareAll;

  String get troubleshootLogsClearAll;

  String get troubleshootLogsShared;

  String get troubleshootLogsShareFailed;

  String get troubleshootLogsDeleted;

  String get troubleshootLogsDeleteFailed;

  String get troubleshootLogsDeleteTitle;

  String troubleshootLogsDeleteBody(String name);

  String get troubleshootLogsClearAllTitle;

  String get troubleshootLogsClearAllBody;

  String troubleshootLogsClearedAll(int runtime, int crash);

  String get troubleshootLogsLogContent;

  String get troubleshootLogsDetailInfo;

  String get troubleshootLogsActions;

  String get troubleshootLogsFileName;

  String get troubleshootLogsFileType;

  String get troubleshootLogsFileSize;

  String get troubleshootLogsModifiedAt;

  String get troubleshootLogsViewContent;

  String get troubleshootLogsViewContentBody;

  String get troubleshootLogsEmptyContent;

  String get troubleshootLogsTruncated;

  String get troubleshootLogsFooter;

  String get troubleshootEventsTitle;

  String get troubleshootEventsRecentTitle;

  String get troubleshootEventsRecentBody;

  String get troubleshootEventsEmpty;

  String get troubleshootEventsEmptyBody;

  String get troubleshootEventsAll;

  String get troubleshootEventsWarnPlus;

  String get troubleshootEventsErrorOnly;

  String get troubleshootEventsModuleAll;

  String troubleshootEventsCount(int count);

  String troubleshootEventsAnomaly(int count);

  String get troubleshootEventsExport;

  String get troubleshootEventsStatTotal;

  String get troubleshootEventsStatError;

  String get troubleshootEventsNoMatch;

  String get troubleshootEventsLevel;

  String get troubleshootEventsModule;

  String get troubleshootEventsOpen;

  String get troubleshootEventsOpenBody;

  String get troubleshootDetailMode;

  String get troubleshootDetailModeNote;

  String get automationTitle;

  String get automationSubtitle;

  String get automationHubSection;

  String get automationIntro;

  String get automationOverviewEmptyTitle;

  String get automationOverviewEmptyHint;

  String automationOverviewSummary(int total, int enabled);

  String get automationOverviewHint;

  String get automationSettingsSection;

  String get automationRulesSection;

  String get automationHistory;

  String get automationHistoryEmpty;

  String get automationRuleFallbackName;

  String automationPriorityShort(int value);

  String automationActionCount(int value);

  String get automationTriggerSchedule;

  String get automationTriggerNetwork;

  String get automationTriggerState;

  String get automationTriggerManual;

  String get automationNewTitle;

  String get automationEditTitle;

  String get automationDelete;

  String get automationSave;

  String get automationEditIntro;

  String get automationRuleName;

  String get automationPriority;

  String get automationTrigger;

  String get automationMatch;

  String get automationMatchAll;

  String get automationMatchAny;

  String get automationActions;

  String get automationActionPause;

  String get automationMinutes;

  String get automationActionBlockServices;

  String get automationServicesUnavailable;

  String get automationSwitchProfileNone;

  String get automationSwitchProfile;

  String get automationScheduleStart;

  String get automationScheduleEnd;

  String get profilesTitle;

  String get profilesSubtitle;

  String get profilesAdd;

  String get profilesIntro;

  String get profilesEmpty;

  String get profilesListSection;

  String get profilesApply;

  String get profilesDelete;

  String get profilesName;

  String get profilesUpstreamSet;

  String get profilesCancel;

  String get profilesSave;

  String profilesApplied(String name);

  String get timetableTitle;

  String get timetableSubtitle;

  String get timetableAdd;

  String get timetableIntro;

  String get timetableEmpty;

  String get netProfileTitle;

  String get netProfileSubtitle;

  String get netProfileAdd;

  String get netProfileIntro;

  String get netProfileCurrentNet;

  String get netProfileResolved;

  String get netProfileNone;

  String get netProfileEmpty;

  String get netProfileList;

  String get netProfileDelete;

  String get netProfileName;

  String get netProfileUpstreamSet;

  String get netProfilePriority;

  String get netProfileCancel;

  String get netProfileSave;

  String get automationAdd;

  String get networkDiagnosticsTitle;

  String get networkDiagnosticsIntro;

  String get dnsLeakSection;

  String get dnsLeakRun;

  String get dnsLeakPass;

  String get dnsLeakLeak;

  String get dnsLeakUnknown;

  String get dnsLeakReasonBypass;

  String get dnsLeakReasonProxied;

  String get dnsLeakReasonMismatch;

  String get dnsLeakReasonPlaintext;

  String get dnsLeakReasonInsufficient;

  String get dnsLeakVpnActive;

  String get dnsLeakVpnInactive;

  String get captiveSection;

  String get captiveRun;

  String get captiveOpen;

  String get captivePortal;

  String get captiveUnknown;

  String get captiveOpenPortal;

  String get networkDiagnosticsFailed;

  String get appInsightsTitle;

  String get appInsightsIntro;

  String get appInsightsEmpty;

  String get appInsightsReports;

  String get appInsightsMap;

  String appInsightsStat(int connections, int blocked, String bytes);

  String get appInsightsNoDomains;

  String get privacySuiteTitle;

  String get privacySuiteIntro;

  String get privacyDnsSection;

  String get privacyBlockHttpsSvcb;

  String get privacyBlockHttpsSvcbDesc;

  String get privacyRebinding;

  String get privacyRebindingDesc;

  String get dns64Title;

  String get dns64Intro;

  String get dns64Enable;

  String get dns64EnableDesc;

  String get connectionRateLimitTitle;

  String get connectionRateLimitCardDescription;

  String get connectionRateLimitIntro;

  String get connectionRateLimitSectionSwitch;

  String get connectionRateLimitSectionParameters;

  String get connectionRateLimitEnable;

  String get connectionRateLimitEnableDesc;

  String get connectionRateLimitRate;

  String get connectionRateLimitBurst;

  String get connectionRateLimitFooter;

  String connectionRateLimitApplyFailed(String message);

  String get ruleVersionsTitle;

  String get ruleVersionsIntro;

  String get ruleVersionsPick;

  String get ruleVersionsHistory;

  String get ruleVersionsEmpty;

  String get ruleVersionsNone;

  String get ruleVersionsUnavailable;

  String get ruleVersionsCurrent;

  String ruleVersionsRuleCount(int count);

  String get ruleVersionsCompare;

  String get ruleVersionsRollback;

  String get ruleVersionsDiffTitle;

  String ruleVersionsDiffSummary(int added, int removed);

  String get ruleVersionsAdded;

  String get ruleVersionsRemoved;

  String get ruleVersionsRollbackConfirm;

  String get ruleVersionsRollbackDone;

  String ruleVersionsRollbackFailed(String message);

  String get troubleshootLogsDownload;

  String get troubleshootLogsDownloadAll;

  String get troubleshootLogsDownloadsDir;

  String troubleshootLogsDownloaded(String path);

  String troubleshootLogsDownloadedCount(int count);

  String get troubleshootLogsDownloadFailed;

  String get commonSaved;

  String get modeServerFeature1;

  String get modeServerFeature1Body;

  String get modeServerFeature2;

  String get modeServerFeature2Body;

  String get modeServerFeature3;

  String get modeServerFeature3Body;

  String get modeServerFeature4;

  String get modeServerFeature4Body;

  String get onboardingTipServer1;

  String get onboardingTipServer2;

  String get onboardingTipServer3;

  String get serverRetry;

  String get serverRetryPort1053;

  String get serverStart;

  String get serverStarting;

  String get serverStop;

  String get serverListening;

  String get serverStopped;

  String get serverRootMode;

  String get serverNonRootMode;

  String serverClientHint(int port);

  String get serverQueries;

  String get serverBlocked;

  String get serverBlockRate;

  String get serverCacheHit;

  String get serverAverageLatency;

  String get serverAverageLatencyHint;

  String get serverFilter;

  String get serverFilterOn;

  String get serverFilterOff;

  String get serverRecentQueries;

  String get serverNoQueries;

  String get serverViewAll;

  String get serverTabHome;

  String get serverTabHub;

  String get serverTabLogs;

  String get serverHubTitle;

  String get serverHubDataPlane;

  String get serverHubSystem;

  String serverHubUpstreamSummary(int count, String mode);

  String serverHubFilterSummary(String state, int count);

  String serverHubCacheSummary(int count, String mode);

  String serverHubLogSummary(int days, String file);

  String get serverHubLogFileOn;

  String get serverHubLogFileOff;

  String serverHubSettingsSummary(String mode);

  String get serverUpstream;

  String get serverUpstreamTitle;

  String get serverUpstreamHubHint;

  String get serverFilterTitle;

  String get serverFilterHubHint;

  String get serverCacheTitle;

  String get serverCacheHubHint;

  String get serverQueryLogTitle;

  String get serverQueryLogHubHint;

  String get serverSettingsTitle;

  String get serverSettingsHubHint;

  String get serverAppearance;

  String get serverAppearanceHint;

  String get serverAbout;

  String get serverAboutHint;

  String get serverLogsTitle;

  String get serverLogClear;

  String get serverLogClearTitle;

  String get serverLogClearBody;

  String get serverLogCleared;

  String serverLogPage(int page, int pages);

  String get serverLogAll;

  String get serverLogBlocked;

  String get serverLogCached;

  String get serverLogError;

  String get serverLogSearchDomain;

  String get serverLogSearchClient;

  String get serverLogSearch;

  String get serverLogEmpty;

  String get serverLogEmptyBody;

  String get serverLogNoMatchTitle;

  String get serverLogNoMatchBody;

  String get serverLogStoppedTitle;

  String get serverLogStoppedBody;

  String get serverLogResults;

  String get serverLogFilterClient;

  String get serverLogClientAll;

  String get serverLogClientEmpty;

  String serverLogClientFiltered(String client);

  String get serverLogTime;

  String get serverLogStatus;

  String get serverLogType;

  String get serverLogClient;

  String get serverLogProtocol;

  String get serverLogDuration;

  String get serverLogCache;

  String get serverLogRcode;

  String get serverLogTtl;

  String get serverLogUpstream;

  String get serverLogRule;

  String get serverLogRuleReason;

  String get serverLogErrorField;

  String serverLogDays(int days);

  String get serverUpstreamAdd;

  String get serverUpstreamMode;

  String get serverUpstreamScheduling;

  String get serverUpstreamProviders;

  String get serverUpstreamRequired;

  String get serverUpstreamDelete;

  String serverUpstreamDeleteBody(String id);

  String get serverUpstreamDuplicate;

  String get serverUpstreamSaved;

  String get serverUpstreamProviderNote;

  String get serverUpstreamModeNote;

  String get serverUpstreamBootstrap;

  String get serverBootstrapSummary;

  String get serverBootstrapServers;

  String serverBootstrapServerCount(int count);

  String get serverBootstrapDefault;

  String get serverBootstrapNote;

  String get serverModeSingle;

  String get serverModeSingleDesc;

  String get serverModeParallel;

  String get serverModeParallelDesc;

  String get serverModeSmart;

  String get serverModeSmartDesc;

  String get serverModePrimaryBackup;

  String get serverModePrimaryBackupDesc;

  String get serverFilterEnabled;

  String get serverFilterEnabledBody;

  String get serverFilterResponse;

  String get serverFilterResponseBody;

  String get serverFilterState;

  String get serverFilterBlockMode;

  String get serverFilterSource;

  String serverFilterCustomCount(int count);

  String serverFilterSubscriptionCount(int count);

  String get serverFilterTestTitle;

  String get serverFilterTestEntryBody;

  String get serverBlockNullIp;

  String get serverBlockNxdomain;

  String get serverBlockRefused;

  String get serverBlockAddresses;

  String get serverBlockingIPv4;

  String get serverBlockingIPv6;

  String get serverCustomRules;

  String get serverCustomRulesContent;

  String get serverCustomRulesHint;

  String get serverCustomRulesNote;

  String get serverSubscriptions;

  String get serverSubscriptionList;

  String get serverSubscriptionEmpty;

  String get serverSubscriptionAdd;

  String get serverSubscriptionAddTitle;

  String get serverSubscriptionDelete;

  String serverSubscriptionDeleteBody(String name);

  String get serverSubscriptionRefresh;

  String get serverSubscriptionError;

  String get serverSubscriptionRefreshed;

  String serverSubscriptionRules(int count);

  String get serverSubscriptionNote;

  String get serverSubscriptionName;

  String get serverSubscriptionUrl;

  String get serverSubscriptionRequired;

  String get serverCheckTitle;

  String get serverCheckDomain;

  String get serverCheckDomainRequired;

  String get serverCheckAction;

  String get serverCheckChecking;

  String get serverCheckResult;

  String get serverCheckBlocked;

  String get serverCheckAllowed;

  String get serverFilterSaved;

  String get serverCacheEnabled;

  String get serverCacheEnabledBody;

  String get serverCacheState;

  String get serverCacheCapacity;

  String get serverCacheEntries;

  String get serverCacheMode;

  String get serverCacheLimit;

  String get serverCacheFixed;

  String get serverCacheTtl;

  String get serverCacheMaxTtl;

  String get serverCacheFixedTtl;

  String get serverCacheMinTtl;

  String get serverCacheMinTtlBody;

  String get serverCacheMinTtlValue;

  String get serverCacheStale;

  String get serverCacheStaleBody;

  String get serverCacheNegative;

  String get serverCacheOptimistic;

  String get serverCachePrefetch;

  String get serverCacheFooter;

  String get serverCacheSaved;

  String get serverCacheAdvanced;

  String get serverCacheBehavior;

  String get serverCacheAdvancedSummary;

  String get serverCacheAdvancedTtl;

  String get serverCacheFallback;

  String get serverCachePerformance;

  String get serverQueryLogEnabled;

  String get serverQueryLogContent;

  String get serverQueryLogEnabledBody;

  String get serverQueryLogFile;

  String get serverQueryLogFileBody;

  String get serverQueryLogClients;

  String get serverQueryLogClientsBody;

  String get serverQueryLogRetention;

  String get serverQueryLogRetentionNote;

  String get serverQueryLogMemory;

  String get serverQueryLogMemoryEntries;

  String get serverQueryLogMemoryNote;

  String get serverQueryLogSaved;

  String get serverNumberInvalid;

  String get serverSettingsRuntime;

  String get serverRunning;

  String get serverSettingsSwitchModeBody;

  String get serverSettingsListen;

  String get serverSettingsRoot;

  String get serverSettingsRootRunning;

  String get serverSettingsRootBody;

  String get serverSettingsRootNote;

  String get serverPort;

  String get serverPortFixed;

  String get serverSettingsProbeRoot;

  String get serverSettingsProbeRootBody;

  String get serverSettingsStorage;

  String get serverSettingsDataDir;

  String get serverSettingsDataDirBody;

  String get serverRootAvailable;

  String serverRootUnavailable(String message);

  String get serverRootDenied;

  String get serverStatusTitle;

  String get serverUptime;

  String get serverOverviewTitle;

  String get serverLast24Hours;

  String get serverTrafficTitle;

  String get serverTrafficPeak;

  String get serverTrafficAverage;

  String get serverPerHour;

  String get serverBlockingTitle;

  String get serverAllowed;

  String get serverTopBlocked;

  String get serverCacheEfficiency;

  String get serverCacheForwarded;

  String get serverCacheErrors;

  String get serverTopDomainsTitle;

  String get serverTopClientsTitle;

  String get serverQuickActions;

  String get serverNoStatistics;

  String get serverNoTraffic;

  String get serverTrafficStopped;

  String get serverNoRanking;

  String serverCacheEntriesShort(int count);

  String serverUpstreamShort(int count);
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'zh':
      return AppL10nZh();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
