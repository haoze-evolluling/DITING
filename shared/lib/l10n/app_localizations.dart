import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @ruleTestTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则测试'**
  String get ruleTestTitle;

  /// No description provided for @ruleTestEnterSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'输入域名查看为何被拦截或放行'**
  String get ruleTestEnterSubtitle;

  /// No description provided for @ruleTestIntro.
  ///
  /// In zh, this message translates to:
  /// **'输入域名，立即查看判定结果、命中规则与改写结果。判定逻辑与引擎完全一致。'**
  String get ruleTestIntro;

  /// No description provided for @ruleTestDomainLabel.
  ///
  /// In zh, this message translates to:
  /// **'域名'**
  String get ruleTestDomainLabel;

  /// No description provided for @ruleTestDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'例如 ads.example.com'**
  String get ruleTestDomainHint;

  /// No description provided for @ruleTestQtype.
  ///
  /// In zh, this message translates to:
  /// **'查询类型'**
  String get ruleTestQtype;

  /// No description provided for @ruleTestRun.
  ///
  /// In zh, this message translates to:
  /// **'开始测试'**
  String get ruleTestRun;

  /// No description provided for @ruleTestResultTitle.
  ///
  /// In zh, this message translates to:
  /// **'判定结果'**
  String get ruleTestResultTitle;

  /// No description provided for @ruleTestActionBlock.
  ///
  /// In zh, this message translates to:
  /// **'拦截'**
  String get ruleTestActionBlock;

  /// No description provided for @ruleTestActionAllow.
  ///
  /// In zh, this message translates to:
  /// **'白名单放行'**
  String get ruleTestActionAllow;

  /// No description provided for @ruleTestActionPass.
  ///
  /// In zh, this message translates to:
  /// **'放行'**
  String get ruleTestActionPass;

  /// No description provided for @ruleTestMatchedRule.
  ///
  /// In zh, this message translates to:
  /// **'命中规则'**
  String get ruleTestMatchedRule;

  /// No description provided for @ruleTestReason.
  ///
  /// In zh, this message translates to:
  /// **'原因'**
  String get ruleTestReason;

  /// No description provided for @ruleTestRewriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'改写结果'**
  String get ruleTestRewriteTitle;

  /// No description provided for @ruleTestNoRewrite.
  ///
  /// In zh, this message translates to:
  /// **'无改写'**
  String get ruleTestNoRewrite;

  /// No description provided for @ruleTestInvalidDomain.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效域名'**
  String get ruleTestInvalidDomain;

  /// No description provided for @ruleTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'规则测试失败，请稍后重试'**
  String get ruleTestFailed;

  /// No description provided for @ruleTestEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'测试结果会显示在这里'**
  String get ruleTestEmptyHint;

  /// No description provided for @subscriptionHealthOk.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get subscriptionHealthOk;

  /// No description provided for @subscriptionHealthUnchanged.
  ///
  /// In zh, this message translates to:
  /// **'无变化'**
  String get subscriptionHealthUnchanged;

  /// No description provided for @subscriptionHealthCached.
  ///
  /// In zh, this message translates to:
  /// **'使用缓存'**
  String get subscriptionHealthCached;

  /// No description provided for @subscriptionHealthFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败'**
  String get subscriptionHealthFailed;

  /// No description provided for @blockPauseTitle.
  ///
  /// In zh, this message translates to:
  /// **'临时暂停'**
  String get blockPauseTitle;

  /// No description provided for @blockPauseEntrySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'临时跳过拦截 / 仅白名单'**
  String get blockPauseEntrySubtitle;

  /// No description provided for @blockPauseIntro.
  ///
  /// In zh, this message translates to:
  /// **'暂停后跳过全部拦截，DNS 仍照常解析，到期自动恢复。仅白名单模式只放行显式允许的域名。'**
  String get blockPauseIntro;

  /// No description provided for @blockPauseRunningLabel.
  ///
  /// In zh, this message translates to:
  /// **'暂停中，剩余'**
  String get blockPauseRunningLabel;

  /// No description provided for @blockPauseInactive.
  ///
  /// In zh, this message translates to:
  /// **'当前未暂停，拦截正常生效'**
  String get blockPauseInactive;

  /// No description provided for @blockPauseResume.
  ///
  /// In zh, this message translates to:
  /// **'立即恢复'**
  String get blockPauseResume;

  /// No description provided for @blockPausePresetButton.
  ///
  /// In zh, this message translates to:
  /// **'暂停 {minutes} 分钟'**
  String blockPausePresetButton(int minutes);

  /// No description provided for @blockPauseAllowlistTitle.
  ///
  /// In zh, this message translates to:
  /// **'仅白名单模式'**
  String get blockPauseAllowlistTitle;

  /// No description provided for @blockPauseAllowlistSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'只放行显式允许的域名，其余全部拦截'**
  String get blockPauseAllowlistSubtitle;

  /// No description provided for @blockPauseFailed.
  ///
  /// In zh, this message translates to:
  /// **'设置失败，请稍后重试'**
  String get blockPauseFailed;

  /// No description provided for @hitRankingTitle.
  ///
  /// In zh, this message translates to:
  /// **'命中排行'**
  String get hitRankingTitle;

  /// No description provided for @hitRankingEntrySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看被拦截最多的域名与命中原因'**
  String get hitRankingEntrySubtitle;

  /// No description provided for @hitRankingDomains.
  ///
  /// In zh, this message translates to:
  /// **'被拦截最多的域名'**
  String get hitRankingDomains;

  /// No description provided for @hitRankingDomainsFooter.
  ///
  /// In zh, this message translates to:
  /// **'点击域名用规则测试解释其判定'**
  String get hitRankingDomainsFooter;

  /// No description provided for @hitRankingExplainHint.
  ///
  /// In zh, this message translates to:
  /// **'点击查看规则测试'**
  String get hitRankingExplainHint;

  /// No description provided for @hitRankingReasons.
  ///
  /// In zh, this message translates to:
  /// **'命中原因（归因）'**
  String get hitRankingReasons;

  /// No description provided for @hitRankingEmpty.
  ///
  /// In zh, this message translates to:
  /// **'所选时间范围内没有拦截记录'**
  String get hitRankingEmpty;

  /// No description provided for @hitRankingEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'切换时间范围，或先开启规则拦截。'**
  String get hitRankingEmptyBody;

  /// No description provided for @hitRankingLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'命中排行加载失败'**
  String get hitRankingLoadFailed;

  /// No description provided for @hitRankingFooter.
  ///
  /// In zh, this message translates to:
  /// **'统计来自本机 dns_log，按被拦截结果聚合。'**
  String get hitRankingFooter;

  /// No description provided for @hitRankingTotal.
  ///
  /// In zh, this message translates to:
  /// **'共拦截 {count} 次'**
  String hitRankingTotal(int count);

  /// No description provided for @healthTitle.
  ///
  /// In zh, this message translates to:
  /// **'保护健康'**
  String get healthTitle;

  /// No description provided for @healthEntrySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看四维评分与改进建议'**
  String get healthEntrySubtitle;

  /// No description provided for @healthIntro.
  ///
  /// In zh, this message translates to:
  /// **'从权限、DNS、过滤器、缓存四个维度评估保护是否真正生效，并给出下一步建议。'**
  String get healthIntro;

  /// No description provided for @healthIntroShort.
  ///
  /// In zh, this message translates to:
  /// **'四维综合评估保护是否有效'**
  String get healthIntroShort;

  /// No description provided for @healthScoreLabel.
  ///
  /// In zh, this message translates to:
  /// **'健康评分'**
  String get healthScoreLabel;

  /// No description provided for @healthLevelOk.
  ///
  /// In zh, this message translates to:
  /// **'良好'**
  String get healthLevelOk;

  /// No description provided for @healthLevelWarning.
  ///
  /// In zh, this message translates to:
  /// **'注意'**
  String get healthLevelWarning;

  /// No description provided for @healthLevelCritical.
  ///
  /// In zh, this message translates to:
  /// **'需要处理'**
  String get healthLevelCritical;

  /// No description provided for @healthDimensionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'评分维度'**
  String get healthDimensionsTitle;

  /// No description provided for @healthDimPermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get healthDimPermissions;

  /// No description provided for @healthDimDns.
  ///
  /// In zh, this message translates to:
  /// **'DNS'**
  String get healthDimDns;

  /// No description provided for @healthDimFilter.
  ///
  /// In zh, this message translates to:
  /// **'过滤器'**
  String get healthDimFilter;

  /// No description provided for @healthDimCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get healthDimCache;

  /// No description provided for @healthAdviceTitle.
  ///
  /// In zh, this message translates to:
  /// **'建议'**
  String get healthAdviceTitle;

  /// No description provided for @healthAdviceGrantPermissions.
  ///
  /// In zh, this message translates to:
  /// **'授予 VPN / 通知权限，保护才能生效'**
  String get healthAdviceGrantPermissions;

  /// No description provided for @healthAdviceStartProtection.
  ///
  /// In zh, this message translates to:
  /// **'保护未运行，请启动'**
  String get healthAdviceStartProtection;

  /// No description provided for @healthAdviceImportRules.
  ///
  /// In zh, this message translates to:
  /// **'尚未导入规则，拦截不会生效'**
  String get healthAdviceImportRules;

  /// No description provided for @healthAdviceUpdateSubscriptions.
  ///
  /// In zh, this message translates to:
  /// **'有订阅更新失败，请到订阅页重试'**
  String get healthAdviceUpdateSubscriptions;

  /// No description provided for @healthAdviceLowCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中偏低，检查上游或启用缓存'**
  String get healthAdviceLowCache;

  /// No description provided for @healthAdviceNoBlocking.
  ///
  /// In zh, this message translates to:
  /// **'近期没有拦截记录，确认规则已生效'**
  String get healthAdviceNoBlocking;

  /// No description provided for @healthAdviceAllGood.
  ///
  /// In zh, this message translates to:
  /// **'保护状态良好，无需处理'**
  String get healthAdviceAllGood;

  /// No description provided for @healthLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在评估…'**
  String get healthLoading;

  /// No description provided for @healthLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'评估失败，请稍后重试'**
  String get healthLoadFailed;

  /// No description provided for @searchTitle.
  ///
  /// In zh, this message translates to:
  /// **'全局搜索'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索功能、设置与命令'**
  String get searchHint;

  /// No description provided for @searchEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词开始搜索'**
  String get searchEmptyTitle;

  /// No description provided for @searchEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'可搜索全部功能中心页面与常用命令'**
  String get searchEmptyBody;

  /// No description provided for @searchNoResults.
  ///
  /// In zh, this message translates to:
  /// **'没有找到匹配项'**
  String get searchNoResults;

  /// No description provided for @searchGroupTools.
  ///
  /// In zh, this message translates to:
  /// **'常用命令'**
  String get searchGroupTools;

  /// No description provided for @flowTitle.
  ///
  /// In zh, this message translates to:
  /// **'实时连接'**
  String get flowTitle;

  /// No description provided for @flowEntrySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按应用查看实时连接与远端'**
  String get flowEntrySubtitle;

  /// No description provided for @flowRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get flowRefresh;

  /// No description provided for @flowEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'保护运行且有流量时，这里按应用→域名→远端显示实时连接。'**
  String get flowEmptyBody;

  /// No description provided for @flowStatusActive.
  ///
  /// In zh, this message translates to:
  /// **'活跃'**
  String get flowStatusActive;

  /// No description provided for @flowStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'已拦截'**
  String get flowStatusFailed;

  /// No description provided for @flowStatusClosed.
  ///
  /// In zh, this message translates to:
  /// **'已结束'**
  String get flowStatusClosed;

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'谛听 DITING'**
  String get appTitle;

  /// No description provided for @uiBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get uiBack;

  /// No description provided for @uiCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get uiCancel;

  /// No description provided for @uiClearSearch.
  ///
  /// In zh, this message translates to:
  /// **'清除搜索'**
  String get uiClearSearch;

  /// No description provided for @uiClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get uiClose;

  /// No description provided for @uiHidePassword.
  ///
  /// In zh, this message translates to:
  /// **'隐藏密码'**
  String get uiHidePassword;

  /// No description provided for @uiMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get uiMore;

  /// No description provided for @uiNoSearchResults.
  ///
  /// In zh, this message translates to:
  /// **'无搜索结果'**
  String get uiNoSearchResults;

  /// No description provided for @uiReset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get uiReset;

  /// No description provided for @uiSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get uiSearch;

  /// No description provided for @uiShowLess.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get uiShowLess;

  /// No description provided for @uiShowMore.
  ///
  /// In zh, this message translates to:
  /// **'展开'**
  String get uiShowMore;

  /// No description provided for @uiShowPassword.
  ///
  /// In zh, this message translates to:
  /// **'显示密码'**
  String get uiShowPassword;

  /// No description provided for @uiSort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get uiSort;

  /// No description provided for @uiSubmit.
  ///
  /// In zh, this message translates to:
  /// **'提交'**
  String get uiSubmit;

  /// No description provided for @languageTitle.
  ///
  /// In zh, this message translates to:
  /// **'语言设置'**
  String get languageTitle;

  /// No description provided for @languageInterfaceSection.
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get languageInterfaceSection;

  /// No description provided for @languageInterfaceFooter.
  ///
  /// In zh, this message translates to:
  /// **'选择应用界面语言。「跟随系统」会跟随设备语言，非中文或英文的系统显示中文。'**
  String get languageInterfaceFooter;

  /// No description provided for @languageChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @commonFollowSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get commonFollowSystem;

  /// No description provided for @commonSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get commonSelectAll;

  /// No description provided for @commonClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get commonClear;

  /// No description provided for @commonInvertSelection.
  ///
  /// In zh, this message translates to:
  /// **'反选'**
  String get commonInvertSelection;

  /// No description provided for @commonFilter.
  ///
  /// In zh, this message translates to:
  /// **'过滤'**
  String get commonFilter;

  /// No description provided for @commonSort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get commonSort;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonDiscard.
  ///
  /// In zh, this message translates to:
  /// **'不保存'**
  String get commonDiscard;

  /// No description provided for @commonSaveChangesTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存更改？'**
  String get commonSaveChangesTitle;

  /// No description provided for @commonSaveChangesMessage.
  ///
  /// In zh, this message translates to:
  /// **'你的选择还没保存。保存后离开，还是放弃这些修改？'**
  String get commonSaveChangesMessage;

  /// No description provided for @commonSaveChangesMessageFor.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」的选择还没保存。保存后离开，还是放弃这些修改？'**
  String commonSaveChangesMessageFor(String name);

  /// No description provided for @commonGrantPermission.
  ///
  /// In zh, this message translates to:
  /// **'去授权'**
  String get commonGrantPermission;

  /// No description provided for @palettePurple.
  ///
  /// In zh, this message translates to:
  /// **'鸢尾紫'**
  String get palettePurple;

  /// No description provided for @paletteBlue.
  ///
  /// In zh, this message translates to:
  /// **'睡莲蓝'**
  String get paletteBlue;

  /// No description provided for @paletteCyan.
  ///
  /// In zh, this message translates to:
  /// **'池水青'**
  String get paletteCyan;

  /// No description provided for @paletteGreen.
  ///
  /// In zh, this message translates to:
  /// **'柳叶绿'**
  String get paletteGreen;

  /// No description provided for @paletteOrange.
  ///
  /// In zh, this message translates to:
  /// **'暮光赭'**
  String get paletteOrange;

  /// No description provided for @paletteRed.
  ///
  /// In zh, this message translates to:
  /// **'罂粟红'**
  String get paletteRed;

  /// No description provided for @palettePink.
  ///
  /// In zh, this message translates to:
  /// **'暮霞粉'**
  String get palettePink;

  /// No description provided for @paletteGold.
  ///
  /// In zh, this message translates to:
  /// **'麦穗金'**
  String get paletteGold;

  /// No description provided for @themeModeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色模式'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色模式'**
  String get themeModeDark;

  /// No description provided for @appListUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'读不到应用列表'**
  String get appListUnavailable;

  /// No description provided for @appListFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部应用'**
  String get appListFilterAll;

  /// No description provided for @appListFilterSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统应用'**
  String get appListFilterSystem;

  /// No description provided for @appListFilterUser.
  ///
  /// In zh, this message translates to:
  /// **'用户应用'**
  String get appListFilterUser;

  /// No description provided for @appListFilterSelected.
  ///
  /// In zh, this message translates to:
  /// **'已勾选应用'**
  String get appListFilterSelected;

  /// No description provided for @appListSortLabelAsc.
  ///
  /// In zh, this message translates to:
  /// **'应用名称 A-Z'**
  String get appListSortLabelAsc;

  /// No description provided for @appListSortLabelDesc.
  ///
  /// In zh, this message translates to:
  /// **'应用名称 Z-A'**
  String get appListSortLabelDesc;

  /// No description provided for @appListSortPackageAsc.
  ///
  /// In zh, this message translates to:
  /// **'包名 A-Z'**
  String get appListSortPackageAsc;

  /// No description provided for @appListSortPackageDesc.
  ///
  /// In zh, this message translates to:
  /// **'包名 Z-A'**
  String get appListSortPackageDesc;

  /// No description provided for @appListNotRegistered.
  ///
  /// In zh, this message translates to:
  /// **'未注册'**
  String get appListNotRegistered;

  /// No description provided for @appListChannelUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'应用列表通道不可用：{detail}'**
  String appListChannelUnavailable(String detail);

  /// No description provided for @appListReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取应用列表失败：{detail}'**
  String appListReadFailed(String detail);

  /// No description provided for @appListReadFailedCode.
  ///
  /// In zh, this message translates to:
  /// **'读取应用列表失败（{code}）'**
  String appListReadFailedCode(String code);

  /// No description provided for @dbWriteUnhealthy.
  ///
  /// In zh, this message translates to:
  /// **'日志写入异常：已丢弃 {dropped} 条、打开失败 {failures} 次，可在「故障排查」查看详情'**
  String dbWriteUnhealthy(int dropped, int failures);

  /// No description provided for @agreementDeclinedTitle.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝使用须知'**
  String get agreementDeclinedTitle;

  /// No description provided for @agreementDeclinedMessage.
  ///
  /// In zh, this message translates to:
  /// **'未同意使用须知与免责声明，无法继续使用谛听。你可以直接退出应用，或重新查看条款后再决定。'**
  String get agreementDeclinedMessage;

  /// No description provided for @agreementReviewAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新查看'**
  String get agreementReviewAgain;

  /// No description provided for @agreementTitle.
  ///
  /// In zh, this message translates to:
  /// **'使用须知与免责声明'**
  String get agreementTitle;

  /// No description provided for @agreementDecline.
  ///
  /// In zh, this message translates to:
  /// **'不同意并退出'**
  String get agreementDecline;

  /// No description provided for @agreementAccept.
  ///
  /// In zh, this message translates to:
  /// **'同意并继续'**
  String get agreementAccept;

  /// No description provided for @agreementMessage.
  ///
  /// In zh, this message translates to:
  /// **'软件说明\n谛听是一款专注于本地 DNS 解析优化与网络规则过滤的开源工具。提供三种工作模式：普通模式（全隧道深度管控）、极速模式（Go 引擎 + DNS 窄路由）与独立服务器模式（局域网免 VPN 服务）。本软件完全在设备本地闭环运行，无任何远程数据上传与隐私追踪。\n\n运行机制与注意事项\n普通模式与极速模式依赖 Android 本地 VPN 接口接管 DNS 解析，不连接任何远程 VPN 服务器；独立服务器模式无需 VPN 权限，直接监听本地 1053 端口供局域网设备接入。规则与日志完整保存在本机，启用高级扩展功能前请了解其具体影响。\n\n免责条款\n本软件按现状提供。使用者须遵守相关法律法规，自行确认规则与上游解析来源的合法性及安全性。严禁将本软件用于任何违法用途；使用者因自行配置或使用本软件所产生的后果由使用者自行承担。'**
  String get agreementMessage;

  /// No description provided for @homeProviderSingleLabel.
  ///
  /// In zh, this message translates to:
  /// **'解析服务商'**
  String get homeProviderSingleLabel;

  /// No description provided for @homeProviderRaceLabel.
  ///
  /// In zh, this message translates to:
  /// **'竞速服务商'**
  String get homeProviderRaceLabel;

  /// No description provided for @homeChartEmptyLabel.
  ///
  /// In zh, this message translates to:
  /// **'还没有采到样本'**
  String get homeChartEmptyLabel;

  /// No description provided for @durationHours.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时'**
  String durationHours(int hours);

  /// No description provided for @durationMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String durationMinutes(int minutes);

  /// No description provided for @durationSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String durationSeconds(int seconds);

  /// No description provided for @dashboardDetailTooltip.
  ///
  /// In zh, this message translates to:
  /// **'详情'**
  String get dashboardDetailTooltip;

  /// No description provided for @dashboardEmptyLabel.
  ///
  /// In zh, this message translates to:
  /// **'仪表盘还没有卡片'**
  String get dashboardEmptyLabel;

  /// No description provided for @dashboardEmptyDescription.
  ///
  /// In zh, this message translates to:
  /// **'进入编辑模式，从「添加卡片」里挑几个放上来。'**
  String get dashboardEmptyDescription;

  /// No description provided for @dashboardEnterEditMode.
  ///
  /// In zh, this message translates to:
  /// **'进入编辑模式'**
  String get dashboardEnterEditMode;

  /// No description provided for @dashboardEditHint.
  ///
  /// In zh, this message translates to:
  /// **'拖动手柄排序，点右上角移除；改完点右上角「完成」。'**
  String get dashboardEditHint;

  /// No description provided for @dashboardAllRemovedLabel.
  ///
  /// In zh, this message translates to:
  /// **'卡片都移除了'**
  String get dashboardAllRemovedLabel;

  /// No description provided for @dashboardAllRemovedDescription.
  ///
  /// In zh, this message translates to:
  /// **'点下面的「添加卡片」挑一个。'**
  String get dashboardAllRemovedDescription;

  /// No description provided for @dashboardAddCard.
  ///
  /// In zh, this message translates to:
  /// **'添加卡片'**
  String get dashboardAddCard;

  /// No description provided for @providerSheetSingleTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择解析服务商'**
  String get providerSheetSingleTitle;

  /// No description provided for @providerSheetRaceTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择竞速服务商'**
  String get providerSheetRaceTitle;

  /// No description provided for @providerSheetSingleOptions.
  ///
  /// In zh, this message translates to:
  /// **'可选服务商'**
  String get providerSheetSingleOptions;

  /// No description provided for @providerSheetRaceMinimum.
  ///
  /// In zh, this message translates to:
  /// **'至少选 2 个'**
  String get providerSheetRaceMinimum;

  /// No description provided for @providerSheetManage.
  ///
  /// In zh, this message translates to:
  /// **'管理服务...'**
  String get providerSheetManage;

  /// No description provided for @providerSheetVisibility.
  ///
  /// In zh, this message translates to:
  /// **'服务显示...'**
  String get providerSheetVisibility;

  /// No description provided for @providerSheetSingleFooter.
  ///
  /// In zh, this message translates to:
  /// **'延迟取自上一次解析的健康记录，不是实时值。'**
  String get providerSheetSingleFooter;

  /// No description provided for @providerSheetRaceFooter.
  ///
  /// In zh, this message translates to:
  /// **'竞速模式下每个查询会并发发往所有选中服务商。'**
  String get providerSheetRaceFooter;

  /// No description provided for @powerButtonStop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get powerButtonStop;

  /// No description provided for @powerButtonStart.
  ///
  /// In zh, this message translates to:
  /// **'开启'**
  String get powerButtonStart;

  /// No description provided for @powerButtonStarting.
  ///
  /// In zh, this message translates to:
  /// **'启动中'**
  String get powerButtonStarting;

  /// No description provided for @homeEditDashboard.
  ///
  /// In zh, this message translates to:
  /// **'编辑仪表盘'**
  String get homeEditDashboard;

  /// No description provided for @homeDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get homeDone;

  /// No description provided for @homeSwitchWorkMode.
  ///
  /// In zh, this message translates to:
  /// **'切换工作模式'**
  String get homeSwitchWorkMode;

  /// No description provided for @homeTitleNormal.
  ///
  /// In zh, this message translates to:
  /// **'谛听 · 普通'**
  String get homeTitleNormal;

  /// No description provided for @homeTitleServer.
  ///
  /// In zh, this message translates to:
  /// **'谛听 · 服务器'**
  String get homeTitleServer;

  /// No description provided for @homeTitleExpress.
  ///
  /// In zh, this message translates to:
  /// **'谛听 · 极速'**
  String get homeTitleExpress;

  /// No description provided for @logRequestsOverview.
  ///
  /// In zh, this message translates to:
  /// **'请求概览'**
  String get logRequestsOverview;

  /// No description provided for @logTodayRequests.
  ///
  /// In zh, this message translates to:
  /// **'今日请求'**
  String get logTodayRequests;

  /// No description provided for @logPassed.
  ///
  /// In zh, this message translates to:
  /// **'通过'**
  String get logPassed;

  /// No description provided for @logFiltered.
  ///
  /// In zh, this message translates to:
  /// **'过滤'**
  String get logFiltered;

  /// No description provided for @logCacheHits.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中'**
  String get logCacheHits;

  /// No description provided for @logHighlights.
  ///
  /// In zh, this message translates to:
  /// **'重点记录'**
  String get logHighlights;

  /// No description provided for @logBlocked.
  ///
  /// In zh, this message translates to:
  /// **'过滤拦截'**
  String get logBlocked;

  /// No description provided for @logFailed.
  ///
  /// In zh, this message translates to:
  /// **'异常失败'**
  String get logFailed;

  /// No description provided for @logBypassed.
  ///
  /// In zh, this message translates to:
  /// **'旁路直连'**
  String get logBypassed;

  /// No description provided for @logOffModeTitle.
  ///
  /// In zh, this message translates to:
  /// **'解析服务概况'**
  String get logOffModeTitle;

  /// No description provided for @logCacheEntries.
  ///
  /// In zh, this message translates to:
  /// **'有效缓存'**
  String get logCacheEntries;

  /// No description provided for @logCacheHitsTotal.
  ///
  /// In zh, this message translates to:
  /// **'累计缓存命中'**
  String get logCacheHitsTotal;

  /// No description provided for @logRaceRequests.
  ///
  /// In zh, this message translates to:
  /// **'并发竞速请求'**
  String get logRaceRequests;

  /// No description provided for @logBootstrapAttempts.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 尝试'**
  String get logBootstrapAttempts;

  /// No description provided for @logRecentRequests.
  ///
  /// In zh, this message translates to:
  /// **'最近请求'**
  String get logRecentRequests;

  /// No description provided for @logRecentRequestsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无请求日志'**
  String get logRecentRequestsEmpty;

  /// No description provided for @logRecentBlocked.
  ///
  /// In zh, this message translates to:
  /// **'最近拦截与错误'**
  String get logRecentBlocked;

  /// No description provided for @logRecentBlockedEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无拦截或错误记录'**
  String get logRecentBlockedEmpty;

  /// No description provided for @logCacheHotspots.
  ///
  /// In zh, this message translates to:
  /// **'缓存热点'**
  String get logCacheHotspots;

  /// No description provided for @logCacheHotspotsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无有效缓存'**
  String get logCacheHotspotsEmpty;

  /// No description provided for @logExpiresIn.
  ///
  /// In zh, this message translates to:
  /// **'{duration} 后过期'**
  String logExpiresIn(String duration);

  /// No description provided for @logTimes.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String logTimes(String count);

  /// No description provided for @logRaceWinners.
  ///
  /// In zh, this message translates to:
  /// **'竞速胜出'**
  String get logRaceWinners;

  /// No description provided for @logRaceWinnersEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无竞速数据'**
  String get logRaceWinnersEmpty;

  /// No description provided for @logAverageWinLatency.
  ///
  /// In zh, this message translates to:
  /// **'平均胜出耗时 {latency}'**
  String logAverageWinLatency(String latency);

  /// No description provided for @logBootstrapDnsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无 Bootstrap 数据'**
  String get logBootstrapDnsEmpty;

  /// No description provided for @logBootstrapRow.
  ///
  /// In zh, this message translates to:
  /// **'{ip} · 成功 {percent} · {latency}'**
  String logBootstrapRow(String ip, String latency, String percent);

  /// No description provided for @logRuleBlocks.
  ///
  /// In zh, this message translates to:
  /// **'规则拦截'**
  String get logRuleBlocks;

  /// No description provided for @logRuleBlocksEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无规则拦截数据'**
  String get logRuleBlocksEmpty;

  /// No description provided for @logShareRow.
  ///
  /// In zh, this message translates to:
  /// **'{status} · 占全部请求 {percent}'**
  String logShareRow(String percent, String status);

  /// No description provided for @logPrivacyMode.
  ///
  /// In zh, this message translates to:
  /// **'隐私模式保护中'**
  String get logPrivacyMode;

  /// No description provided for @logLoggingOff.
  ///
  /// In zh, this message translates to:
  /// **'日志已关闭'**
  String get logLoggingOff;

  /// No description provided for @logPrivacyModeBody.
  ///
  /// In zh, this message translates to:
  /// **'重新开启日志后，仪表盘将从新产生的请求开始统计。当前各类解析服务与缓存热点均正常工作。'**
  String get logPrivacyModeBody;

  /// No description provided for @logPerfTitle.
  ///
  /// In zh, this message translates to:
  /// **'解析效能概况'**
  String get logPerfTitle;

  /// No description provided for @logTodayStats.
  ///
  /// In zh, this message translates to:
  /// **'今日统计'**
  String get logTodayStats;

  /// No description provided for @logAverageLatency.
  ///
  /// In zh, this message translates to:
  /// **'平均解析耗时'**
  String get logAverageLatency;

  /// No description provided for @logNoTimingSamples.
  ///
  /// In zh, this message translates to:
  /// **'— · 今日暂无计时样本'**
  String get logNoTimingSamples;

  /// No description provided for @logSampleValue.
  ///
  /// In zh, this message translates to:
  /// **'{value} · {count} 个样本'**
  String logSampleValue(String count, String value);

  /// No description provided for @logCacheHitRate.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中率'**
  String get logCacheHitRate;

  /// No description provided for @logCacheHitRateValue.
  ///
  /// In zh, this message translates to:
  /// **'{percent} · 分母为通过 + 失败'**
  String logCacheHitRateValue(String percent);

  /// No description provided for @logRaceSuccessRate.
  ///
  /// In zh, this message translates to:
  /// **'竞速成功率'**
  String get logRaceSuccessRate;

  /// No description provided for @logBootstrapSuccessRate.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 成功率'**
  String get logBootstrapSuccessRate;

  /// No description provided for @logRateValue.
  ///
  /// In zh, this message translates to:
  /// **'{percent} · {count} 次 · {latency}'**
  String logRateValue(String count, String latency, String percent);

  /// No description provided for @dashboardRestoreDefaults.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get dashboardRestoreDefaults;

  /// No description provided for @dashboardAllCardsAdded.
  ///
  /// In zh, this message translates to:
  /// **'卡片都放上来了'**
  String get dashboardAllCardsAdded;

  /// No description provided for @dashboardAllCardsAddedDescription.
  ///
  /// In zh, this message translates to:
  /// **'想减少卡片，请回到编辑模式点卡片右上角的移除。'**
  String get dashboardAllCardsAddedDescription;

  /// No description provided for @dashboardAvailableCards.
  ///
  /// In zh, this message translates to:
  /// **'可添加的卡片'**
  String get dashboardAvailableCards;

  /// No description provided for @dashboardOrderHint.
  ///
  /// In zh, this message translates to:
  /// **'卡片顺序可在编辑模式下拖拽调整。'**
  String get dashboardOrderHint;

  /// No description provided for @dashboardCardProviderDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前解析服务商，点开即可切换或调整竞速列表'**
  String get dashboardCardProviderDescription;

  /// No description provided for @dashboardCardResolutionDescription.
  ///
  /// In zh, this message translates to:
  /// **'解析模式选择、一句话说明与当前生效的 DNS 地址'**
  String get dashboardCardResolutionDescription;

  /// No description provided for @dashboardCardStatusDescription.
  ///
  /// In zh, this message translates to:
  /// **'内核状态、运行时长、当前服务商与今日查询'**
  String get dashboardCardStatusDescription;

  /// No description provided for @dashboardCardSpeedDescription.
  ///
  /// In zh, this message translates to:
  /// **'上下行实时速率曲线与今日累计流量'**
  String get dashboardCardSpeedDescription;

  /// No description provided for @dashboardCardSiteLatencyDescription.
  ///
  /// In zh, this message translates to:
  /// **'自定义 4 个站点的实测延迟，详情页可按分类测速'**
  String get dashboardCardSiteLatencyDescription;

  /// No description provided for @dashboardCardMemoryDescription.
  ///
  /// In zh, this message translates to:
  /// **'本进程 PSS 与 Java / 原生堆构成'**
  String get dashboardCardMemoryDescription;

  /// No description provided for @dashboardCardIntranetDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前局域网地址、监听状态与复制入口'**
  String get dashboardCardIntranetDescription;

  /// No description provided for @intranetIpTitle.
  ///
  /// In zh, this message translates to:
  /// **'内网 IP'**
  String get intranetIpTitle;

  /// No description provided for @intranetCopyAddress.
  ///
  /// In zh, this message translates to:
  /// **'复制地址'**
  String get intranetCopyAddress;

  /// No description provided for @intranetReading.
  ///
  /// In zh, this message translates to:
  /// **'读取中…'**
  String get intranetReading;

  /// No description provided for @intranetNoActiveNetwork.
  ///
  /// In zh, this message translates to:
  /// **'无活动网络'**
  String get intranetNoActiveNetwork;

  /// No description provided for @intranetLanAccess.
  ///
  /// In zh, this message translates to:
  /// **'局域网接入'**
  String get intranetLanAccess;

  /// No description provided for @intranetConnectHint.
  ///
  /// In zh, this message translates to:
  /// **'连上 Wi-Fi 或以太网后这里会显示可用地址'**
  String get intranetConnectHint;

  /// No description provided for @memoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'内存信息'**
  String get memoryTitle;

  /// No description provided for @memoryJavaHeap.
  ///
  /// In zh, this message translates to:
  /// **'Java 堆'**
  String get memoryJavaHeap;

  /// No description provided for @memoryNativeHeap.
  ///
  /// In zh, this message translates to:
  /// **'原生堆'**
  String get memoryNativeHeap;

  /// No description provided for @memorySystemAvailable.
  ///
  /// In zh, this message translates to:
  /// **'整机可用'**
  String get memorySystemAvailable;

  /// No description provided for @speedTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络速度'**
  String get speedTitle;

  /// No description provided for @speedUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get speedUpload;

  /// No description provided for @speedDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get speedDownload;

  /// No description provided for @speedExpressNoStats.
  ///
  /// In zh, this message translates to:
  /// **'极速模式不统计'**
  String get speedExpressNoStats;

  /// No description provided for @speedNoChannel.
  ///
  /// In zh, this message translates to:
  /// **'当前环境无速率通道'**
  String get speedNoChannel;

  /// No description provided for @resolutionModeTitle.
  ///
  /// In zh, this message translates to:
  /// **'解析模式'**
  String get resolutionModeTitle;

  /// No description provided for @resolutionNoProvider.
  ///
  /// In zh, this message translates to:
  /// **'未选择服务商'**
  String get resolutionNoProvider;

  /// No description provided for @resolutionSingleSummary.
  ///
  /// In zh, this message translates to:
  /// **'只用当前选中的服务商，最快但可用性取决于它。'**
  String get resolutionSingleSummary;

  /// No description provided for @resolutionSmartSummary.
  ///
  /// In zh, this message translates to:
  /// **'按历史成功率挑一个，失败后自动换下一个。'**
  String get resolutionSmartSummary;

  /// No description provided for @resolutionParallelSummary.
  ///
  /// In zh, this message translates to:
  /// **'同时向所有服务商发起，取最先返回的结果。'**
  String get resolutionParallelSummary;

  /// No description provided for @resolutionPrimaryBackupSummary.
  ///
  /// In zh, this message translates to:
  /// **'主服务商优先，超时后才动备用。'**
  String get resolutionPrimaryBackupSummary;

  /// No description provided for @siteLatencyTesting.
  ///
  /// In zh, this message translates to:
  /// **'测速中…'**
  String get siteLatencyTesting;

  /// No description provided for @siteLatencyNotTested.
  ///
  /// In zh, this message translates to:
  /// **'尚未测速'**
  String get siteLatencyNotTested;

  /// No description provided for @siteLatencyTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络测速'**
  String get siteLatencyTitle;

  /// No description provided for @siteLatencyRetest.
  ///
  /// In zh, this message translates to:
  /// **'重新测速'**
  String get siteLatencyRetest;

  /// No description provided for @commonFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get commonFailed;

  /// No description provided for @siteLatencyNoReply.
  ///
  /// In zh, this message translates to:
  /// **'无回包'**
  String get siteLatencyNoReply;

  /// No description provided for @statusTitle.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get statusTitle;

  /// No description provided for @statusUptime.
  ///
  /// In zh, this message translates to:
  /// **'运行时长'**
  String get statusUptime;

  /// No description provided for @statusActiveProvider.
  ///
  /// In zh, this message translates to:
  /// **'当前服务商'**
  String get statusActiveProvider;

  /// No description provided for @statusNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择'**
  String get statusNotSelected;

  /// No description provided for @statusTodayQueries.
  ///
  /// In zh, this message translates to:
  /// **'今日查询'**
  String get statusTodayQueries;

  /// No description provided for @statusDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'状态详情'**
  String get statusDetailTitle;

  /// No description provided for @statusNotTiming.
  ///
  /// In zh, this message translates to:
  /// **'未计时'**
  String get statusNotTiming;

  /// No description provided for @statusCoreSection.
  ///
  /// In zh, this message translates to:
  /// **'内核'**
  String get statusCoreSection;

  /// No description provided for @statusWorkMode.
  ///
  /// In zh, this message translates to:
  /// **'工作模式'**
  String get statusWorkMode;

  /// No description provided for @statusCoreState.
  ///
  /// In zh, this message translates to:
  /// **'内核状态'**
  String get statusCoreState;

  /// No description provided for @statusListenPort.
  ///
  /// In zh, this message translates to:
  /// **'监听端口'**
  String get statusListenPort;

  /// No description provided for @statusNotListening.
  ///
  /// In zh, this message translates to:
  /// **'未监听'**
  String get statusNotListening;

  /// No description provided for @statusProviderFooter.
  ///
  /// In zh, this message translates to:
  /// **'延迟是该服务商的最近一次实测值，不是本机到目标的往返。'**
  String get statusProviderFooter;

  /// No description provided for @statusNoProviderHint.
  ///
  /// In zh, this message translates to:
  /// **'还没有选择服务商。在服务商管理里挑一个，解析才会走真实上游。'**
  String get statusNoProviderHint;

  /// No description provided for @statusTodayCounts.
  ///
  /// In zh, this message translates to:
  /// **'今日计数'**
  String get statusTodayCounts;

  /// No description provided for @statusCountsFooter.
  ///
  /// In zh, this message translates to:
  /// **'计数从本次内核启动开始累计，重启或切换工作模式后归零；已在服务器模式里做的重置也只清计数，不动规则与缓存。'**
  String get statusCountsFooter;

  /// No description provided for @statusQueries.
  ///
  /// In zh, this message translates to:
  /// **'查询'**
  String get statusQueries;

  /// No description provided for @statusBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已拦截'**
  String get statusBlocked;

  /// No description provided for @statusAverageLatency.
  ///
  /// In zh, this message translates to:
  /// **'平均时延'**
  String get statusAverageLatency;

  /// No description provided for @statusCacheHitRate.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中率'**
  String get statusCacheHitRate;

  /// No description provided for @statusServerPortReady.
  ///
  /// In zh, this message translates to:
  /// **'本机 DNS 端口可用，局域网设备可把它当作 DNS'**
  String get statusServerPortReady;

  /// No description provided for @statusTunnelActive.
  ///
  /// In zh, this message translates to:
  /// **'本机流量已经过谛听，解析与规则都在生效'**
  String get statusTunnelActive;

  /// No description provided for @statusServerPortClosed.
  ///
  /// In zh, this message translates to:
  /// **'DNS 端口未监听，服务器模式当前不提供解析'**
  String get statusServerPortClosed;

  /// No description provided for @statusCoreStopped.
  ///
  /// In zh, this message translates to:
  /// **'内核未运行，本机流量按系统默认网络走'**
  String get statusCoreStopped;

  /// No description provided for @siteLatencySheetLatency.
  ///
  /// In zh, this message translates to:
  /// **'延迟'**
  String get siteLatencySheetLatency;

  /// No description provided for @siteLatencySheetCategory.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get siteLatencySheetCategory;

  /// No description provided for @siteLatencySheetTarget.
  ///
  /// In zh, this message translates to:
  /// **'目标'**
  String get siteLatencySheetTarget;

  /// No description provided for @siteLatencySheetAverage.
  ///
  /// In zh, this message translates to:
  /// **'平均往返'**
  String get siteLatencySheetAverage;

  /// No description provided for @siteLatencySheetMinMax.
  ///
  /// In zh, this message translates to:
  /// **'最小 / 最大'**
  String get siteLatencySheetMinMax;

  /// No description provided for @siteLatencySheetJitter.
  ///
  /// In zh, this message translates to:
  /// **'抖动'**
  String get siteLatencySheetJitter;

  /// No description provided for @siteLatencySheetLoss.
  ///
  /// In zh, this message translates to:
  /// **'丢包'**
  String get siteLatencySheetLoss;

  /// No description provided for @siteLatencySheetDns.
  ///
  /// In zh, this message translates to:
  /// **'解析地址'**
  String get siteLatencySheetDns;

  /// No description provided for @siteLatencySheetLastRun.
  ///
  /// In zh, this message translates to:
  /// **'最近测速'**
  String get siteLatencySheetLastRun;

  /// No description provided for @siteLatencySheetNotTested.
  ///
  /// In zh, this message translates to:
  /// **'尚未测速。点测速按钮开始测量。'**
  String get siteLatencySheetNotTested;

  /// No description provided for @siteLatencySheetNoReply.
  ///
  /// In zh, this message translates to:
  /// **'三个回显请求都没有收到应答，可能是站点限流或当前网络不通。'**
  String get siteLatencySheetNoReply;

  /// No description provided for @siteLatencySheetFallbackFooter.
  ///
  /// In zh, this message translates to:
  /// **'系统 ping 不可用，这次数值来自 TCP 握手 / isReachable，衡量的是建连时延而不是 ICMP 回显，会略高于真实往返。'**
  String get siteLatencySheetFallbackFooter;

  /// No description provided for @siteLatencySheetIcmpFooter.
  ///
  /// In zh, this message translates to:
  /// **'数值来自系统 ping 的 ICMP 回显（3 次取平均）。本应用自身流量不经过 VPN，测的是物理网络。'**
  String get siteLatencySheetIcmpFooter;

  /// No description provided for @trafficStructureLive.
  ///
  /// In zh, this message translates to:
  /// **'实时汇总'**
  String get trafficStructureLive;

  /// No description provided for @trafficStructureFocused.
  ///
  /// In zh, this message translates to:
  /// **'重点流量结构'**
  String get trafficStructureFocused;

  /// No description provided for @trafficStructureToday.
  ///
  /// In zh, this message translates to:
  /// **'今日流量结构'**
  String get trafficStructureToday;

  /// No description provided for @trafficStructureBypass.
  ///
  /// In zh, this message translates to:
  /// **'旁路'**
  String get trafficStructureBypass;

  /// No description provided for @trafficStructureCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get trafficStructureCache;

  /// No description provided for @trafficStructureRaceRate.
  ///
  /// In zh, this message translates to:
  /// **'竞速成功率'**
  String get trafficStructureRaceRate;

  /// No description provided for @trafficStructureBootstrapRate.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 成功率'**
  String get trafficStructureBootstrapRate;

  /// No description provided for @trafficStructureBlockedShare.
  ///
  /// In zh, this message translates to:
  /// **'拦截占比'**
  String get trafficStructureBlockedShare;

  /// No description provided for @trafficStructureBlockRate.
  ///
  /// In zh, this message translates to:
  /// **'拦截率'**
  String get trafficStructureBlockRate;

  /// No description provided for @trafficStructureCacheRate.
  ///
  /// In zh, this message translates to:
  /// **'缓存率'**
  String get trafficStructureCacheRate;

  /// No description provided for @dashboardSitesTitle.
  ///
  /// In zh, this message translates to:
  /// **'仪表盘站点'**
  String get dashboardSitesTitle;

  /// No description provided for @dashboardSitesCardSection.
  ///
  /// In zh, this message translates to:
  /// **'仪表盘卡片'**
  String get dashboardSitesCardSection;

  /// No description provided for @dashboardSitesAtLeastOne.
  ///
  /// In zh, this message translates to:
  /// **'卡片至少保留 1 个站点'**
  String get dashboardSitesAtLeastOne;

  /// No description provided for @dashboardSitesFooter.
  ///
  /// In zh, this message translates to:
  /// **'这四张卡片用的是同一个仪表盘卡片，改动立刻生效；测速在详情页按分类手动触发。'**
  String get dashboardSitesFooter;

  /// No description provided for @trafficMonitorTitle.
  ///
  /// In zh, this message translates to:
  /// **'流量监控'**
  String get trafficMonitorTitle;

  /// No description provided for @trafficMonitorToday.
  ///
  /// In zh, this message translates to:
  /// **'今日代理流量'**
  String get trafficMonitorToday;

  /// No description provided for @trafficMonitorLiveRate.
  ///
  /// In zh, this message translates to:
  /// **'实时速率'**
  String get trafficMonitorLiveRate;

  /// No description provided for @trafficMonitorNoStats.
  ///
  /// In zh, this message translates to:
  /// **'本模式不统计'**
  String get trafficMonitorNoStats;

  /// No description provided for @memoryDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'内存详情'**
  String get memoryDetailTitle;

  /// No description provided for @memoryResample.
  ///
  /// In zh, this message translates to:
  /// **'重新采样'**
  String get memoryResample;

  /// No description provided for @memoryProcessPss.
  ///
  /// In zh, this message translates to:
  /// **'本进程 PSS'**
  String get memoryProcessPss;

  /// No description provided for @memoryUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'不可用'**
  String get memoryUnavailable;

  /// No description provided for @memoryOther.
  ///
  /// In zh, this message translates to:
  /// **'其它'**
  String get memoryOther;

  /// No description provided for @memoryComposition.
  ///
  /// In zh, this message translates to:
  /// **'进程构成'**
  String get memoryComposition;

  /// No description provided for @memoryCompositionFooter.
  ///
  /// In zh, this message translates to:
  /// **'PSS 按共享页的比例计入本进程，因此 Java 堆与原生堆之和小于 PSS，差额是代码、图形缓冲与共享库。'**
  String get memoryCompositionFooter;

  /// No description provided for @memoryOtherCode.
  ///
  /// In zh, this message translates to:
  /// **'其它（代码 / 共享库）'**
  String get memoryOtherCode;

  /// No description provided for @memorySystemSection.
  ///
  /// In zh, this message translates to:
  /// **'整机内存'**
  String get memorySystemSection;

  /// No description provided for @memorySystemFooter.
  ///
  /// In zh, this message translates to:
  /// **'整机占用 = 总量 - 可用量，包含系统与所有应用；本进程只是其中一份。'**
  String get memorySystemFooter;

  /// No description provided for @memorySystemUsed.
  ///
  /// In zh, this message translates to:
  /// **'整机已用'**
  String get memorySystemUsed;

  /// No description provided for @memoryRecentPss.
  ///
  /// In zh, this message translates to:
  /// **'最近 PSS'**
  String get memoryRecentPss;

  /// No description provided for @memorySampling.
  ///
  /// In zh, this message translates to:
  /// **'正在采样…'**
  String get memorySampling;

  /// No description provided for @memoryRecentPssCaption.
  ///
  /// In zh, this message translates to:
  /// **'打开本页后每 2 秒采样一次，最多保留 60 个点；曲线持续上扬说明有内存未释放。'**
  String get memoryRecentPssCaption;

  /// No description provided for @memorySourceFooter.
  ///
  /// In zh, this message translates to:
  /// **'数据来自 ActivityManager 的 MemoryInfo；切到后台或系统回收后数值会明显下降。'**
  String get memorySourceFooter;

  /// No description provided for @siteLatencyDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'测速详情'**
  String get siteLatencyDetailTitle;

  /// No description provided for @siteLatencyTestAll.
  ///
  /// In zh, this message translates to:
  /// **'测全部'**
  String get siteLatencyTestAll;

  /// No description provided for @siteLatencyCustomSites.
  ///
  /// In zh, this message translates to:
  /// **'自定义仪表盘站点'**
  String get siteLatencyCustomSites;

  /// No description provided for @siteLatencyConnectivity.
  ///
  /// In zh, this message translates to:
  /// **'站点连通性'**
  String get siteLatencyConnectivity;

  /// No description provided for @siteLatencyTestingShort.
  ///
  /// In zh, this message translates to:
  /// **'测速中'**
  String get siteLatencyTestingShort;

  /// No description provided for @siteLatencyNoTest.
  ///
  /// In zh, this message translates to:
  /// **'未测速'**
  String get siteLatencyNoTest;

  /// No description provided for @siteLatencyInProgress.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get siteLatencyInProgress;

  /// No description provided for @siteLatencyPending.
  ///
  /// In zh, this message translates to:
  /// **'待测'**
  String get siteLatencyPending;

  /// No description provided for @siteLatencyAllReachable.
  ///
  /// In zh, this message translates to:
  /// **'全部通畅'**
  String get siteLatencyAllReachable;

  /// No description provided for @siteLatencyTestingEach.
  ///
  /// In zh, this message translates to:
  /// **'正在逐个站点测速…'**
  String get siteLatencyTestingEach;

  /// No description provided for @siteLatencyPickCategory.
  ///
  /// In zh, this message translates to:
  /// **'选一个分类点测速，或点右上角测全部。'**
  String get siteLatencyPickCategory;

  /// No description provided for @siteLatencyThisRun.
  ///
  /// In zh, this message translates to:
  /// **'本次结果'**
  String get siteLatencyThisRun;

  /// No description provided for @siteLatencyReachable.
  ///
  /// In zh, this message translates to:
  /// **'通畅'**
  String get siteLatencyReachable;

  /// No description provided for @siteLatencyMeasuredSites.
  ///
  /// In zh, this message translates to:
  /// **'已测站点'**
  String get siteLatencyMeasuredSites;

  /// No description provided for @siteLatencyDetailFooter.
  ///
  /// In zh, this message translates to:
  /// **'每个站点发 3 个 ICMP 回显，取平均值；系统 ping 不可用时退回 TCP 握手，会标上 * 号，数值略高于真实往返。本应用自身流量不经过 VPN，测的是物理网络。'**
  String get siteLatencyDetailFooter;

  /// No description provided for @intranetDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'内网 IP 详情'**
  String get intranetDetailTitle;

  /// No description provided for @intranetRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新网络信息'**
  String get intranetRefresh;

  /// No description provided for @intranetLocalAddress.
  ///
  /// In zh, this message translates to:
  /// **'本机局域网地址'**
  String get intranetLocalAddress;

  /// No description provided for @intranetUsableAsDns.
  ///
  /// In zh, this message translates to:
  /// **'可作 DNS'**
  String get intranetUsableAsDns;

  /// No description provided for @intranetLocalOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅本机'**
  String get intranetLocalOnly;

  /// No description provided for @intranetSameSubnetHint.
  ///
  /// In zh, this message translates to:
  /// **'同网段设备把 DNS 指到这个地址即可走本机解析。'**
  String get intranetSameSubnetHint;

  /// No description provided for @intranetNetworkOverview.
  ///
  /// In zh, this message translates to:
  /// **'网络概况'**
  String get intranetNetworkOverview;

  /// No description provided for @commonEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get commonEnabled;

  /// No description provided for @commonDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get commonDisabled;

  /// No description provided for @intranetDnsServers.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务器'**
  String get intranetDnsServers;

  /// No description provided for @intranetInterfaces.
  ///
  /// In zh, this message translates to:
  /// **'接口'**
  String get intranetInterfaces;

  /// No description provided for @intranetNoInterface.
  ///
  /// In zh, this message translates to:
  /// **'系统没有报告活动网络接口，可能是飞行模式或未联网。'**
  String get intranetNoInterface;

  /// No description provided for @intranetAdapter.
  ///
  /// In zh, this message translates to:
  /// **'网卡'**
  String get intranetAdapter;

  /// No description provided for @intranetGateway.
  ///
  /// In zh, this message translates to:
  /// **'网关'**
  String get intranetGateway;

  /// No description provided for @intranetPrivateDnsOff.
  ///
  /// In zh, this message translates to:
  /// **'系统私人 DNS 未开启，解析请求由本机与代理按模式处理。'**
  String get intranetPrivateDnsOff;

  /// No description provided for @intranetNoDnsServer.
  ///
  /// In zh, this message translates to:
  /// **'没有读到 DNS 服务器：接口未下发 DNS，或当前环境没有诊断通道。'**
  String get intranetNoDnsServer;

  /// No description provided for @intranetPrimaryDns.
  ///
  /// In zh, this message translates to:
  /// **'首选'**
  String get intranetPrimaryDns;

  /// No description provided for @intranetPrivateDns.
  ///
  /// In zh, this message translates to:
  /// **'私人 DNS'**
  String get intranetPrivateDns;

  /// No description provided for @intranetPortFooter.
  ///
  /// In zh, this message translates to:
  /// **'端口只在服务启动时绑定，改动端口后需要重启服务；把同网段设备的 DNS 指向上面的地址即可让它们走本机解析。'**
  String get intranetPortFooter;

  /// No description provided for @intranetCopyAddressWithPort.
  ///
  /// In zh, this message translates to:
  /// **'复制地址（含端口）'**
  String get intranetCopyAddressWithPort;

  /// No description provided for @speedDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'网速详情'**
  String get speedDetailTitle;

  /// No description provided for @speedCurrentDownload.
  ///
  /// In zh, this message translates to:
  /// **'当前下载'**
  String get speedCurrentDownload;

  /// No description provided for @speedSamplingPaused.
  ///
  /// In zh, this message translates to:
  /// **'暂停采样'**
  String get speedSamplingPaused;

  /// No description provided for @speedLive.
  ///
  /// In zh, this message translates to:
  /// **'实时'**
  String get speedLive;

  /// No description provided for @speedSamplingHint.
  ///
  /// In zh, this message translates to:
  /// **'每秒采样一次，下图是最近一分钟。'**
  String get speedSamplingHint;

  /// No description provided for @speedCurrentUpload.
  ///
  /// In zh, this message translates to:
  /// **'当前上传'**
  String get speedCurrentUpload;

  /// No description provided for @speedDownloadPeak.
  ///
  /// In zh, this message translates to:
  /// **'下行峰值'**
  String get speedDownloadPeak;

  /// No description provided for @speedUploadPeak.
  ///
  /// In zh, this message translates to:
  /// **'上行峰值'**
  String get speedUploadPeak;

  /// No description provided for @speedSamples.
  ///
  /// In zh, this message translates to:
  /// **'样本'**
  String get speedSamples;

  /// No description provided for @speedTodayTotal.
  ///
  /// In zh, this message translates to:
  /// **'今日累计'**
  String get speedTodayTotal;

  /// No description provided for @speedNoTrafficToday.
  ///
  /// In zh, this message translates to:
  /// **'流量库还没有今天的记录。'**
  String get speedNoTrafficToday;

  /// No description provided for @speedTotal.
  ///
  /// In zh, this message translates to:
  /// **'合计'**
  String get speedTotal;

  /// No description provided for @speedRateFooter.
  ///
  /// In zh, this message translates to:
  /// **'速率来自内核数据面的实时计数，只包含经过隧道转发的流量；本应用自身的探测与测速不计入。今日累计来自应用流量统计，与「流量统计」页同一份数据。'**
  String get speedRateFooter;

  /// No description provided for @speedExpressSource.
  ///
  /// In zh, this message translates to:
  /// **'极速模式不经过内核数据面，因此没有逐秒速率；切回普通模式后恢复。'**
  String get speedExpressSource;

  /// No description provided for @speedNoChannelSource.
  ///
  /// In zh, this message translates to:
  /// **'当前环境没有速率通道（桌面环境或纯 Dart 测试），读不到实时速率。'**
  String get speedNoChannelSource;

  /// No description provided for @speedNoDataInMode.
  ///
  /// In zh, this message translates to:
  /// **'当前模式下没有速率数据'**
  String get speedNoDataInMode;

  /// No description provided for @speedWaitingSample.
  ///
  /// In zh, this message translates to:
  /// **'正在等待第一个样本'**
  String get speedWaitingSample;

  /// No description provided for @commonNoData.
  ///
  /// In zh, this message translates to:
  /// **'无数据'**
  String get commonNoData;

  /// No description provided for @commonPendingTitle.
  ///
  /// In zh, this message translates to:
  /// **'尚未接入'**
  String get commonPendingTitle;

  /// No description provided for @commonPendingBody.
  ///
  /// In zh, this message translates to:
  /// **'这个页面还没有连接到本机服务，接入后会显示实时数据。'**
  String get commonPendingBody;

  /// No description provided for @homePowerPending.
  ///
  /// In zh, this message translates to:
  /// **'电源控制还没有接入本机服务'**
  String get homePowerPending;

  /// No description provided for @intranetModeNotListening.
  ///
  /// In zh, this message translates to:
  /// **'{mode}不监听局域网，其他设备无法把这里当 DNS'**
  String intranetModeNotListening(String mode);

  /// No description provided for @intranetListeningOn.
  ///
  /// In zh, this message translates to:
  /// **'已监听 0.0.0.0:{port}，其他设备把 DNS 指到上面的地址'**
  String intranetListeningOn(int port);

  /// No description provided for @intranetServiceStopped.
  ///
  /// In zh, this message translates to:
  /// **'服务未启动：启动后才会绑定 {port} 端口'**
  String intranetServiceStopped(int port);

  /// No description provided for @commonCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制 {text}'**
  String commonCopied(String text);

  /// No description provided for @intranetGatewaySuffix.
  ///
  /// In zh, this message translates to:
  /// **' · 网关 {gateway}'**
  String intranetGatewaySuffix(String gateway);

  /// No description provided for @speedTotalDash.
  ///
  /// In zh, this message translates to:
  /// **'累计 —'**
  String get speedTotalDash;

  /// No description provided for @siteLatencyAliveRatio.
  ///
  /// In zh, this message translates to:
  /// **'{alive} / {total} 通畅'**
  String siteLatencyAliveRatio(int alive, int total);

  /// No description provided for @siteLatencyLastRun.
  ///
  /// In zh, this message translates to:
  /// **'最近测速 {ago}'**
  String siteLatencyLastRun(String ago);

  /// No description provided for @siteLatencyProviderSuffix.
  ///
  /// In zh, this message translates to:
  /// **' · 解析服务商 {name}'**
  String siteLatencyProviderSuffix(String name);

  /// No description provided for @siteLatencySitesCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个站点'**
  String siteLatencySitesCount(int count);

  /// No description provided for @siteLatencyTestCategory.
  ///
  /// In zh, this message translates to:
  /// **'测速{category}'**
  String siteLatencyTestCategory(String category);

  /// No description provided for @memorySystemShare.
  ///
  /// In zh, this message translates to:
  /// **'占整机 {percent}'**
  String memorySystemShare(String percent);

  /// No description provided for @memorySystemUsedOf.
  ///
  /// In zh, this message translates to:
  /// **'整机已用 {used} / {total}'**
  String memorySystemUsedOf(String total, String used);

  /// No description provided for @memoryNoChannel.
  ///
  /// In zh, this message translates to:
  /// **'当前环境读不到内存数据（桌面环境或纯 Dart 测试）。'**
  String get memoryNoChannel;

  /// No description provided for @trafficStructureRateValue.
  ///
  /// In zh, this message translates to:
  /// **'{percent} · {count} 次 · {latency}'**
  String trafficStructureRateValue(
    String count,
    String latency,
    String percent,
  );

  /// No description provided for @trafficStructureShareValue.
  ///
  /// In zh, this message translates to:
  /// **'{percent} · {count} 次'**
  String trafficStructureShareValue(String count, String percent);

  /// No description provided for @statusPausedSummary.
  ///
  /// In zh, this message translates to:
  /// **'{mode}{core}，计时已暂停'**
  String statusPausedSummary(String core, String mode);

  /// No description provided for @speedTotalsDown.
  ///
  /// In zh, this message translates to:
  /// **'下行 {percent}'**
  String speedTotalsDown(String percent);

  /// No description provided for @speedTotalsUp.
  ///
  /// In zh, this message translates to:
  /// **'上行 {percent}'**
  String speedTotalsUp(String percent);

  /// No description provided for @speedPeakAverage.
  ///
  /// In zh, this message translates to:
  /// **'峰值 {peak} · 平均 {average}'**
  String speedPeakAverage(String average, String peak);

  /// No description provided for @intranetConnectHintSentence.
  ///
  /// In zh, this message translates to:
  /// **'连上 Wi-Fi 或以太网后这里会显示可用地址。'**
  String get intranetConnectHintSentence;

  /// No description provided for @intranetModeNotListeningSentence.
  ///
  /// In zh, this message translates to:
  /// **'{mode}不监听局域网，其它设备无法把这里当 DNS。'**
  String intranetModeNotListeningSentence(String mode);

  /// No description provided for @intranetPrivateDnsOn.
  ///
  /// In zh, this message translates to:
  /// **'系统开启了私人 DNS（{dns}），系统解析会走加密通道，可能绕过本地服务。'**
  String intranetPrivateDnsOn(String dns);

  /// No description provided for @intranetSecondaryDns.
  ///
  /// In zh, this message translates to:
  /// **'备用 {index}'**
  String intranetSecondaryDns(int index);

  /// No description provided for @intranetCopyAddressSemantics.
  ///
  /// In zh, this message translates to:
  /// **'复制地址 {address}'**
  String intranetCopyAddressSemantics(String address);

  /// No description provided for @speedTotalAccumulated.
  ///
  /// In zh, this message translates to:
  /// **'累计 {value}'**
  String speedTotalAccumulated(String value);

  /// No description provided for @dashboardSitesFull.
  ///
  /// In zh, this message translates to:
  /// **'卡片只能放 {count} 个站点，先点掉一个再换别的。'**
  String dashboardSitesFull(int count);

  /// No description provided for @dashboardSitesRemaining.
  ///
  /// In zh, this message translates to:
  /// **'还可以再放 {count} 个站点。'**
  String dashboardSitesRemaining(int count);

  /// No description provided for @dashboardSitesMax.
  ///
  /// In zh, this message translates to:
  /// **'卡片最多放 {count} 个站点，先取消一个再选。'**
  String dashboardSitesMax(int count);

  /// No description provided for @dashboardSitesPosition.
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 位'**
  String dashboardSitesPosition(int index);

  /// No description provided for @siteLatencyFailedCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个失败'**
  String siteLatencyFailedCount(int count);

  /// No description provided for @siteLatencyDetailFooterLong.
  ///
  /// In zh, this message translates to:
  /// **'每个站点发 3 个 ICMP 回显，取平均值；系统 ping 不可用时退回 TCP 握手，会标上 * 号，数值略高于真实往返。本应用自身流量不经过 VPN，测的是物理网络。'**
  String get siteLatencyDetailFooterLong;

  /// No description provided for @homeLayerPowerButton.
  ///
  /// In zh, this message translates to:
  /// **'启动按钮'**
  String get homeLayerPowerButton;

  /// No description provided for @homeLayerPoem.
  ///
  /// In zh, this message translates to:
  /// **'首页古诗'**
  String get homeLayerPoem;

  /// No description provided for @bottomBarHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get bottomBarHome;

  /// No description provided for @bottomBarFeatureHub.
  ///
  /// In zh, this message translates to:
  /// **'功能中心'**
  String get bottomBarFeatureHub;

  /// No description provided for @bottomBarLogDashboard.
  ///
  /// In zh, this message translates to:
  /// **'日志仪表盘'**
  String get bottomBarLogDashboard;

  /// No description provided for @bottomBarAppTraffic.
  ///
  /// In zh, this message translates to:
  /// **'应用流量'**
  String get bottomBarAppTraffic;

  /// No description provided for @bottomBarNetworkTools.
  ///
  /// In zh, this message translates to:
  /// **'网络工具'**
  String get bottomBarNetworkTools;

  /// No description provided for @bottomBarSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get bottomBarSettings;

  /// No description provided for @bottomBarStyleFloating.
  ///
  /// In zh, this message translates to:
  /// **'浮条'**
  String get bottomBarStyleFloating;

  /// No description provided for @bottomBarStyleDocked.
  ///
  /// In zh, this message translates to:
  /// **'普通'**
  String get bottomBarStyleDocked;

  /// No description provided for @tabTransitionNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get tabTransitionNone;

  /// No description provided for @tabTransitionFade.
  ///
  /// In zh, this message translates to:
  /// **'淡入'**
  String get tabTransitionFade;

  /// No description provided for @tabTransitionSlide.
  ///
  /// In zh, this message translates to:
  /// **'滑动'**
  String get tabTransitionSlide;

  /// No description provided for @tabTransitionScale.
  ///
  /// In zh, this message translates to:
  /// **'缩放'**
  String get tabTransitionScale;

  /// No description provided for @commonOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonOff;

  /// No description provided for @glassModeStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get glassModeStandard;

  /// No description provided for @glassModeUltra.
  ///
  /// In zh, this message translates to:
  /// **'极致'**
  String get glassModeUltra;

  /// No description provided for @previewBrightnessLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get previewBrightnessLight;

  /// No description provided for @previewBrightnessDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get previewBrightnessDark;

  /// No description provided for @resolutionModeSingle.
  ///
  /// In zh, this message translates to:
  /// **'单服务商'**
  String get resolutionModeSingle;

  /// No description provided for @resolutionModeSmart.
  ///
  /// In zh, this message translates to:
  /// **'智能选择'**
  String get resolutionModeSmart;

  /// No description provided for @resolutionModeParallel.
  ///
  /// In zh, this message translates to:
  /// **'并行竞速'**
  String get resolutionModeParallel;

  /// No description provided for @resolutionModePrimaryBackup.
  ///
  /// In zh, this message translates to:
  /// **'主备切换'**
  String get resolutionModePrimaryBackup;

  /// No description provided for @workModeNormalTitle.
  ///
  /// In zh, this message translates to:
  /// **'普通模式'**
  String get workModeNormalTitle;

  /// No description provided for @workModeNormalBadge.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get workModeNormalBadge;

  /// No description provided for @workModeNormalSummary.
  ///
  /// In zh, this message translates to:
  /// **'全量域名解析、黑白名单、HTTPS 检查、网络管控'**
  String get workModeNormalSummary;

  /// No description provided for @workModeServerTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务器模式'**
  String get workModeServerTitle;

  /// No description provided for @workModeServerBadge.
  ///
  /// In zh, this message translates to:
  /// **'轻量'**
  String get workModeServerBadge;

  /// No description provided for @workModeServerSummary.
  ///
  /// In zh, this message translates to:
  /// **'纯 DNS 代理与解析加速、低功耗'**
  String get workModeServerSummary;

  /// No description provided for @workModeExpressTitle.
  ///
  /// In zh, this message translates to:
  /// **'极速模式'**
  String get workModeExpressTitle;

  /// No description provided for @workModeExpressBadge.
  ///
  /// In zh, this message translates to:
  /// **'极速'**
  String get workModeExpressBadge;

  /// No description provided for @workModeExpressSummary.
  ///
  /// In zh, this message translates to:
  /// **'DNS 窄路由、加速与规则过滤、Android 9+（64 位）'**
  String get workModeExpressSummary;

  /// No description provided for @stateStopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get stateStopped;

  /// No description provided for @stateStarting.
  ///
  /// In zh, this message translates to:
  /// **'启动中'**
  String get stateStarting;

  /// No description provided for @stateRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get stateRunning;

  /// No description provided for @stateStopping.
  ///
  /// In zh, this message translates to:
  /// **'停止中'**
  String get stateStopping;

  /// No description provided for @powerStateError.
  ///
  /// In zh, this message translates to:
  /// **'启动失败'**
  String get powerStateError;

  /// No description provided for @serverStatusError.
  ///
  /// In zh, this message translates to:
  /// **'异常'**
  String get serverStatusError;

  /// No description provided for @logModeAllLabel.
  ///
  /// In zh, this message translates to:
  /// **'记录全部'**
  String get logModeAllLabel;

  /// No description provided for @logModeAllDescription.
  ///
  /// In zh, this message translates to:
  /// **'请求、命中、竞速与拦截都进日志'**
  String get logModeAllDescription;

  /// No description provided for @logModeBlockedLabel.
  ///
  /// In zh, this message translates to:
  /// **'仅拦截与错误'**
  String get logModeBlockedLabel;

  /// No description provided for @logModeBlockedDescription.
  ///
  /// In zh, this message translates to:
  /// **'只记录被拦截与出错的请求'**
  String get logModeBlockedDescription;

  /// No description provided for @logModeOffLabel.
  ///
  /// In zh, this message translates to:
  /// **'关闭日志'**
  String get logModeOffLabel;

  /// No description provided for @logModeOffDescription.
  ///
  /// In zh, this message translates to:
  /// **'不记录任何请求，节省空间'**
  String get logModeOffDescription;

  /// No description provided for @ipv6AutoLabel.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get ipv6AutoLabel;

  /// No description provided for @ipv6AutoDescription.
  ///
  /// In zh, this message translates to:
  /// **'按当前网络能力决定是否启用'**
  String get ipv6AutoDescription;

  /// No description provided for @ipv6DisableLabel.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get ipv6DisableLabel;

  /// No description provided for @ipv6DisableDescription.
  ///
  /// In zh, this message translates to:
  /// **'隧道内不启用 IPv6'**
  String get ipv6DisableDescription;

  /// No description provided for @ipv6PreferLabel.
  ///
  /// In zh, this message translates to:
  /// **'优先'**
  String get ipv6PreferLabel;

  /// No description provided for @ipv6PreferDescription.
  ///
  /// In zh, this message translates to:
  /// **'尽量走 IPv6，失败再回落'**
  String get ipv6PreferDescription;

  /// No description provided for @commonToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get commonToday;

  /// No description provided for @logWindowSevenDays.
  ///
  /// In zh, this message translates to:
  /// **'7 天'**
  String get logWindowSevenDays;

  /// No description provided for @logWindowSevenDaysRecent.
  ///
  /// In zh, this message translates to:
  /// **'近 7 天'**
  String get logWindowSevenDaysRecent;

  /// No description provided for @commonAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get commonAll;

  /// No description provided for @trafficWindowWeek.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get trafficWindowWeek;

  /// No description provided for @trafficWindowMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get trafficWindowMonth;

  /// No description provided for @trafficSortTotal.
  ///
  /// In zh, this message translates to:
  /// **'按总流量'**
  String get trafficSortTotal;

  /// No description provided for @trafficSortDownload.
  ///
  /// In zh, this message translates to:
  /// **'按下载流量'**
  String get trafficSortDownload;

  /// No description provided for @trafficSortUpload.
  ///
  /// In zh, this message translates to:
  /// **'按上传流量'**
  String get trafficSortUpload;

  /// No description provided for @davStatusIdle.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get davStatusIdle;

  /// No description provided for @davStatusConnecting.
  ///
  /// In zh, this message translates to:
  /// **'连接中'**
  String get davStatusConnecting;

  /// No description provided for @davStatusConnected.
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get davStatusConnected;

  /// No description provided for @davStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get davStatusFailed;

  /// No description provided for @updateStageIdle.
  ///
  /// In zh, this message translates to:
  /// **'未检查'**
  String get updateStageIdle;

  /// No description provided for @updateStageChecking.
  ///
  /// In zh, this message translates to:
  /// **'检查中'**
  String get updateStageChecking;

  /// No description provided for @updateStageUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新'**
  String get updateStageUpToDate;

  /// No description provided for @updateStageAvailable.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本'**
  String get updateStageAvailable;

  /// No description provided for @updateStageDownloading.
  ///
  /// In zh, this message translates to:
  /// **'下载中'**
  String get updateStageDownloading;

  /// No description provided for @updateStageDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'下载完成'**
  String get updateStageDownloaded;

  /// No description provided for @ipQualityStageIdle.
  ///
  /// In zh, this message translates to:
  /// **'未检测'**
  String get ipQualityStageIdle;

  /// No description provided for @ipQualityStageLoading.
  ///
  /// In zh, this message translates to:
  /// **'检测中'**
  String get ipQualityStageLoading;

  /// No description provided for @ipQualityStageLoaded.
  ///
  /// In zh, this message translates to:
  /// **'检测完成'**
  String get ipQualityStageLoaded;

  /// No description provided for @ipQualityStageFailed.
  ///
  /// In zh, this message translates to:
  /// **'检测失败'**
  String get ipQualityStageFailed;

  /// No description provided for @subscriptionDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get subscriptionDeleted;

  /// No description provided for @subscriptionDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已禁用'**
  String get subscriptionDisabled;

  /// No description provided for @subscriptionUngrouped.
  ///
  /// In zh, this message translates to:
  /// **'未分组'**
  String get subscriptionUngrouped;

  /// No description provided for @providerNotTested.
  ///
  /// In zh, this message translates to:
  /// **'未测速'**
  String get providerNotTested;

  /// No description provided for @elapsedJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get elapsedJustNow;

  /// No description provided for @elapsedSecondsAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 秒前'**
  String elapsedSecondsAgo(int count);

  /// No description provided for @elapsedMinutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 分钟前'**
  String elapsedMinutesAgo(int count);

  /// No description provided for @elapsedHoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 小时前'**
  String elapsedHoursAgo(int count);

  /// No description provided for @elapsedDaysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 天前'**
  String elapsedDaysAgo(int count);

  /// No description provided for @providerRaceSummary.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 个：{names}'**
  String providerRaceSummary(String count, String names);

  /// No description provided for @rulesDbUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前环境无法读写规则库'**
  String get rulesDbUnavailable;

  /// No description provided for @agentApiKeyMissing.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置可用的 API Key，请先在「AI 厂商管理」里填写并选中该厂商。'**
  String get agentApiKeyMissing;

  /// No description provided for @agentNoExtraInfo.
  ///
  /// In zh, this message translates to:
  /// **'（无附加信息）'**
  String get agentNoExtraInfo;

  /// No description provided for @agentNoLegacyDatabase.
  ///
  /// In zh, this message translates to:
  /// **'未找到旧版数据库，无法读取 DNS 与 HTTPS 日志；请先启动一次服务。'**
  String get agentNoLegacyDatabase;

  /// No description provided for @agentExpressNoHttps.
  ///
  /// In zh, this message translates to:
  /// **'极速模式只做窄路由 DNS 加速，不产生 HTTPS 检查记录'**
  String get agentExpressNoHttps;

  /// No description provided for @autoUpdateDisabled.
  ///
  /// In zh, this message translates to:
  /// **'自动更新已关闭'**
  String get autoUpdateDisabled;

  /// No description provided for @autoUpdateNoSubscriptions.
  ///
  /// In zh, this message translates to:
  /// **'没有可自动更新的订阅'**
  String get autoUpdateNoSubscriptions;

  /// No description provided for @autoUpdateNotDue.
  ///
  /// In zh, this message translates to:
  /// **'未到更新时间'**
  String get autoUpdateNotDue;

  /// No description provided for @autoUpdateBusy.
  ///
  /// In zh, this message translates to:
  /// **'正在手动更新，本轮跳过'**
  String get autoUpdateBusy;

  /// No description provided for @cleanupGroupRuntime.
  ///
  /// In zh, this message translates to:
  /// **'运行数据'**
  String get cleanupGroupRuntime;

  /// No description provided for @cleanupGroupWeights.
  ///
  /// In zh, this message translates to:
  /// **'权重数据'**
  String get cleanupGroupWeights;

  /// No description provided for @cleanupGroupRules.
  ///
  /// In zh, this message translates to:
  /// **'规则与订阅'**
  String get cleanupGroupRules;

  /// No description provided for @cleanupGroupStorage.
  ///
  /// In zh, this message translates to:
  /// **'存储与安全'**
  String get cleanupGroupStorage;

  /// No description provided for @cleanupGroupGuides.
  ///
  /// In zh, this message translates to:
  /// **'引导与重置'**
  String get cleanupGroupGuides;

  /// No description provided for @backupReadFileFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取所选文件'**
  String get backupReadFileFailed;

  /// No description provided for @caChannelUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'证书通道不可用'**
  String get caChannelUnavailable;

  /// No description provided for @caInstallUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法调起证书安装界面'**
  String get caInstallUnavailable;

  /// No description provided for @caDownloadDirUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法写入下载目录'**
  String get caDownloadDirUnavailable;

  /// No description provided for @fontSystemDefault.
  ///
  /// In zh, this message translates to:
  /// **'系统默认'**
  String get fontSystemDefault;

  /// No description provided for @diagnosticsChannelUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'诊断通道不可用（当前平台没有原生实现）'**
  String get diagnosticsChannelUnavailable;

  /// No description provided for @diagnosticsUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前环境不支持该诊断能力'**
  String get diagnosticsUnsupported;

  /// No description provided for @diagnosticsPingUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前环境不支持 Ping 探测'**
  String get diagnosticsPingUnsupported;

  /// No description provided for @diagnosticsTraceUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前环境不支持路由追踪'**
  String get diagnosticsTraceUnsupported;

  /// No description provided for @diagnosticsDnsUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前环境不支持 DNS 查询'**
  String get diagnosticsDnsUnsupported;

  /// No description provided for @diagnosticsEmptyTarget.
  ///
  /// In zh, this message translates to:
  /// **'请输入探测目标'**
  String get diagnosticsEmptyTarget;

  /// No description provided for @diagnosticsTargetHasSpace.
  ///
  /// In zh, this message translates to:
  /// **'目标不能包含空格'**
  String get diagnosticsTargetHasSpace;

  /// No description provided for @diagnosticsAnswerUpstream.
  ///
  /// In zh, this message translates to:
  /// **'上游解析'**
  String get diagnosticsAnswerUpstream;

  /// No description provided for @diagnosticsAnswerCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中'**
  String get diagnosticsAnswerCache;

  /// No description provided for @diagnosticsAnswerRewrite.
  ///
  /// In zh, this message translates to:
  /// **'覆写规则'**
  String get diagnosticsAnswerRewrite;

  /// No description provided for @diagnosticsAnswerBlocked.
  ///
  /// In zh, this message translates to:
  /// **'被规则拦截'**
  String get diagnosticsAnswerBlocked;

  /// No description provided for @diagnosticsAnswerFailed.
  ///
  /// In zh, this message translates to:
  /// **'查询失败'**
  String get diagnosticsAnswerFailed;

  /// No description provided for @diagnosticsNoActiveNetwork.
  ///
  /// In zh, this message translates to:
  /// **'无活动网络'**
  String get diagnosticsNoActiveNetwork;

  /// No description provided for @aiPresetMainland.
  ///
  /// In zh, this message translates to:
  /// **'国内厂商'**
  String get aiPresetMainland;

  /// No description provided for @aiPresetOverseas.
  ///
  /// In zh, this message translates to:
  /// **'海外厂商'**
  String get aiPresetOverseas;

  /// No description provided for @aiPresetAggregator.
  ///
  /// In zh, this message translates to:
  /// **'聚合与本地部署'**
  String get aiPresetAggregator;

  /// No description provided for @aiProviderConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置厂商'**
  String get aiProviderConfigured;

  /// No description provided for @aiProviderExampleName.
  ///
  /// In zh, this message translates to:
  /// **'示例厂商（请修改）'**
  String get aiProviderExampleName;

  /// No description provided for @logSubscriptionDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除订阅'**
  String get logSubscriptionDeleted;

  /// No description provided for @logRaceFastest.
  ///
  /// In zh, this message translates to:
  /// **'最快响应'**
  String get logRaceFastest;

  /// No description provided for @logRaceSmart.
  ///
  /// In zh, this message translates to:
  /// **'智能选择'**
  String get logRaceSmart;

  /// No description provided for @logRaceSequential.
  ///
  /// In zh, this message translates to:
  /// **'依次尝试'**
  String get logRaceSequential;

  /// No description provided for @logRaceSingle.
  ///
  /// In zh, this message translates to:
  /// **'单服务商'**
  String get logRaceSingle;

  /// No description provided for @providerNoProviderSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择服务商'**
  String get providerNoProviderSelected;

  /// No description provided for @onDemandDisabled.
  ///
  /// In zh, this message translates to:
  /// **'按需连接已关闭，未做改动'**
  String get onDemandDisabled;

  /// No description provided for @onDemandServerMode.
  ///
  /// In zh, this message translates to:
  /// **'服务器模式不使用隧道，未做改动'**
  String get onDemandServerMode;

  /// No description provided for @onDemandUnknownSsid.
  ///
  /// In zh, this message translates to:
  /// **'无法读取当前 Wi-Fi，未做改动'**
  String get onDemandUnknownSsid;

  /// No description provided for @onDemandSameNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络未变化，保持当前 VPN 状态'**
  String get onDemandSameNetwork;

  /// No description provided for @onDemandNoWifi.
  ///
  /// In zh, this message translates to:
  /// **'当前不在 Wi-Fi 上，已断开 VPN'**
  String get onDemandNoWifi;

  /// No description provided for @onDemandStarted.
  ///
  /// In zh, this message translates to:
  /// **'已匹配白名单，VPN 已启动'**
  String get onDemandStarted;

  /// No description provided for @onDemandAlreadyRunning.
  ///
  /// In zh, this message translates to:
  /// **'已匹配白名单，VPN 正在运行'**
  String get onDemandAlreadyRunning;

  /// No description provided for @onDemandStopped.
  ///
  /// In zh, this message translates to:
  /// **'当前网络不在白名单，已断开 VPN'**
  String get onDemandStopped;

  /// No description provided for @onDemandAlreadyStopped.
  ///
  /// In zh, this message translates to:
  /// **'当前网络不在白名单，VPN 未启动'**
  String get onDemandAlreadyStopped;

  /// No description provided for @onDemandBusy.
  ///
  /// In zh, this message translates to:
  /// **'VPN 正在切换状态，稍后再试'**
  String get onDemandBusy;

  /// No description provided for @onDemandNeedsConsent.
  ///
  /// In zh, this message translates to:
  /// **'已匹配白名单，等待系统 VPN 授权'**
  String get onDemandNeedsConsent;

  /// No description provided for @speedTestSelectProvider.
  ///
  /// In zh, this message translates to:
  /// **'请先选择至少一个测速服务商'**
  String get speedTestSelectProvider;

  /// No description provided for @speedTestEmptyDomain.
  ///
  /// In zh, this message translates to:
  /// **'请输入用于测速的域名'**
  String get speedTestEmptyDomain;

  /// No description provided for @imagePickerUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前设备没有可用的图片选择器'**
  String get imagePickerUnavailable;

  /// No description provided for @serverModeRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先切换到服务器模式'**
  String get serverModeRequired;

  /// No description provided for @serverStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务启动失败'**
  String get serverStartFailed;

  /// No description provided for @serverStartTimeout.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务启动超时'**
  String get serverStartTimeout;

  /// No description provided for @recognitionInvalidConfig.
  ///
  /// In zh, this message translates to:
  /// **'云端名单配置无效'**
  String get recognitionInvalidConfig;

  /// No description provided for @recognitionGithubInterrupted.
  ///
  /// In zh, this message translates to:
  /// **'与 GitHub 的连接被中断，请稍后重试'**
  String get recognitionGithubInterrupted;

  /// No description provided for @recognitionGithubTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接 GitHub 超时，请检查网络后重试'**
  String get recognitionGithubTimeout;

  /// No description provided for @recognitionNetworkUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'网络不可用，无法更新名单'**
  String get recognitionNetworkUnavailable;

  /// No description provided for @recognitionUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'名单更新失败'**
  String get recognitionUpdateFailed;

  /// No description provided for @subscriptionNotFound.
  ///
  /// In zh, this message translates to:
  /// **'订阅不存在或数据库不可用'**
  String get subscriptionNotFound;

  /// No description provided for @subscriptionDatabaseUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'订阅数据库不可用'**
  String get subscriptionDatabaseUnavailable;

  /// No description provided for @subscriptionRuleDbUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'规则库不可用，下载的规则无法入库'**
  String get subscriptionRuleDbUnavailable;

  /// No description provided for @subscriptionUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败'**
  String get subscriptionUpdateFailed;

  /// No description provided for @subscriptionLocalFileUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'无法读取本地文件'**
  String get subscriptionLocalFileUnreadable;

  /// No description provided for @subscriptionLocalRuleDbUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'规则库不可用，本地规则无法入库'**
  String get subscriptionLocalRuleDbUnavailable;

  /// No description provided for @subscriptionNothingToUpdate.
  ///
  /// In zh, this message translates to:
  /// **'没有可更新的订阅'**
  String get subscriptionNothingToUpdate;

  /// No description provided for @subscriptionPickRuleFile.
  ///
  /// In zh, this message translates to:
  /// **'请选择一个规则文件'**
  String get subscriptionPickRuleFile;

  /// No description provided for @subscriptionPickTxtFile.
  ///
  /// In zh, this message translates to:
  /// **'请选择扩展名为 .txt 的规则文件'**
  String get subscriptionPickTxtFile;

  /// No description provided for @subscriptionLegacyDatabaseMissing.
  ///
  /// In zh, this message translates to:
  /// **'订阅数据库不可用（未找到 1.4.3 数据库）'**
  String get subscriptionLegacyDatabaseMissing;

  /// No description provided for @subscriptionThisFile.
  ///
  /// In zh, this message translates to:
  /// **'该文件'**
  String get subscriptionThisFile;

  /// No description provided for @subscriptionThisLink.
  ///
  /// In zh, this message translates to:
  /// **'该订阅链接'**
  String get subscriptionThisLink;

  /// No description provided for @subscriptionLocalRuleFile.
  ///
  /// In zh, this message translates to:
  /// **'本地规则文件'**
  String get subscriptionLocalRuleFile;

  /// No description provided for @webdavEmptyCredentials.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址与用户名不能为空'**
  String get webdavEmptyCredentials;

  /// No description provided for @webdavDirectoryCreated.
  ///
  /// In zh, this message translates to:
  /// **'目录不存在，已自动创建'**
  String get webdavDirectoryCreated;

  /// No description provided for @webdavUploaded.
  ///
  /// In zh, this message translates to:
  /// **'已上传到云端'**
  String get webdavUploaded;

  /// No description provided for @webdavNoBackup.
  ///
  /// In zh, this message translates to:
  /// **'云端还没有备份文件'**
  String get webdavNoBackup;

  /// No description provided for @webdavDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'已从云端取回备份'**
  String get webdavDownloaded;

  /// No description provided for @updateCheckFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先检查更新'**
  String get updateCheckFirst;

  /// No description provided for @updateDownloadFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先下载更新包'**
  String get updateDownloadFirst;

  /// No description provided for @updateInstallerUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法调起系统安装器，请稍后重试'**
  String get updateInstallerUnavailable;

  /// No description provided for @workModeNoDataPlane.
  ///
  /// In zh, this message translates to:
  /// **'当前工作模式尚未接入数据面'**
  String get workModeNoDataPlane;

  /// No description provided for @workModeNoVpnConsent.
  ///
  /// In zh, this message translates to:
  /// **'没有获得 VPN 授权'**
  String get workModeNoVpnConsent;

  /// No description provided for @workModeStartTimeout.
  ///
  /// In zh, this message translates to:
  /// **'服务启动超时'**
  String get workModeStartTimeout;

  /// No description provided for @workModeVpnStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'VPN 启动失败'**
  String get workModeVpnStartFailed;

  /// No description provided for @aiProviderZhipu.
  ///
  /// In zh, this message translates to:
  /// **'智谱 GLM'**
  String get aiProviderZhipu;

  /// No description provided for @aiProviderMoonshot.
  ///
  /// In zh, this message translates to:
  /// **'Kimi（月之暗面）'**
  String get aiProviderMoonshot;

  /// No description provided for @aiProviderDashscope.
  ///
  /// In zh, this message translates to:
  /// **'阿里云百炼（通义千问）'**
  String get aiProviderDashscope;

  /// No description provided for @aiProviderVolcengine.
  ///
  /// In zh, this message translates to:
  /// **'火山方舟（豆包）'**
  String get aiProviderVolcengine;

  /// No description provided for @aiProviderQianfan.
  ///
  /// In zh, this message translates to:
  /// **'百度千帆（ERNIE）'**
  String get aiProviderQianfan;

  /// No description provided for @aiProviderStepfun.
  ///
  /// In zh, this message translates to:
  /// **'阶跃星辰'**
  String get aiProviderStepfun;

  /// No description provided for @aiProviderSiliconflow.
  ///
  /// In zh, this message translates to:
  /// **'硅基流动'**
  String get aiProviderSiliconflow;

  /// No description provided for @aiProviderOllamaLocal.
  ///
  /// In zh, this message translates to:
  /// **'Ollama（本机）'**
  String get aiProviderOllamaLocal;

  /// No description provided for @rulesReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取应用规则失败：{detail}'**
  String rulesReadFailed(String detail);

  /// No description provided for @autoUpdateChecked.
  ///
  /// In zh, this message translates to:
  /// **'已检查 {count} 个订阅'**
  String autoUpdateChecked(int count);

  /// No description provided for @caChannelUnavailableDetail.
  ///
  /// In zh, this message translates to:
  /// **'证书通道不可用：{detail}'**
  String caChannelUnavailableDetail(String detail);

  /// No description provided for @caReadFailedCode.
  ///
  /// In zh, this message translates to:
  /// **'读取根证书失败（{code}）'**
  String caReadFailedCode(String code);

  /// No description provided for @caReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取根证书失败：{detail}'**
  String caReadFailed(String detail);

  /// No description provided for @agentAnalysisFailed.
  ///
  /// In zh, this message translates to:
  /// **'分析失败：{detail}'**
  String agentAnalysisFailed(String detail);

  /// No description provided for @diagnosticsFailedCode.
  ///
  /// In zh, this message translates to:
  /// **'诊断执行失败（{code}）'**
  String diagnosticsFailedCode(String code);

  /// No description provided for @diagnosticsFailed.
  ///
  /// In zh, this message translates to:
  /// **'诊断执行失败：{detail}'**
  String diagnosticsFailed(String detail);

  /// No description provided for @subscriptionDeletedWithId.
  ///
  /// In zh, this message translates to:
  /// **'已删除订阅 #{id}'**
  String subscriptionDeletedWithId(int id);

  /// No description provided for @providerLatencyValue.
  ///
  /// In zh, this message translates to:
  /// **'{value}ms'**
  String providerLatencyValue(int value);

  /// No description provided for @providerRaceSummaryNames.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 个：{names}'**
  String providerRaceSummaryNames(int count, String names);

  /// No description provided for @providerNamesSeparator.
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get providerNamesSeparator;

  /// No description provided for @recognitionInvalidConfigKept.
  ///
  /// In zh, this message translates to:
  /// **'云端名单配置无效（{detail}），已保留本地缓存'**
  String recognitionInvalidConfigKept(String detail);

  /// No description provided for @recognitionFetchFailed.
  ///
  /// In zh, this message translates to:
  /// **'云端名单拉取失败（{detail}）'**
  String recognitionFetchFailed(String detail);

  /// No description provided for @recognitionUpdateFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'名单更新失败：{detail}'**
  String recognitionUpdateFailedDetail(String detail);

  /// No description provided for @subscriptionAlreadyExists.
  ///
  /// In zh, this message translates to:
  /// **'{what}已作为{kind}存在'**
  String subscriptionAlreadyExists(String kind, String what);

  /// No description provided for @subscriptionUpdatedCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个已更新'**
  String subscriptionUpdatedCount(int count);

  /// No description provided for @subscriptionUnchangedCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个未变化'**
  String subscriptionUnchangedCount(int count);

  /// No description provided for @subscriptionFailedCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个失败'**
  String subscriptionFailedCount(int count);

  /// No description provided for @subscriptionAlreadyExistsNamed.
  ///
  /// In zh, this message translates to:
  /// **'{what}已作为{kind}存在（「{name}」）'**
  String subscriptionAlreadyExistsNamed(String kind, String name, String what);

  /// No description provided for @commonBypass.
  ///
  /// In zh, this message translates to:
  /// **'旁路'**
  String get commonBypass;

  /// No description provided for @commonRewrite.
  ///
  /// In zh, this message translates to:
  /// **'覆写'**
  String get commonRewrite;

  /// No description provided for @cleanupLogs.
  ///
  /// In zh, this message translates to:
  /// **'删除请求日志'**
  String get cleanupLogs;

  /// No description provided for @cleanupTraffic.
  ///
  /// In zh, this message translates to:
  /// **'删除流量统计'**
  String get cleanupTraffic;

  /// No description provided for @cleanupCrash.
  ///
  /// In zh, this message translates to:
  /// **'删除崩溃日志'**
  String get cleanupCrash;

  /// No description provided for @cleanupDnsCache.
  ///
  /// In zh, this message translates to:
  /// **'删除 DNS 缓存'**
  String get cleanupDnsCache;

  /// No description provided for @cleanupProviderWeights.
  ///
  /// In zh, this message translates to:
  /// **'恢复 DNS 默认权重'**
  String get cleanupProviderWeights;

  /// No description provided for @cleanupBootstrapWeights.
  ///
  /// In zh, this message translates to:
  /// **'恢复 Bootstrap 权重'**
  String get cleanupBootstrapWeights;

  /// No description provided for @cleanupDomainRules.
  ///
  /// In zh, this message translates to:
  /// **'删除全部域名规则'**
  String get cleanupDomainRules;

  /// No description provided for @cleanupAddressRules.
  ///
  /// In zh, this message translates to:
  /// **'删除全部地址规则'**
  String get cleanupAddressRules;

  /// No description provided for @cleanupSubscriptions.
  ///
  /// In zh, this message translates to:
  /// **'删除全部规则订阅'**
  String get cleanupSubscriptions;

  /// No description provided for @cleanupAppRules.
  ///
  /// In zh, this message translates to:
  /// **'重置应用控制名单'**
  String get cleanupAppRules;

  /// No description provided for @cleanupOutboundProxy.
  ///
  /// In zh, this message translates to:
  /// **'重置出站代理配置'**
  String get cleanupOutboundProxy;

  /// No description provided for @cleanupCaCertificate.
  ///
  /// In zh, this message translates to:
  /// **'重置 HTTPS 抓包证书'**
  String get cleanupCaCertificate;

  /// No description provided for @cleanupDownloadCache.
  ///
  /// In zh, this message translates to:
  /// **'清理下载与临时缓存'**
  String get cleanupDownloadCache;

  /// No description provided for @cleanupCustomBackground.
  ///
  /// In zh, this message translates to:
  /// **'清除自定义背景缓存'**
  String get cleanupCustomBackground;

  /// No description provided for @cleanupSettingsGuides.
  ///
  /// In zh, this message translates to:
  /// **'重置所有新手引导'**
  String get cleanupSettingsGuides;

  /// No description provided for @cleanupAllData.
  ///
  /// In zh, this message translates to:
  /// **'清理全部本地数据'**
  String get cleanupAllData;

  /// No description provided for @cleanupDoneItems.
  ///
  /// In zh, this message translates to:
  /// **'已{action}：{count} 项{detail}'**
  String cleanupDoneItems(String action, int count, String detail);

  /// No description provided for @cleanupDoneEmpty.
  ///
  /// In zh, this message translates to:
  /// **'已{action}：没有可清理的数据'**
  String cleanupDoneEmpty(String action);

  /// No description provided for @blockResponseNxdomain.
  ///
  /// In zh, this message translates to:
  /// **'返回 NXDOMAIN'**
  String get blockResponseNxdomain;

  /// No description provided for @blockResponseNxdomainDescription.
  ///
  /// In zh, this message translates to:
  /// **'返回域名不存在，并提供 5 分钟负缓存以减少重复查询'**
  String get blockResponseNxdomainDescription;

  /// No description provided for @blockResponseNodata.
  ///
  /// In zh, this message translates to:
  /// **'返回 NODATA'**
  String get blockResponseNodata;

  /// No description provided for @blockResponseNodataDescription.
  ///
  /// In zh, this message translates to:
  /// **'返回域名存在但没有该记录，并提供 5 分钟负缓存'**
  String get blockResponseNodataDescription;

  /// No description provided for @blockResponseRefused.
  ///
  /// In zh, this message translates to:
  /// **'返回 REFUSED'**
  String get blockResponseRefused;

  /// No description provided for @blockResponseRefusedDescription.
  ///
  /// In zh, this message translates to:
  /// **'返回服务器拒绝该查询，不提供缓存记录'**
  String get blockResponseRefusedDescription;

  /// No description provided for @blockResponseZeroAddress.
  ///
  /// In zh, this message translates to:
  /// **'返回 0.0.0.0 / ::'**
  String get blockResponseZeroAddress;

  /// No description provided for @blockResponseZeroAddressDescription.
  ///
  /// In zh, this message translates to:
  /// **'A 返回 0.0.0.0，AAAA 返回 ::，其他类型返回空结果'**
  String get blockResponseZeroAddressDescription;

  /// No description provided for @subscriptionSourceRemote.
  ///
  /// In zh, this message translates to:
  /// **'网络订阅'**
  String get subscriptionSourceRemote;

  /// No description provided for @subscriptionSourceLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地文件'**
  String get subscriptionSourceLocal;

  /// No description provided for @subscriptionKindDomain.
  ///
  /// In zh, this message translates to:
  /// **'黑白名单规则'**
  String get subscriptionKindDomain;

  /// No description provided for @subscriptionKindHosts.
  ///
  /// In zh, this message translates to:
  /// **'hosts 规则'**
  String get subscriptionKindHosts;

  /// No description provided for @logRowDirect.
  ///
  /// In zh, this message translates to:
  /// **'{protocol} 直连'**
  String logRowDirect(String protocol);

  /// No description provided for @logRowDirectWithPackage.
  ///
  /// In zh, this message translates to:
  /// **'{protocol} 直连 · {package}'**
  String logRowDirectWithPackage(String package, String protocol);

  /// No description provided for @logRowCacheHit.
  ///
  /// In zh, this message translates to:
  /// **'命中缓存'**
  String get logRowCacheHit;

  /// No description provided for @logRowNoAuthority.
  ///
  /// In zh, this message translates to:
  /// **'未取得 authority'**
  String get logRowNoAuthority;

  /// No description provided for @cachePresetConservativeName.
  ///
  /// In zh, this message translates to:
  /// **'保守'**
  String get cachePresetConservativeName;

  /// No description provided for @cachePresetConservativeSummary.
  ///
  /// In zh, this message translates to:
  /// **'遵从服务器有效期 (TTL)'**
  String get cachePresetConservativeSummary;

  /// No description provided for @cachePresetConservativeDescription.
  ///
  /// In zh, this message translates to:
  /// **'遵从 DNS 服务器返回的有效期，不主动延长缓存时间，适合经常切换网络或对实时性敏感的场景。'**
  String get cachePresetConservativeDescription;

  /// No description provided for @cachePresetStandardName.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get cachePresetStandardName;

  /// No description provided for @cachePresetStandardSummary.
  ///
  /// In zh, this message translates to:
  /// **'最长 1 小时，短记录至少 1 分钟'**
  String get cachePresetStandardSummary;

  /// No description provided for @cachePresetStandardDescription.
  ///
  /// In zh, this message translates to:
  /// **'减少重复查询，同时避免记录过期滞后。解析失败时可短暂使用 5 分钟内的旧记录应急。'**
  String get cachePresetStandardDescription;

  /// No description provided for @cachePresetAggressiveName.
  ///
  /// In zh, this message translates to:
  /// **'高命中'**
  String get cachePresetAggressiveName;

  /// No description provided for @cachePresetAggressiveSummary.
  ///
  /// In zh, this message translates to:
  /// **'最长 6 小时，短记录至少 2 分钟'**
  String get cachePresetAggressiveSummary;

  /// No description provided for @cachePresetAggressiveDescription.
  ///
  /// In zh, this message translates to:
  /// **'更偏向降低网络请求次数和提升弱网可用性。域名变更时更新可能会稍慢一些。'**
  String get cachePresetAggressiveDescription;

  /// No description provided for @cacheDisabledSummary.
  ///
  /// In zh, this message translates to:
  /// **'已关闭 · 每次解析都会请求上游'**
  String get cacheDisabledSummary;

  /// No description provided for @upstreamNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写名称'**
  String get upstreamNameRequired;

  /// No description provided for @upstreamAddressRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写地址'**
  String get upstreamAddressRequired;

  /// No description provided for @upstreamDohNeedsHttps.
  ///
  /// In zh, this message translates to:
  /// **'DoH 地址必须以 https:// 开头'**
  String get upstreamDohNeedsHttps;

  /// No description provided for @upstreamDohInvalidUrl.
  ///
  /// In zh, this message translates to:
  /// **'DoH 地址不是合法的 URL'**
  String get upstreamDohInvalidUrl;

  /// No description provided for @upstreamPortRange.
  ///
  /// In zh, this message translates to:
  /// **'端口需在 1–65535 之间'**
  String get upstreamPortRange;

  /// No description provided for @upstreamIpv6Invalid.
  ///
  /// In zh, this message translates to:
  /// **'IPv6 地址格式不正确'**
  String get upstreamIpv6Invalid;

  /// No description provided for @upstreamPresetAliyun.
  ///
  /// In zh, this message translates to:
  /// **'阿里云'**
  String get upstreamPresetAliyun;

  /// No description provided for @upstreamPresetTencent.
  ///
  /// In zh, this message translates to:
  /// **'腾讯云 DNSPod'**
  String get upstreamPresetTencent;

  /// No description provided for @upstreamPresetByteDance.
  ///
  /// In zh, this message translates to:
  /// **'字节跳动'**
  String get upstreamPresetByteDance;

  /// No description provided for @cleanupFailed.
  ///
  /// In zh, this message translates to:
  /// **'清理失败：{detail}'**
  String cleanupFailed(String detail);

  /// No description provided for @cleanupProxyRestored.
  ///
  /// In zh, this message translates to:
  /// **'已恢复直连'**
  String get cleanupProxyRestored;

  /// No description provided for @cleanupCaNeedsReimport.
  ///
  /// In zh, this message translates to:
  /// **'需重新生成并导入系统证书'**
  String get cleanupCaNeedsReimport;

  /// No description provided for @hubCategoryDns.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务'**
  String get hubCategoryDns;

  /// No description provided for @hubProviderManagement.
  ///
  /// In zh, this message translates to:
  /// **'服务商管理'**
  String get hubProviderManagement;

  /// No description provided for @hubProviderManagementDescription.
  ///
  /// In zh, this message translates to:
  /// **'配置与管理 DoH、DoT 与传统 DNS 解析服务商'**
  String get hubProviderManagementDescription;

  /// No description provided for @hubBootstrap.
  ///
  /// In zh, this message translates to:
  /// **'引导解析设置'**
  String get hubBootstrap;

  /// No description provided for @hubBootstrapDescription.
  ///
  /// In zh, this message translates to:
  /// **'配置用于首次解析加密上游域名的引导 DNS 节点'**
  String get hubBootstrapDescription;

  /// No description provided for @hubResolution.
  ///
  /// In zh, this message translates to:
  /// **'解析模式'**
  String get hubResolution;

  /// No description provided for @hubResolutionDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择单一服务、智能选择、最快响应或依次尝试策略'**
  String get hubResolutionDescription;

  /// No description provided for @hubCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存设置'**
  String get hubCache;

  /// No description provided for @hubCacheDescription.
  ///
  /// In zh, this message translates to:
  /// **'配置 DNS 缓存开关、缓存策略与最大最小生存时间 (TTL)'**
  String get hubCacheDescription;

  /// No description provided for @hubCategoryRules.
  ///
  /// In zh, this message translates to:
  /// **'策略与规则'**
  String get hubCategoryRules;

  /// No description provided for @hubRuleControl.
  ///
  /// In zh, this message translates to:
  /// **'规则控制'**
  String get hubRuleControl;

  /// No description provided for @hubRuleControlDescription.
  ///
  /// In zh, this message translates to:
  /// **'统一管理拦截策略开关与在线网络规则订阅'**
  String get hubRuleControlDescription;

  /// No description provided for @hubBlocklist.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get hubBlocklist;

  /// No description provided for @hubBlocklistDescription.
  ///
  /// In zh, this message translates to:
  /// **'自定义屏蔽域名列表，匹配时返回拦截响应'**
  String get hubBlocklistDescription;

  /// No description provided for @hubAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'白名单'**
  String get hubAllowlist;

  /// No description provided for @hubAllowlistDescription.
  ///
  /// In zh, this message translates to:
  /// **'自定义放行域名列表，豁免所有规则直接放行'**
  String get hubAllowlistDescription;

  /// No description provided for @hubRewrite.
  ///
  /// In zh, this message translates to:
  /// **'覆写名单'**
  String get hubRewrite;

  /// No description provided for @hubRewriteDescription.
  ///
  /// In zh, this message translates to:
  /// **'自定义域名覆写指向特定 IPv4/IPv6 或 CNAME'**
  String get hubRewriteDescription;

  /// No description provided for @hubCategoryNetwork.
  ///
  /// In zh, this message translates to:
  /// **'应用管理'**
  String get hubCategoryNetwork;

  /// No description provided for @hubAppTraffic.
  ///
  /// In zh, this message translates to:
  /// **'应用流量统计'**
  String get hubAppTraffic;

  /// No description provided for @hubAppTrafficDescription.
  ///
  /// In zh, this message translates to:
  /// **'统计各应用的网络连接数、上传与下载流量明细'**
  String get hubAppTrafficDescription;

  /// No description provided for @hubAppRules.
  ///
  /// In zh, this message translates to:
  /// **'应用独立规则'**
  String get hubAppRules;

  /// No description provided for @hubAppRulesDescription.
  ///
  /// In zh, this message translates to:
  /// **'为特定应用单独指定专属域名放行与网络规则'**
  String get hubAppRulesDescription;

  /// No description provided for @hubBlockedApps.
  ///
  /// In zh, this message translates to:
  /// **'禁止联网应用'**
  String get hubBlockedApps;

  /// No description provided for @hubBlockedAppsDescription.
  ///
  /// In zh, this message translates to:
  /// **'在本地隧道层拦截指定应用的全部网络外联'**
  String get hubBlockedAppsDescription;

  /// No description provided for @hubExcludedApps.
  ///
  /// In zh, this message translates to:
  /// **'排除应用'**
  String get hubExcludedApps;

  /// No description provided for @hubExcludedAppsDescription.
  ///
  /// In zh, this message translates to:
  /// **'允许指定应用绕过本软件直连网络'**
  String get hubExcludedAppsDescription;

  /// No description provided for @hubCategoryAdvanced.
  ///
  /// In zh, this message translates to:
  /// **'高级与诊断'**
  String get hubCategoryAdvanced;

  /// No description provided for @hubHttpsInspection.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 流量检查'**
  String get hubHttpsInspection;

  /// No description provided for @hubHttpsInspectionDescription.
  ///
  /// In zh, this message translates to:
  /// **'解密并检查特定应用的 HTTP(S) 流量，支持域名与 URL 过滤'**
  String get hubHttpsInspectionDescription;

  /// No description provided for @hubOutboundProxy.
  ///
  /// In zh, this message translates to:
  /// **'出站代理'**
  String get hubOutboundProxy;

  /// No description provided for @hubOutboundProxyDescription.
  ///
  /// In zh, this message translates to:
  /// **'将过滤后的流量转发到本地 SOCKS5 或 HTTP 代理'**
  String get hubOutboundProxyDescription;

  /// No description provided for @hubDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'网络诊断'**
  String get hubDiagnostics;

  /// No description provided for @hubDiagnosticsDescription.
  ///
  /// In zh, this message translates to:
  /// **'提供 DNS 查询、Ping 延迟测试与网络连通性诊断工具'**
  String get hubDiagnosticsDescription;

  /// No description provided for @hubAiAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'AI 分析'**
  String get hubAiAnalysis;

  /// No description provided for @hubAiAnalysisDescription.
  ///
  /// In zh, this message translates to:
  /// **'配置大语言模型接口与密钥，用于日志研判与网络流量分析'**
  String get hubAiAnalysisDescription;

  /// No description provided for @hubCategoryInterface.
  ///
  /// In zh, this message translates to:
  /// **'界面与设置'**
  String get hubCategoryInterface;

  /// No description provided for @hubAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观调整'**
  String get hubAppearance;

  /// No description provided for @hubAppearanceDescription.
  ///
  /// In zh, this message translates to:
  /// **'自定义日夜模式、主题色彩、组件透明度与软件壁纸背景'**
  String get hubAppearanceDescription;

  /// No description provided for @hubProviderVisibility.
  ///
  /// In zh, this message translates to:
  /// **'服务显示'**
  String get hubProviderVisibility;

  /// No description provided for @hubProviderVisibilityDescription.
  ///
  /// In zh, this message translates to:
  /// **'自定义在首页解析服务下拉列表中显示的服务商'**
  String get hubProviderVisibilityDescription;

  /// No description provided for @hubHiddenFeatures.
  ///
  /// In zh, this message translates to:
  /// **'隐藏功能'**
  String get hubHiddenFeatures;

  /// No description provided for @hubHiddenFeaturesDescription.
  ///
  /// In zh, this message translates to:
  /// **'自定义在功能中心显示的功能卡片，不改后台运行'**
  String get hubHiddenFeaturesDescription;

  /// No description provided for @hubOtherSettings.
  ///
  /// In zh, this message translates to:
  /// **'其他设置'**
  String get hubOtherSettings;

  /// No description provided for @hubOtherSettingsDescription.
  ///
  /// In zh, this message translates to:
  /// **'语言切换、前后台行为、通知设置等全局配置'**
  String get hubOtherSettingsDescription;

  /// No description provided for @hubCategoryData.
  ///
  /// In zh, this message translates to:
  /// **'数据与维护'**
  String get hubCategoryData;

  /// No description provided for @hubLogs.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get hubLogs;

  /// No description provided for @hubLogsDescription.
  ///
  /// In zh, this message translates to:
  /// **'实时解析统计、请求明细查询与日志导出'**
  String get hubLogsDescription;

  /// No description provided for @hubBackup.
  ///
  /// In zh, this message translates to:
  /// **'备份与迁移'**
  String get hubBackup;

  /// No description provided for @hubBackupDescription.
  ///
  /// In zh, this message translates to:
  /// **'导出与导入服务商、规则订阅及个性化设置'**
  String get hubBackupDescription;

  /// No description provided for @hubDataCleanup.
  ///
  /// In zh, this message translates to:
  /// **'数据清理'**
  String get hubDataCleanup;

  /// No description provided for @hubDataCleanupDescription.
  ///
  /// In zh, this message translates to:
  /// **'删除缓存、日志或域名与地址过滤规则'**
  String get hubDataCleanupDescription;

  /// No description provided for @hubTroubleshooting.
  ///
  /// In zh, this message translates to:
  /// **'故障排查'**
  String get hubTroubleshooting;

  /// No description provided for @hubTroubleshootingDescription.
  ///
  /// In zh, this message translates to:
  /// **'导出崩溃日志，手动抓取并导出运行日志发给开发者'**
  String get hubTroubleshootingDescription;

  /// No description provided for @hubCategoryNetworkTools.
  ///
  /// In zh, this message translates to:
  /// **'网络工具与隐私'**
  String get hubCategoryNetworkTools;

  /// No description provided for @hubCategoryAutomation.
  ///
  /// In zh, this message translates to:
  /// **'自动化与场景'**
  String get hubCategoryAutomation;

  /// No description provided for @hubCategoryIntegration.
  ///
  /// In zh, this message translates to:
  /// **'接口与联动'**
  String get hubCategoryIntegration;

  /// No description provided for @hubCategorySubscription.
  ///
  /// In zh, this message translates to:
  /// **'订阅与更新'**
  String get hubCategorySubscription;

  /// No description provided for @hubDnsLeak.
  ///
  /// In zh, this message translates to:
  /// **'DNS 泄漏检测'**
  String get hubDnsLeak;

  /// No description provided for @hubAutoUpdateDescription.
  ///
  /// In zh, this message translates to:
  /// **'按固定间隔或每天固定时刻自动更新规则订阅'**
  String get hubAutoUpdateDescription;

  /// No description provided for @hubCategoryAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于谛听'**
  String get hubCategoryAbout;

  /// No description provided for @hubAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get hubAbout;

  /// No description provided for @hubAboutDescription.
  ///
  /// In zh, this message translates to:
  /// **'查看版本信息、检查更新、开源地址与贡献者名单'**
  String get hubAboutDescription;

  /// No description provided for @hubSponsor.
  ///
  /// In zh, this message translates to:
  /// **'赞助'**
  String get hubSponsor;

  /// No description provided for @hubSponsorDescription.
  ///
  /// In zh, this message translates to:
  /// **'支持谛听项目持续维护与开发'**
  String get hubSponsorDescription;

  /// No description provided for @hubSponsors.
  ///
  /// In zh, this message translates to:
  /// **'赞助者名单'**
  String get hubSponsors;

  /// No description provided for @hubSponsorsDescription.
  ///
  /// In zh, this message translates to:
  /// **'鸣谢支持谛听项目的赞助者'**
  String get hubSponsorsDescription;

  /// No description provided for @hubContributors.
  ///
  /// In zh, this message translates to:
  /// **'共建者名单'**
  String get hubContributors;

  /// No description provided for @hubContributorsDescription.
  ///
  /// In zh, this message translates to:
  /// **'感谢为谛听贡献代码与建议的共建者'**
  String get hubContributorsDescription;

  /// No description provided for @fontSizeSmall.
  ///
  /// In zh, this message translates to:
  /// **'小'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get fontSizeStandard;

  /// No description provided for @fontSizeLarge.
  ///
  /// In zh, this message translates to:
  /// **'大'**
  String get fontSizeLarge;

  /// No description provided for @fontSizeExtraLarge.
  ///
  /// In zh, this message translates to:
  /// **'特大'**
  String get fontSizeExtraLarge;

  /// No description provided for @fontSizeFooter.
  ///
  /// In zh, this message translates to:
  /// **'字号会同时放大正文、标题与列表行，不会改变系统设置；界面已按所选比例排版，无需重启。'**
  String get fontSizeFooter;

  /// No description provided for @fontSizePreview.
  ///
  /// In zh, this message translates to:
  /// **'实时预览'**
  String get fontSizePreview;

  /// No description provided for @appearancePoem.
  ///
  /// In zh, this message translates to:
  /// **'谛听万象，明察清浊'**
  String get appearancePoem;

  /// No description provided for @appearancePoemBody.
  ///
  /// In zh, this message translates to:
  /// **'网络连通性、规则命中与设备状态，都在这一页里说清楚。'**
  String get appearancePoemBody;

  /// No description provided for @appearanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'外观设置'**
  String get appearanceTitle;

  /// No description provided for @appearanceInterfaceSection.
  ///
  /// In zh, this message translates to:
  /// **'界面显示'**
  String get appearanceInterfaceSection;

  /// No description provided for @appearanceHomeOpacitySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'交互组件与文字的透明度'**
  String get appearanceHomeOpacitySubtitle;

  /// No description provided for @appearancePureBlackOn.
  ///
  /// In zh, this message translates to:
  /// **'深色表面折叠为纯黑，OLED 更省电'**
  String get appearancePureBlackOn;

  /// No description provided for @appearancePureBlackOff.
  ///
  /// In zh, this message translates to:
  /// **'切到深色模式后才可开启'**
  String get appearancePureBlackOff;

  /// No description provided for @appearanceHomeSection.
  ///
  /// In zh, this message translates to:
  /// **'首页内容'**
  String get appearanceHomeSection;

  /// No description provided for @appearanceHomeSentenceSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'运行与停止两种状态各一句'**
  String get appearanceHomeSentenceSubtitle;

  /// No description provided for @appearanceNotification.
  ///
  /// In zh, this message translates to:
  /// **'通知栏设置'**
  String get appearanceNotification;

  /// No description provided for @appearanceNotificationSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'常驻通知、实时速率与自定义文案'**
  String get appearanceNotificationSubtitle;

  /// No description provided for @appearanceBackgroundSection.
  ///
  /// In zh, this message translates to:
  /// **'背景与动效'**
  String get appearanceBackgroundSection;

  /// No description provided for @appearanceHapticSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换 tab 时给一次轻震'**
  String get appearanceHapticSubtitle;

  /// No description provided for @appearanceBottomBarStyleFloating.
  ///
  /// In zh, this message translates to:
  /// **'浮在页面之上'**
  String get appearanceBottomBarStyleFloating;

  /// No description provided for @appearanceBottomBarStyleDocked.
  ///
  /// In zh, this message translates to:
  /// **'贴底排列'**
  String get appearanceBottomBarStyleDocked;

  /// No description provided for @appearanceTabTransitionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换底部标签时的动画方式'**
  String get appearanceTabTransitionSubtitle;

  /// No description provided for @appearanceMotionFooter.
  ///
  /// In zh, this message translates to:
  /// **'底栏样式、动画与玻璃只作用于浮条；普通底栏始终是实色。'**
  String get appearanceMotionFooter;

  /// No description provided for @appearancePaletteGoldLegacy.
  ///
  /// In zh, this message translates to:
  /// **'落盘值沿用旧版的 indigo'**
  String get appearancePaletteGoldLegacy;

  /// No description provided for @appearancePaletteFooter.
  ///
  /// In zh, this message translates to:
  /// **'色板只提供种子，上屏的是 HCT 推导出的整套角色色。旧版没有自定义取色，因此这里也不提供。'**
  String get appearancePaletteFooter;

  /// No description provided for @launcherIconTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用图标'**
  String get launcherIconTitle;

  /// No description provided for @launcherIconInfoLabel.
  ///
  /// In zh, this message translates to:
  /// **'选择桌面显示的应用图标'**
  String get launcherIconInfoLabel;

  /// No description provided for @launcherIconDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get launcherIconDefault;

  /// No description provided for @launcherIconDefaultDescription.
  ///
  /// In zh, this message translates to:
  /// **'谛听默认图标'**
  String get launcherIconDefaultDescription;

  /// No description provided for @launcherIconAdguard.
  ///
  /// In zh, this message translates to:
  /// **'AdGuard'**
  String get launcherIconAdguard;

  /// No description provided for @launcherIconAdguardDescription.
  ///
  /// In zh, this message translates to:
  /// **'绿色盾牌与白色对勾'**
  String get launcherIconAdguardDescription;

  /// No description provided for @launcherIconFooter.
  ///
  /// In zh, this message translates to:
  /// **'系统没有在运行时替换图标的接口，切换通过启用对应的启动入口实现。返回桌面即可看到；若桌面缓存未刷新，请稍候或重启桌面。'**
  String get launcherIconFooter;

  /// No description provided for @launcherIconApplied.
  ///
  /// In zh, this message translates to:
  /// **'已切换应用图标，返回桌面即可看到'**
  String get launcherIconApplied;

  /// No description provided for @launcherIconApplyFailed.
  ///
  /// In zh, this message translates to:
  /// **'切换应用图标失败，请稍后重试'**
  String get launcherIconApplyFailed;

  /// No description provided for @fontFamilySizeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'当前 {percent}%'**
  String fontFamilySizeSubtitle(String percent);

  /// No description provided for @fontFamilySystemDefault.
  ///
  /// In zh, this message translates to:
  /// **'跟随宿主平台的中文界面字体，最稳妥的选择'**
  String get fontFamilySystemDefault;

  /// No description provided for @fontFamilyImported.
  ///
  /// In zh, this message translates to:
  /// **'已导入的第三方字体'**
  String get fontFamilyImported;

  /// No description provided for @fontFamilyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有导入字体。导入后即可在这里切换，字体文件只保存在本机。'**
  String get fontFamilyEmpty;

  /// No description provided for @fontFamilyFooter.
  ///
  /// In zh, this message translates to:
  /// **'导入的字体只影响本机显示，删除后会自动回退到系统默认。'**
  String get fontFamilyFooter;

  /// No description provided for @fontFamilyLocalOnly.
  ///
  /// In zh, this message translates to:
  /// **'选择只影响本机显示，不改动服务端规则。'**
  String get fontFamilyLocalOnly;

  /// No description provided for @fontFamilyImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败'**
  String get fontFamilyImportFailed;

  /// No description provided for @fontFamilyDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除字体'**
  String get fontFamilyDeleteTitle;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @fontFamilyDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除「{name}」后，使用该字体的界面会回退到系统默认。'**
  String fontFamilyDeleteConfirm(String name);

  /// No description provided for @fontFamilyImport.
  ///
  /// In zh, this message translates to:
  /// **'导入字体'**
  String get fontFamilyImport;

  /// No description provided for @fontFamilyReading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取字体文件…'**
  String get fontFamilyReading;

  /// No description provided for @fontFamilyPickFile.
  ///
  /// In zh, this message translates to:
  /// **'选择本机的 TTF / OTF 文件'**
  String get fontFamilyPickFile;

  /// No description provided for @notificationPersistentSection.
  ///
  /// In zh, this message translates to:
  /// **'常驻通知'**
  String get notificationPersistentSection;

  /// No description provided for @notificationPersistentFooter.
  ///
  /// In zh, this message translates to:
  /// **'关闭后服务运行时不再显示常驻通知，系统可能因此更快回收进程。'**
  String get notificationPersistentFooter;

  /// No description provided for @notificationPersistent.
  ///
  /// In zh, this message translates to:
  /// **'通知常驻'**
  String get notificationPersistent;

  /// No description provided for @notificationPersistentSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'服务运行时保留一条不可划掉的通知'**
  String get notificationPersistentSubtitle;

  /// No description provided for @notificationShowSpeedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在通知里显示当前上下行速率'**
  String get notificationShowSpeedSubtitle;

  /// No description provided for @notificationStatsSection.
  ///
  /// In zh, this message translates to:
  /// **'通知详情'**
  String get notificationStatsSection;

  /// No description provided for @notificationStatsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未显示任何详情，通知只保留状态文案'**
  String get notificationStatsEmpty;

  /// No description provided for @notificationStatsFooter.
  ///
  /// In zh, this message translates to:
  /// **'统计从本次服务启动开始累计，与日志记录模式无关；已开启的项目按住拖动可调整顺序。极速与服务器模式没有实时网速，该项会自动省略。'**
  String get notificationStatsFooter;

  /// No description provided for @notificationStatsHidden.
  ///
  /// In zh, this message translates to:
  /// **'未显示的项目'**
  String get notificationStatsHidden;

  /// No description provided for @notificationStatTotal.
  ///
  /// In zh, this message translates to:
  /// **'请求'**
  String get notificationStatTotal;

  /// No description provided for @notificationStatSpeed.
  ///
  /// In zh, this message translates to:
  /// **'实时网速'**
  String get notificationStatSpeed;

  /// No description provided for @notificationStatTotalSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'本次运行处理的请求总数（DNS 与 HTTPS）'**
  String get notificationStatTotalSubtitle;

  /// No description provided for @notificationStatPassedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'正常放行的请求，含覆写后返回的结果'**
  String get notificationStatPassedSubtitle;

  /// No description provided for @notificationStatFilteredSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'被规则过滤拦截的请求'**
  String get notificationStatFilteredSubtitle;

  /// No description provided for @notificationStatFailedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'解析或处理失败的请求'**
  String get notificationStatFailedSubtitle;

  /// No description provided for @notificationStatCachedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'由本机缓存直接应答的请求'**
  String get notificationStatCachedSubtitle;

  /// No description provided for @notificationStatRewrittenSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'命中覆写规则、返回改写结果的请求'**
  String get notificationStatRewrittenSubtitle;

  /// No description provided for @notificationTextRunning.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务开启时'**
  String get notificationTextRunning;

  /// No description provided for @notificationTextStopped.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务关闭时'**
  String get notificationTextStopped;

  /// No description provided for @notificationTextHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用默认文案'**
  String get notificationTextHint;

  /// No description provided for @notificationTextSection.
  ///
  /// In zh, this message translates to:
  /// **'通知文案'**
  String get notificationTextSection;

  /// No description provided for @notificationTextFooter.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用默认文案；文案只影响通知栏，不改变服务行为。'**
  String get notificationTextFooter;

  /// No description provided for @notificationPermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get notificationPermissions;

  /// No description provided for @notificationSystemPermission.
  ///
  /// In zh, this message translates to:
  /// **'系统通知权限'**
  String get notificationSystemPermission;

  /// No description provided for @notificationSystemPermissionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'打开系统的通知设置页'**
  String get notificationSystemPermissionSubtitle;

  /// No description provided for @backgroundTitle.
  ///
  /// In zh, this message translates to:
  /// **'软件背景'**
  String get backgroundTitle;

  /// No description provided for @backgroundSection.
  ///
  /// In zh, this message translates to:
  /// **'自定义背景'**
  String get backgroundSection;

  /// No description provided for @backgroundFooter.
  ///
  /// In zh, this message translates to:
  /// **'壁纸只保存在本机，不随备份导出。'**
  String get backgroundFooter;

  /// No description provided for @backgroundEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用自定义背景'**
  String get backgroundEnable;

  /// No description provided for @backgroundPickFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先添加一张图片'**
  String get backgroundPickFirst;

  /// No description provided for @backgroundBehindPages.
  ///
  /// In zh, this message translates to:
  /// **'在全部页面下垫一层壁纸'**
  String get backgroundBehindPages;

  /// No description provided for @backgroundAddImage.
  ///
  /// In zh, this message translates to:
  /// **'添加图片'**
  String get backgroundAddImage;

  /// No description provided for @backgroundAddImageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从相册选择一张'**
  String get backgroundAddImageSubtitle;

  /// No description provided for @backgroundAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加壁纸'**
  String get backgroundAdded;

  /// No description provided for @backgroundAddedFooter.
  ///
  /// In zh, this message translates to:
  /// **'点一下切换，长按删除。'**
  String get backgroundAddedFooter;

  /// No description provided for @backgroundEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有背景图'**
  String get backgroundEmpty;

  /// No description provided for @backgroundEmptyDescription.
  ///
  /// In zh, this message translates to:
  /// **'点「添加图片」从相册里挑一张。'**
  String get backgroundEmptyDescription;

  /// No description provided for @backgroundDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除壁纸'**
  String get backgroundDeleteTitle;

  /// No description provided for @backgroundDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除这张已添加的壁纸吗？'**
  String get backgroundDeleteConfirm;

  /// No description provided for @foregroundTitle.
  ///
  /// In zh, this message translates to:
  /// **'前后台行为'**
  String get foregroundTitle;

  /// No description provided for @foregroundPrivacySection.
  ///
  /// In zh, this message translates to:
  /// **'后台与隐私'**
  String get foregroundPrivacySection;

  /// No description provided for @foregroundPrivacyFooter.
  ///
  /// In zh, this message translates to:
  /// **'「后台隐藏」会从最近任务列表里移除本应用；下次从桌面图标进入即可。'**
  String get foregroundPrivacyFooter;

  /// No description provided for @foregroundHide.
  ///
  /// In zh, this message translates to:
  /// **'后台隐藏'**
  String get foregroundHide;

  /// No description provided for @foregroundHideSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'不在最近任务列表中显示'**
  String get foregroundHideSubtitle;

  /// No description provided for @foregroundRouting.
  ///
  /// In zh, this message translates to:
  /// **'路由'**
  String get foregroundRouting;

  /// No description provided for @foregroundBypassLan.
  ///
  /// In zh, this message translates to:
  /// **'绕过局域网'**
  String get foregroundBypassLan;

  /// No description provided for @foregroundBypassLanSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'本地网段与本机地址不走隧道'**
  String get foregroundBypassLanSubtitle;

  /// No description provided for @foregroundStability.
  ///
  /// In zh, this message translates to:
  /// **'稳定性'**
  String get foregroundStability;

  /// No description provided for @foregroundBatteryFooter.
  ///
  /// In zh, this message translates to:
  /// **'关闭电池优化后，系统在后台更不容易回收服务进程。'**
  String get foregroundBatteryFooter;

  /// No description provided for @foregroundIgnoreBattery.
  ///
  /// In zh, this message translates to:
  /// **'忽略电池优化'**
  String get foregroundIgnoreBattery;

  /// No description provided for @foregroundIgnoreBatterySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'请求把本应用加入系统白名单'**
  String get foregroundIgnoreBatterySubtitle;

  /// No description provided for @dayNightTitle.
  ///
  /// In zh, this message translates to:
  /// **'日夜模式'**
  String get dayNightTitle;

  /// No description provided for @dayNightFollowSystemDescription.
  ///
  /// In zh, this message translates to:
  /// **'系统切换深色时一起切换'**
  String get dayNightFollowSystemDescription;

  /// No description provided for @dayNightFooter.
  ///
  /// In zh, this message translates to:
  /// **'纯黑只在深色模式下生效，开关在「外观设置」的界面显示组里。'**
  String get dayNightFooter;

  /// No description provided for @homeOpacityTitle.
  ///
  /// In zh, this message translates to:
  /// **'首页透明度'**
  String get homeOpacityTitle;

  /// No description provided for @homeOpacityComponents.
  ///
  /// In zh, this message translates to:
  /// **'交互组件'**
  String get homeOpacityComponents;

  /// No description provided for @homeOpacityComponentsFooter.
  ///
  /// In zh, this message translates to:
  /// **'透明度只影响可见度，不影响这些组件的点击区域。'**
  String get homeOpacityComponentsFooter;

  /// No description provided for @homeOpacityText.
  ///
  /// In zh, this message translates to:
  /// **'文字'**
  String get homeOpacityText;

  /// No description provided for @bottomBarHomeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'首页与仪表盘'**
  String get bottomBarHomeSubtitle;

  /// No description provided for @bottomBarFeatureHubSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'全部功能入口'**
  String get bottomBarFeatureHubSubtitle;

  /// No description provided for @bottomBarLogDashboardSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'日志仪表盘'**
  String get bottomBarLogDashboardSubtitle;

  /// No description provided for @bottomBarAppTrafficSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'应用流量排行'**
  String get bottomBarAppTrafficSubtitle;

  /// No description provided for @bottomBarNetworkToolsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'测速与网络诊断'**
  String get bottomBarNetworkToolsSubtitle;

  /// No description provided for @bottomBarSettingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'全部设置项'**
  String get bottomBarSettingsSubtitle;

  /// No description provided for @bottomBarMinimumHint.
  ///
  /// In zh, this message translates to:
  /// **'底栏至少保留 2 项'**
  String get bottomBarMinimumHint;

  /// No description provided for @bottomBarCustomTitle.
  ///
  /// In zh, this message translates to:
  /// **'底栏自定义'**
  String get bottomBarCustomTitle;

  /// No description provided for @bottomBarItemsHeader.
  ///
  /// In zh, this message translates to:
  /// **'底栏项（{count}/{max}）'**
  String bottomBarItemsHeader(String count, String max);

  /// No description provided for @bottomBarDragHint.
  ///
  /// In zh, this message translates to:
  /// **'按住右侧把手或长按整行拖动排序，顺序即底栏从左到右的顺序。至少 2 项、最多 {max} 项：浮条按项数等比分配宽度，再多就挤到看不清图标。'**
  String bottomBarDragHint(String max);

  /// No description provided for @bottomBarDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get bottomBarDisabled;

  /// No description provided for @bottomBarNewItemFooter.
  ///
  /// In zh, this message translates to:
  /// **'新启用的项排在底栏最右侧。'**
  String get bottomBarNewItemFooter;

  /// No description provided for @bottomBarFeel.
  ///
  /// In zh, this message translates to:
  /// **'手感'**
  String get bottomBarFeel;

  /// No description provided for @homeSentenceTitle.
  ///
  /// In zh, this message translates to:
  /// **'首页句子'**
  String get homeSentenceTitle;

  /// No description provided for @homeSentenceFooter.
  ///
  /// In zh, this message translates to:
  /// **'两项均可留空；留空后对应状态下首页不显示句子，句子只在首页电源区下方出现一次。'**
  String get homeSentenceFooter;

  /// No description provided for @appearancePaletteTitle.
  ///
  /// In zh, this message translates to:
  /// **'主题色配置'**
  String get appearancePaletteTitle;

  /// No description provided for @appearancePaletteInfoLabel.
  ///
  /// In zh, this message translates to:
  /// **'色板'**
  String get appearancePaletteInfoLabel;

  /// No description provided for @appearancePaletteBody.
  ///
  /// In zh, this message translates to:
  /// **'色板只提供种子，上屏的是 HCT 推导出的整套角色色。旧版没有自定义取色，因此这里也不提供。'**
  String get appearancePaletteBody;

  /// No description provided for @dayNightInfoLabel.
  ///
  /// In zh, this message translates to:
  /// **'模式'**
  String get dayNightInfoLabel;

  /// No description provided for @appearanceFontSizeLabel.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get appearanceFontSizeLabel;

  /// No description provided for @appearanceFontSizeCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前 {percent}%'**
  String appearanceFontSizeCurrent(int percent);

  /// No description provided for @appearanceFontSection.
  ///
  /// In zh, this message translates to:
  /// **'字体'**
  String get appearanceFontSection;

  /// No description provided for @appearanceFontImported.
  ///
  /// In zh, this message translates to:
  /// **'已导入 {name}'**
  String appearanceFontImported(String name);

  /// No description provided for @appearanceFontDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {name}'**
  String appearanceFontDeleted(String name);

  /// No description provided for @appearanceBottomBarMax.
  ///
  /// In zh, this message translates to:
  /// **'底栏最多 {max} 项'**
  String appearanceBottomBarMax(int max);

  /// No description provided for @appearanceBottomBarHeader.
  ///
  /// In zh, this message translates to:
  /// **'底栏项（{count}/{max}）'**
  String appearanceBottomBarHeader(int count, int max);

  /// No description provided for @appearanceBottomBarDragBody.
  ///
  /// In zh, this message translates to:
  /// **'按住右侧把手或长按整行拖动排序，顺序即底栏从左到右的顺序。至少 2 项、最多 {max} 项：浮条按项数等比分配宽度，再多就挤到看不清图标。'**
  String appearanceBottomBarDragBody(int max);

  /// No description provided for @appearanceBottomBarSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 项，可配置 2–4 项'**
  String appearanceBottomBarSelected(int count);

  /// No description provided for @appearanceHaptic.
  ///
  /// In zh, this message translates to:
  /// **'底栏触感反馈'**
  String get appearanceHaptic;

  /// No description provided for @appearancePureBlack.
  ///
  /// In zh, this message translates to:
  /// **'纯黑'**
  String get appearancePureBlack;

  /// No description provided for @appearanceBottomBarStyle.
  ///
  /// In zh, this message translates to:
  /// **'底栏样式'**
  String get appearanceBottomBarStyle;

  /// No description provided for @appearanceTabTransition.
  ///
  /// In zh, this message translates to:
  /// **'tab 切换动画'**
  String get appearanceTabTransition;

  /// No description provided for @appearanceLiquidGlass.
  ///
  /// In zh, this message translates to:
  /// **'Liquid 玻璃'**
  String get appearanceLiquidGlass;

  /// No description provided for @fontFamilyTitle.
  ///
  /// In zh, this message translates to:
  /// **'字体设置'**
  String get fontFamilyTitle;

  /// No description provided for @fontSizeRestoreDefaults.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get fontSizeRestoreDefaults;

  /// No description provided for @fontFamilyHapticSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换 tab 时给一次轻震'**
  String get fontFamilyHapticSubtitle;

  /// No description provided for @ruleKindBlockTitle.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get ruleKindBlockTitle;

  /// No description provided for @ruleKindBlockSummary.
  ///
  /// In zh, this message translates to:
  /// **'拦截匹配的域名'**
  String get ruleKindBlockSummary;

  /// No description provided for @ruleKindAllowTitle.
  ///
  /// In zh, this message translates to:
  /// **'白名单'**
  String get ruleKindAllowTitle;

  /// No description provided for @ruleKindAllowSummary.
  ///
  /// In zh, this message translates to:
  /// **'放行匹配的域名'**
  String get ruleKindAllowSummary;

  /// No description provided for @ruleKindRewriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'覆写'**
  String get ruleKindRewriteTitle;

  /// No description provided for @ruleKindRewriteSummary.
  ///
  /// In zh, this message translates to:
  /// **'改写域名解析结果'**
  String get ruleKindRewriteSummary;

  /// No description provided for @ruleSourceUser.
  ///
  /// In zh, this message translates to:
  /// **'用户自定义'**
  String get ruleSourceUser;

  /// No description provided for @ruleSourceSubscription.
  ///
  /// In zh, this message translates to:
  /// **'规则订阅'**
  String get ruleSourceSubscription;

  /// No description provided for @ruleSourcePreset.
  ///
  /// In zh, this message translates to:
  /// **'内置预设'**
  String get ruleSourcePreset;

  /// No description provided for @rulePatternRequired.
  ///
  /// In zh, this message translates to:
  /// **'规则内容不能为空'**
  String get rulePatternRequired;

  /// No description provided for @ruleAllowNeedsAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'该规则为放行规则，请在白名单中添加'**
  String get ruleAllowNeedsAllowlist;

  /// No description provided for @ruleAlreadyExists.
  ///
  /// In zh, this message translates to:
  /// **'该规则已存在'**
  String get ruleAlreadyExists;

  /// No description provided for @ruleDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'域名，如 cdn.example.com'**
  String get ruleDomainHint;

  /// No description provided for @ruleTargetRequired.
  ///
  /// In zh, this message translates to:
  /// **'目标值不能为空'**
  String get ruleTargetRequired;

  /// No description provided for @ruleTargetHint.
  ///
  /// In zh, this message translates to:
  /// **'目标值，如 10.0.0.8'**
  String get ruleTargetHint;

  /// No description provided for @ruleImportant.
  ///
  /// In zh, this message translates to:
  /// **'重要'**
  String get ruleImportant;

  /// No description provided for @ruleReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'只读'**
  String get ruleReadOnly;

  /// No description provided for @ruleEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑规则'**
  String get ruleEdit;

  /// No description provided for @ruleDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除规则'**
  String get ruleDelete;

  /// No description provided for @batchImportDone.
  ///
  /// In zh, this message translates to:
  /// **'导入完成'**
  String get batchImportDone;

  /// No description provided for @batchAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'批量添加规则'**
  String get batchAddTitle;

  /// No description provided for @batchTarget.
  ///
  /// In zh, this message translates to:
  /// **'导入到'**
  String get batchTarget;

  /// No description provided for @batchTargetTable.
  ///
  /// In zh, this message translates to:
  /// **'目标规则表'**
  String get batchTargetTable;

  /// No description provided for @batchTargetTableSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'导入的规则将写入所选规则表'**
  String get batchTargetTableSubtitle;

  /// No description provided for @batchPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'每行一条规则，例如：\n||ads.example.com^\n\n空行会被忽略，重复规则自动跳过。'**
  String get batchPlaceholder;

  /// No description provided for @batchImportable.
  ///
  /// In zh, this message translates to:
  /// **'可导入'**
  String get batchImportable;

  /// No description provided for @batchDuplicated.
  ///
  /// In zh, this message translates to:
  /// **'重复'**
  String get batchDuplicated;

  /// No description provided for @batchInvalid.
  ///
  /// In zh, this message translates to:
  /// **'无效'**
  String get batchInvalid;

  /// No description provided for @batchInvalidHeader.
  ///
  /// In zh, this message translates to:
  /// **'以下规则未通过校验'**
  String get batchInvalidHeader;

  /// No description provided for @batchDuplicateHeader.
  ///
  /// In zh, this message translates to:
  /// **'已存在，将跳过'**
  String get batchDuplicateHeader;

  /// No description provided for @ruleClearCustomTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空自定义规则'**
  String get ruleClearCustomTitle;

  /// No description provided for @commonClearAll.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get commonClearAll;

  /// No description provided for @ruleResetDefault.
  ///
  /// In zh, this message translates to:
  /// **'重置默认白名单'**
  String get ruleResetDefault;

  /// No description provided for @commonReset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get commonReset;

  /// No description provided for @rulePresetProtectedTitle.
  ///
  /// In zh, this message translates to:
  /// **'预设规则受保护'**
  String get rulePresetProtectedTitle;

  /// No description provided for @ruleAllowEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'允许编辑默认白名单？'**
  String get ruleAllowEditTitle;

  /// No description provided for @ruleAllowEditConfirm.
  ///
  /// In zh, this message translates to:
  /// **'仍然开启'**
  String get ruleAllowEditConfirm;

  /// No description provided for @ruleTotal.
  ///
  /// In zh, this message translates to:
  /// **'规则总数'**
  String get ruleTotal;

  /// No description provided for @ruleEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get ruleEnabled;

  /// No description provided for @ruleRewriteEntries.
  ///
  /// In zh, this message translates to:
  /// **'覆写条目'**
  String get ruleRewriteEntries;

  /// No description provided for @ruleCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get ruleCustom;

  /// No description provided for @ruleAllowEditDefault.
  ///
  /// In zh, this message translates to:
  /// **'允许编辑默认白名单'**
  String get ruleAllowEditDefault;

  /// No description provided for @ruleAllowEditDefaultSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭时预设规则只读，避免误放宽放行范围'**
  String get ruleAllowEditDefaultSubtitle;

  /// No description provided for @ruleNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的规则'**
  String get ruleNoMatch;

  /// No description provided for @ruleNoMatchDescription.
  ///
  /// In zh, this message translates to:
  /// **'换个关键词或筛选条件再试'**
  String get ruleNoMatchDescription;

  /// No description provided for @ruleAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get ruleAll;

  /// No description provided for @formIssuesTitle.
  ///
  /// In zh, this message translates to:
  /// **'有几点需要先修正'**
  String get formIssuesTitle;

  /// No description provided for @formSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get formSave;

  /// No description provided for @formProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get formProcessing;

  /// No description provided for @formAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get formAdd;

  /// No description provided for @formDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get formDelete;

  /// No description provided for @formHelp.
  ///
  /// In zh, this message translates to:
  /// **'说明'**
  String get formHelp;

  /// No description provided for @formGotIt.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get formGotIt;

  /// No description provided for @rulePatternHint.
  ///
  /// In zh, this message translates to:
  /// **'规则内容，如 ||ads.example.com^'**
  String get rulePatternHint;

  /// No description provided for @ruleBatchImported.
  ///
  /// In zh, this message translates to:
  /// **'已向{kind}导入 {count} 条规则。'**
  String ruleBatchImported(String count, int kind);

  /// No description provided for @ruleBatchSkippedDuplicates.
  ///
  /// In zh, this message translates to:
  /// **'跳过 {count} 条重复规则。'**
  String ruleBatchSkippedDuplicates(int count);

  /// No description provided for @ruleBatchAllowRejected.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条放行规则（含 #@#）未导入：该规则为放行规则，请在白名单中添加。'**
  String ruleBatchAllowRejected(int count);

  /// No description provided for @ruleBatchImportCount.
  ///
  /// In zh, this message translates to:
  /// **'导入 {count} 条'**
  String ruleBatchImportCount(int count);

  /// No description provided for @ruleBatchMoreDuplicates.
  ///
  /// In zh, this message translates to:
  /// **'等 {count} 条'**
  String ruleBatchMoreDuplicates(int count);

  /// No description provided for @ruleAddForKind.
  ///
  /// In zh, this message translates to:
  /// **'添加{kind}规则'**
  String ruleAddForKind(String kind);

  /// No description provided for @ruleEditDefaultPreset.
  ///
  /// In zh, this message translates to:
  /// **'编辑默认预设规则'**
  String get ruleEditDefaultPreset;

  /// No description provided for @ruleEditForKind.
  ///
  /// In zh, this message translates to:
  /// **'编辑{kind}规则'**
  String ruleEditForKind(String kind);

  /// No description provided for @ruleDeletePresetMessage.
  ///
  /// In zh, this message translates to:
  /// **'「{pattern}」是内置预设规则，删除后可通过重置默认恢复。'**
  String ruleDeletePresetMessage(String pattern);

  /// No description provided for @ruleDeleteSubscriptionMessage.
  ///
  /// In zh, this message translates to:
  /// **'「{pattern}」来自订阅「{name}」，删除后下次更新订阅可能重新出现。'**
  String ruleDeleteSubscriptionMessage(String name, String pattern);

  /// No description provided for @ruleDeleteUserMessage.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{pattern}」吗？此操作不可撤销。'**
  String ruleDeleteUserMessage(String pattern);

  /// No description provided for @ruleClearCustomMessage.
  ///
  /// In zh, this message translates to:
  /// **'将删除全部用户自定义的{kind}规则，订阅与预设规则不受影响。'**
  String ruleClearCustomMessage(String kind);

  /// No description provided for @ruleResetMessage.
  ///
  /// In zh, this message translates to:
  /// **'将内置预设规则恢复为初始内容，你自己添加与订阅带来的规则保留。'**
  String get ruleResetMessage;

  /// No description provided for @rulePresetProtectedMessage.
  ///
  /// In zh, this message translates to:
  /// **'默认白名单规则处于只读状态。请先开启页面顶部的「允许编辑默认白名单」开关，再修改或删除这些规则。'**
  String get rulePresetProtectedMessage;

  /// No description provided for @ruleAllowEditMessage.
  ///
  /// In zh, this message translates to:
  /// **'白名单是放行名单，改动它可能让本应被拦截的流量通过。确认你清楚这条风险后再开启。'**
  String get ruleAllowEditMessage;

  /// No description provided for @ruleTally.
  ///
  /// In zh, this message translates to:
  /// **'共 {matched} 条 · 启用 {enabled}'**
  String ruleTally(int matched, int enabled);

  /// No description provided for @ruleNoRulesForKind.
  ///
  /// In zh, this message translates to:
  /// **'还没有{kind}规则'**
  String ruleNoRulesForKind(String kind);

  /// No description provided for @ruleClearCustomForKind.
  ///
  /// In zh, this message translates to:
  /// **'清空自定义{kind}'**
  String ruleClearCustomForKind(String kind);

  /// No description provided for @subsPickTxt.
  ///
  /// In zh, this message translates to:
  /// **'请选择扩展名为 .txt 的规则文件'**
  String get subsPickTxt;

  /// No description provided for @subsNoPersistPermission.
  ///
  /// In zh, this message translates to:
  /// **'系统未授予长期读取权限，更新时需要重新选择文件'**
  String get subsNoPersistPermission;

  /// No description provided for @subsGroupNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'分组名称不能为空'**
  String get subsGroupNameRequired;

  /// No description provided for @subsEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑订阅'**
  String get subsEdit;

  /// No description provided for @subsAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加订阅'**
  String get subsAdd;

  /// No description provided for @subsSaveTooltip.
  ///
  /// In zh, this message translates to:
  /// **'保存订阅'**
  String get subsSaveTooltip;

  /// No description provided for @subsInfoSection.
  ///
  /// In zh, this message translates to:
  /// **'订阅信息'**
  String get subsInfoSection;

  /// No description provided for @subsSourceType.
  ///
  /// In zh, this message translates to:
  /// **'订阅方式'**
  String get subsSourceType;

  /// No description provided for @subsSourceLocalPick.
  ///
  /// In zh, this message translates to:
  /// **'从存储中选择一个 .txt 文件'**
  String get subsSourceLocalPick;

  /// No description provided for @subsSourceRemoteDownload.
  ///
  /// In zh, this message translates to:
  /// **'从网络地址下载规则正文'**
  String get subsSourceRemoteDownload;

  /// No description provided for @subsLocalRuleFile.
  ///
  /// In zh, this message translates to:
  /// **'本地规则文件'**
  String get subsLocalRuleFile;

  /// No description provided for @subsLocalFileSubscription.
  ///
  /// In zh, this message translates to:
  /// **'本地文件订阅'**
  String get subsLocalFileSubscription;

  /// No description provided for @subsPickFile.
  ///
  /// In zh, this message translates to:
  /// **'选择规则文件'**
  String get subsPickFile;

  /// No description provided for @subsLocalFileHint.
  ///
  /// In zh, this message translates to:
  /// **'仅支持 .txt，点击从存储中选择'**
  String get subsLocalFileHint;

  /// No description provided for @subsLocalFileRepick.
  ///
  /// In zh, this message translates to:
  /// **'点击可重新选择文件'**
  String get subsLocalFileRepick;

  /// No description provided for @subsChoose.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get subsChoose;

  /// No description provided for @subsNameOptional.
  ///
  /// In zh, this message translates to:
  /// **'名称（可选）'**
  String get subsNameOptional;

  /// No description provided for @subsNameEmptyFileName.
  ///
  /// In zh, this message translates to:
  /// **'留空则取文件名'**
  String get subsNameEmptyFileName;

  /// No description provided for @subsUrl.
  ///
  /// In zh, this message translates to:
  /// **'订阅地址'**
  String get subsUrl;

  /// No description provided for @subsNameEmptyUrlTail.
  ///
  /// In zh, this message translates to:
  /// **'留空则取链接末段'**
  String get subsNameEmptyUrlTail;

  /// No description provided for @subsRuleType.
  ///
  /// In zh, this message translates to:
  /// **'规则类型'**
  String get subsRuleType;

  /// No description provided for @subsKindHostsHint.
  ///
  /// In zh, this message translates to:
  /// **'仅导入 hosts 地址与 CNAME 覆写规则'**
  String get subsKindHostsHint;

  /// No description provided for @subsKindDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'导入域名规则与黑白名单'**
  String get subsKindDomainHint;

  /// No description provided for @subsGroupHint.
  ///
  /// In zh, this message translates to:
  /// **'分组只影响订阅页的筛选与批量更新，可稍后调整。'**
  String get subsGroupHint;

  /// No description provided for @subsNewGroupShort.
  ///
  /// In zh, this message translates to:
  /// **'+ 新建'**
  String get subsNewGroupShort;

  /// No description provided for @subsMirrorTemplateFooter.
  ///
  /// In zh, this message translates to:
  /// **'镜像地址会把原始订阅地址改写成镜像前缀，常用于加速 GitHub 等慢速源。'**
  String get subsMirrorTemplateFooter;

  /// No description provided for @subsAddMirrorTemplate.
  ///
  /// In zh, this message translates to:
  /// **'添加镜像站模板'**
  String get subsAddMirrorTemplate;

  /// No description provided for @subsAddMirrorTemplateSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有模板，先去保存一个常用的镜像前缀'**
  String get subsAddMirrorTemplateSubtitle;

  /// No description provided for @subsMirrorFooter.
  ///
  /// In zh, this message translates to:
  /// **'下载时先请求镜像地址；镜像失败且开启回退时，再试原始地址。'**
  String get subsMirrorFooter;

  /// No description provided for @subsUseMirrorTemplate.
  ///
  /// In zh, this message translates to:
  /// **'使用镜像站模板'**
  String get subsUseMirrorTemplate;

  /// No description provided for @subsUseMirrorTemplateSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'订阅源较慢或被限速时，改写下载地址'**
  String get subsUseMirrorTemplateSubtitle;

  /// No description provided for @subsMirrorTemplate.
  ///
  /// In zh, this message translates to:
  /// **'镜像模板'**
  String get subsMirrorTemplate;

  /// No description provided for @subsMirrorFallback.
  ///
  /// In zh, this message translates to:
  /// **'失败后回退直连'**
  String get subsMirrorFallback;

  /// No description provided for @subsMirrorFallbackSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'镜像请求失败时，改用原始订阅地址'**
  String get subsMirrorFallbackSubtitle;

  /// No description provided for @subsEffectiveUrl.
  ///
  /// In zh, this message translates to:
  /// **'实际请求地址'**
  String get subsEffectiveUrl;

  /// No description provided for @subsNothingToUpdate.
  ///
  /// In zh, this message translates to:
  /// **'没有可更新的远程订阅'**
  String get subsNothingToUpdate;

  /// No description provided for @subsDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除订阅'**
  String get subsDeleteTitle;

  /// No description provided for @subsRenameTitle.
  ///
  /// In zh, this message translates to:
  /// **'重命名订阅'**
  String get subsRenameTitle;

  /// No description provided for @subsNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'名称不能为空'**
  String get subsNameRequired;

  /// No description provided for @subsTitle.
  ///
  /// In zh, this message translates to:
  /// **'订阅'**
  String get subsTitle;

  /// No description provided for @subsUpdateAll.
  ///
  /// In zh, this message translates to:
  /// **'更新全部订阅'**
  String get subsUpdateAll;

  /// No description provided for @subsCount.
  ///
  /// In zh, this message translates to:
  /// **'订阅数'**
  String get subsCount;

  /// No description provided for @subsRuleCount.
  ///
  /// In zh, this message translates to:
  /// **'已入库规则'**
  String get subsRuleCount;

  /// No description provided for @subsAbnormal.
  ///
  /// In zh, this message translates to:
  /// **'异常'**
  String get subsAbnormal;

  /// No description provided for @subsUpdating.
  ///
  /// In zh, this message translates to:
  /// **'正在更新订阅…'**
  String get subsUpdating;

  /// No description provided for @subsEmptyLabel.
  ///
  /// In zh, this message translates to:
  /// **'还没有订阅'**
  String get subsEmptyLabel;

  /// No description provided for @subsEmptyDescription.
  ///
  /// In zh, this message translates to:
  /// **'订阅可以批量维护规则；更新会下载正文、解析并写入规则库，拦截随之生效。'**
  String get subsEmptyDescription;

  /// No description provided for @subsUpdateFooter.
  ///
  /// In zh, this message translates to:
  /// **'更新会下载正文、解析成黑/白名单与覆写规则并写入规则库，同时替换该订阅上一次贡献的规则；元素隐藏规则本仓不注入，不计入条数。'**
  String get subsUpdateFooter;

  /// No description provided for @subsAllGroups.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get subsAllGroups;

  /// No description provided for @subsNewGroupTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建分组'**
  String get subsNewGroupTitle;

  /// No description provided for @subsEditRemoteHint.
  ///
  /// In zh, this message translates to:
  /// **'修改链接或收录类型后会立即重新下载，并替换该订阅原有的规则；订阅方式与本地文件不可更改。'**
  String get subsEditRemoteHint;

  /// No description provided for @subsEditLocalHint.
  ///
  /// In zh, this message translates to:
  /// **'本地文件通过系统文件选择器读取，应用只保留读取权限；同名的黑白名单与 hosts 订阅互不影响。'**
  String get subsEditLocalHint;

  /// No description provided for @subsAddRemoteHint.
  ///
  /// In zh, this message translates to:
  /// **'同一条链接可以为黑白名单和 hosts 各建一条订阅（唯一性按「链接 + 类型」判定），保存后会立即下载一次正文并写入规则库。'**
  String get subsAddRemoteHint;

  /// No description provided for @subsKindLabel.
  ///
  /// In zh, this message translates to:
  /// **'收录类型'**
  String get subsKindLabel;

  /// No description provided for @subsGroupLabel.
  ///
  /// In zh, this message translates to:
  /// **'所属分组'**
  String get subsGroupLabel;

  /// No description provided for @subsMirrorTitle.
  ///
  /// In zh, this message translates to:
  /// **'镜像加速'**
  String get subsMirrorTitle;

  /// No description provided for @subsDeleteMessage.
  ///
  /// In zh, this message translates to:
  /// **'删除「{name}」后不可撤销。\n\n删除会同时移除这条订阅贡献的全部规则（来源标签 sub_<id>）。'**
  String subsDeleteMessage(String name);

  /// No description provided for @subsTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个订阅'**
  String subsTotal(int count);

  /// No description provided for @subsGroupTotal.
  ///
  /// In zh, this message translates to:
  /// **'「{group}」下 {count} 个订阅'**
  String subsGroupTotal(String count, int group);

  /// No description provided for @subsUpdateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get subsUpdateNow;

  /// No description provided for @subsReimport.
  ///
  /// In zh, this message translates to:
  /// **'重新导入文件'**
  String get subsReimport;

  /// No description provided for @subsRename.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get subsRename;

  /// No description provided for @subsConsecutiveFailures.
  ///
  /// In zh, this message translates to:
  /// **'连续失败 {count} 次'**
  String subsConsecutiveFailures(int count);

  /// No description provided for @subsMirrorFallbackShort.
  ///
  /// In zh, this message translates to:
  /// **'镜像 · 可回退'**
  String get subsMirrorFallbackShort;

  /// No description provided for @subsMirrorNoFallback.
  ///
  /// In zh, this message translates to:
  /// **'镜像 · 不回退'**
  String get subsMirrorNoFallback;

  /// No description provided for @subsLastUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'上次更新失败'**
  String get subsLastUpdateFailed;

  /// No description provided for @subsNeverUpdated.
  ///
  /// In zh, this message translates to:
  /// **'从未成功更新'**
  String get subsNeverUpdated;

  /// No description provided for @subsRuleCountValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String subsRuleCountValue(String count);

  /// No description provided for @subsRulesStored.
  ///
  /// In zh, this message translates to:
  /// **'已入库 {count} 条规则；{action}该订阅贡献的规则。'**
  String subsRulesStored(String action, String count);

  /// No description provided for @subsActionRemote.
  ///
  /// In zh, this message translates to:
  /// **'更新会重新下载并替换'**
  String get subsActionRemote;

  /// No description provided for @subsActionLocal.
  ///
  /// In zh, this message translates to:
  /// **'重新导入会重新读取该文件并替换'**
  String get subsActionLocal;

  /// No description provided for @subsPickRuleFile.
  ///
  /// In zh, this message translates to:
  /// **'请选择一个规则文件'**
  String get subsPickRuleFile;

  /// No description provided for @subsChange.
  ///
  /// In zh, this message translates to:
  /// **'更换'**
  String get subsChange;

  /// No description provided for @subsGroupShort.
  ///
  /// In zh, this message translates to:
  /// **'+ 分组'**
  String get subsGroupShort;

  /// No description provided for @subsManageGroupsShort.
  ///
  /// In zh, this message translates to:
  /// **'管理分组'**
  String get subsManageGroupsShort;

  /// No description provided for @subsManageGroupsTitle.
  ///
  /// In zh, this message translates to:
  /// **'分组管理'**
  String get subsManageGroupsTitle;

  /// No description provided for @subsGroupRenameTitle.
  ///
  /// In zh, this message translates to:
  /// **'重命名分组'**
  String get subsGroupRenameTitle;

  /// No description provided for @subsGroupDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除分组'**
  String get subsGroupDeleteTitle;

  /// No description provided for @subsGroupDeleteMessage.
  ///
  /// In zh, this message translates to:
  /// **'删除「{name}」后，组内订阅会移到未分组，订阅与规则本身不会被删除。'**
  String subsGroupDeleteMessage(String name);

  /// No description provided for @subsGroupDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'已存在同名分组'**
  String get subsGroupDuplicate;

  /// No description provided for @subsGroupSubCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个订阅'**
  String subsGroupSubCount(int count);

  /// No description provided for @subsGroupsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有分组'**
  String get subsGroupsEmpty;

  /// No description provided for @subsGroupsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'点击右上角新建分组，之后可以在这里重命名或删除。'**
  String get subsGroupsEmptyHint;

  /// No description provided for @subsGroupsFooter.
  ///
  /// In zh, this message translates to:
  /// **'分组只影响订阅页的筛选与批量更新；删除分组不会删除订阅或规则。'**
  String get subsGroupsFooter;

  /// No description provided for @subsMirrorName.
  ///
  /// In zh, this message translates to:
  /// **'镜像 {mirror}'**
  String subsMirrorName(String mirror);

  /// No description provided for @trafficPackageName.
  ///
  /// In zh, this message translates to:
  /// **'包名'**
  String get trafficPackageName;

  /// No description provided for @trafficAppName.
  ///
  /// In zh, this message translates to:
  /// **'应用名'**
  String get trafficAppName;

  /// No description provided for @trafficDown.
  ///
  /// In zh, this message translates to:
  /// **'下行流量'**
  String get trafficDown;

  /// No description provided for @trafficUp.
  ///
  /// In zh, this message translates to:
  /// **'上行流量'**
  String get trafficUp;

  /// No description provided for @trafficTotal.
  ///
  /// In zh, this message translates to:
  /// **'合计'**
  String get trafficTotal;

  /// No description provided for @trafficShare.
  ///
  /// In zh, this message translates to:
  /// **'占比'**
  String get trafficShare;

  /// No description provided for @trafficStartDate.
  ///
  /// In zh, this message translates to:
  /// **'统计起始日'**
  String get trafficStartDate;

  /// No description provided for @trafficLastUpdate.
  ///
  /// In zh, this message translates to:
  /// **'最后更新'**
  String get trafficLastUpdate;

  /// No description provided for @trafficAttributionFooter.
  ///
  /// In zh, this message translates to:
  /// **'流量按 UID 归因到应用（上游 TrafficAttributionDialog 的口径）；同一应用的多进程流量合并计算。'**
  String get trafficAttributionFooter;

  /// No description provided for @trafficAttributionTitle.
  ///
  /// In zh, this message translates to:
  /// **'流量归因说明'**
  String get trafficAttributionTitle;

  /// No description provided for @trafficScopeTitle.
  ///
  /// In zh, this message translates to:
  /// **'统计口径'**
  String get trafficScopeTitle;

  /// No description provided for @trafficScopeBody.
  ///
  /// In zh, this message translates to:
  /// **'流量按 UID 归因：每个应用的上下行字节数由引擎按 UID 累计后按天落库（表 app_traffic_daily，主键是「日期 + 包名」），不走包名匹配，因此共享 UID 的应用会合并成一项。'**
  String get trafficScopeBody;

  /// No description provided for @trafficWhyLowerTitle.
  ///
  /// In zh, this message translates to:
  /// **'为什么数字比系统设置里少'**
  String get trafficWhyLowerTitle;

  /// No description provided for @trafficWhyLowerBody.
  ///
  /// In zh, this message translates to:
  /// **'这里只统计经过本机隧道处理的流量，未进入隧道的直连流量不计入；系统设置里的统计包含全部网卡流量。'**
  String get trafficWhyLowerBody;

  /// No description provided for @trafficWhyNoRateTitle.
  ///
  /// In zh, this message translates to:
  /// **'为什么没有实时速率'**
  String get trafficWhyNoRateTitle;

  /// No description provided for @trafficWhyNoRateBody.
  ///
  /// In zh, this message translates to:
  /// **'实时速率需要内核每秒回报的速率序列；本仓的按天流量表只有「日期 + 包名 + 上下行累计字节」，没有速率列。因此「本次会话」窗口与「按实时速率」排序不可用，页面上也没有速率曲线——页面里出现的每个数字都是真实字节数。'**
  String get trafficWhyNoRateBody;

  /// No description provided for @trafficRetentionTitle.
  ///
  /// In zh, this message translates to:
  /// **'记录保留多久'**
  String get trafficRetentionTitle;

  /// No description provided for @trafficRetentionBody.
  ///
  /// In zh, this message translates to:
  /// **'按天保留，由原生侧的清理策略删除过期行；「全部历史」档位汇总表里现存的全部日期。'**
  String get trafficRetentionBody;

  /// No description provided for @trafficSystemAppsTitle.
  ///
  /// In zh, this message translates to:
  /// **'系统应用怎么识别'**
  String get trafficSystemAppsTitle;

  /// No description provided for @trafficSystemAppsBody.
  ///
  /// In zh, this message translates to:
  /// **'流量表里没有系统应用标记，页面按旧版 SystemAppClassifier 的同一份前缀表识别（android、com.android.*、各厂商预装前缀等）。「隐藏系统应用」开关的状态落在 traffic_stats_hide_system_apps。'**
  String get trafficSystemAppsBody;

  /// No description provided for @trafficUpstreamFooter.
  ///
  /// In zh, this message translates to:
  /// **'上游对应 ui/traffic/TrafficAttributionDialog.kt 与 AppTrafficDetailDialog.kt；本页数字来自 app_traffic_daily。'**
  String get trafficUpstreamFooter;

  /// No description provided for @trafficTitle.
  ///
  /// In zh, this message translates to:
  /// **'流量统计'**
  String get trafficTitle;

  /// No description provided for @trafficClearHistory.
  ///
  /// In zh, this message translates to:
  /// **'清除历史'**
  String get trafficClearHistory;

  /// No description provided for @trafficRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get trafficRefresh;

  /// No description provided for @trafficAttribution.
  ///
  /// In zh, this message translates to:
  /// **'归因说明'**
  String get trafficAttribution;

  /// No description provided for @trafficLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取流量记录'**
  String get trafficLoadFailed;

  /// No description provided for @trafficLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取流量记录'**
  String get trafficLoading;

  /// No description provided for @trafficAppCount.
  ///
  /// In zh, this message translates to:
  /// **'应用数'**
  String get trafficAppCount;

  /// No description provided for @trafficAppCountUnit.
  ///
  /// In zh, this message translates to:
  /// **'个'**
  String get trafficAppCountUnit;

  /// No description provided for @trafficNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无流量数据'**
  String get trafficNoData;

  /// No description provided for @trafficNoMatchingApps.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的应用'**
  String get trafficNoMatchingApps;

  /// No description provided for @trafficRankingTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用流量排行'**
  String get trafficRankingTitle;

  /// No description provided for @trafficShareFooter.
  ///
  /// In zh, this message translates to:
  /// **'占比按{window}总字节数（下行 + 上行）计算；{range}。点按一行查看该应用的上下行明细。'**
  String trafficShareFooter(String range, String window);

  /// No description provided for @trafficClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除全部流量记录？'**
  String get trafficClearTitle;

  /// No description provided for @trafficConfirmClear.
  ///
  /// In zh, this message translates to:
  /// **'确认清除'**
  String get trafficConfirmClear;

  /// No description provided for @trafficClearBody.
  ///
  /// In zh, this message translates to:
  /// **'此操作将清空所有已持久化的应用历史流量统计，清除后无法恢复。'**
  String get trafficClearBody;

  /// No description provided for @trafficRangeAllHistory.
  ///
  /// In zh, this message translates to:
  /// **'范围为全部历史记录'**
  String get trafficRangeAllHistory;

  /// No description provided for @trafficSessionRange.
  ///
  /// In zh, this message translates to:
  /// **'本次会话'**
  String get trafficSessionRange;

  /// No description provided for @trafficSessionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'「本次会话」需要内核按会话回报流量，本仓只有按天落库的历史记录'**
  String get trafficSessionUnavailable;

  /// No description provided for @trafficLiveRate.
  ///
  /// In zh, this message translates to:
  /// **'按实时速率'**
  String get trafficLiveRate;

  /// No description provided for @trafficHideSystemApps.
  ///
  /// In zh, this message translates to:
  /// **'隐藏系统应用'**
  String get trafficHideSystemApps;

  /// No description provided for @trafficSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索应用名或包名'**
  String get trafficSearchHint;

  /// No description provided for @trafficAllHistory.
  ///
  /// In zh, this message translates to:
  /// **'全部历史'**
  String get trafficAllHistory;

  /// No description provided for @trafficLiveRateUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'「按实时网速」需要每秒速率，本仓的按天表里没有速率列'**
  String get trafficLiveRateUnavailable;

  /// No description provided for @trafficHideSystemAppsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按系统应用标记与厂商预装前缀识别，隐藏后不计入排行'**
  String get trafficHideSystemAppsSubtitle;

  /// No description provided for @trafficWindowLabelDate.
  ///
  /// In zh, this message translates to:
  /// **'统计日期 {date}'**
  String trafficWindowLabelDate(String date);

  /// No description provided for @trafficWindowLabelRange.
  ///
  /// In zh, this message translates to:
  /// **'统计范围 {start} 至 {end}'**
  String trafficWindowLabelRange(String end, String start);

  /// No description provided for @trafficShareWindow.
  ///
  /// In zh, this message translates to:
  /// **'占比按{window}总字节数（下行 + 上行）计算；{range}。点按一行查看该应用的上下行明细。'**
  String trafficShareWindow(String range, String window);

  /// No description provided for @trafficTotalApps.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个应用产生流量 · 合计 {total}'**
  String trafficTotalApps(int count, String total);

  /// No description provided for @trafficSearchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有应用名或包名包含「{search}」。'**
  String trafficSearchEmpty(String search);

  /// No description provided for @trafficHiddenCount.
  ///
  /// In zh, this message translates to:
  /// **'本次共有 {count} 个应用被「隐藏系统应用」过滤掉，关闭该开关即可看到。'**
  String trafficHiddenCount(int count);

  /// No description provided for @trafficNoRecordsBody.
  ///
  /// In zh, this message translates to:
  /// **'流量按天由原生侧汇总落库；启动隧道并产生流量后，这里会出现各应用的下行 / 上行字节数。'**
  String get trafficNoRecordsBody;

  /// No description provided for @trafficNoRecordsForWindow.
  ///
  /// In zh, this message translates to:
  /// **'「{window}」还没有流量记录。流量按天由原生侧汇总落库，换个时间窗口或启动隧道产生流量后再看。'**
  String trafficNoRecordsForWindow(String window);

  /// No description provided for @trafficOptionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'「{label}」不可用：{reason}'**
  String trafficOptionUnavailable(String label, String reason);

  /// No description provided for @trafficNoSourceReason.
  ///
  /// In zh, this message translates to:
  /// **'本仓没有对应的数据来源'**
  String get trafficNoSourceReason;

  /// No description provided for @trafficCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除 {count} 条流量记录'**
  String trafficCleared(int count);

  /// No description provided for @trafficClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清除失败：{detail}'**
  String trafficClearFailed(String detail);

  /// No description provided for @trafficShareBarTooltip.
  ///
  /// In zh, this message translates to:
  /// **'占比条长度是这一行按「{sort}」在当前窗口总量里的份额（当前 {value}），与列表排序一致。'**
  String trafficShareBarTooltip(String sort, String value);

  /// No description provided for @trafficWhyDaemonTitle.
  ///
  /// In zh, this message translates to:
  /// **'为什么系统设置将全部流量算给谛听？'**
  String get trafficWhyDaemonTitle;

  /// No description provided for @trafficWhyDaemonBody.
  ///
  /// In zh, this message translates to:
  /// **'因 Android VPN 机制，系统将代理出站归属于守护进程。谛听自身不偷跑流量，点按查看统计口径。'**
  String get trafficWhyDaemonBody;

  /// No description provided for @trafficLiveRateTitle.
  ///
  /// In zh, this message translates to:
  /// **'实时速率'**
  String get trafficLiveRateTitle;

  /// No description provided for @trafficNoLiveRate.
  ///
  /// In zh, this message translates to:
  /// **'本模式不统计实时速率：极速模式的窄路由不经过引擎的流量计数器，本仓也没有它的累计表。上面的 {window} 下行 / 上行与下方排行都是真实数字。'**
  String trafficNoLiveRate(String window);

  /// No description provided for @trafficLiveRateBody.
  ///
  /// In zh, this message translates to:
  /// **'来自引擎的每秒速率（本次会话），与常驻通知里的读数同源；上面的 {window} 下行 / 上行是 `app_traffic_daily` 的累计字节，两者口径不同，数字不必相等。'**
  String trafficLiveRateBody(String window);

  /// No description provided for @trafficSearchPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'搜索应用或包名...'**
  String get trafficSearchPlaceholder;

  /// No description provided for @trafficWindowDown.
  ///
  /// In zh, this message translates to:
  /// **'{window}下行'**
  String trafficWindowDown(String window);

  /// No description provided for @trafficWindowUp.
  ///
  /// In zh, this message translates to:
  /// **'{window}上行'**
  String trafficWindowUp(String window);

  /// No description provided for @obsRequestsTitle.
  ///
  /// In zh, this message translates to:
  /// **'请求'**
  String get obsRequestsTitle;

  /// No description provided for @obsSource.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get obsSource;

  /// No description provided for @obsStatus.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get obsStatus;

  /// No description provided for @obsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get obsRefresh;

  /// No description provided for @obsClearFilter.
  ///
  /// In zh, this message translates to:
  /// **'清除筛选'**
  String get obsClearFilter;

  /// No description provided for @obsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取请求记录'**
  String get obsLoadFailed;

  /// No description provided for @obsLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取请求记录'**
  String get obsLoading;

  /// No description provided for @obsNoRecords.
  ///
  /// In zh, this message translates to:
  /// **'还没有请求记录'**
  String get obsNoRecords;

  /// No description provided for @obsNoMatchingRequests.
  ///
  /// In zh, this message translates to:
  /// **'没有符合条件的请求'**
  String get obsNoMatchingRequests;

  /// No description provided for @obsNoRecordsBody.
  ///
  /// In zh, this message translates to:
  /// **'应用发出请求后会在这里留下记录；HTTPS 记录需要开启流量检查。'**
  String get obsNoRecordsBody;

  /// No description provided for @obsResetFilter.
  ///
  /// In zh, this message translates to:
  /// **'重置筛选条件'**
  String get obsResetFilter;

  /// No description provided for @obsRecordsHeader.
  ///
  /// In zh, this message translates to:
  /// **'请求记录'**
  String get obsRecordsHeader;

  /// No description provided for @obsRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get obsRetry;

  /// No description provided for @obsBypassedDns.
  ///
  /// In zh, this message translates to:
  /// **'直连，未经过 DNS 解析流程'**
  String get obsBypassedDns;

  /// No description provided for @obsBlockedDns.
  ///
  /// In zh, this message translates to:
  /// **'被过滤规则拦截，未发出查询'**
  String get obsBlockedDns;

  /// No description provided for @obsRewrittenDns.
  ///
  /// In zh, this message translates to:
  /// **'命中了覆写规则，返回改写后的结果'**
  String get obsRewrittenDns;

  /// No description provided for @obsErrorDns.
  ///
  /// In zh, this message translates to:
  /// **'解析过程出错，未取得应答'**
  String get obsErrorDns;

  /// No description provided for @obsPassedDns.
  ///
  /// In zh, this message translates to:
  /// **'按规则解析并正常返回'**
  String get obsPassedDns;

  /// No description provided for @obsPassedHttps.
  ///
  /// In zh, this message translates to:
  /// **'按规则转发成功'**
  String get obsPassedHttps;

  /// No description provided for @obsRewrittenHttps.
  ///
  /// In zh, this message translates to:
  /// **'命中了覆写规则，返回改写后的请求'**
  String get obsRewrittenHttps;

  /// No description provided for @obsBlockedHttps.
  ///
  /// In zh, this message translates to:
  /// **'被过滤规则拦截，未建立连接'**
  String get obsBlockedHttps;

  /// No description provided for @obsBypassedHttps.
  ///
  /// In zh, this message translates to:
  /// **'未解密直接转发（旁路）'**
  String get obsBypassedHttps;

  /// No description provided for @obsErrorHttps.
  ///
  /// In zh, this message translates to:
  /// **'处理过程出错'**
  String get obsErrorHttps;

  /// No description provided for @obsNoRuleHttps.
  ///
  /// In zh, this message translates to:
  /// **'未命中规则（或未记录规则）'**
  String get obsNoRuleHttps;

  /// No description provided for @obsNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get obsNone;

  /// No description provided for @obsRequestDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'请求详情'**
  String get obsRequestDetailTitle;

  /// No description provided for @obsCachedChip.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get obsCachedChip;

  /// No description provided for @obsBasicInfo.
  ///
  /// In zh, this message translates to:
  /// **'基础信息'**
  String get obsBasicInfo;

  /// No description provided for @obsTime.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get obsTime;

  /// No description provided for @obsProtocol.
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get obsProtocol;

  /// No description provided for @obsAppPackage.
  ///
  /// In zh, this message translates to:
  /// **'应用包名'**
  String get obsAppPackage;

  /// No description provided for @obsResolved.
  ///
  /// In zh, this message translates to:
  /// **'解析结果'**
  String get obsResolved;

  /// No description provided for @obsElapsed.
  ///
  /// In zh, this message translates to:
  /// **'耗时'**
  String get obsElapsed;

  /// No description provided for @obsBlockingSubscription.
  ///
  /// In zh, this message translates to:
  /// **'拦截订阅'**
  String get obsBlockingSubscription;

  /// No description provided for @obsRuleMatch.
  ///
  /// In zh, this message translates to:
  /// **'规则命中'**
  String get obsRuleMatch;

  /// No description provided for @obsRule.
  ///
  /// In zh, this message translates to:
  /// **'规则'**
  String get obsRule;

  /// No description provided for @obsHandling.
  ///
  /// In zh, this message translates to:
  /// **'处理方式'**
  String get obsHandling;

  /// No description provided for @obsError.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get obsError;

  /// No description provided for @obsAiAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'AI 分析'**
  String get obsAiAnalysis;

  /// No description provided for @obsRawRecord.
  ///
  /// In zh, this message translates to:
  /// **'原始记录'**
  String get obsRawRecord;

  /// No description provided for @obsRawRecordFooter.
  ///
  /// In zh, this message translates to:
  /// **'引擎写入 message 字段的原文，未经改写。'**
  String get obsRawRecordFooter;

  /// No description provided for @obsFailedHint.
  ///
  /// In zh, this message translates to:
  /// **'处理失败的请求可在「连接」页配合查看对应的活动连接。'**
  String get obsFailedHint;

  /// No description provided for @obsRulesHint.
  ///
  /// In zh, this message translates to:
  /// **'加入的黑白名单可在「规则」页查看和撤销。'**
  String get obsRulesHint;

  /// No description provided for @obsCacheHit.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中'**
  String get obsCacheHit;

  /// No description provided for @obsCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制 {text}'**
  String obsCopied(String text);

  /// No description provided for @obsCopyAddress.
  ///
  /// In zh, this message translates to:
  /// **'复制地址'**
  String get obsCopyAddress;

  /// No description provided for @obsCopyDomain.
  ///
  /// In zh, this message translates to:
  /// **'复制域名'**
  String get obsCopyDomain;

  /// No description provided for @obsInBlocklist.
  ///
  /// In zh, this message translates to:
  /// **'已在黑名单'**
  String get obsInBlocklist;

  /// No description provided for @obsAddToBlocklist.
  ///
  /// In zh, this message translates to:
  /// **'加入黑名单'**
  String get obsAddToBlocklist;

  /// No description provided for @obsInAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'已在白名单'**
  String get obsInAllowlist;

  /// No description provided for @obsAddToAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'加入白名单'**
  String get obsAddToAllowlist;

  /// No description provided for @obsIpOnlyFooter.
  ///
  /// In zh, this message translates to:
  /// **'该记录只有 IP 地址，域名规则无法匹配，因此不能加入黑白名单。'**
  String get obsIpOnlyFooter;

  /// No description provided for @obsAnalyzeRequest.
  ///
  /// In zh, this message translates to:
  /// **'分析这条请求'**
  String get obsAnalyzeRequest;

  /// No description provided for @obsAnalyzeRequestBody.
  ///
  /// In zh, this message translates to:
  /// **'用配置的模型研判归属、风险与处置建议'**
  String get obsAnalyzeRequestBody;

  /// No description provided for @obsCopiedHost.
  ///
  /// In zh, this message translates to:
  /// **'已复制 {host}'**
  String obsCopiedHost(String host);

  /// No description provided for @obsAddedToKind.
  ///
  /// In zh, this message translates to:
  /// **'已将 {domain} 加入{kind}'**
  String obsAddedToKind(String domain, String kind);

  /// No description provided for @obsAlreadyInKind.
  ///
  /// In zh, this message translates to:
  /// **'{domain} 已在{kind}中'**
  String obsAlreadyInKind(String domain, String kind);

  /// No description provided for @obsCurrentFilter.
  ///
  /// In zh, this message translates to:
  /// **'当前筛选：{filter}。'**
  String obsCurrentFilter(String filter);

  /// No description provided for @obsFooterCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 条，其中 {failed} 条处理失败{filter}{more}。点按一行查看规则命中与处理结果。'**
  String obsFooterCount(int count, int failed, String filter, String more);

  /// No description provided for @obsFooterFilter.
  ///
  /// In zh, this message translates to:
  /// **'（筛选：{filter}）'**
  String obsFooterFilter(String filter);

  /// No description provided for @obsFooterMore.
  ///
  /// In zh, this message translates to:
  /// **'；继续下滑加载更多'**
  String get obsFooterMore;

  /// No description provided for @obsFooterAll.
  ///
  /// In zh, this message translates to:
  /// **'；已加载全部'**
  String get obsFooterAll;

  /// No description provided for @obsByApp.
  ///
  /// In zh, this message translates to:
  /// **'按应用查看'**
  String get obsByApp;

  /// No description provided for @obsViewAppRequests.
  ///
  /// In zh, this message translates to:
  /// **'查看该应用的请求记录'**
  String get obsViewAppRequests;

  /// No description provided for @obsAppsTitle.
  ///
  /// In zh, this message translates to:
  /// **'按应用查看'**
  String get obsAppsTitle;

  /// No description provided for @obsAppsHeader.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get obsAppsHeader;

  /// No description provided for @obsAppsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有带应用归属的请求'**
  String get obsAppsEmpty;

  /// No description provided for @obsAppsEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'请求记录中带有应用包名时，会按应用汇总在这里。'**
  String get obsAppsEmptyBody;

  /// No description provided for @obsAppsFooter.
  ///
  /// In zh, this message translates to:
  /// **'按请求次数从多到少排列，统计范围为当前保留的全部请求记录。点按一个应用查看它的请求。'**
  String get obsAppsFooter;

  /// No description provided for @obsAppRequestCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次请求'**
  String obsAppRequestCount(int count);

  /// No description provided for @obsExportLogs.
  ///
  /// In zh, this message translates to:
  /// **'导出日志'**
  String get obsExportLogs;

  /// No description provided for @obsExportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出请求日志'**
  String get obsExportTitle;

  /// No description provided for @obsExportRangeSection.
  ///
  /// In zh, this message translates to:
  /// **'时间范围'**
  String get obsExportRangeSection;

  /// No description provided for @obsExportRangeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部时间'**
  String get obsExportRangeAll;

  /// No description provided for @obsExportRangeHour.
  ///
  /// In zh, this message translates to:
  /// **'最近 1 小时'**
  String get obsExportRangeHour;

  /// No description provided for @obsExportRangeDay.
  ///
  /// In zh, this message translates to:
  /// **'最近 24 小时'**
  String get obsExportRangeDay;

  /// No description provided for @obsExportRangeWeek.
  ///
  /// In zh, this message translates to:
  /// **'最近 7 天'**
  String get obsExportRangeWeek;

  /// No description provided for @obsExportRangeCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get obsExportRangeCustom;

  /// No description provided for @obsExportCustomRange.
  ///
  /// In zh, this message translates to:
  /// **'起止日期'**
  String get obsExportCustomRange;

  /// No description provided for @obsExportPickRange.
  ///
  /// In zh, this message translates to:
  /// **'点击选择起止日期'**
  String get obsExportPickRange;

  /// No description provided for @obsExportScopeSection.
  ///
  /// In zh, this message translates to:
  /// **'筛选条件'**
  String get obsExportScopeSection;

  /// No description provided for @obsExportIntro.
  ///
  /// In zh, this message translates to:
  /// **'选择时间范围、请求来源、状态与应用，再勾选需要导出的字段。'**
  String get obsExportIntro;

  /// No description provided for @obsExportDnsOnlyNote.
  ///
  /// In zh, this message translates to:
  /// **'当前模式没有 HTTPS 请求日志，导出仅包含 DNS 记录'**
  String get obsExportDnsOnlyNote;

  /// No description provided for @obsExportApps.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get obsExportApps;

  /// No description provided for @obsExportAllApps.
  ///
  /// In zh, this message translates to:
  /// **'全部应用'**
  String get obsExportAllApps;

  /// No description provided for @obsExportSelectedApps.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 个应用'**
  String obsExportSelectedApps(int count);

  /// No description provided for @obsExportSelectedColumns.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 个字段'**
  String obsExportSelectedColumns(int count);

  /// No description provided for @obsExportAppPickerTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择应用'**
  String get obsExportAppPickerTitle;

  /// No description provided for @obsExportAppPickerDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get obsExportAppPickerDone;

  /// No description provided for @obsExportColumnsSection.
  ///
  /// In zh, this message translates to:
  /// **'包含字段'**
  String get obsExportColumnsSection;

  /// No description provided for @obsExportColumnTime.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get obsExportColumnTime;

  /// No description provided for @obsExportColumnSource.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get obsExportColumnSource;

  /// No description provided for @obsExportColumnStatus.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get obsExportColumnStatus;

  /// No description provided for @obsExportColumnAppName.
  ///
  /// In zh, this message translates to:
  /// **'应用名称'**
  String get obsExportColumnAppName;

  /// No description provided for @obsExportColumnPackage.
  ///
  /// In zh, this message translates to:
  /// **'应用包名'**
  String get obsExportColumnPackage;

  /// No description provided for @obsExportColumnHost.
  ///
  /// In zh, this message translates to:
  /// **'主机/查询'**
  String get obsExportColumnHost;

  /// No description provided for @obsExportColumnProtocol.
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get obsExportColumnProtocol;

  /// No description provided for @obsExportColumnRule.
  ///
  /// In zh, this message translates to:
  /// **'匹配规则'**
  String get obsExportColumnRule;

  /// No description provided for @obsExportColumnElapsed.
  ///
  /// In zh, this message translates to:
  /// **'耗时(ms)'**
  String get obsExportColumnElapsed;

  /// No description provided for @obsExportColumnCached.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get obsExportColumnCached;

  /// No description provided for @obsExportColumnSubscription.
  ///
  /// In zh, this message translates to:
  /// **'拦截订阅'**
  String get obsExportColumnSubscription;

  /// No description provided for @obsExportColumnMessage.
  ///
  /// In zh, this message translates to:
  /// **'原始消息'**
  String get obsExportColumnMessage;

  /// No description provided for @obsExportCachedYes.
  ///
  /// In zh, this message translates to:
  /// **'是'**
  String get obsExportCachedYes;

  /// No description provided for @obsExportCachedNo.
  ///
  /// In zh, this message translates to:
  /// **'否'**
  String get obsExportCachedNo;

  /// No description provided for @obsExportLimit.
  ///
  /// In zh, this message translates to:
  /// **'条数上限'**
  String get obsExportLimit;

  /// No description provided for @obsExportLimitHint.
  ///
  /// In zh, this message translates to:
  /// **'1–{max}'**
  String obsExportLimitHint(int max);

  /// No description provided for @obsExportAction.
  ///
  /// In zh, this message translates to:
  /// **'导出 CSV'**
  String get obsExportAction;

  /// No description provided for @obsExportBusy.
  ///
  /// In zh, this message translates to:
  /// **'正在导出…'**
  String get obsExportBusy;

  /// No description provided for @obsExportDone.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {count} 条记录'**
  String obsExportDone(int count);

  /// No description provided for @obsExportEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有符合条件的记录，未生成文件'**
  String get obsExportEmpty;

  /// No description provided for @obsExportCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消导出'**
  String get obsExportCancelled;

  /// No description provided for @obsExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败'**
  String get obsExportFailed;

  /// No description provided for @obsExportTruncated.
  ///
  /// In zh, this message translates to:
  /// **'已达到 {count} 条上限'**
  String obsExportTruncated(int count);

  /// No description provided for @obsExportFooter.
  ///
  /// In zh, this message translates to:
  /// **'CSV 文件（UTF-8），可用表格软件打开。'**
  String get obsExportFooter;

  /// No description provided for @obsExportAtLeastOneColumn.
  ///
  /// In zh, this message translates to:
  /// **'至少选择一个字段'**
  String get obsExportAtLeastOneColumn;

  /// No description provided for @obsExportInvalidLimit.
  ///
  /// In zh, this message translates to:
  /// **'请输入 1–{max} 之间的条数'**
  String obsExportInvalidLimit(int max);

  /// No description provided for @logsSubStatsTitle.
  ///
  /// In zh, this message translates to:
  /// **'订阅拦截率'**
  String get logsSubStatsTitle;

  /// No description provided for @logsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get logsRefresh;

  /// No description provided for @logsTimeRange.
  ///
  /// In zh, this message translates to:
  /// **'时间范围'**
  String get logsTimeRange;

  /// No description provided for @logsSubStatsFooter.
  ///
  /// In zh, this message translates to:
  /// **'拦截率为所选时间范围内，该订阅拦截请求数占全部已记录请求（DNS + HTTPS）的比例。'**
  String get logsSubStatsFooter;

  /// No description provided for @logsOverview.
  ///
  /// In zh, this message translates to:
  /// **'概览'**
  String get logsOverview;

  /// No description provided for @logsSubStatsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取拦截统计'**
  String get logsSubStatsLoadFailed;

  /// No description provided for @logsLoadingStats.
  ///
  /// In zh, this message translates to:
  /// **'正在加载统计数据'**
  String get logsLoadingStats;

  /// No description provided for @logsBlockingSubs.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽订阅'**
  String get logsBlockingSubs;

  /// No description provided for @logsMissingSubColumn.
  ///
  /// In zh, this message translates to:
  /// **'当前数据库缺少订阅标记列'**
  String get logsMissingSubColumn;

  /// No description provided for @logsMissingSubColumnBody.
  ///
  /// In zh, this message translates to:
  /// **'这张库是在加入「订阅拦截统计」之前创建的，日志行里没有记录 blockSubscriptionId。重新产生请求日志后即可统计，历史数据无法补算。'**
  String get logsMissingSubColumnBody;

  /// No description provided for @logsAllRecordedRequests.
  ///
  /// In zh, this message translates to:
  /// **'全部已记录请求'**
  String get logsAllRecordedRequests;

  /// No description provided for @logsBlockedRequests.
  ///
  /// In zh, this message translates to:
  /// **'拦截请求'**
  String get logsBlockedRequests;

  /// No description provided for @logsAllRecordedFooter.
  ///
  /// In zh, this message translates to:
  /// **'DNS 与 HTTPS 日志合计，含通过、屏蔽和失败。'**
  String get logsAllRecordedFooter;

  /// No description provided for @logsNoBlockingSubs.
  ///
  /// In zh, this message translates to:
  /// **'暂无屏蔽订阅'**
  String get logsNoBlockingSubs;

  /// No description provided for @logsNoBlockingSubsBody.
  ///
  /// In zh, this message translates to:
  /// **'导入屏蔽订阅并产生 DNS 或 HTTPS 请求后，此处将显示其拦截率。'**
  String get logsNoBlockingSubsBody;

  /// No description provided for @logsBlockingSubsFooter.
  ///
  /// In zh, this message translates to:
  /// **'按拦截次数排序；「已删除」表示订阅已移除，但历史命中仍保留。'**
  String get logsBlockingSubsFooter;

  /// No description provided for @logsExpired.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get logsExpired;

  /// No description provided for @logsRaceTitle.
  ///
  /// In zh, this message translates to:
  /// **'竞速统计'**
  String get logsRaceTitle;

  /// No description provided for @logsRaceFooter.
  ///
  /// In zh, this message translates to:
  /// **'只统计真实发出过 DoH 请求的竞速解析；本机缓存命中的查询不进这张表。'**
  String get logsRaceFooter;

  /// No description provided for @logsRaceLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取竞速记录'**
  String get logsRaceLoadFailed;

  /// No description provided for @logsLoadingRace.
  ///
  /// In zh, this message translates to:
  /// **'正在读取竞速记录'**
  String get logsLoadingRace;

  /// No description provided for @logsRaceSummary.
  ///
  /// In zh, this message translates to:
  /// **'{range}内共 {count} 次竞速解析。'**
  String logsRaceSummary(String range, String count);

  /// No description provided for @logsRaceEmptyRange.
  ///
  /// In zh, this message translates to:
  /// **'所选时间范围内还没有竞速记录。'**
  String get logsRaceEmptyRange;

  /// No description provided for @logsRaceRequests.
  ///
  /// In zh, this message translates to:
  /// **'竞速请求'**
  String get logsRaceRequests;

  /// No description provided for @logsSuccess.
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get logsSuccess;

  /// No description provided for @logsAverageElapsed.
  ///
  /// In zh, this message translates to:
  /// **'平均耗时'**
  String get logsAverageElapsed;

  /// No description provided for @logsStrategyOverview.
  ///
  /// In zh, this message translates to:
  /// **'策略概览'**
  String get logsStrategyOverview;

  /// No description provided for @logsStrategyFooter.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中的请求不触发竞速，因此不进这张表；首选命中率 = 首选服务商即胜出且成功的比例。'**
  String get logsStrategyFooter;

  /// No description provided for @logsWinnerProviders.
  ///
  /// In zh, this message translates to:
  /// **'胜出服务商'**
  String get logsWinnerProviders;

  /// No description provided for @logsNoWinners.
  ///
  /// In zh, this message translates to:
  /// **'还没有胜出记录'**
  String get logsNoWinners;

  /// No description provided for @logsNoWinnersBody.
  ///
  /// In zh, this message translates to:
  /// **'竞速解析成功后，胜出的服务商会在这里按次数排序。'**
  String get logsNoWinnersBody;

  /// No description provided for @logsWinnerFooter.
  ///
  /// In zh, this message translates to:
  /// **'按胜出次数排序；平均耗时是该服务商胜出时的耗时均值。'**
  String get logsWinnerFooter;

  /// No description provided for @logsAverageWinLatency.
  ///
  /// In zh, this message translates to:
  /// **'平均胜出耗时 {latency}'**
  String logsAverageWinLatency(String latency);

  /// No description provided for @logsSmartPrimary.
  ///
  /// In zh, this message translates to:
  /// **'智能选择首选'**
  String get logsSmartPrimary;

  /// No description provided for @logsSmartPrimaryFooter.
  ///
  /// In zh, this message translates to:
  /// **'只有智能选择策略下才有意义；首选命中率统计「首选服务商就是胜出者」的比例，兜底救回的查询不计入。'**
  String get logsSmartPrimaryFooter;

  /// No description provided for @logsPrimaryHit.
  ///
  /// In zh, this message translates to:
  /// **'首选命中 {percent} · 平均首选耗时 {latency}'**
  String logsPrimaryHit(String percent, String latency);

  /// No description provided for @logsDashboardTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志仪表盘'**
  String get logsDashboardTitle;

  /// No description provided for @logsModeTooltip.
  ///
  /// In zh, this message translates to:
  /// **'日志模式'**
  String get logsModeTooltip;

  /// No description provided for @logsRequestsDashboard.
  ///
  /// In zh, this message translates to:
  /// **'请求日志仪表盘'**
  String get logsRequestsDashboard;

  /// No description provided for @logsRequestsDashboardBody.
  ///
  /// In zh, this message translates to:
  /// **'全部 DNS、HTTPS、缓存、竞速与规则拦截的实时概览'**
  String get logsRequestsDashboardBody;

  /// No description provided for @logsFocusedDashboard.
  ///
  /// In zh, this message translates to:
  /// **'重点请求仪表盘'**
  String get logsFocusedDashboard;

  /// No description provided for @logsFocusedDashboardBody.
  ///
  /// In zh, this message translates to:
  /// **'DNS 与 HTTPS 拦截、错误、旁路记录及解析状态概览'**
  String get logsFocusedDashboardBody;

  /// No description provided for @logsServiceOverview.
  ///
  /// In zh, this message translates to:
  /// **'服务状态与解析概览'**
  String get logsServiceOverview;

  /// No description provided for @logsPrivacyBody.
  ///
  /// In zh, this message translates to:
  /// **'当前处于隐私模式，不记录请求明细。DNS 缓存、并发竞速与网络流量监控仍正常运行。'**
  String get logsPrivacyBody;

  /// No description provided for @logsCacheTableTitle.
  ///
  /// In zh, this message translates to:
  /// **'DNS 缓存表'**
  String get logsCacheTableTitle;

  /// No description provided for @logsCacheLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取缓存表：{detail}'**
  String logsCacheLoadFailed(String detail);

  /// No description provided for @logsLoadingCache.
  ///
  /// In zh, this message translates to:
  /// **'正在读取缓存表'**
  String get logsLoadingCache;

  /// No description provided for @logsCacheEmpty.
  ///
  /// In zh, this message translates to:
  /// **'缓存表还没有条目'**
  String get logsCacheEmpty;

  /// No description provided for @logsCacheNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的缓存'**
  String get logsCacheNoMatch;

  /// No description provided for @logsCacheEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'引擎解析成功后会把应答写进 dns_cache；全新安装或隧道刚启动时这张表可能还是空的。'**
  String get logsCacheEmptyBody;

  /// No description provided for @logsCurrentSearch.
  ///
  /// In zh, this message translates to:
  /// **'当前搜索：{query}'**
  String logsCurrentSearch(String query);

  /// No description provided for @logsLiveCache.
  ///
  /// In zh, this message translates to:
  /// **'有效缓存'**
  String get logsLiveCache;

  /// No description provided for @logsNeverHit.
  ///
  /// In zh, this message translates to:
  /// **'尚未命中'**
  String get logsNeverHit;

  /// No description provided for @logsCacheFooter.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 条，按命中次数与过期时间排序。剩余 TTL 少于 30 秒的条目标橙色。点按一行查看详情，可复制域名、加入黑白名单或用 AI 分析。'**
  String logsCacheFooter(String count);

  /// No description provided for @logsBootstrapTitle.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 统计'**
  String get logsBootstrapTitle;

  /// No description provided for @logsBootstrapFooter.
  ///
  /// In zh, this message translates to:
  /// **'成功率为成功次数 ÷ 尝试次数；平均耗时按各节点的尝试次数加权。'**
  String get logsBootstrapFooter;

  /// No description provided for @logsBootstrapLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取 Bootstrap 记录'**
  String get logsBootstrapLoadFailed;

  /// No description provided for @logsLoadingBootstrap.
  ///
  /// In zh, this message translates to:
  /// **'正在读取 Bootstrap 记录'**
  String get logsLoadingBootstrap;

  /// No description provided for @logsBootstrapSummary.
  ///
  /// In zh, this message translates to:
  /// **'{range}内共 {count} 次 Bootstrap 探测。'**
  String logsBootstrapSummary(String range, String count);

  /// No description provided for @logsBootstrapEmptyRange.
  ///
  /// In zh, this message translates to:
  /// **'所选时间范围内还没有 Bootstrap 探测记录。'**
  String get logsBootstrapEmptyRange;

  /// No description provided for @logsAttempts.
  ///
  /// In zh, this message translates to:
  /// **'尝试次数'**
  String get logsAttempts;

  /// No description provided for @logsSuccessRate.
  ///
  /// In zh, this message translates to:
  /// **'成功率'**
  String get logsSuccessRate;

  /// No description provided for @logsNodes.
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get logsNodes;

  /// No description provided for @logsNoProbes.
  ///
  /// In zh, this message translates to:
  /// **'还没有探测记录'**
  String get logsNoProbes;

  /// No description provided for @logsNoProbesBody.
  ///
  /// In zh, this message translates to:
  /// **'开启「启用 Bootstrap IP」并产生解析后，各节点的尝试与成功率会出现在这里。'**
  String get logsNoProbesBody;

  /// No description provided for @logsNodesFooter.
  ///
  /// In zh, this message translates to:
  /// **'按尝试次数排序；显示最近窗口内的聚合值。'**
  String get logsNodesFooter;

  /// No description provided for @logsCacheDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存详情'**
  String get logsCacheDetailTitle;

  /// No description provided for @logsCacheExpiringBody.
  ///
  /// In zh, this message translates to:
  /// **'缓存即将过期，过期后下一次查询会重新向上游解析'**
  String get logsCacheExpiringBody;

  /// No description provided for @logsCacheValidBody.
  ///
  /// In zh, this message translates to:
  /// **'缓存有效，命中时直接返回应答，不再请求上游'**
  String get logsCacheValidBody;

  /// No description provided for @logsExpiring.
  ///
  /// In zh, this message translates to:
  /// **'即将过期'**
  String get logsExpiring;

  /// No description provided for @logsValid.
  ///
  /// In zh, this message translates to:
  /// **'有效'**
  String get logsValid;

  /// No description provided for @logsHitTimes.
  ///
  /// In zh, this message translates to:
  /// **'命中 {count} 次'**
  String logsHitTimes(int count);

  /// No description provided for @logsCacheInfo.
  ///
  /// In zh, this message translates to:
  /// **'缓存信息'**
  String get logsCacheInfo;

  /// No description provided for @logsRecordType.
  ///
  /// In zh, this message translates to:
  /// **'记录类型'**
  String get logsRecordType;

  /// No description provided for @logsRemainingTtl.
  ///
  /// In zh, this message translates to:
  /// **'剩余 TTL'**
  String get logsRemainingTtl;

  /// No description provided for @logsOriginalTtl.
  ///
  /// In zh, this message translates to:
  /// **'原始 TTL'**
  String get logsOriginalTtl;

  /// No description provided for @logsExpiry.
  ///
  /// In zh, this message translates to:
  /// **'过期时间'**
  String get logsExpiry;

  /// No description provided for @logsHitCount.
  ///
  /// In zh, this message translates to:
  /// **'命中次数'**
  String get logsHitCount;

  /// No description provided for @logsLastHit.
  ///
  /// In zh, this message translates to:
  /// **'最后命中'**
  String get logsLastHit;

  /// No description provided for @logsResponseSize.
  ///
  /// In zh, this message translates to:
  /// **'应答大小'**
  String get logsResponseSize;

  /// No description provided for @logsAnalyzeDomain.
  ///
  /// In zh, this message translates to:
  /// **'分析这个域名'**
  String get logsAnalyzeDomain;

  /// No description provided for @logsCacheDetailFooter.
  ///
  /// In zh, this message translates to:
  /// **'缓存表每 10 秒从引擎内存同步一次，这里是打开时的快照。加入的黑白名单可在「规则」页查看和撤销。'**
  String get logsCacheDetailFooter;

  /// No description provided for @logsAiInsight.
  ///
  /// In zh, this message translates to:
  /// **'AI 研判'**
  String get logsAiInsight;

  /// No description provided for @logsNotAnalysed.
  ///
  /// In zh, this message translates to:
  /// **'未分析'**
  String get logsNotAnalysed;

  /// No description provided for @logsHasReport.
  ///
  /// In zh, this message translates to:
  /// **'已有结论'**
  String get logsHasReport;

  /// No description provided for @logsAiInsightBody.
  ///
  /// In zh, this message translates to:
  /// **'把最近的 DNS 与 HTTPS 记录交给配置的模型，汇总异常请求、防护效果与优化建议。'**
  String get logsAiInsightBody;

  /// No description provided for @logsAnalyseTraffic.
  ///
  /// In zh, this message translates to:
  /// **'用 AI 研判最近流量'**
  String get logsAnalyseTraffic;

  /// No description provided for @logsViewFullReport.
  ///
  /// In zh, this message translates to:
  /// **'查看完整报告'**
  String get logsViewFullReport;

  /// No description provided for @logsModelName.
  ///
  /// In zh, this message translates to:
  /// **'模型 {model}'**
  String logsModelName(String model);

  /// No description provided for @logsSuccessWith.
  ///
  /// In zh, this message translates to:
  /// **'成功 {percent}'**
  String logsSuccessWith(String percent);

  /// No description provided for @logsAverageWith.
  ///
  /// In zh, this message translates to:
  /// **'平均 {latency}'**
  String logsAverageWith(String latency);

  /// No description provided for @logsPrimaryHitOnly.
  ///
  /// In zh, this message translates to:
  /// **'首选命中 {percent}'**
  String logsPrimaryHitOnly(String percent);

  /// No description provided for @logsFallbackUses.
  ///
  /// In zh, this message translates to:
  /// **'兜底 {count} 次'**
  String logsFallbackUses(String count);

  /// No description provided for @logsBootstrapRow.
  ///
  /// In zh, this message translates to:
  /// **'{ip} · 成功 {percent} · 平均 {latency}{failures}'**
  String logsBootstrapRow(
    String ip,
    String percent,
    String latency,
    String failures,
  );

  /// No description provided for @logsBootstrapFailures.
  ///
  /// In zh, this message translates to:
  /// **' · 失败 {count} 次'**
  String logsBootstrapFailures(String count);

  /// No description provided for @logsEntryCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String logsEntryCount(int count);

  /// No description provided for @logsCacheRow.
  ///
  /// In zh, this message translates to:
  /// **'{ttl} · 命中 {count} 次 · {size} B'**
  String logsCacheRow(String ttl, int count, int size);

  /// No description provided for @logsLastHitAt.
  ///
  /// In zh, this message translates to:
  /// **'最后命中 {time}'**
  String logsLastHitAt(String time);

  /// No description provided for @logsCacheFooterCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 条，按命中次数与过期时间排序。剩余 TTL 少于 30 秒的条目标橙色。点按一行查看详情，可复制域名、加入黑白名单或用 AI 分析。'**
  String logsCacheFooterCount(int count);

  /// No description provided for @logsSubStatsRow.
  ///
  /// In zh, this message translates to:
  /// **'{status} · 拦截 {count} 次'**
  String logsSubStatsRow(String status, String count);

  /// No description provided for @aboutTitle.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get aboutTitle;

  /// No description provided for @aboutMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get aboutMore;

  /// No description provided for @aboutProject.
  ///
  /// In zh, this message translates to:
  /// **'项目'**
  String get aboutProject;

  /// No description provided for @aboutJoinQq.
  ///
  /// In zh, this message translates to:
  /// **'加入 QQ 群'**
  String get aboutJoinQq;

  /// No description provided for @aboutQqGroup.
  ///
  /// In zh, this message translates to:
  /// **'群号 {number}'**
  String aboutQqGroup(String number);

  /// No description provided for @aboutSponsor.
  ///
  /// In zh, this message translates to:
  /// **'赞助'**
  String get aboutSponsor;

  /// No description provided for @aboutCredits.
  ///
  /// In zh, this message translates to:
  /// **'开源致谢'**
  String get aboutCredits;

  /// No description provided for @aboutCreditsUi.
  ///
  /// In zh, this message translates to:
  /// **'界面组件与交互实现复用自该项目'**
  String get aboutCreditsUi;

  /// No description provided for @aboutCreditsCore.
  ///
  /// In zh, this message translates to:
  /// **'Go 隧道内核最初魔改自该项目'**
  String get aboutCreditsCore;

  /// No description provided for @aboutCreditsBody.
  ///
  /// In zh, this message translates to:
  /// **'上述两个项目均以 GPL-3.0 协议开源，相关代码与设计的版权归各自作者所有。谛听的界面层大量借鉴了 FlClash 的实现思路，隧道内核也源自 blockads-android 的早期改造；在此向它们的作者与所有贡献者致以诚挚谢意。'**
  String get aboutCreditsBody;

  /// No description provided for @aboutSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get aboutSettings;

  /// No description provided for @aboutStartupCheck.
  ///
  /// In zh, this message translates to:
  /// **'关闭启动时检查更新'**
  String get aboutStartupCheck;

  /// No description provided for @aboutStartupCheckOn.
  ///
  /// In zh, this message translates to:
  /// **'应用启动时不自动检查，可随时手动检查'**
  String get aboutStartupCheckOn;

  /// No description provided for @aboutStartupCheckOff.
  ///
  /// In zh, this message translates to:
  /// **'应用启动时自动检查新版本'**
  String get aboutStartupCheckOff;

  /// No description provided for @aboutDisclaimerEntry.
  ///
  /// In zh, this message translates to:
  /// **'使用须知与免责声明'**
  String get aboutDisclaimerEntry;

  /// No description provided for @aboutDisclaimerEntryBody.
  ///
  /// In zh, this message translates to:
  /// **'软件说明、运行机制与免责条款全文'**
  String get aboutDisclaimerEntryBody;

  /// No description provided for @aboutOtherContributors.
  ///
  /// In zh, this message translates to:
  /// **'其他贡献者'**
  String get aboutOtherContributors;

  /// No description provided for @aboutSponsorList.
  ///
  /// In zh, this message translates to:
  /// **'赞助者名单'**
  String get aboutSponsorList;

  /// No description provided for @aboutSponsorListBody.
  ///
  /// In zh, this message translates to:
  /// **'鸣谢支持谛听项目的赞助者'**
  String get aboutSponsorListBody;

  /// No description provided for @aboutBuilderList.
  ///
  /// In zh, this message translates to:
  /// **'共建者名单'**
  String get aboutBuilderList;

  /// No description provided for @aboutBuilderListBody.
  ///
  /// In zh, this message translates to:
  /// **'感谢为谛听贡献代码与建议的共建者'**
  String get aboutBuilderListBody;

  /// No description provided for @aboutInstallerFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法调起系统安装器'**
  String get aboutInstallerFailed;

  /// No description provided for @aboutAppName.
  ///
  /// In zh, this message translates to:
  /// **'谛听'**
  String get aboutAppName;

  /// No description provided for @aboutTagline.
  ///
  /// In zh, this message translates to:
  /// **'基于 Android VpnService 的本地优先 DNS 加速与流量过滤工具，简单易用，开源无广告。'**
  String get aboutTagline;

  /// No description provided for @aboutChecking.
  ///
  /// In zh, this message translates to:
  /// **'检查中…'**
  String get aboutChecking;

  /// No description provided for @aboutCheckUpdate.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get aboutCheckUpdate;

  /// No description provided for @aboutDownloading.
  ///
  /// In zh, this message translates to:
  /// **'下载中…'**
  String get aboutDownloading;

  /// No description provided for @aboutInstall.
  ///
  /// In zh, this message translates to:
  /// **'安装'**
  String get aboutInstall;

  /// No description provided for @aboutDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get aboutDownload;

  /// No description provided for @aboutCheckingRelease.
  ///
  /// In zh, this message translates to:
  /// **'正在检查 GitHub Release'**
  String get aboutCheckingRelease;

  /// No description provided for @aboutUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本{version}'**
  String aboutUpToDate(String version);

  /// No description provided for @aboutVersionSuffix.
  ///
  /// In zh, this message translates to:
  /// **'（{version}）'**
  String aboutVersionSuffix(String version);

  /// No description provided for @aboutFoundVersion.
  ///
  /// In zh, this message translates to:
  /// **'发现 {version}版本'**
  String aboutFoundVersion(String version);

  /// No description provided for @aboutCurrentSuffix.
  ///
  /// In zh, this message translates to:
  /// **'（当前 {version}）'**
  String aboutCurrentSuffix(String version);

  /// No description provided for @aboutNew.
  ///
  /// In zh, this message translates to:
  /// **'新'**
  String get aboutNew;

  /// No description provided for @aboutNewVersion.
  ///
  /// In zh, this message translates to:
  /// **'新版本'**
  String get aboutNewVersion;

  /// No description provided for @aboutUpdatePackage.
  ///
  /// In zh, this message translates to:
  /// **'{version} 更新包'**
  String aboutUpdatePackage(String version);

  /// No description provided for @aboutLinkCopyFallback.
  ///
  /// In zh, this message translates to:
  /// **'未能打开浏览器，链接已复制：{url}'**
  String aboutLinkCopyFallback(String url);

  /// No description provided for @devStressLogs.
  ///
  /// In zh, this message translates to:
  /// **'日志压测'**
  String get devStressLogs;

  /// No description provided for @devStressLogsBody.
  ///
  /// In zh, this message translates to:
  /// **'向当前模式的日志库真实写入 {count} 条 DNS 日志'**
  String devStressLogsBody(int count);

  /// No description provided for @devErrorReport.
  ///
  /// In zh, this message translates to:
  /// **'错误上报自检'**
  String get devErrorReport;

  /// No description provided for @devErrorReportBody.
  ///
  /// In zh, this message translates to:
  /// **'通过 FlutterError 上报一条测试异常，验证错误链路'**
  String get devErrorReportBody;

  /// No description provided for @devClearAll.
  ///
  /// In zh, this message translates to:
  /// **'清空全部数据'**
  String get devClearAll;

  /// No description provided for @devClearAllBody.
  ///
  /// In zh, this message translates to:
  /// **'删除配置、规则与日志，恢复出厂状态'**
  String get devClearAllBody;

  /// No description provided for @devVacuum.
  ///
  /// In zh, this message translates to:
  /// **'压缩数据库'**
  String get devVacuum;

  /// No description provided for @devVacuumBody.
  ///
  /// In zh, this message translates to:
  /// **'对三个本地库执行 VACUUM，回收已删除记录占用的空间'**
  String get devVacuumBody;

  /// No description provided for @devCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get devCancel;

  /// No description provided for @devRun.
  ///
  /// In zh, this message translates to:
  /// **'执行'**
  String get devRun;

  /// No description provided for @devConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'{action}\n\n该操作会真正改写本机数据，无法撤销。'**
  String devConfirmBody(String action);

  /// No description provided for @devActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'{action}失败：{error}'**
  String devActionFailed(String action, String error);

  /// No description provided for @devStressNoDb.
  ///
  /// In zh, this message translates to:
  /// **'日志压测失败：无法打开日志数据库'**
  String get devStressNoDb;

  /// No description provided for @devStressDone.
  ///
  /// In zh, this message translates to:
  /// **'日志压测完成：写入 {count} 条到 {file}'**
  String devStressDone(String count, String file);

  /// No description provided for @devTestException.
  ///
  /// In zh, this message translates to:
  /// **'开发者选项触发的测试异常'**
  String get devTestException;

  /// No description provided for @devErrorReported.
  ///
  /// In zh, this message translates to:
  /// **'已上报一条 FlutterError：开发者选项触发的测试异常'**
  String get devErrorReported;

  /// No description provided for @devVacuumNoDb.
  ///
  /// In zh, this message translates to:
  /// **'压缩数据库失败：本机还没有数据库文件'**
  String get devVacuumNoDb;

  /// No description provided for @devVacuumDone.
  ///
  /// In zh, this message translates to:
  /// **'已压缩 {files}，回收 {kb} KB'**
  String devVacuumDone(String files, int kb);

  /// No description provided for @devRestartNeeded.
  ///
  /// In zh, this message translates to:
  /// **'需要重启'**
  String get devRestartNeeded;

  /// No description provided for @devLater.
  ///
  /// In zh, this message translates to:
  /// **'稍后'**
  String get devLater;

  /// No description provided for @devQuitNow.
  ///
  /// In zh, this message translates to:
  /// **'立即退出'**
  String get devQuitNow;

  /// No description provided for @devClearAllDone.
  ///
  /// In zh, this message translates to:
  /// **'全部数据已清空，需要重新启动应用才能从出厂状态进入。'**
  String get devClearAllDone;

  /// No description provided for @devOptions.
  ///
  /// In zh, this message translates to:
  /// **'开发者选项'**
  String get devOptions;

  /// No description provided for @devDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'诊断与观测'**
  String get devDiagnostics;

  /// No description provided for @devIpQuality.
  ///
  /// In zh, this message translates to:
  /// **'IP 质量'**
  String get devIpQuality;

  /// No description provided for @devIpQualityBody.
  ///
  /// In zh, this message translates to:
  /// **'实测出口地址与三个公开情报源的类型判断'**
  String get devIpQualityBody;

  /// No description provided for @devRequestLogs.
  ///
  /// In zh, this message translates to:
  /// **'请求日志'**
  String get devRequestLogs;

  /// No description provided for @devRequestLogsBody.
  ///
  /// In zh, this message translates to:
  /// **'合并 http_request_log 与 dns_log 的实时请求记录'**
  String get devRequestLogsBody;

  /// No description provided for @devLogRetention.
  ///
  /// In zh, this message translates to:
  /// **'日志保留'**
  String get devLogRetention;

  /// No description provided for @devLogRetentionBody.
  ///
  /// In zh, this message translates to:
  /// **'日志容量上限与 DNS 请求日志的记录范围'**
  String get devLogRetentionBody;

  /// No description provided for @devTroubleshoot.
  ///
  /// In zh, this message translates to:
  /// **'故障排查'**
  String get devTroubleshoot;

  /// No description provided for @devTroubleshootBody.
  ///
  /// In zh, this message translates to:
  /// **'导出崩溃日志，手动抓取并导出运行日志'**
  String get devTroubleshootBody;

  /// No description provided for @devDataCleanup.
  ///
  /// In zh, this message translates to:
  /// **'数据清理'**
  String get devDataCleanup;

  /// No description provided for @devUnlocked.
  ///
  /// In zh, this message translates to:
  /// **'实验动作已解锁'**
  String get devUnlocked;

  /// No description provided for @devLocked.
  ///
  /// In zh, this message translates to:
  /// **'关闭时下面的动作不可用'**
  String get devLocked;

  /// No description provided for @devWarning.
  ///
  /// In zh, this message translates to:
  /// **'这里的动作会真的改写本机数据（日志库、prefs、数据库文件），其中「清空全部数据」不可撤销，不要在生产环境打开。'**
  String get devWarning;

  /// No description provided for @devRunning.
  ///
  /// In zh, this message translates to:
  /// **'执行中…'**
  String get devRunning;

  /// No description provided for @sponsorGithub.
  ///
  /// In zh, this message translates to:
  /// **'在 GitHub 查看赞助方式'**
  String get sponsorGithub;

  /// No description provided for @sponsorReadme.
  ///
  /// In zh, this message translates to:
  /// **'查看 README 中的赞助说明'**
  String get sponsorReadme;

  /// No description provided for @sponsorReadmeCopied.
  ///
  /// In zh, this message translates to:
  /// **'未能打开浏览器，README 地址已复制'**
  String get sponsorReadmeCopied;

  /// No description provided for @sponsorThanks.
  ///
  /// In zh, this message translates to:
  /// **'致谢名单'**
  String get sponsorThanks;

  /// No description provided for @sponsorThanksBody.
  ///
  /// In zh, this message translates to:
  /// **'感谢每一位支持项目的朋友'**
  String get sponsorThanksBody;

  /// No description provided for @sponsorBuildersBody.
  ///
  /// In zh, this message translates to:
  /// **'感谢提出建议与帮助测试的伙伴'**
  String get sponsorBuildersBody;

  /// No description provided for @sponsorUsage.
  ///
  /// In zh, this message translates to:
  /// **'你的每一笔支持都会用于'**
  String get sponsorUsage;

  /// No description provided for @sponsorUsageNewFeatures.
  ///
  /// In zh, this message translates to:
  /// **'持续开发新功能'**
  String get sponsorUsageNewFeatures;

  /// No description provided for @sponsorUsageBugs.
  ///
  /// In zh, this message translates to:
  /// **'修复 Bug'**
  String get sponsorUsageBugs;

  /// No description provided for @sponsorUsageTokens.
  ///
  /// In zh, this message translates to:
  /// **'购买词元'**
  String get sponsorUsageTokens;

  /// No description provided for @sponsorFreeWays.
  ///
  /// In zh, this message translates to:
  /// **'即使不捐赠，也欢迎'**
  String get sponsorFreeWays;

  /// No description provided for @sponsorFreeStar.
  ///
  /// In zh, this message translates to:
  /// **'点一个 Star⭐'**
  String get sponsorFreeStar;

  /// No description provided for @sponsorFreeIssue.
  ///
  /// In zh, this message translates to:
  /// **'提交 Issue'**
  String get sponsorFreeIssue;

  /// No description provided for @sponsorFreePr.
  ///
  /// In zh, this message translates to:
  /// **'提交 PR'**
  String get sponsorFreePr;

  /// No description provided for @sponsorFreeShare.
  ///
  /// In zh, this message translates to:
  /// **'分享给更多人'**
  String get sponsorFreeShare;

  /// No description provided for @sponsorFooter.
  ///
  /// In zh, this message translates to:
  /// **'感谢每一位支持项目的朋友！'**
  String get sponsorFooter;

  /// No description provided for @sponsorBuyDrink.
  ///
  /// In zh, this message translates to:
  /// **'请作者喝杯蜜雪 🧋'**
  String get sponsorBuyDrink;

  /// No description provided for @sponsorSupportKicker.
  ///
  /// In zh, this message translates to:
  /// **'// 支持项目'**
  String get sponsorSupportKicker;

  /// No description provided for @sponsorNote.
  ///
  /// In zh, this message translates to:
  /// **'如果这个项目帮助到了你，欢迎请作者喝杯蜜雪。付款时请备注昵称，以便同步加入赞助者名单。'**
  String get sponsorNote;

  /// No description provided for @sponsorAlipay.
  ///
  /// In zh, this message translates to:
  /// **'支付宝'**
  String get sponsorAlipay;

  /// No description provided for @sponsorWechat.
  ///
  /// In zh, this message translates to:
  /// **'微信支付'**
  String get sponsorWechat;

  /// No description provided for @sponsorNickname.
  ///
  /// In zh, this message translates to:
  /// **'备注昵称'**
  String get sponsorNickname;

  /// No description provided for @sponsorScan.
  ///
  /// In zh, this message translates to:
  /// **'扫码赞助'**
  String get sponsorScan;

  /// No description provided for @sponsorQrCode.
  ///
  /// In zh, this message translates to:
  /// **'{label} 收款码'**
  String sponsorQrCode(String label);

  /// No description provided for @sponsorClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get sponsorClose;

  /// No description provided for @sponsorNoteShort.
  ///
  /// In zh, this message translates to:
  /// **'付款时请备注昵称，以便同步加入赞助者名单。'**
  String get sponsorNoteShort;

  /// No description provided for @aboutQqCopied.
  ///
  /// In zh, this message translates to:
  /// **'未检测到 QQ，群号已复制：{number}'**
  String aboutQqCopied(String number);

  /// No description provided for @disclaimerTitle.
  ///
  /// In zh, this message translates to:
  /// **'免责声明'**
  String get disclaimerTitle;

  /// No description provided for @disclaimerTerms.
  ///
  /// In zh, this message translates to:
  /// **'条款全文'**
  String get disclaimerTerms;

  /// No description provided for @disclaimerSource.
  ///
  /// In zh, this message translates to:
  /// **'正式条款以仓库 NOTICE.md 与随包 LICENSE 为准。'**
  String get disclaimerSource;

  /// No description provided for @ipQualityRedetect.
  ///
  /// In zh, this message translates to:
  /// **'重新检测'**
  String get ipQualityRedetect;

  /// No description provided for @ipQualityEgress.
  ///
  /// In zh, this message translates to:
  /// **'当前出口地址'**
  String get ipQualityEgress;

  /// No description provided for @ipQualitySources.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get ipQualitySources;

  /// No description provided for @ipQualitySourcesFooter.
  ///
  /// In zh, this message translates to:
  /// **'各来源对「住宅 / 机房」的判断经常互相矛盾：命中数越多越可信，但单一来源的「风险」标签不足以作为结论。'**
  String get ipQualitySourcesFooter;

  /// No description provided for @ipQualityQuerying.
  ///
  /// In zh, this message translates to:
  /// **'正在查询出口 IP 与 3 个情报源…'**
  String get ipQualityQuerying;

  /// No description provided for @ipQualityChecking.
  ///
  /// In zh, this message translates to:
  /// **'检测中…'**
  String get ipQualityChecking;

  /// No description provided for @ipQualityDetecting.
  ///
  /// In zh, this message translates to:
  /// **'正在检测'**
  String get ipQualityDetecting;

  /// No description provided for @ipQualityFailed.
  ///
  /// In zh, this message translates to:
  /// **'检测失败'**
  String get ipQualityFailed;

  /// No description provided for @ipQualityNotYet.
  ///
  /// In zh, this message translates to:
  /// **'尚未检测'**
  String get ipQualityNotYet;

  /// No description provided for @ipQualityDetectingBody.
  ///
  /// In zh, this message translates to:
  /// **'正在获取出口 IP 并查询情报源，请稍候'**
  String get ipQualityDetectingBody;

  /// No description provided for @ipQualityStartBody.
  ///
  /// In zh, this message translates to:
  /// **'点下方按钮开始检测当前出口 IP 的质量'**
  String get ipQualityStartBody;

  /// No description provided for @ipQualityStart.
  ///
  /// In zh, this message translates to:
  /// **'开始检测'**
  String get ipQualityStart;

  /// No description provided for @ipQualityJudgedAs.
  ///
  /// In zh, this message translates to:
  /// **'判定为{type}'**
  String ipQualityJudgedAs(String type);

  /// No description provided for @ipQualityNotUsed.
  ///
  /// In zh, this message translates to:
  /// **'未采用'**
  String get ipQualityNotUsed;

  /// No description provided for @ipQualityUsed.
  ///
  /// In zh, this message translates to:
  /// **'已采用'**
  String get ipQualityUsed;

  /// No description provided for @devFooterWarning.
  ///
  /// In zh, this message translates to:
  /// **'这些动作直接作用于本机的数据库、prefs 与 native 通道：日志压测会真的写入 {count} 条日志，压缩数据库执行的是 SQLite VACUUM，清空全部数据会删除所有本地数据并要求重启。'**
  String devFooterWarning(int count);

  /// No description provided for @devDataCleanupBody.
  ///
  /// In zh, this message translates to:
  /// **'按类别删除日志、权重、规则与缓存'**
  String get devDataCleanupBody;

  /// No description provided for @devConfigSection.
  ///
  /// In zh, this message translates to:
  /// **'配置与资源'**
  String get devConfigSection;

  /// No description provided for @devCustomResources.
  ///
  /// In zh, this message translates to:
  /// **'自定义资源'**
  String get devCustomResources;

  /// No description provided for @devCustomResourcesBody.
  ///
  /// In zh, this message translates to:
  /// **'User-Agent、按需连接等配置资源入口'**
  String get devCustomResourcesBody;

  /// No description provided for @devUserAgentBody.
  ///
  /// In zh, this message translates to:
  /// **'订阅下载与测速请求携带的 UA'**
  String get devUserAgentBody;

  /// No description provided for @devOnDemand.
  ///
  /// In zh, this message translates to:
  /// **'按需连接'**
  String get devOnDemand;

  /// No description provided for @devOnDemandBody.
  ///
  /// In zh, this message translates to:
  /// **'按 SSID 决定是否启动 VPN'**
  String get devOnDemandBody;

  /// No description provided for @devWebdav.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 云同步'**
  String get devWebdav;

  /// No description provided for @devWebdavBody.
  ///
  /// In zh, this message translates to:
  /// **'把备份真实上传到自建的 WebDAV 服务'**
  String get devWebdavBody;

  /// No description provided for @devUiSection.
  ///
  /// In zh, this message translates to:
  /// **'界面与外观保留项'**
  String get devUiSection;

  /// No description provided for @devFontFamilyBody.
  ///
  /// In zh, this message translates to:
  /// **'选择界面字体族，独立页'**
  String get devFontFamilyBody;

  /// No description provided for @devFontSizeBody.
  ///
  /// In zh, this message translates to:
  /// **'全局文字缩放；在外观设置「界面显示」组内联滑杆'**
  String get devFontSizeBody;

  /// No description provided for @devTabAnimation.
  ///
  /// In zh, this message translates to:
  /// **'Tab 动画'**
  String get devTabAnimation;

  /// No description provided for @devTabAnimationBody.
  ///
  /// In zh, this message translates to:
  /// **'切换底部标签时的入场动画；在外观设置「背景与动效」组内联选项'**
  String get devTabAnimationBody;

  /// No description provided for @devExperimental.
  ///
  /// In zh, this message translates to:
  /// **'实验动作'**
  String get devExperimental;

  /// No description provided for @devLegacyFooter.
  ///
  /// In zh, this message translates to:
  /// **'以上「诊断与观测」「配置与资源」「界面与外观保留项」里的页面都不属于旧版 1.4.3 的界面，保留供调试与组件验收；旧版对应的功能仍按旧版菜单进入，不经过本页。'**
  String get devLegacyFooter;

  /// No description provided for @unknownRouteTitle.
  ///
  /// In zh, this message translates to:
  /// **'页面不存在'**
  String get unknownRouteTitle;

  /// No description provided for @unknownRouteBody.
  ///
  /// In zh, this message translates to:
  /// **'找不到这个页面'**
  String get unknownRouteBody;

  /// No description provided for @unknownRouteBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get unknownRouteBack;

  /// No description provided for @disclaimerReadFirst.
  ///
  /// In zh, this message translates to:
  /// **'使用前请阅读'**
  String get disclaimerReadFirst;

  /// No description provided for @disclaimerIntro.
  ///
  /// In zh, this message translates to:
  /// **'谛听是一款开源的本地域名解析与流量观测工具。软件本身不提供、不代理、也不转发任何网络接入服务，全部数据都在本机处理。'**
  String get disclaimerIntro;

  /// No description provided for @disclaimerLawful.
  ///
  /// In zh, this message translates to:
  /// **'请在遵守所在地法律法规的前提下使用本软件。将本软件用于任何未经授权的网络环境，后果由使用者自行承担。'**
  String get disclaimerLawful;

  /// No description provided for @disclaimerFirstRun.
  ///
  /// In zh, this message translates to:
  /// **'首次启动时确认的文本'**
  String get disclaimerFirstRun;

  /// No description provided for @disclaimerImmutable.
  ///
  /// In zh, this message translates to:
  /// **'不可修改'**
  String get disclaimerImmutable;

  /// No description provided for @devFontFamily.
  ///
  /// In zh, this message translates to:
  /// **'字体'**
  String get devFontFamily;

  /// No description provided for @devFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get devFontSize;

  /// No description provided for @devWarningTitle.
  ///
  /// In zh, this message translates to:
  /// **'开发者模式'**
  String get devWarningTitle;

  /// No description provided for @devFooterLegacy.
  ///
  /// In zh, this message translates to:
  /// **'以上「诊断与观测」「配置与资源」「界面与外观保留项」里的页面都不属于旧版 1.4.3 的界面，保留供调试与组件验收；旧版对应的功能仍按旧版菜单进入，不经过本页。'**
  String get devFooterLegacy;

  /// No description provided for @devFooterMoved.
  ///
  /// In zh, this message translates to:
  /// **'IP 质量、请求日志、自定义资源等入口已统一收纳到「功能中心」对应分类，开发者选项在此仅保留以下实验动作。'**
  String get devFooterMoved;

  /// No description provided for @ipTypeResidential.
  ///
  /// In zh, this message translates to:
  /// **'住宅'**
  String get ipTypeResidential;

  /// No description provided for @ipTypeMobile.
  ///
  /// In zh, this message translates to:
  /// **'移动'**
  String get ipTypeMobile;

  /// No description provided for @ipTypeBusiness.
  ///
  /// In zh, this message translates to:
  /// **'商业'**
  String get ipTypeBusiness;

  /// No description provided for @ipTypeHosting.
  ///
  /// In zh, this message translates to:
  /// **'机房'**
  String get ipTypeHosting;

  /// No description provided for @ipLevelGood.
  ///
  /// In zh, this message translates to:
  /// **'优秀'**
  String get ipLevelGood;

  /// No description provided for @ipLevelNormal.
  ///
  /// In zh, this message translates to:
  /// **'一般'**
  String get ipLevelNormal;

  /// No description provided for @ipLevelRisky.
  ///
  /// In zh, this message translates to:
  /// **'风险'**
  String get ipLevelRisky;

  /// No description provided for @ipStatusOk.
  ///
  /// In zh, this message translates to:
  /// **'命中'**
  String get ipStatusOk;

  /// No description provided for @ipStatusNoType.
  ///
  /// In zh, this message translates to:
  /// **'无类型'**
  String get ipStatusNoType;

  /// No description provided for @ipStatusTimeout.
  ///
  /// In zh, this message translates to:
  /// **'超时'**
  String get ipStatusTimeout;

  /// No description provided for @ipStatusRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'限流'**
  String get ipStatusRateLimited;

  /// No description provided for @ipStatusMismatch.
  ///
  /// In zh, this message translates to:
  /// **'IP 不一致'**
  String get ipStatusMismatch;

  /// No description provided for @modeSelectTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择工作模式'**
  String get modeSelectTitle;

  /// No description provided for @modeContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get modeContinue;

  /// No description provided for @modeSwitchNote.
  ///
  /// In zh, this message translates to:
  /// **'随时可以在设置里重新选择；切换模式会先停止当前模式的服务，两个模式不会同时运行。'**
  String get modeSwitchNote;

  /// No description provided for @modeSharedNote.
  ///
  /// In zh, this message translates to:
  /// **'三种模式共用一套规则与缓存，区别在接管方式：普通模式走全隧道，服务器模式只做局域网 DNS，极速模式把路由收窄到只接管 DNS。'**
  String get modeSharedNote;

  /// No description provided for @modeNormalFeature1.
  ///
  /// In zh, this message translates to:
  /// **'全隧道接管'**
  String get modeNormalFeature1;

  /// No description provided for @modeNormalFeature1Body.
  ///
  /// In zh, this message translates to:
  /// **'Go 栈接管全部流量，可按应用分流'**
  String get modeNormalFeature1Body;

  /// No description provided for @modeNormalFeature2.
  ///
  /// In zh, this message translates to:
  /// **'全功能规则'**
  String get modeNormalFeature2;

  /// No description provided for @modeNormalFeature2Body.
  ///
  /// In zh, this message translates to:
  /// **'黑白名单、覆写、HTTPS 检查全部可用'**
  String get modeNormalFeature2Body;

  /// No description provided for @modeNormalFeature3.
  ///
  /// In zh, this message translates to:
  /// **'可选 HTTPS 检查'**
  String get modeNormalFeature3;

  /// No description provided for @modeNormalFeature3Body.
  ///
  /// In zh, this message translates to:
  /// **'需要安装并信任本地 CA 证书'**
  String get modeNormalFeature3Body;

  /// No description provided for @modeNormalFeature4.
  ///
  /// In zh, this message translates to:
  /// **'应用流量统计'**
  String get modeNormalFeature4;

  /// No description provided for @modeNormalFeature4Body.
  ///
  /// In zh, this message translates to:
  /// **'按应用记录上下行与查询数'**
  String get modeNormalFeature4Body;

  /// No description provided for @modeServerFeature1.
  ///
  /// In zh, this message translates to:
  /// **'局域网 DNS 服务'**
  String get modeServerFeature1;

  /// No description provided for @modeServerFeature1Body.
  ///
  /// In zh, this message translates to:
  /// **'监听 0.0.0.0，供同一网段设备使用'**
  String get modeServerFeature1Body;

  /// No description provided for @modeServerFeature2.
  ///
  /// In zh, this message translates to:
  /// **'不占 VPN 槽位'**
  String get modeServerFeature2;

  /// No description provided for @modeServerFeature2Body.
  ///
  /// In zh, this message translates to:
  /// **'本机不建立隧道，可与其它 VPN 共存'**
  String get modeServerFeature2Body;

  /// No description provided for @modeServerFeature3.
  ///
  /// In zh, this message translates to:
  /// **'共享规则与缓存'**
  String get modeServerFeature3;

  /// No description provided for @modeServerFeature3Body.
  ///
  /// In zh, this message translates to:
  /// **'与普通模式共用同一套规则库'**
  String get modeServerFeature3Body;

  /// No description provided for @modeServerFeature4.
  ///
  /// In zh, this message translates to:
  /// **'低功耗'**
  String get modeServerFeature4;

  /// No description provided for @modeServerFeature4Body.
  ///
  /// In zh, this message translates to:
  /// **'只处理 DNS 查询，无流量转发'**
  String get modeServerFeature4Body;

  /// No description provided for @modeExpressFeature1.
  ///
  /// In zh, this message translates to:
  /// **'Go 引擎 + 窄路由'**
  String get modeExpressFeature1;

  /// No description provided for @modeExpressFeature1Body.
  ///
  /// In zh, this message translates to:
  /// **'只接管 DNS 端口，其余流量直连物理网络'**
  String get modeExpressFeature1Body;

  /// No description provided for @modeExpressFeature2.
  ///
  /// In zh, this message translates to:
  /// **'四种上游调度'**
  String get modeExpressFeature2;

  /// No description provided for @modeExpressFeature2Body.
  ///
  /// In zh, this message translates to:
  /// **'单服务商 / 智能 / 竞速 / 主备'**
  String get modeExpressFeature2Body;

  /// No description provided for @modeExpressFeature3.
  ///
  /// In zh, this message translates to:
  /// **'64 分片 LRU 缓存'**
  String get modeExpressFeature3;

  /// No description provided for @modeExpressFeature3Body.
  ///
  /// In zh, this message translates to:
  /// **'命中率高、内存占用可控'**
  String get modeExpressFeature3Body;

  /// No description provided for @modeExpressFeature4.
  ///
  /// In zh, this message translates to:
  /// **'更低功耗'**
  String get modeExpressFeature4;

  /// No description provided for @modeExpressFeature4Body.
  ///
  /// In zh, this message translates to:
  /// **'只处理 DNS 查询，无全隧道转发'**
  String get modeExpressFeature4Body;

  /// No description provided for @onboardingTitle.
  ///
  /// In zh, this message translates to:
  /// **'引导'**
  String get onboardingTitle;

  /// No description provided for @onboardingSkip.
  ///
  /// In zh, this message translates to:
  /// **'跳过引导'**
  String get onboardingSkip;

  /// No description provided for @onboardingPrev.
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get onboardingPrev;

  /// No description provided for @onboardingStart.
  ///
  /// In zh, this message translates to:
  /// **'开始使用'**
  String get onboardingStart;

  /// No description provided for @onboardingNext.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get onboardingNext;

  /// No description provided for @onboardingChosen.
  ///
  /// In zh, this message translates to:
  /// **'你选择了{mode}'**
  String onboardingChosen(String mode);

  /// No description provided for @onboardingChangeable.
  ///
  /// In zh, this message translates to:
  /// **'之后还能改'**
  String get onboardingChangeable;

  /// No description provided for @onboardingChangeableBody.
  ///
  /// In zh, this message translates to:
  /// **'设置 → 重新选择工作模式，随时可以切换。切换会先停止当前模式的服务。'**
  String get onboardingChangeableBody;

  /// No description provided for @onboardingSharedRules.
  ///
  /// In zh, this message translates to:
  /// **'规则与缓存共用'**
  String get onboardingSharedRules;

  /// No description provided for @onboardingSharedRulesBody.
  ///
  /// In zh, this message translates to:
  /// **'三种模式共享同一套黑白名单与 DNS 缓存，不必为每个模式重配一遍。'**
  String get onboardingSharedRulesBody;

  /// No description provided for @onboardingExclusive.
  ///
  /// In zh, this message translates to:
  /// **'模式互斥'**
  String get onboardingExclusive;

  /// No description provided for @onboardingExclusiveBody.
  ///
  /// In zh, this message translates to:
  /// **'同一时刻只有一个模式在运行；离开时会先停掉上一个模式。'**
  String get onboardingExclusiveBody;

  /// No description provided for @permVpn.
  ///
  /// In zh, this message translates to:
  /// **'VPN 连接'**
  String get permVpn;

  /// No description provided for @permNotification.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get permNotification;

  /// No description provided for @permAppList.
  ///
  /// In zh, this message translates to:
  /// **'应用列表'**
  String get permAppList;

  /// No description provided for @permBattery.
  ///
  /// In zh, this message translates to:
  /// **'忽略电池优化'**
  String get permBattery;

  /// No description provided for @permRequired.
  ///
  /// In zh, this message translates to:
  /// **'必需'**
  String get permRequired;

  /// No description provided for @permOptional.
  ///
  /// In zh, this message translates to:
  /// **'可选'**
  String get permOptional;

  /// No description provided for @permVpnNormalBody.
  ///
  /// In zh, this message translates to:
  /// **'建立本地隧道接管流量；拒绝则无法启动'**
  String get permVpnNormalBody;

  /// No description provided for @permNotificationBody.
  ///
  /// In zh, this message translates to:
  /// **'前台服务常驻通知；拒绝则服务可能被系统回收'**
  String get permNotificationBody;

  /// No description provided for @permAppListBody.
  ///
  /// In zh, this message translates to:
  /// **'按应用分流与统计；拒绝则只能按域名规则'**
  String get permAppListBody;

  /// No description provided for @permBatteryBody.
  ///
  /// In zh, this message translates to:
  /// **'避免后台被杀；拒绝则长时间待机可能断开'**
  String get permBatteryBody;

  /// No description provided for @permBatteryServerBody.
  ///
  /// In zh, this message translates to:
  /// **'避免后台被杀；拒绝则局域网内会间歇不可用'**
  String get permBatteryServerBody;

  /// No description provided for @permVpnExpressBody.
  ///
  /// In zh, this message translates to:
  /// **'建立窄路由隧道；拒绝则无法启动'**
  String get permVpnExpressBody;

  /// No description provided for @permNeeded.
  ///
  /// In zh, this message translates to:
  /// **'需要这些权限'**
  String get permNeeded;

  /// No description provided for @permAllLocal.
  ///
  /// In zh, this message translates to:
  /// **'全部权限只在本机使用，不会上传任何数据。'**
  String get permAllLocal;

  /// No description provided for @permGrantedCount.
  ///
  /// In zh, this message translates to:
  /// **'已授予 {granted} / {total} 项；全部权限只在本机使用，不会上传任何数据。'**
  String permGrantedCount(String granted, String total);

  /// No description provided for @onboardingTipNormal1.
  ///
  /// In zh, this message translates to:
  /// **'点首页的大圆钮启动服务，第一次会弹出系统 VPN 授权。'**
  String get onboardingTipNormal1;

  /// No description provided for @onboardingTipNormal2.
  ///
  /// In zh, this message translates to:
  /// **'黑名单 / 白名单在「功能中心 → 规则与订阅」里维护。'**
  String get onboardingTipNormal2;

  /// No description provided for @onboardingTipNormal3.
  ///
  /// In zh, this message translates to:
  /// **'首页句子和透明度都能在设置里改。'**
  String get onboardingTipNormal3;

  /// No description provided for @onboardingTipServer1.
  ///
  /// In zh, this message translates to:
  /// **'启动后把同网段设备的 DNS 指向「局域网接入」里显示的地址。'**
  String get onboardingTipServer1;

  /// No description provided for @onboardingTipServer2.
  ///
  /// In zh, this message translates to:
  /// **'端口可在「服务器模式」页改，默认 5353。'**
  String get onboardingTipServer2;

  /// No description provided for @onboardingTipServer3.
  ///
  /// In zh, this message translates to:
  /// **'本模式不建立 VPN，可与其它 VPN 同时运行。'**
  String get onboardingTipServer3;

  /// No description provided for @onboardingTipExpress1.
  ///
  /// In zh, this message translates to:
  /// **'极速模式启动更快，但功能是普通模式的子集。'**
  String get onboardingTipExpress1;

  /// No description provided for @onboardingTipExpress2.
  ///
  /// In zh, this message translates to:
  /// **'多路竞速至少要选 2 家服务商。'**
  String get onboardingTipExpress2;

  /// No description provided for @onboardingTipExpress3.
  ///
  /// In zh, this message translates to:
  /// **'需要 HTTPS 检查或应用管控时请切回普通模式。'**
  String get onboardingTipExpress3;

  /// No description provided for @onboardingReady.
  ///
  /// In zh, this message translates to:
  /// **'可以开始了'**
  String get onboardingReady;

  /// No description provided for @onboardingReadyBody.
  ///
  /// In zh, this message translates to:
  /// **'下面是三条最常用的上手要点。'**
  String get onboardingReadyBody;

  /// No description provided for @onboardingTipIndex.
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 条'**
  String onboardingTipIndex(String index);

  /// No description provided for @permStillDenied.
  ///
  /// In zh, this message translates to:
  /// **'{name} 仍未授予，请在系统设置里允许后返回本页'**
  String permStillDenied(String name);

  /// No description provided for @permGranted.
  ///
  /// In zh, this message translates to:
  /// **'已授予'**
  String get permGranted;

  /// No description provided for @permDenied.
  ///
  /// In zh, this message translates to:
  /// **'未授予'**
  String get permDenied;

  /// No description provided for @permUnknown.
  ///
  /// In zh, this message translates to:
  /// **'状态未知'**
  String get permUnknown;

  /// No description provided for @permGrant.
  ///
  /// In zh, this message translates to:
  /// **'去授予'**
  String get permGrant;

  /// No description provided for @toolSpeedTest.
  ///
  /// In zh, this message translates to:
  /// **'测速'**
  String get toolSpeedTest;

  /// No description provided for @toolPing.
  ///
  /// In zh, this message translates to:
  /// **'Ping 测试'**
  String get toolPing;

  /// No description provided for @toolDnsLookup.
  ///
  /// In zh, this message translates to:
  /// **'DNS 解析'**
  String get toolDnsLookup;

  /// No description provided for @toolTraceroute.
  ///
  /// In zh, this message translates to:
  /// **'路由追踪'**
  String get toolTraceroute;

  /// No description provided for @toolDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'网络诊断'**
  String get toolDiagnostics;

  /// No description provided for @toolRefreshInfo.
  ///
  /// In zh, this message translates to:
  /// **'刷新网络信息'**
  String get toolRefreshInfo;

  /// No description provided for @toolActiveInterface.
  ///
  /// In zh, this message translates to:
  /// **'活动接口'**
  String get toolActiveInterface;

  /// No description provided for @toolLocalAddress.
  ///
  /// In zh, this message translates to:
  /// **'本机地址'**
  String get toolLocalAddress;

  /// No description provided for @toolDnsServers.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务器'**
  String get toolDnsServers;

  /// No description provided for @toolCountUnit.
  ///
  /// In zh, this message translates to:
  /// **'个'**
  String get toolCountUnit;

  /// No description provided for @toolPrivateDnsProbe.
  ///
  /// In zh, this message translates to:
  /// **'探测走物理网络（本应用流量不经过隧道）；系统私人 DNS：{dns}'**
  String toolPrivateDnsProbe(String dns);

  /// No description provided for @toolPhysicalProbe.
  ///
  /// In zh, this message translates to:
  /// **'探测走物理网络：本应用自身流量被排除在隧道外，下面四个工具测的都是物理链路的真实时延。'**
  String get toolPhysicalProbe;

  /// No description provided for @toolInputHostOrIp.
  ///
  /// In zh, this message translates to:
  /// **'输入 IP 或域名'**
  String get toolInputHostOrIp;

  /// No description provided for @toolPingCount4.
  ///
  /// In zh, this message translates to:
  /// **'4 次'**
  String get toolPingCount4;

  /// No description provided for @toolPingCount10.
  ///
  /// In zh, this message translates to:
  /// **'10 次'**
  String get toolPingCount10;

  /// No description provided for @toolPingOptions.
  ///
  /// In zh, this message translates to:
  /// **'探测选项'**
  String get toolPingOptions;

  /// No description provided for @toolViaTunnel.
  ///
  /// In zh, this message translates to:
  /// **'通过 Go 隧道解析'**
  String get toolViaTunnel;

  /// No description provided for @toolViaTunnelPingBody.
  ///
  /// In zh, this message translates to:
  /// **'域名经运行中的 Go 隧道解析（应用覆写与过滤规则），探测仍走物理网络'**
  String get toolViaTunnelPingBody;

  /// No description provided for @toolStartPing.
  ///
  /// In zh, this message translates to:
  /// **'开始 Ping'**
  String get toolStartPing;

  /// No description provided for @toolPinging.
  ///
  /// In zh, this message translates to:
  /// **'正在探测…'**
  String get toolPinging;

  /// No description provided for @toolTcpFallback.
  ///
  /// In zh, this message translates to:
  /// **'系统 ICMP 受限，已用 TCP 回退测量。此时的时延是连接建立耗时，不能与 ICMP 往返时延直接比较。'**
  String get toolTcpFallback;

  /// No description provided for @toolPingFailed.
  ///
  /// In zh, this message translates to:
  /// **'探测失败：未收到任何回复'**
  String get toolPingFailed;

  /// No description provided for @toolTarget.
  ///
  /// In zh, this message translates to:
  /// **'目标'**
  String get toolTarget;

  /// No description provided for @toolResolvedAddress.
  ///
  /// In zh, this message translates to:
  /// **'解析地址'**
  String get toolResolvedAddress;

  /// No description provided for @toolAddressFamily.
  ///
  /// In zh, this message translates to:
  /// **'地址族'**
  String get toolAddressFamily;

  /// No description provided for @toolSentReceived.
  ///
  /// In zh, this message translates to:
  /// **'发送 / 接收'**
  String get toolSentReceived;

  /// No description provided for @toolPacketLoss.
  ///
  /// In zh, this message translates to:
  /// **'丢包率'**
  String get toolPacketLoss;

  /// No description provided for @toolMinAvgMax.
  ///
  /// In zh, this message translates to:
  /// **'最小 / 平均 / 最大'**
  String get toolMinAvgMax;

  /// No description provided for @toolJitter.
  ///
  /// In zh, this message translates to:
  /// **'抖动'**
  String get toolJitter;

  /// No description provided for @toolJitterFooter.
  ///
  /// In zh, this message translates to:
  /// **'抖动按各包时延与均值的平均绝对偏差计算。'**
  String get toolJitterFooter;

  /// No description provided for @toolPacketN.
  ///
  /// In zh, this message translates to:
  /// **'第 {n} 个包'**
  String toolPacketN(String n);

  /// No description provided for @toolTimeout.
  ///
  /// In zh, this message translates to:
  /// **'超时'**
  String get toolTimeout;

  /// No description provided for @toolPingSummary.
  ///
  /// In zh, this message translates to:
  /// **'本次共发送 {sent} 个探测包，失败 {failed} 个。'**
  String toolPingSummary(String failed, String sent);

  /// No description provided for @toolPingFooter.
  ///
  /// In zh, this message translates to:
  /// **'Ping 由原生侧执行：优先调用系统 ping 二进制，不可用时回退到地址可达性与 TCP 端口握手计时，并会明确标注。'**
  String get toolPingFooter;

  /// No description provided for @toolDnsSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get toolDnsSystem;

  /// No description provided for @toolDnsCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get toolDnsCustom;

  /// No description provided for @toolCustomDnsError.
  ///
  /// In zh, this message translates to:
  /// **'请输入自定义 DNS 服务器 IP'**
  String get toolCustomDnsError;

  /// No description provided for @toolInputDomain.
  ///
  /// In zh, this message translates to:
  /// **'输入要解析的域名'**
  String get toolInputDomain;

  /// No description provided for @toolCustomDnsHint.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DNS 服务器 IP（如 1.1.1.1）'**
  String get toolCustomDnsHint;

  /// No description provided for @toolQueryOptions.
  ///
  /// In zh, this message translates to:
  /// **'查询选项'**
  String get toolQueryOptions;

  /// No description provided for @toolViaTunnelDnsBody.
  ///
  /// In zh, this message translates to:
  /// **'开启后由隧道引擎解析，会套用拦截规则与缓存；关闭时直接问系统解析器'**
  String get toolViaTunnelDnsBody;

  /// No description provided for @toolStartQuery.
  ///
  /// In zh, this message translates to:
  /// **'开始查询'**
  String get toolStartQuery;

  /// No description provided for @toolQuerying.
  ///
  /// In zh, this message translates to:
  /// **'查询中…'**
  String get toolQuerying;

  /// No description provided for @toolQueryDomain.
  ///
  /// In zh, this message translates to:
  /// **'查询域名'**
  String get toolQueryDomain;

  /// No description provided for @toolRecordType.
  ///
  /// In zh, this message translates to:
  /// **'记录类型'**
  String get toolRecordType;

  /// No description provided for @toolAnswerSource.
  ///
  /// In zh, this message translates to:
  /// **'答案来源'**
  String get toolAnswerSource;

  /// No description provided for @toolElapsed.
  ///
  /// In zh, this message translates to:
  /// **'耗时'**
  String get toolElapsed;

  /// No description provided for @toolAnswerCount.
  ///
  /// In zh, this message translates to:
  /// **'答案条数'**
  String get toolAnswerCount;

  /// No description provided for @toolDnsBlockedBody.
  ///
  /// In zh, this message translates to:
  /// **'该域名被隧道规则拦截，因此没有真实上游应答。'**
  String get toolDnsBlockedBody;

  /// No description provided for @toolDnsNoAnswers.
  ///
  /// In zh, this message translates to:
  /// **'没有返回任何应答记录。若来源是「被规则拦截」，说明该域名在本机规则里被拦掉了。'**
  String get toolDnsNoAnswers;

  /// No description provided for @toolDnsFooter.
  ///
  /// In zh, this message translates to:
  /// **'「走隧道查询」问的是本软件的解析链路（含规则与缓存），此时服务器由隧道决定；关闭后可选择跟随系统或指定一台 DNS 服务器，两者结果可能不同。'**
  String get toolDnsFooter;

  /// No description provided for @toolTunnelEngine.
  ///
  /// In zh, this message translates to:
  /// **'隧道引擎'**
  String get toolTunnelEngine;

  /// No description provided for @toolSpeedChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查测速通道…'**
  String get toolSpeedChecking;

  /// No description provided for @toolSpeedUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前设备不支持测速：本机没有提供 DNS 查询耗时测量的原生通道，页面不会显示任何模拟耗时。'**
  String get toolSpeedUnsupported;

  /// No description provided for @toolSpeedDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'用于测速的域名'**
  String get toolSpeedDomainHint;

  /// No description provided for @toolSpeedProviders.
  ///
  /// In zh, this message translates to:
  /// **'测速服务商'**
  String get toolSpeedProviders;

  /// No description provided for @toolNoProviders.
  ///
  /// In zh, this message translates to:
  /// **'暂无 {protocol} DNS 服务商'**
  String toolNoProviders(String protocol);

  /// No description provided for @toolNoProvidersBody.
  ///
  /// In zh, this message translates to:
  /// **'在「服务商管理」里添加后即可参与测速'**
  String get toolNoProvidersBody;

  /// No description provided for @toolSpeedSelectionNote.
  ///
  /// In zh, this message translates to:
  /// **'可选择 1 个或多个服务商；这里的选择只用于 DNS 查询测速，不影响竞速模式。'**
  String get toolSpeedSelectionNote;

  /// No description provided for @toolTestQueryTime.
  ///
  /// In zh, this message translates to:
  /// **'测试查询耗时'**
  String get toolTestQueryTime;

  /// No description provided for @toolSpeedRunning.
  ///
  /// In zh, this message translates to:
  /// **'测速中…'**
  String get toolSpeedRunning;

  /// No description provided for @toolSpeedEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未测速。选好服务商后点上面的按钮，本应用会直接向每个服务商发送 3 次真实 DNS 查询并记录往返耗时。'**
  String get toolSpeedEmpty;

  /// No description provided for @toolSpeedResults.
  ///
  /// In zh, this message translates to:
  /// **'查询耗时结果'**
  String get toolSpeedResults;

  /// No description provided for @toolSpeedResultsFooter.
  ///
  /// In zh, this message translates to:
  /// **'测速结果按成功优先、平均耗时从低到高排序；结果只反映本次查询时的网络状态。域名当前为「{domain}」。'**
  String toolSpeedResultsFooter(String domain);

  /// No description provided for @toolSpeedFooter.
  ///
  /// In zh, this message translates to:
  /// **'测速由原生侧执行：向每个服务商分别发送真实的 DoH / DoT / 明文 DNS 查询，只有拿到成功应答的样本才计入耗时。'**
  String get toolSpeedFooter;

  /// No description provided for @toolFastest.
  ///
  /// In zh, this message translates to:
  /// **'最快'**
  String get toolFastest;

  /// No description provided for @toolSampleCount.
  ///
  /// In zh, this message translates to:
  /// **'{rate} · 样本 {count}'**
  String toolSampleCount(String count, String rate);

  /// No description provided for @toolAllFailed.
  ///
  /// In zh, this message translates to:
  /// **'全部失败（{count} 次）'**
  String toolAllFailed(String count);

  /// No description provided for @toolTraceOptions.
  ///
  /// In zh, this message translates to:
  /// **'追踪选项'**
  String get toolTraceOptions;

  /// No description provided for @toolStartTrace.
  ///
  /// In zh, this message translates to:
  /// **'开始追踪'**
  String get toolStartTrace;

  /// No description provided for @toolTracing.
  ///
  /// In zh, this message translates to:
  /// **'追踪中…'**
  String get toolTracing;

  /// No description provided for @toolTraceFailed.
  ///
  /// In zh, this message translates to:
  /// **'追踪失败：未收到任何回应'**
  String get toolTraceFailed;

  /// No description provided for @toolTraceCancelled.
  ///
  /// In zh, this message translates to:
  /// **'追踪已取消。'**
  String get toolTraceCancelled;

  /// No description provided for @toolHopCount.
  ///
  /// In zh, this message translates to:
  /// **'跳数'**
  String get toolHopCount;

  /// No description provided for @toolHopCountValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} / 最多 {max}'**
  String toolHopCountValue(String count, String max);

  /// No description provided for @toolNoResponse.
  ///
  /// In zh, this message translates to:
  /// **'无响应'**
  String get toolNoResponse;

  /// No description provided for @toolTraceFooter.
  ///
  /// In zh, this message translates to:
  /// **'星号表示该跳在超时时间内没有回包——不代表链路断了，很多路由器不响应探测包。绿色一行表示已到达目标。'**
  String get toolTraceFooter;

  /// No description provided for @toolTraceHops15.
  ///
  /// In zh, this message translates to:
  /// **'15 跳'**
  String get toolTraceHops15;

  /// No description provided for @toolTraceHops30.
  ///
  /// In zh, this message translates to:
  /// **'30 跳'**
  String get toolTraceHops30;

  /// No description provided for @uaDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除 User-Agent'**
  String get uaDeleteTitle;

  /// No description provided for @uaDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除这一条吗？只删候选，不影响当前已选中的 UA。'**
  String get uaDeleteBody;

  /// No description provided for @uaAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加 User-Agent'**
  String get uaAdd;

  /// No description provided for @uaEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑 User-Agent'**
  String get uaEdit;

  /// No description provided for @uaNote.
  ///
  /// In zh, this message translates to:
  /// **'UA 会随订阅下载、规则集拉取与订阅测速请求一起发送；部分服务端按 UA 拒绝请求，改这里可以绕过。'**
  String get uaNote;

  /// No description provided for @uaCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前选择'**
  String get uaCurrent;

  /// No description provided for @uaNoOverride.
  ///
  /// In zh, this message translates to:
  /// **'不覆写'**
  String get uaNoOverride;

  /// No description provided for @uaNoOverrideBody.
  ///
  /// In zh, this message translates to:
  /// **'沿用订阅或内核自带的 UA'**
  String get uaNoOverrideBody;

  /// No description provided for @uaBuiltin.
  ///
  /// In zh, this message translates to:
  /// **'内置'**
  String get uaBuiltin;

  /// No description provided for @uaCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get uaCustom;

  /// No description provided for @uaBuiltinNote.
  ///
  /// In zh, this message translates to:
  /// **'内置 UA 不可删除：删掉之后内核回落到默认值，用户会误以为「设置没生效」。'**
  String get uaBuiltinNote;

  /// No description provided for @uaHint.
  ///
  /// In zh, this message translates to:
  /// **'如：clash-verge/v2.0.0'**
  String get uaHint;

  /// No description provided for @uaEmptyError.
  ///
  /// In zh, this message translates to:
  /// **'UA 不能为空'**
  String get uaEmptyError;

  /// No description provided for @uaDuplicateError.
  ///
  /// In zh, this message translates to:
  /// **'该 UA 已存在'**
  String get uaDuplicateError;

  /// No description provided for @ssidInvalid.
  ///
  /// In zh, this message translates to:
  /// **'SSID 不能为空或已存在'**
  String get ssidInvalid;

  /// No description provided for @ssidAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加 SSID'**
  String get ssidAdd;

  /// No description provided for @ssidEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑 SSID'**
  String get ssidEdit;

  /// No description provided for @ssidSave.
  ///
  /// In zh, this message translates to:
  /// **'保存 SSID'**
  String get ssidSave;

  /// No description provided for @ssidHint.
  ///
  /// In zh, this message translates to:
  /// **'区分大小写，与系统 Wi-Fi 列表里的名字完全一致'**
  String get ssidHint;

  /// No description provided for @ssidExample.
  ///
  /// In zh, this message translates to:
  /// **'如：Home-5G'**
  String get ssidExample;

  /// No description provided for @ssidEmptyError.
  ///
  /// In zh, this message translates to:
  /// **'SSID 不能为空'**
  String get ssidEmptyError;

  /// No description provided for @ssidConnection.
  ///
  /// In zh, this message translates to:
  /// **'连接方式'**
  String get ssidConnection;

  /// No description provided for @ssidCellular.
  ///
  /// In zh, this message translates to:
  /// **'蜂窝网络'**
  String get ssidCellular;

  /// No description provided for @ssidCellularBody.
  ///
  /// In zh, this message translates to:
  /// **'在该网络下也启动 VPN'**
  String get ssidCellularBody;

  /// No description provided for @ssidWifiBody.
  ///
  /// In zh, this message translates to:
  /// **'连上该 SSID 时启动 VPN'**
  String get ssidWifiBody;

  /// No description provided for @ssidBothOff.
  ///
  /// In zh, this message translates to:
  /// **'两种都关掉，等于把这条 SSID 从白名单里排除（VPN 不会启动）。'**
  String get ssidBothOff;

  /// No description provided for @ssidDelay.
  ///
  /// In zh, this message translates to:
  /// **'延迟'**
  String get ssidDelay;

  /// No description provided for @ssidStartDelay.
  ///
  /// In zh, this message translates to:
  /// **'启动延迟'**
  String get ssidStartDelay;

  /// No description provided for @ssidStartDelayBody.
  ///
  /// In zh, this message translates to:
  /// **'等待网络就绪后再启动 VPN'**
  String get ssidStartDelayBody;

  /// No description provided for @ssidImmediate.
  ///
  /// In zh, this message translates to:
  /// **'立即连接'**
  String get ssidImmediate;

  /// No description provided for @odTitle.
  ///
  /// In zh, this message translates to:
  /// **'按需连接'**
  String get odTitle;

  /// No description provided for @odApplyNow.
  ///
  /// In zh, this message translates to:
  /// **'立即应用'**
  String get odApplyNow;

  /// No description provided for @odEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用按需连接'**
  String get odEnable;

  /// No description provided for @odEnableBody.
  ///
  /// In zh, this message translates to:
  /// **'连上白名单里的 SSID 时自动启动 VPN'**
  String get odEnableBody;

  /// No description provided for @odDisableBody.
  ///
  /// In zh, this message translates to:
  /// **'关闭时 VPN 始终在线，不随网络切换'**
  String get odDisableBody;

  /// No description provided for @odNote.
  ///
  /// In zh, this message translates to:
  /// **'开启后，只有连上白名单里的 SSID 时才会自动启动 VPN；其余网络保持断开，省电也更可控。自动判定只在网络变化时启停 VPN，不会覆盖手动开关的结果；点右上角「立即应用」可立即按当前网络重新判定。'**
  String get odNote;

  /// No description provided for @odAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'SSID 白名单'**
  String get odAllowlist;

  /// No description provided for @odNoSsid.
  ///
  /// In zh, this message translates to:
  /// **'还没有 SSID'**
  String get odNoSsid;

  /// No description provided for @odNoSsidBody.
  ///
  /// In zh, this message translates to:
  /// **'没有白名单时按需连接不会触发'**
  String get odNoSsidBody;

  /// No description provided for @odDelayNote.
  ///
  /// In zh, this message translates to:
  /// **'延迟用于等 Wi-Fi 完成认证与 DHCP；过早启动 VPN 会让首个请求落到尚未就绪的网络上。'**
  String get odDelayNote;

  /// No description provided for @odCellular.
  ///
  /// In zh, this message translates to:
  /// **'蜂窝'**
  String get odCellular;

  /// No description provided for @odKindsNone.
  ///
  /// In zh, this message translates to:
  /// **'不启用'**
  String get odKindsNone;

  /// No description provided for @odDelayValue.
  ///
  /// In zh, this message translates to:
  /// **'延迟 {ms} ms'**
  String odDelayValue(String ms);

  /// No description provided for @odStateDisabled.
  ///
  /// In zh, this message translates to:
  /// **'按需连接已关闭'**
  String get odStateDisabled;

  /// No description provided for @odStateUnknown.
  ///
  /// In zh, this message translates to:
  /// **'无法读取当前 Wi-Fi，白名单不会触发'**
  String get odStateUnknown;

  /// No description provided for @odStateNoWifi.
  ///
  /// In zh, this message translates to:
  /// **'当前不在 Wi-Fi 上，VPN 保持断开'**
  String get odStateNoWifi;

  /// No description provided for @odStateMatched.
  ///
  /// In zh, this message translates to:
  /// **'已匹配 {ssid}，VPN 会自动启动'**
  String odStateMatched(String ssid);

  /// No description provided for @odStateUnmatched.
  ///
  /// In zh, this message translates to:
  /// **'当前 Wi-Fi 不在白名单，VPN 保持断开'**
  String get odStateUnmatched;

  /// No description provided for @odDisabledHint.
  ///
  /// In zh, this message translates to:
  /// **'按需连接已关闭，VPN 不再随网络切换'**
  String get odDisabledHint;

  /// No description provided for @odPillDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get odPillDisabled;

  /// No description provided for @odPillUnknown.
  ///
  /// In zh, this message translates to:
  /// **'无法判断'**
  String get odPillUnknown;

  /// No description provided for @odPillNoWifi.
  ///
  /// In zh, this message translates to:
  /// **'未连接 Wi-Fi'**
  String get odPillNoWifi;

  /// No description provided for @odPillWillStart.
  ///
  /// In zh, this message translates to:
  /// **'会启动 VPN'**
  String get odPillWillStart;

  /// No description provided for @odPillWillNotStart.
  ///
  /// In zh, this message translates to:
  /// **'不会启动 VPN'**
  String get odPillWillNotStart;

  /// No description provided for @odDecision.
  ///
  /// In zh, this message translates to:
  /// **'当前判定'**
  String get odDecision;

  /// No description provided for @odDecisionFooter.
  ///
  /// In zh, this message translates to:
  /// **'判定按当前网络实时计算：切换 Wi-Fi 后重新读取即可看到结果。SSID 区分大小写。'**
  String get odDecisionFooter;

  /// No description provided for @odCurrentNetwork.
  ///
  /// In zh, this message translates to:
  /// **'当前网络'**
  String get odCurrentNetwork;

  /// No description provided for @odWifiName.
  ///
  /// In zh, this message translates to:
  /// **'Wi-Fi 名称'**
  String get odWifiName;

  /// No description provided for @odReadAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新读取'**
  String get odReadAgain;

  /// No description provided for @odPermission.
  ///
  /// In zh, this message translates to:
  /// **'读取权限'**
  String get odPermission;

  /// No description provided for @odPermissionBody.
  ///
  /// In zh, this message translates to:
  /// **'Android 10 起读取 Wi-Fi 名称需要位置权限'**
  String get odPermissionBody;

  /// No description provided for @odNotGranted.
  ///
  /// In zh, this message translates to:
  /// **'未授权'**
  String get odNotGranted;

  /// No description provided for @odWifiUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'本机当前无法读取 Wi-Fi 名称：请在系统设置里授予本应用位置权限后重新读取。'**
  String get odWifiUnreadable;

  /// No description provided for @odSsidPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'SSID 只用于匹配白名单，不会被上传；手动添加的 SSID 在无法读取时仍然可用。'**
  String get odSsidPrivacy;

  /// No description provided for @odBatteryJoined.
  ///
  /// In zh, this message translates to:
  /// **'已加入'**
  String get odBatteryJoined;

  /// No description provided for @odBatteryNotJoined.
  ///
  /// In zh, this message translates to:
  /// **'未加入'**
  String get odBatteryNotJoined;

  /// No description provided for @odBatteryUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'不可用'**
  String get odBatteryUnavailable;

  /// No description provided for @odPrerequisites.
  ///
  /// In zh, this message translates to:
  /// **'前置条件'**
  String get odPrerequisites;

  /// No description provided for @odIgnoreBattery.
  ///
  /// In zh, this message translates to:
  /// **'忽略电池优化'**
  String get odIgnoreBattery;

  /// No description provided for @odBatteryOk.
  ///
  /// In zh, this message translates to:
  /// **'系统不会在后台冻结 VPN 进程'**
  String get odBatteryOk;

  /// No description provided for @odBatteryAsk.
  ///
  /// In zh, this message translates to:
  /// **'未加入时后台 VPN 可能被系统冻结，点击申请'**
  String get odBatteryAsk;

  /// No description provided for @odBatteryNoChannel.
  ///
  /// In zh, this message translates to:
  /// **'当前构建没有提供电池优化通道'**
  String get odBatteryNoChannel;

  /// No description provided for @odBatteryFooter.
  ///
  /// In zh, this message translates to:
  /// **'点击「未加入」会打开系统授权页；返回后会重新读取真实状态，取消则保持未加入。'**
  String get odBatteryFooter;

  /// No description provided for @odBatteryJoinedHint.
  ///
  /// In zh, this message translates to:
  /// **'已加入电池优化白名单'**
  String get odBatteryJoinedHint;

  /// No description provided for @odBatteryStillOff.
  ///
  /// In zh, this message translates to:
  /// **'仍未加入，VPN 可能被系统冻结'**
  String get odBatteryStillOff;

  /// No description provided for @odBatteryUnsupportedHint.
  ///
  /// In zh, this message translates to:
  /// **'当前构建不支持该授权'**
  String get odBatteryUnsupportedHint;

  /// No description provided for @odCapNoPermission.
  ///
  /// In zh, this message translates to:
  /// **'无法读取：需要位置权限'**
  String get odCapNoPermission;

  /// No description provided for @odCapCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前连接：{name}'**
  String odCapCurrent(String name);

  /// No description provided for @customResourcesTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义资源'**
  String get customResourcesTitle;

  /// No description provided for @customResourcesNote.
  ///
  /// In zh, this message translates to:
  /// **'这些资源按名字被引用：改名字等于断开引用，改内容则在下一次加载配置时生效。它们不属于旧版 1.4.3 的界面，保留在此供调试使用。'**
  String get customResourcesNote;

  /// No description provided for @customResourcesSection.
  ///
  /// In zh, this message translates to:
  /// **'资源'**
  String get customResourcesSection;

  /// No description provided for @configDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get configDelete;

  /// No description provided for @configCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get configCancel;

  /// No description provided for @configNotSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get configNotSet;

  /// No description provided for @configItemCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 项'**
  String configItemCount(int count);

  /// No description provided for @odEditSsidTooltip.
  ///
  /// In zh, this message translates to:
  /// **'编辑 {ssid}'**
  String odEditSsidTooltip(String ssid);

  /// No description provided for @odDeleteSsidTooltip.
  ///
  /// In zh, this message translates to:
  /// **'删除 {ssid}'**
  String odDeleteSsidTooltip(String ssid);

  /// No description provided for @serverSwitched.
  ///
  /// In zh, this message translates to:
  /// **'已切换到 {name}，重启服务后生效'**
  String serverSwitched(String name);

  /// No description provided for @serverSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {name}'**
  String serverSelected(String name);

  /// No description provided for @serverAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加 {name}'**
  String serverAdded(String name);

  /// No description provided for @serverSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {name}'**
  String serverSaved(String name);

  /// No description provided for @serverDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除 {name}？'**
  String serverDeleteConfirm(String name);

  /// No description provided for @serverDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'如果它正被使用，删除后会回落到第一个内置服务商。'**
  String get serverDeleteBody;

  /// No description provided for @serverDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {name}'**
  String serverDeleted(String name);

  /// No description provided for @serverUpstreamTitle.
  ///
  /// In zh, this message translates to:
  /// **'上游服务器'**
  String get serverUpstreamTitle;

  /// No description provided for @serverAddCustom.
  ///
  /// In zh, this message translates to:
  /// **'添加自定义服务商'**
  String get serverAddCustom;

  /// No description provided for @serverCurrentUpstream.
  ///
  /// In zh, this message translates to:
  /// **'当前用于解析 DNS：({protocol}) {name}'**
  String serverCurrentUpstream(String name, String protocol);

  /// No description provided for @serverBuiltinProviders.
  ///
  /// In zh, this message translates to:
  /// **'内置 DNS 服务商'**
  String get serverBuiltinProviders;

  /// No description provided for @serverNoBuiltin.
  ///
  /// In zh, this message translates to:
  /// **'暂无内置服务商'**
  String get serverNoBuiltin;

  /// No description provided for @serverCustomProviders.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DNS 服务商'**
  String get serverCustomProviders;

  /// No description provided for @serverNoCustom.
  ///
  /// In zh, this message translates to:
  /// **'暂无自定义服务商'**
  String get serverNoCustom;

  /// No description provided for @serverNoCustomBody.
  ///
  /// In zh, this message translates to:
  /// **'点右上角加号添加 DoH / DoT / 明文 DNS 上游'**
  String get serverNoCustomBody;

  /// No description provided for @serverUpstreamFooter.
  ///
  /// In zh, this message translates to:
  /// **'服务器模式支持单服务商与智能选择 / 并行竞速 / 主备切换，解析模式与候选上游在上方切换；需重启服务生效。内置服务商由应用维护，只能切换；自定义项可通过右侧菜单编辑或删除。'**
  String get serverUpstreamFooter;

  /// No description provided for @serverEditName.
  ///
  /// In zh, this message translates to:
  /// **'编辑 {name}'**
  String serverEditName(String name);

  /// No description provided for @serverDeleteName.
  ///
  /// In zh, this message translates to:
  /// **'删除 {name}'**
  String serverDeleteName(String name);

  /// No description provided for @serverEditCustom.
  ///
  /// In zh, this message translates to:
  /// **'编辑自定义服务商'**
  String get serverEditCustom;

  /// No description provided for @serverSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get serverSave;

  /// No description provided for @serverName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get serverName;

  /// No description provided for @serverDohAddress.
  ///
  /// In zh, this message translates to:
  /// **'DoH 地址'**
  String get serverDohAddress;

  /// No description provided for @serverAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverAddress;

  /// No description provided for @serverDohPrefix.
  ///
  /// In zh, this message translates to:
  /// **'必须以 https:// 开头'**
  String get serverDohPrefix;

  /// No description provided for @serverAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'IPv4 / IPv6 均可；IPv6 可直接填 [::1]'**
  String get serverAddressHint;

  /// No description provided for @serverPort.
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get serverPort;

  /// No description provided for @serverPortHint.
  ///
  /// In zh, this message translates to:
  /// **'DNS 通常 53，DoT 通常 853'**
  String get serverPortHint;

  /// No description provided for @serverUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前设备不可用'**
  String get serverUnavailable;

  /// No description provided for @serverBatteryJoined.
  ///
  /// In zh, this message translates to:
  /// **'已加入电池优化白名单'**
  String get serverBatteryJoined;

  /// No description provided for @serverBatteryNotJoined.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入电池优化白名单'**
  String get serverBatteryNotJoined;

  /// No description provided for @serverClearCache.
  ///
  /// In zh, this message translates to:
  /// **'清空缓存'**
  String get serverClearCache;

  /// No description provided for @serverClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get serverClear;

  /// No description provided for @serverClearCacheBody.
  ///
  /// In zh, this message translates to:
  /// **'将清空本机已缓存的解析结果，下一次查询会重新向上游请求。'**
  String get serverClearCacheBody;

  /// No description provided for @serverCacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'缓存已清空'**
  String get serverCacheCleared;

  /// No description provided for @serverCacheClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清空失败：请先启动解析服务再试'**
  String get serverCacheClearFailed;

  /// No description provided for @serverCacheOn.
  ///
  /// In zh, this message translates to:
  /// **'{preset} · 命中缓存的查询不再请求上游'**
  String serverCacheOn(String preset);

  /// No description provided for @serverCacheOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭 · 每次解析都请求上游 DNS'**
  String get serverCacheOff;

  /// No description provided for @serverModeSettings.
  ///
  /// In zh, this message translates to:
  /// **'模式设置'**
  String get serverModeSettings;

  /// No description provided for @serverProxySettings.
  ///
  /// In zh, this message translates to:
  /// **'代理与解析设置'**
  String get serverProxySettings;

  /// No description provided for @serverCacheSettings.
  ///
  /// In zh, this message translates to:
  /// **'缓存设置'**
  String get serverCacheSettings;

  /// No description provided for @serverRuleControl.
  ///
  /// In zh, this message translates to:
  /// **'规则控制'**
  String get serverRuleControl;

  /// No description provided for @serverRuleControlOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启 · 命中规则按拦截策略返回'**
  String get serverRuleControlOn;

  /// No description provided for @serverRuleControlOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭 · 不执行域名规则过滤'**
  String get serverRuleControlOff;

  /// No description provided for @serverRuleMasterSaved.
  ///
  /// In zh, this message translates to:
  /// **'规则开关已保存，重启 DNS 服务后生效'**
  String get serverRuleMasterSaved;

  /// No description provided for @serverListenPort.
  ///
  /// In zh, this message translates to:
  /// **'本地监听端口'**
  String get serverListenPort;

  /// No description provided for @serverListenPortBody.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务在本机监听的端口，默认 1053'**
  String get serverListenPortBody;

  /// No description provided for @serverRuleManagement.
  ///
  /// In zh, this message translates to:
  /// **'规则管理'**
  String get serverRuleManagement;

  /// No description provided for @serverBlocklist.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get serverBlocklist;

  /// No description provided for @serverBlocklistBody.
  ///
  /// In zh, this message translates to:
  /// **'管理域名屏蔽规则，独立规则库'**
  String get serverBlocklistBody;

  /// No description provided for @serverAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'白名单'**
  String get serverAllowlist;

  /// No description provided for @serverAllowlistBody.
  ///
  /// In zh, this message translates to:
  /// **'管理域名放行规则，独立规则库'**
  String get serverAllowlistBody;

  /// No description provided for @serverHosts.
  ///
  /// In zh, this message translates to:
  /// **'Hosts 覆写'**
  String get serverHosts;

  /// No description provided for @serverHostsBody.
  ///
  /// In zh, this message translates to:
  /// **'将指定域名解析到配置的 IP 或 CNAME'**
  String get serverHostsBody;

  /// No description provided for @serverRulesFooter.
  ///
  /// In zh, this message translates to:
  /// **'这三张表只影响服务器模式的独立规则库，与普通模式的规则互不覆盖。'**
  String get serverRulesFooter;

  /// No description provided for @serverDataReset.
  ///
  /// In zh, this message translates to:
  /// **'数据与重置'**
  String get serverDataReset;

  /// No description provided for @serverResetStats.
  ///
  /// In zh, this message translates to:
  /// **'重置运行统计'**
  String get serverResetStats;

  /// No description provided for @serverResetStatsBody.
  ///
  /// In zh, this message translates to:
  /// **'清空本次运行的统计数据'**
  String get serverResetStatsBody;

  /// No description provided for @serverBackground.
  ///
  /// In zh, this message translates to:
  /// **'后台稳定性'**
  String get serverBackground;

  /// No description provided for @serverBackgroundBody.
  ///
  /// In zh, this message translates to:
  /// **'系统会在后台冻结省电名单之外的应用；把它加入白名单，DNS 服务才能在息屏后继续应答局域网查询。'**
  String get serverBackgroundBody;

  /// No description provided for @serverRunMode.
  ///
  /// In zh, this message translates to:
  /// **'运行模式'**
  String get serverRunMode;

  /// No description provided for @serverWizard.
  ///
  /// In zh, this message translates to:
  /// **'使用向导'**
  String get serverWizard;

  /// No description provided for @serverWizardBody.
  ///
  /// In zh, this message translates to:
  /// **'查看服务器模式架构原理、局域网配置与就绪指引'**
  String get serverWizardBody;

  /// No description provided for @serverReselectMode.
  ///
  /// In zh, this message translates to:
  /// **'重新选择工作模式'**
  String get serverReselectMode;

  /// No description provided for @serverReselectModeBody.
  ///
  /// In zh, this message translates to:
  /// **'浏览所有工作模式详情并重新选择'**
  String get serverReselectModeBody;

  /// No description provided for @serverBatteryIgnored.
  ///
  /// In zh, this message translates to:
  /// **'已忽略电池优化'**
  String get serverBatteryIgnored;

  /// No description provided for @serverBatteryIgnoredShort.
  ///
  /// In zh, this message translates to:
  /// **'已忽略'**
  String get serverBatteryIgnoredShort;

  /// No description provided for @serverBatteryKeepAlive.
  ///
  /// In zh, this message translates to:
  /// **'保持 DNS 服务在后台稳定运行'**
  String get serverBatteryKeepAlive;

  /// No description provided for @serverIgnoreBattery.
  ///
  /// In zh, this message translates to:
  /// **'忽略电池优化'**
  String get serverIgnoreBattery;

  /// No description provided for @serverCachePresetConservative.
  ///
  /// In zh, this message translates to:
  /// **'保守'**
  String get serverCachePresetConservative;

  /// No description provided for @serverCachePresetHighHit.
  ///
  /// In zh, this message translates to:
  /// **'高命中'**
  String get serverCachePresetHighHit;

  /// No description provided for @serverCachePresetStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get serverCachePresetStandard;

  /// No description provided for @serverNavOverview.
  ///
  /// In zh, this message translates to:
  /// **'概览'**
  String get serverNavOverview;

  /// No description provided for @serverPortInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入数字'**
  String get serverPortInvalid;

  /// No description provided for @serverPortRange.
  ///
  /// In zh, this message translates to:
  /// **'范围 {min}–{max}'**
  String serverPortRange(String max, String min);

  /// No description provided for @serverPortChanged.
  ///
  /// In zh, this message translates to:
  /// **'端口已改为 {port}，重启服务后生效'**
  String serverPortChanged(String port);

  /// No description provided for @serverResetConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认重置'**
  String get serverResetConfirm;

  /// No description provided for @serverResetStatsConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'将清空本次运行的全部统计数据，确认继续吗？'**
  String get serverResetStatsConfirmBody;

  /// No description provided for @serverStatsReset.
  ///
  /// In zh, this message translates to:
  /// **'运行统计已重置'**
  String get serverStatsReset;

  /// No description provided for @serverOverviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'谛听 · 服务器模式'**
  String get serverOverviewTitle;

  /// No description provided for @serverSwitchMode.
  ///
  /// In zh, this message translates to:
  /// **'切换工作模式'**
  String get serverSwitchMode;

  /// No description provided for @serverChangePort.
  ///
  /// In zh, this message translates to:
  /// **'修改监听端口'**
  String get serverChangePort;

  /// No description provided for @serverCurrentUpstreamCard.
  ///
  /// In zh, this message translates to:
  /// **'当前上游'**
  String get serverCurrentUpstreamCard;

  /// No description provided for @serverLanAccess.
  ///
  /// In zh, this message translates to:
  /// **'局域网接入'**
  String get serverLanAccess;

  /// No description provided for @serverLanBody.
  ///
  /// In zh, this message translates to:
  /// **'把同网段设备的 DNS 指向上面这个地址即可；端口只在启动时绑定，改动后需要重启服务。'**
  String get serverLanBody;

  /// No description provided for @serverNoNetwork.
  ///
  /// In zh, this message translates to:
  /// **'未连接网络'**
  String get serverNoNetwork;

  /// No description provided for @serverLanConnectHint.
  ///
  /// In zh, this message translates to:
  /// **'连上 Wi-Fi 或以太网后这里会显示可用地址'**
  String get serverLanConnectHint;

  /// No description provided for @serverLanPointHint.
  ///
  /// In zh, this message translates to:
  /// **'将局域网其他设备的 DNS 指向此地址'**
  String get serverLanPointHint;

  /// No description provided for @serverCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制 {text}'**
  String serverCopied(String text);

  /// No description provided for @serverServiceStatus.
  ///
  /// In zh, this message translates to:
  /// **'服务状态'**
  String get serverServiceStatus;

  /// No description provided for @serverTotalQueries.
  ///
  /// In zh, this message translates to:
  /// **'总查询量'**
  String get serverTotalQueries;

  /// No description provided for @serverCacheHits.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中'**
  String get serverCacheHits;

  /// No description provided for @serverBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已拦截'**
  String get serverBlocked;

  /// No description provided for @serverAverageLatency.
  ///
  /// In zh, this message translates to:
  /// **'平均时延'**
  String get serverAverageLatency;

  /// No description provided for @serverUptime.
  ///
  /// In zh, this message translates to:
  /// **'运行时长'**
  String get serverUptime;

  /// No description provided for @serverStatsLastSevenDays.
  ///
  /// In zh, this message translates to:
  /// **'近 7 天累计'**
  String get serverStatsLastSevenDays;

  /// No description provided for @serverLogsTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务器日志仪表盘'**
  String get serverLogsTitle;

  /// No description provided for @serverLogsBody.
  ///
  /// In zh, this message translates to:
  /// **'查看局域网设备经服务器模式发起的 DNS 请求、拦截、缓存与上游竞速记录。服务器模式不建立 VPN 隧道，因此这里不含上下行流量与 HTTPS 检查数据。'**
  String get serverLogsBody;

  /// No description provided for @serverResetStatsBodyShort.
  ///
  /// In zh, this message translates to:
  /// **'清空本次运行的全部计数，不清规则与缓存'**
  String get serverResetStatsBodyShort;

  /// No description provided for @serverModeSettingsBody.
  ///
  /// In zh, this message translates to:
  /// **'监听端口、后台稳定性、数据重置与运行模式'**
  String get serverModeSettingsBody;

  /// No description provided for @serverModeNote.
  ///
  /// In zh, this message translates to:
  /// **'服务器模式不建立 VPN 隧道：它只在本机监听 DNS 端口，因此可以与其它 VPN 共存，也不占用系统的 VPN 槽位；本机应用的查询不会自动经过该服务。'**
  String get serverModeNote;

  /// No description provided for @serverBusyStarting.
  ///
  /// In zh, this message translates to:
  /// **'启动中'**
  String get serverBusyStarting;

  /// No description provided for @serverBusyStopping.
  ///
  /// In zh, this message translates to:
  /// **'停止中'**
  String get serverBusyStopping;

  /// No description provided for @serverRunning.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get serverRunning;

  /// No description provided for @serverStopped.
  ///
  /// In zh, this message translates to:
  /// **'开启'**
  String get serverStopped;

  /// No description provided for @serverListening.
  ///
  /// In zh, this message translates to:
  /// **'监听 0.0.0.0:{port}'**
  String serverListening(String port);

  /// No description provided for @serverStatusStopped.
  ///
  /// In zh, this message translates to:
  /// **'服务器模式已停止'**
  String get serverStatusStopped;

  /// No description provided for @serverStatusStarting.
  ///
  /// In zh, this message translates to:
  /// **'正在启动服务...'**
  String get serverStatusStarting;

  /// No description provided for @serverStatusRunning.
  ///
  /// In zh, this message translates to:
  /// **'服务器模式运行中'**
  String get serverStatusRunning;

  /// No description provided for @serverStatusStopping.
  ///
  /// In zh, this message translates to:
  /// **'正在停止服务...'**
  String get serverStatusStopping;

  /// No description provided for @serverStatusErrorText.
  ///
  /// In zh, this message translates to:
  /// **'服务启动异常'**
  String get serverStatusErrorText;

  /// No description provided for @troubleshootTitle.
  ///
  /// In zh, this message translates to:
  /// **'故障排查'**
  String get troubleshootTitle;

  /// No description provided for @troubleshootRuntimeLogs.
  ///
  /// In zh, this message translates to:
  /// **'运行日志'**
  String get troubleshootRuntimeLogs;

  /// No description provided for @troubleshootRecordLogs.
  ///
  /// In zh, this message translates to:
  /// **'记录运行日志'**
  String get troubleshootRecordLogs;

  /// No description provided for @troubleshootExportLogs.
  ///
  /// In zh, this message translates to:
  /// **'导出运行日志'**
  String get troubleshootExportLogs;

  /// No description provided for @troubleshootClearLogs.
  ///
  /// In zh, this message translates to:
  /// **'清空运行日志'**
  String get troubleshootClearLogs;

  /// No description provided for @troubleshootClearLogsBody.
  ///
  /// In zh, this message translates to:
  /// **'删除本地已记录的全部运行日志文件'**
  String get troubleshootClearLogsBody;

  /// No description provided for @troubleshootRecordNote.
  ///
  /// In zh, this message translates to:
  /// **'默认关闭。开启后会在通知栏显示状态，关闭软件或手动关闭后即停止记录；日志只保存在本机，不会自动上传。'**
  String get troubleshootRecordNote;

  /// No description provided for @troubleshootLocalDb.
  ///
  /// In zh, this message translates to:
  /// **'本地数据库'**
  String get troubleshootLocalDb;

  /// No description provided for @troubleshootWriteStatus.
  ///
  /// In zh, this message translates to:
  /// **'日志写入状态'**
  String get troubleshootWriteStatus;

  /// No description provided for @troubleshootWriteStatusNote.
  ///
  /// In zh, this message translates to:
  /// **'日志、竞速记录与流量统计由后台直接写入本地数据库。出现丢弃或打开失败时，多为数据库被长时间占用，点击可重新读取；反复出现请导出运行日志反馈。'**
  String get troubleshootWriteStatusNote;

  /// No description provided for @troubleshootCrashLogs.
  ///
  /// In zh, this message translates to:
  /// **'崩溃日志'**
  String get troubleshootCrashLogs;

  /// No description provided for @troubleshootExportCrashes.
  ///
  /// In zh, this message translates to:
  /// **'导出崩溃日志'**
  String get troubleshootExportCrashes;

  /// No description provided for @troubleshootClearCrashes.
  ///
  /// In zh, this message translates to:
  /// **'清空崩溃日志'**
  String get troubleshootClearCrashes;

  /// No description provided for @troubleshootClearCrashesBody.
  ///
  /// In zh, this message translates to:
  /// **'删除本地所有已记录的崩溃文件'**
  String get troubleshootClearCrashesBody;

  /// No description provided for @troubleshootCrashNote.
  ///
  /// In zh, this message translates to:
  /// **'发生未捕获异常时自动保存诊断信息与关键日志，仅保存在设备本地，导出后可反馈给开发者。'**
  String get troubleshootCrashNote;

  /// No description provided for @troubleshootCaptureWarning.
  ///
  /// In zh, this message translates to:
  /// **'抓取运行日志会持续读写少量文件，可能导致功耗升高、存储占用增加或产生其他未知影响，不需要时请及时关闭。导出的文件可发送给开发者，配合问题现象与发生时间能更快定位原因。'**
  String get troubleshootCaptureWarning;

  /// No description provided for @troubleshootReadingStatus.
  ///
  /// In zh, this message translates to:
  /// **'正在读取抓取状态…'**
  String get troubleshootReadingStatus;

  /// No description provided for @troubleshootRecording.
  ///
  /// In zh, this message translates to:
  /// **'正在记录，已占用 {size}，再次点击可关闭'**
  String troubleshootRecording(String size);

  /// No description provided for @troubleshootStoppedWithLogs.
  ///
  /// In zh, this message translates to:
  /// **'已关闭，本地已有 {size} 日志可导出'**
  String troubleshootStoppedWithLogs(String size);

  /// No description provided for @troubleshootStoppedNoLogs.
  ///
  /// In zh, this message translates to:
  /// **'已关闭，开启后才会记录运行日志'**
  String get troubleshootStoppedNoLogs;

  /// No description provided for @troubleshootReadingLogs.
  ///
  /// In zh, this message translates to:
  /// **'正在读取本地日志…'**
  String get troubleshootReadingLogs;

  /// No description provided for @troubleshootNoLogs.
  ///
  /// In zh, this message translates to:
  /// **'当前设备没有运行日志'**
  String get troubleshootNoLogs;

  /// No description provided for @troubleshootLogCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个文件，{size}，点击导出文件'**
  String troubleshootLogCount(int count, String size);

  /// No description provided for @troubleshootReadingHealth.
  ///
  /// In zh, this message translates to:
  /// **'正在读取写入状态…'**
  String get troubleshootReadingHealth;

  /// No description provided for @troubleshootHealthy.
  ///
  /// In zh, this message translates to:
  /// **'正常，没有日志被丢弃'**
  String get troubleshootHealthy;

  /// No description provided for @troubleshootHealthyDetail.
  ///
  /// In zh, this message translates to:
  /// **'正常，没有日志被丢弃（{mode} · {detail}）'**
  String troubleshootHealthyDetail(String detail, String mode);

  /// No description provided for @troubleshootDropped.
  ///
  /// In zh, this message translates to:
  /// **'已丢弃 {dropped} 条日志{split}，打开失败 {failed} 次{reason}'**
  String troubleshootDropped(
    int dropped,
    String failed,
    int reason,
    String split,
  );

  /// No description provided for @troubleshootOverflow.
  ///
  /// In zh, this message translates to:
  /// **'队列溢出'**
  String get troubleshootOverflow;

  /// No description provided for @troubleshootTableMissing.
  ///
  /// In zh, this message translates to:
  /// **'表缺失'**
  String get troubleshootTableMissing;

  /// No description provided for @troubleshootNoDatabase.
  ///
  /// In zh, this message translates to:
  /// **'无数据库'**
  String get troubleshootNoDatabase;

  /// No description provided for @troubleshootClosed.
  ///
  /// In zh, this message translates to:
  /// **'停止时未写完'**
  String get troubleshootClosed;

  /// No description provided for @troubleshootReadingCrashes.
  ///
  /// In zh, this message translates to:
  /// **'正在读取本机崩溃日志…'**
  String get troubleshootReadingCrashes;

  /// No description provided for @troubleshootNoCrashes.
  ///
  /// In zh, this message translates to:
  /// **'当前设备没有崩溃日志'**
  String get troubleshootNoCrashes;

  /// No description provided for @troubleshootCrashCount.
  ///
  /// In zh, this message translates to:
  /// **'已记录 {count} 份崩溃日志，点击导出文件'**
  String troubleshootCrashCount(int count);

  /// No description provided for @troubleshootStoppedToast.
  ///
  /// In zh, this message translates to:
  /// **'已停止记录运行日志'**
  String get troubleshootStoppedToast;

  /// No description provided for @troubleshootStartTitle.
  ///
  /// In zh, this message translates to:
  /// **'开启运行日志抓取'**
  String get troubleshootStartTitle;

  /// No description provided for @troubleshootCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get troubleshootCancel;

  /// No description provided for @troubleshootConfirmStart.
  ///
  /// In zh, this message translates to:
  /// **'确定开启'**
  String get troubleshootConfirmStart;

  /// No description provided for @troubleshootStartBody.
  ///
  /// In zh, this message translates to:
  /// **'该功能主要用于协助开发者排查问题，开启后会开始记录软件的运行日志，并持续写入本机存储。\n\n抓取期间可能导致功耗升高、存储占用增加，或产生其他未知影响。如非排查问题所需，建议用完即关。\n\n日志只保存在本机，关闭后停止记录；导出后你可以自行发送给开发者。'**
  String get troubleshootStartBody;

  /// No description provided for @troubleshootStartedToast.
  ///
  /// In zh, this message translates to:
  /// **'已开始记录运行日志'**
  String get troubleshootStartedToast;

  /// No description provided for @troubleshootStartFailedToast.
  ///
  /// In zh, this message translates to:
  /// **'无法开启日志抓取，请稍后重试'**
  String get troubleshootStartFailedToast;

  /// No description provided for @troubleshootNoExportableLogs.
  ///
  /// In zh, this message translates to:
  /// **'没有可导出的运行日志'**
  String get troubleshootNoExportableLogs;

  /// No description provided for @troubleshootExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：本机没有可写的导出目录'**
  String get troubleshootExportFailed;

  /// No description provided for @troubleshootExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出到 {path}'**
  String troubleshootExported(String path);

  /// No description provided for @troubleshootConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get troubleshootConfirm;

  /// No description provided for @troubleshootClearLogsConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认清空所有已保存的运行日志吗？该操作不可恢复。'**
  String get troubleshootClearLogsConfirm;

  /// No description provided for @troubleshootClearedLogs.
  ///
  /// In zh, this message translates to:
  /// **'已清空 {count} 个日志文件'**
  String troubleshootClearedLogs(String count);

  /// No description provided for @troubleshootNoClearableLogs.
  ///
  /// In zh, this message translates to:
  /// **'没有可清空的运行日志'**
  String get troubleshootNoClearableLogs;

  /// No description provided for @troubleshootNoExportableCrashes.
  ///
  /// In zh, this message translates to:
  /// **'没有可导出的崩溃日志'**
  String get troubleshootNoExportableCrashes;

  /// No description provided for @troubleshootClearCrashesConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认清空所有已保存的崩溃日志吗？'**
  String get troubleshootClearCrashesConfirm;

  /// No description provided for @troubleshootClearedCrashes.
  ///
  /// In zh, this message translates to:
  /// **'已清空 {count} 份崩溃日志'**
  String troubleshootClearedCrashes(String count);

  /// No description provided for @troubleshootNoClearableCrashes.
  ///
  /// In zh, this message translates to:
  /// **'没有可清空的崩溃日志'**
  String get troubleshootNoClearableCrashes;

  /// No description provided for @bypassAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加绕过域名'**
  String get bypassAddTitle;

  /// No description provided for @bypassAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get bypassAdd;

  /// No description provided for @bypassSuffix.
  ///
  /// In zh, this message translates to:
  /// **'域名后缀'**
  String get bypassSuffix;

  /// No description provided for @bypassSuffixBody.
  ///
  /// In zh, this message translates to:
  /// **'匹配该后缀及其子域名；不参与 HTTPS 解密'**
  String get bypassSuffixBody;

  /// No description provided for @mirrorGlobal.
  ///
  /// In zh, this message translates to:
  /// **'全局镜像'**
  String get mirrorGlobal;

  /// No description provided for @mirrorDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认使用镜像下载'**
  String get mirrorDefault;

  /// No description provided for @mirrorNeedTemplate.
  ///
  /// In zh, this message translates to:
  /// **'先添加一个模板后才能开启'**
  String get mirrorNeedTemplate;

  /// No description provided for @mirrorTemplateNote.
  ///
  /// In zh, this message translates to:
  /// **'订阅下载与软件更新都经由所选模板'**
  String get mirrorTemplateNote;

  /// No description provided for @mirrorTemplate.
  ///
  /// In zh, this message translates to:
  /// **'使用的模板'**
  String get mirrorTemplate;

  /// No description provided for @mirrorNote.
  ///
  /// In zh, this message translates to:
  /// **'开启后，未单独设置镜像的订阅、检查更新与下载安装包都会先请求镜像，镜像失败时自动改用原始地址。单独设置过镜像的订阅仍按自己的设置。'**
  String get mirrorNote;

  /// No description provided for @hiddenFeaturesTitle.
  ///
  /// In zh, this message translates to:
  /// **'隐藏功能'**
  String get hiddenFeaturesTitle;

  /// No description provided for @hiddenFeaturesReset.
  ///
  /// In zh, this message translates to:
  /// **'恢复全部显示'**
  String get hiddenFeaturesReset;

  /// No description provided for @hiddenFeaturesNote.
  ///
  /// In zh, this message translates to:
  /// **'自定义在功能中心显示的功能卡片。关闭开关将从功能中心隐藏该卡片，默认全部显示。隐藏仅调整界面展示，不会影响功能的后台运行与规则生效。设置会保存到本机，重启后仍然有效。'**
  String get hiddenFeaturesNote;

  /// No description provided for @hiddenFeaturesFooter.
  ///
  /// In zh, this message translates to:
  /// **'「隐藏功能」卡片固定常驻，确保随时可以在这里恢复。'**
  String get hiddenFeaturesFooter;

  /// No description provided for @cacheSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存设置'**
  String get cacheSettingsTitle;

  /// No description provided for @cacheSection.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get cacheSection;

  /// No description provided for @cacheLocalDns.
  ///
  /// In zh, this message translates to:
  /// **'本地 DNS 缓存'**
  String get cacheLocalDns;

  /// No description provided for @cacheOffNote.
  ///
  /// In zh, this message translates to:
  /// **'关闭后每次解析都会请求上游 DNS'**
  String get cacheOffNote;

  /// No description provided for @cachePresetSection.
  ///
  /// In zh, this message translates to:
  /// **'缓存档位'**
  String get cachePresetSection;

  /// No description provided for @cachePresetNote.
  ///
  /// In zh, this message translates to:
  /// **'建议使用「标准」。档位会自动设置最长 TTL、最短 TTL 和解析失败兜底时间，不再需要手动填写秒数。'**
  String get cachePresetNote;

  /// No description provided for @recognitionSponsorTitle.
  ///
  /// In zh, this message translates to:
  /// **'赞助者名单'**
  String get recognitionSponsorTitle;

  /// No description provided for @recognitionSponsorIntro.
  ///
  /// In zh, this message translates to:
  /// **'感谢每一位支持谛听项目的朋友！名单默认按赞助时间由早到晚排列，可通过右上角按钮切换为由晚到早；与赞助金额无关，每一份支持都同样珍贵。'**
  String get recognitionSponsorIntro;

  /// No description provided for @recognitionSponsorSection.
  ///
  /// In zh, this message translates to:
  /// **'赞助者'**
  String get recognitionSponsorSection;

  /// No description provided for @recognitionBuilderTitle.
  ///
  /// In zh, this message translates to:
  /// **'共建者名单'**
  String get recognitionBuilderTitle;

  /// No description provided for @recognitionBuilderIntro.
  ///
  /// In zh, this message translates to:
  /// **'感谢每一位为谛听提出建议、帮助测试的共建者！名单按用户名称的字母顺序排列，中文名称按拼音排序。'**
  String get recognitionBuilderIntro;

  /// No description provided for @recognitionBuilderSection.
  ///
  /// In zh, this message translates to:
  /// **'共建者'**
  String get recognitionBuilderSection;

  /// No description provided for @providerVisibilityTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务显示'**
  String get providerVisibilityTitle;

  /// No description provided for @providerVisibilityNote.
  ///
  /// In zh, this message translates to:
  /// **'关闭竞速模式时，首页解析服务下拉框仅显示这里选中的服务。当前正在使用的服务会始终保留。按住右侧手柄拖动可调整顺序，该顺序同时决定选择竞速服务商时的排列。'**
  String get providerVisibilityNote;

  /// No description provided for @providerVisibilityProtocol.
  ///
  /// In zh, this message translates to:
  /// **'{protocol} 服务'**
  String providerVisibilityProtocol(String protocol);

  /// No description provided for @providerVisibilityAll.
  ///
  /// In zh, this message translates to:
  /// **'全部 {protocol} 服务'**
  String providerVisibilityAll(String protocol);

  /// No description provided for @providerVisibilityNone.
  ///
  /// In zh, this message translates to:
  /// **'不显示该类型的服务'**
  String get providerVisibilityNone;

  /// No description provided for @providerVisibilityAllOn.
  ///
  /// In zh, this message translates to:
  /// **'显示该类型的全部服务'**
  String get providerVisibilityAllOn;

  /// No description provided for @providerVisibilityCount.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 个服务'**
  String providerVisibilityCount(String count);

  /// No description provided for @markdownCopyCode.
  ///
  /// In zh, this message translates to:
  /// **'复制代码'**
  String get markdownCopyCode;

  /// No description provided for @markdownCodeCopied.
  ///
  /// In zh, this message translates to:
  /// **'代码已复制到剪贴板'**
  String get markdownCodeCopied;

  /// No description provided for @recognitionUpdated.
  ///
  /// In zh, this message translates to:
  /// **'名单已更新'**
  String get recognitionUpdated;

  /// No description provided for @recognitionRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新名单'**
  String get recognitionRefresh;

  /// No description provided for @recognitionSortAsc.
  ///
  /// In zh, this message translates to:
  /// **'切换为由早到晚'**
  String get recognitionSortAsc;

  /// No description provided for @recognitionSortDesc.
  ///
  /// In zh, this message translates to:
  /// **'切换为由晚到早'**
  String get recognitionSortDesc;

  /// No description provided for @recognitionEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂时没有名单'**
  String get recognitionEmpty;

  /// No description provided for @recognitionLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'名单加载失败'**
  String get recognitionLoadFailed;

  /// No description provided for @recognitionEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'名单由云端下发，点这里拉取一次。'**
  String get recognitionEmptyBody;

  /// No description provided for @recognitionLoad.
  ///
  /// In zh, this message translates to:
  /// **'加载名单'**
  String get recognitionLoad;

  /// No description provided for @recognitionRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get recognitionRetry;

  /// No description provided for @recognitionNoMembers.
  ///
  /// In zh, this message translates to:
  /// **'暂时还没有成员'**
  String get recognitionNoMembers;

  /// No description provided for @recognitionNoMembersBody.
  ///
  /// In zh, this message translates to:
  /// **'名单会随云端配置更新，稍后再来看看。'**
  String get recognitionNoMembersBody;

  /// No description provided for @recognitionRefreshShort.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get recognitionRefreshShort;

  /// No description provided for @recognitionCached.
  ///
  /// In zh, this message translates to:
  /// **'正在显示本地缓存的名单'**
  String get recognitionCached;

  /// No description provided for @recognitionLastUpdate.
  ///
  /// In zh, this message translates to:
  /// **'上次更新：{time}'**
  String recognitionLastUpdate(String time);

  /// No description provided for @recognitionCloudNote.
  ///
  /// In zh, this message translates to:
  /// **'名单由云端下发，进入页面时自动检查更新'**
  String get recognitionCloudNote;

  /// No description provided for @appRulesAllowCount.
  ///
  /// In zh, this message translates to:
  /// **'{package} · {count} 个放行域名'**
  String appRulesAllowCount(String count, int package);

  /// No description provided for @appRulesConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置'**
  String get appRulesConfigured;

  /// No description provided for @appRulesSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get appRulesSystem;

  /// No description provided for @appRulesIncludeSub.
  ///
  /// In zh, this message translates to:
  /// **'包含子域名'**
  String get appRulesIncludeSub;

  /// No description provided for @appRulesDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get appRulesDelete;

  /// No description provided for @appRulesAddDomainTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加放行域名'**
  String get appRulesAddDomainTitle;

  /// No description provided for @appRulesCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get appRulesCancel;

  /// No description provided for @appRulesAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get appRulesAdd;

  /// No description provided for @appRulesDomain.
  ///
  /// In zh, this message translates to:
  /// **'域名'**
  String get appRulesDomain;

  /// No description provided for @appRulesDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'只填裸域名；包含子域名，不需要写通配符或 @@ 前缀'**
  String get appRulesDomainHint;

  /// No description provided for @appRulesAllowlistRow.
  ///
  /// In zh, this message translates to:
  /// **'白名单（放行）'**
  String get appRulesAllowlistRow;

  /// No description provided for @appRulesBlocklistRow.
  ///
  /// In zh, this message translates to:
  /// **'黑名单（拦截）'**
  String get appRulesBlocklistRow;

  /// No description provided for @appRulesImportant.
  ///
  /// In zh, this message translates to:
  /// **'重要'**
  String get appRulesImportant;

  /// No description provided for @appRulesDisable.
  ///
  /// In zh, this message translates to:
  /// **'停用'**
  String get appRulesDisable;

  /// No description provided for @appRulesEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get appRulesEnable;

  /// No description provided for @appRulesAddRuleTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加 DNS 规则'**
  String get appRulesAddRuleTitle;

  /// No description provided for @appRulesRuleDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'只填裸域名；仅对本应用生效'**
  String get appRulesRuleDomainHint;

  /// No description provided for @appRulesBlocklist.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get appRulesBlocklist;

  /// No description provided for @appRulesAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'白名单'**
  String get appRulesAllowlist;

  /// No description provided for @logRetentionTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志模式'**
  String get logRetentionTitle;

  /// No description provided for @logRetentionDnsLogs.
  ///
  /// In zh, this message translates to:
  /// **'DNS 请求日志'**
  String get logRetentionDnsLogs;

  /// No description provided for @logRetentionOffNote.
  ///
  /// In zh, this message translates to:
  /// **'关闭后不会删除已有日志，重新开启即可继续查看。'**
  String get logRetentionOffNote;

  /// No description provided for @logRetentionOverlay.
  ///
  /// In zh, this message translates to:
  /// **'悬浮窗'**
  String get logRetentionOverlay;

  /// No description provided for @logRetentionOverlayLogs.
  ///
  /// In zh, this message translates to:
  /// **'悬浮窗日志'**
  String get logRetentionOverlayLogs;

  /// No description provided for @logRetentionOverlayBody.
  ///
  /// In zh, this message translates to:
  /// **'VPN 运行且应用在后台时显示悬浮球，点按查看实时请求'**
  String get logRetentionOverlayBody;

  /// No description provided for @logRetentionOverlayNote.
  ///
  /// In zh, this message translates to:
  /// **'回到应用前台时悬浮窗会自动隐藏。仅普通模式可用。'**
  String get logRetentionOverlayNote;

  /// No description provided for @logRetentionCleanup.
  ///
  /// In zh, this message translates to:
  /// **'自动清理时间'**
  String get logRetentionCleanup;

  /// No description provided for @logRetentionKeepDays.
  ///
  /// In zh, this message translates to:
  /// **'保留 {days} 天'**
  String logRetentionKeepDays(String days);

  /// No description provided for @logRetentionCleanupNote.
  ///
  /// In zh, this message translates to:
  /// **'超过所选时间的请求日志由隧道服务每小时清理一次（首次在启动 30 秒后）。关闭日志不会删除已有记录。'**
  String get logRetentionCleanupNote;

  /// No description provided for @appBlockTitle.
  ///
  /// In zh, this message translates to:
  /// **'禁止联网应用'**
  String get appBlockTitle;

  /// No description provided for @appBlockInfo.
  ///
  /// In zh, this message translates to:
  /// **'通过本机 VPN 按 UID 阻止所选应用的全部网络连接。共享同一 UID 的应用会一并受影响。'**
  String get appBlockInfo;

  /// No description provided for @appBlockToggle.
  ///
  /// In zh, this message translates to:
  /// **'启用禁止联网'**
  String get appBlockToggle;

  /// No description provided for @appBlockToggleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未选择应用；开启后不会阻断流量'**
  String get appBlockToggleEmpty;

  /// No description provided for @appBlockSelection.
  ///
  /// In zh, this message translates to:
  /// **'禁止联网的应用'**
  String get appBlockSelection;

  /// No description provided for @appExcludeTitle.
  ///
  /// In zh, this message translates to:
  /// **'排除应用'**
  String get appExcludeTitle;

  /// No description provided for @appExcludeInfo.
  ///
  /// In zh, this message translates to:
  /// **'排除后，应用将使用系统 DNS，不参与本应用的过滤、缓存、日志和统计。'**
  String get appExcludeInfo;

  /// No description provided for @appExcludeSelection.
  ///
  /// In zh, this message translates to:
  /// **'排除的应用'**
  String get appExcludeSelection;

  /// No description provided for @appSelectionSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存，启动 DNS VPN 后生效'**
  String get appSelectionSaved;

  /// No description provided for @appSelectionSaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存更改？'**
  String get appSelectionSaveTitle;

  /// No description provided for @appSelectionSaveBody.
  ///
  /// In zh, this message translates to:
  /// **'「{title}」的选择还没保存。保存后离开，还是放弃这些修改？'**
  String appSelectionSaveBody(String title);

  /// No description provided for @appSelectionSwitch.
  ///
  /// In zh, this message translates to:
  /// **'开关'**
  String get appSelectionSwitch;

  /// No description provided for @appSelectionNoAppsYet.
  ///
  /// In zh, this message translates to:
  /// **'尚未选择应用'**
  String get appSelectionNoAppsYet;

  /// No description provided for @appSelectionCount.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 个应用'**
  String appSelectionCount(String count);

  /// No description provided for @appSelectionNoAppsAvailable.
  ///
  /// In zh, this message translates to:
  /// **'设备上没有可选的应用'**
  String get appSelectionNoAppsAvailable;

  /// No description provided for @appSelectionNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'未找到匹配应用'**
  String get appSelectionNoMatch;

  /// No description provided for @appSelectionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get appSelectionSave;

  /// No description provided for @appSelectionNothingRead.
  ///
  /// In zh, this message translates to:
  /// **'未读取到任何已安装应用；此处的勾选保存后不会命中任何应用。'**
  String get appSelectionNothingRead;

  /// No description provided for @appSelectionExclusiveNote.
  ///
  /// In zh, this message translates to:
  /// **'勾选会同时取消该应用在「排除应用」「禁止联网」「HTTPS 检查」与应用独立规则里的选择。'**
  String get appSelectionExclusiveNote;

  /// No description provided for @bootstrapTitle.
  ///
  /// In zh, this message translates to:
  /// **'引导解析设置'**
  String get bootstrapTitle;

  /// No description provided for @bootstrapAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增 Bootstrap IP'**
  String get bootstrapAdd;

  /// No description provided for @bootstrapGlobal.
  ///
  /// In zh, this message translates to:
  /// **'全局开关'**
  String get bootstrapGlobal;

  /// No description provided for @bootstrapEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用 Bootstrap IP'**
  String get bootstrapEnable;

  /// No description provided for @bootstrapEnableBody.
  ///
  /// In zh, this message translates to:
  /// **'使用独立递归 DNS 解析加密服务商域名，支持智能权重优选与自动回退'**
  String get bootstrapEnableBody;

  /// No description provided for @bootstrapEnableNote.
  ///
  /// In zh, this message translates to:
  /// **'开启后将通过加权算法动态优选 Bootstrap IP；关闭后将通过系统 DNS 解析加密上游域名。'**
  String get bootstrapEnableNote;

  /// No description provided for @bootstrapBuiltin.
  ///
  /// In zh, this message translates to:
  /// **'内置 Bootstrap IP'**
  String get bootstrapBuiltin;

  /// No description provided for @bootstrapCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义 Bootstrap IP'**
  String get bootstrapCustom;

  /// No description provided for @bootstrapNoCustom.
  ///
  /// In zh, this message translates to:
  /// **'暂无自定义 Bootstrap IP。点击右上角「新增」添加。'**
  String get bootstrapNoCustom;

  /// No description provided for @bootstrapNoSample.
  ///
  /// In zh, this message translates to:
  /// **'{ip} · 暂无样本'**
  String bootstrapNoSample(String ip);

  /// No description provided for @bootstrapAverage.
  ///
  /// In zh, this message translates to:
  /// **' · 平均 {ms}ms'**
  String bootstrapAverage(String ms);

  /// No description provided for @bootstrapFailures.
  ///
  /// In zh, this message translates to:
  /// **' · 失败 {count}'**
  String bootstrapFailures(String count);

  /// No description provided for @bootstrapStats.
  ///
  /// In zh, this message translates to:
  /// **'{ip}{latency} · 样本 {samples} · 成功 {success}%{failures}'**
  String bootstrapStats(
    String failures,
    String ip,
    String latency,
    String samples,
    String success,
  );

  /// No description provided for @bootstrapInvalidIp.
  ///
  /// In zh, this message translates to:
  /// **'请填写合法的 IPv4 或 IPv6 地址'**
  String get bootstrapInvalidIp;

  /// No description provided for @bootstrapNameOptional.
  ///
  /// In zh, this message translates to:
  /// **'名称（可选）'**
  String get bootstrapNameOptional;

  /// No description provided for @bootstrapIpAddress.
  ///
  /// In zh, this message translates to:
  /// **'IP 地址'**
  String get bootstrapIpAddress;

  /// No description provided for @caCertTitle.
  ///
  /// In zh, this message translates to:
  /// **'CA 证书设置'**
  String get caCertTitle;

  /// No description provided for @caCertStatusMissing.
  ///
  /// In zh, this message translates to:
  /// **'尚未生成：引擎还没有产出 ca.crt'**
  String get caCertStatusMissing;

  /// No description provided for @caCertStatusUntrusted.
  ///
  /// In zh, this message translates to:
  /// **'已生成，但未装进系统信任存储'**
  String get caCertStatusUntrusted;

  /// No description provided for @caCertStatusTrusted.
  ///
  /// In zh, this message translates to:
  /// **'已生成且已被系统信任'**
  String get caCertStatusTrusted;

  /// No description provided for @caCertSectionStatus.
  ///
  /// In zh, this message translates to:
  /// **'证书状态'**
  String get caCertSectionStatus;

  /// No description provided for @caCertRootStatus.
  ///
  /// In zh, this message translates to:
  /// **'根证书状态'**
  String get caCertRootStatus;

  /// No description provided for @caCertVerified.
  ///
  /// In zh, this message translates to:
  /// **'已验证'**
  String get caCertVerified;

  /// No description provided for @caCertUnverified.
  ///
  /// In zh, this message translates to:
  /// **'未验证'**
  String get caCertUnverified;

  /// No description provided for @caCertReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取失败'**
  String get caCertReadFailed;

  /// No description provided for @caCertStatusFooter.
  ///
  /// In zh, this message translates to:
  /// **'仅已验证的根证书支持流量检查；启用了证书绑定（SSL Pinning）的应用将自动旁路。'**
  String get caCertStatusFooter;

  /// No description provided for @caCertSectionActions.
  ///
  /// In zh, this message translates to:
  /// **'证书操作'**
  String get caCertSectionActions;

  /// No description provided for @caCertGuide.
  ///
  /// In zh, this message translates to:
  /// **'安装与卸载指南'**
  String get caCertGuide;

  /// No description provided for @caCertGuideSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看各机型系统证书的安装、移除及安全说明'**
  String get caCertGuideSubtitle;

  /// No description provided for @caCertInstall.
  ///
  /// In zh, this message translates to:
  /// **'安装根证书'**
  String get caCertInstall;

  /// No description provided for @caCertInstallSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'交给系统安装器；Android 11 起还需在设置里手动确认'**
  String get caCertInstallSubtitle;

  /// No description provided for @caCertInstalled.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get caCertInstalled;

  /// No description provided for @caCertNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'未安装'**
  String get caCertNotInstalled;

  /// No description provided for @caCertSaveToDownloads.
  ///
  /// In zh, this message translates to:
  /// **'保存证书到下载目录'**
  String get caCertSaveToDownloads;

  /// No description provided for @caCertSaveToDownloadsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'下载目录里的 .crt 可在系统设置里手动安装'**
  String get caCertSaveToDownloadsSubtitle;

  /// No description provided for @caCertFingerprint.
  ///
  /// In zh, this message translates to:
  /// **'证书指纹'**
  String get caCertFingerprint;

  /// No description provided for @caCertNoFingerprint.
  ///
  /// In zh, this message translates to:
  /// **'尚未生成证书时没有指纹'**
  String get caCertNoFingerprint;

  /// No description provided for @caCertFingerprintSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'SHA-256（点击查看完整指纹）'**
  String get caCertFingerprintSubtitle;

  /// No description provided for @caCertViewPem.
  ///
  /// In zh, this message translates to:
  /// **'查看证书内容'**
  String get caCertViewPem;

  /// No description provided for @caCertViewPemSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'以可复制的 PEM 文本显示，便于拷到别处安装'**
  String get caCertViewPemSubtitle;

  /// No description provided for @caCertSectionManage.
  ///
  /// In zh, this message translates to:
  /// **'证书管理'**
  String get caCertSectionManage;

  /// No description provided for @caCertRegenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成根证书'**
  String get caCertRegenerate;

  /// No description provided for @caCertRegenerateSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'作废当前私钥并生成新证书，重置后需重新安装'**
  String get caCertRegenerateSubtitle;

  /// No description provided for @caCertNoCertificate.
  ///
  /// In zh, this message translates to:
  /// **'还没有可用证书，请先点「重新生成根证书」'**
  String get caCertNoCertificate;

  /// No description provided for @caCertInstallDialogBody.
  ///
  /// In zh, this message translates to:
  /// **'Android 只允许用户手动把根证书装进「CA 证书」一栏，应用无法静默写入系统信任存储。\n\n点「继续」会先保存一份证书文件到下载目录，再尝试打开系统安装器；若安装器只提示去设置，请用该文件在「设置 → 安全 → 加密与凭据 → 安装证书 → CA 证书」里手动选中它。'**
  String get caCertInstallDialogBody;

  /// No description provided for @caCertSavedTo.
  ///
  /// In zh, this message translates to:
  /// **'证书已存到 {name}。'**
  String caCertSavedTo(String name);

  /// No description provided for @caCertDownloadsDir.
  ///
  /// In zh, this message translates to:
  /// **'下载目录'**
  String get caCertDownloadsDir;

  /// No description provided for @caCertSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'证书文件保存失败（{error}）。'**
  String caCertSaveFailed(String error);

  /// No description provided for @caCertOpenedInstaller.
  ///
  /// In zh, this message translates to:
  /// **'已打开系统证书安装界面。'**
  String get caCertOpenedInstaller;

  /// No description provided for @caCertOpenedSettings.
  ///
  /// In zh, this message translates to:
  /// **'系统没有证书安装器，已打开安全设置。'**
  String get caCertOpenedSettings;

  /// No description provided for @caCertInstallerUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法打开证书安装界面。'**
  String get caCertInstallerUnavailable;

  /// No description provided for @caCertManualHint.
  ///
  /// In zh, this message translates to:
  /// **'若界面只提示前往设置，请在「加密与凭据 → 安装证书 → CA 证书」里手动选中它。'**
  String get caCertManualHint;

  /// No description provided for @caCertSavedHint.
  ///
  /// In zh, this message translates to:
  /// **'已保存到 {name}，可在「加密与凭据 → 安装证书」里选中它'**
  String caCertSavedHint(String name);

  /// No description provided for @caCertDownloadsFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法写入下载目录'**
  String get caCertDownloadsFailed;

  /// No description provided for @caCertRegenerateTitle.
  ///
  /// In zh, this message translates to:
  /// **'重新生成根证书？'**
  String get caCertRegenerateTitle;

  /// No description provided for @caCertRegenerateBody.
  ///
  /// In zh, this message translates to:
  /// **'会删除现有的 ca.crt / ca.key 与黑名单缓存。已安装的旧证书随即失效，之前被信任的所有连接都需要重新安装新证书，HTTPS 检查也会被自动关闭。'**
  String get caCertRegenerateBody;

  /// No description provided for @caCertRegenerateAction.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get caCertRegenerateAction;

  /// No description provided for @caCertGenerateFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成失败：{error}'**
  String caCertGenerateFailed(String error);

  /// No description provided for @caCertGenerated.
  ///
  /// In zh, this message translates to:
  /// **'已生成新证书，请前往系统设置安装'**
  String get caCertGenerated;

  /// No description provided for @caCertFingerprintTitle.
  ///
  /// In zh, this message translates to:
  /// **'证书指纹（SHA-256）'**
  String get caCertFingerprintTitle;

  /// No description provided for @caCertFingerprintCopied.
  ///
  /// In zh, this message translates to:
  /// **'指纹已复制'**
  String get caCertFingerprintCopied;

  /// No description provided for @caCertPemTitle.
  ///
  /// In zh, this message translates to:
  /// **'根证书 PEM'**
  String get caCertPemTitle;

  /// No description provided for @caCertPemCopied.
  ///
  /// In zh, this message translates to:
  /// **'证书内容已复制'**
  String get caCertPemCopied;

  /// No description provided for @caCertGuideTitle.
  ///
  /// In zh, this message translates to:
  /// **'CA 证书指南'**
  String get caCertGuideTitle;

  /// No description provided for @caCertWhyTitle.
  ///
  /// In zh, this message translates to:
  /// **'为什么需要安装'**
  String get caCertWhyTitle;

  /// No description provided for @caCertWhyBody.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 流量检查需要在设备上建立一条本地解密通道。系统只信任「用户」证书区里手工安装的根证书，应用无法代替你点这一步。'**
  String get caCertWhyBody;

  /// No description provided for @caCertStepsTitle.
  ///
  /// In zh, this message translates to:
  /// **'安装步骤'**
  String get caCertStepsTitle;

  /// No description provided for @caCertStep1.
  ///
  /// In zh, this message translates to:
  /// **'1. 在「CA 证书设置」里点「安装根证书」，应用会把证书文件存进下载目录，再交给系统安装器。'**
  String get caCertStep1;

  /// No description provided for @caCertStep2.
  ///
  /// In zh, this message translates to:
  /// **'2. Android 11 起系统安装器通常只提示前往设置，这是平台限制，不是应用故障。请从「设置 → 安全 → 加密与凭据 → 安装证书 → CA 证书」里选中下载目录里的那个 .crt 文件。'**
  String get caCertStep2;

  /// No description provided for @caCertStep3.
  ///
  /// In zh, this message translates to:
  /// **'3. 安装时系统会要求屏幕锁或指纹；设备没有锁屏时无法安装，需先设一个 PIN。'**
  String get caCertStep3;

  /// No description provided for @caCertStep4.
  ///
  /// In zh, this message translates to:
  /// **'4. 回到本页，状态应变成「已验证」；没变就退出重进该页重新检查。'**
  String get caCertStep4;

  /// No description provided for @caCertWhichAppsTitle.
  ///
  /// In zh, this message translates to:
  /// **'哪些应用能被检查'**
  String get caCertWhichAppsTitle;

  /// No description provided for @caCertWhichAppsBody.
  ///
  /// In zh, this message translates to:
  /// **'系统只信任「用户」证书区的根证书，而 targetSdk 24（Android 7.0）及以上的应用默认不信任用户证书。只有自带网络安全配置允许用户 CA 的应用，其 HTTPS 才能被解密并看到明文。'**
  String get caCertWhichAppsBody;

  /// No description provided for @caCertWhichAppsWarning.
  ///
  /// In zh, this message translates to:
  /// **'其余应用的 HTTPS 请求会被记录为「失败 / client_tls」，这是应用的证书绑定或系统策略导致的，属于预期行为；这类应用应加入绕过规则。'**
  String get caCertWhichAppsWarning;

  /// No description provided for @caCertRiskTitle.
  ///
  /// In zh, this message translates to:
  /// **'卸载与风险'**
  String get caCertRiskTitle;

  /// No description provided for @caCertRiskWarning.
  ///
  /// In zh, this message translates to:
  /// **'根证书一旦装进用户信任区，任何持有对应私钥的软件都能解密本机流量。不再使用时请到系统设置里删除它，并在本页「重新生成根证书」作废旧私钥。'**
  String get caCertRiskWarning;

  /// No description provided for @caCertRiskPinning.
  ///
  /// In zh, this message translates to:
  /// **'部分应用使用证书绑定（SSL Pinning），装证书后仍会连接失败；这类应用应加入绕过规则，而不是反复重装证书。'**
  String get caCertRiskPinning;

  /// No description provided for @commonCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get commonCopy;

  /// No description provided for @commonContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get commonContinue;

  /// No description provided for @commonUnknownReason.
  ///
  /// In zh, this message translates to:
  /// **'未知原因'**
  String get commonUnknownReason;

  /// No description provided for @autoUpdateTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动更新设置'**
  String get autoUpdateTitle;

  /// No description provided for @autoUpdateSection.
  ///
  /// In zh, this message translates to:
  /// **'自动更新'**
  String get autoUpdateSection;

  /// No description provided for @autoUpdateRulesSwitch.
  ///
  /// In zh, this message translates to:
  /// **'自动更新规则订阅'**
  String get autoUpdateRulesSwitch;

  /// No description provided for @autoUpdateRulesSwitchSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'启动应用、回到前台或到达设定时刻时检查是否到期'**
  String get autoUpdateRulesSwitchSubtitle;

  /// No description provided for @autoUpdateIntervalSection.
  ///
  /// In zh, this message translates to:
  /// **'更新频率'**
  String get autoUpdateIntervalSection;

  /// No description provided for @autoUpdateEveryHours.
  ///
  /// In zh, this message translates to:
  /// **'每 {hours} 小时'**
  String autoUpdateEveryHours(int hours);

  /// No description provided for @autoUpdateCustomInterval.
  ///
  /// In zh, this message translates to:
  /// **'自定义更新时间'**
  String get autoUpdateCustomInterval;

  /// No description provided for @autoUpdateCustomHint.
  ///
  /// In zh, this message translates to:
  /// **'输入 1 至 168 小时之间的更新时间'**
  String get autoUpdateCustomHint;

  /// No description provided for @autoUpdateTimedSection.
  ///
  /// In zh, this message translates to:
  /// **'按时刻更新'**
  String get autoUpdateTimedSection;

  /// No description provided for @autoUpdateDailyAt.
  ///
  /// In zh, this message translates to:
  /// **'每天 {time}'**
  String autoUpdateDailyAt(String time);

  /// No description provided for @autoUpdateEveryOtherDayAt.
  ///
  /// In zh, this message translates to:
  /// **'隔天 {time}'**
  String autoUpdateEveryOtherDayAt(String time);

  /// No description provided for @autoUpdateTimedPickHint.
  ///
  /// In zh, this message translates to:
  /// **'点按选择执行时刻'**
  String get autoUpdateTimedPickHint;

  /// No description provided for @autoUpdateTimedChangeHint.
  ///
  /// In zh, this message translates to:
  /// **'点按修改执行时刻'**
  String get autoUpdateTimedChangeHint;

  /// No description provided for @autoUpdateIntervalFooter.
  ///
  /// In zh, this message translates to:
  /// **'设置保存在当前工作模式的数据集里（普通 / 极速 / 服务器各自独立）。按时刻更新使用手机系统时间与时区；新选的时刻若今天已过，从下一次开始计。本机没有后台任务队列：应用在前台时到点立即执行，不在前台时会在下次启动或切回前台时补跑，进程被完全关闭期间不会更新。'**
  String get autoUpdateIntervalFooter;

  /// No description provided for @autoUpdateStatusSection.
  ///
  /// In zh, this message translates to:
  /// **'执行状态'**
  String get autoUpdateStatusSection;

  /// No description provided for @autoUpdateNext.
  ///
  /// In zh, this message translates to:
  /// **'下次预计更新'**
  String get autoUpdateNext;

  /// No description provided for @autoUpdateLast.
  ///
  /// In zh, this message translates to:
  /// **'上次自动更新'**
  String get autoUpdateLast;

  /// No description provided for @autoUpdateNoRunYet.
  ///
  /// In zh, this message translates to:
  /// **'本次会话还没有执行过自动更新'**
  String get autoUpdateNoRunYet;

  /// No description provided for @autoUpdateRunCount.
  ///
  /// In zh, this message translates to:
  /// **'（{count} 个订阅）'**
  String autoUpdateRunCount(int count);

  /// No description provided for @autoUpdateStatusFooter.
  ///
  /// In zh, this message translates to:
  /// **'按间隔时，判据是每条订阅的「上次尝试时间」与间隔；按时刻时，最近一个已到的时刻之后没有尝试过的订阅视为到期。正在手动更新时本轮会让路。'**
  String get autoUpdateStatusFooter;

  /// No description provided for @autoUpdateGroupsSection.
  ///
  /// In zh, this message translates to:
  /// **'分组自动更新'**
  String get autoUpdateGroupsSection;

  /// No description provided for @autoUpdateReadingGroups.
  ///
  /// In zh, this message translates to:
  /// **'读取分组中…'**
  String get autoUpdateReadingGroups;

  /// No description provided for @autoUpdateNoGroups.
  ///
  /// In zh, this message translates to:
  /// **'还没有分组'**
  String get autoUpdateNoGroups;

  /// No description provided for @autoUpdateNoGroupsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在规则订阅页新建分组后，可以在这里单独开关'**
  String get autoUpdateNoGroupsSubtitle;

  /// No description provided for @autoUpdateGroupsFooter.
  ///
  /// In zh, this message translates to:
  /// **'仅会自动更新已开启的分组中的网络订阅；写入 `subscription_group` 表。'**
  String get autoUpdateGroupsFooter;

  /// No description provided for @autoUpdateReadingSubs.
  ///
  /// In zh, this message translates to:
  /// **'正在读取订阅…'**
  String get autoUpdateReadingSubs;

  /// No description provided for @autoUpdateNoCandidates.
  ///
  /// In zh, this message translates to:
  /// **'没有可自动更新的订阅（需为远程、已启用、且所在分组已开启）'**
  String get autoUpdateNoCandidates;

  /// No description provided for @autoUpdateDueNow.
  ///
  /// In zh, this message translates to:
  /// **'已到期：应用在前台时会立即执行'**
  String get autoUpdateDueNow;

  /// No description provided for @autoUpdateRemainingHours.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时 {minutes} 分钟后'**
  String autoUpdateRemainingHours(int hours, int minutes);

  /// No description provided for @autoUpdateRemainingMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟后'**
  String autoUpdateRemainingMinutes(int minutes);

  /// No description provided for @autoUpdateNextAt.
  ///
  /// In zh, this message translates to:
  /// **'{moment}（{left}）'**
  String autoUpdateNextAt(String moment, String left);

  /// No description provided for @autoUpdateMoment.
  ///
  /// In zh, this message translates to:
  /// **'{month} 月 {day} 日 {time}'**
  String autoUpdateMoment(int month, int day, String time);

  /// No description provided for @autoUpdateIntervalLabel.
  ///
  /// In zh, this message translates to:
  /// **'更新间隔（小时）'**
  String get autoUpdateIntervalLabel;

  /// No description provided for @autoUpdateIntervalHelper.
  ///
  /// In zh, this message translates to:
  /// **'1–168 小时'**
  String get autoUpdateIntervalHelper;

  /// No description provided for @mirrorTplTitle.
  ///
  /// In zh, this message translates to:
  /// **'镜像站模板'**
  String get mirrorTplTitle;

  /// No description provided for @mirrorTplAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加模板'**
  String get mirrorTplAdd;

  /// No description provided for @mirrorTplIntro.
  ///
  /// In zh, this message translates to:
  /// **'保存常用的下载镜像。开启全局镜像后，订阅与软件更新默认都走所选模板；添加订阅时也可以单独指定模板。'**
  String get mirrorTplIntro;

  /// No description provided for @mirrorTplActions.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get mirrorTplActions;

  /// No description provided for @mirrorTplFormatExample.
  ///
  /// In zh, this message translates to:
  /// **'镜像站格式示例'**
  String get mirrorTplFormatExample;

  /// No description provided for @mirrorTplFormatExampleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'了解占位符如何组成镜像地址'**
  String get mirrorTplFormatExampleSubtitle;

  /// No description provided for @mirrorTplSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存模板'**
  String get mirrorTplSaved;

  /// No description provided for @mirrorTplReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取镜像站模板'**
  String get mirrorTplReadFailed;

  /// No description provided for @mirrorTplReadFailedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'旧库尚未就绪或该表不可用'**
  String get mirrorTplReadFailedSubtitle;

  /// No description provided for @mirrorTplSavedCount.
  ///
  /// In zh, this message translates to:
  /// **'已保存模板（{count}）'**
  String mirrorTplSavedCount(int count);

  /// No description provided for @mirrorTplReading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取镜像站模板…'**
  String get mirrorTplReading;

  /// No description provided for @mirrorTplEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无模板。点击右上角「添加模板」开始使用。'**
  String get mirrorTplEmpty;

  /// No description provided for @mirrorTplDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'同名模板已存在，请换一个名称'**
  String get mirrorTplDuplicate;

  /// No description provided for @mirrorTplDuplicateSave.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：名称与已有模板重复'**
  String get mirrorTplDuplicateSave;

  /// No description provided for @mirrorTplFormatTitle.
  ///
  /// In zh, this message translates to:
  /// **'镜像站格式'**
  String get mirrorTplFormatTitle;

  /// No description provided for @mirrorTplFormatIntro.
  ///
  /// In zh, this message translates to:
  /// **'镜像地址由固定前缀与占位符组成，下载订阅时会把占位符替换成真实链接。'**
  String get mirrorTplFormatIntro;

  /// No description provided for @mirrorTplFormatUrl.
  ///
  /// In zh, this message translates to:
  /// **'{token}：完整订阅地址'**
  String mirrorTplFormatUrl(String token);

  /// No description provided for @mirrorTplFormatScheme.
  ///
  /// In zh, this message translates to:
  /// **'{token}：http 或 https'**
  String mirrorTplFormatScheme(String token);

  /// No description provided for @mirrorTplFormatUrlEncoded.
  ///
  /// In zh, this message translates to:
  /// **'{token}：URL 编码后的完整地址'**
  String mirrorTplFormatUrlEncoded(String token);

  /// No description provided for @mirrorTplFormatHost.
  ///
  /// In zh, this message translates to:
  /// **'{token}：订阅域名'**
  String mirrorTplFormatHost(String token);

  /// No description provided for @mirrorTplFormatPath.
  ///
  /// In zh, this message translates to:
  /// **'{token}：路径部分'**
  String mirrorTplFormatPath(String token);

  /// No description provided for @mirrorTplFormatPathAndQuery.
  ///
  /// In zh, this message translates to:
  /// **'{token}：路径与查询参数'**
  String mirrorTplFormatPathAndQuery(String token);

  /// No description provided for @mirrorTplFormatSample.
  ///
  /// In zh, this message translates to:
  /// **'示例：https://ghproxy.example.com/{token}'**
  String mirrorTplFormatSample(String token);

  /// No description provided for @mirrorTplFormatPlaceholders.
  ///
  /// In zh, this message translates to:
  /// **'可用占位符：{url}、{scheme}、{urlEncoded}、{host}、{path}、{pathAndQuery}'**
  String mirrorTplFormatPlaceholders(
    String url,
    String scheme,
    String urlEncoded,
    String host,
    String path,
    String pathAndQuery,
  );

  /// No description provided for @mirrorTplNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'模板名称'**
  String get mirrorTplNameLabel;

  /// No description provided for @mirrorTplNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：GitHub 镜像'**
  String get mirrorTplNameHint;

  /// No description provided for @mirrorTplAddressLabel.
  ///
  /// In zh, this message translates to:
  /// **'模板地址'**
  String get mirrorTplAddressLabel;

  /// No description provided for @mirrorTplInvalid.
  ///
  /// In zh, this message translates to:
  /// **'必须使用 HTTP(S) 并包含至少一个占位符'**
  String get mirrorTplInvalid;

  /// No description provided for @mirrorTplAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加镜像站模板'**
  String get mirrorTplAddTitle;

  /// No description provided for @mirrorTplEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑镜像站模板'**
  String get mirrorTplEditTitle;

  /// No description provided for @commonEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get commonEdit;

  /// No description provided for @ruleControlUrlNotReadyCa.
  ///
  /// In zh, this message translates to:
  /// **'未就绪 · 需先安装并验证 CA 根证书'**
  String get ruleControlUrlNotReadyCa;

  /// No description provided for @ruleControlUrlNotReadyInspection.
  ///
  /// In zh, this message translates to:
  /// **'未就绪 · 需在 HTTPS 流量检查中开启'**
  String get ruleControlUrlNotReadyInspection;

  /// No description provided for @ruleControlUrlNotReadyApps.
  ///
  /// In zh, this message translates to:
  /// **'未就绪 · 需在 HTTPS 流量检查中选择目标应用'**
  String get ruleControlUrlNotReadyApps;

  /// No description provided for @ruleControlUrlPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停 · 未启用解密 URL 过滤与重定向'**
  String get ruleControlUrlPaused;

  /// No description provided for @ruleControlUrlRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中 · 解密流量匹配 URL 屏蔽、放行及重定向'**
  String get ruleControlUrlRunning;

  /// No description provided for @ruleControlIntro.
  ///
  /// In zh, this message translates to:
  /// **'统一管理域名过滤、URL 规则及规则覆写的总控开关、拦截策略与在线规则订阅。黑名单、白名单与覆写名单可在功能中心中独立管理。'**
  String get ruleControlIntro;

  /// No description provided for @ruleControlIntroLimited.
  ///
  /// In zh, this message translates to:
  /// **'统一管理域名过滤的总控开关、拦截策略与在线规则订阅。黑名单、白名单与覆写名单可在功能中心中独立管理。'**
  String get ruleControlIntroLimited;

  /// No description provided for @ruleControlFilterSection.
  ///
  /// In zh, this message translates to:
  /// **'过滤与覆写控制'**
  String get ruleControlFilterSection;

  /// No description provided for @ruleControlDomainRules.
  ///
  /// In zh, this message translates to:
  /// **'启用域名规则'**
  String get ruleControlDomainRules;

  /// No description provided for @ruleControlDomainRulesOn.
  ///
  /// In zh, this message translates to:
  /// **'开启 DNS 阶段域名屏蔽、白名单放行及 IPv4/IPv6 覆写'**
  String get ruleControlDomainRulesOn;

  /// No description provided for @ruleControlDomainRulesOff.
  ///
  /// In zh, this message translates to:
  /// **'已禁用 DNS 域名过滤，查询将直接放行'**
  String get ruleControlDomainRulesOff;

  /// No description provided for @ruleControlUrlRules.
  ///
  /// In zh, this message translates to:
  /// **'URL 规则与内容过滤'**
  String get ruleControlUrlRules;

  /// No description provided for @ruleControlNotReady.
  ///
  /// In zh, this message translates to:
  /// **'未就绪'**
  String get ruleControlNotReady;

  /// No description provided for @ruleControlPolicySection.
  ///
  /// In zh, this message translates to:
  /// **'拦截策略'**
  String get ruleControlPolicySection;

  /// No description provided for @ruleControlBlockResponse.
  ///
  /// In zh, this message translates to:
  /// **'拦截响应'**
  String get ruleControlBlockResponse;

  /// No description provided for @ruleControlDynamicSummary.
  ///
  /// In zh, this message translates to:
  /// **'动态策略：先 NODATA，高频请求后 {mode}'**
  String ruleControlDynamicSummary(String mode);

  /// No description provided for @ruleControlNetworkPrivacySection.
  ///
  /// In zh, this message translates to:
  /// **'网络隐私与诊断'**
  String get ruleControlNetworkPrivacySection;

  /// No description provided for @ruleControlInterfacesSection.
  ///
  /// In zh, this message translates to:
  /// **'对外接口与联动'**
  String get ruleControlInterfacesSection;

  /// No description provided for @ruleControlSubsSection.
  ///
  /// In zh, this message translates to:
  /// **'订阅与更新'**
  String get ruleControlSubsSection;

  /// No description provided for @ruleControlSubsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理域名规则与 IPv4/IPv6 覆写订阅源及分组'**
  String get ruleControlSubsSubtitle;

  /// No description provided for @ruleControlCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个'**
  String ruleControlCount(int count);

  /// No description provided for @ruleControlAutoUpdateOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启 · 每 {hours} 小时自动更新'**
  String ruleControlAutoUpdateOn(int hours);

  /// No description provided for @ruleControlAutoUpdateDaily.
  ///
  /// In zh, this message translates to:
  /// **'已开启 · 每天 {time} 自动更新'**
  String ruleControlAutoUpdateDaily(String time);

  /// No description provided for @ruleControlAutoUpdateEveryOtherDay.
  ///
  /// In zh, this message translates to:
  /// **'已开启 · 隔天 {time} 自动更新'**
  String ruleControlAutoUpdateEveryOtherDay(String time);

  /// No description provided for @ruleControlAutoUpdateOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭自动更新'**
  String get ruleControlAutoUpdateOff;

  /// No description provided for @ruleControlMirrorSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'维护订阅下载镜像，可在添加订阅时直接选择'**
  String get ruleControlMirrorSubtitle;

  /// No description provided for @blockResponseFixedSection.
  ///
  /// In zh, this message translates to:
  /// **'固定响应'**
  String get blockResponseFixedSection;

  /// No description provided for @blockResponseFixedFooter.
  ///
  /// In zh, this message translates to:
  /// **'动态策略开启时会临时覆盖以上选择：先返回 NODATA，高频请求后返回 NXDOMAIN。'**
  String get blockResponseFixedFooter;

  /// No description provided for @blockResponseDynamicSection.
  ///
  /// In zh, this message translates to:
  /// **'动态策略'**
  String get blockResponseDynamicSection;

  /// No description provided for @blockResponseEnableDynamic.
  ///
  /// In zh, this message translates to:
  /// **'启用动态策略'**
  String get blockResponseEnableDynamic;

  /// No description provided for @blockResponseEnableDynamicSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'同一域名的所有记录类型合并计数'**
  String get blockResponseEnableDynamicSubtitle;

  /// No description provided for @blockResponseParameters.
  ///
  /// In zh, this message translates to:
  /// **'动态参数'**
  String get blockResponseParameters;

  /// No description provided for @blockResponseParamsSummary.
  ///
  /// In zh, this message translates to:
  /// **'{threshold} 次 / {window} 秒 / 保持 {duration} 秒'**
  String blockResponseParamsSummary(int threshold, int window, int duration);

  /// No description provided for @blockResponseDynamicFooter.
  ///
  /// In zh, this message translates to:
  /// **'正常客户端会缓存 NODATA 响应。动态策略主要用于持续重试或忽略负缓存的请求。'**
  String get blockResponseDynamicFooter;

  /// No description provided for @blockResponseThresholdError.
  ///
  /// In zh, this message translates to:
  /// **'请求次数需在 2–100 之间'**
  String get blockResponseThresholdError;

  /// No description provided for @blockResponseWindowError.
  ///
  /// In zh, this message translates to:
  /// **'统计窗口需在 10–300 秒之间'**
  String get blockResponseWindowError;

  /// No description provided for @blockResponseDurationError.
  ///
  /// In zh, this message translates to:
  /// **'保持时长需在 60–3600 秒之间'**
  String get blockResponseDurationError;

  /// No description provided for @blockResponseThresholdLabel.
  ///
  /// In zh, this message translates to:
  /// **'请求次数'**
  String get blockResponseThresholdLabel;

  /// No description provided for @blockResponseThresholdHelper.
  ///
  /// In zh, this message translates to:
  /// **'2–100 次；第 N+1 次开始升级'**
  String get blockResponseThresholdHelper;

  /// No description provided for @blockResponseWindowLabel.
  ///
  /// In zh, this message translates to:
  /// **'统计窗口（秒）'**
  String get blockResponseWindowLabel;

  /// No description provided for @blockResponseWindowHelper.
  ///
  /// In zh, this message translates to:
  /// **'10–300 秒'**
  String get blockResponseWindowHelper;

  /// No description provided for @blockResponseDurationLabel.
  ///
  /// In zh, this message translates to:
  /// **'NXDOMAIN 保持时长（秒）'**
  String get blockResponseDurationLabel;

  /// No description provided for @blockResponseDurationHelper.
  ///
  /// In zh, this message translates to:
  /// **'60–3600 秒；首次升级起固定计时'**
  String get blockResponseDurationHelper;

  /// No description provided for @httpInspCheckingCa.
  ///
  /// In zh, this message translates to:
  /// **'正在检查根证书…'**
  String get httpInspCheckingCa;

  /// No description provided for @httpInspNoAppsHint.
  ///
  /// In zh, this message translates to:
  /// **'未选择目标应用，仅保留 DNS 过滤'**
  String get httpInspNoAppsHint;

  /// No description provided for @httpInspSelectedHint.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 个应用，其余直接转发'**
  String httpInspSelectedHint(int count);

  /// No description provided for @httpInspScopeSection.
  ///
  /// In zh, this message translates to:
  /// **'检查范围'**
  String get httpInspScopeSection;

  /// No description provided for @httpInspEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用 HTTPS 检查'**
  String get httpInspEnable;

  /// No description provided for @httpInspTargetApps.
  ///
  /// In zh, this message translates to:
  /// **'目标应用'**
  String get httpInspTargetApps;

  /// No description provided for @httpInspNoApps.
  ///
  /// In zh, this message translates to:
  /// **'未选择任何应用'**
  String get httpInspNoApps;

  /// No description provided for @httpInspSelectedApps.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 个应用'**
  String httpInspSelectedApps(int count);

  /// No description provided for @httpInspCaCert.
  ///
  /// In zh, this message translates to:
  /// **'CA 证书'**
  String get httpInspCaCert;

  /// No description provided for @httpInspCaReady.
  ///
  /// In zh, this message translates to:
  /// **'证书已安装且指纹匹配，可查看或重置'**
  String get httpInspCaReady;

  /// No description provided for @httpInspContentSection.
  ///
  /// In zh, this message translates to:
  /// **'解密内容过滤'**
  String get httpInspContentSection;

  /// No description provided for @httpInspUrlRules.
  ///
  /// In zh, this message translates to:
  /// **'启用 URL 规则与重定向'**
  String get httpInspUrlRules;

  /// No description provided for @httpInspNeedEnable.
  ///
  /// In zh, this message translates to:
  /// **'需先启用 HTTPS 检查'**
  String get httpInspNeedEnable;

  /// No description provided for @httpInspUrlPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停 · 解密请求直接放行，不应用 URL 规则及 CNAME 重定向'**
  String get httpInspUrlPaused;

  /// No description provided for @httpInspUrlOn.
  ///
  /// In zh, this message translates to:
  /// **'开启解密流量下的 URL 屏蔽、放行及 CNAME 重定向'**
  String get httpInspUrlOn;

  /// No description provided for @httpInspProtocolSection.
  ///
  /// In zh, this message translates to:
  /// **'协议与兼容性'**
  String get httpInspProtocolSection;

  /// No description provided for @httpInspBlockHttp3.
  ///
  /// In zh, this message translates to:
  /// **'拦截 HTTP/3 (QUIC)'**
  String get httpInspBlockHttp3;

  /// No description provided for @httpInspBlockHttp3Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'阻断 QUIC 促使回退至 TCP 以便解密；若异常请关闭'**
  String get httpInspBlockHttp3Subtitle;

  /// No description provided for @httpInspBlockDot.
  ///
  /// In zh, this message translates to:
  /// **'阻断加密 DNS (DoT)'**
  String get httpInspBlockDot;

  /// No description provided for @httpInspBlockDotSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'阻断 TCP 853 端口，防止绕过域名规则'**
  String get httpInspBlockDotSubtitle;

  /// No description provided for @httpInspRequestLogs.
  ///
  /// In zh, this message translates to:
  /// **'请求日志'**
  String get httpInspRequestLogs;

  /// No description provided for @httpInspRequestLogsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看解密明细与自动旁路记录'**
  String get httpInspRequestLogsSubtitle;

  /// No description provided for @httpInspBypassFooter.
  ///
  /// In zh, this message translates to:
  /// **'写入 https_bypass_rules，与 assets/https_passthrough.txt 的内置清单合并后交给引擎的 setExtraPassthroughSuffixes。'**
  String get httpInspBypassFooter;

  /// No description provided for @httpInspBypassTitle.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 绕过规则（{count}）'**
  String httpInspBypassTitle(int count);

  /// No description provided for @httpInspBypassEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未配置自定义绕过规则'**
  String get httpInspBypassEmpty;

  /// No description provided for @httpInspBypassEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'内置放行清单始终生效；这里是额外追加的域名后缀'**
  String get httpInspBypassEmptySubtitle;

  /// No description provided for @httpInspBypassRowSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'不参与解密，直接透传'**
  String get httpInspBypassRowSubtitle;

  /// No description provided for @httpInspCaRequiredTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要先安装根证书'**
  String get httpInspCaRequiredTitle;

  /// No description provided for @httpInspGoInstall.
  ///
  /// In zh, this message translates to:
  /// **'前往安装'**
  String get httpInspGoInstall;

  /// No description provided for @httpInspCaReadingBody.
  ///
  /// In zh, this message translates to:
  /// **'正在读取根证书状态，请稍后再试。'**
  String get httpInspCaReadingBody;

  /// No description provided for @httpInspCaRequiredBody.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 检查要把解密后的明文交回应用，必须由系统的根证书信任链认可谛听的根证书。当前是「{problem}」，所以还不能选择目标应用。\n\n去 CA 证书页生成并安装证书？'**
  String httpInspCaRequiredBody(String problem);

  /// No description provided for @httpInspCaMissing.
  ///
  /// In zh, this message translates to:
  /// **'尚未生成根证书：前往 CA 证书页生成'**
  String get httpInspCaMissing;

  /// No description provided for @httpInspCaNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'证书已生成但未安装到系统信任存储'**
  String get httpInspCaNotInstalled;

  /// No description provided for @httpInspCaReadyShort.
  ///
  /// In zh, this message translates to:
  /// **'证书已就绪'**
  String get httpInspCaReadyShort;

  /// No description provided for @httpInspNeedDomainRulesTitle.
  ///
  /// In zh, this message translates to:
  /// **'还需要开启域名规则'**
  String get httpInspNeedDomainRulesTitle;

  /// No description provided for @httpInspEnableAll.
  ///
  /// In zh, this message translates to:
  /// **'全部开启'**
  String get httpInspEnableAll;

  /// No description provided for @httpInspNeedDomainRulesBody.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 检查负责解密，域名规则负责决定解密后的流量怎么处理。当前域名规则是关闭状态，只开检查不会有任何拦截效果。\n\n是否同时开启域名规则？'**
  String get httpInspNeedDomainRulesBody;

  /// No description provided for @httpInspAppsTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择检查应用'**
  String get httpInspAppsTitle;

  /// No description provided for @httpInspSelectVisible.
  ///
  /// In zh, this message translates to:
  /// **'全选当前结果'**
  String get httpInspSelectVisible;

  /// No description provided for @httpInspDeselectVisible.
  ///
  /// In zh, this message translates to:
  /// **'取消当前结果'**
  String get httpInspDeselectVisible;

  /// No description provided for @httpInspAppsIntro.
  ///
  /// In zh, this message translates to:
  /// **'Go 隧道接管流量后，HTTPS 流量检查仅检查所选应用的 HTTP(S) 请求，其他应用直接转发。选择应用会取消其「排除应用」「禁止联网」与应用独立规则状态。'**
  String get httpInspAppsIntro;

  /// No description provided for @httpInspAppsCount.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {selected} 个应用（可见 {visible}）'**
  String httpInspAppsCount(int selected, int visible);

  /// No description provided for @commonLater.
  ///
  /// In zh, this message translates to:
  /// **'稍后'**
  String get commonLater;

  /// No description provided for @ruleControlSubsTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则订阅'**
  String get ruleControlSubsTitle;

  /// No description provided for @cleanupIntro.
  ///
  /// In zh, this message translates to:
  /// **'以下操作会立即删除本机数据，删除后无法恢复。重要规则或配置请在执行前备份。'**
  String get cleanupIntro;

  /// No description provided for @cleanupRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在执行：{title}'**
  String cleanupRunning(String title);

  /// No description provided for @cleanupDescLogs.
  ///
  /// In zh, this message translates to:
  /// **'清除 DNS、HTTP 请求日志、竞速统计及 Bootstrap 解析日志'**
  String get cleanupDescLogs;

  /// No description provided for @cleanupDescTraffic.
  ///
  /// In zh, this message translates to:
  /// **'清除所有应用的历史流量统计记录与实时统计状态'**
  String get cleanupDescTraffic;

  /// No description provided for @cleanupDescCrash.
  ///
  /// In zh, this message translates to:
  /// **'清除本地保存的所有 Java 与 Native 异常崩溃日志'**
  String get cleanupDescCrash;

  /// No description provided for @cleanupDescDnsCache.
  ///
  /// In zh, this message translates to:
  /// **'移除已缓存的解析结果，下次访问会重新查询'**
  String get cleanupDescDnsCache;

  /// No description provided for @cleanupDescProviderWeights.
  ///
  /// In zh, this message translates to:
  /// **'清除智能选择的健康样本，让它重新按默认权重分配流量'**
  String get cleanupDescProviderWeights;

  /// No description provided for @cleanupDescBootstrapWeights.
  ///
  /// In zh, this message translates to:
  /// **'清除 Bootstrap DNS 解析健康样本，重新按默认权重选择'**
  String get cleanupDescBootstrapWeights;

  /// No description provided for @cleanupDescDomainRules.
  ///
  /// In zh, this message translates to:
  /// **'清除域名屏蔽、白名单、IPv4/IPv6 覆写及对应订阅，恢复预设白名单'**
  String get cleanupDescDomainRules;

  /// No description provided for @cleanupDescAddressRules.
  ///
  /// In zh, this message translates to:
  /// **'清除 URL 屏蔽、放行和 CNAME 覆写规则，不影响域名规则'**
  String get cleanupDescAddressRules;

  /// No description provided for @cleanupDescSubscriptions.
  ///
  /// In zh, this message translates to:
  /// **'清除所有网络与本地规则订阅、订阅分组及自动更新任务'**
  String get cleanupDescSubscriptions;

  /// No description provided for @cleanupDescAppRules.
  ///
  /// In zh, this message translates to:
  /// **'清空分应用排除、禁止联网应用、应用白名单及抓包名单'**
  String get cleanupDescAppRules;

  /// No description provided for @cleanupDescOutboundProxy.
  ///
  /// In zh, this message translates to:
  /// **'清空出站代理协议、服务器与鉴权信息，恢复直连'**
  String get cleanupDescOutboundProxy;

  /// No description provided for @cleanupDescCaCertificate.
  ///
  /// In zh, this message translates to:
  /// **'清除本地生成的 MITM CA 根证书与私钥'**
  String get cleanupDescCaCertificate;

  /// No description provided for @cleanupDescDownloadCache.
  ///
  /// In zh, this message translates to:
  /// **'删除更新安装包、下载临时文件及应用临时缓存'**
  String get cleanupDescDownloadCache;

  /// No description provided for @cleanupDescCustomBackground.
  ///
  /// In zh, this message translates to:
  /// **'清除已配置的自定义壁纸图片缓存及路径记录，恢复默认背景'**
  String get cleanupDescCustomBackground;

  /// No description provided for @cleanupDescSettingsGuides.
  ///
  /// In zh, this message translates to:
  /// **'让所有首次进入说明再次显示，需要重新同意使用协议'**
  String get cleanupDescSettingsGuides;

  /// No description provided for @cleanupDescAllData.
  ///
  /// In zh, this message translates to:
  /// **'深度清空所有日志、缓存、规则、订阅、证书与配置，应用将退出'**
  String get cleanupDescAllData;

  /// No description provided for @cleanupConfirmLogs.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除所有 DNS、HTTP 请求日志、竞速统计和 Bootstrap DNS 解析统计吗？'**
  String get cleanupConfirmLogs;

  /// No description provided for @cleanupConfirmTraffic.
  ///
  /// In zh, this message translates to:
  /// **'确定要清除所有应用的历史流量统计记录与实时统计状态吗？'**
  String get cleanupConfirmTraffic;

  /// No description provided for @cleanupConfirmCrash.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除所有本地崩溃日志和崩溃统计状态吗？'**
  String get cleanupConfirmCrash;

  /// No description provided for @cleanupConfirmDnsCache.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除所有本地 DNS 缓存吗？下次访问域名时会重新查询。'**
  String get cleanupConfirmDnsCache;

  /// No description provided for @cleanupConfirmProviderWeights.
  ///
  /// In zh, this message translates to:
  /// **'确定要清除所有服务商健康样本并恢复竞速模式默认权重吗？'**
  String get cleanupConfirmProviderWeights;

  /// No description provided for @cleanupConfirmBootstrapWeights.
  ///
  /// In zh, this message translates to:
  /// **'确定要清除 Bootstrap DNS 解析健康样本并恢复默认权重吗？'**
  String get cleanupConfirmBootstrapWeights;

  /// No description provided for @cleanupConfirmDomainRules.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除全部域名规则吗？域名屏蔽、白名单、IPv4/IPv6 覆写规则及对应订阅都会被移除，地址规则不受影响。'**
  String get cleanupConfirmDomainRules;

  /// No description provided for @cleanupConfirmAddressRules.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除全部地址规则吗？URL 屏蔽、放行和 CNAME 覆写规则都会被移除，域名规则不受影响。'**
  String get cleanupConfirmAddressRules;

  /// No description provided for @cleanupConfirmSubscriptions.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除所有规则订阅吗？所有订阅链接、分组与订阅导入的规则都会被移除，手动添加的规则不受影响。'**
  String get cleanupConfirmSubscriptions;

  /// No description provided for @cleanupConfirmAppRules.
  ///
  /// In zh, this message translates to:
  /// **'确定要重置所有应用控制名单吗？分应用代理排除、禁止联网应用、应用独立白名单以及 HTTP/HTTPS 抓包应用配置都将被清空并恢复默认。'**
  String get cleanupConfirmAppRules;

  /// No description provided for @cleanupConfirmOutboundProxy.
  ///
  /// In zh, this message translates to:
  /// **'确定要重置出站代理配置吗？出站代理将被禁用，服务器地址、端口及账号密码将被清除。'**
  String get cleanupConfirmOutboundProxy;

  /// No description provided for @cleanupConfirmCaCertificate.
  ///
  /// In zh, this message translates to:
  /// **'确定要清除本地生成的 HTTPS 抓包 CA 证书和私钥吗？如果系统已安装此证书，清除后需重新生成并导入系统方可继续解密抓包。'**
  String get cleanupConfirmCaCertificate;

  /// No description provided for @cleanupConfirmDownloadCache.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除下载的更新安装包和临时缓存文件吗？'**
  String get cleanupConfirmDownloadCache;

  /// No description provided for @cleanupConfirmCustomBackground.
  ///
  /// In zh, this message translates to:
  /// **'确定要清除自定义壁纸缓存并恢复默认外观背景吗？'**
  String get cleanupConfirmCustomBackground;

  /// No description provided for @cleanupConfirmSettingsGuides.
  ///
  /// In zh, this message translates to:
  /// **'确定要重置所有应用设置新手引导和首次使用协议吗？这不会删除任何配置、规则、缓存、日志或证书。操作完成后应用将退出；下次打开时需要重新同意使用协议，所有新手引导也会再次显示。'**
  String get cleanupConfirmSettingsGuides;

  /// No description provided for @cleanupConfirmAllData.
  ///
  /// In zh, this message translates to:
  /// **'确定要执行全面数据清理吗？将依次清理所有日志、流量统计、崩溃记录、DNS 缓存、服务商权重、域名及地址规则、规则订阅、临时缓存及抓包证书。所有自定义配置与规则将被清空，新手引导也将重置，操作完成后应用将退出。'**
  String get cleanupConfirmAllData;

  /// No description provided for @cleanupRestartTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要重启应用'**
  String get cleanupRestartTitle;

  /// No description provided for @cleanupRestartBody.
  ///
  /// In zh, this message translates to:
  /// **'清理已完成。新手引导与使用协议已重置，应用需要重新启动才会生效。'**
  String get cleanupRestartBody;

  /// No description provided for @commonConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get commonConfirm;

  /// No description provided for @transferTitle.
  ///
  /// In zh, this message translates to:
  /// **'备份与迁移'**
  String get transferTitle;

  /// No description provided for @transferMetricProviders.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务商'**
  String get transferMetricProviders;

  /// No description provided for @transferMetricSubs.
  ///
  /// In zh, this message translates to:
  /// **'规则订阅'**
  String get transferMetricSubs;

  /// No description provided for @transferMetricCustomRules.
  ///
  /// In zh, this message translates to:
  /// **'自定义规则'**
  String get transferMetricCustomRules;

  /// No description provided for @transferMetricListedApps.
  ///
  /// In zh, this message translates to:
  /// **'名单应用'**
  String get transferMetricListedApps;

  /// No description provided for @transferSectionAppConfig.
  ///
  /// In zh, this message translates to:
  /// **'应用配置备份'**
  String get transferSectionAppConfig;

  /// No description provided for @transferSectionRules.
  ///
  /// In zh, this message translates to:
  /// **'规则与订阅配置'**
  String get transferSectionRules;

  /// No description provided for @transferSectionAppControl.
  ///
  /// In zh, this message translates to:
  /// **'应用控制与流量管理'**
  String get transferSectionAppControl;

  /// No description provided for @transferSectionPersonal.
  ///
  /// In zh, this message translates to:
  /// **'个性化与通用设置'**
  String get transferSectionPersonal;

  /// No description provided for @transferDeselectAll.
  ///
  /// In zh, this message translates to:
  /// **'全不选'**
  String get transferDeselectAll;

  /// No description provided for @transferImportExportSection.
  ///
  /// In zh, this message translates to:
  /// **'导入导出'**
  String get transferImportExportSection;

  /// No description provided for @transferExportJson.
  ///
  /// In zh, this message translates to:
  /// **'导出应用配置 (JSON)'**
  String get transferExportJson;

  /// No description provided for @transferExportHintNone.
  ///
  /// In zh, this message translates to:
  /// **'请先勾选要导出的分组'**
  String get transferExportHintNone;

  /// No description provided for @transferExportHintCount.
  ///
  /// In zh, this message translates to:
  /// **'将勾选的 {count} 组配置保存为 JSON 文件'**
  String transferExportHintCount(int count);

  /// No description provided for @transferImportJson.
  ///
  /// In zh, this message translates to:
  /// **'导入应用配置 (JSON)'**
  String get transferImportJson;

  /// No description provided for @transferImportSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从备份文件合并配置，自动跳过本机已存在项目'**
  String get transferImportSubtitle;

  /// No description provided for @transferImportExportFooter.
  ///
  /// In zh, this message translates to:
  /// **'导出的配置文件包含个人自定义设置，请妥善保管；导入时将合并配置并自动跳过已存在的条目。出站代理的账号密码不在备份范围内。'**
  String get transferImportExportFooter;

  /// No description provided for @transferCloudSection.
  ///
  /// In zh, this message translates to:
  /// **'云端备份'**
  String get transferCloudSection;

  /// No description provided for @transferWebdav.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 云同步'**
  String get transferWebdav;

  /// No description provided for @transferWebdavSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'把配置文件同步到自建 WebDAV 服务器'**
  String get transferWebdavSubtitle;

  /// No description provided for @transferBusyExporting.
  ///
  /// In zh, this message translates to:
  /// **'正在生成备份文件…'**
  String get transferBusyExporting;

  /// No description provided for @transferBusySaving.
  ///
  /// In zh, this message translates to:
  /// **'等待选择保存位置…'**
  String get transferBusySaving;

  /// No description provided for @transferBusyPickingImport.
  ///
  /// In zh, this message translates to:
  /// **'等待选择备份文件…'**
  String get transferBusyPickingImport;

  /// No description provided for @transferExportEmpty.
  ///
  /// In zh, this message translates to:
  /// **'所选分组没有可导出的内容'**
  String get transferExportEmpty;

  /// No description provided for @transferExportCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消保存'**
  String get transferExportCancelled;

  /// No description provided for @transferExportDone.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {groups} 组、共 {items} 项'**
  String transferExportDone(int groups, int items);

  /// No description provided for @transferExportSkipped.
  ///
  /// In zh, this message translates to:
  /// **'；跳过 {count} 项'**
  String transferExportSkipped(int count);

  /// No description provided for @transferExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败'**
  String get transferExportFailed;

  /// No description provided for @transferImportCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消导入'**
  String get transferImportCancelled;

  /// No description provided for @transferImportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入应用配置'**
  String get transferImportTitle;

  /// No description provided for @transferImportFailedChip.
  ///
  /// In zh, this message translates to:
  /// **'导入失败'**
  String get transferImportFailedChip;

  /// No description provided for @transferImportDoneChip.
  ///
  /// In zh, this message translates to:
  /// **'导入完成'**
  String get transferImportDoneChip;

  /// No description provided for @transferImportSummary.
  ///
  /// In zh, this message translates to:
  /// **'导入汇总：新增 {added} 项，更新 {updated} 项，跳过 {skipped} 项'**
  String transferImportSummary(int added, int updated, int skipped);

  /// No description provided for @transferSourceFile.
  ///
  /// In zh, this message translates to:
  /// **'来源文件：{name}'**
  String transferSourceFile(String name);

  /// No description provided for @transferExportedAt.
  ///
  /// In zh, this message translates to:
  /// **'备份导出于 {time}'**
  String transferExportedAt(String time);

  /// No description provided for @transferOutcomeRow.
  ///
  /// In zh, this message translates to:
  /// **'  + {group} · {detail}'**
  String transferOutcomeRow(String group, String detail);

  /// No description provided for @transferFailedGroupRow.
  ///
  /// In zh, this message translates to:
  /// **'  ! {group}：{error}'**
  String transferFailedGroupRow(String group, String error);

  /// No description provided for @transferNothingChanged.
  ///
  /// In zh, this message translates to:
  /// **'  （备份中的条目本机都已存在，没有需要变更的内容）'**
  String get transferNothingChanged;

  /// No description provided for @transferSubscriptionsNote.
  ///
  /// In zh, this message translates to:
  /// **'包含 {count} 个订阅，请进入订阅管理执行规则更新。'**
  String transferSubscriptionsNote(int count);

  /// No description provided for @transferDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get transferDone;

  /// No description provided for @transferOutcomeAdded.
  ///
  /// In zh, this message translates to:
  /// **'新增 {count}'**
  String transferOutcomeAdded(int count);

  /// No description provided for @transferOutcomeUpdated.
  ///
  /// In zh, this message translates to:
  /// **'更新 {count}'**
  String transferOutcomeUpdated(int count);

  /// No description provided for @transferOutcomeSkipped.
  ///
  /// In zh, this message translates to:
  /// **'跳过 {count}'**
  String transferOutcomeSkipped(int count);

  /// No description provided for @transferNoChange.
  ///
  /// In zh, this message translates to:
  /// **'无变化'**
  String get transferNoChange;

  /// No description provided for @transferOutcomeSeparator.
  ///
  /// In zh, this message translates to:
  /// **'，'**
  String get transferOutcomeSeparator;

  /// No description provided for @webdavClearConfig.
  ///
  /// In zh, this message translates to:
  /// **'清空配置'**
  String get webdavClearConfig;

  /// No description provided for @webdavTest.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get webdavTest;

  /// No description provided for @webdavServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get webdavServer;

  /// No description provided for @webdavUsername.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get webdavUsername;

  /// No description provided for @webdavPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get webdavPassword;

  /// No description provided for @webdavPath.
  ///
  /// In zh, this message translates to:
  /// **'远端路径'**
  String get webdavPath;

  /// No description provided for @webdavUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传备份'**
  String get webdavUpload;

  /// No description provided for @webdavDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载恢复'**
  String get webdavDownload;

  /// No description provided for @webdavFooter.
  ///
  /// In zh, this message translates to:
  /// **'「测试连接」会真实发起 WebDAV 请求：PROPFIND 探测目录，不存在则尝试创建。上传与下载走与「备份与迁移」同一份备份格式。{hint}密码只存在内存里，不落盘。'**
  String webdavFooter(String hint);

  /// No description provided for @webdavFooterConnected.
  ///
  /// In zh, this message translates to:
  /// **'连接成功后即可上传或恢复。'**
  String get webdavFooterConnected;

  /// No description provided for @webdavNoConfig.
  ///
  /// In zh, this message translates to:
  /// **'本机没有可备份的配置'**
  String get webdavNoConfig;

  /// No description provided for @webdavUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'上传失败'**
  String get webdavUploadFailed;

  /// No description provided for @webdavNoCloudBackup.
  ///
  /// In zh, this message translates to:
  /// **'云端没有可恢复的备份'**
  String get webdavNoCloudBackup;

  /// No description provided for @webdavRestoreTitle.
  ///
  /// In zh, this message translates to:
  /// **'从云端恢复配置'**
  String get webdavRestoreTitle;

  /// No description provided for @webdavRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败'**
  String get webdavRestoreFailed;

  /// No description provided for @webdavRestoreDone.
  ///
  /// In zh, this message translates to:
  /// **'恢复完成'**
  String get webdavRestoreDone;

  /// No description provided for @webdavRestoreSummary.
  ///
  /// In zh, this message translates to:
  /// **'恢复汇总：新增 {added} 项，更新 {updated} 项，跳过 {skipped} 项'**
  String webdavRestoreSummary(int added, int updated, int skipped);

  /// No description provided for @webdavOutcomeRow.
  ///
  /// In zh, this message translates to:
  /// **'  + {group} · 新增 {added}，跳过 {skipped}'**
  String webdavOutcomeRow(String group, int added, int skipped);

  /// No description provided for @webdavNothingChanged.
  ///
  /// In zh, this message translates to:
  /// **'  （云端备份与本机一致，没有需要变更的内容）'**
  String get webdavNothingChanged;

  /// No description provided for @webdavHintIdle.
  ///
  /// In zh, this message translates to:
  /// **'配置服务器信息后可测试连接'**
  String get webdavHintIdle;

  /// No description provided for @webdavHintConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在握手，请稍候'**
  String get webdavHintConnecting;

  /// No description provided for @webdavHintConnected.
  ///
  /// In zh, this message translates to:
  /// **'可上传备份或从云端恢复配置'**
  String get webdavHintConnected;

  /// No description provided for @webdavHintFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查地址、账号与证书后重试'**
  String get webdavHintFailed;

  /// No description provided for @backupGroupProviders.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DNS 服务商'**
  String get backupGroupProviders;

  /// No description provided for @backupGroupProvidersDesc.
  ///
  /// In zh, this message translates to:
  /// **'DoH、DoT 服务商与解析配置'**
  String get backupGroupProvidersDesc;

  /// No description provided for @backupGroupBootstrap.
  ///
  /// In zh, this message translates to:
  /// **'自定义 Bootstrap IP'**
  String get backupGroupBootstrap;

  /// No description provided for @backupGroupBootstrapDesc.
  ///
  /// In zh, this message translates to:
  /// **'引导 DNS 节点与启用状态'**
  String get backupGroupBootstrapDesc;

  /// No description provided for @backupGroupCache.
  ///
  /// In zh, this message translates to:
  /// **'DNS 缓存策略'**
  String get backupGroupCache;

  /// No description provided for @backupGroupCacheDesc.
  ///
  /// In zh, this message translates to:
  /// **'DNS 缓存开关、预设与 TTL 控制'**
  String get backupGroupCacheDesc;

  /// No description provided for @backupGroupOutbound.
  ///
  /// In zh, this message translates to:
  /// **'出站代理配置'**
  String get backupGroupOutbound;

  /// No description provided for @backupGroupOutboundDesc.
  ///
  /// In zh, this message translates to:
  /// **'SOCKS5 / HTTP 代理与代理应用，不含账号密码'**
  String get backupGroupOutboundDesc;

  /// No description provided for @backupGroupSubscriptions.
  ///
  /// In zh, this message translates to:
  /// **'网络规则订阅'**
  String get backupGroupSubscriptions;

  /// No description provided for @backupGroupSubscriptionsDesc.
  ///
  /// In zh, this message translates to:
  /// **'订阅源链接、镜像加速与自动更新'**
  String get backupGroupSubscriptionsDesc;

  /// No description provided for @backupGroupDomainRules.
  ///
  /// In zh, this message translates to:
  /// **'自定义屏蔽域名规则'**
  String get backupGroupDomainRules;

  /// No description provided for @backupGroupDomainRulesDesc.
  ///
  /// In zh, this message translates to:
  /// **'手动添加的域名屏蔽规则及状态'**
  String get backupGroupDomainRulesDesc;

  /// No description provided for @backupGroupRewriteDomain.
  ///
  /// In zh, this message translates to:
  /// **'自定义复写域名规则'**
  String get backupGroupRewriteDomain;

  /// No description provided for @backupGroupRewriteDomainDesc.
  ///
  /// In zh, this message translates to:
  /// **'IPv4 / IPv6 域名覆写规则'**
  String get backupGroupRewriteDomainDesc;

  /// No description provided for @backupGroupRewriteCname.
  ///
  /// In zh, this message translates to:
  /// **'自定义复写 CNAME 规则'**
  String get backupGroupRewriteCname;

  /// No description provided for @backupGroupRewriteCnameDesc.
  ///
  /// In zh, this message translates to:
  /// **'CNAME 域名覆写规则'**
  String get backupGroupRewriteCnameDesc;

  /// No description provided for @backupGroupAddressRules.
  ///
  /// In zh, this message translates to:
  /// **'自定义屏蔽地址规则'**
  String get backupGroupAddressRules;

  /// No description provided for @backupGroupAddressRulesDesc.
  ///
  /// In zh, this message translates to:
  /// **'URL 路径屏蔽规则'**
  String get backupGroupAddressRulesDesc;

  /// No description provided for @backupGroupExcluded.
  ///
  /// In zh, this message translates to:
  /// **'排除应用名单'**
  String get backupGroupExcluded;

  /// No description provided for @backupGroupExcludedDesc.
  ///
  /// In zh, this message translates to:
  /// **'绕过过滤使用系统 DNS 的应用'**
  String get backupGroupExcludedDesc;

  /// No description provided for @backupGroupBlocked.
  ///
  /// In zh, this message translates to:
  /// **'禁止联网名单'**
  String get backupGroupBlocked;

  /// No description provided for @backupGroupBlockedDesc.
  ///
  /// In zh, this message translates to:
  /// **'服务运行时禁止联网的应用'**
  String get backupGroupBlockedDesc;

  /// No description provided for @backupGroupAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'应用独立规则与放行'**
  String get backupGroupAllowlist;

  /// No description provided for @backupGroupAllowlistDesc.
  ///
  /// In zh, this message translates to:
  /// **'单应用放行规则与域名白名单'**
  String get backupGroupAllowlistDesc;

  /// No description provided for @backupGroupHttpInspection.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 抓包检测配置'**
  String get backupGroupHttpInspection;

  /// No description provided for @backupGroupHttpInspectionDesc.
  ///
  /// In zh, this message translates to:
  /// **'流量抓包开关与目标应用名单'**
  String get backupGroupHttpInspectionDesc;

  /// No description provided for @backupGroupAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观与界面个性化'**
  String get backupGroupAppearance;

  /// No description provided for @backupGroupAppearanceDesc.
  ///
  /// In zh, this message translates to:
  /// **'主题风格、组件透明度与标语'**
  String get backupGroupAppearanceDesc;

  /// No description provided for @backupGroupSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统与通用设置'**
  String get backupGroupSystem;

  /// No description provided for @backupGroupSystemDesc.
  ///
  /// In zh, this message translates to:
  /// **'局域网绕行、日志模式、语言与通知'**
  String get backupGroupSystemDesc;

  /// No description provided for @webdavUploadedCount.
  ///
  /// In zh, this message translates to:
  /// **'已上传 {groups} 组、共 {items} 项'**
  String webdavUploadedCount(int groups, int items);

  /// No description provided for @agentApiEnabled.
  ///
  /// In zh, this message translates to:
  /// **'AI 分析已启用'**
  String get agentApiEnabled;

  /// No description provided for @agentApiDisabled.
  ///
  /// In zh, this message translates to:
  /// **'AI 分析未启用'**
  String get agentApiDisabled;

  /// No description provided for @agentApiNoProvider.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置 AI 厂商；请先在「AI 厂商管理」中添加并填写 API Key。'**
  String get agentApiNoProvider;

  /// No description provided for @agentApiCurrentProvider.
  ///
  /// In zh, this message translates to:
  /// **'当前厂商：{name} · {model}'**
  String agentApiCurrentProvider(String name, String model);

  /// No description provided for @agentApiNoModel.
  ///
  /// In zh, this message translates to:
  /// **'未选择模型'**
  String get agentApiNoModel;

  /// No description provided for @agentApiKeyConfigured.
  ///
  /// In zh, this message translates to:
  /// **'密钥已配置'**
  String get agentApiKeyConfigured;

  /// No description provided for @agentApiTemperature.
  ///
  /// In zh, this message translates to:
  /// **'温度 {value}'**
  String agentApiTemperature(String value);

  /// No description provided for @agentApiProviderChip.
  ///
  /// In zh, this message translates to:
  /// **'请求由你的厂商处理'**
  String get agentApiProviderChip;

  /// No description provided for @agentApiReadyHintOn.
  ///
  /// In zh, this message translates to:
  /// **'补全厂商与密钥后，日志页就能直接发起分析。'**
  String get agentApiReadyHintOn;

  /// No description provided for @agentApiReadyHintOff.
  ///
  /// In zh, this message translates to:
  /// **'开启后即可在日志页直接发起分析。'**
  String get agentApiReadyHintOff;

  /// No description provided for @agentApiSectionProvider.
  ///
  /// In zh, this message translates to:
  /// **'厂商与参数'**
  String get agentApiSectionProvider;

  /// No description provided for @agentApiProvidersSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个已配置厂商 · 选择接口与模型'**
  String agentApiProvidersSubtitle(int count);

  /// No description provided for @agentParamsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词与采样温度'**
  String get agentParamsSubtitle;

  /// No description provided for @agentApiSectionTest.
  ///
  /// In zh, this message translates to:
  /// **'功能测试'**
  String get agentApiSectionTest;

  /// No description provided for @agentApiTestDomain.
  ///
  /// In zh, this message translates to:
  /// **'分析一个域名'**
  String get agentApiTestDomain;

  /// No description provided for @agentApiTestDomainSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用示例域名真实调用模型，检查安全风险与处置建议'**
  String get agentApiTestDomainSubtitle;

  /// No description provided for @agentApiTestTraffic.
  ///
  /// In zh, this message translates to:
  /// **'分析最近流量'**
  String get agentApiTestTraffic;

  /// No description provided for @agentApiTestTrafficSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'汇总最近 DNS 与 HTTPS 记录后真实调用模型'**
  String get agentApiTestTrafficSubtitle;

  /// No description provided for @agentApiTestFooterReady.
  ///
  /// In zh, this message translates to:
  /// **'两项都会真实请求你配置的厂商并消耗额度。'**
  String get agentApiTestFooterReady;

  /// No description provided for @agentApiTestFooterNotReady.
  ///
  /// In zh, this message translates to:
  /// **'当前配置不完整（未启用或缺少 API Key），点击会提示先补配置。'**
  String get agentApiTestFooterNotReady;

  /// No description provided for @agentApiSectionEntries.
  ///
  /// In zh, this message translates to:
  /// **'分析入口'**
  String get agentApiSectionEntries;

  /// No description provided for @agentApiCacheTable.
  ///
  /// In zh, this message translates to:
  /// **'DNS 缓存表'**
  String get agentApiCacheTable;

  /// No description provided for @agentApiCacheTableSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'点按任意一行，分析该域名的安全风险'**
  String get agentApiCacheTableSubtitle;

  /// No description provided for @agentApiRequests.
  ///
  /// In zh, this message translates to:
  /// **'请求记录'**
  String get agentApiRequests;

  /// No description provided for @agentApiRequestsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'打开一条请求的详情，底部可分析该域名'**
  String get agentApiRequestsSubtitle;

  /// No description provided for @agentApiDashboard.
  ///
  /// In zh, this message translates to:
  /// **'日志仪表盘'**
  String get agentApiDashboard;

  /// No description provided for @agentApiDashboardSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'「AI 研判」卡片可对最近流量发起整体分析'**
  String get agentApiDashboardSubtitle;

  /// No description provided for @agentApiEntriesFooter.
  ///
  /// In zh, this message translates to:
  /// **'分析结果里的域名可以一键写入白名单或屏蔽规则，写入后启动 DNS VPN 生效。'**
  String get agentApiEntriesFooter;

  /// No description provided for @agentApiSectionReset.
  ///
  /// In zh, this message translates to:
  /// **'重置设置'**
  String get agentApiSectionReset;

  /// No description provided for @agentApiResetItem.
  ///
  /// In zh, this message translates to:
  /// **'恢复出厂默认配置'**
  String get agentApiResetItem;

  /// No description provided for @agentApiResetSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'将清空厂商、API Key、提示词与温度'**
  String get agentApiResetSubtitle;

  /// No description provided for @agentApiFooter.
  ///
  /// In zh, this message translates to:
  /// **'AI 分析用于辅助研判，不会自动修改规则；所有请求由你配置的厂商处理，密钥只存在本机。'**
  String get agentApiFooter;

  /// No description provided for @agentApiResetTitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认配置？'**
  String get agentApiResetTitle;

  /// No description provided for @agentApiResetBody.
  ///
  /// In zh, this message translates to:
  /// **'此操作将把所有 AI 分析参数、API Key 与系统提示词恢复为默认设置。'**
  String get agentApiResetBody;

  /// No description provided for @agentApiResetConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认恢复'**
  String get agentApiResetConfirm;

  /// No description provided for @agentProvidersTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 厂商管理'**
  String get agentProvidersTitle;

  /// No description provided for @agentProvidersAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加自定义厂商'**
  String get agentProvidersAdd;

  /// No description provided for @agentProvidersIntro.
  ///
  /// In zh, this message translates to:
  /// **'点选下方预设厂商会自动预填接口地址；模型名请在编辑页点「拉取模型」从厂商真实返回的列表里选。编辑时若 API Key 留空则保留原密钥。密钥以旧版同一套掩码混淆后存在本机，不额外落明文。'**
  String get agentProvidersIntro;

  /// No description provided for @agentProvidersMine.
  ///
  /// In zh, this message translates to:
  /// **'我的厂商'**
  String get agentProvidersMine;

  /// No description provided for @agentProvidersEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无厂商'**
  String get agentProvidersEmpty;

  /// No description provided for @agentProvidersEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从下方预设厂商目录点选，或点击右上角添加自定义厂商'**
  String get agentProvidersEmptySubtitle;

  /// No description provided for @agentProvidersRow.
  ///
  /// In zh, this message translates to:
  /// **'{model} · {baseUrl} · {key}'**
  String agentProvidersRow(String model, String baseUrl, String key);

  /// No description provided for @agentProvidersKeyConfigured.
  ///
  /// In zh, this message translates to:
  /// **'密钥已配置'**
  String get agentProvidersKeyConfigured;

  /// No description provided for @agentProvidersKeyMissing.
  ///
  /// In zh, this message translates to:
  /// **'缺少密钥'**
  String get agentProvidersKeyMissing;

  /// No description provided for @agentProvidersFooter.
  ///
  /// In zh, this message translates to:
  /// **'点一行可切换当前生效厂商；切换会把接口地址、密钥与模型同步到旧版的四个平铺键，避免新版界面与旧版读取来源不一致。'**
  String get agentProvidersFooter;

  /// No description provided for @agentProvidersAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加'**
  String get agentProvidersAdded;

  /// No description provided for @agentProvidersDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除厂商'**
  String get agentProvidersDeleteTitle;

  /// No description provided for @agentProvidersDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除「{name}」吗？相关 API Key 也会从本机移除。'**
  String agentProvidersDeleteBody(String name);

  /// No description provided for @agentEditorAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加厂商'**
  String get agentEditorAddTitle;

  /// No description provided for @agentEditorEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑厂商'**
  String get agentEditorEditTitle;

  /// No description provided for @agentEditorPaste.
  ///
  /// In zh, this message translates to:
  /// **'从剪贴板识别'**
  String get agentEditorPaste;

  /// No description provided for @agentEditorName.
  ///
  /// In zh, this message translates to:
  /// **'厂商名称'**
  String get agentEditorName;

  /// No description provided for @agentEditorBaseUrl.
  ///
  /// In zh, this message translates to:
  /// **'接口地址'**
  String get agentEditorBaseUrl;

  /// No description provided for @agentEditorModel.
  ///
  /// In zh, this message translates to:
  /// **'模型名称'**
  String get agentEditorModel;

  /// No description provided for @agentEditorModelHint.
  ///
  /// In zh, this message translates to:
  /// **'点「拉取模型」从厂商返回的列表里选'**
  String get agentEditorModelHint;

  /// No description provided for @agentEditorKeyKeep.
  ///
  /// In zh, this message translates to:
  /// **'留空则保留原密钥'**
  String get agentEditorKeyKeep;

  /// No description provided for @agentEditorKeyLocal.
  ///
  /// In zh, this message translates to:
  /// **'仅保存在本机（旧版同一套掩码）'**
  String get agentEditorKeyLocal;

  /// No description provided for @agentEditorFetching.
  ///
  /// In zh, this message translates to:
  /// **'请求中…'**
  String get agentEditorFetching;

  /// No description provided for @agentEditorFetch.
  ///
  /// In zh, this message translates to:
  /// **'拉取模型'**
  String get agentEditorFetch;

  /// No description provided for @agentEditorTest.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get agentEditorTest;

  /// No description provided for @agentEditorErrorRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写名称、以 http(s) 开头的接口地址与模型名'**
  String get agentEditorErrorRequired;

  /// No description provided for @agentEditorErrorBaseUrl.
  ///
  /// In zh, this message translates to:
  /// **'请先填写接口地址'**
  String get agentEditorErrorBaseUrl;

  /// No description provided for @agentEditorErrorTestNeeds.
  ///
  /// In zh, this message translates to:
  /// **'测试连接需要接口地址与模型名'**
  String get agentEditorErrorTestNeeds;

  /// No description provided for @agentEditorFetched.
  ///
  /// In zh, this message translates to:
  /// **'拉取到 {count} 个模型，点下方标签选择'**
  String agentEditorFetched(int count);

  /// No description provided for @agentEditorFetchFailed.
  ///
  /// In zh, this message translates to:
  /// **'拉取模型失败：{error}'**
  String agentEditorFetchFailed(String error);

  /// No description provided for @agentEditorConnected.
  ///
  /// In zh, this message translates to:
  /// **'连接成功：{model}'**
  String agentEditorConnected(String model);

  /// No description provided for @agentEditorUsage.
  ///
  /// In zh, this message translates to:
  /// **'，用量 {tokens} tokens'**
  String agentEditorUsage(int tokens);

  /// No description provided for @agentEditorConnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{error}'**
  String agentEditorConnectFailed(String error);

  /// No description provided for @agentParamsTitle.
  ///
  /// In zh, this message translates to:
  /// **'参数与提示词'**
  String get agentParamsTitle;

  /// No description provided for @agentParamsPromptSection.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词'**
  String get agentParamsPromptSection;

  /// No description provided for @agentParamsPromptItem.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词设定'**
  String get agentParamsPromptItem;

  /// No description provided for @agentParamsPromptUnset.
  ///
  /// In zh, this message translates to:
  /// **'未设置（将使用各分析场景的内置提示词）'**
  String get agentParamsPromptUnset;

  /// No description provided for @agentParamsPromptFooter.
  ///
  /// In zh, this message translates to:
  /// **'留空时域名分析与流量分析各用自己那份内置提示词；填写后两者都以此为准。'**
  String get agentParamsPromptFooter;

  /// No description provided for @agentParamsPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：你是一名网络安全与 DNS 威胁情报专家……'**
  String get agentParamsPromptHint;

  /// No description provided for @agentParamsTemperatureSection.
  ///
  /// In zh, this message translates to:
  /// **'采样温度（Temperature）'**
  String get agentParamsTemperatureSection;

  /// No description provided for @agentParamsTemperatureItem.
  ///
  /// In zh, this message translates to:
  /// **'生成随机度与创造性'**
  String get agentParamsTemperatureItem;

  /// No description provided for @agentParamsTemperatureFooter.
  ///
  /// In zh, this message translates to:
  /// **'安全研判建议 0.2–0.4：温度越低，结论越稳定、越少自由发挥。'**
  String get agentParamsTemperatureFooter;

  /// No description provided for @agentParamsTemperatureStrict.
  ///
  /// In zh, this message translates to:
  /// **'严谨精确（适合安全分析与结构化输出）'**
  String get agentParamsTemperatureStrict;

  /// No description provided for @agentParamsTemperatureBalanced.
  ///
  /// In zh, this message translates to:
  /// **'平衡适中（推荐日常综合分析场景）'**
  String get agentParamsTemperatureBalanced;

  /// No description provided for @agentParamsTemperatureWild.
  ///
  /// In zh, this message translates to:
  /// **'发散多变（输出内容更为丰富自由）'**
  String get agentParamsTemperatureWild;

  /// No description provided for @agentParamsTemplateSecurity.
  ///
  /// In zh, this message translates to:
  /// **'安全威胁分析'**
  String get agentParamsTemplateSecurity;

  /// No description provided for @agentParamsTemplateTechnical.
  ///
  /// In zh, this message translates to:
  /// **'极简技术审查'**
  String get agentParamsTemplateTechnical;

  /// No description provided for @agentParamsTemplatePrivacy.
  ///
  /// In zh, this message translates to:
  /// **'隐私与遥测审查'**
  String get agentParamsTemplatePrivacy;

  /// No description provided for @agentSheetCopied.
  ///
  /// In zh, this message translates to:
  /// **'分析结果已复制到剪贴板'**
  String get agentSheetCopied;

  /// No description provided for @agentSheetRuleAdded.
  ///
  /// In zh, this message translates to:
  /// **'已写入{kind}，启动 DNS VPN 后生效'**
  String agentSheetRuleAdded(String kind);

  /// No description provided for @agentSheetRuleExists.
  ///
  /// In zh, this message translates to:
  /// **'该域名已在{kind}中'**
  String agentSheetRuleExists(String kind);

  /// No description provided for @agentSheetFooter.
  ///
  /// In zh, this message translates to:
  /// **'AI 只做研判，不会自动修改规则；结论仅供参考。请求由你配置的厂商处理，密钥只存在本机。'**
  String get agentSheetFooter;

  /// No description provided for @agentSheetDisabledTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 分析功能已关闭'**
  String get agentSheetDisabledTitle;

  /// No description provided for @agentSheetDisabledBody.
  ///
  /// In zh, this message translates to:
  /// **'AI 分析服务当前处于停用状态。你可以直接在此开启，或前往设置页面管理。'**
  String get agentSheetDisabledBody;

  /// No description provided for @agentSheetEnableAndStart.
  ///
  /// In zh, this message translates to:
  /// **'开启 AI 分析并继续'**
  String get agentSheetEnableAndStart;

  /// No description provided for @agentSheetNoKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'未配置 API 密钥'**
  String get agentSheetNoKeyTitle;

  /// No description provided for @agentSheetNoKeyBody.
  ///
  /// In zh, this message translates to:
  /// **'需配置 OpenAI 兼容的 API 密钥后，方可使用 AI 域名与流量分析功能。'**
  String get agentSheetNoKeyBody;

  /// No description provided for @agentSheetGoConfigure.
  ///
  /// In zh, this message translates to:
  /// **'前往配置'**
  String get agentSheetGoConfigure;

  /// No description provided for @agentSheetRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在进行 AI 分析…'**
  String get agentSheetRunning;

  /// No description provided for @agentSheetModel.
  ///
  /// In zh, this message translates to:
  /// **'模型 {model}'**
  String agentSheetModel(String model);

  /// No description provided for @agentSheetUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get agentSheetUnknown;

  /// No description provided for @agentSheetFailed.
  ///
  /// In zh, this message translates to:
  /// **'分析失败'**
  String get agentSheetFailed;

  /// No description provided for @agentSheetUnknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get agentSheetUnknownError;

  /// No description provided for @agentSheetCheckSettings.
  ///
  /// In zh, this message translates to:
  /// **'检查设置'**
  String get agentSheetCheckSettings;

  /// No description provided for @agentSheetNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'尚未分析'**
  String get agentSheetNotStarted;

  /// No description provided for @agentSheetSuperseded.
  ///
  /// In zh, this message translates to:
  /// **'结果已被新的分析取代'**
  String get agentSheetSuperseded;

  /// No description provided for @agentSheetStartHint.
  ///
  /// In zh, this message translates to:
  /// **'点下面的按钮开始分析。'**
  String get agentSheetStartHint;

  /// No description provided for @agentSheetSupersededHint.
  ///
  /// In zh, this message translates to:
  /// **'另一个分析请求覆盖了这次会话，重新分析可以取回结论。'**
  String get agentSheetSupersededHint;

  /// No description provided for @agentSheetStart.
  ///
  /// In zh, this message translates to:
  /// **'开始分析'**
  String get agentSheetStart;

  /// No description provided for @agentSheetHideDigest.
  ///
  /// In zh, this message translates to:
  /// **'收起送检摘要'**
  String get agentSheetHideDigest;

  /// No description provided for @agentSheetShowDigest.
  ///
  /// In zh, this message translates to:
  /// **'查看送检摘要'**
  String get agentSheetShowDigest;

  /// No description provided for @agentSheetAddBlock.
  ///
  /// In zh, this message translates to:
  /// **'加入屏蔽规则'**
  String get agentSheetAddBlock;

  /// No description provided for @agentSheetCopyResult.
  ///
  /// In zh, this message translates to:
  /// **'复制结果'**
  String get agentSheetCopyResult;

  /// No description provided for @agentSheetReanalyze.
  ///
  /// In zh, this message translates to:
  /// **'重新分析'**
  String get agentSheetReanalyze;

  /// No description provided for @agentTargetDomainTitle.
  ///
  /// In zh, this message translates to:
  /// **'域名安全分析'**
  String get agentTargetDomainTitle;

  /// No description provided for @agentTargetTrafficTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络流量分析'**
  String get agentTargetTrafficTitle;

  /// No description provided for @agentTargetTrafficSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'基于近期 DNS 与 HTTPS 监控数据'**
  String get agentTargetTrafficSubtitle;

  /// No description provided for @agentApiChipKeyMissing.
  ///
  /// In zh, this message translates to:
  /// **'缺少 API Key'**
  String get agentApiChipKeyMissing;

  /// No description provided for @agentSheetAddAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'加入白名单'**
  String get agentSheetAddAllowlist;

  /// No description provided for @featureHubLongPress.
  ///
  /// In zh, this message translates to:
  /// **'可长按'**
  String get featureHubLongPress;

  /// No description provided for @outboundSaved.
  ///
  /// In zh, this message translates to:
  /// **'出站代理设置已保存，启动隧道后生效'**
  String get outboundSaved;

  /// No description provided for @outboundSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String outboundSaveFailed(String error);

  /// No description provided for @outboundResetTitle.
  ///
  /// In zh, this message translates to:
  /// **'重置出站代理？'**
  String get outboundResetTitle;

  /// No description provided for @outboundResetBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除全部九个出站代理键（包括已加密保存的账号与密码）。'**
  String get outboundResetBody;

  /// No description provided for @outboundResetDone.
  ///
  /// In zh, this message translates to:
  /// **'已重置出站代理'**
  String get outboundResetDone;

  /// No description provided for @outboundResetMenu.
  ///
  /// In zh, this message translates to:
  /// **'重置出站代理'**
  String get outboundResetMenu;

  /// No description provided for @outboundSectionProxy.
  ///
  /// In zh, this message translates to:
  /// **'代理'**
  String get outboundSectionProxy;

  /// No description provided for @outboundEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用出站代理功能'**
  String get outboundEnable;

  /// No description provided for @outboundApp.
  ///
  /// In zh, this message translates to:
  /// **'代理应用'**
  String get outboundApp;

  /// No description provided for @outboundHostLabel.
  ///
  /// In zh, this message translates to:
  /// **'地址'**
  String get outboundHostLabel;

  /// No description provided for @outboundHostHelper.
  ///
  /// In zh, this message translates to:
  /// **'仅支持 127.0.0.1 或 ::1'**
  String get outboundHostHelper;

  /// No description provided for @outboundUsernameLabel.
  ///
  /// In zh, this message translates to:
  /// **'账号（可选）'**
  String get outboundUsernameLabel;

  /// No description provided for @outboundPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'密码（可选）'**
  String get outboundPasswordLabel;

  /// No description provided for @outboundHttpFooter.
  ///
  /// In zh, this message translates to:
  /// **'HTTP CONNECT 不支持 UDP；UDP 会被严格阻断，QUIC 可回退到 TCP。代理应用本身将绕过 DITING。'**
  String get outboundHttpFooter;

  /// No description provided for @outboundSocksFooter.
  ///
  /// In zh, this message translates to:
  /// **'SOCKS5 通过 UDP ASSOCIATE 转发 UDP。代理应用本身将绕过 DITING，防止流量环路。'**
  String get outboundSocksFooter;

  /// No description provided for @outboundStatusOff.
  ///
  /// In zh, this message translates to:
  /// **'未运行'**
  String get outboundStatusOff;

  /// No description provided for @outboundStatusConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在连接'**
  String get outboundStatusConnecting;

  /// No description provided for @outboundStatusReady.
  ///
  /// In zh, this message translates to:
  /// **'代理可用'**
  String get outboundStatusReady;

  /// No description provided for @outboundStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get outboundStatusFailed;

  /// No description provided for @outboundFooterError.
  ///
  /// In zh, this message translates to:
  /// **'引擎上报的错误会一直保留到下一次隧道启动，便于回看原因。'**
  String get outboundFooterError;

  /// No description provided for @outboundFooterReady.
  ///
  /// In zh, this message translates to:
  /// **'引擎已确认代理可用；修改配置后需要重启隧道才会重新校验。'**
  String get outboundFooterReady;

  /// No description provided for @outboundFooterConnecting.
  ///
  /// In zh, this message translates to:
  /// **'隧道启动时会校验代理连通性，结果会实时显示在这里。'**
  String get outboundFooterConnecting;

  /// No description provided for @outboundAppsTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择代理应用'**
  String get outboundAppsTitle;

  /// No description provided for @outboundAppsIntro.
  ///
  /// In zh, this message translates to:
  /// **'选择提供本地代理端口的应用。代理应用本身会绕过 DITING。端口由该应用绑定，谛听无法代它监听。'**
  String get outboundAppsIntro;

  /// No description provided for @outboundAppsCount.
  ///
  /// In zh, this message translates to:
  /// **'已安装应用（{count}）'**
  String outboundAppsCount(int count);

  /// No description provided for @outboundAppsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'设备上没有可选的代理应用'**
  String get outboundAppsEmpty;

  /// No description provided for @resolutionSingleDesc.
  ///
  /// In zh, this message translates to:
  /// **'所有查询都发往当前选中的服务商。'**
  String get resolutionSingleDesc;

  /// No description provided for @resolutionSmartDesc.
  ///
  /// In zh, this message translates to:
  /// **'按历史成功率挑一个，失败后自动换下一个。'**
  String get resolutionSmartDesc;

  /// No description provided for @resolutionParallelDesc.
  ///
  /// In zh, this message translates to:
  /// **'同时向所有服务商发起，取最先返回的结果。'**
  String get resolutionParallelDesc;

  /// No description provided for @resolutionPrimaryBackupDesc.
  ///
  /// In zh, this message translates to:
  /// **'主服务商优先，超时后才动备用。'**
  String get resolutionPrimaryBackupDesc;

  /// No description provided for @resolutionProtocolSavedError.
  ///
  /// In zh, this message translates to:
  /// **'协议已保存，运行中的服务未能更新：{error}'**
  String resolutionProtocolSavedError(String error);

  /// No description provided for @resolutionBuiltinProtocol.
  ///
  /// In zh, this message translates to:
  /// **'内置服务协议'**
  String get resolutionBuiltinProtocol;

  /// No description provided for @resolutionBuiltinNote.
  ///
  /// In zh, this message translates to:
  /// **'仅切换内置服务商使用的 DNS / DoT / DoH 协议；自定义服务商按自身协议展示。'**
  String get resolutionBuiltinNote;

  /// No description provided for @resolutionConfigSection.
  ///
  /// In zh, this message translates to:
  /// **'模式配置'**
  String get resolutionConfigSection;

  /// No description provided for @resolutionConfigFooter.
  ///
  /// In zh, this message translates to:
  /// **'解析模式与竞速服务商保存在当前工作模式的数据集里（普通 / 极速 / 服务器各自独立）。'**
  String get resolutionConfigFooter;

  /// No description provided for @resolutionNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get resolutionNotConfigured;

  /// No description provided for @resolutionProviderCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个服务商'**
  String resolutionProviderCount(int count);

  /// No description provided for @resolutionPickerTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择解析模式'**
  String get resolutionPickerTitle;

  /// No description provided for @resolutionMinProviders.
  ///
  /// In zh, this message translates to:
  /// **'至少保留 2 家服务商'**
  String get resolutionMinProviders;

  /// No description provided for @resolutionSingleHint.
  ///
  /// In zh, this message translates to:
  /// **'选择一个服务商作为唯一查询出口。'**
  String get resolutionSingleHint;

  /// No description provided for @resolutionRaceHint.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 家服务商，至少需要 2 家。'**
  String resolutionRaceHint(int count);

  /// No description provided for @resolutionReady.
  ///
  /// In zh, this message translates to:
  /// **'已就绪'**
  String get resolutionReady;

  /// No description provided for @resolutionPending.
  ///
  /// In zh, this message translates to:
  /// **'待配置'**
  String get resolutionPending;

  /// No description provided for @resolutionSectionSingle.
  ///
  /// In zh, this message translates to:
  /// **'查询服务'**
  String get resolutionSectionSingle;

  /// No description provided for @resolutionSectionSmart.
  ///
  /// In zh, this message translates to:
  /// **'候选服务'**
  String get resolutionSectionSmart;

  /// No description provided for @resolutionSectionParallel.
  ///
  /// In zh, this message translates to:
  /// **'同时查询的服务'**
  String get resolutionSectionParallel;

  /// No description provided for @resolutionSectionBackup.
  ///
  /// In zh, this message translates to:
  /// **'依次尝试的服务'**
  String get resolutionSectionBackup;

  /// No description provided for @resolutionNoProviders.
  ///
  /// In zh, this message translates to:
  /// **'暂无此协议的服务商'**
  String get resolutionNoProviders;

  /// No description provided for @resolutionMoveUp.
  ///
  /// In zh, this message translates to:
  /// **'上移'**
  String get resolutionMoveUp;

  /// No description provided for @resolutionMoveDown.
  ///
  /// In zh, this message translates to:
  /// **'下移'**
  String get resolutionMoveDown;

  /// No description provided for @outboundNoApp.
  ///
  /// In zh, this message translates to:
  /// **'未选择'**
  String get outboundNoApp;

  /// No description provided for @appRulesSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存，启动 DNS VPN 后生效'**
  String get appRulesSaved;

  /// No description provided for @appRulesClearAllTooltip.
  ///
  /// In zh, this message translates to:
  /// **'清空全部放行规则'**
  String get appRulesClearAllTooltip;

  /// No description provided for @appRulesMasterSection.
  ///
  /// In zh, this message translates to:
  /// **'总开关'**
  String get appRulesMasterSection;

  /// No description provided for @appRulesMasterToggle.
  ///
  /// In zh, this message translates to:
  /// **'启用单应用域名放行'**
  String get appRulesMasterToggle;

  /// No description provided for @appRulesNoConfigured.
  ///
  /// In zh, this message translates to:
  /// **'暂未配置任何应用独立规则'**
  String get appRulesNoConfigured;

  /// No description provided for @appRulesConfiguredSummary.
  ///
  /// In zh, this message translates to:
  /// **'已配置 {apps} 个应用 · 放行 {domains} 个域名'**
  String appRulesConfiguredSummary(int apps, int domains);

  /// No description provided for @appRulesMasterFooter.
  ///
  /// In zh, this message translates to:
  /// **'为指定应用深度定制网络与解析控制：网络层白名单隔离（只放行列出的域名）、DNS 专属黑/白名单与「默认拦截全部外联」。进入某个应用可分别配置，保存后启动 DNS VPN 时下发。'**
  String get appRulesMasterFooter;

  /// No description provided for @appRulesAppsCount.
  ///
  /// In zh, this message translates to:
  /// **'应用（{count}）'**
  String appRulesAppsCount(int count);

  /// No description provided for @appRulesNoConfigurableApps.
  ///
  /// In zh, this message translates to:
  /// **'设备上没有可配置的应用'**
  String get appRulesNoConfigurableApps;

  /// No description provided for @appRulesFooterNoApps.
  ///
  /// In zh, this message translates to:
  /// **'未读取到任何已安装应用，无法配置应用独立规则。'**
  String get appRulesFooterNoApps;

  /// No description provided for @appRulesFooterSave.
  ///
  /// In zh, this message translates to:
  /// **'保存后写入 app_allowlist_enabled 与 app_allowlist_rules_json，启动 DNS VPN 时下发给引擎。'**
  String get appRulesFooterSave;

  /// No description provided for @appRulesAddAllowDomain.
  ///
  /// In zh, this message translates to:
  /// **'添加放行域名'**
  String get appRulesAddAllowDomain;

  /// No description provided for @appRulesAppSection.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get appRulesAppSection;

  /// No description provided for @appRulesBackToList.
  ///
  /// In zh, this message translates to:
  /// **'返回应用列表'**
  String get appRulesBackToList;

  /// No description provided for @appRulesClearAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空全部放行规则？'**
  String get appRulesClearAllTitle;

  /// No description provided for @appRulesClearAllBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除所有应用的专属放行域名。保存后生效，黑名单与全阻断设置不受影响。'**
  String get appRulesClearAllBody;

  /// No description provided for @appRulesRuleExists.
  ///
  /// In zh, this message translates to:
  /// **'规则已存在或规则库不可用'**
  String get appRulesRuleExists;

  /// No description provided for @appRulesRuleAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加{kind}规则'**
  String appRulesRuleAdded(String kind);

  /// No description provided for @appRulesDeleteRuleTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除这条规则？'**
  String get appRulesDeleteRuleTitle;

  /// No description provided for @appRulesFullBlockOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启全外联拦截模式'**
  String get appRulesFullBlockOn;

  /// No description provided for @appRulesFullBlockOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭全外联拦截模式'**
  String get appRulesFullBlockOff;

  /// No description provided for @appRulesAddDnsRule.
  ///
  /// In zh, this message translates to:
  /// **'添加 DNS 规则'**
  String get appRulesAddDnsRule;

  /// No description provided for @appRulesDnsScopeIntro.
  ///
  /// In zh, this message translates to:
  /// **'这些规则写入规则库的 block_rule / allow_rule，带 appScope 只对本应用生效，并随规则快照的 appRules 下发，不会扩大成全局拦截。'**
  String get appRulesDnsScopeIntro;

  /// No description provided for @appRulesDnsScopeSection.
  ///
  /// In zh, this message translates to:
  /// **'DNS 专属黑/白名单'**
  String get appRulesDnsScopeSection;

  /// No description provided for @appRulesReadingRules.
  ///
  /// In zh, this message translates to:
  /// **'正在读取规则库'**
  String get appRulesReadingRules;

  /// No description provided for @appRulesWait.
  ///
  /// In zh, this message translates to:
  /// **'稍候'**
  String get appRulesWait;

  /// No description provided for @appRulesRuleDbUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'读不到规则库'**
  String get appRulesRuleDbUnreadable;

  /// No description provided for @appRulesRuleDbUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前环境无法读写规则库'**
  String get appRulesRuleDbUnavailable;

  /// No description provided for @appRulesNoScopedRules.
  ///
  /// In zh, this message translates to:
  /// **'未配置 DNS 专属规则'**
  String get appRulesNoScopedRules;

  /// No description provided for @appRulesNoScopedRulesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'添加后仅对本应用生效，不影响其他应用'**
  String get appRulesNoScopedRulesSubtitle;

  /// No description provided for @appRulesScopedCount.
  ///
  /// In zh, this message translates to:
  /// **'DNS 专属黑/白名单（{count}）'**
  String appRulesScopedCount(int count);

  /// No description provided for @appRulesAllowDomainTitle.
  ///
  /// In zh, this message translates to:
  /// **'专属放行域名（网络层） ({count})'**
  String appRulesAllowDomainTitle(int count);

  /// No description provided for @appRulesNoAllowDomains.
  ///
  /// In zh, this message translates to:
  /// **'未配置网络放行域名'**
  String get appRulesNoAllowDomains;

  /// No description provided for @appRulesNoAllowDomainsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'网络层白名单为空时，该应用不受额外限制'**
  String get appRulesNoAllowDomainsSubtitle;

  /// No description provided for @appRulesAllowDomainFooter.
  ///
  /// In zh, this message translates to:
  /// **'这些域名会写入 app_allowlist_rules_json，由引擎在下一次启动隧道时下发给 setAppAllowlist。'**
  String get appRulesAllowDomainFooter;

  /// No description provided for @appRulesIsolationSection.
  ///
  /// In zh, this message translates to:
  /// **'外联与隔离模式'**
  String get appRulesIsolationSection;

  /// No description provided for @appRulesFullBlockToggle.
  ///
  /// In zh, this message translates to:
  /// **'默认拦截全部外联'**
  String get appRulesFullBlockToggle;

  /// No description provided for @appRulesFullBlockToggleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'开启后阻断该应用的所有网络连接，仅放行白名单'**
  String get appRulesFullBlockToggleSubtitle;

  /// No description provided for @appRulesFullBlockOnTitle.
  ///
  /// In zh, this message translates to:
  /// **'已开启全阻断模式'**
  String get appRulesFullBlockOnTitle;

  /// No description provided for @appRulesFullBlockOnBody.
  ///
  /// In zh, this message translates to:
  /// **'请确保已添加必要的放行白名单，否则应用可能无法联网。'**
  String get appRulesFullBlockOnBody;

  /// No description provided for @providerMgmtDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除 DNS 服务商'**
  String get providerMgmtDeleteTitle;

  /// No description provided for @providerMgmtDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」吗？删除后无法再作为解析服务使用。'**
  String providerMgmtDeleteBody(String name);

  /// No description provided for @providerMgmtTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务商管理'**
  String get providerMgmtTitle;

  /// No description provided for @providerMgmtAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增 DNS 服务商'**
  String get providerMgmtAdd;

  /// No description provided for @providerMgmtCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前用于解析 DNS'**
  String get providerMgmtCurrent;

  /// No description provided for @providerMgmtBuiltin.
  ///
  /// In zh, this message translates to:
  /// **'内置服务商'**
  String get providerMgmtBuiltin;

  /// No description provided for @providerMgmtCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义服务商'**
  String get providerMgmtCustom;

  /// No description provided for @providerMgmtEmptyCustom.
  ///
  /// In zh, this message translates to:
  /// **'暂无自定义服务商'**
  String get providerMgmtEmptyCustom;

  /// No description provided for @providerMgmtEmptyCustomSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'点击右上角「+」添加 DoH、DoT 或传统 DNS 服务'**
  String get providerMgmtEmptyCustomSubtitle;

  /// No description provided for @providerMgmtFooter.
  ///
  /// In zh, this message translates to:
  /// **'内置服务商由应用维护，只能切换；自定义服务商可编辑或删除。'**
  String get providerMgmtFooter;

  /// No description provided for @providerMgmtEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑 DNS 服务商'**
  String get providerMgmtEditTitle;

  /// No description provided for @providerMgmtAddressLabel.
  ///
  /// In zh, this message translates to:
  /// **'地址'**
  String get providerMgmtAddressLabel;

  /// No description provided for @providerMgmtPortLabel.
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get providerMgmtPortLabel;

  /// No description provided for @providerMgmtDohAddressLabel.
  ///
  /// In zh, this message translates to:
  /// **'DoH 地址'**
  String get providerMgmtDohAddressLabel;

  /// No description provided for @providerMgmtNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写名称'**
  String get providerMgmtNameRequired;

  /// No description provided for @providerMgmtDohRequired.
  ///
  /// In zh, this message translates to:
  /// **'DoH 地址需以 https:// 开头'**
  String get providerMgmtDohRequired;

  /// No description provided for @providerMgmtAddressRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写地址'**
  String get providerMgmtAddressRequired;

  /// No description provided for @providerMgmtPortRange.
  ///
  /// In zh, this message translates to:
  /// **'端口需在 1–65535 之间'**
  String get providerMgmtPortRange;

  /// No description provided for @providerMgmtProbeTooltip.
  ///
  /// In zh, this message translates to:
  /// **'测试该服务是否可用'**
  String get providerMgmtProbeTooltip;

  /// No description provided for @providerMgmtProbeOk.
  ///
  /// In zh, this message translates to:
  /// **'可用 · {ms} ms'**
  String providerMgmtProbeOk(int ms);

  /// No description provided for @providerMgmtProbeFailed.
  ///
  /// In zh, this message translates to:
  /// **'不可用：{message}'**
  String providerMgmtProbeFailed(String message);

  /// No description provided for @providerMgmtProbeNoResponse.
  ///
  /// In zh, this message translates to:
  /// **'无响应'**
  String get providerMgmtProbeNoResponse;

  /// No description provided for @notifModeSingle.
  ///
  /// In zh, this message translates to:
  /// **'单一服务'**
  String get notifModeSingle;

  /// No description provided for @notifModeSmart.
  ///
  /// In zh, this message translates to:
  /// **'智能选择'**
  String get notifModeSmart;

  /// No description provided for @notifModeParallel.
  ///
  /// In zh, this message translates to:
  /// **'最快响应'**
  String get notifModeParallel;

  /// No description provided for @notifModeBackup.
  ///
  /// In zh, this message translates to:
  /// **'依次尝试'**
  String get notifModeBackup;

  /// No description provided for @notifRunningMode.
  ///
  /// In zh, this message translates to:
  /// **'运行中 · [{mode}] {count} 个服务商'**
  String notifRunningMode(String mode, int count);

  /// No description provided for @notifRunningProvider.
  ///
  /// In zh, this message translates to:
  /// **'运行中 · {name}'**
  String notifRunningProvider(String name);

  /// No description provided for @notifRunningServer.
  ///
  /// In zh, this message translates to:
  /// **'运行中 · {name} · 端口 {port}'**
  String notifRunningServer(String name, int port);

  /// No description provided for @notifRunningServerMode.
  ///
  /// In zh, this message translates to:
  /// **'运行中 · [{mode}] {count} 个服务商 · 端口 {port}'**
  String notifRunningServerMode(String mode, int count, int port);

  /// No description provided for @platformNoSaveDialog.
  ///
  /// In zh, this message translates to:
  /// **'无法打开保存对话框：{error}'**
  String platformNoSaveDialog(String error);

  /// No description provided for @platformNoFilePicker.
  ///
  /// In zh, this message translates to:
  /// **'无法打开文件选择器：{error}'**
  String platformNoFilePicker(String error);

  /// No description provided for @platformNoFilePickerShort.
  ///
  /// In zh, this message translates to:
  /// **'无法打开文件选择器'**
  String get platformNoFilePickerShort;

  /// No description provided for @platformNoLocalRead.
  ///
  /// In zh, this message translates to:
  /// **'当前环境不支持读取本地文件'**
  String get platformNoLocalRead;

  /// No description provided for @platformReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取该文件：{error}'**
  String platformReadFailed(String error);

  /// No description provided for @platformNoSystemPicker.
  ///
  /// In zh, this message translates to:
  /// **'当前环境不支持系统文件选择器'**
  String get platformNoSystemPicker;

  /// No description provided for @updateConnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：无法连接（{error}）'**
  String updateConnectFailed(String error);

  /// No description provided for @updateTlsFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：TLS 证书校验不通过'**
  String get updateTlsFailed;

  /// No description provided for @updateBadJson.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：服务器返回的内容不是合法 JSON'**
  String get updateBadJson;

  /// No description provided for @updateRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：GitHub 接口限流（未认证请求每小时 60 次），请稍后再试或直接访问项目发布页'**
  String get updateRateLimited;

  /// No description provided for @updateForbidden.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：GitHub 拒绝访问（HTTP 403）'**
  String get updateForbidden;

  /// No description provided for @updateNotFound.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：仓库或发布页不存在（HTTP 404）'**
  String get updateNotFound;

  /// No description provided for @updateServerError.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：GitHub 服务异常（HTTP {status}）'**
  String updateServerError(int status);

  /// No description provided for @updateUnexpectedStatus.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：GitHub 返回 {status}'**
  String updateUnexpectedStatus(int status);

  /// No description provided for @updateResponseNotJson.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：响应不是合法 JSON'**
  String get updateResponseNotJson;

  /// No description provided for @updateUnexpectedFormat.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：响应格式不符合预期'**
  String get updateUnexpectedFormat;

  /// No description provided for @updateMissingTag.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败：最新版本缺少 tag_name'**
  String get updateMissingTag;

  /// No description provided for @updateNoApk.
  ///
  /// In zh, this message translates to:
  /// **'最新版本未提供 Android APK'**
  String get updateNoApk;

  /// No description provided for @updateBadDownloadUrl.
  ///
  /// In zh, this message translates to:
  /// **'更新包下载地址无效'**
  String get updateBadDownloadUrl;

  /// No description provided for @updateApkFileName.
  ///
  /// In zh, this message translates to:
  /// **'谛听-{version}.apk'**
  String updateApkFileName(String version);

  /// No description provided for @agentApiEmptyEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'接口地址为空，请先在「AI 厂商管理」里填写'**
  String get agentApiEmptyEndpoint;

  /// No description provided for @agentApiNoModelListJson.
  ///
  /// In zh, this message translates to:
  /// **'服务端未返回模型列表（响应不是 JSON 对象）'**
  String get agentApiNoModelListJson;

  /// No description provided for @agentApiNoModelListData.
  ///
  /// In zh, this message translates to:
  /// **'服务端未返回模型列表（响应中缺少 data 字段）'**
  String get agentApiNoModelListData;

  /// No description provided for @agentApiNoModels.
  ///
  /// In zh, this message translates to:
  /// **'接口未返回任何模型，请手动填写模型名称'**
  String get agentApiNoModels;

  /// No description provided for @agentApiKeyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'API Key 不能为空'**
  String get agentApiKeyEmpty;

  /// No description provided for @agentApiKeyEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'API Key 不能为空，请先在 AI 分析设置中配置'**
  String get agentApiKeyEmptyHint;

  /// No description provided for @agentApiResponseNotJsonObject.
  ///
  /// In zh, this message translates to:
  /// **'服务端响应不是 JSON 对象'**
  String get agentApiResponseNotJsonObject;

  /// No description provided for @agentApiEmptyContent.
  ///
  /// In zh, this message translates to:
  /// **'模型返回了空内容，请检查模型名称或稍后重试'**
  String get agentApiEmptyContent;

  /// No description provided for @agentApiBadUrl.
  ///
  /// In zh, this message translates to:
  /// **'接口地址不合法：{url}'**
  String agentApiBadUrl(String url);

  /// No description provided for @agentApiCancelled.
  ///
  /// In zh, this message translates to:
  /// **'分析已取消'**
  String get agentApiCancelled;

  /// No description provided for @agentApiTimeout.
  ///
  /// In zh, this message translates to:
  /// **'请求超时：模型服务在限定时间内没有响应'**
  String get agentApiTimeout;

  /// No description provided for @agentApiUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'无法连接模型服务（{error}）'**
  String agentApiUnreachable(String error);

  /// No description provided for @agentApiTls.
  ///
  /// In zh, this message translates to:
  /// **'TLS 握手失败：服务端证书不可信或协议不匹配'**
  String get agentApiTls;

  /// No description provided for @agentApiInvalidJson.
  ///
  /// In zh, this message translates to:
  /// **'服务端响应不是合法 JSON'**
  String get agentApiInvalidJson;

  /// No description provided for @agentApiBadKey.
  ///
  /// In zh, this message translates to:
  /// **'API Key 无效或已过期'**
  String get agentApiBadKey;

  /// No description provided for @agentApiNoAccess.
  ///
  /// In zh, this message translates to:
  /// **'密钥无权访问该模型，或该地区被限制'**
  String get agentApiNoAccess;

  /// No description provided for @agentApiModelNotFound.
  ///
  /// In zh, this message translates to:
  /// **'接口地址或模型名称不存在（404）'**
  String get agentApiModelNotFound;

  /// No description provided for @agentApiRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'请求过于频繁或额度用尽（429）'**
  String get agentApiRateLimited;

  /// No description provided for @agentApiUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'模型服务暂时不可用（{status}）'**
  String agentApiUnavailable(int status);

  /// No description provided for @agentApiRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求失败（{status}）'**
  String agentApiRequestFailed(int status);

  /// No description provided for @agentApiServerDetail.
  ///
  /// In zh, this message translates to:
  /// **'：{message}'**
  String agentApiServerDetail(String message);

  /// No description provided for @davProbeNoWrite.
  ///
  /// In zh, this message translates to:
  /// **'服务器可达但无法创建目录，请检查账号是否具备写入权限'**
  String get davProbeNoWrite;

  /// No description provided for @davProbeConnect.
  ///
  /// In zh, this message translates to:
  /// **'无法连接到服务器：{error}'**
  String davProbeConnect(String error);

  /// No description provided for @davProbeTls.
  ///
  /// In zh, this message translates to:
  /// **'TLS 握手失败：服务器证书不被信任（自签证书需在系统里安装）'**
  String get davProbeTls;

  /// No description provided for @davProbeHttp.
  ///
  /// In zh, this message translates to:
  /// **'HTTP 请求失败，请检查服务器是否支持 WebDAV'**
  String get davProbeHttp;

  /// No description provided for @davUploadConnect.
  ///
  /// In zh, this message translates to:
  /// **'上传失败：无法连接服务器（{error}）'**
  String davUploadConnect(String error);

  /// No description provided for @davUploadTls.
  ///
  /// In zh, this message translates to:
  /// **'上传失败：TLS 证书不被信任'**
  String get davUploadTls;

  /// No description provided for @davDownloadHttp.
  ///
  /// In zh, this message translates to:
  /// **'下载失败（HTTP {status}）'**
  String davDownloadHttp(int status);

  /// No description provided for @davStatus401.
  ///
  /// In zh, this message translates to:
  /// **'认证失败：用户名或密码不正确'**
  String get davStatus401;

  /// No description provided for @davStatus403.
  ///
  /// In zh, this message translates to:
  /// **'服务器拒绝访问：该账号没有读写此目录的权限'**
  String get davStatus403;

  /// No description provided for @davStatus404.
  ///
  /// In zh, this message translates to:
  /// **'服务器上找不到该目录'**
  String get davStatus404;

  /// No description provided for @davStatus405.
  ///
  /// In zh, this message translates to:
  /// **'服务器不允许该操作（可能未启用 WebDAV）'**
  String get davStatus405;

  /// No description provided for @davStatus409.
  ///
  /// In zh, this message translates to:
  /// **'目标目录不存在，无法写入'**
  String get davStatus409;

  /// No description provided for @davStatus507.
  ///
  /// In zh, this message translates to:
  /// **'服务器存储空间不足'**
  String get davStatus507;

  /// No description provided for @davStatus5xx.
  ///
  /// In zh, this message translates to:
  /// **'服务器内部错误（HTTP {status}）'**
  String davStatus5xx(int status);

  /// No description provided for @davStatusOther.
  ///
  /// In zh, this message translates to:
  /// **'服务器返回 HTTP {status}'**
  String davStatusOther(int status);

  /// No description provided for @ipQualityNoExitIp.
  ///
  /// In zh, this message translates to:
  /// **'无法获取当前出口 IP：网络不可达或探测服务超时'**
  String get ipQualityNoExitIp;

  /// No description provided for @ipQualityNoSourceResult.
  ///
  /// In zh, this message translates to:
  /// **'所有 IP 情报源均未返回结果，请检查网络后重试'**
  String get ipQualityNoSourceResult;

  /// No description provided for @disclaimerTerm1Title.
  ///
  /// In zh, this message translates to:
  /// **'一、软件性质'**
  String get disclaimerTerm1Title;

  /// No description provided for @disclaimerTerm1Content.
  ///
  /// In zh, this message translates to:
  /// **'谛听是一款开源的本地域名解析与流量观测工具，不以任何形式提供网络接入服务。软件本身不含任何服务器、节点或订阅内容，也不代替任何网络服务商。'**
  String get disclaimerTerm1Content;

  /// No description provided for @disclaimerTerm2Title.
  ///
  /// In zh, this message translates to:
  /// **'二、使用方式'**
  String get disclaimerTerm2Title;

  /// No description provided for @disclaimerTerm2Content.
  ///
  /// In zh, this message translates to:
  /// **'用户应仅在自有设备与自有网络上使用本软件。将本软件用于任何网络接入、绕过计费或在未授权网络上运行的行为，均超出软件设计用途。'**
  String get disclaimerTerm2Content;

  /// No description provided for @disclaimerTerm3Title.
  ///
  /// In zh, this message translates to:
  /// **'三、责任范围'**
  String get disclaimerTerm3Title;

  /// No description provided for @disclaimerTerm3Content.
  ///
  /// In zh, this message translates to:
  /// **'因使用或无法使用本软件导致的任何直接或间接损失，包括但不限于数据丢失、服务中断、设备损坏，作者与贡献者均不承担责任。'**
  String get disclaimerTerm3Content;

  /// No description provided for @disclaimerTerm4Title.
  ///
  /// In zh, this message translates to:
  /// **'四、第三方组件'**
  String get disclaimerTerm4Title;

  /// No description provided for @disclaimerTerm4Content.
  ///
  /// In zh, this message translates to:
  /// **'本软件的界面组件层移植自 DITING（GPL-3.0-or-later），并使用了 material_ui、material_color_utilities 等开源组件。各组件的许可条款见仓库 NOTICE.md，使用本软件即表示同时接受这些条款。'**
  String get disclaimerTerm4Content;

  /// No description provided for @disclaimerTerm5Title.
  ///
  /// In zh, this message translates to:
  /// **'五、无担保'**
  String get disclaimerTerm5Title;

  /// No description provided for @disclaimerTerm5Content.
  ///
  /// In zh, this message translates to:
  /// **'本软件按「现状」提供，不附带任何明示或暗示的担保，包括但不限于适销性、特定用途适用性与不侵权的担保。'**
  String get disclaimerTerm5Content;

  /// No description provided for @disclaimerTerm6Title.
  ///
  /// In zh, this message translates to:
  /// **'六、责任限制'**
  String get disclaimerTerm6Title;

  /// No description provided for @disclaimerTerm6Content.
  ///
  /// In zh, this message translates to:
  /// **'在法律允许的最大范围内，作者不对任何间接、附带、特殊或后果性损害负责，即使已被告知此类损害的可能性。'**
  String get disclaimerTerm6Content;

  /// No description provided for @disclaimerTerm7Title.
  ///
  /// In zh, this message translates to:
  /// **'七、隐私'**
  String get disclaimerTerm7Title;

  /// No description provided for @disclaimerTerm7Content.
  ///
  /// In zh, this message translates to:
  /// **'本软件默认不收集、不上传任何用户数据。日志与规则仅保存在本地；若用户主动配置 WebDAV 备份，数据将上传至用户自行指定的服务器。'**
  String get disclaimerTerm7Content;

  /// No description provided for @disclaimerTerm8Title.
  ///
  /// In zh, this message translates to:
  /// **'八、许可'**
  String get disclaimerTerm8Title;

  /// No description provided for @disclaimerTerm8Content.
  ///
  /// In zh, this message translates to:
  /// **'本软件以 GPL-3.0-or-later 发布。你可以自由使用、修改与再分发，但衍生作品必须沿用同一许可并保留原始版权声明。'**
  String get disclaimerTerm8Content;

  /// No description provided for @disclaimerTerm9Title.
  ///
  /// In zh, this message translates to:
  /// **'九、条款变更'**
  String get disclaimerTerm9Title;

  /// No description provided for @disclaimerTerm9Content.
  ///
  /// In zh, this message translates to:
  /// **'作者保留随时修改本免责声明的权利。变更后的条款随新版本一同发布，继续使用即视为接受修改后的条款。'**
  String get disclaimerTerm9Content;

  /// No description provided for @disclaimerTerm10Title.
  ///
  /// In zh, this message translates to:
  /// **'十、接受条款'**
  String get disclaimerTerm10Title;

  /// No description provided for @disclaimerTerm10Content.
  ///
  /// In zh, this message translates to:
  /// **'在继续使用本软件前，请确认你已阅读、理解并同意上述全部条款。若不同意，请立即停止使用并卸载本软件。'**
  String get disclaimerTerm10Content;

  /// No description provided for @settingsModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换普通模式或服务器模式'**
  String get settingsModeSubtitle;

  /// No description provided for @settingsPerformanceSection.
  ///
  /// In zh, this message translates to:
  /// **'性能优化'**
  String get settingsPerformanceSection;

  /// No description provided for @settingsCacheSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存已解析的域名，减少重复查询'**
  String get settingsCacheSubtitle;

  /// No description provided for @settingsLogModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择 DNS 请求日志的记录范围'**
  String get settingsLogModeSubtitle;

  /// No description provided for @settingsRuntimeSection.
  ///
  /// In zh, this message translates to:
  /// **'运行行为'**
  String get settingsRuntimeSection;

  /// No description provided for @settingsForegroundSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'后台隐藏、通知常驻、绕过局域网'**
  String get settingsForegroundSubtitle;

  /// No description provided for @settingsAutoStartTitle.
  ///
  /// In zh, this message translates to:
  /// **'启动时自动开启'**
  String get settingsAutoStartTitle;

  /// No description provided for @settingsAutoStartSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'上次未手动关闭时，打开应用自动恢复普通或极速模式'**
  String get settingsAutoStartSubtitle;

  /// No description provided for @settingsVpnWatchdogTitle.
  ///
  /// In zh, this message translates to:
  /// **'VPN 看门狗'**
  String get settingsVpnWatchdogTitle;

  /// No description provided for @settingsVpnWatchdogSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'VPN 通道被其他应用占用时持续监测，释放后自动重新连接'**
  String get settingsVpnWatchdogSubtitle;

  /// No description provided for @settingsDataSection.
  ///
  /// In zh, this message translates to:
  /// **'数据管理'**
  String get settingsDataSection;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择应用界面语言'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsWizardSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看当前工作模式的架构原理、权限配置与上手指引'**
  String get settingsWizardSubtitle;

  /// No description provided for @settingsGuideSection.
  ///
  /// In zh, this message translates to:
  /// **'上手引导'**
  String get settingsGuideSection;

  /// No description provided for @backupErrEmpty.
  ///
  /// In zh, this message translates to:
  /// **'文件内容为空'**
  String get backupErrEmpty;

  /// No description provided for @backupErrInvalidJson.
  ///
  /// In zh, this message translates to:
  /// **'不是合法的 JSON：{error}'**
  String backupErrInvalidJson(String error);

  /// No description provided for @backupErrRootNotObject.
  ///
  /// In zh, this message translates to:
  /// **'备份文件的根节点必须是 JSON 对象'**
  String get backupErrRootNotObject;

  /// No description provided for @backupErrNotDiting.
  ///
  /// In zh, this message translates to:
  /// **'这不是谛听的备份文件：缺少 format 标记'**
  String get backupErrNotDiting;

  /// No description provided for @backupErrNoVersion.
  ///
  /// In zh, this message translates to:
  /// **'备份文件缺少版本号'**
  String get backupErrNoVersion;

  /// No description provided for @backupErrVersionTooHigh.
  ///
  /// In zh, this message translates to:
  /// **'备份版本 {version} 高于本版应用支持的 {max}，请升级应用后再导入'**
  String backupErrVersionTooHigh(String version, int max);

  /// No description provided for @backupErrNoData.
  ///
  /// In zh, this message translates to:
  /// **'备份文件缺少 data 段'**
  String get backupErrNoData;

  /// No description provided for @backupErrProvidersNotArray.
  ///
  /// In zh, this message translates to:
  /// **'服务商分组应为数组'**
  String get backupErrProvidersNotArray;

  /// No description provided for @backupErrBootstrapNotObject.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 分组应为对象'**
  String get backupErrBootstrapNotObject;

  /// No description provided for @backupErrCacheNotObject.
  ///
  /// In zh, this message translates to:
  /// **'缓存分组应为对象'**
  String get backupErrCacheNotObject;

  /// No description provided for @backupErrOutboundNotObject.
  ///
  /// In zh, this message translates to:
  /// **'出站代理分组应为对象'**
  String get backupErrOutboundNotObject;

  /// No description provided for @backupErrBlockedNotObject.
  ///
  /// In zh, this message translates to:
  /// **'禁止联网分组应为对象'**
  String get backupErrBlockedNotObject;

  /// No description provided for @backupErrAppRulesNotObject.
  ///
  /// In zh, this message translates to:
  /// **'应用独立规则分组应为对象'**
  String get backupErrAppRulesNotObject;

  /// No description provided for @backupErrInspectionNotObject.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 抓包分组应为对象'**
  String get backupErrInspectionNotObject;

  /// No description provided for @backupErrSubsNotObject.
  ///
  /// In zh, this message translates to:
  /// **'订阅分组应为对象'**
  String get backupErrSubsNotObject;

  /// No description provided for @backupErrNoRuleDbSubs.
  ///
  /// In zh, this message translates to:
  /// **'本机还没有规则库，无法导入订阅'**
  String get backupErrNoRuleDbSubs;

  /// No description provided for @backupErrRulesNotArray.
  ///
  /// In zh, this message translates to:
  /// **'规则分组应为数组'**
  String get backupErrRulesNotArray;

  /// No description provided for @backupErrNoRuleDbRules.
  ///
  /// In zh, this message translates to:
  /// **'本机还没有规则库，无法导入规则'**
  String get backupErrNoRuleDbRules;

  /// No description provided for @backupErrRewriteNotArray.
  ///
  /// In zh, this message translates to:
  /// **'覆写规则分组应为数组'**
  String get backupErrRewriteNotArray;

  /// No description provided for @backupErrNoRuleDbRewrite.
  ///
  /// In zh, this message translates to:
  /// **'本机还没有规则库，无法导入覆写规则'**
  String get backupErrNoRuleDbRewrite;

  /// No description provided for @backupErrAddressNotArray.
  ///
  /// In zh, this message translates to:
  /// **'地址规则分组应为数组'**
  String get backupErrAddressNotArray;

  /// No description provided for @backupErrNoRuleDbAddress.
  ///
  /// In zh, this message translates to:
  /// **'本机还没有规则库，无法导入地址规则'**
  String get backupErrNoRuleDbAddress;

  /// No description provided for @agentPasteEmpty.
  ///
  /// In zh, this message translates to:
  /// **'剪贴板为空'**
  String get agentPasteEmpty;

  /// No description provided for @agentPasteBoth.
  ///
  /// In zh, this message translates to:
  /// **'已自动识别并填入服务地址与 API Key'**
  String get agentPasteBoth;

  /// No description provided for @agentPasteBaseUrl.
  ///
  /// In zh, this message translates to:
  /// **'已填入服务地址'**
  String get agentPasteBaseUrl;

  /// No description provided for @agentPasteKey.
  ///
  /// In zh, this message translates to:
  /// **'已填入 API Key'**
  String get agentPasteKey;

  /// No description provided for @agentPasteJson.
  ///
  /// In zh, this message translates to:
  /// **'已从 JSON 中识别并更新 API 配置'**
  String get agentPasteJson;

  /// No description provided for @logDirect.
  ///
  /// In zh, this message translates to:
  /// **'{protocol} 直连'**
  String logDirect(String protocol);

  /// No description provided for @logDirectWithApp.
  ///
  /// In zh, this message translates to:
  /// **'{protocol} 直连 · {app}'**
  String logDirectWithApp(String protocol, String app);

  /// No description provided for @subsErrUrlUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'订阅地址不可用'**
  String get subsErrUrlUnavailable;

  /// No description provided for @subsErrTimeout.
  ///
  /// In zh, this message translates to:
  /// **'下载超时（读取 {seconds} 秒）'**
  String subsErrTimeout(int seconds);

  /// No description provided for @subsErrTls.
  ///
  /// In zh, this message translates to:
  /// **'TLS 握手失败，请检查证书或镜像地址'**
  String get subsErrTls;

  /// No description provided for @subsErrEmptyResponse.
  ///
  /// In zh, this message translates to:
  /// **'订阅响应为空'**
  String get subsErrEmptyResponse;

  /// No description provided for @subsErrUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'网络不可达'**
  String get subsErrUnreachable;

  /// No description provided for @subsErrUnreachableCode.
  ///
  /// In zh, this message translates to:
  /// **'网络不可达：{code}'**
  String subsErrUnreachableCode(String code);

  /// No description provided for @subsErrUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前环境不支持网络订阅更新'**
  String get subsErrUnsupported;

  /// No description provided for @subsErrMirrorPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'镜像模板必须包含 {list}'**
  String subsErrMirrorPlaceholder(String list);

  /// No description provided for @subsErrRawUrlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'原始订阅地址格式无效'**
  String get subsErrRawUrlInvalid;

  /// No description provided for @subsErrMirrorScheme.
  ///
  /// In zh, this message translates to:
  /// **'镜像模板生成的地址必须使用 HTTP 或 HTTPS'**
  String get subsErrMirrorScheme;

  /// No description provided for @subsErrEmpty.
  ///
  /// In zh, this message translates to:
  /// **'订阅地址不能为空'**
  String get subsErrEmpty;

  /// No description provided for @subsErrBadFormat.
  ///
  /// In zh, this message translates to:
  /// **'订阅地址格式无效'**
  String get subsErrBadFormat;

  /// No description provided for @subsErrNotHttp.
  ///
  /// In zh, this message translates to:
  /// **'订阅链接必须使用 HTTP 或 HTTPS'**
  String get subsErrNotHttp;

  /// No description provided for @subsErrNoHost.
  ///
  /// In zh, this message translates to:
  /// **'订阅地址缺少主机名'**
  String get subsErrNoHost;

  /// No description provided for @siteCategoryShopping.
  ///
  /// In zh, this message translates to:
  /// **'购物'**
  String get siteCategoryShopping;

  /// No description provided for @siteCategoryVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get siteCategoryVideo;

  /// No description provided for @siteCategoryMusic.
  ///
  /// In zh, this message translates to:
  /// **'音乐'**
  String get siteCategoryMusic;

  /// No description provided for @siteCategorySocial.
  ///
  /// In zh, this message translates to:
  /// **'社交'**
  String get siteCategorySocial;

  /// No description provided for @siteCategoryDeveloper.
  ///
  /// In zh, this message translates to:
  /// **'开发者'**
  String get siteCategoryDeveloper;

  /// No description provided for @siteCategoryGame.
  ///
  /// In zh, this message translates to:
  /// **'游戏'**
  String get siteCategoryGame;

  /// No description provided for @outboundProxyHostInvalid.
  ///
  /// In zh, this message translates to:
  /// **'代理地址仅支持 127.0.0.1 或 ::1'**
  String get outboundProxyHostInvalid;

  /// No description provided for @outboundProxyPortRange.
  ///
  /// In zh, this message translates to:
  /// **'代理端口必须在 1 到 65535 之间'**
  String get outboundProxyPortRange;

  /// No description provided for @outboundProxyAppRequired.
  ///
  /// In zh, this message translates to:
  /// **'请选择提供本地代理端口的应用'**
  String get outboundProxyAppRequired;

  /// No description provided for @outboundProxySelfNotAllowed.
  ///
  /// In zh, this message translates to:
  /// **'不能选择 DITING 自身作为代理应用'**
  String get outboundProxySelfNotAllowed;

  /// No description provided for @outboundProxyAppMissing.
  ///
  /// In zh, this message translates to:
  /// **'所选代理应用未安装'**
  String get outboundProxyAppMissing;

  /// No description provided for @outboundProxyCredentialsTooLong.
  ///
  /// In zh, this message translates to:
  /// **'代理账号或密码过长'**
  String get outboundProxyCredentialsTooLong;

  /// No description provided for @updateDownloadNoPath.
  ///
  /// In zh, this message translates to:
  /// **'下载失败：未返回安装包路径'**
  String get updateDownloadNoPath;

  /// No description provided for @updateDownloadUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前设备不支持应用内下载，请用浏览器打开下载地址'**
  String get updateDownloadUnsupported;

  /// No description provided for @updateDownloadFailedCode.
  ///
  /// In zh, this message translates to:
  /// **'下载失败（{code}）'**
  String updateDownloadFailedCode(String code);

  /// No description provided for @dnsLatencySuccessRate.
  ///
  /// In zh, this message translates to:
  /// **'成功率 {success}/{attempts}'**
  String dnsLatencySuccessRate(int success, int attempts);

  /// No description provided for @dnsLatencyUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前设备不支持测速'**
  String get dnsLatencyUnsupported;

  /// No description provided for @dnsLatencyChannelFailedCode.
  ///
  /// In zh, this message translates to:
  /// **'测速通道调用失败（{code}）'**
  String dnsLatencyChannelFailedCode(String code);

  /// No description provided for @dnsLatencyChannelFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'测速通道调用失败：{detail}'**
  String dnsLatencyChannelFailedDetail(String detail);

  /// No description provided for @fontImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法导入该字体'**
  String get fontImportFailed;

  /// No description provided for @fontReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取该字体文件'**
  String get fontReadFailed;

  /// No description provided for @fontParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法解析该字体文件，请确认它是完整的 TTF/OTF'**
  String get fontParseFailed;

  /// No description provided for @fontCustomName.
  ///
  /// In zh, this message translates to:
  /// **'自定义字体'**
  String get fontCustomName;

  /// No description provided for @recognitionAvatarTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'头像体积超限'**
  String get recognitionAvatarTooLarge;

  /// No description provided for @recognitionConfigTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'名单配置过大'**
  String get recognitionConfigTooLarge;

  /// No description provided for @taglineRunning.
  ///
  /// In zh, this message translates to:
  /// **'谛听万象，明察清浊'**
  String get taglineRunning;

  /// No description provided for @taglineStopped.
  ///
  /// In zh, this message translates to:
  /// **'收耳静眠，归于无声'**
  String get taglineStopped;

  /// No description provided for @backupErrProvidersInvalidJson.
  ///
  /// In zh, this message translates to:
  /// **'服务商配置不是合法 JSON'**
  String get backupErrProvidersInvalidJson;

  /// No description provided for @backupErrBootstrapInvalidJson.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 配置不是合法 JSON'**
  String get backupErrBootstrapInvalidJson;

  /// No description provided for @backupErrAppearanceNotObject.
  ///
  /// In zh, this message translates to:
  /// **'外观分组应为对象'**
  String get backupErrAppearanceNotObject;

  /// No description provided for @backupErrSystemNotObject.
  ///
  /// In zh, this message translates to:
  /// **'系统设置分组应为对象'**
  String get backupErrSystemNotObject;

  /// No description provided for @outboundScopeTitle.
  ///
  /// In zh, this message translates to:
  /// **'代理范围'**
  String get outboundScopeTitle;

  /// No description provided for @outboundScopeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部应用'**
  String get outboundScopeAll;

  /// No description provided for @outboundScopeApps.
  ///
  /// In zh, this message translates to:
  /// **'仅选中应用'**
  String get outboundScopeApps;

  /// No description provided for @outboundScopeAllFooter.
  ///
  /// In zh, this message translates to:
  /// **'所有应用的连接以及谛听自身的 DNS 上游查询都经过代理。'**
  String get outboundScopeAllFooter;

  /// No description provided for @outboundScopeAppsFooter.
  ///
  /// In zh, this message translates to:
  /// **'只有选中应用的连接经过代理；其他应用、无法识别归属的连接以及谛听自身的 DNS 上游查询直接连接。'**
  String get outboundScopeAppsFooter;

  /// No description provided for @outboundTargets.
  ///
  /// In zh, this message translates to:
  /// **'走代理的应用'**
  String get outboundTargets;

  /// No description provided for @outboundTargetsTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择走代理的应用'**
  String get outboundTargetsTitle;

  /// No description provided for @outboundTargetsIntro.
  ///
  /// In zh, this message translates to:
  /// **'勾选的应用会经代理连接网络，修改后需重启隧道生效。代理应用本身、谛听以及「排除应用」中的应用不经过隧道，无法走代理，因此不在列表中。'**
  String get outboundTargetsIntro;

  /// No description provided for @outboundProxyTargetsRequired.
  ///
  /// In zh, this message translates to:
  /// **'「仅选中应用」模式下请至少选择一个走代理的应用'**
  String get outboundProxyTargetsRequired;

  /// No description provided for @logDashboardCardHero.
  ///
  /// In zh, this message translates to:
  /// **'仪表盘标题'**
  String get logDashboardCardHero;

  /// No description provided for @logDashboardCardTrafficStructure.
  ///
  /// In zh, this message translates to:
  /// **'流量结构'**
  String get logDashboardCardTrafficStructure;

  /// No description provided for @logDashboardEditHint.
  ///
  /// In zh, this message translates to:
  /// **'正在编辑「{mode}」模式的布局，切换日志模式后各自独立。拖动手柄排序，点右上角移除。'**
  String logDashboardEditHint(String mode);

  /// No description provided for @logDashboardModeFooter.
  ///
  /// In zh, this message translates to:
  /// **'这里只列出当前日志模式能显示数据的卡片。'**
  String get logDashboardModeFooter;

  /// No description provided for @logDashboardCardHeroDescription.
  ///
  /// In zh, this message translates to:
  /// **'页面顶部的标题与一句话说明，随日志模式变化'**
  String get logDashboardCardHeroDescription;

  /// No description provided for @logDashboardCardTrafficMonitorDescription.
  ///
  /// In zh, this message translates to:
  /// **'上下行实时速率与今日累计流量'**
  String get logDashboardCardTrafficMonitorDescription;

  /// No description provided for @logDashboardCardRequestOverviewDescription.
  ///
  /// In zh, this message translates to:
  /// **'今日请求、放行、拦截与缓存命中计数'**
  String get logDashboardCardRequestOverviewDescription;

  /// No description provided for @logDashboardCardHighlightDescription.
  ///
  /// In zh, this message translates to:
  /// **'今日拦截、错误与旁路的重点计数'**
  String get logDashboardCardHighlightDescription;

  /// No description provided for @logDashboardCardPrivacyDescription.
  ///
  /// In zh, this message translates to:
  /// **'说明日志已关闭、不记录任何请求'**
  String get logDashboardCardPrivacyDescription;

  /// No description provided for @logDashboardCardOffMetricDescription.
  ///
  /// In zh, this message translates to:
  /// **'缓存条目、缓存命中、竞速与 Bootstrap 次数'**
  String get logDashboardCardOffMetricDescription;

  /// No description provided for @logDashboardCardPerfDescription.
  ///
  /// In zh, this message translates to:
  /// **'平均延迟、缓存命中率与竞速、Bootstrap 成功率'**
  String get logDashboardCardPerfDescription;

  /// No description provided for @logDashboardCardAiDescription.
  ///
  /// In zh, this message translates to:
  /// **'用 AI 研判今日流量，复用上一次的报告'**
  String get logDashboardCardAiDescription;

  /// No description provided for @logDashboardCardTrafficStructureDescription.
  ///
  /// In zh, this message translates to:
  /// **'今日请求结果构成的环形图'**
  String get logDashboardCardTrafficStructureDescription;

  /// No description provided for @logDashboardCardRecentRequestsDescription.
  ///
  /// In zh, this message translates to:
  /// **'最近几条请求记录'**
  String get logDashboardCardRecentRequestsDescription;

  /// No description provided for @logDashboardCardRecentBlockedDescription.
  ///
  /// In zh, this message translates to:
  /// **'最近几条拦截与错误记录'**
  String get logDashboardCardRecentBlockedDescription;

  /// No description provided for @logDashboardCardCacheDescription.
  ///
  /// In zh, this message translates to:
  /// **'命中次数最多的缓存域名'**
  String get logDashboardCardCacheDescription;

  /// No description provided for @logDashboardCardRaceDescription.
  ///
  /// In zh, this message translates to:
  /// **'竞速中胜出最多的上游'**
  String get logDashboardCardRaceDescription;

  /// No description provided for @logDashboardCardBootstrapDescription.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap DNS 的解析次数与成功率'**
  String get logDashboardCardBootstrapDescription;

  /// No description provided for @logDashboardCardRuleBlocksDescription.
  ///
  /// In zh, this message translates to:
  /// **'拦截次数最多的规则来源'**
  String get logDashboardCardRuleBlocksDescription;

  /// No description provided for @logStatsTitle.
  ///
  /// In zh, this message translates to:
  /// **'统计'**
  String get logStatsTitle;

  /// No description provided for @logStatsRequests.
  ///
  /// In zh, this message translates to:
  /// **'请求'**
  String get logStatsRequests;

  /// No description provided for @logStatsTotal.
  ///
  /// In zh, this message translates to:
  /// **'总请求'**
  String get logStatsTotal;

  /// No description provided for @logStatsData.
  ///
  /// In zh, this message translates to:
  /// **'数据使用'**
  String get logStatsData;

  /// No description provided for @logStatsSaved.
  ///
  /// In zh, this message translates to:
  /// **'缓存节省'**
  String get logStatsSaved;

  /// No description provided for @logStatsUploaded.
  ///
  /// In zh, this message translates to:
  /// **'已上传'**
  String get logStatsUploaded;

  /// No description provided for @logStatsDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get logStatsDownloaded;

  /// No description provided for @logStatsWindow.
  ///
  /// In zh, this message translates to:
  /// **'统计范围'**
  String get logStatsWindow;

  /// No description provided for @logStatsRecentActivity.
  ///
  /// In zh, this message translates to:
  /// **'最近的活动'**
  String get logStatsRecentActivity;

  /// No description provided for @logDashboardCardStatsDescription.
  ///
  /// In zh, this message translates to:
  /// **'按今日、本周、本月或全部历史统计拦截、缓存命中与上下行流量'**
  String get logDashboardCardStatsDescription;

  /// No description provided for @floatingLogOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开悬浮窗日志'**
  String get floatingLogOpen;

  /// No description provided for @floatingLogTitle.
  ///
  /// In zh, this message translates to:
  /// **'实时请求'**
  String get floatingLogTitle;

  /// No description provided for @floatingLogPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get floatingLogPaused;

  /// No description provided for @floatingLogSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get floatingLogSearch;

  /// No description provided for @floatingLogSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'域名、应用或规则'**
  String get floatingLogSearchHint;

  /// No description provided for @floatingLogPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停刷新'**
  String get floatingLogPause;

  /// No description provided for @floatingLogResume.
  ///
  /// In zh, this message translates to:
  /// **'继续刷新'**
  String get floatingLogResume;

  /// No description provided for @floatingLogMinimize.
  ///
  /// In zh, this message translates to:
  /// **'收起为悬浮球'**
  String get floatingLogMinimize;

  /// No description provided for @floatingLogPanelSize.
  ///
  /// In zh, this message translates to:
  /// **'面板大小'**
  String get floatingLogPanelSize;

  /// No description provided for @floatingLogSizeSmall.
  ///
  /// In zh, this message translates to:
  /// **'小'**
  String get floatingLogSizeSmall;

  /// No description provided for @floatingLogSizeMedium.
  ///
  /// In zh, this message translates to:
  /// **'中'**
  String get floatingLogSizeMedium;

  /// No description provided for @floatingLogSizeLarge.
  ///
  /// In zh, this message translates to:
  /// **'大'**
  String get floatingLogSizeLarge;

  /// No description provided for @floatingLogClear.
  ///
  /// In zh, this message translates to:
  /// **'清空列表'**
  String get floatingLogClear;

  /// No description provided for @floatingLogOpenApp.
  ///
  /// In zh, this message translates to:
  /// **'打开谛听'**
  String get floatingLogOpenApp;

  /// No description provided for @floatingLogHide.
  ///
  /// In zh, this message translates to:
  /// **'本次隐藏'**
  String get floatingLogHide;

  /// No description provided for @floatingLogHideHint.
  ///
  /// In zh, this message translates to:
  /// **'回到应用后再次显示'**
  String get floatingLogHideHint;

  /// No description provided for @floatingLogCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get floatingLogCopied;

  /// No description provided for @floatingLogCopyDomain.
  ///
  /// In zh, this message translates to:
  /// **'复制域名'**
  String get floatingLogCopyDomain;

  /// No description provided for @floatingLogCopyRecord.
  ///
  /// In zh, this message translates to:
  /// **'复制记录'**
  String get floatingLogCopyRecord;

  /// No description provided for @floatingLogEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无请求'**
  String get floatingLogEmpty;

  /// No description provided for @floatingLogEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'新的请求会实时出现在这里。'**
  String get floatingLogEmptyBody;

  /// No description provided for @floatingLogClearedBody.
  ///
  /// In zh, this message translates to:
  /// **'列表已清空，新的请求会继续出现。'**
  String get floatingLogClearedBody;

  /// No description provided for @floatingLogNoMatchBody.
  ///
  /// In zh, this message translates to:
  /// **'换个关键词或筛选条件试试。'**
  String get floatingLogNoMatchBody;

  /// No description provided for @floatingLogUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法读取日志'**
  String get floatingLogUnavailable;

  /// No description provided for @floatingLogUnavailableBody.
  ///
  /// In zh, this message translates to:
  /// **'日志数据库尚未创建，请先在应用中启动一次隧道。'**
  String get floatingLogUnavailableBody;

  /// No description provided for @floatingLogShown.
  ///
  /// In zh, this message translates to:
  /// **'显示 {count} 条'**
  String floatingLogShown(int count);

  /// No description provided for @floatingLogNewRows.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条新请求'**
  String floatingLogNewRows(int count);

  /// No description provided for @floatingLogPermissionTitle.
  ///
  /// In zh, this message translates to:
  /// **'悬浮窗权限'**
  String get floatingLogPermissionTitle;

  /// No description provided for @floatingLogPermissionGranted.
  ///
  /// In zh, this message translates to:
  /// **'已授予'**
  String get floatingLogPermissionGranted;

  /// No description provided for @floatingLogPermissionMissing.
  ///
  /// In zh, this message translates to:
  /// **'未授予，点按前往系统设置开启'**
  String get floatingLogPermissionMissing;

  /// No description provided for @floatingLogOpacity.
  ///
  /// In zh, this message translates to:
  /// **'面板不透明度'**
  String get floatingLogOpacity;

  /// No description provided for @floatingLogSizeTitle.
  ///
  /// In zh, this message translates to:
  /// **'面板大小'**
  String get floatingLogSizeTitle;

  /// No description provided for @logRetentionOverlayHowTo.
  ///
  /// In zh, this message translates to:
  /// **'拖动悬浮球或面板标题栏可移动位置；点按一行展开详情，长按复制域名。'**
  String get logRetentionOverlayHowTo;

  /// No description provided for @permOverlay.
  ///
  /// In zh, this message translates to:
  /// **'悬浮窗'**
  String get permOverlay;

  /// No description provided for @desktopDnsServiceTitle.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务'**
  String get desktopDnsServiceTitle;

  /// No description provided for @desktopQueriesTitle.
  ///
  /// In zh, this message translates to:
  /// **'查询指标'**
  String get desktopQueriesTitle;

  /// No description provided for @desktopQueriesTotal.
  ///
  /// In zh, this message translates to:
  /// **'总查询'**
  String get desktopQueriesTotal;

  /// No description provided for @desktopQueriesSuccess.
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get desktopQueriesSuccess;

  /// No description provided for @desktopQueriesFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get desktopQueriesFailed;

  /// No description provided for @desktopQps.
  ///
  /// In zh, this message translates to:
  /// **'QPS'**
  String get desktopQps;

  /// No description provided for @desktopCacheTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get desktopCacheTitle;

  /// No description provided for @desktopCacheHits.
  ///
  /// In zh, this message translates to:
  /// **'命中'**
  String get desktopCacheHits;

  /// No description provided for @desktopCacheEvictions.
  ///
  /// In zh, this message translates to:
  /// **'淘汰'**
  String get desktopCacheEvictions;

  /// No description provided for @desktopFilterTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则拦截'**
  String get desktopFilterTitle;

  /// No description provided for @desktopFilterRules.
  ///
  /// In zh, this message translates to:
  /// **'有效防护规则'**
  String get desktopFilterRules;

  /// No description provided for @desktopFilterBlockRate.
  ///
  /// In zh, this message translates to:
  /// **'拦截比例'**
  String get desktopFilterBlockRate;

  /// No description provided for @desktopTakeoverTitle.
  ///
  /// In zh, this message translates to:
  /// **'系统 DNS 接管'**
  String get desktopTakeoverTitle;

  /// No description provided for @desktopTakeoverOn.
  ///
  /// In zh, this message translates to:
  /// **'已接管'**
  String get desktopTakeoverOn;

  /// No description provided for @desktopTakeoverOff.
  ///
  /// In zh, this message translates to:
  /// **'未接管'**
  String get desktopTakeoverOff;

  /// No description provided for @desktopFilterPauseTitle.
  ///
  /// In zh, this message translates to:
  /// **'临时暂停拦截'**
  String get desktopFilterPauseTitle;

  /// No description provided for @desktopFilterPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get desktopFilterPaused;

  /// No description provided for @desktopFilterActive.
  ///
  /// In zh, this message translates to:
  /// **'生效中'**
  String get desktopFilterActive;

  /// No description provided for @desktopServiceHostTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台服务'**
  String get desktopServiceHostTitle;

  /// No description provided for @desktopServiceAutoStart.
  ///
  /// In zh, this message translates to:
  /// **'开机自启'**
  String get desktopServiceAutoStart;

  /// No description provided for @desktopServiceNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'未安装'**
  String get desktopServiceNotInstalled;

  /// No description provided for @desktopVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get desktopVersion;

  /// No description provided for @desktopProcessId.
  ///
  /// In zh, this message translates to:
  /// **'进程'**
  String get desktopProcessId;

  /// No description provided for @desktopPerformanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'性能'**
  String get desktopPerformanceTitle;

  /// No description provided for @desktopRuntimeTitle.
  ///
  /// In zh, this message translates to:
  /// **'运行信息'**
  String get desktopRuntimeTitle;

  /// No description provided for @desktopLanAllowed.
  ///
  /// In zh, this message translates to:
  /// **'局域网'**
  String get desktopLanAllowed;

  /// No description provided for @desktopListeningOn.
  ///
  /// In zh, this message translates to:
  /// **'监听'**
  String get desktopListeningOn;

  /// No description provided for @desktopStartDns.
  ///
  /// In zh, this message translates to:
  /// **'启动 DNS'**
  String get desktopStartDns;

  /// No description provided for @desktopStopDns.
  ///
  /// In zh, this message translates to:
  /// **'停止 DNS'**
  String get desktopStopDns;

  /// No description provided for @desktopStartDnsTitle.
  ///
  /// In zh, this message translates to:
  /// **'启动 DNS 服务？'**
  String get desktopStartDnsTitle;

  /// No description provided for @desktopStartDnsMessage.
  ///
  /// In zh, this message translates to:
  /// **'启动后本机解析与规则过滤随之生效。'**
  String get desktopStartDnsMessage;

  /// No description provided for @desktopStopDnsTitle.
  ///
  /// In zh, this message translates to:
  /// **'停止 DNS 服务？'**
  String get desktopStopDnsTitle;

  /// No description provided for @desktopStopDnsMessage.
  ///
  /// In zh, this message translates to:
  /// **'停止后本机解析回到系统默认 DNS，接管与规则随之失效。'**
  String get desktopStopDnsMessage;

  /// No description provided for @desktopBackendOfflineTitle.
  ///
  /// In zh, this message translates to:
  /// **'连不上本机服务'**
  String get desktopBackendOfflineTitle;

  /// No description provided for @desktopBackendOfflineBody.
  ///
  /// In zh, this message translates to:
  /// **'确认谛听服务正在运行，并监听 {address}。'**
  String desktopBackendOfflineBody(String address);

  /// No description provided for @desktopBackendUnauthorizedTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要访问令牌'**
  String get desktopBackendUnauthorizedTitle;

  /// No description provided for @desktopBackendUnauthorizedBody.
  ///
  /// In zh, this message translates to:
  /// **'本机服务已启用 IPC 令牌，填入令牌后才能读取状态。'**
  String get desktopBackendUnauthorizedBody;

  /// No description provided for @desktopActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopActionFailed(String message);

  /// No description provided for @desktopLastUpdated.
  ///
  /// In zh, this message translates to:
  /// **'更新于 {time}'**
  String desktopLastUpdated(String time);

  /// No description provided for @desktopRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get desktopRetry;

  /// No description provided for @desktopRecentQueriesTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近查询'**
  String get desktopRecentQueriesTitle;

  /// No description provided for @desktopRecentQueriesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有查询记录'**
  String get desktopRecentQueriesEmpty;

  /// No description provided for @desktopLogWindow24h.
  ///
  /// In zh, this message translates to:
  /// **'近 24 小时'**
  String get desktopLogWindow24h;

  /// No description provided for @desktopLogDomain.
  ///
  /// In zh, this message translates to:
  /// **'域名'**
  String get desktopLogDomain;

  /// No description provided for @desktopLogClient.
  ///
  /// In zh, this message translates to:
  /// **'客户端'**
  String get desktopLogClient;

  /// No description provided for @desktopLogDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'域名包含'**
  String get desktopLogDomainHint;

  /// No description provided for @desktopLogClientHint.
  ///
  /// In zh, this message translates to:
  /// **'客户端 IP 或主机名'**
  String get desktopLogClientHint;

  /// No description provided for @desktopLogAllTypes.
  ///
  /// In zh, this message translates to:
  /// **'全部类型'**
  String get desktopLogAllTypes;

  /// No description provided for @desktopLogClear.
  ///
  /// In zh, this message translates to:
  /// **'清空历史'**
  String get desktopLogClear;

  /// No description provided for @desktopLogClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空查询历史？'**
  String get desktopLogClearTitle;

  /// No description provided for @desktopLogClearBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除全部内存记录与已落盘的历史日志文件，此操作不可撤销。'**
  String get desktopLogClearBody;

  /// No description provided for @desktopLogClearDone.
  ///
  /// In zh, this message translates to:
  /// **'查询历史与统计已清空'**
  String get desktopLogClearDone;

  /// No description provided for @desktopLogClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清空失败：{message}'**
  String desktopLogClearFailed(String message);

  /// No description provided for @desktopLogTopDomains.
  ///
  /// In zh, this message translates to:
  /// **'高频访问域名'**
  String get desktopLogTopDomains;

  /// No description provided for @desktopLogTopBlocked.
  ///
  /// In zh, this message translates to:
  /// **'拦截命中排行'**
  String get desktopLogTopBlocked;

  /// No description provided for @desktopLogTopClients.
  ///
  /// In zh, this message translates to:
  /// **'活跃客户端'**
  String get desktopLogTopClients;

  /// No description provided for @desktopLogNoBlocked.
  ///
  /// In zh, this message translates to:
  /// **'暂无拦截记录'**
  String get desktopLogNoBlocked;

  /// No description provided for @desktopLiveTitle.
  ///
  /// In zh, this message translates to:
  /// **'实时查询流'**
  String get desktopLiveTitle;

  /// No description provided for @desktopLiveConnected.
  ///
  /// In zh, this message translates to:
  /// **'实时监听中'**
  String get desktopLiveConnected;

  /// No description provided for @desktopLivePaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get desktopLivePaused;

  /// No description provided for @desktopLiveDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get desktopLiveDisconnected;

  /// No description provided for @desktopLiveDisconnectedBody.
  ///
  /// In zh, this message translates to:
  /// **'本机事件通道没有连上，实时记录暂停；查询历史与统计仍可正常读取。'**
  String get desktopLiveDisconnectedBody;

  /// No description provided for @desktopLiveShown.
  ///
  /// In zh, this message translates to:
  /// **'符合筛选 {count} 条'**
  String desktopLiveShown(String count);

  /// No description provided for @desktopLiveSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'检索域名或客户端 IP'**
  String get desktopLiveSearchHint;

  /// No description provided for @desktopLiveOnlyBlocked.
  ///
  /// In zh, this message translates to:
  /// **'仅看已拦截'**
  String get desktopLiveOnlyBlocked;

  /// No description provided for @desktopLivePause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get desktopLivePause;

  /// No description provided for @desktopLiveResume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get desktopLiveResume;

  /// No description provided for @desktopLiveClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get desktopLiveClear;

  /// No description provided for @desktopLiveEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有推送的查询'**
  String get desktopLiveEmpty;

  /// No description provided for @desktopLiveCaptured.
  ///
  /// In zh, this message translates to:
  /// **'缓冲区记录'**
  String get desktopLiveCaptured;

  /// No description provided for @desktopLiveBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已拦截'**
  String get desktopLiveBlocked;

  /// No description provided for @desktopLiveSuccessRate.
  ///
  /// In zh, this message translates to:
  /// **'成功率'**
  String get desktopLiveSuccessRate;

  /// No description provided for @desktopLiveBufferNote.
  ///
  /// In zh, this message translates to:
  /// **'滚动缓冲区上限 {count} 条'**
  String desktopLiveBufferNote(String count);

  /// No description provided for @desktopLiveStale.
  ///
  /// In zh, this message translates to:
  /// **'容灾复用'**
  String get desktopLiveStale;

  /// No description provided for @desktopLogConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'查询日志与留存策略'**
  String get desktopLogConfigTitle;

  /// No description provided for @desktopLogConfigEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用查询日志记录'**
  String get desktopLogConfigEnabled;

  /// No description provided for @desktopLogConfigEnabledBody.
  ///
  /// In zh, this message translates to:
  /// **'关闭后不再记录任何查询历史与统计，DNS 解析不受影响'**
  String get desktopLogConfigEnabledBody;

  /// No description provided for @desktopLogConfigMaxEntries.
  ///
  /// In zh, this message translates to:
  /// **'内存缓冲条数'**
  String get desktopLogConfigMaxEntries;

  /// No description provided for @desktopLogConfigRetentionDays.
  ///
  /// In zh, this message translates to:
  /// **'落盘留存天数'**
  String get desktopLogConfigRetentionDays;

  /// No description provided for @desktopLogConfigFile.
  ///
  /// In zh, this message translates to:
  /// **'历史记录落盘'**
  String get desktopLogConfigFile;

  /// No description provided for @desktopLogConfigFileBody.
  ///
  /// In zh, this message translates to:
  /// **'按天写入 JSON-Lines 文件，供历史检索回溯（目录不可写时自动降级为纯内存）'**
  String get desktopLogConfigFileBody;

  /// No description provided for @desktopLogConfigClients.
  ///
  /// In zh, this message translates to:
  /// **'记录客户端信息'**
  String get desktopLogConfigClients;

  /// No description provided for @desktopLogConfigClientsBody.
  ///
  /// In zh, this message translates to:
  /// **'记录发起查询的设备 IP 与主机名；关闭后仅保留域名维度统计'**
  String get desktopLogConfigClientsBody;

  /// No description provided for @desktopLogConfigDataDir.
  ///
  /// In zh, this message translates to:
  /// **'落盘目录：{path}'**
  String desktopLogConfigDataDir(String path);

  /// No description provided for @desktopLogConfigSave.
  ///
  /// In zh, this message translates to:
  /// **'保存策略'**
  String get desktopLogConfigSave;

  /// No description provided for @desktopLogConfigSaved.
  ///
  /// In zh, this message translates to:
  /// **'查询日志配置已保存并生效'**
  String get desktopLogConfigSaved;

  /// No description provided for @desktopLogConfigLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到查询日志配置'**
  String get desktopLogConfigLoadFailed;

  /// No description provided for @desktopLogConfigInvalid.
  ///
  /// In zh, this message translates to:
  /// **'缓冲条数与留存天数需为正整数'**
  String get desktopLogConfigInvalid;

  /// No description provided for @desktopLogPagePrev.
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get desktopLogPagePrev;

  /// No description provided for @desktopLogPageNext.
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get desktopLogPageNext;

  /// No description provided for @desktopLogPageInfo.
  ///
  /// In zh, this message translates to:
  /// **'第 {from}–{to} 条，共 {total} 条'**
  String desktopLogPageInfo(String from, String to, String total);

  /// No description provided for @desktopHubResolveSection.
  ///
  /// In zh, this message translates to:
  /// **'解析服务'**
  String get desktopHubResolveSection;

  /// No description provided for @desktopHubProtectSection.
  ///
  /// In zh, this message translates to:
  /// **'拦截防护'**
  String get desktopHubProtectSection;

  /// No description provided for @desktopHubUpstream.
  ///
  /// In zh, this message translates to:
  /// **'上游解析'**
  String get desktopHubUpstream;

  /// No description provided for @desktopHubUpstreamBody.
  ///
  /// In zh, this message translates to:
  /// **'调度策略、上游节点、Bootstrap 引导与条件分流'**
  String get desktopHubUpstreamBody;

  /// No description provided for @desktopUpstreamTitle.
  ///
  /// In zh, this message translates to:
  /// **'上游解析'**
  String get desktopUpstreamTitle;

  /// No description provided for @desktopUpstreamModeTitle.
  ///
  /// In zh, this message translates to:
  /// **'上游调度策略'**
  String get desktopUpstreamModeTitle;

  /// No description provided for @desktopUpstreamModeBody.
  ///
  /// In zh, this message translates to:
  /// **'选择多服务器协同工作与容灾模式'**
  String get desktopUpstreamModeBody;

  /// No description provided for @desktopUpstreamModeSingle.
  ///
  /// In zh, this message translates to:
  /// **'单服务器模式'**
  String get desktopUpstreamModeSingle;

  /// No description provided for @desktopUpstreamModeSingleBody.
  ///
  /// In zh, this message translates to:
  /// **'始终固定使用列表中的首选服务器进行解析'**
  String get desktopUpstreamModeSingleBody;

  /// No description provided for @desktopUpstreamModeBackup.
  ///
  /// In zh, this message translates to:
  /// **'主备自动容灾'**
  String get desktopUpstreamModeBackup;

  /// No description provided for @desktopUpstreamModeBackupBody.
  ///
  /// In zh, this message translates to:
  /// **'平时优先使用主服务器，超时或故障时自动切换至备用服务器'**
  String get desktopUpstreamModeBackupBody;

  /// No description provided for @desktopUpstreamModeRace.
  ///
  /// In zh, this message translates to:
  /// **'并发极速响应'**
  String get desktopUpstreamModeRace;

  /// No description provided for @desktopUpstreamModeRaceBody.
  ///
  /// In zh, this message translates to:
  /// **'同时向全部服务器发送查询，自动采用最快返回的结果，解析延迟最低'**
  String get desktopUpstreamModeRaceBody;

  /// No description provided for @desktopUpstreamModeSmart.
  ///
  /// In zh, this message translates to:
  /// **'智能延迟优选'**
  String get desktopUpstreamModeSmart;

  /// No description provided for @desktopUpstreamModeSmartBody.
  ///
  /// In zh, this message translates to:
  /// **'根据各服务器近期响应速度与稳定性动态评分，智能选用最优质服务器'**
  String get desktopUpstreamModeSmartBody;

  /// No description provided for @desktopUpstreamNodesTitle.
  ///
  /// In zh, this message translates to:
  /// **'已配置的 DNS 服务器'**
  String get desktopUpstreamNodesTitle;

  /// No description provided for @desktopUpstreamNodesBody.
  ///
  /// In zh, this message translates to:
  /// **'管理用于解析域名的 DNS 服务器，支持加密传输与智能容灾测速'**
  String get desktopUpstreamNodesBody;

  /// No description provided for @desktopUpstreamNodesCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个节点'**
  String desktopUpstreamNodesCount(int count);

  /// No description provided for @desktopUpstreamAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加 DNS 服务器'**
  String get desktopUpstreamAdd;

  /// No description provided for @desktopUpstreamAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加 DNS 服务器'**
  String get desktopUpstreamAddTitle;

  /// No description provided for @desktopUpstreamEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑 DNS 服务器'**
  String get desktopUpstreamEditTitle;

  /// No description provided for @desktopUpstreamName.
  ///
  /// In zh, this message translates to:
  /// **'服务器名称 / 标识'**
  String get desktopUpstreamName;

  /// No description provided for @desktopUpstreamProtocol.
  ///
  /// In zh, this message translates to:
  /// **'连接协议'**
  String get desktopUpstreamProtocol;

  /// No description provided for @desktopUpstreamAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址 (IP 或域名)'**
  String get desktopUpstreamAddress;

  /// No description provided for @desktopUpstreamUrl.
  ///
  /// In zh, this message translates to:
  /// **'加密解析地址 (URL)'**
  String get desktopUpstreamUrl;

  /// No description provided for @desktopUpstreamPin.
  ///
  /// In zh, this message translates to:
  /// **'证书指纹 (可选，SHA-256)'**
  String get desktopUpstreamPin;

  /// No description provided for @desktopUpstreamPinWarning.
  ///
  /// In zh, this message translates to:
  /// **'填写指纹后将替代系统 CA 链校验，仅适用于自签或私有 CA 部署的上游。指纹不匹配时该上游将完全不可用。'**
  String get desktopUpstreamPinWarning;

  /// No description provided for @desktopUpstreamPreset.
  ///
  /// In zh, this message translates to:
  /// **'常用推荐预设'**
  String get desktopUpstreamPreset;

  /// No description provided for @desktopUpstreamPresetProvider.
  ///
  /// In zh, this message translates to:
  /// **'服务商'**
  String get desktopUpstreamPresetProvider;

  /// No description provided for @desktopUpstreamPresetProtocol.
  ///
  /// In zh, this message translates to:
  /// **'解析协议'**
  String get desktopUpstreamPresetProtocol;

  /// No description provided for @desktopUpstreamStamp.
  ///
  /// In zh, this message translates to:
  /// **'DNS 印章 (sdns://)'**
  String get desktopUpstreamStamp;

  /// No description provided for @desktopUpstreamStampHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴印章'**
  String get desktopUpstreamStampHint;

  /// No description provided for @desktopUpstreamStampParse.
  ///
  /// In zh, this message translates to:
  /// **'解析'**
  String get desktopUpstreamStampParse;

  /// No description provided for @desktopUpstreamStampParsing.
  ///
  /// In zh, this message translates to:
  /// **'解析中…'**
  String get desktopUpstreamStampParsing;

  /// No description provided for @desktopUpstreamStampEmpty.
  ///
  /// In zh, this message translates to:
  /// **'请先粘贴 sdns:// 印章'**
  String get desktopUpstreamStampEmpty;

  /// No description provided for @desktopUpstreamStampFailed.
  ///
  /// In zh, this message translates to:
  /// **'印章解析失败：{message}'**
  String desktopUpstreamStampFailed(String message);

  /// No description provided for @desktopUpstreamStampParsed.
  ///
  /// In zh, this message translates to:
  /// **'已解析为 {proto}'**
  String desktopUpstreamStampParsed(String proto);

  /// No description provided for @desktopUpstreamInvalid.
  ///
  /// In zh, this message translates to:
  /// **'服务器名称与地址不得为空'**
  String get desktopUpstreamInvalid;

  /// No description provided for @desktopUpstreamDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get desktopUpstreamDeleteTitle;

  /// No description provided for @desktopUpstreamDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除上游 DNS 服务器 [{name}] 吗？'**
  String desktopUpstreamDeleteBody(String name);

  /// No description provided for @desktopUpstreamKeepOne.
  ///
  /// In zh, this message translates to:
  /// **'请至少保留一个 DNS 服务器以维持正常的域名解析服务。'**
  String get desktopUpstreamKeepOne;

  /// No description provided for @desktopUpstreamEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无配置 DNS 服务器'**
  String get desktopUpstreamEmpty;

  /// No description provided for @desktopUpstreamEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'请添加主备 DNS 服务器后保存。'**
  String get desktopUpstreamEmptyBody;

  /// No description provided for @desktopUpstreamTest.
  ///
  /// In zh, this message translates to:
  /// **'测试延迟'**
  String get desktopUpstreamTest;

  /// No description provided for @desktopUpstreamTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'测试失败：{message}'**
  String desktopUpstreamTestFailed(String message);

  /// No description provided for @desktopUpstreamSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新 DNS 配置失败：{message}'**
  String desktopUpstreamSaveFailed(String message);

  /// No description provided for @desktopUpstreamSaved.
  ///
  /// In zh, this message translates to:
  /// **'DNS 服务器配置已更新并即时生效'**
  String get desktopUpstreamSaved;

  /// No description provided for @desktopUpstreamLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取上游配置失败'**
  String get desktopUpstreamLoadFailed;

  /// No description provided for @desktopUpstreamBootstrapTitle.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 引导解析'**
  String get desktopUpstreamBootstrapTitle;

  /// No description provided for @desktopUpstreamBootstrapBody.
  ///
  /// In zh, this message translates to:
  /// **'建立 DoT（TLS）和 DoH（HTTPS）加密连接前解析上游域名的前置服务器，优先使用纯 IP 地址。'**
  String get desktopUpstreamBootstrapBody;

  /// No description provided for @desktopUpstreamBootstrapOn.
  ///
  /// In zh, this message translates to:
  /// **'引导启用'**
  String get desktopUpstreamBootstrapOn;

  /// No description provided for @desktopUpstreamBootstrapOff.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get desktopUpstreamBootstrapOff;

  /// No description provided for @desktopUpstreamBootstrapAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加引导'**
  String get desktopUpstreamBootstrapAdd;

  /// No description provided for @desktopUpstreamBootstrapEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未配置 Bootstrap DNS 服务器'**
  String get desktopUpstreamBootstrapEmpty;

  /// No description provided for @desktopUpstreamBootstrapKeepOne.
  ///
  /// In zh, this message translates to:
  /// **'请至少保留一个 Bootstrap DNS 服务器，避免加密握手域名无法解析。'**
  String get desktopUpstreamBootstrapKeepOne;

  /// No description provided for @desktopUpstreamBootstrapName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get desktopUpstreamBootstrapName;

  /// No description provided for @desktopUpstreamBootstrapAddress.
  ///
  /// In zh, this message translates to:
  /// **'IP 地址 (可带端口)'**
  String get desktopUpstreamBootstrapAddress;

  /// No description provided for @desktopUpstreamBootstrapInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请填写名称与 IP 地址'**
  String get desktopUpstreamBootstrapInvalid;

  /// No description provided for @desktopUpstreamBootstrapDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除引导服务器 [{name}] 吗？'**
  String desktopUpstreamBootstrapDeleteBody(String name);

  /// No description provided for @desktopUpstreamRoutesTitle.
  ///
  /// In zh, this message translates to:
  /// **'条件分流路由'**
  String get desktopUpstreamRoutesTitle;

  /// No description provided for @desktopUpstreamRoutesBody.
  ///
  /// In zh, this message translates to:
  /// **'为内部私有域名定向指定专用 DNS 服务器，支持 *.internal 这类泛域名'**
  String get desktopUpstreamRoutesBody;

  /// No description provided for @desktopUpstreamRoutesAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加分流规则'**
  String get desktopUpstreamRoutesAdd;

  /// No description provided for @desktopUpstreamRoutesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂未配置条件分流路由，全部域名请求遵循全局调度模式。'**
  String get desktopUpstreamRoutesEmpty;

  /// No description provided for @desktopUpstreamRouteDomain.
  ///
  /// In zh, this message translates to:
  /// **'匹配域名或后缀'**
  String get desktopUpstreamRouteDomain;

  /// No description provided for @desktopUpstreamRouteServer.
  ///
  /// In zh, this message translates to:
  /// **'定向 DNS 服务器地址'**
  String get desktopUpstreamRouteServer;

  /// No description provided for @desktopUpstreamRouteInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请填写匹配域名与目标 DNS 地址'**
  String get desktopUpstreamRouteInvalid;

  /// No description provided for @desktopUpstreamRouteDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除匹配域名 [{domain}] 的分流规则吗？'**
  String desktopUpstreamRouteDeleteBody(String domain);

  /// No description provided for @desktopUpstreamFallbackPolicyTitle.
  ///
  /// In zh, this message translates to:
  /// **'回退触发条件'**
  String get desktopUpstreamFallbackPolicyTitle;

  /// No description provided for @desktopUpstreamFallbackPolicyBody.
  ///
  /// In zh, this message translates to:
  /// **'何时改用备用上游：超时、应答码与解析失败'**
  String get desktopUpstreamFallbackPolicyBody;

  /// No description provided for @desktopUpstreamFallbackPolicyOff.
  ///
  /// In zh, this message translates to:
  /// **'备用链未开启，触发条件暂不生效。'**
  String get desktopUpstreamFallbackPolicyOff;

  /// No description provided for @desktopUpstreamFallbackTitle.
  ///
  /// In zh, this message translates to:
  /// **'独立回退上游'**
  String get desktopUpstreamFallbackTitle;

  /// No description provided for @desktopUpstreamFallbackBody.
  ///
  /// In zh, this message translates to:
  /// **'主链路整体失效后整链切换的备用解析链路'**
  String get desktopUpstreamFallbackBody;

  /// No description provided for @desktopUpstreamFallbackOff.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get desktopUpstreamFallbackOff;

  /// No description provided for @desktopUpstreamFallbackCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个回退节点'**
  String desktopUpstreamFallbackCount(int count);

  /// No description provided for @desktopUpstreamFallbackNote.
  ///
  /// In zh, this message translates to:
  /// **'与主链路是两条独立链路：主链路先以独立超时尝试整条链，失败或命中下列响应码后，才整链切换到回退上游。'**
  String get desktopUpstreamFallbackNote;

  /// No description provided for @desktopUpstreamFallbackEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未配置回退上游，DNS 查询量不会因此增加。'**
  String get desktopUpstreamFallbackEmpty;

  /// No description provided for @desktopUpstreamFallbackAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加回退节点'**
  String get desktopUpstreamFallbackAdd;

  /// No description provided for @desktopUpstreamFallbackTimeout.
  ///
  /// In zh, this message translates to:
  /// **'主链路独立超时（毫秒）'**
  String get desktopUpstreamFallbackTimeout;

  /// No description provided for @desktopUpstreamFallbackTimeoutHint.
  ///
  /// In zh, this message translates to:
  /// **'留空或 0 使用服务端默认 2000ms，取值范围 100–30000。'**
  String get desktopUpstreamFallbackTimeoutHint;

  /// No description provided for @desktopUpstreamFallbackRcode.
  ///
  /// In zh, this message translates to:
  /// **'触发回退的响应码'**
  String get desktopUpstreamFallbackRcode;

  /// No description provided for @desktopUpstreamFallbackRcodeHint.
  ///
  /// In zh, this message translates to:
  /// **'默认仅 SERVFAIL 与 REFUSED。NXDOMAIN 是权威有效判定，勾选它会让「域名不存在」也去问备用上游。'**
  String get desktopUpstreamFallbackRcodeHint;

  /// No description provided for @desktopUpstreamFallbackOnError.
  ///
  /// In zh, this message translates to:
  /// **'超时、连接失败等链路故障同样触发回退'**
  String get desktopUpstreamFallbackOnError;

  /// No description provided for @desktopUpstreamWeight.
  ///
  /// In zh, this message translates to:
  /// **'权重 {weight}'**
  String desktopUpstreamWeight(int weight);

  /// No description provided for @desktopUpstreamPinSet.
  ///
  /// In zh, this message translates to:
  /// **'指纹固定'**
  String get desktopUpstreamPinSet;

  /// No description provided for @desktopUpstreamPresetMissing.
  ///
  /// In zh, this message translates to:
  /// **'该服务商未提供此协议的公开端点，请手动填写'**
  String get desktopUpstreamPresetMissing;

  /// No description provided for @desktopUpstreamProbeFailed.
  ///
  /// In zh, this message translates to:
  /// **'测试失败'**
  String get desktopUpstreamProbeFailed;

  /// No description provided for @desktopUpstreamBootstrapAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加 Bootstrap DNS 服务器'**
  String get desktopUpstreamBootstrapAddTitle;

  /// No description provided for @desktopUpstreamBootstrapEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑 Bootstrap DNS 服务器'**
  String get desktopUpstreamBootstrapEditTitle;

  /// No description provided for @desktopHubCache.
  ///
  /// In zh, this message translates to:
  /// **'解析缓存'**
  String get desktopHubCache;

  /// No description provided for @desktopHubCacheBody.
  ///
  /// In zh, this message translates to:
  /// **'命中率、容量、TTL 策略、排除规则与落盘持久化'**
  String get desktopHubCacheBody;

  /// No description provided for @desktopCacheEngineTitle.
  ///
  /// In zh, this message translates to:
  /// **'智能解析加速引擎'**
  String get desktopCacheEngineTitle;

  /// No description provided for @desktopCacheEngineBody.
  ///
  /// In zh, this message translates to:
  /// **'自动缓存已访问过的解析结果，下次访问直接返回；上游抖动时复用近期记录兜底。'**
  String get desktopCacheEngineBody;

  /// No description provided for @desktopCacheEngineOn.
  ///
  /// In zh, this message translates to:
  /// **'加速生效中'**
  String get desktopCacheEngineOn;

  /// No description provided for @desktopCacheEngineOff.
  ///
  /// In zh, this message translates to:
  /// **'加速已停用'**
  String get desktopCacheEngineOff;

  /// No description provided for @desktopCacheHitRatio.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中率'**
  String get desktopCacheHitRatio;

  /// No description provided for @desktopCacheRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新数据'**
  String get desktopCacheRefresh;

  /// No description provided for @desktopCacheClear.
  ///
  /// In zh, this message translates to:
  /// **'一键清空缓存'**
  String get desktopCacheClear;

  /// No description provided for @desktopCacheClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'确定清空所有加速缓存？'**
  String get desktopCacheClearTitle;

  /// No description provided for @desktopCacheClearBody.
  ///
  /// In zh, this message translates to:
  /// **'此操作将清空当前全部已缓存的网址记录（共 {count} 条）。清空后后续访问将重新通过网络解析。'**
  String desktopCacheClearBody(int count);

  /// No description provided for @desktopCacheClearDone.
  ///
  /// In zh, this message translates to:
  /// **'加速缓存已全部清空'**
  String get desktopCacheClearDone;

  /// No description provided for @desktopCacheClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清空缓存失败：{message}'**
  String desktopCacheClearFailed(String message);

  /// No description provided for @desktopCacheTelemetryTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存遥测指标'**
  String get desktopCacheTelemetryTitle;

  /// No description provided for @desktopCacheTelemetryCapacity.
  ///
  /// In zh, this message translates to:
  /// **'容量 {used} / {max}'**
  String desktopCacheTelemetryCapacity(int used, int max);

  /// No description provided for @desktopCacheMisses.
  ///
  /// In zh, this message translates to:
  /// **'实时联网解析'**
  String get desktopCacheMisses;

  /// No description provided for @desktopCacheStaleHits.
  ///
  /// In zh, this message translates to:
  /// **'弱网应急保障'**
  String get desktopCacheStaleHits;

  /// No description provided for @desktopCacheNegativeHits.
  ///
  /// In zh, this message translates to:
  /// **'无效网址拦截'**
  String get desktopCacheNegativeHits;

  /// No description provided for @desktopCachePrefetchCount.
  ///
  /// In zh, this message translates to:
  /// **'热点预取刷新'**
  String get desktopCachePrefetchCount;

  /// No description provided for @desktopCacheTopTitle.
  ///
  /// In zh, this message translates to:
  /// **'高频访问网址排行'**
  String get desktopCacheTopTitle;

  /// No description provided for @desktopCacheTopBody.
  ///
  /// In zh, this message translates to:
  /// **'本地缓存命中次数最高的前 10 个域名'**
  String get desktopCacheTopBody;

  /// No description provided for @desktopCacheTopEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无高频网址访问记录'**
  String get desktopCacheTopEmpty;

  /// No description provided for @desktopCacheTopHits.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String desktopCacheTopHits(int count);

  /// No description provided for @desktopCacheConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'加速策略设置'**
  String get desktopCacheConfigTitle;

  /// No description provided for @desktopCacheConfigBody.
  ///
  /// In zh, this message translates to:
  /// **'有效期规则、弱网容灾与热点预取'**
  String get desktopCacheConfigBody;

  /// No description provided for @desktopCacheConfigSave.
  ///
  /// In zh, this message translates to:
  /// **'保存策略'**
  String get desktopCacheConfigSave;

  /// No description provided for @desktopCacheConfigSaved.
  ///
  /// In zh, this message translates to:
  /// **'加速策略已保存并即时生效'**
  String get desktopCacheConfigSaved;

  /// No description provided for @desktopCacheFallbackTitle.
  ///
  /// In zh, this message translates to:
  /// **'弱网回退'**
  String get desktopCacheFallbackTitle;

  /// No description provided for @desktopCacheFallbackBody.
  ///
  /// In zh, this message translates to:
  /// **'上游抖动时用过期记录兜底，以及先回旧值再刷新的乐观模式'**
  String get desktopCacheFallbackBody;

  /// No description provided for @desktopCacheModeLabel.
  ///
  /// In zh, this message translates to:
  /// **'记录有效期计算方式'**
  String get desktopCacheModeLabel;

  /// No description provided for @desktopCacheModeLimit.
  ///
  /// In zh, this message translates to:
  /// **'限制最长有效期（推荐）'**
  String get desktopCacheModeLimit;

  /// No description provided for @desktopCacheModeFollow.
  ///
  /// In zh, this message translates to:
  /// **'完全遵从上游 TTL'**
  String get desktopCacheModeFollow;

  /// No description provided for @desktopCacheModeFixed.
  ///
  /// In zh, this message translates to:
  /// **'强制使用固定有效期'**
  String get desktopCacheModeFixed;

  /// No description provided for @desktopCacheMaxTtl.
  ///
  /// In zh, this message translates to:
  /// **'最长保存时长（秒）'**
  String get desktopCacheMaxTtl;

  /// No description provided for @desktopCacheMinTtl.
  ///
  /// In zh, this message translates to:
  /// **'最短保留时长（秒）'**
  String get desktopCacheMinTtl;

  /// No description provided for @desktopCacheFixedTtl.
  ///
  /// In zh, this message translates to:
  /// **'固定有效期（秒）'**
  String get desktopCacheFixedTtl;

  /// No description provided for @desktopCacheMinTtlEnabled.
  ///
  /// In zh, this message translates to:
  /// **'应用最短保留时长'**
  String get desktopCacheMinTtlEnabled;

  /// No description provided for @desktopCacheStaleTitle.
  ///
  /// In zh, this message translates to:
  /// **'弱网应急保障（旧记录兜底）'**
  String get desktopCacheStaleTitle;

  /// No description provided for @desktopCacheStaleBody.
  ///
  /// In zh, this message translates to:
  /// **'上游超时或断网时，复用近期缓存防止网页报错'**
  String get desktopCacheStaleBody;

  /// No description provided for @desktopCacheStaleSeconds.
  ///
  /// In zh, this message translates to:
  /// **'应急保留期（秒）'**
  String get desktopCacheStaleSeconds;

  /// No description provided for @desktopCacheOptimistic.
  ///
  /// In zh, this message translates to:
  /// **'极速响应'**
  String get desktopCacheOptimistic;

  /// No description provided for @desktopCacheOptimisticBody.
  ///
  /// In zh, this message translates to:
  /// **'先返回缓存，后台静默刷新'**
  String get desktopCacheOptimisticBody;

  /// No description provided for @desktopCacheNegative.
  ///
  /// In zh, this message translates to:
  /// **'无效网址记忆加速'**
  String get desktopCacheNegative;

  /// No description provided for @desktopCacheNegativeBody.
  ///
  /// In zh, this message translates to:
  /// **'记住不存在或错误的域名，避免频繁重复重试'**
  String get desktopCacheNegativeBody;

  /// No description provided for @desktopCacheNegativeSeconds.
  ///
  /// In zh, this message translates to:
  /// **'无效记录保留（秒）'**
  String get desktopCacheNegativeSeconds;

  /// No description provided for @desktopCachePrefetchTitle.
  ///
  /// In zh, this message translates to:
  /// **'热点域名主动预取'**
  String get desktopCachePrefetchTitle;

  /// No description provided for @desktopCachePrefetchBody.
  ///
  /// In zh, this message translates to:
  /// **'在常用域名记录到期前提前回源刷新，避免首次访问等待'**
  String get desktopCachePrefetchBody;

  /// No description provided for @desktopCachePrefetchThreshold.
  ///
  /// In zh, this message translates to:
  /// **'命中次数门槛'**
  String get desktopCachePrefetchThreshold;

  /// No description provided for @desktopCachePrefetchThresholdHint.
  ///
  /// In zh, this message translates to:
  /// **'被访问达到该次数的域名才会预取'**
  String get desktopCachePrefetchThresholdHint;

  /// No description provided for @desktopCachePrefetchBefore.
  ///
  /// In zh, this message translates to:
  /// **'剩余有效期阈值（毫秒）'**
  String get desktopCachePrefetchBefore;

  /// No description provided for @desktopCachePrefetchBeforeHint.
  ///
  /// In zh, this message translates to:
  /// **'剩余有效期低于该值时触发刷新'**
  String get desktopCachePrefetchBeforeHint;

  /// No description provided for @desktopCacheInvalidNumbers.
  ///
  /// In zh, this message translates to:
  /// **'秒数与阈值需为正整数'**
  String get desktopCacheInvalidNumbers;

  /// No description provided for @desktopCacheSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存缓存配置失败：{message}'**
  String desktopCacheSaveFailed(String message);

  /// No description provided for @desktopCacheLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到缓存配置'**
  String get desktopCacheLoadFailed;

  /// No description provided for @desktopCachePersistTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存落盘持久化'**
  String get desktopCachePersistTitle;

  /// No description provided for @desktopCachePersistBody.
  ///
  /// In zh, this message translates to:
  /// **'把内存中的解析结果定期写入磁盘，服务重启后可直接读回。默认关闭：读取上次的应答会让「上游已变更但仍命中旧记录」更难察觉。'**
  String get desktopCachePersistBody;

  /// No description provided for @desktopCachePersistOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启'**
  String get desktopCachePersistOn;

  /// No description provided for @desktopCachePersistOff.
  ///
  /// In zh, this message translates to:
  /// **'未开启'**
  String get desktopCachePersistOff;

  /// No description provided for @desktopCachePersistInterval.
  ///
  /// In zh, this message translates to:
  /// **'定时落盘间隔（秒）'**
  String get desktopCachePersistInterval;

  /// No description provided for @desktopCachePersistIntervalHint.
  ///
  /// In zh, this message translates to:
  /// **'取值范围 30–86400；留空或 0 使用默认值 300。服务退出时总会额外写一次。'**
  String get desktopCachePersistIntervalHint;

  /// No description provided for @desktopCachePersistPath.
  ///
  /// In zh, this message translates to:
  /// **'落盘文件'**
  String get desktopCachePersistPath;

  /// No description provided for @desktopCachePersistLastError.
  ///
  /// In zh, this message translates to:
  /// **'最近一次落盘失败：{message}'**
  String desktopCachePersistLastError(String message);

  /// No description provided for @desktopCachePersistRecords.
  ///
  /// In zh, this message translates to:
  /// **'当前 {count} 条可落盘记录'**
  String desktopCachePersistRecords(int count);

  /// No description provided for @desktopCacheSnapshotTitle.
  ///
  /// In zh, this message translates to:
  /// **'磁盘快照'**
  String get desktopCacheSnapshotTitle;

  /// No description provided for @desktopCacheSnapshotBody.
  ///
  /// In zh, this message translates to:
  /// **'把当前缓存立即写入落盘文件，或从文件读回上次的记录'**
  String get desktopCacheSnapshotBody;

  /// No description provided for @desktopCachePersistDump.
  ///
  /// In zh, this message translates to:
  /// **'立即落盘'**
  String get desktopCachePersistDump;

  /// No description provided for @desktopCachePersistLoad.
  ///
  /// In zh, this message translates to:
  /// **'从文件恢复'**
  String get desktopCachePersistLoad;

  /// No description provided for @desktopCachePersistDumpDone.
  ///
  /// In zh, this message translates to:
  /// **'已落盘 {count} 条缓存记录'**
  String desktopCachePersistDumpDone(int count);

  /// No description provided for @desktopCachePersistLoadDone.
  ///
  /// In zh, this message translates to:
  /// **'已从落盘文件恢复 {count} 条缓存记录'**
  String desktopCachePersistLoadDone(int count);

  /// No description provided for @desktopCachePersistDumpFailed.
  ///
  /// In zh, this message translates to:
  /// **'落盘失败：{message}'**
  String desktopCachePersistDumpFailed(String message);

  /// No description provided for @desktopCachePersistLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败：{message}'**
  String desktopCachePersistLoadFailed(String message);

  /// No description provided for @desktopCachePersistLoadTitle.
  ///
  /// In zh, this message translates to:
  /// **'确定从落盘文件恢复缓存？'**
  String get desktopCachePersistLoadTitle;

  /// No description provided for @desktopCachePersistLoadBody.
  ///
  /// In zh, this message translates to:
  /// **'文件中仍有效的记录会被读入当前缓存，覆盖同名的现有条目；已过期的记录会被自动忽略。'**
  String get desktopCachePersistLoadBody;

  /// No description provided for @desktopCachePersistToggleOn.
  ///
  /// In zh, this message translates to:
  /// **'缓存落盘已开启'**
  String get desktopCachePersistToggleOn;

  /// No description provided for @desktopCachePersistToggleOff.
  ///
  /// In zh, this message translates to:
  /// **'缓存落盘已关闭'**
  String get desktopCachePersistToggleOff;

  /// No description provided for @desktopCachePersistIntervalSaved.
  ///
  /// In zh, this message translates to:
  /// **'落盘间隔已更新'**
  String get desktopCachePersistIntervalSaved;

  /// No description provided for @desktopCacheExcludeTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存排除规则'**
  String get desktopCacheExcludeTitle;

  /// No description provided for @desktopCacheExcludeBody.
  ///
  /// In zh, this message translates to:
  /// **'命中规则的域名既不读取也不写入缓存，每次都实时回源。适用于内网域名、动态 IP 探测等「缓存反而出错」的场景。'**
  String get desktopCacheExcludeBody;

  /// No description provided for @desktopCacheExcludeOff.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get desktopCacheExcludeOff;

  /// No description provided for @desktopCacheExcludeCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条规则'**
  String desktopCacheExcludeCount(int count);

  /// No description provided for @desktopCacheExcludeLabel.
  ///
  /// In zh, this message translates to:
  /// **'正则表达式（一行一条，Go RE2 语法）'**
  String get desktopCacheExcludeLabel;

  /// No description provided for @desktopCacheExcludeHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：\\.local\$'**
  String get desktopCacheExcludeHint;

  /// No description provided for @desktopCacheExcludeSave.
  ///
  /// In zh, this message translates to:
  /// **'保存规则'**
  String get desktopCacheExcludeSave;

  /// No description provided for @desktopCacheExcludeSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {count} 条排除规则'**
  String desktopCacheExcludeSaved(int count);

  /// No description provided for @desktopCacheExcludeCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清空排除规则，全部域名重新参与缓存'**
  String get desktopCacheExcludeCleared;

  /// No description provided for @desktopCacheExcludeFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存排除规则失败：{message}'**
  String desktopCacheExcludeFailed(String message);

  /// No description provided for @desktopCacheExcludeHits.
  ///
  /// In zh, this message translates to:
  /// **'已拦截 {count} 次缓存读写'**
  String desktopCacheExcludeHits(int count);

  /// No description provided for @desktopCacheExcludeReset.
  ///
  /// In zh, this message translates to:
  /// **'撤销修改'**
  String get desktopCacheExcludeReset;

  /// No description provided for @desktopCacheExcludeTooMany.
  ///
  /// In zh, this message translates to:
  /// **'规则超过 {max} 条，超出部分不会被保存'**
  String desktopCacheExcludeTooMany(int max);

  /// No description provided for @desktopCacheExcludeTooLong.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条规则超过 {max} 字符，保存时会被忽略'**
  String desktopCacheExcludeTooLong(int count, int max);

  /// No description provided for @desktopCacheExcludePresetLocal.
  ///
  /// In zh, this message translates to:
  /// **'内网单标签域'**
  String get desktopCacheExcludePresetLocal;

  /// No description provided for @desktopCacheExcludePresetPtr.
  ///
  /// In zh, this message translates to:
  /// **'PTR 反查'**
  String get desktopCacheExcludePresetPtr;

  /// No description provided for @desktopCacheExcludePresetProbe.
  ///
  /// In zh, this message translates to:
  /// **'临时探测域'**
  String get desktopCacheExcludePresetProbe;

  /// No description provided for @desktopCacheEntriesTitle.
  ///
  /// In zh, this message translates to:
  /// **'已缓存域名明细'**
  String get desktopCacheEntriesTitle;

  /// No description provided for @desktopCacheEntriesBody.
  ///
  /// In zh, this message translates to:
  /// **'实时查看分片缓存记录、TTL 有效期与解析 IP'**
  String get desktopCacheEntriesBody;

  /// No description provided for @desktopCacheEntriesSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索网址或记录类型…'**
  String get desktopCacheEntriesSearch;

  /// No description provided for @desktopCacheEntriesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未匹配到符合条件的缓存条目'**
  String get desktopCacheEntriesEmpty;

  /// No description provided for @desktopCacheEntriesNone.
  ///
  /// In zh, this message translates to:
  /// **'缓存中暂无记录'**
  String get desktopCacheEntriesNone;

  /// No description provided for @desktopCacheEntriesLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取缓存条目失败'**
  String get desktopCacheEntriesLoadFailed;

  /// No description provided for @desktopCacheFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get desktopCacheFilterAll;

  /// No description provided for @desktopCacheFilterFresh.
  ///
  /// In zh, this message translates to:
  /// **'有效记录'**
  String get desktopCacheFilterFresh;

  /// No description provided for @desktopCacheFilterStale.
  ///
  /// In zh, this message translates to:
  /// **'应急备用'**
  String get desktopCacheFilterStale;

  /// No description provided for @desktopCacheFilterNegative.
  ///
  /// In zh, this message translates to:
  /// **'无效网址'**
  String get desktopCacheFilterNegative;

  /// No description provided for @desktopCacheEntryDomain.
  ///
  /// In zh, this message translates to:
  /// **'网址 / 域名'**
  String get desktopCacheEntryDomain;

  /// No description provided for @desktopCacheEntryType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get desktopCacheEntryType;

  /// No description provided for @desktopCacheEntryStatus.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get desktopCacheEntryStatus;

  /// No description provided for @desktopCacheEntryRemaining.
  ///
  /// In zh, this message translates to:
  /// **'剩余有效期'**
  String get desktopCacheEntryRemaining;

  /// No description provided for @desktopCacheEntryTtl.
  ///
  /// In zh, this message translates to:
  /// **'初始 TTL'**
  String get desktopCacheEntryTtl;

  /// No description provided for @desktopCacheEntryHits.
  ///
  /// In zh, this message translates to:
  /// **'命中次数'**
  String get desktopCacheEntryHits;

  /// No description provided for @desktopCacheEntryIps.
  ///
  /// In zh, this message translates to:
  /// **'解析 IP 列表'**
  String get desktopCacheEntryIps;

  /// No description provided for @desktopCacheStatusFresh.
  ///
  /// In zh, this message translates to:
  /// **'有效'**
  String get desktopCacheStatusFresh;

  /// No description provided for @desktopCacheStatusStale.
  ///
  /// In zh, this message translates to:
  /// **'应急备用'**
  String get desktopCacheStatusStale;

  /// No description provided for @desktopCacheStatusNegative.
  ///
  /// In zh, this message translates to:
  /// **'无效网址'**
  String get desktopCacheStatusNegative;

  /// No description provided for @desktopCacheNoIps.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get desktopCacheNoIps;

  /// No description provided for @desktopHubRewrite.
  ///
  /// In zh, this message translates to:
  /// **'自定义重写'**
  String get desktopHubRewrite;

  /// No description provided for @desktopHubRewriteBody.
  ///
  /// In zh, this message translates to:
  /// **'把域名指向指定 IP、别名或 TXT，本地直接权威应答'**
  String get desktopHubRewriteBody;

  /// No description provided for @desktopRewriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DNS 重写'**
  String get desktopRewriteTitle;

  /// No description provided for @desktopRewriteEngineTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DNS 重写与域名伪装'**
  String get desktopRewriteEngineTitle;

  /// No description provided for @desktopRewriteEngineBody.
  ///
  /// In zh, this message translates to:
  /// **'匹配规则在上游解析前直接权威应答，无需等待外网请求；支持精确域名与 *.lan 泛域名。'**
  String get desktopRewriteEngineBody;

  /// No description provided for @desktopRewriteEngineOn.
  ///
  /// In zh, this message translates to:
  /// **'重写引擎已就绪'**
  String get desktopRewriteEngineOn;

  /// No description provided for @desktopRewriteEngineOff.
  ///
  /// In zh, this message translates to:
  /// **'重写引擎已停用'**
  String get desktopRewriteEngineOff;

  /// No description provided for @desktopRewriteEnabled.
  ///
  /// In zh, this message translates to:
  /// **'重写已启用'**
  String get desktopRewriteEnabled;

  /// No description provided for @desktopRewriteDisabled.
  ///
  /// In zh, this message translates to:
  /// **'重写已关闭'**
  String get desktopRewriteDisabled;

  /// No description provided for @desktopRewriteDefaultTtl.
  ///
  /// In zh, this message translates to:
  /// **'默认生存期（秒）'**
  String get desktopRewriteDefaultTtl;

  /// No description provided for @desktopRewriteTtlSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get desktopRewriteTtlSave;

  /// No description provided for @desktopRewriteTtlSaved.
  ///
  /// In zh, this message translates to:
  /// **'默认重写 TTL 已保存'**
  String get desktopRewriteTtlSaved;

  /// No description provided for @desktopRewriteTtlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'TTL 需为正整数'**
  String get desktopRewriteTtlInvalid;

  /// No description provided for @desktopRewriteToggleOn.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DNS 重写已开启'**
  String get desktopRewriteToggleOn;

  /// No description provided for @desktopRewriteToggleOff.
  ///
  /// In zh, this message translates to:
  /// **'自定义 DNS 重写已关闭'**
  String get desktopRewriteToggleOff;

  /// No description provided for @desktopRewriteSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存重写配置失败：{message}'**
  String desktopRewriteSaveFailed(String message);

  /// No description provided for @desktopRewriteLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到 DNS 重写配置'**
  String get desktopRewriteLoadFailed;

  /// No description provided for @desktopRewriteRulesTitle.
  ///
  /// In zh, this message translates to:
  /// **'DNS 重写规则列表'**
  String get desktopRewriteRulesTitle;

  /// No description provided for @desktopRewriteRulesBody.
  ///
  /// In zh, this message translates to:
  /// **'当前生效的自定义伪装映射'**
  String get desktopRewriteRulesBody;

  /// No description provided for @desktopRewriteRulesCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条规则'**
  String desktopRewriteRulesCount(int count);

  /// No description provided for @desktopRewriteAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加重写规则'**
  String get desktopRewriteAdd;

  /// No description provided for @desktopRewriteSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索域名、目标 IP 或别名…'**
  String get desktopRewriteSearch;

  /// No description provided for @desktopRewriteEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂未添加任何 DNS 重写规则，点击上方按钮即可添加'**
  String get desktopRewriteEmpty;

  /// No description provided for @desktopRewriteNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'未找到符合条件的重写规则'**
  String get desktopRewriteNoMatch;

  /// No description provided for @desktopRewriteResetSearch.
  ///
  /// In zh, this message translates to:
  /// **'清除检索'**
  String get desktopRewriteResetSearch;

  /// No description provided for @desktopRewriteDomain.
  ///
  /// In zh, this message translates to:
  /// **'匹配域名'**
  String get desktopRewriteDomain;

  /// No description provided for @desktopRewriteTypes.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get desktopRewriteTypes;

  /// No description provided for @desktopRewriteTarget.
  ///
  /// In zh, this message translates to:
  /// **'重写目标详情'**
  String get desktopRewriteTarget;

  /// No description provided for @desktopRewriteTtl.
  ///
  /// In zh, this message translates to:
  /// **'TTL'**
  String get desktopRewriteTtl;

  /// No description provided for @desktopRewriteActions.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get desktopRewriteActions;

  /// No description provided for @desktopRewriteEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑重写规则'**
  String get desktopRewriteEdit;

  /// No description provided for @desktopRewriteDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除规则'**
  String get desktopRewriteDelete;

  /// No description provided for @desktopRewriteSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{count} 秒'**
  String desktopRewriteSeconds(int count);

  /// No description provided for @desktopRewriteNoTarget.
  ///
  /// In zh, this message translates to:
  /// **'无目标'**
  String get desktopRewriteNoTarget;

  /// No description provided for @desktopRewriteRcodeOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅返回 {rcode}，不返回任何记录'**
  String desktopRewriteRcodeOnly(String rcode);

  /// No description provided for @desktopRewriteDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除 DNS 重写规则'**
  String get desktopRewriteDeleteTitle;

  /// No description provided for @desktopRewriteDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除域名「{domain}」的 DNS 重写规则吗？'**
  String desktopRewriteDeleteBody(String domain);

  /// No description provided for @desktopRewriteRuleSaved.
  ///
  /// In zh, this message translates to:
  /// **'重写规则「{domain}」已保存并生效'**
  String desktopRewriteRuleSaved(String domain);

  /// No description provided for @desktopRewriteRuleDeleted.
  ///
  /// In zh, this message translates to:
  /// **'重写规则「{domain}」已删除'**
  String desktopRewriteRuleDeleted(String domain);

  /// No description provided for @desktopRewriteRuleFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存重写规则失败：{message}'**
  String desktopRewriteRuleFailed(String message);

  /// No description provided for @desktopRewriteDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除规则失败：{message}'**
  String desktopRewriteDeleteFailed(String message);

  /// No description provided for @desktopRewriteAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加 DNS 重写与伪装规则'**
  String get desktopRewriteAddTitle;

  /// No description provided for @desktopRewriteEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑 DNS 重写规则'**
  String get desktopRewriteEditTitle;

  /// No description provided for @desktopRewriteDomainLabel.
  ///
  /// In zh, this message translates to:
  /// **'匹配域名'**
  String get desktopRewriteDomainLabel;

  /// No description provided for @desktopRewriteDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'如 host.lan 或 *.home.local'**
  String get desktopRewriteDomainHint;

  /// No description provided for @desktopRewriteDomainHelp.
  ///
  /// In zh, this message translates to:
  /// **'支持精确域名（如 router.lan）或泛域名（如 *.cluster.internal）'**
  String get desktopRewriteDomainHelp;

  /// No description provided for @desktopRewriteDomainRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入匹配域名（支持精准匹配或 *.lan 泛域名）'**
  String get desktopRewriteDomainRequired;

  /// No description provided for @desktopRewriteTargetMode.
  ///
  /// In zh, this message translates to:
  /// **'应答目标'**
  String get desktopRewriteTargetMode;

  /// No description provided for @desktopRewriteModeShortcut.
  ///
  /// In zh, this message translates to:
  /// **'快捷目标'**
  String get desktopRewriteModeShortcut;

  /// No description provided for @desktopRewriteModeRecords.
  ///
  /// In zh, this message translates to:
  /// **'自定义记录'**
  String get desktopRewriteModeRecords;

  /// No description provided for @desktopRewriteTargetType.
  ///
  /// In zh, this message translates to:
  /// **'重写目标类型'**
  String get desktopRewriteTargetType;

  /// No description provided for @desktopRewriteTypeIp.
  ///
  /// In zh, this message translates to:
  /// **'A / AAAA 地址'**
  String get desktopRewriteTypeIp;

  /// No description provided for @desktopRewriteTypeCname.
  ///
  /// In zh, this message translates to:
  /// **'CNAME 别名'**
  String get desktopRewriteTypeCname;

  /// No description provided for @desktopRewriteTypeTxt.
  ///
  /// In zh, this message translates to:
  /// **'TXT 文本'**
  String get desktopRewriteTypeTxt;

  /// No description provided for @desktopRewriteIpsLabel.
  ///
  /// In zh, this message translates to:
  /// **'IPv4 / IPv6 目标解析地址'**
  String get desktopRewriteIpsLabel;

  /// No description provided for @desktopRewriteIpsHelp.
  ///
  /// In zh, this message translates to:
  /// **'每行一个 IP 地址，支持多 IP 负载均衡返回'**
  String get desktopRewriteIpsHelp;

  /// No description provided for @desktopRewriteCnameLabel.
  ///
  /// In zh, this message translates to:
  /// **'CNAME 目标重定向域名'**
  String get desktopRewriteCnameLabel;

  /// No description provided for @desktopRewriteCnameHelp.
  ///
  /// In zh, this message translates to:
  /// **'系统将自动遵循别名链进行递归解析'**
  String get desktopRewriteCnameHelp;

  /// No description provided for @desktopRewriteTxtLabel.
  ///
  /// In zh, this message translates to:
  /// **'TXT 记录内容（每行一条）'**
  String get desktopRewriteTxtLabel;

  /// No description provided for @desktopRewriteRecordsLabel.
  ///
  /// In zh, this message translates to:
  /// **'自定义记录'**
  String get desktopRewriteRecordsLabel;

  /// No description provided for @desktopRewriteRecordAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加记录'**
  String get desktopRewriteRecordAdd;

  /// No description provided for @desktopRewriteRecordEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未添加记录，点击「添加记录」开始'**
  String get desktopRewriteRecordEmpty;

  /// No description provided for @desktopRewriteRecordValueHint.
  ///
  /// In zh, this message translates to:
  /// **'记录取值'**
  String get desktopRewriteRecordValueHint;

  /// No description provided for @desktopRewriteRecordsHelp.
  ///
  /// In zh, this message translates to:
  /// **'取值语法与 AdGuard 的 dnsrewrite 一致：MX 填「优先级 主机」，SRV 填「优先级 权重 端口 目标」，HTTPS/SVCB 填「优先级 目标 参数…」。仅与匹配记录类型的查询返回这些记录。'**
  String get desktopRewriteRecordsHelp;

  /// No description provided for @desktopRewriteRcodeLabel.
  ///
  /// In zh, this message translates to:
  /// **'应答码覆盖（可选）'**
  String get desktopRewriteRcodeLabel;

  /// No description provided for @desktopRewriteRcodeNone.
  ///
  /// In zh, this message translates to:
  /// **'不覆盖（正常返回记录）'**
  String get desktopRewriteRcodeNone;

  /// No description provided for @desktopRewriteRcodeWarning.
  ///
  /// In zh, this message translates to:
  /// **'选择失败应答码后，本条规则只返回该错误码，不再返回任何记录；客户端会认为该域名不可用或被拒绝。'**
  String get desktopRewriteRcodeWarning;

  /// No description provided for @desktopRewriteTtlLabel.
  ///
  /// In zh, this message translates to:
  /// **'生存时间 TTL（秒，可选）'**
  String get desktopRewriteTtlLabel;

  /// No description provided for @desktopRewriteTtlHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用全局默认 TTL'**
  String get desktopRewriteTtlHint;

  /// No description provided for @desktopRewriteNeedIp.
  ///
  /// In zh, this message translates to:
  /// **'请输入至少一个 IPv4 或 IPv6 目标解析地址'**
  String get desktopRewriteNeedIp;

  /// No description provided for @desktopRewriteNeedCname.
  ///
  /// In zh, this message translates to:
  /// **'请输入 CNAME 别名重定向目标域名'**
  String get desktopRewriteNeedCname;

  /// No description provided for @desktopRewriteNeedTxt.
  ///
  /// In zh, this message translates to:
  /// **'请输入至少一条 TXT 记录文本'**
  String get desktopRewriteNeedTxt;

  /// No description provided for @desktopRewriteNeedRecord.
  ///
  /// In zh, this message translates to:
  /// **'请至少添加一条有效记录（类型与取值均不能为空）'**
  String get desktopRewriteNeedRecord;

  /// No description provided for @desktopRewriteChipEmpty.
  ///
  /// In zh, this message translates to:
  /// **'空'**
  String get desktopRewriteChipEmpty;

  /// No description provided for @desktopZoneSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'区域解析开关与默认 TTL'**
  String get desktopZoneSettingsTitle;

  /// No description provided for @desktopZoneSettingsBody.
  ///
  /// In zh, this message translates to:
  /// **'开关本地权威区域，并设置没有写明 TTL 的记录使用多久'**
  String get desktopZoneSettingsBody;

  /// No description provided for @desktopZoneTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地权威区（zone 文件）'**
  String get desktopZoneTitle;

  /// No description provided for @desktopZoneBody.
  ///
  /// In zh, this message translates to:
  /// **'整段声明一个名字空间由本机负责，区内未收录的名字返回权威 NODATA 而非转发上游；适合内网域名与局域网服务发现'**
  String get desktopZoneBody;

  /// No description provided for @desktopZoneBadge.
  ///
  /// In zh, this message translates to:
  /// **'{zones} / {maxZones} 区 · {records} 个名字'**
  String desktopZoneBadge(int zones, int maxZones, int records);

  /// No description provided for @desktopZoneRules.
  ///
  /// In zh, this message translates to:
  /// **'区顶点及其以下所有名字都由本地负责：区里没有的名字会被权威地判为「不存在」，不会漏到公网，同名时也优先于 hosts 条目。因此顶点要写成完整后缀（如 lan.），而不是单条域名。区文件语法遵循 RFC 1035，INCLUDE 指令出于安全考虑一律拒绝。'**
  String get desktopZoneRules;

  /// No description provided for @desktopZoneDefaultTtl.
  ///
  /// In zh, this message translates to:
  /// **'默认 TTL（秒）'**
  String get desktopZoneDefaultTtl;

  /// No description provided for @desktopZoneTtlSaved.
  ///
  /// In zh, this message translates to:
  /// **'本地权威区默认 TTL 已保存'**
  String get desktopZoneTtlSaved;

  /// No description provided for @desktopZoneTtlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'TTL 需为正整数'**
  String get desktopZoneTtlInvalid;

  /// No description provided for @desktopZoneToggleOn.
  ///
  /// In zh, this message translates to:
  /// **'本地权威区已启用'**
  String get desktopZoneToggleOn;

  /// No description provided for @desktopZoneToggleOff.
  ///
  /// In zh, this message translates to:
  /// **'本地权威区已停用'**
  String get desktopZoneToggleOff;

  /// No description provided for @desktopZoneSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存本地权威区配置失败：{message}'**
  String desktopZoneSaveFailed(String message);

  /// No description provided for @desktopZoneLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到本地权威区配置'**
  String get desktopZoneLoadFailed;

  /// No description provided for @desktopZoneLimit.
  ///
  /// In zh, this message translates to:
  /// **'合计上限 {records} 条记录；超出部分会被截断并在区上标注。'**
  String desktopZoneLimit(int records);

  /// No description provided for @desktopZoneAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加区'**
  String get desktopZoneAdd;

  /// No description provided for @desktopZoneSaveAll.
  ///
  /// In zh, this message translates to:
  /// **'保存全部'**
  String get desktopZoneSaveAll;

  /// No description provided for @desktopZoneSaved.
  ///
  /// In zh, this message translates to:
  /// **'本地权威区配置已保存并生效'**
  String get desktopZoneSaved;

  /// No description provided for @desktopZoneEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置任何本地权威区'**
  String get desktopZoneEmpty;

  /// No description provided for @desktopZoneMaxZones.
  ///
  /// In zh, this message translates to:
  /// **'最多支持 {max} 个区，请先删除不再使用的区'**
  String desktopZoneMaxZones(int max);

  /// No description provided for @desktopZoneOriginHint.
  ///
  /// In zh, this message translates to:
  /// **'区顶点，如 lan.'**
  String get desktopZoneOriginHint;

  /// No description provided for @desktopZoneDeleted.
  ///
  /// In zh, this message translates to:
  /// **'区「{origin}」已删除'**
  String desktopZoneDeleted(String origin);

  /// No description provided for @desktopZoneUnnamed.
  ///
  /// In zh, this message translates to:
  /// **'（未命名）'**
  String get desktopZoneUnnamed;

  /// No description provided for @desktopZoneStateDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get desktopZoneStateDisabled;

  /// No description provided for @desktopZoneStatePending.
  ///
  /// In zh, this message translates to:
  /// **'待构建'**
  String get desktopZoneStatePending;

  /// No description provided for @desktopZoneStateFailed.
  ///
  /// In zh, this message translates to:
  /// **'解析失败'**
  String get desktopZoneStateFailed;

  /// No description provided for @desktopZoneStateTruncated.
  ///
  /// In zh, this message translates to:
  /// **'已加载 {count} 条（截断）'**
  String desktopZoneStateTruncated(int count);

  /// No description provided for @desktopZoneStateLoaded.
  ///
  /// In zh, this message translates to:
  /// **'已加载 {count} 条'**
  String desktopZoneStateLoaded(int count);

  /// No description provided for @desktopZoneFailedReason.
  ///
  /// In zh, this message translates to:
  /// **'该区未被加载'**
  String get desktopZoneFailedReason;

  /// No description provided for @desktopZoneExpand.
  ///
  /// In zh, this message translates to:
  /// **'展开编辑'**
  String get desktopZoneExpand;

  /// No description provided for @desktopZoneCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get desktopZoneCollapse;

  /// No description provided for @desktopZoneDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除该区'**
  String get desktopZoneDelete;

  /// No description provided for @desktopZoneContent.
  ///
  /// In zh, this message translates to:
  /// **'区文件内容'**
  String get desktopZoneContent;

  /// No description provided for @desktopZonePreview.
  ///
  /// In zh, this message translates to:
  /// **'预演解析'**
  String get desktopZonePreview;

  /// No description provided for @desktopZonePreviewNote.
  ///
  /// In zh, this message translates to:
  /// **'用与后端一致的解析路径试跑一次；改动需点「保存全部」才会生效。'**
  String get desktopZonePreviewNote;

  /// No description provided for @desktopZonePreviewEmpty.
  ///
  /// In zh, this message translates to:
  /// **'（空区，无记录）'**
  String get desktopZonePreviewEmpty;

  /// No description provided for @desktopZonePreviewMore.
  ///
  /// In zh, this message translates to:
  /// **'… 其余 {count} 条已省略'**
  String desktopZonePreviewMore(int count);

  /// No description provided for @desktopHubDns64.
  ///
  /// In zh, this message translates to:
  /// **'IPv6 / DNS64'**
  String get desktopHubDns64;

  /// No description provided for @desktopHubDns64Body.
  ///
  /// In zh, this message translates to:
  /// **'为纯 IPv6 网络把仅有 IPv4 记录的目标合成为 AAAA'**
  String get desktopHubDns64Body;

  /// No description provided for @desktopDns64Title.
  ///
  /// In zh, this message translates to:
  /// **'IPv6 / DNS64'**
  String get desktopDns64Title;

  /// No description provided for @desktopDns64Refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新 DNS64 配置'**
  String get desktopDns64Refresh;

  /// No description provided for @desktopDns64CardTitle.
  ///
  /// In zh, this message translates to:
  /// **'DNS64 IPv6-only 网络过渡合成'**
  String get desktopDns64CardTitle;

  /// No description provided for @desktopDns64CardBody.
  ///
  /// In zh, this message translates to:
  /// **'遵循 RFC 6052 / RFC 6147，为纯 IPv6 终端自动把仅有 A 记录的目标合成为 AAAA'**
  String get desktopDns64CardBody;

  /// No description provided for @desktopDns64EngineOn.
  ///
  /// In zh, this message translates to:
  /// **'DNS64 合成中'**
  String get desktopDns64EngineOn;

  /// No description provided for @desktopDns64EngineOff.
  ///
  /// In zh, this message translates to:
  /// **'功能已停用'**
  String get desktopDns64EngineOff;

  /// No description provided for @desktopDns64Description.
  ///
  /// In zh, this message translates to:
  /// **'当客户端位于纯 IPv6 网络并通过 NAT64 网关访问互联网时，若目标域名只有 IPv4（A）记录而没有原生 IPv6（AAAA）记录，DNS64 引擎会用指定前缀把 IPv4 地址合成映射为 AAAA 返回，让终端仍能端到端访问。'**
  String get desktopDns64Description;

  /// No description provided for @desktopDns64PrefixesCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'合成前缀'**
  String get desktopDns64PrefixesCardTitle;

  /// No description provided for @desktopDns64PrefixesLabel.
  ///
  /// In zh, this message translates to:
  /// **'用于合成的 IPv6 前缀（每行一个）'**
  String get desktopDns64PrefixesLabel;

  /// No description provided for @desktopDns64PrefixesHelper.
  ///
  /// In zh, this message translates to:
  /// **'每行一个 IPv6 网段。支持 /32、/40、/48、/56、/64、/96；留空时服务使用知名公共前缀 64:ff9b::/96。'**
  String get desktopDns64PrefixesHelper;

  /// No description provided for @desktopDns64FillWellKnown.
  ///
  /// In zh, this message translates to:
  /// **'填入标准前缀'**
  String get desktopDns64FillWellKnown;

  /// No description provided for @desktopDns64NoteTitle.
  ///
  /// In zh, this message translates to:
  /// **'智能保护机制'**
  String get desktopDns64NoteTitle;

  /// No description provided for @desktopDns64NoteBody.
  ///
  /// In zh, this message translates to:
  /// **'服务内置 RFC 6147 排除网段（回环、链路本地、IPv4-mapped 与自身前缀），避免回环与重复嵌套合成；目标已有原生 AAAA 时直接返回原生记录，不做额外合成。'**
  String get desktopDns64NoteBody;

  /// No description provided for @desktopDns64Save.
  ///
  /// In zh, this message translates to:
  /// **'保存 DNS64 配置'**
  String get desktopDns64Save;

  /// No description provided for @desktopDns64Saving.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get desktopDns64Saving;

  /// No description provided for @desktopDns64Saved.
  ///
  /// In zh, this message translates to:
  /// **'DNS64 过渡合成配置已更新'**
  String get desktopDns64Saved;

  /// No description provided for @desktopDns64ToggleOn.
  ///
  /// In zh, this message translates to:
  /// **'DNS64 过渡合成已开启'**
  String get desktopDns64ToggleOn;

  /// No description provided for @desktopDns64ToggleOff.
  ///
  /// In zh, this message translates to:
  /// **'DNS64 过渡合成已关闭'**
  String get desktopDns64ToggleOff;

  /// No description provided for @desktopDns64SaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新 DNS64 配置失败：{message}'**
  String desktopDns64SaveFailed(String message);

  /// No description provided for @desktopDns64LoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到 DNS64 配置'**
  String get desktopDns64LoadFailed;

  /// No description provided for @desktopHubFilterLists.
  ///
  /// In zh, this message translates to:
  /// **'规则订阅'**
  String get desktopHubFilterLists;

  /// No description provided for @desktopHubFilterListsBody.
  ///
  /// In zh, this message translates to:
  /// **'在线规则库与本地规则文件，按订阅批量生效'**
  String get desktopHubFilterListsBody;

  /// No description provided for @desktopFilterListsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则订阅'**
  String get desktopFilterListsPageTitle;

  /// No description provided for @desktopFilterListsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新订阅状态'**
  String get desktopFilterListsRefresh;

  /// No description provided for @desktopFilterSummaryTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则拦截总览'**
  String get desktopFilterSummaryTitle;

  /// No description provided for @desktopFilterEngineOn.
  ///
  /// In zh, this message translates to:
  /// **'防护生效中'**
  String get desktopFilterEngineOn;

  /// No description provided for @desktopFilterEngineOff.
  ///
  /// In zh, this message translates to:
  /// **'防护已关闭'**
  String get desktopFilterEngineOff;

  /// No description provided for @desktopFilterPausedChip.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get desktopFilterPausedChip;

  /// No description provided for @desktopFilterBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已拦截请求'**
  String get desktopFilterBlocked;

  /// No description provided for @desktopFilterTimes.
  ///
  /// In zh, this message translates to:
  /// **'次'**
  String get desktopFilterTimes;

  /// No description provided for @desktopFilterRulesUnit.
  ///
  /// In zh, this message translates to:
  /// **'条'**
  String get desktopFilterRulesUnit;

  /// No description provided for @desktopFilterActiveLists.
  ///
  /// In zh, this message translates to:
  /// **'已启用规则库'**
  String get desktopFilterActiveLists;

  /// No description provided for @desktopFilterListsUnit.
  ///
  /// In zh, this message translates to:
  /// **'个'**
  String get desktopFilterListsUnit;

  /// No description provided for @desktopFilterPausedRemaining.
  ///
  /// In zh, this message translates to:
  /// **'拦截已暂停，剩余 {remaining} 后自动恢复'**
  String desktopFilterPausedRemaining(String remaining);

  /// No description provided for @desktopFilterPauseDays.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天'**
  String desktopFilterPauseDays(int days);

  /// No description provided for @desktopFilterPauseHours.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时 {minutes} 分'**
  String desktopFilterPauseHours(int hours, int minutes);

  /// No description provided for @desktopFilterPauseMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分 {seconds} 秒'**
  String desktopFilterPauseMinutes(int minutes, int seconds);

  /// No description provided for @desktopFilterPauseSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String desktopFilterPauseSeconds(int seconds);

  /// No description provided for @desktopFilterListsTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则订阅库'**
  String get desktopFilterListsTitle;

  /// No description provided for @desktopFilterListsBody.
  ///
  /// In zh, this message translates to:
  /// **'支持在线订阅链接与本地规则文本文件；每个规则库独立开关，全部更新会逐个重新拉取。'**
  String get desktopFilterListsBody;

  /// No description provided for @desktopFilterListsCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个规则库'**
  String desktopFilterListsCount(int count);

  /// No description provided for @desktopFilterListUpdateAll.
  ///
  /// In zh, this message translates to:
  /// **'全部更新'**
  String get desktopFilterListUpdateAll;

  /// No description provided for @desktopFilterListAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加规则库'**
  String get desktopFilterListAdd;

  /// No description provided for @desktopFilterListsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无规则订阅库'**
  String get desktopFilterListsEmpty;

  /// No description provided for @desktopFilterListsEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'添加 AdGuard 语法规则链接或本地 Hosts 规则文件后，规则会随订阅自动下载并生效。'**
  String get desktopFilterListsEmptyBody;

  /// No description provided for @desktopFilterListDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'订阅列表 {index}'**
  String desktopFilterListDefaultName(int index);

  /// No description provided for @desktopFilterListAdded.
  ///
  /// In zh, this message translates to:
  /// **'规则库已添加并开始下载'**
  String get desktopFilterListAdded;

  /// No description provided for @desktopFilterListAllUpdated.
  ///
  /// In zh, this message translates to:
  /// **'全部规则库已更新完成'**
  String get desktopFilterListAllUpdated;

  /// No description provided for @desktopFilterListUpdated.
  ///
  /// In zh, this message translates to:
  /// **'规则库已更新'**
  String get desktopFilterListUpdated;

  /// No description provided for @desktopFilterActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopFilterActionFailed(String message);

  /// No description provided for @desktopFilterListToggleOn.
  ///
  /// In zh, this message translates to:
  /// **'已启用规则库：{name}'**
  String desktopFilterListToggleOn(String name);

  /// No description provided for @desktopFilterListToggleOff.
  ///
  /// In zh, this message translates to:
  /// **'已停用规则库：{name}'**
  String desktopFilterListToggleOff(String name);

  /// No description provided for @desktopFilterListDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除规则库'**
  String get desktopFilterListDeleteTitle;

  /// No description provided for @desktopFilterListDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除规则库「{name}」吗？删除后其包含的拦截规则将不再生效。'**
  String desktopFilterListDeleteBody(String name);

  /// No description provided for @desktopFilterListDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除'**
  String get desktopFilterListDeleteConfirm;

  /// No description provided for @desktopFilterListDeleted.
  ///
  /// In zh, this message translates to:
  /// **'规则库已删除'**
  String get desktopFilterListDeleted;

  /// No description provided for @desktopFilterListRules.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条规则'**
  String desktopFilterListRules(int count);

  /// No description provided for @desktopFilterListEnabled.
  ///
  /// In zh, this message translates to:
  /// **'规则拦截生效中'**
  String get desktopFilterListEnabled;

  /// No description provided for @desktopFilterListDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已暂停拦截'**
  String get desktopFilterListDisabled;

  /// No description provided for @desktopFilterListNeverUpdated.
  ///
  /// In zh, this message translates to:
  /// **'最后更新：未更新'**
  String get desktopFilterListNeverUpdated;

  /// No description provided for @desktopFilterListUpdatedAt.
  ///
  /// In zh, this message translates to:
  /// **'最后更新：{time}'**
  String desktopFilterListUpdatedAt(String time);

  /// No description provided for @desktopFilterListRefreshOne.
  ///
  /// In zh, this message translates to:
  /// **'立即更新此规则库'**
  String get desktopFilterListRefreshOne;

  /// No description provided for @desktopFilterListDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除此规则库'**
  String get desktopFilterListDelete;

  /// No description provided for @desktopFilterListHealthOk.
  ///
  /// In zh, this message translates to:
  /// **'已同步'**
  String get desktopFilterListHealthOk;

  /// No description provided for @desktopFilterListHealthUnchanged.
  ///
  /// In zh, this message translates to:
  /// **'未变更'**
  String get desktopFilterListHealthUnchanged;

  /// No description provided for @desktopFilterListHealthCached.
  ///
  /// In zh, this message translates to:
  /// **'沿用缓存'**
  String get desktopFilterListHealthCached;

  /// No description provided for @desktopFilterListHealthFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败'**
  String get desktopFilterListHealthFailed;

  /// No description provided for @desktopFilterListHealthOkBody.
  ///
  /// In zh, this message translates to:
  /// **'本次拉取获取到新内容并已生效'**
  String get desktopFilterListHealthOkBody;

  /// No description provided for @desktopFilterListHealthUnchangedBody.
  ///
  /// In zh, this message translates to:
  /// **'服务端返回 304，本地副本仍然有效'**
  String get desktopFilterListHealthUnchangedBody;

  /// No description provided for @desktopFilterListHealthCachedBody.
  ///
  /// In zh, this message translates to:
  /// **'拉取失败，继续使用上次缓存内容'**
  String get desktopFilterListHealthCachedBody;

  /// No description provided for @desktopFilterListHealthFailedBody.
  ///
  /// In zh, this message translates to:
  /// **'拉取失败且无可用缓存'**
  String get desktopFilterListHealthFailedBody;

  /// No description provided for @desktopFilterListAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加规则订阅库'**
  String get desktopFilterListAddTitle;

  /// No description provided for @desktopFilterListAddBody.
  ///
  /// In zh, this message translates to:
  /// **'输入规则库的名称，以及在线订阅网址（URL）或本地文件路径。'**
  String get desktopFilterListAddBody;

  /// No description provided for @desktopFilterListNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'规则库名称'**
  String get desktopFilterListNameLabel;

  /// No description provided for @desktopFilterListNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：广告拦截通用规则'**
  String get desktopFilterListNameHint;

  /// No description provided for @desktopFilterListUrlLabel.
  ///
  /// In zh, this message translates to:
  /// **'订阅链接 / 文件路径'**
  String get desktopFilterListUrlLabel;

  /// No description provided for @desktopFilterListUrlHint.
  ///
  /// In zh, this message translates to:
  /// **'https://… 或本地文件路径'**
  String get desktopFilterListUrlHint;

  /// No description provided for @desktopFilterListAddConfirm.
  ///
  /// In zh, this message translates to:
  /// **'添加并下载'**
  String get desktopFilterListAddConfirm;

  /// No description provided for @desktopFilterListNeedUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的规则源 URL 或本地文件路径'**
  String get desktopFilterListNeedUrl;

  /// No description provided for @desktopFilterListsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到规则订阅库'**
  String get desktopFilterListsLoadFailed;

  /// No description provided for @desktopHubFilterRules.
  ///
  /// In zh, this message translates to:
  /// **'自定义规则'**
  String get desktopHubFilterRules;

  /// No description provided for @desktopHubFilterRulesBody.
  ///
  /// In zh, this message translates to:
  /// **'手写 AdGuard 语法规则，保存后立即热重载生效'**
  String get desktopHubFilterRulesBody;

  /// No description provided for @desktopFilterRulesPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义规则'**
  String get desktopFilterRulesPageTitle;

  /// No description provided for @desktopFilterRulesRefresh.
  ///
  /// In zh, this message translates to:
  /// **'重新读取自定义规则'**
  String get desktopFilterRulesRefresh;

  /// No description provided for @desktopFilterRulesEditorTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义规则文本编辑器'**
  String get desktopFilterRulesEditorTitle;

  /// No description provided for @desktopFilterRulesEditorBody.
  ///
  /// In zh, this message translates to:
  /// **'编辑用户专属的过滤拦截或放行清单，每行一条'**
  String get desktopFilterRulesEditorBody;

  /// No description provided for @desktopFilterRulesSave.
  ///
  /// In zh, this message translates to:
  /// **'保存规则'**
  String get desktopFilterRulesSave;

  /// No description provided for @desktopFilterRulesSaving.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get desktopFilterRulesSaving;

  /// No description provided for @desktopFilterRulesSaved.
  ///
  /// In zh, this message translates to:
  /// **'自定义规则已保存生效'**
  String get desktopFilterRulesSaved;

  /// No description provided for @desktopFilterRulesSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存自定义规则失败：{message}'**
  String desktopFilterRulesSaveFailed(String message);

  /// No description provided for @desktopFilterRulesLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到自定义规则'**
  String get desktopFilterRulesLoadFailed;

  /// No description provided for @desktopFilterRulesPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'在此输入自定义拦截或信任规则，每行一条…'**
  String get desktopFilterRulesPlaceholder;

  /// No description provided for @desktopFilterRulesLineCount.
  ///
  /// In zh, this message translates to:
  /// **'行数统计：{count} 条规则'**
  String desktopFilterRulesLineCount(int count);

  /// No description provided for @desktopFilterRulesHint.
  ///
  /// In zh, this message translates to:
  /// **'每行一条规则，以 ! 开头的行为注释；修改后点击保存立即热重载生效。'**
  String get desktopFilterRulesHint;

  /// No description provided for @desktopFilterGuideTitle.
  ///
  /// In zh, this message translates to:
  /// **'AdGuard 语法速查指南'**
  String get desktopFilterGuideTitle;

  /// No description provided for @desktopFilterGuideBody.
  ///
  /// In zh, this message translates to:
  /// **'主流广告过滤与信任规则编写格式'**
  String get desktopFilterGuideBody;

  /// No description provided for @desktopFilterGuideCommon.
  ///
  /// In zh, this message translates to:
  /// **'常用格式'**
  String get desktopFilterGuideCommon;

  /// No description provided for @desktopFilterGuideExempt.
  ///
  /// In zh, this message translates to:
  /// **'豁免放行'**
  String get desktopFilterGuideExempt;

  /// No description provided for @desktopFilterGuideCompat.
  ///
  /// In zh, this message translates to:
  /// **'传统兼容'**
  String get desktopFilterGuideCompat;

  /// No description provided for @desktopFilterGuidePriority.
  ///
  /// In zh, this message translates to:
  /// **'强制优先'**
  String get desktopFilterGuidePriority;

  /// No description provided for @desktopFilterGuideRewrite.
  ///
  /// In zh, this message translates to:
  /// **'应答重写'**
  String get desktopFilterGuideRewrite;

  /// No description provided for @desktopFilterGuideDomainTitle.
  ///
  /// In zh, this message translates to:
  /// **'域名与子域名拦截'**
  String get desktopFilterGuideDomainTitle;

  /// No description provided for @desktopFilterGuideDomainBody.
  ///
  /// In zh, this message translates to:
  /// **'匹配并拦截 example.com 及其所有子域名（如 ad.example.com）。'**
  String get desktopFilterGuideDomainBody;

  /// No description provided for @desktopFilterGuideAllowTitle.
  ///
  /// In zh, this message translates to:
  /// **'白名单信任放行'**
  String get desktopFilterGuideAllowTitle;

  /// No description provided for @desktopFilterGuideAllowBody.
  ///
  /// In zh, this message translates to:
  /// **'即便其他规则命中，也始终允许解析 safe.com。'**
  String get desktopFilterGuideAllowBody;

  /// No description provided for @desktopFilterGuideHostsTitle.
  ///
  /// In zh, this message translates to:
  /// **'Hosts 文件格式'**
  String get desktopFilterGuideHostsTitle;

  /// No description provided for @desktopFilterGuideHostsBody.
  ///
  /// In zh, this message translates to:
  /// **'兼容标准 Hosts 文件屏蔽特定域名的语法。'**
  String get desktopFilterGuideHostsBody;

  /// No description provided for @desktopFilterGuideImportantTitle.
  ///
  /// In zh, this message translates to:
  /// **'最高优先级强力拦截'**
  String get desktopFilterGuideImportantTitle;

  /// No description provided for @desktopFilterGuideImportantBody.
  ///
  /// In zh, this message translates to:
  /// **'忽略所有白名单规则，强制拦截该域名。'**
  String get desktopFilterGuideImportantBody;

  /// No description provided for @desktopFilterGuideRewriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'应答重写'**
  String get desktopFilterGuideRewriteTitle;

  /// No description provided for @desktopFilterGuideRewriteBody.
  ///
  /// In zh, this message translates to:
  /// **'无需上游应答，直接按规则给出结果：支持 IPv4/IPv6 地址、域名（CNAME）、NOERROR;A;1.2.3.4 这类显式写法，以及 REFUSED / NXDOMAIN 等应答码；显式写法还支持 MX、SRV、NS、PTR、TXT、HTTPS、SVCB。优先级高于一切拦截与放行规则，用 @@||nas.lan^\$dnsrewrite 可取消该域名的全部重写。'**
  String get desktopFilterGuideRewriteBody;

  /// No description provided for @desktopFilterGuideFooter.
  ///
  /// In zh, this message translates to:
  /// **'提示：每行一条规则，以 ! 开头的行为注释。'**
  String get desktopFilterGuideFooter;

  /// No description provided for @desktopHubFilterConfig.
  ///
  /// In zh, this message translates to:
  /// **'拦截方式'**
  String get desktopHubFilterConfig;

  /// No description provided for @desktopHubFilterConfigBody.
  ///
  /// In zh, this message translates to:
  /// **'应答模式、阻断地址、更新周期、临时暂停与高级拦截'**
  String get desktopHubFilterConfigBody;

  /// No description provided for @desktopFilterConfigPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'拦截方式'**
  String get desktopFilterConfigPageTitle;

  /// No description provided for @desktopFilterConfigRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新拦截配置'**
  String get desktopFilterConfigRefresh;

  /// No description provided for @desktopFilterConfigLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到拦截配置'**
  String get desktopFilterConfigLoadFailed;

  /// No description provided for @desktopFilterConfigSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存拦截配置失败：{message}'**
  String desktopFilterConfigSaveFailed(String message);

  /// No description provided for @desktopFilterEngineOnMessage.
  ///
  /// In zh, this message translates to:
  /// **'规则拦截防护已开启'**
  String get desktopFilterEngineOnMessage;

  /// No description provided for @desktopFilterEngineOffMessage.
  ///
  /// In zh, this message translates to:
  /// **'规则拦截防护已关闭'**
  String get desktopFilterEngineOffMessage;

  /// No description provided for @desktopFilterModeTitle.
  ///
  /// In zh, this message translates to:
  /// **'拦截响应处理方式'**
  String get desktopFilterModeTitle;

  /// No description provided for @desktopFilterModeBody.
  ///
  /// In zh, this message translates to:
  /// **'命中拦截规则时向客户端返回的应答'**
  String get desktopFilterModeBody;

  /// No description provided for @desktopFilterModeSave.
  ///
  /// In zh, this message translates to:
  /// **'保存策略与参数'**
  String get desktopFilterModeSave;

  /// No description provided for @desktopFilterModeSaving.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get desktopFilterModeSaving;

  /// No description provided for @desktopFilterModeSaved.
  ///
  /// In zh, this message translates to:
  /// **'拦截策略配置已保存'**
  String get desktopFilterModeSaved;

  /// No description provided for @desktopFilterModeParamsTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则自动更新与阻断地址'**
  String get desktopFilterModeParamsTitle;

  /// No description provided for @desktopFilterModeParamsBody.
  ///
  /// In zh, this message translates to:
  /// **'被拦截域名得到的应答地址，以及规则列表的自动更新周期'**
  String get desktopFilterModeParamsBody;

  /// No description provided for @desktopFilterModeBlockingIPv4.
  ///
  /// In zh, this message translates to:
  /// **'阻断 IPv4 响应地址'**
  String get desktopFilterModeBlockingIPv4;

  /// No description provided for @desktopFilterModeBlockingIPv6.
  ///
  /// In zh, this message translates to:
  /// **'阻断 IPv6 响应地址'**
  String get desktopFilterModeBlockingIPv6;

  /// No description provided for @desktopFilterModeInterval.
  ///
  /// In zh, this message translates to:
  /// **'规则库同步周期（小时）'**
  String get desktopFilterModeInterval;

  /// No description provided for @desktopFilterModeIntervalHelper.
  ///
  /// In zh, this message translates to:
  /// **'默认 24 小时'**
  String get desktopFilterModeIntervalHelper;

  /// No description provided for @desktopFilterModeInvalid.
  ///
  /// In zh, this message translates to:
  /// **'同步周期需为正整数，阻断地址不能为空'**
  String get desktopFilterModeInvalid;

  /// No description provided for @desktopFilterModeNullIp.
  ///
  /// In zh, this message translates to:
  /// **'立即返回空地址（0.0.0.0 / ::）'**
  String get desktopFilterModeNullIp;

  /// No description provided for @desktopFilterModeNullIpBody.
  ///
  /// In zh, this message translates to:
  /// **'以极速终止广告和弹窗资源加载，不会引起浏览器反复重发请求。'**
  String get desktopFilterModeNullIpBody;

  /// No description provided for @desktopFilterModeNxdomain.
  ///
  /// In zh, this message translates to:
  /// **'提示域名不存在（NXDOMAIN）'**
  String get desktopFilterModeNxdomain;

  /// No description provided for @desktopFilterModeNxdomainBody.
  ///
  /// In zh, this message translates to:
  /// **'告知客户端该网址不存在，部分标准网络软件将放弃进一步连接探测。'**
  String get desktopFilterModeNxdomainBody;

  /// No description provided for @desktopFilterModeRefused.
  ///
  /// In zh, this message translates to:
  /// **'明确拒绝请求（REFUSED）'**
  String get desktopFilterModeRefused;

  /// No description provided for @desktopFilterModeRefusedBody.
  ///
  /// In zh, this message translates to:
  /// **'向客户端返回拒绝码，表示请求被 DNS 防火墙安全策略主动阻止。'**
  String get desktopFilterModeRefusedBody;

  /// No description provided for @desktopFilterAdvancedTitle.
  ///
  /// In zh, this message translates to:
  /// **'高级拦截能力'**
  String get desktopFilterAdvancedTitle;

  /// No description provided for @desktopFilterAdvancedBody.
  ///
  /// In zh, this message translates to:
  /// **'针对绕过手法的增强拦截策略，默认关闭，按需开启'**
  String get desktopFilterAdvancedBody;

  /// No description provided for @desktopFilterAdvancedResponseTitle.
  ///
  /// In zh, this message translates to:
  /// **'响应侧别名链深度复检'**
  String get desktopFilterAdvancedResponseTitle;

  /// No description provided for @desktopFilterAdvancedResponseBody.
  ///
  /// In zh, this message translates to:
  /// **'对上游应答中的 CNAME 目标与 A/AAAA 所属名二次匹配黑名单，拦截「查询域名合法但别名指向黑名单域」的深链绕过；缓存命中的应答同样复检。'**
  String get desktopFilterAdvancedResponseBody;

  /// No description provided for @desktopFilterAdvancedResponseOn.
  ///
  /// In zh, this message translates to:
  /// **'响应侧别名链复检已开启'**
  String get desktopFilterAdvancedResponseOn;

  /// No description provided for @desktopFilterAdvancedResponseOff.
  ///
  /// In zh, this message translates to:
  /// **'响应侧别名链复检已关闭'**
  String get desktopFilterAdvancedResponseOff;

  /// No description provided for @desktopFilterAdvancedAllowlistTitle.
  ///
  /// In zh, this message translates to:
  /// **'仅白名单模式'**
  String get desktopFilterAdvancedAllowlistTitle;

  /// No description provided for @desktopFilterAdvancedAllowlistBody.
  ///
  /// In zh, this message translates to:
  /// **'开启后仅命中放行规则（@@ 例外）的查询才被放行，其余一律阻断；本地 Hosts / 重写 / 内网域名等本地权威应答不受影响。'**
  String get desktopFilterAdvancedAllowlistBody;

  /// No description provided for @desktopFilterAdvancedAllowlistWarning.
  ///
  /// In zh, this message translates to:
  /// **'请先确保已配置充分的放行白名单，否则可能造成大面积域名解析失败。'**
  String get desktopFilterAdvancedAllowlistWarning;

  /// No description provided for @desktopFilterAdvancedAllowlistOn.
  ///
  /// In zh, this message translates to:
  /// **'仅白名单模式已开启'**
  String get desktopFilterAdvancedAllowlistOn;

  /// No description provided for @desktopFilterAdvancedAllowlistOff.
  ///
  /// In zh, this message translates to:
  /// **'仅白名单模式已关闭'**
  String get desktopFilterAdvancedAllowlistOff;

  /// No description provided for @desktopFilterAdvancedBogusTitle.
  ///
  /// In zh, this message translates to:
  /// **'伪应答纠正'**
  String get desktopFilterAdvancedBogusTitle;

  /// No description provided for @desktopFilterAdvancedBogusBody.
  ///
  /// In zh, this message translates to:
  /// **'部分网络在域名不存在时返回固定的导航或广告页地址；开启后应答地址落在下方清单内即判定为上游劫持，就地改写为 NXDOMAIN。'**
  String get desktopFilterAdvancedBogusBody;

  /// No description provided for @desktopFilterAdvancedBogusOn.
  ///
  /// In zh, this message translates to:
  /// **'伪应答纠正已开启'**
  String get desktopFilterAdvancedBogusOn;

  /// No description provided for @desktopFilterAdvancedBogusOff.
  ///
  /// In zh, this message translates to:
  /// **'伪应答纠正已关闭'**
  String get desktopFilterAdvancedBogusOff;

  /// No description provided for @desktopFilterAdvancedBogusListLabel.
  ///
  /// In zh, this message translates to:
  /// **'劫持地址清单（一行一条，支持 IP 与 CIDR 网段）'**
  String get desktopFilterAdvancedBogusListLabel;

  /// No description provided for @desktopFilterAdvancedBogusSuspicious.
  ///
  /// In zh, this message translates to:
  /// **'以下条目格式可疑，保存时若无法解析将被服务忽略：{entries}'**
  String desktopFilterAdvancedBogusSuspicious(String entries);

  /// No description provided for @desktopFilterAdvancedBogusPresets.
  ///
  /// In zh, this message translates to:
  /// **'快捷填入：'**
  String get desktopFilterAdvancedBogusPresets;

  /// No description provided for @desktopFilterAdvancedBogusReset.
  ///
  /// In zh, this message translates to:
  /// **'撤销修改'**
  String get desktopFilterAdvancedBogusReset;

  /// No description provided for @desktopFilterAdvancedBogusSave.
  ///
  /// In zh, this message translates to:
  /// **'保存地址清单'**
  String get desktopFilterAdvancedBogusSave;

  /// No description provided for @desktopFilterAdvancedBogusSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {count} 条劫持地址'**
  String desktopFilterAdvancedBogusSaved(int count);

  /// No description provided for @desktopFilterAdvancedBogusCleared.
  ///
  /// In zh, this message translates to:
  /// **'劫持地址清单已清空'**
  String get desktopFilterAdvancedBogusCleared;

  /// No description provided for @desktopFilterPauseBody.
  ///
  /// In zh, this message translates to:
  /// **'在指定时长内整体放行全部查询，到期自动恢复（重启服务亦恢复）。'**
  String get desktopFilterPauseBody;

  /// No description provided for @desktopFilterPauseDuration.
  ///
  /// In zh, this message translates to:
  /// **'暂停时长'**
  String get desktopFilterPauseDuration;

  /// No description provided for @desktopFilterPauseAction.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get desktopFilterPauseAction;

  /// No description provided for @desktopFilterPauseResume.
  ///
  /// In zh, this message translates to:
  /// **'立即恢复拦截'**
  String get desktopFilterPauseResume;

  /// No description provided for @desktopFilterPauseStarted.
  ///
  /// In zh, this message translates to:
  /// **'拦截已暂停'**
  String get desktopFilterPauseStarted;

  /// No description provided for @desktopFilterPauseResumed.
  ///
  /// In zh, this message translates to:
  /// **'拦截已恢复'**
  String get desktopFilterPauseResumed;

  /// No description provided for @desktopFilterPauseActiveTitle.
  ///
  /// In zh, this message translates to:
  /// **'拦截已暂停'**
  String get desktopFilterPauseActiveTitle;

  /// No description provided for @desktopFilterPauseActiveBody.
  ///
  /// In zh, this message translates to:
  /// **'剩余 {remaining} 后自动恢复拦截'**
  String desktopFilterPauseActiveBody(String remaining);

  /// No description provided for @desktopFilterPauseMinutesOnly.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String desktopFilterPauseMinutesOnly(int minutes);

  /// No description provided for @desktopFilterPauseOneHour.
  ///
  /// In zh, this message translates to:
  /// **'1 小时'**
  String get desktopFilterPauseOneHour;

  /// No description provided for @desktopFilterPauseEightHours.
  ///
  /// In zh, this message translates to:
  /// **'8 小时'**
  String get desktopFilterPauseEightHours;

  /// No description provided for @desktopHubFilterSchedule.
  ///
  /// In zh, this message translates to:
  /// **'时间计划'**
  String get desktopHubFilterSchedule;

  /// No description provided for @desktopHubFilterScheduleBody.
  ///
  /// In zh, this message translates to:
  /// **'只在指定时段执行拦截，其余时间自动放行'**
  String get desktopHubFilterScheduleBody;

  /// No description provided for @desktopSchedulePageTitle.
  ///
  /// In zh, this message translates to:
  /// **'时间计划'**
  String get desktopSchedulePageTitle;

  /// No description provided for @desktopScheduleRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新时间计划'**
  String get desktopScheduleRefresh;

  /// No description provided for @desktopScheduleLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到时间计划'**
  String get desktopScheduleLoadFailed;

  /// No description provided for @desktopScheduleTitle.
  ///
  /// In zh, this message translates to:
  /// **'分时拦截 · 时间计划'**
  String get desktopScheduleTitle;

  /// No description provided for @desktopScheduleBody.
  ///
  /// In zh, this message translates to:
  /// **'仅在指定时段内执行广告拦截，其余时间自动放行'**
  String get desktopScheduleBody;

  /// No description provided for @desktopScheduleBadgeOff.
  ///
  /// In zh, this message translates to:
  /// **'未启用 · 拦截常开'**
  String get desktopScheduleBadgeOff;

  /// No description provided for @desktopScheduleBadgeActive.
  ///
  /// In zh, this message translates to:
  /// **'拦截生效中'**
  String get desktopScheduleBadgeActive;

  /// No description provided for @desktopScheduleBadgePaused.
  ///
  /// In zh, this message translates to:
  /// **'计划暂停 · 放行全部'**
  String get desktopScheduleBadgePaused;

  /// No description provided for @desktopScheduleEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用分时拦截'**
  String get desktopScheduleEnable;

  /// No description provided for @desktopScheduleEnableBody.
  ///
  /// In zh, this message translates to:
  /// **'关闭时拦截始终生效；开启后仅在下列时间窗口内执行拦截。'**
  String get desktopScheduleEnableBody;

  /// No description provided for @desktopScheduleNoEnabled.
  ///
  /// In zh, this message translates to:
  /// **'当前无已启用计划，拦截将保持常开。请至少启用一条计划以限制拦截时段。'**
  String get desktopScheduleNoEnabled;

  /// No description provided for @desktopScheduleSave.
  ///
  /// In zh, this message translates to:
  /// **'保存计划'**
  String get desktopScheduleSave;

  /// No description provided for @desktopScheduleSaving.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get desktopScheduleSaving;

  /// No description provided for @desktopScheduleSaved.
  ///
  /// In zh, this message translates to:
  /// **'时间计划已保存并生效'**
  String get desktopScheduleSaved;

  /// No description provided for @desktopScheduleSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存时间计划失败：{message}'**
  String desktopScheduleSaveFailed(String message);

  /// No description provided for @desktopScheduleAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增时间计划'**
  String get desktopScheduleAdd;

  /// No description provided for @desktopScheduleName.
  ///
  /// In zh, this message translates to:
  /// **'计划名称'**
  String get desktopScheduleName;

  /// No description provided for @desktopScheduleEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用该计划'**
  String get desktopScheduleEnabled;

  /// No description provided for @desktopScheduleStart.
  ///
  /// In zh, this message translates to:
  /// **'生效开始时刻'**
  String get desktopScheduleStart;

  /// No description provided for @desktopScheduleEnd.
  ///
  /// In zh, this message translates to:
  /// **'生效结束时刻'**
  String get desktopScheduleEnd;

  /// No description provided for @desktopScheduleEndHelper.
  ///
  /// In zh, this message translates to:
  /// **'早于开始即跨夜'**
  String get desktopScheduleEndHelper;

  /// No description provided for @desktopScheduleWeekdays.
  ///
  /// In zh, this message translates to:
  /// **'生效星期'**
  String get desktopScheduleWeekdays;

  /// No description provided for @desktopScheduleEveryDay.
  ///
  /// In zh, this message translates to:
  /// **'每天'**
  String get desktopScheduleEveryDay;

  /// No description provided for @desktopScheduleDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除该计划'**
  String get desktopScheduleDelete;

  /// No description provided for @desktopScheduleDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除时间计划'**
  String get desktopScheduleDeleteTitle;

  /// No description provided for @desktopScheduleDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除该时间计划吗？保存后不再生效。'**
  String get desktopScheduleDeleteBody;

  /// No description provided for @desktopScheduleDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get desktopScheduleDeleteConfirm;

  /// No description provided for @desktopWeekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get desktopWeekdayMon;

  /// No description provided for @desktopWeekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'二'**
  String get desktopWeekdayTue;

  /// No description provided for @desktopWeekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get desktopWeekdayWed;

  /// No description provided for @desktopWeekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'四'**
  String get desktopWeekdayThu;

  /// No description provided for @desktopWeekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get desktopWeekdayFri;

  /// No description provided for @desktopWeekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'六'**
  String get desktopWeekdaySat;

  /// No description provided for @desktopWeekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get desktopWeekdaySun;

  /// No description provided for @desktopHubFilterServices.
  ///
  /// In zh, this message translates to:
  /// **'应用拦截'**
  String get desktopHubFilterServices;

  /// No description provided for @desktopHubFilterServicesBody.
  ///
  /// In zh, this message translates to:
  /// **'内置应用与网站规则，一键整组拦截，可按周计划放行'**
  String get desktopHubFilterServicesBody;

  /// No description provided for @desktopServicesPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用拦截'**
  String get desktopServicesPageTitle;

  /// No description provided for @desktopServicesRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新应用拦截'**
  String get desktopServicesRefresh;

  /// No description provided for @desktopServicesLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到内置服务目录'**
  String get desktopServicesLoadFailed;

  /// No description provided for @desktopServicesGroupsTitle.
  ///
  /// In zh, this message translates to:
  /// **'整组拦截'**
  String get desktopServicesGroupsTitle;

  /// No description provided for @desktopServicesGroupsBody.
  ///
  /// In zh, this message translates to:
  /// **'一次性开关整组应用与网站，不必逐个点选'**
  String get desktopServicesGroupsBody;

  /// No description provided for @desktopServicesTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用与网站拦截'**
  String get desktopServicesTitle;

  /// No description provided for @desktopServicesBody.
  ///
  /// In zh, this message translates to:
  /// **'一键拦截常见应用与网站，规则随程序内置、无需联网拉取；可与订阅规则、自定义规则叠加生效。'**
  String get desktopServicesBody;

  /// No description provided for @desktopServicesCount.
  ///
  /// In zh, this message translates to:
  /// **'{blocked} / {total} 项已拦截'**
  String desktopServicesCount(int blocked, int total);

  /// No description provided for @desktopServicesClearAll.
  ///
  /// In zh, this message translates to:
  /// **'全部取消'**
  String get desktopServicesClearAll;

  /// No description provided for @desktopServicesCleared.
  ///
  /// In zh, this message translates to:
  /// **'已取消全部应用拦截'**
  String get desktopServicesCleared;

  /// No description provided for @desktopServicesSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索应用名称、域名或规则…'**
  String get desktopServicesSearchHint;

  /// No description provided for @desktopServicesGroupFilter.
  ///
  /// In zh, this message translates to:
  /// **'分组筛选'**
  String get desktopServicesGroupFilter;

  /// No description provided for @desktopServicesAllGroups.
  ///
  /// In zh, this message translates to:
  /// **'全部分组'**
  String get desktopServicesAllGroups;

  /// No description provided for @desktopServicesGroupItem.
  ///
  /// In zh, this message translates to:
  /// **'{name} ({count})'**
  String desktopServicesGroupItem(String name, int count);

  /// No description provided for @desktopServicesGroupChip.
  ///
  /// In zh, this message translates to:
  /// **'{name} · {count}'**
  String desktopServicesGroupChip(String name, int count);

  /// No description provided for @desktopServicesActiveRules.
  ///
  /// In zh, this message translates to:
  /// **'展开 {count} 条规则'**
  String desktopServicesActiveRules(int count);

  /// No description provided for @desktopServicesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'内置服务目录为空'**
  String get desktopServicesEmpty;

  /// No description provided for @desktopServicesNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'未找到符合条件的应用'**
  String get desktopServicesNoMatch;

  /// No description provided for @desktopServicesBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已拦截：{name}'**
  String desktopServicesBlocked(String name);

  /// No description provided for @desktopServicesUnblocked.
  ///
  /// In zh, this message translates to:
  /// **'已取消拦截：{name}'**
  String desktopServicesUnblocked(String name);

  /// No description provided for @desktopServicesActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopServicesActionFailed(String message);

  /// No description provided for @desktopServicesGroupOn.
  ///
  /// In zh, this message translates to:
  /// **'已整组拦截：{name}'**
  String desktopServicesGroupOn(String name);

  /// No description provided for @desktopServicesGroupOff.
  ///
  /// In zh, this message translates to:
  /// **'已取消整组拦截：{name}'**
  String desktopServicesGroupOff(String name);

  /// No description provided for @desktopServicesByGroup.
  ///
  /// In zh, this message translates to:
  /// **'随分组'**
  String get desktopServicesByGroup;

  /// No description provided for @desktopServicesScheduleInside.
  ///
  /// In zh, this message translates to:
  /// **'计划内'**
  String get desktopServicesScheduleInside;

  /// No description provided for @desktopServicesScheduleOutside.
  ///
  /// In zh, this message translates to:
  /// **'计划外'**
  String get desktopServicesScheduleOutside;

  /// No description provided for @desktopServicesRuleCount.
  ///
  /// In zh, this message translates to:
  /// **'{group} · {count} 条规则'**
  String desktopServicesRuleCount(String group, int count);

  /// No description provided for @desktopServicesScheduleEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑每周生效计划'**
  String get desktopServicesScheduleEdit;

  /// No description provided for @desktopServicesShowRules.
  ///
  /// In zh, this message translates to:
  /// **'查看或收起规则'**
  String get desktopServicesShowRules;

  /// No description provided for @desktopServicesScheduleTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} 的每周生效计划'**
  String desktopServicesScheduleTitle(String name);

  /// No description provided for @desktopServicesScheduleBody.
  ///
  /// In zh, this message translates to:
  /// **'仅在命中的时间窗口内拦截该应用，其余时间正常放行。未配置任何计划时恒为拦截；需要某段时间完全不限制时，取消勾选该服务比清空计划更直观。'**
  String get desktopServicesScheduleBody;

  /// No description provided for @desktopServicesScheduleSave.
  ///
  /// In zh, this message translates to:
  /// **'保存计划'**
  String get desktopServicesScheduleSave;

  /// No description provided for @desktopServicesScheduleSaved.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」的每周生效计划已保存'**
  String desktopServicesScheduleSaved(String name);

  /// No description provided for @desktopServicesScheduleRemoved.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」已恢复为始终拦截'**
  String desktopServicesScheduleRemoved(String name);

  /// No description provided for @desktopHubPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'安全隐私'**
  String get desktopHubPrivacy;

  /// No description provided for @desktopHubPrivacyBody.
  ///
  /// In zh, this message translates to:
  /// **'协议加固、ECS 子网隐私与内置重绑定 / hosts 防御'**
  String get desktopHubPrivacyBody;

  /// No description provided for @desktopPrivacyPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全隐私'**
  String get desktopPrivacyPageTitle;

  /// No description provided for @desktopPrivacyRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新安全隐私配置'**
  String get desktopPrivacyRefresh;

  /// No description provided for @desktopPrivacyLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到安全隐私配置'**
  String get desktopPrivacyLoadFailed;

  /// No description provided for @desktopPrivacySaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{message}'**
  String desktopPrivacySaveFailed(String message);

  /// No description provided for @desktopPrivacyProtocolTitle.
  ///
  /// In zh, this message translates to:
  /// **'协议隐私与外泄防御'**
  String get desktopPrivacyProtocolTitle;

  /// No description provided for @desktopPrivacyProtocolBody.
  ///
  /// In zh, this message translates to:
  /// **'阻断局域网私有 PTR 与单标签域名泄露，防御 ECH 加密绕过与报文侧信道嗅探'**
  String get desktopPrivacyProtocolBody;

  /// No description provided for @desktopPrivacyBlockTitle.
  ///
  /// In zh, this message translates to:
  /// **'记录类型拦截'**
  String get desktopPrivacyBlockTitle;

  /// No description provided for @desktopPrivacyBlockBody.
  ///
  /// In zh, this message translates to:
  /// **'ECH、ANY 与 IPv6 查询的拦截策略，与协议加固分开设置'**
  String get desktopPrivacyBlockBody;

  /// No description provided for @desktopPrivacyEdeTitle.
  ///
  /// In zh, this message translates to:
  /// **'Extended DNS Errors（EDE 错误诊断扩展）'**
  String get desktopPrivacyEdeTitle;

  /// No description provided for @desktopPrivacyEdeBody.
  ///
  /// In zh, this message translates to:
  /// **'向支持的客户端在 OPT 报文中透明返回 RFC 8914 扩展错误代码与原因说明（如策略阻断、速率超限、Rebind 拦截或上游解析故障）。'**
  String get desktopPrivacyEdeBody;

  /// No description provided for @desktopPrivacyEdeOn.
  ///
  /// In zh, this message translates to:
  /// **'EDE 错误诊断已开启'**
  String get desktopPrivacyEdeOn;

  /// No description provided for @desktopPrivacyEdeOff.
  ///
  /// In zh, this message translates to:
  /// **'EDE 错误诊断已关闭'**
  String get desktopPrivacyEdeOff;

  /// No description provided for @desktopPrivacyPtrTitle.
  ///
  /// In zh, this message translates to:
  /// **'私有反向 PTR 解析防泄露'**
  String get desktopPrivacyPtrTitle;

  /// No description provided for @desktopPrivacyPtrBody.
  ///
  /// In zh, this message translates to:
  /// **'阻断局域网私有 IP 的反向域名 PTR 查询向公共上游泄露；命中且未在本地绑定的反查直接返回权威 NXDOMAIN。'**
  String get desktopPrivacyPtrBody;

  /// No description provided for @desktopPrivacyPtrOn.
  ///
  /// In zh, this message translates to:
  /// **'私有 PTR 防泄露已开启'**
  String get desktopPrivacyPtrOn;

  /// No description provided for @desktopPrivacyPtrOff.
  ///
  /// In zh, this message translates to:
  /// **'私有 PTR 防泄露已关闭'**
  String get desktopPrivacyPtrOff;

  /// No description provided for @desktopPrivacyUnqualifiedTitle.
  ///
  /// In zh, this message translates to:
  /// **'阻止无点单标签域名外泄'**
  String get desktopPrivacyUnqualifiedTitle;

  /// No description provided for @desktopPrivacyUnqualifiedBody.
  ///
  /// In zh, this message translates to:
  /// **'拦截没有顶级域名点分隔的内部单标签请求（如 router、printer），防止拼写错误或搜索域缺失导致内网主机名泄漏至公共递归解析器。'**
  String get desktopPrivacyUnqualifiedBody;

  /// No description provided for @desktopPrivacyUnqualifiedOn.
  ///
  /// In zh, this message translates to:
  /// **'单标签域名防外泄已开启'**
  String get desktopPrivacyUnqualifiedOn;

  /// No description provided for @desktopPrivacyUnqualifiedOff.
  ///
  /// In zh, this message translates to:
  /// **'单标签域名防外泄已关闭'**
  String get desktopPrivacyUnqualifiedOff;

  /// No description provided for @desktopPrivacyEchTitle.
  ///
  /// In zh, this message translates to:
  /// **'剥离 ECH（加密 ClientHello）'**
  String get desktopPrivacyEchTitle;

  /// No description provided for @desktopPrivacyEchBody.
  ///
  /// In zh, this message translates to:
  /// **'从上游 HTTPS / SVCB 资源记录中过滤剥离 ech 参数，防止客户端用 TLS 1.3 ECH 隐藏真实域名而绕过本地审计。'**
  String get desktopPrivacyEchBody;

  /// No description provided for @desktopPrivacyEchOn.
  ///
  /// In zh, this message translates to:
  /// **'ECH 剥离已开启'**
  String get desktopPrivacyEchOn;

  /// No description provided for @desktopPrivacyEchOff.
  ///
  /// In zh, this message translates to:
  /// **'ECH 剥离已关闭'**
  String get desktopPrivacyEchOff;

  /// No description provided for @desktopPrivacyAnyTitle.
  ///
  /// In zh, this message translates to:
  /// **'ANY 查询最小化'**
  String get desktopPrivacyAnyTitle;

  /// No description provided for @desktopPrivacyAnyBody.
  ///
  /// In zh, this message translates to:
  /// **'ANY 查询常被用于 DNS 放大攻击，也会让按记录类型下发的拦截失效；开启后本机不再转发 ANY，而是直接给出最小化应答。'**
  String get desktopPrivacyAnyBody;

  /// No description provided for @desktopPrivacyAnyOn.
  ///
  /// In zh, this message translates to:
  /// **'ANY 查询最小化已开启'**
  String get desktopPrivacyAnyOn;

  /// No description provided for @desktopPrivacyAnyOff.
  ///
  /// In zh, this message translates to:
  /// **'ANY 查询最小化已关闭'**
  String get desktopPrivacyAnyOff;

  /// No description provided for @desktopPrivacyAnyModeLabel.
  ///
  /// In zh, this message translates to:
  /// **'应答形式'**
  String get desktopPrivacyAnyModeLabel;

  /// No description provided for @desktopPrivacyAnyModeNotimp.
  ///
  /// In zh, this message translates to:
  /// **'NOTIMP（推荐）'**
  String get desktopPrivacyAnyModeNotimp;

  /// No description provided for @desktopPrivacyAnyModeNotimpBody.
  ///
  /// In zh, this message translates to:
  /// **'明确回应「不支持该查询」，客户端不会把它误当成一次有效解析。'**
  String get desktopPrivacyAnyModeNotimpBody;

  /// No description provided for @desktopPrivacyAnyModeRfc.
  ///
  /// In zh, this message translates to:
  /// **'RFC 8482 最小应答'**
  String get desktopPrivacyAnyModeRfc;

  /// No description provided for @desktopPrivacyAnyModeRfcBody.
  ///
  /// In zh, this message translates to:
  /// **'返回 NOERROR + 一条 HINFO(\"RFC8482\")，语义更准确，但需要客户端理解这一约定。'**
  String get desktopPrivacyAnyModeRfcBody;

  /// No description provided for @desktopPrivacyAnyModeSaved.
  ///
  /// In zh, this message translates to:
  /// **'ANY 最小化应答形式已保存'**
  String get desktopPrivacyAnyModeSaved;

  /// No description provided for @desktopPrivacyIpv6Title.
  ///
  /// In zh, this message translates to:
  /// **'过滤 IPv6（AAAA）查询'**
  String get desktopPrivacyIpv6Title;

  /// No description provided for @desktopPrivacyIpv6Body.
  ///
  /// In zh, this message translates to:
  /// **'对所有 AAAA 查询秒级应答权威 NODATA，并在 HTTPS 查询中过滤 ipv6hint；在 IPv6 不佳的网络里消除双栈重试导致的卡顿。'**
  String get desktopPrivacyIpv6Body;

  /// No description provided for @desktopPrivacyIpv6On.
  ///
  /// In zh, this message translates to:
  /// **'IPv6 过滤已开启'**
  String get desktopPrivacyIpv6On;

  /// No description provided for @desktopPrivacyIpv6Off.
  ///
  /// In zh, this message translates to:
  /// **'IPv6 过滤已关闭'**
  String get desktopPrivacyIpv6Off;

  /// No description provided for @desktopPrivacyPaddingTitle.
  ///
  /// In zh, this message translates to:
  /// **'EDNS0 报文填充大小'**
  String get desktopPrivacyPaddingTitle;

  /// No description provided for @desktopPrivacyPaddingBody.
  ///
  /// In zh, this message translates to:
  /// **'对加密 DNS 填充至固定块，防范报文长度指纹侧信道分析。'**
  String get desktopPrivacyPaddingBody;

  /// No description provided for @desktopPrivacyPaddingValue.
  ///
  /// In zh, this message translates to:
  /// **'{size} 字节'**
  String desktopPrivacyPaddingValue(int size);

  /// No description provided for @desktopPrivacyPaddingSaved.
  ///
  /// In zh, this message translates to:
  /// **'EDNS0 填充大小已保存'**
  String get desktopPrivacyPaddingSaved;

  /// No description provided for @desktopPrivacyEcsTitle.
  ///
  /// In zh, this message translates to:
  /// **'EDNS Client Subnet（ECS 策略）'**
  String get desktopPrivacyEcsTitle;

  /// No description provided for @desktopPrivacyEcsBody.
  ///
  /// In zh, this message translates to:
  /// **'ECS 允许向递归解析器携带客户端所在子网以优化 CDN 调度，但未经处理的原生 ECS 会向上游泄露家庭或企业内网真实网段。'**
  String get desktopPrivacyEcsBody;

  /// No description provided for @desktopPrivacyEcsOn.
  ///
  /// In zh, this message translates to:
  /// **'ECS 策略已生效'**
  String get desktopPrivacyEcsOn;

  /// No description provided for @desktopPrivacyEcsOff.
  ///
  /// In zh, this message translates to:
  /// **'策略已停用'**
  String get desktopPrivacyEcsOff;

  /// No description provided for @desktopPrivacyEcsOnMessage.
  ///
  /// In zh, this message translates to:
  /// **'ECS 策略已开启'**
  String get desktopPrivacyEcsOnMessage;

  /// No description provided for @desktopPrivacyEcsOffMessage.
  ///
  /// In zh, this message translates to:
  /// **'ECS 策略已关闭'**
  String get desktopPrivacyEcsOffMessage;

  /// No description provided for @desktopPrivacyEcsStripTitle.
  ///
  /// In zh, this message translates to:
  /// **'剥离请求中的真实客户端子网'**
  String get desktopPrivacyEcsStripTitle;

  /// No description provided for @desktopPrivacyEcsStripBody.
  ///
  /// In zh, this message translates to:
  /// **'开启后转发查询时主动抹除客户端发送的真实出口子网信息，保障家庭或内网各设备的网络隐私。'**
  String get desktopPrivacyEcsStripBody;

  /// No description provided for @desktopPrivacyEcsStripOn.
  ///
  /// In zh, this message translates to:
  /// **'真实客户端子网剥离已开启'**
  String get desktopPrivacyEcsStripOn;

  /// No description provided for @desktopPrivacyEcsStripOff.
  ///
  /// In zh, this message translates to:
  /// **'真实客户端子网剥离已关闭'**
  String get desktopPrivacyEcsStripOff;

  /// No description provided for @desktopPrivacyEcsSubnetLabel.
  ///
  /// In zh, this message translates to:
  /// **'自定义转发子网（CIDR）'**
  String get desktopPrivacyEcsSubnetLabel;

  /// No description provided for @desktopPrivacyEcsSubnetHelper.
  ///
  /// In zh, this message translates to:
  /// **'可选。填写公共出口网段向权威 DNS 伪装位置以保持 CDN 调度，留空则完全保密。'**
  String get desktopPrivacyEcsSubnetHelper;

  /// No description provided for @desktopPrivacyEcsSave.
  ///
  /// In zh, this message translates to:
  /// **'保存 ECS 策略'**
  String get desktopPrivacyEcsSave;

  /// No description provided for @desktopPrivacyEcsSaved.
  ///
  /// In zh, this message translates to:
  /// **'EDNS Client Subnet 客户端子网策略已更新'**
  String get desktopPrivacyEcsSaved;

  /// No description provided for @desktopPrivacyDefenceTitle.
  ///
  /// In zh, this message translates to:
  /// **'内置安全防御模块'**
  String get desktopPrivacyDefenceTitle;

  /// No description provided for @desktopPrivacyDefenceBody.
  ///
  /// In zh, this message translates to:
  /// **'重绑定防御与本地 Hosts 解析的运行状态与配置'**
  String get desktopPrivacyDefenceBody;

  /// No description provided for @desktopPrivacyRebindTitle.
  ///
  /// In zh, this message translates to:
  /// **'DNS 重绑定防御'**
  String get desktopPrivacyRebindTitle;

  /// No description provided for @desktopPrivacyRebindBody.
  ///
  /// In zh, this message translates to:
  /// **'阻断外网域名解析为私有 IP，防止攻击者用 DNS 重绑定访问局域网设备。'**
  String get desktopPrivacyRebindBody;

  /// No description provided for @desktopPrivacyRebindOn.
  ///
  /// In zh, this message translates to:
  /// **'DNS 重绑定防御已开启'**
  String get desktopPrivacyRebindOn;

  /// No description provided for @desktopPrivacyRebindOff.
  ///
  /// In zh, this message translates to:
  /// **'DNS 重绑定防御已关闭'**
  String get desktopPrivacyRebindOff;

  /// No description provided for @desktopPrivacyRebindCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个白名单域名'**
  String desktopPrivacyRebindCount(int count);

  /// No description provided for @desktopPrivacyRebindAllowlist.
  ///
  /// In zh, this message translates to:
  /// **'白名单设置'**
  String get desktopPrivacyRebindAllowlist;

  /// No description provided for @desktopPrivacyRebindDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'DNS 重绑定防御白名单域名'**
  String get desktopPrivacyRebindDialogTitle;

  /// No description provided for @desktopPrivacyRebindDialogBody.
  ///
  /// In zh, this message translates to:
  /// **'名单内的域名允许解析为局域网私有 IP（如 192.168.x.x、10.x.x.x、127.0.0.1），支持后缀通配（如 .lan、.local）。每行一个。'**
  String get desktopPrivacyRebindDialogBody;

  /// No description provided for @desktopPrivacyRebindDialogSave.
  ///
  /// In zh, this message translates to:
  /// **'保存白名单'**
  String get desktopPrivacyRebindDialogSave;

  /// No description provided for @desktopPrivacyRebindSaved.
  ///
  /// In zh, this message translates to:
  /// **'DNS 重绑定防御白名单已保存'**
  String get desktopPrivacyRebindSaved;

  /// No description provided for @desktopPrivacyHostsTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地 Hosts 解析器'**
  String get desktopPrivacyHostsTitle;

  /// No description provided for @desktopPrivacyHostsBody.
  ///
  /// In zh, this message translates to:
  /// **'系统与自定义 hosts 映射优先应答，命中后不再向上游查询。'**
  String get desktopPrivacyHostsBody;

  /// No description provided for @desktopPrivacyHostsOn.
  ///
  /// In zh, this message translates to:
  /// **'本地 Hosts 解析已开启'**
  String get desktopPrivacyHostsOn;

  /// No description provided for @desktopPrivacyHostsOff.
  ///
  /// In zh, this message translates to:
  /// **'本地 Hosts 解析已关闭'**
  String get desktopPrivacyHostsOff;

  /// No description provided for @desktopPrivacyHostsSystem.
  ///
  /// In zh, this message translates to:
  /// **'联动系统 hosts 文件'**
  String get desktopPrivacyHostsSystem;

  /// No description provided for @desktopPrivacyHostsTtl.
  ///
  /// In zh, this message translates to:
  /// **'TTL {seconds}s'**
  String desktopPrivacyHostsTtl(int seconds);

  /// No description provided for @desktopPrivacyHostsSystemOn.
  ///
  /// In zh, this message translates to:
  /// **'已联动系统 hosts'**
  String get desktopPrivacyHostsSystemOn;

  /// No description provided for @desktopPrivacyHostsSystemOff.
  ///
  /// In zh, this message translates to:
  /// **'已停止联动系统 hosts'**
  String get desktopPrivacyHostsSystemOff;

  /// No description provided for @desktopHubPrivacySection.
  ///
  /// In zh, this message translates to:
  /// **'隐私与加密'**
  String get desktopHubPrivacySection;

  /// No description provided for @desktopHubShareSection.
  ///
  /// In zh, this message translates to:
  /// **'网络共享'**
  String get desktopHubShareSection;

  /// No description provided for @desktopSafeSearchTitle.
  ///
  /// In zh, this message translates to:
  /// **'强制安全搜索'**
  String get desktopSafeSearchTitle;

  /// No description provided for @desktopSafeSearchBody.
  ///
  /// In zh, this message translates to:
  /// **'把主流搜索引擎重写为强制过滤入口，从 DNS 层确保无法关闭安全搜索。属新增拦截能力，默认关闭。'**
  String get desktopSafeSearchBody;

  /// No description provided for @desktopSafeSearchEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已生效 · {count} 家'**
  String desktopSafeSearchEnabled(int count);

  /// No description provided for @desktopSafeSearchOff.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get desktopSafeSearchOff;

  /// No description provided for @desktopSafeSearchOn.
  ///
  /// In zh, this message translates to:
  /// **'强制安全搜索已开启'**
  String get desktopSafeSearchOn;

  /// No description provided for @desktopSafeSearchOffMessage.
  ///
  /// In zh, this message translates to:
  /// **'强制安全搜索已关闭'**
  String get desktopSafeSearchOffMessage;

  /// No description provided for @desktopSafeSearchServiceSaved.
  ///
  /// In zh, this message translates to:
  /// **'安全搜索服务商已更新'**
  String get desktopSafeSearchServiceSaved;

  /// No description provided for @desktopSafeSearchTtl.
  ///
  /// In zh, this message translates to:
  /// **'重写应答 TTL（秒）'**
  String get desktopSafeSearchTtl;

  /// No description provided for @desktopSafeSearchTtlSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get desktopSafeSearchTtlSave;

  /// No description provided for @desktopSafeSearchTtlSaved.
  ///
  /// In zh, this message translates to:
  /// **'安全搜索应答 TTL 已保存'**
  String get desktopSafeSearchTtlSaved;

  /// No description provided for @desktopSafeSearchTtlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'TTL 需为正整数'**
  String get desktopSafeSearchTtlInvalid;

  /// No description provided for @desktopSafeSearchFooter.
  ///
  /// In zh, this message translates to:
  /// **'未勾选的服务商将直接透传正常解析。'**
  String get desktopSafeSearchFooter;

  /// No description provided for @desktopSafeSearchTtlCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全搜索改写有效期'**
  String get desktopSafeSearchTtlCardTitle;

  /// No description provided for @desktopSafeSearchTtlCardBody.
  ///
  /// In zh, this message translates to:
  /// **'强制安全搜索的改写记录在本地保留多久，到期后重新向上游确认。'**
  String get desktopSafeSearchTtlCardBody;

  /// No description provided for @desktopSafeSearchTtlChip.
  ///
  /// In zh, this message translates to:
  /// **'当前 {seconds}s'**
  String desktopSafeSearchTtlChip(int seconds);

  /// No description provided for @desktopSafeSearchBing.
  ///
  /// In zh, this message translates to:
  /// **'Bing'**
  String get desktopSafeSearchBing;

  /// No description provided for @desktopSafeSearchDuckDuckGo.
  ///
  /// In zh, this message translates to:
  /// **'DuckDuckGo'**
  String get desktopSafeSearchDuckDuckGo;

  /// No description provided for @desktopSafeSearchEcosia.
  ///
  /// In zh, this message translates to:
  /// **'Ecosia'**
  String get desktopSafeSearchEcosia;

  /// No description provided for @desktopSafeSearchGoogle.
  ///
  /// In zh, this message translates to:
  /// **'Google'**
  String get desktopSafeSearchGoogle;

  /// No description provided for @desktopSafeSearchPixabay.
  ///
  /// In zh, this message translates to:
  /// **'Pixabay'**
  String get desktopSafeSearchPixabay;

  /// No description provided for @desktopSafeSearchYandex.
  ///
  /// In zh, this message translates to:
  /// **'Yandex'**
  String get desktopSafeSearchYandex;

  /// No description provided for @desktopSafeSearchYoutube.
  ///
  /// In zh, this message translates to:
  /// **'YouTube'**
  String get desktopSafeSearchYoutube;

  /// No description provided for @desktopReputationTitle.
  ///
  /// In zh, this message translates to:
  /// **'恶意网址库（Safe Browsing）'**
  String get desktopReputationTitle;

  /// No description provided for @desktopReputationOn.
  ///
  /// In zh, this message translates to:
  /// **'查询中'**
  String get desktopReputationOn;

  /// No description provided for @desktopReputationOff.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get desktopReputationOff;

  /// No description provided for @desktopReputationOnMessage.
  ///
  /// In zh, this message translates to:
  /// **'恶意网址库查询已开启'**
  String get desktopReputationOnMessage;

  /// No description provided for @desktopReputationOffMessage.
  ///
  /// In zh, this message translates to:
  /// **'恶意网址库查询已关闭'**
  String get desktopReputationOffMessage;

  /// No description provided for @desktopReputationBody.
  ///
  /// In zh, this message translates to:
  /// **'查询时只把域名的 SHA-256 前 2 字节发往第三方哈希前缀服务，对方返回命中的完整摘要，本地再比对；第三方无法从这 2 个字节还原完整域名。查询失败一律放行。'**
  String get desktopReputationBody;

  /// No description provided for @desktopReputationLookups.
  ///
  /// In zh, this message translates to:
  /// **'查询次数'**
  String get desktopReputationLookups;

  /// No description provided for @desktopReputationBlocked.
  ///
  /// In zh, this message translates to:
  /// **'命中拦截'**
  String get desktopReputationBlocked;

  /// No description provided for @desktopReputationHitRate.
  ///
  /// In zh, this message translates to:
  /// **'缓存命中率'**
  String get desktopReputationHitRate;

  /// No description provided for @desktopReputationFailures.
  ///
  /// In zh, this message translates to:
  /// **'查询失败'**
  String get desktopReputationFailures;

  /// No description provided for @desktopReputationAnswer.
  ///
  /// In zh, this message translates to:
  /// **'拦截方式'**
  String get desktopReputationAnswer;

  /// No description provided for @desktopReputationAnswerNullIp.
  ///
  /// In zh, this message translates to:
  /// **'空地址'**
  String get desktopReputationAnswerNullIp;

  /// No description provided for @desktopReputationTimeout.
  ///
  /// In zh, this message translates to:
  /// **'查询超时（毫秒）'**
  String get desktopReputationTimeout;

  /// No description provided for @desktopReputationCacheSize.
  ///
  /// In zh, this message translates to:
  /// **'缓存条目上限'**
  String get desktopReputationCacheSize;

  /// No description provided for @desktopReputationCacheTtl.
  ///
  /// In zh, this message translates to:
  /// **'缓存有效期（秒）'**
  String get desktopReputationCacheTtl;

  /// No description provided for @desktopReputationParamsTitle.
  ///
  /// In zh, this message translates to:
  /// **'查询参数'**
  String get desktopReputationParamsTitle;

  /// No description provided for @desktopReputationParamsInvalid.
  ///
  /// In zh, this message translates to:
  /// **'超时与缓存有效期需为正整数，缓存条目不能为负'**
  String get desktopReputationParamsInvalid;

  /// No description provided for @desktopReputationParamsSave.
  ///
  /// In zh, this message translates to:
  /// **'保存查询参数'**
  String get desktopReputationParamsSave;

  /// No description provided for @desktopReputationParamsSaved.
  ///
  /// In zh, this message translates to:
  /// **'查询参数已保存'**
  String get desktopReputationParamsSaved;

  /// No description provided for @desktopReputationFooter.
  ///
  /// In zh, this message translates to:
  /// **'缓存按 2 字节前缀索引，同一前缀下的域名共享一次查询。'**
  String get desktopReputationFooter;

  /// No description provided for @desktopParentalTitle.
  ///
  /// In zh, this message translates to:
  /// **'家长控制'**
  String get desktopParentalTitle;

  /// No description provided for @desktopParentalBody.
  ///
  /// In zh, this message translates to:
  /// **'与恶意网址库机制相同，借第三方分类库拦截成人内容域名；两者各自独立开关，可只开家长控制。'**
  String get desktopParentalBody;

  /// No description provided for @desktopParentalWarning.
  ///
  /// In zh, this message translates to:
  /// **'恶意网址库当前未开启。两者互不依赖，但钓鱼与恶意软件站点不在家长控制的分类范围内。'**
  String get desktopParentalWarning;

  /// No description provided for @desktopParentalOn.
  ///
  /// In zh, this message translates to:
  /// **'家长控制已开启'**
  String get desktopParentalOn;

  /// No description provided for @desktopParentalOff.
  ///
  /// In zh, this message translates to:
  /// **'家长控制已关闭'**
  String get desktopParentalOff;

  /// No description provided for @desktopHubEncrypted.
  ///
  /// In zh, this message translates to:
  /// **'加密 DNS 服务'**
  String get desktopHubEncrypted;

  /// No description provided for @desktopHubEncryptedBody.
  ///
  /// In zh, this message translates to:
  /// **'以 DoT / DoH / DoQ 向局域网提供加密解析，含证书与 DDR'**
  String get desktopHubEncryptedBody;

  /// No description provided for @desktopEncryptedPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'加密 DNS 服务'**
  String get desktopEncryptedPageTitle;

  /// No description provided for @desktopEncryptedRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新加密 DNS 状态'**
  String get desktopEncryptedRefresh;

  /// No description provided for @desktopEncryptedLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到加密 DNS 服务状态'**
  String get desktopEncryptedLoadFailed;

  /// No description provided for @desktopEncryptedSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopEncryptedSaveFailed(String message);

  /// No description provided for @desktopEncryptedListenersTitle.
  ///
  /// In zh, this message translates to:
  /// **'加密 DNS 服务'**
  String get desktopEncryptedListenersTitle;

  /// No description provided for @desktopEncryptedListenersBody.
  ///
  /// In zh, this message translates to:
  /// **'在局域网内以 DoT / DoH / DoQ 提供解析，终端无需明文查询'**
  String get desktopEncryptedListenersBody;

  /// No description provided for @desktopEncryptedEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get desktopEncryptedEnabled;

  /// No description provided for @desktopEncryptedDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get desktopEncryptedDisabled;

  /// No description provided for @desktopEncryptedOn.
  ///
  /// In zh, this message translates to:
  /// **'加密 DNS 服务已开启'**
  String get desktopEncryptedOn;

  /// No description provided for @desktopEncryptedOff.
  ///
  /// In zh, this message translates to:
  /// **'加密 DNS 服务已关闭'**
  String get desktopEncryptedOff;

  /// No description provided for @desktopEncryptedNoProtocol.
  ///
  /// In zh, this message translates to:
  /// **'服务总开关已打开，但三种协议都没选中，因此不会有任何监听。'**
  String get desktopEncryptedNoProtocol;

  /// No description provided for @desktopEncryptedDot.
  ///
  /// In zh, this message translates to:
  /// **'DoT · DNS over TLS'**
  String get desktopEncryptedDot;

  /// No description provided for @desktopEncryptedDotBody.
  ///
  /// In zh, this message translates to:
  /// **'端口 {port}，客户端用 tls:// 连接'**
  String desktopEncryptedDotBody(int port);

  /// No description provided for @desktopEncryptedDoh.
  ///
  /// In zh, this message translates to:
  /// **'DoH · DNS over HTTPS'**
  String get desktopEncryptedDoh;

  /// No description provided for @desktopEncryptedDohBody.
  ///
  /// In zh, this message translates to:
  /// **'端口 {port}，路径 {path}'**
  String desktopEncryptedDohBody(int port, String path);

  /// No description provided for @desktopEncryptedDoq.
  ///
  /// In zh, this message translates to:
  /// **'DoQ · DNS over QUIC'**
  String get desktopEncryptedDoq;

  /// No description provided for @desktopEncryptedDoqBody.
  ///
  /// In zh, this message translates to:
  /// **'端口 {port}，UDP 上的加密解析'**
  String desktopEncryptedDoqBody(int port);

  /// No description provided for @desktopEncryptedListening.
  ///
  /// In zh, this message translates to:
  /// **'正在监听 {address}'**
  String desktopEncryptedListening(String address);

  /// No description provided for @desktopEncryptedNotListening.
  ///
  /// In zh, this message translates to:
  /// **'未在监听（服务未启动、证书不可用或端口被占用）'**
  String get desktopEncryptedNotListening;

  /// No description provided for @desktopEncryptedDotOn.
  ///
  /// In zh, this message translates to:
  /// **'DoT 已启用'**
  String get desktopEncryptedDotOn;

  /// No description provided for @desktopEncryptedDotOff.
  ///
  /// In zh, this message translates to:
  /// **'DoT 已停用'**
  String get desktopEncryptedDotOff;

  /// No description provided for @desktopEncryptedDohOn.
  ///
  /// In zh, this message translates to:
  /// **'DoH 已启用'**
  String get desktopEncryptedDohOn;

  /// No description provided for @desktopEncryptedDohOff.
  ///
  /// In zh, this message translates to:
  /// **'DoH 已停用'**
  String get desktopEncryptedDohOff;

  /// No description provided for @desktopEncryptedDoqOn.
  ///
  /// In zh, this message translates to:
  /// **'DoQ 已启用'**
  String get desktopEncryptedDoqOn;

  /// No description provided for @desktopEncryptedDoqOff.
  ///
  /// In zh, this message translates to:
  /// **'DoQ 已停用'**
  String get desktopEncryptedDoqOff;

  /// No description provided for @desktopEncryptedUrls.
  ///
  /// In zh, this message translates to:
  /// **'客户端填写以下任一地址即可使用：'**
  String get desktopEncryptedUrls;

  /// No description provided for @desktopEncryptedNetworkTitle.
  ///
  /// In zh, this message translates to:
  /// **'监听参数'**
  String get desktopEncryptedNetworkTitle;

  /// No description provided for @desktopEncryptedListenAddress.
  ///
  /// In zh, this message translates to:
  /// **'监听地址'**
  String get desktopEncryptedListenAddress;

  /// No description provided for @desktopEncryptedListenHint.
  ///
  /// In zh, this message translates to:
  /// **'留空表示全部网卡'**
  String get desktopEncryptedListenHint;

  /// No description provided for @desktopEncryptedServerName.
  ///
  /// In zh, this message translates to:
  /// **'服务器名（客户端连接用）'**
  String get desktopEncryptedServerName;

  /// No description provided for @desktopEncryptedDotPort.
  ///
  /// In zh, this message translates to:
  /// **'DoT 端口'**
  String get desktopEncryptedDotPort;

  /// No description provided for @desktopEncryptedDohPort.
  ///
  /// In zh, this message translates to:
  /// **'DoH 端口'**
  String get desktopEncryptedDohPort;

  /// No description provided for @desktopEncryptedDoqPort.
  ///
  /// In zh, this message translates to:
  /// **'DoQ 端口'**
  String get desktopEncryptedDoqPort;

  /// No description provided for @desktopEncryptedDohPath.
  ///
  /// In zh, this message translates to:
  /// **'DoH 路径'**
  String get desktopEncryptedDohPath;

  /// No description provided for @desktopEncryptedServerNameHint.
  ///
  /// In zh, this message translates to:
  /// **'服务器名会被写进证书的 SAN，终端按它连接才不会报证书错误。'**
  String get desktopEncryptedServerNameHint;

  /// No description provided for @desktopEncryptedPortInvalid.
  ///
  /// In zh, this message translates to:
  /// **'端口需为 1–65535 的整数'**
  String get desktopEncryptedPortInvalid;

  /// No description provided for @desktopEncryptedReset.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get desktopEncryptedReset;

  /// No description provided for @desktopEncryptedSaveNetwork.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get desktopEncryptedSaveNetwork;

  /// No description provided for @desktopEncryptedNetworkSaved.
  ///
  /// In zh, this message translates to:
  /// **'监听参数已保存'**
  String get desktopEncryptedNetworkSaved;

  /// No description provided for @desktopEncryptedCertTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务端证书'**
  String get desktopEncryptedCertTitle;

  /// No description provided for @desktopEncryptedCertBody.
  ///
  /// In zh, this message translates to:
  /// **'服务端 TLS 证书的摘要；私钥不会离开本机'**
  String get desktopEncryptedCertBody;

  /// No description provided for @desktopEncryptedCertSelfSigned.
  ///
  /// In zh, this message translates to:
  /// **'自签证书'**
  String get desktopEncryptedCertSelfSigned;

  /// No description provided for @desktopEncryptedCertLoaded.
  ///
  /// In zh, this message translates to:
  /// **'已载入'**
  String get desktopEncryptedCertLoaded;

  /// No description provided for @desktopEncryptedCertMissing.
  ///
  /// In zh, this message translates to:
  /// **'未载入'**
  String get desktopEncryptedCertMissing;

  /// No description provided for @desktopEncryptedCertExpired.
  ///
  /// In zh, this message translates to:
  /// **'服务端证书已过期：客户端 TLS 握手会全部失败。请立即重新签发或导入有效证书。'**
  String get desktopEncryptedCertExpired;

  /// No description provided for @desktopEncryptedCertExpiresSoon.
  ///
  /// In zh, this message translates to:
  /// **'服务端自签证书将在 30 天内到期。到期后所有加密查询都会握手失败，建议尽早重新签发。'**
  String get desktopEncryptedCertExpiresSoon;

  /// No description provided for @desktopEncryptedCertMissingBody.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置可用证书，加密监听无法启动。'**
  String get desktopEncryptedCertMissingBody;

  /// No description provided for @desktopEncryptedCertSubject.
  ///
  /// In zh, this message translates to:
  /// **'主体'**
  String get desktopEncryptedCertSubject;

  /// No description provided for @desktopEncryptedCertIssuer.
  ///
  /// In zh, this message translates to:
  /// **'签发者'**
  String get desktopEncryptedCertIssuer;

  /// No description provided for @desktopEncryptedCertNotAfter.
  ///
  /// In zh, this message translates to:
  /// **'有效期至'**
  String get desktopEncryptedCertNotAfter;

  /// No description provided for @desktopEncryptedCertDays.
  ///
  /// In zh, this message translates to:
  /// **'剩余天数'**
  String get desktopEncryptedCertDays;

  /// No description provided for @desktopEncryptedCertDaysValue.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天'**
  String desktopEncryptedCertDaysValue(int days);

  /// No description provided for @desktopEncryptedCertDns.
  ///
  /// In zh, this message translates to:
  /// **'覆盖域名'**
  String get desktopEncryptedCertDns;

  /// No description provided for @desktopEncryptedCertIps.
  ///
  /// In zh, this message translates to:
  /// **'覆盖 IP'**
  String get desktopEncryptedCertIps;

  /// No description provided for @desktopEncryptedCertFingerprint.
  ///
  /// In zh, this message translates to:
  /// **'SHA-256：{fingerprint}'**
  String desktopEncryptedCertFingerprint(String fingerprint);

  /// No description provided for @desktopEncryptedCertDir.
  ///
  /// In zh, this message translates to:
  /// **'证书目录：{dir}'**
  String desktopEncryptedCertDir(String dir);

  /// No description provided for @desktopEncryptedCertGenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新签发'**
  String get desktopEncryptedCertGenerate;

  /// No description provided for @desktopEncryptedCertImport.
  ///
  /// In zh, this message translates to:
  /// **'导入 PEM'**
  String get desktopEncryptedCertImport;

  /// No description provided for @desktopEncryptedCertGenerated.
  ///
  /// In zh, this message translates to:
  /// **'证书已生成'**
  String get desktopEncryptedCertGenerated;

  /// No description provided for @desktopEncryptedCertImported.
  ///
  /// In zh, this message translates to:
  /// **'证书已导入'**
  String get desktopEncryptedCertImported;

  /// No description provided for @desktopEncryptedCertGenerateTitle.
  ///
  /// In zh, this message translates to:
  /// **'生成自签证书'**
  String get desktopEncryptedCertGenerateTitle;

  /// No description provided for @desktopEncryptedCertGenerateBody.
  ///
  /// In zh, this message translates to:
  /// **'覆盖性动作：已信任旧证书的客户端将全部失效。'**
  String get desktopEncryptedCertGenerateBody;

  /// No description provided for @desktopEncryptedCertKeyType.
  ///
  /// In zh, this message translates to:
  /// **'密钥类型'**
  String get desktopEncryptedCertKeyType;

  /// No description provided for @desktopEncryptedCertCommonName.
  ///
  /// In zh, this message translates to:
  /// **'通用名（CN）'**
  String get desktopEncryptedCertCommonName;

  /// No description provided for @desktopEncryptedCertDnsNames.
  ///
  /// In zh, this message translates to:
  /// **'SAN 域名（每行一个）'**
  String get desktopEncryptedCertDnsNames;

  /// No description provided for @desktopEncryptedCertIpAddresses.
  ///
  /// In zh, this message translates to:
  /// **'SAN IP（每行一个）'**
  String get desktopEncryptedCertIpAddresses;

  /// No description provided for @desktopEncryptedCertValidDays.
  ///
  /// In zh, this message translates to:
  /// **'有效期（天）'**
  String get desktopEncryptedCertValidDays;

  /// No description provided for @desktopEncryptedCertGenerateConfirm.
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get desktopEncryptedCertGenerateConfirm;

  /// No description provided for @desktopEncryptedCertImportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入 PEM 证书'**
  String get desktopEncryptedCertImportTitle;

  /// No description provided for @desktopEncryptedCertImportBody.
  ///
  /// In zh, this message translates to:
  /// **'粘贴证书链与私钥 PEM 文本，两者必须匹配。'**
  String get desktopEncryptedCertImportBody;

  /// No description provided for @desktopEncryptedCertPem.
  ///
  /// In zh, this message translates to:
  /// **'证书链 PEM'**
  String get desktopEncryptedCertPem;

  /// No description provided for @desktopEncryptedKeyPem.
  ///
  /// In zh, this message translates to:
  /// **'私钥 PEM'**
  String get desktopEncryptedKeyPem;

  /// No description provided for @desktopEncryptedCertImportConfirm.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get desktopEncryptedCertImportConfirm;

  /// No description provided for @desktopEncryptedCertImportInvalid.
  ///
  /// In zh, this message translates to:
  /// **'证书与私钥都不能为空'**
  String get desktopEncryptedCertImportInvalid;

  /// No description provided for @desktopEncryptedExtrasTitle.
  ///
  /// In zh, this message translates to:
  /// **'发现与代理'**
  String get desktopEncryptedExtrasTitle;

  /// No description provided for @desktopEncryptedExtrasBody.
  ///
  /// In zh, this message translates to:
  /// **'客户端自动发现、反向代理信任与移动端描述文件'**
  String get desktopEncryptedExtrasBody;

  /// No description provided for @desktopEncryptedDdrTitle.
  ///
  /// In zh, this message translates to:
  /// **'指定解析器发现（DDR）'**
  String get desktopEncryptedDdrTitle;

  /// No description provided for @desktopEncryptedDdrBody.
  ///
  /// In zh, this message translates to:
  /// **'应答 _dns.resolver.arpa 探测，让终端自动发现本机的加密解析入口。'**
  String get desktopEncryptedDdrBody;

  /// No description provided for @desktopEncryptedDdrSelfSignedWarning.
  ///
  /// In zh, this message translates to:
  /// **'当前是自签证书：终端若未预先信任它，开启 DDR 会直接失去 DNS 解析。'**
  String get desktopEncryptedDdrSelfSignedWarning;

  /// No description provided for @desktopEncryptedDdrConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认开启 DDR？'**
  String get desktopEncryptedDdrConfirmTitle;

  /// No description provided for @desktopEncryptedDdrConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'DDR 会让客户端自动切换解析入口；证书不被信任时，这一步等于让客户端失去 DNS。'**
  String get desktopEncryptedDdrConfirmBody;

  /// No description provided for @desktopEncryptedDdrConfirm.
  ///
  /// In zh, this message translates to:
  /// **'仍要开启'**
  String get desktopEncryptedDdrConfirm;

  /// No description provided for @desktopEncryptedDdrOn.
  ///
  /// In zh, this message translates to:
  /// **'DDR 已开启'**
  String get desktopEncryptedDdrOn;

  /// No description provided for @desktopEncryptedDdrOff.
  ///
  /// In zh, this message translates to:
  /// **'DDR 已关闭'**
  String get desktopEncryptedDdrOff;

  /// No description provided for @desktopEncryptedProxyTitle.
  ///
  /// In zh, this message translates to:
  /// **'反向代理透传'**
  String get desktopEncryptedProxyTitle;

  /// No description provided for @desktopEncryptedProxyBody.
  ///
  /// In zh, this message translates to:
  /// **'仅当 DoH 确实位于自己掌握的反向代理之后才开启；开启后会采信转发头。'**
  String get desktopEncryptedProxyBody;

  /// No description provided for @desktopEncryptedProxyUnrestricted.
  ///
  /// In zh, this message translates to:
  /// **'可信来源包含 0.0.0.0/0 或 ::/0：任何人都能伪造来源地址。'**
  String get desktopEncryptedProxyUnrestricted;

  /// No description provided for @desktopEncryptedProxyOn.
  ///
  /// In zh, this message translates to:
  /// **'反向代理透传已开启'**
  String get desktopEncryptedProxyOn;

  /// No description provided for @desktopEncryptedProxyOff.
  ///
  /// In zh, this message translates to:
  /// **'反向代理透传已关闭'**
  String get desktopEncryptedProxyOff;

  /// No description provided for @desktopEncryptedProxySources.
  ///
  /// In zh, this message translates to:
  /// **'可信代理来源（每行一个 IP 或 CIDR）'**
  String get desktopEncryptedProxySources;

  /// No description provided for @desktopEncryptedProxyHeader.
  ///
  /// In zh, this message translates to:
  /// **'自定义转发头（留空则依次尝试 X-Forwarded-For 与 X-Real-IP）'**
  String get desktopEncryptedProxyHeader;

  /// No description provided for @desktopEncryptedProxySave.
  ///
  /// In zh, this message translates to:
  /// **'保存代理配置'**
  String get desktopEncryptedProxySave;

  /// No description provided for @desktopEncryptedProxySaved.
  ///
  /// In zh, this message translates to:
  /// **'反向代理配置已保存'**
  String get desktopEncryptedProxySaved;

  /// No description provided for @desktopEncryptedMobileConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'移动端描述文件'**
  String get desktopEncryptedMobileConfigTitle;

  /// No description provided for @desktopEncryptedMobileConfigBody.
  ///
  /// In zh, this message translates to:
  /// **'在设备上打开该链接即可安装包含本机加密 DNS 的描述文件。'**
  String get desktopEncryptedMobileConfigBody;

  /// No description provided for @desktopEncryptedMobileConfigOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开描述文件'**
  String get desktopEncryptedMobileConfigOpen;

  /// No description provided for @desktopEncryptedOpenUrl.
  ///
  /// In zh, this message translates to:
  /// **'在浏览器中打开'**
  String get desktopEncryptedOpenUrl;

  /// No description provided for @desktopTrafficPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'设备与客户端'**
  String get desktopTrafficPageTitle;

  /// No description provided for @desktopTrafficRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新设备与访问控制'**
  String get desktopTrafficRefresh;

  /// No description provided for @desktopTrafficLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到设备与访问控制状态'**
  String get desktopTrafficLoadFailed;

  /// No description provided for @desktopTrafficSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopTrafficSaveFailed(String message);

  /// No description provided for @desktopTrafficClientsTitle.
  ///
  /// In zh, this message translates to:
  /// **'已识别的局域网客户端'**
  String get desktopTrafficClientsTitle;

  /// No description provided for @desktopTrafficClientsBody.
  ///
  /// In zh, this message translates to:
  /// **'通过 rDNS 或自定义别名识别发起查询的设备'**
  String get desktopTrafficClientsBody;

  /// No description provided for @desktopTrafficClientCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个活跃设备'**
  String desktopTrafficClientCount(int count);

  /// No description provided for @desktopTrafficClientsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂未识别到来自外部或局域网的 DNS 查询设备。'**
  String get desktopTrafficClientsEmpty;

  /// No description provided for @desktopTrafficClientUnnamed.
  ///
  /// In zh, this message translates to:
  /// **'未设置（未知设备）'**
  String get desktopTrafficClientUnnamed;

  /// No description provided for @desktopTrafficClientQueries.
  ///
  /// In zh, this message translates to:
  /// **'累计查询 {count} 次'**
  String desktopTrafficClientQueries(int count);

  /// No description provided for @desktopTrafficClientNever.
  ///
  /// In zh, this message translates to:
  /// **'最近活跃：从未'**
  String get desktopTrafficClientNever;

  /// No description provided for @desktopTrafficClientLastSeen.
  ///
  /// In zh, this message translates to:
  /// **'最近活跃 {time}'**
  String desktopTrafficClientLastSeen(String time);

  /// No description provided for @desktopTrafficStateBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已阻断'**
  String get desktopTrafficStateBlocked;

  /// No description provided for @desktopTrafficStateAllowed.
  ///
  /// In zh, this message translates to:
  /// **'白名单'**
  String get desktopTrafficStateAllowed;

  /// No description provided for @desktopTrafficStateNotAllowed.
  ///
  /// In zh, this message translates to:
  /// **'未在白名单'**
  String get desktopTrafficStateNotAllowed;

  /// No description provided for @desktopTrafficStateOpen.
  ///
  /// In zh, this message translates to:
  /// **'正常放行'**
  String get desktopTrafficStateOpen;

  /// No description provided for @desktopTrafficAlias.
  ///
  /// In zh, this message translates to:
  /// **'别名'**
  String get desktopTrafficAlias;

  /// No description provided for @desktopTrafficAliasTitle.
  ///
  /// In zh, this message translates to:
  /// **'配置客户端设备别名'**
  String get desktopTrafficAliasTitle;

  /// No description provided for @desktopTrafficAliasField.
  ///
  /// In zh, this message translates to:
  /// **'自定义友好设备名称'**
  String get desktopTrafficAliasField;

  /// No description provided for @desktopTrafficAliasHint.
  ///
  /// In zh, this message translates to:
  /// **'如 客厅电视、工作用笔记本、NAS 存储'**
  String get desktopTrafficAliasHint;

  /// No description provided for @desktopTrafficAliasBody.
  ///
  /// In zh, this message translates to:
  /// **'留空保存将清除自定义别名。'**
  String get desktopTrafficAliasBody;

  /// No description provided for @desktopTrafficAliasSave.
  ///
  /// In zh, this message translates to:
  /// **'保存别名'**
  String get desktopTrafficAliasSave;

  /// No description provided for @desktopTrafficAliasSaved.
  ///
  /// In zh, this message translates to:
  /// **'客户端 [{ip}] 别名已更新'**
  String desktopTrafficAliasSaved(String ip);

  /// No description provided for @desktopTrafficAliasCleared.
  ///
  /// In zh, this message translates to:
  /// **'客户端 [{ip}] 别名已清除'**
  String desktopTrafficAliasCleared(String ip);

  /// No description provided for @desktopTrafficAllowedAdd.
  ///
  /// In zh, this message translates to:
  /// **'白名单'**
  String get desktopTrafficAllowedAdd;

  /// No description provided for @desktopTrafficAllowedRemove.
  ///
  /// In zh, this message translates to:
  /// **'已放行'**
  String get desktopTrafficAllowedRemove;

  /// No description provided for @desktopTrafficAllowedAdded.
  ///
  /// In zh, this message translates to:
  /// **'客户端 [{ip}] 已加入白名单'**
  String desktopTrafficAllowedAdded(String ip);

  /// No description provided for @desktopTrafficAllowedRemoved.
  ///
  /// In zh, this message translates to:
  /// **'客户端 [{ip}] 已移出白名单'**
  String desktopTrafficAllowedRemoved(String ip);

  /// No description provided for @desktopTrafficBlockedAdd.
  ///
  /// In zh, this message translates to:
  /// **'阻断'**
  String get desktopTrafficBlockedAdd;

  /// No description provided for @desktopTrafficBlockedRemove.
  ///
  /// In zh, this message translates to:
  /// **'已阻断'**
  String get desktopTrafficBlockedRemove;

  /// No description provided for @desktopTrafficBlockedAdded.
  ///
  /// In zh, this message translates to:
  /// **'客户端 [{ip}] 已加入黑名单阻断'**
  String desktopTrafficBlockedAdded(String ip);

  /// No description provided for @desktopTrafficBlockedRemoved.
  ///
  /// In zh, this message translates to:
  /// **'客户端 [{ip}] 已移出黑名单'**
  String desktopTrafficBlockedRemoved(String ip);

  /// No description provided for @desktopTrafficAccessTitle.
  ///
  /// In zh, this message translates to:
  /// **'客户端访问控制（ACL）'**
  String get desktopTrafficAccessTitle;

  /// No description provided for @desktopTrafficAccessBody.
  ///
  /// In zh, this message translates to:
  /// **'限制特定 IP 或 CIDR 网段设备的 DNS 查询权限'**
  String get desktopTrafficAccessBody;

  /// No description provided for @desktopTrafficAccessOpen.
  ///
  /// In zh, this message translates to:
  /// **'未限制'**
  String get desktopTrafficAccessOpen;

  /// No description provided for @desktopTrafficAccessAllowOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅白名单'**
  String get desktopTrafficAccessAllowOnly;

  /// No description provided for @desktopTrafficAccessAllowed.
  ///
  /// In zh, this message translates to:
  /// **'允许访问白名单'**
  String get desktopTrafficAccessAllowed;

  /// No description provided for @desktopTrafficAccessAllowedHint.
  ///
  /// In zh, this message translates to:
  /// **'例如: 192.168.1.0/24 或 192.168.1.50'**
  String get desktopTrafficAccessAllowedHint;

  /// No description provided for @desktopTrafficAccessAllowedBody.
  ///
  /// In zh, this message translates to:
  /// **'若填写，则仅允许名单内的客户端解析；留空表示不限制。每行一个 IP 或 CIDR。'**
  String get desktopTrafficAccessAllowedBody;

  /// No description provided for @desktopTrafficAccessBlocked.
  ///
  /// In zh, this message translates to:
  /// **'显式阻断黑名单'**
  String get desktopTrafficAccessBlocked;

  /// No description provided for @desktopTrafficAccessBlockedHint.
  ///
  /// In zh, this message translates to:
  /// **'例如: 192.168.1.199 或 10.0.0.0/8'**
  String get desktopTrafficAccessBlockedHint;

  /// No description provided for @desktopTrafficAccessBlockedBody.
  ///
  /// In zh, this message translates to:
  /// **'命中该名单的客户端将被直接拒绝解析请求。每行一个 IP 或 CIDR。'**
  String get desktopTrafficAccessBlockedBody;

  /// No description provided for @desktopTrafficAccessSave.
  ///
  /// In zh, this message translates to:
  /// **'保存名单'**
  String get desktopTrafficAccessSave;

  /// No description provided for @desktopTrafficAccessReset.
  ///
  /// In zh, this message translates to:
  /// **'撤销修改'**
  String get desktopTrafficAccessReset;

  /// No description provided for @desktopTrafficAccessSaved.
  ///
  /// In zh, this message translates to:
  /// **'客户端黑白名单已保存'**
  String get desktopTrafficAccessSaved;

  /// No description provided for @desktopTrafficRateLimitTitle.
  ///
  /// In zh, this message translates to:
  /// **'客户端请求速率限制'**
  String get desktopTrafficRateLimitTitle;

  /// No description provided for @desktopTrafficRateLimitBody.
  ///
  /// In zh, this message translates to:
  /// **'基于令牌桶限流，防范局域网 DoS 泛洪与 DNS 放大攻击'**
  String get desktopTrafficRateLimitBody;

  /// No description provided for @desktopTrafficRateLimitOn.
  ///
  /// In zh, this message translates to:
  /// **'限流生效中'**
  String get desktopTrafficRateLimitOn;

  /// No description provided for @desktopTrafficRateLimitOff.
  ///
  /// In zh, this message translates to:
  /// **'限流已停用'**
  String get desktopTrafficRateLimitOff;

  /// No description provided for @desktopTrafficRateLimitSavedOn.
  ///
  /// In zh, this message translates to:
  /// **'速率限制已开启'**
  String get desktopTrafficRateLimitSavedOn;

  /// No description provided for @desktopTrafficRateLimitSavedOff.
  ///
  /// In zh, this message translates to:
  /// **'速率限制已关闭'**
  String get desktopTrafficRateLimitSavedOff;

  /// No description provided for @desktopTrafficRate.
  ///
  /// In zh, this message translates to:
  /// **'速率（令牌/秒）'**
  String get desktopTrafficRate;

  /// No description provided for @desktopTrafficBurst.
  ///
  /// In zh, this message translates to:
  /// **'突发容量（次）'**
  String get desktopTrafficBurst;

  /// No description provided for @desktopTrafficIpv4Prefix.
  ///
  /// In zh, this message translates to:
  /// **'IPv4 聚合掩码'**
  String get desktopTrafficIpv4Prefix;

  /// No description provided for @desktopTrafficIpv6Prefix.
  ///
  /// In zh, this message translates to:
  /// **'IPv6 聚合掩码'**
  String get desktopTrafficIpv6Prefix;

  /// No description provided for @desktopTrafficPrefixBody.
  ///
  /// In zh, this message translates to:
  /// **'单 IP 为 32 / 128；局域网可按需聚合，如 24 / 64。'**
  String get desktopTrafficPrefixBody;

  /// No description provided for @desktopTrafficExempt.
  ///
  /// In zh, this message translates to:
  /// **'豁免 IP / 网段'**
  String get desktopTrafficExempt;

  /// No description provided for @desktopTrafficExemptBody.
  ///
  /// In zh, this message translates to:
  /// **'回环与受信任网段不计入限流统计。'**
  String get desktopTrafficExemptBody;

  /// No description provided for @desktopTrafficRateLimitSave.
  ///
  /// In zh, this message translates to:
  /// **'保存速率限制'**
  String get desktopTrafficRateLimitSave;

  /// No description provided for @desktopTrafficRateInvalid.
  ///
  /// In zh, this message translates to:
  /// **'速率与突发需大于 0，掩码需在 1–32（IPv4）与 1–128（IPv6）之间'**
  String get desktopTrafficRateInvalid;

  /// No description provided for @desktopGroupsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'客户端分组'**
  String get desktopGroupsPageTitle;

  /// No description provided for @desktopGroupsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新客户端分组'**
  String get desktopGroupsRefresh;

  /// No description provided for @desktopGroupsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到客户端分组配置'**
  String get desktopGroupsLoadFailed;

  /// No description provided for @desktopGroupsTitle.
  ///
  /// In zh, this message translates to:
  /// **'客户端分组 · 精细策略'**
  String get desktopGroupsTitle;

  /// No description provided for @desktopGroupsBody.
  ///
  /// In zh, this message translates to:
  /// **'为不同设备组绑定专属订阅规则集与拦截方式，实现精细化管控'**
  String get desktopGroupsBody;

  /// No description provided for @desktopGroupsCount.
  ///
  /// In zh, this message translates to:
  /// **'{enabled} / {total} 个启用分组'**
  String desktopGroupsCount(int enabled, int total);

  /// No description provided for @desktopGroupsOn.
  ///
  /// In zh, this message translates to:
  /// **'分组生效中'**
  String get desktopGroupsOn;

  /// No description provided for @desktopGroupsOff.
  ///
  /// In zh, this message translates to:
  /// **'分组未启用'**
  String get desktopGroupsOff;

  /// No description provided for @desktopGroupsSave.
  ///
  /// In zh, this message translates to:
  /// **'保存策略'**
  String get desktopGroupsSave;

  /// No description provided for @desktopGroupsSaved.
  ///
  /// In zh, this message translates to:
  /// **'客户端分组策略已保存并生效'**
  String get desktopGroupsSaved;

  /// No description provided for @desktopGroupsMaster.
  ///
  /// In zh, this message translates to:
  /// **'启用客户端分组'**
  String get desktopGroupsMaster;

  /// No description provided for @desktopGroupsMasterBody.
  ///
  /// In zh, this message translates to:
  /// **'关闭时所有客户端统一使用全局规则；开启后按网段最长前缀匹配分组。'**
  String get desktopGroupsMasterBody;

  /// No description provided for @desktopGroupsAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增客户端分组'**
  String get desktopGroupsAdd;

  /// No description provided for @desktopGroupsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置任何分组。未命中分组的客户端将统一使用全局规则（默认组）。'**
  String get desktopGroupsEmpty;

  /// No description provided for @desktopGroupsFooter.
  ///
  /// In zh, this message translates to:
  /// **'采用最长前缀匹配：更具体的网段（如 /24）优先于更宽泛的网段（如 /16）。'**
  String get desktopGroupsFooter;

  /// No description provided for @desktopGroupsOpen.
  ///
  /// In zh, this message translates to:
  /// **'客户端分组'**
  String get desktopGroupsOpen;

  /// No description provided for @desktopGroupsName.
  ///
  /// In zh, this message translates to:
  /// **'分组名称'**
  String get desktopGroupsName;

  /// No description provided for @desktopGroupsEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用该分组'**
  String get desktopGroupsEnabled;

  /// No description provided for @desktopGroupsDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除该分组'**
  String get desktopGroupsDelete;

  /// No description provided for @desktopGroupsDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除客户端分组'**
  String get desktopGroupsDeleteTitle;

  /// No description provided for @desktopGroupsDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除该客户端分组吗？保存后不再生效。'**
  String get desktopGroupsDeleteBody;

  /// No description provided for @desktopGroupsMembers.
  ///
  /// In zh, this message translates to:
  /// **'成员 IP / 网段'**
  String get desktopGroupsMembers;

  /// No description provided for @desktopGroupsMembersHint.
  ///
  /// In zh, this message translates to:
  /// **'例如:\n192.168.1.0/24\n10.0.0.7\nfd00::/8'**
  String get desktopGroupsMembersHint;

  /// No description provided for @desktopGroupsMembersBody.
  ///
  /// In zh, this message translates to:
  /// **'每行一个 IP 或 CIDR，支持 IPv4/IPv6。'**
  String get desktopGroupsMembersBody;

  /// No description provided for @desktopGroupsBlockMode.
  ///
  /// In zh, this message translates to:
  /// **'拦截应答方式'**
  String get desktopGroupsBlockMode;

  /// No description provided for @desktopGroupsModeInherit.
  ///
  /// In zh, this message translates to:
  /// **'继承全局'**
  String get desktopGroupsModeInherit;

  /// No description provided for @desktopGroupsModeNullIp.
  ///
  /// In zh, this message translates to:
  /// **'空 IP（0.0.0.0 / ::）'**
  String get desktopGroupsModeNullIp;

  /// No description provided for @desktopGroupsModeNxdomain.
  ///
  /// In zh, this message translates to:
  /// **'NXDOMAIN（域名不存在）'**
  String get desktopGroupsModeNxdomain;

  /// No description provided for @desktopGroupsModeRefused.
  ///
  /// In zh, this message translates to:
  /// **'REFUSED（拒绝应答）'**
  String get desktopGroupsModeRefused;

  /// No description provided for @desktopGroupsAllowlistOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅白名单模式'**
  String get desktopGroupsAllowlistOnly;

  /// No description provided for @desktopGroupsAllowlistOnlyBody.
  ///
  /// In zh, this message translates to:
  /// **'开启后该组仅放行命中放行规则（@@）的查询，其余一律阻断'**
  String get desktopGroupsAllowlistOnlyBody;

  /// No description provided for @desktopGroupsSchedule.
  ///
  /// In zh, this message translates to:
  /// **'组级时间计划'**
  String get desktopGroupsSchedule;

  /// No description provided for @desktopGroupsScheduleBody.
  ///
  /// In zh, this message translates to:
  /// **'开启后该组按自身窗口拦截；关闭则继承全局时间计划'**
  String get desktopGroupsScheduleBody;

  /// No description provided for @desktopGroupsRuleLists.
  ///
  /// In zh, this message translates to:
  /// **'绑定的订阅规则集'**
  String get desktopGroupsRuleLists;

  /// No description provided for @desktopGroupsInheritAll.
  ///
  /// In zh, this message translates to:
  /// **'继承全部'**
  String get desktopGroupsInheritAll;

  /// No description provided for @desktopGroupsNoRuleLists.
  ///
  /// In zh, this message translates to:
  /// **'当前无可用订阅列表，该组将仅应用自定义规则。'**
  String get desktopGroupsNoRuleLists;

  /// No description provided for @desktopGroupsRuleListsInherited.
  ///
  /// In zh, this message translates to:
  /// **'未勾选任何列表 → 继承全部订阅规则。'**
  String get desktopGroupsRuleListsInherited;

  /// No description provided for @desktopGroupsRuleListsSelected.
  ///
  /// In zh, this message translates to:
  /// **'该组只应用所选订阅列表。'**
  String get desktopGroupsRuleListsSelected;

  /// No description provided for @desktopGroupsUpstreams.
  ///
  /// In zh, this message translates to:
  /// **'专属上游 DNS'**
  String get desktopGroupsUpstreams;

  /// No description provided for @desktopGroupsInheritChain.
  ///
  /// In zh, this message translates to:
  /// **'沿用主链路'**
  String get desktopGroupsInheritChain;

  /// No description provided for @desktopGroupsNoUpstreams.
  ///
  /// In zh, this message translates to:
  /// **'当前无可选上游，该组将沿用主链路。'**
  String get desktopGroupsNoUpstreams;

  /// No description provided for @desktopGroupsUpstreamsInherited.
  ///
  /// In zh, this message translates to:
  /// **'未勾选任何上游 → 沿用主链路调度策略。'**
  String get desktopGroupsUpstreamsInherited;

  /// No description provided for @desktopGroupsUpstreamsSelected.
  ///
  /// In zh, this message translates to:
  /// **'该组的查询直接由所选上游解析，不参与全局回退链。'**
  String get desktopGroupsUpstreamsSelected;

  /// No description provided for @desktopGroupsNewName.
  ///
  /// In zh, this message translates to:
  /// **'新分组 {index}'**
  String desktopGroupsNewName(int index);

  /// No description provided for @desktopGroupsListEnabled.
  ///
  /// In zh, this message translates to:
  /// **'该订阅已启用'**
  String get desktopGroupsListEnabled;

  /// No description provided for @desktopGroupsListDisabled.
  ///
  /// In zh, this message translates to:
  /// **'该订阅已停用'**
  String get desktopGroupsListDisabled;

  /// No description provided for @desktopToolsPortTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络诊断与修复'**
  String get desktopToolsPortTitle;

  /// No description provided for @desktopToolsPortBody.
  ///
  /// In zh, this message translates to:
  /// **'排查 53 端口被 ICS 共享或 systemd-resolved stub 占用导致无法启动的问题'**
  String get desktopToolsPortBody;

  /// No description provided for @desktopToolsPortIdle.
  ///
  /// In zh, this message translates to:
  /// **'尚未检测。点本卡片右上角的检索按钮运行一次端口探测。'**
  String get desktopToolsPortIdle;

  /// No description provided for @desktopToolsPortOk.
  ///
  /// In zh, this message translates to:
  /// **'端口正常可用'**
  String get desktopToolsPortOk;

  /// No description provided for @desktopToolsPortConflict.
  ///
  /// In zh, this message translates to:
  /// **'检测到端口冲突'**
  String get desktopToolsPortConflict;

  /// No description provided for @desktopToolsCheck.
  ///
  /// In zh, this message translates to:
  /// **'检测端口'**
  String get desktopToolsCheck;

  /// No description provided for @desktopToolsFix.
  ///
  /// In zh, this message translates to:
  /// **'一键修复端口占用'**
  String get desktopToolsFix;

  /// No description provided for @desktopToolsFixTitle.
  ///
  /// In zh, this message translates to:
  /// **'修复端口占用？'**
  String get desktopToolsFixTitle;

  /// No description provided for @desktopToolsFixBody.
  ///
  /// In zh, this message translates to:
  /// **'将停止占用 53 端口的系统监听（Windows ICS 共享 / systemd-resolved stub），不会启动或重启 DNS 服务。'**
  String get desktopToolsFixBody;

  /// No description provided for @desktopToolsFixed.
  ///
  /// In zh, this message translates to:
  /// **'端口冲突已修复'**
  String get desktopToolsFixed;

  /// No description provided for @desktopToolsFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopToolsFailed(String message);

  /// No description provided for @desktopToolsSystemListener.
  ///
  /// In zh, this message translates to:
  /// **'系统占用'**
  String get desktopToolsSystemListener;

  /// No description provided for @desktopToolsSelfListener.
  ///
  /// In zh, this message translates to:
  /// **'谛听自身'**
  String get desktopToolsSelfListener;

  /// No description provided for @desktopToolsConflictOwner.
  ///
  /// In zh, this message translates to:
  /// **'{process} · PID {pid} · {address}'**
  String desktopToolsConflictOwner(String process, int pid, String address);

  /// No description provided for @desktopToolsConflictService.
  ///
  /// In zh, this message translates to:
  /// **'服务：{service}'**
  String desktopToolsConflictService(String service);

  /// No description provided for @desktopToolsPortFooter.
  ///
  /// In zh, this message translates to:
  /// **'探测只临时占用端口以确认可用性；诊断文本与处置建议来自系统探测本身。'**
  String get desktopToolsPortFooter;

  /// No description provided for @desktopToolsRulePageTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则检测'**
  String get desktopToolsRulePageTitle;

  /// No description provided for @desktopHubDiagnoseSection.
  ///
  /// In zh, this message translates to:
  /// **'诊断与恢复'**
  String get desktopHubDiagnoseSection;

  /// No description provided for @desktopToolsRuleEntryBody.
  ///
  /// In zh, this message translates to:
  /// **'模拟一次查询，查看命中规则与处置结论'**
  String get desktopToolsRuleEntryBody;

  /// No description provided for @desktopHubQueryLog.
  ///
  /// In zh, this message translates to:
  /// **'查询日志'**
  String get desktopHubQueryLog;

  /// No description provided for @desktopHubQueryLogBody.
  ///
  /// In zh, this message translates to:
  /// **'实时查询流、历史记录检索与日志保留策略'**
  String get desktopHubQueryLogBody;

  /// No description provided for @desktopQueryLogPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'查询日志'**
  String get desktopQueryLogPageTitle;

  /// No description provided for @desktopToolsRuleInputTitle.
  ///
  /// In zh, this message translates to:
  /// **'网址拦截模拟测试'**
  String get desktopToolsRuleInputTitle;

  /// No description provided for @desktopToolsRuleInputBody.
  ///
  /// In zh, this message translates to:
  /// **'输入域名快速检测是否命中过滤拦截规则'**
  String get desktopToolsRuleInputBody;

  /// No description provided for @desktopToolsRuleDomain.
  ///
  /// In zh, this message translates to:
  /// **'测试目标域名'**
  String get desktopToolsRuleDomain;

  /// No description provided for @desktopToolsRuleDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'例如: ad.example.com 或 tracker.domain.com'**
  String get desktopToolsRuleDomainHint;

  /// No description provided for @desktopToolsRuleQtype.
  ///
  /// In zh, this message translates to:
  /// **'DNS 记录类型'**
  String get desktopToolsRuleQtype;

  /// No description provided for @desktopToolsRuleQtypeOption.
  ///
  /// In zh, this message translates to:
  /// **'{type} 记录'**
  String desktopToolsRuleQtypeOption(String type);

  /// No description provided for @desktopToolsRuleExamples.
  ///
  /// In zh, this message translates to:
  /// **'快速填充示例：'**
  String get desktopToolsRuleExamples;

  /// No description provided for @desktopToolsRuleRun.
  ///
  /// In zh, this message translates to:
  /// **'立即模拟检测'**
  String get desktopToolsRuleRun;

  /// No description provided for @desktopToolsRuleRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在执行规则匹配…'**
  String get desktopToolsRuleRunning;

  /// No description provided for @desktopToolsRuleVerdictTitle.
  ///
  /// In zh, this message translates to:
  /// **'规则诊断与拦截判定'**
  String get desktopToolsRuleVerdictTitle;

  /// No description provided for @desktopToolsRuleVerdictBody.
  ///
  /// In zh, this message translates to:
  /// **'规则匹配结果、所属规则库与响应动作'**
  String get desktopToolsRuleVerdictBody;

  /// No description provided for @desktopToolsRuleIdle.
  ///
  /// In zh, this message translates to:
  /// **'在上方输入域名并点击「立即模拟检测」以查看规则判定明细'**
  String get desktopToolsRuleIdle;

  /// No description provided for @desktopToolsRuleBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已拦截（阻断访问）'**
  String get desktopToolsRuleBlocked;

  /// No description provided for @desktopToolsRuleRewritten.
  ///
  /// In zh, this message translates to:
  /// **'已重写（{code}）'**
  String desktopToolsRuleRewritten(String code);

  /// No description provided for @desktopToolsRuleAllowed.
  ///
  /// In zh, this message translates to:
  /// **'已放行（信任名单）'**
  String get desktopToolsRuleAllowed;

  /// No description provided for @desktopToolsRulePassed.
  ///
  /// In zh, this message translates to:
  /// **'未命中（正常解析）'**
  String get desktopToolsRulePassed;

  /// No description provided for @desktopToolsRuleMatched.
  ///
  /// In zh, this message translates to:
  /// **'命中的防护规则'**
  String get desktopToolsRuleMatched;

  /// No description provided for @desktopToolsRuleNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'未命中任何规则'**
  String get desktopToolsRuleNoMatch;

  /// No description provided for @desktopToolsRuleList.
  ///
  /// In zh, this message translates to:
  /// **'来源规则库'**
  String get desktopToolsRuleList;

  /// No description provided for @desktopToolsRuleNoList.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get desktopToolsRuleNoList;

  /// No description provided for @desktopToolsRuleReason.
  ///
  /// In zh, this message translates to:
  /// **'处置判定原因'**
  String get desktopToolsRuleReason;

  /// No description provided for @desktopToolsRuleNoReason.
  ///
  /// In zh, this message translates to:
  /// **'正常直连解析'**
  String get desktopToolsRuleNoReason;

  /// No description provided for @desktopToolsRuleRewrite.
  ///
  /// In zh, this message translates to:
  /// **'\$dnsrewrite 应答：{code}'**
  String desktopToolsRuleRewrite(String code);

  /// No description provided for @desktopToolsRuleRewriteEmpty.
  ///
  /// In zh, this message translates to:
  /// **'不返回任何记录（权威 NODATA）'**
  String get desktopToolsRuleRewriteEmpty;

  /// No description provided for @desktopToolsRuleFooter.
  ///
  /// In zh, this message translates to:
  /// **'支持 AdGuard、Hosts 及自定义规则即时模拟测试。'**
  String get desktopToolsRuleFooter;

  /// No description provided for @desktopToolsRuleFailed.
  ///
  /// In zh, this message translates to:
  /// **'检测失败：{message}'**
  String desktopToolsRuleFailed(String message);

  /// No description provided for @desktopHubAppSection.
  ///
  /// In zh, this message translates to:
  /// **'应用与服务'**
  String get desktopHubAppSection;

  /// No description provided for @desktopAboutProjectSection.
  ///
  /// In zh, this message translates to:
  /// **'项目与链接'**
  String get desktopAboutProjectSection;

  /// No description provided for @desktopAboutDisclaimerSection.
  ///
  /// In zh, this message translates to:
  /// **'软件说明与免责声明'**
  String get desktopAboutDisclaimerSection;

  /// No description provided for @desktopSettingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观主题'**
  String get desktopSettingsAppearance;

  /// No description provided for @desktopSettingsAppearanceEntryBody.
  ///
  /// In zh, this message translates to:
  /// **'配色方案与深浅模式，即时预览'**
  String get desktopSettingsAppearanceEntryBody;

  /// No description provided for @desktopSettingsAppearanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'外观与界面主题'**
  String get desktopSettingsAppearanceTitle;

  /// No description provided for @desktopSettingsAppearanceBody.
  ///
  /// In zh, this message translates to:
  /// **'多套配色方案与深浅模式自由切换，全局即时适配'**
  String get desktopSettingsAppearanceBody;

  /// No description provided for @desktopSettingsPalette.
  ///
  /// In zh, this message translates to:
  /// **'主题配色方案'**
  String get desktopSettingsPalette;

  /// No description provided for @desktopSettingsPaletteBody.
  ///
  /// In zh, this message translates to:
  /// **'选择符合个人偏好的视觉设计体系，所有界面元素即时协调匹配'**
  String get desktopSettingsPaletteBody;

  /// No description provided for @desktopSettingsMode.
  ///
  /// In zh, this message translates to:
  /// **'深浅模式'**
  String get desktopSettingsMode;

  /// No description provided for @desktopSettingsModeBody.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统时按系统深浅偏好自动同步'**
  String get desktopSettingsModeBody;

  /// No description provided for @desktopSettingsAppearanceFooter.
  ///
  /// In zh, this message translates to:
  /// **'外观偏好与移动端共用同一组键，切换后重启仍生效。'**
  String get desktopSettingsAppearanceFooter;

  /// No description provided for @desktopSettingsPreview.
  ///
  /// In zh, this message translates to:
  /// **'桌面预览'**
  String get desktopSettingsPreview;

  /// No description provided for @desktopSettingsPreviewBody.
  ///
  /// In zh, this message translates to:
  /// **'侧栏、工具栏与卡片都按当前配色和深浅模式渲染，所见即所得。'**
  String get desktopSettingsPreviewBody;

  /// No description provided for @desktopSettingsSystemResolved.
  ///
  /// In zh, this message translates to:
  /// **'{mode}（跟随系统）'**
  String desktopSettingsSystemResolved(String mode);

  /// No description provided for @desktopServicePageTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务与连接'**
  String get desktopServicePageTitle;

  /// No description provided for @desktopServiceEntryBody.
  ///
  /// In zh, this message translates to:
  /// **'后台连接设置、核心服务与开机自启状态'**
  String get desktopServiceEntryBody;

  /// No description provided for @desktopServiceConnectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台服务连接设置'**
  String get desktopServiceConnectionTitle;

  /// No description provided for @desktopServiceConnectionBody.
  ///
  /// In zh, this message translates to:
  /// **'前端客户端与核心服务的通信管道'**
  String get desktopServiceConnectionBody;

  /// No description provided for @desktopServiceConnectionFooter.
  ///
  /// In zh, this message translates to:
  /// **'保存后立即用新地址重建连接；「测试连接」检查当前服务是否应答。'**
  String get desktopServiceConnectionFooter;

  /// No description provided for @desktopServiceHost.
  ///
  /// In zh, this message translates to:
  /// **'服务地址（IP 或主机名）'**
  String get desktopServiceHost;

  /// No description provided for @desktopServicePort.
  ///
  /// In zh, this message translates to:
  /// **'通信端口'**
  String get desktopServicePort;

  /// No description provided for @desktopServiceToken.
  ///
  /// In zh, this message translates to:
  /// **'访问密钥 / 授权 Token（可选）'**
  String get desktopServiceToken;

  /// No description provided for @desktopServiceTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'留空表示本机无需密码'**
  String get desktopServiceTokenHint;

  /// No description provided for @desktopServiceTest.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get desktopServiceTest;

  /// No description provided for @desktopServiceSave.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get desktopServiceSave;

  /// No description provided for @desktopServiceSaved.
  ///
  /// In zh, this message translates to:
  /// **'连接设置已保存'**
  String get desktopServiceSaved;

  /// No description provided for @desktopServiceReachable.
  ///
  /// In zh, this message translates to:
  /// **'通信正常'**
  String get desktopServiceReachable;

  /// No description provided for @desktopServiceUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'连接异常'**
  String get desktopServiceUnreachable;

  /// No description provided for @desktopServiceConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置'**
  String get desktopServiceConfigured;

  /// No description provided for @desktopServiceAddressInvalid.
  ///
  /// In zh, this message translates to:
  /// **'服务地址不能为空，端口需为 1–65535 的整数'**
  String get desktopServiceAddressInvalid;

  /// No description provided for @desktopServiceCoreTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台核心服务'**
  String get desktopServiceCoreTitle;

  /// No description provided for @desktopServiceCoreBody.
  ///
  /// In zh, this message translates to:
  /// **'宿主机上负责 DNS 与拦截的核心服务状态'**
  String get desktopServiceCoreBody;

  /// No description provided for @desktopServiceCoreFooter.
  ///
  /// In zh, this message translates to:
  /// **'安装、启动与开机自启由宿主机托管，本页只读取并显示其真实状态。'**
  String get desktopServiceCoreFooter;

  /// No description provided for @desktopServiceState.
  ///
  /// In zh, this message translates to:
  /// **'服务状态'**
  String get desktopServiceState;

  /// No description provided for @desktopServiceAutoStartOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启'**
  String get desktopServiceAutoStartOn;

  /// No description provided for @desktopServiceAutoStartOff.
  ///
  /// In zh, this message translates to:
  /// **'未开启'**
  String get desktopServiceAutoStartOff;

  /// No description provided for @desktopServiceAutoStartUnknown.
  ///
  /// In zh, this message translates to:
  /// **'服务未上报'**
  String get desktopServiceAutoStartUnknown;

  /// No description provided for @desktopServiceRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get desktopServiceRunning;

  /// No description provided for @desktopServiceStopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get desktopServiceStopped;

  /// No description provided for @desktopServiceUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get desktopServiceUnknown;

  /// No description provided for @desktopServiceRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新核心服务状态'**
  String get desktopServiceRefresh;

  /// No description provided for @desktopLanWebPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'局域网控制台'**
  String get desktopLanWebPageTitle;

  /// No description provided for @desktopLanWebEntryBody.
  ///
  /// In zh, this message translates to:
  /// **'远程管理开关、访问地址、防火墙放行与管理员凭据'**
  String get desktopLanWebEntryBody;

  /// No description provided for @desktopHubClientAccess.
  ///
  /// In zh, this message translates to:
  /// **'客户端访问控制'**
  String get desktopHubClientAccess;

  /// No description provided for @desktopHubClientAccessBody.
  ///
  /// In zh, this message translates to:
  /// **'哪些局域网客户端可以解析，以及每个客户端的查询限速'**
  String get desktopHubClientAccessBody;

  /// No description provided for @desktopClientAccessPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'客户端访问控制'**
  String get desktopClientAccessPageTitle;

  /// No description provided for @desktopLanWebRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新局域网控制台状态'**
  String get desktopLanWebRefresh;

  /// No description provided for @desktopLanWebLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到局域网控制台状态'**
  String get desktopLanWebLoadFailed;

  /// No description provided for @desktopLanWebAccessTitle.
  ///
  /// In zh, this message translates to:
  /// **'放行与管理员凭据'**
  String get desktopLanWebAccessTitle;

  /// No description provided for @desktopLanWebAccessBody.
  ///
  /// In zh, this message translates to:
  /// **'防火墙放行规则与本控制台的登录账号，凭据只影响局域网访问'**
  String get desktopLanWebAccessBody;

  /// No description provided for @desktopLanWebTitle.
  ///
  /// In zh, this message translates to:
  /// **'局域网 Web 控制台'**
  String get desktopLanWebTitle;

  /// No description provided for @desktopLanWebOpen.
  ///
  /// In zh, this message translates to:
  /// **'对外开放中'**
  String get desktopLanWebOpen;

  /// No description provided for @desktopLanWebLocal.
  ///
  /// In zh, this message translates to:
  /// **'仅本地（127.0.0.1）'**
  String get desktopLanWebLocal;

  /// No description provided for @desktopLanWebEnabledBody.
  ///
  /// In zh, this message translates to:
  /// **'局域网内的手机或电脑可通过浏览器访问完整控制台进行远程管理。'**
  String get desktopLanWebEnabledBody;

  /// No description provided for @desktopLanWebDisabledBody.
  ///
  /// In zh, this message translates to:
  /// **'开启后，局域网内的手机或电脑可通过浏览器访问完整控制台，与桌面客户端共享核心数据与配置。'**
  String get desktopLanWebDisabledBody;

  /// No description provided for @desktopLanWebOn.
  ///
  /// In zh, this message translates to:
  /// **'局域网 Web 管理已开启'**
  String get desktopLanWebOn;

  /// No description provided for @desktopLanWebOff.
  ///
  /// In zh, this message translates to:
  /// **'局域网 Web 管理已关闭'**
  String get desktopLanWebOff;

  /// No description provided for @desktopLanWebFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopLanWebFailed(String message);

  /// No description provided for @desktopLanWebUrls.
  ///
  /// In zh, this message translates to:
  /// **'局域网访问网址（浏览器直连）'**
  String get desktopLanWebUrls;

  /// No description provided for @desktopLanWebNoUrls.
  ///
  /// In zh, this message translates to:
  /// **'未探测到可用的局域网网卡 IPv4 地址'**
  String get desktopLanWebNoUrls;

  /// No description provided for @desktopLanWebPort.
  ///
  /// In zh, this message translates to:
  /// **'Web 端口'**
  String get desktopLanWebPort;

  /// No description provided for @desktopLanWebSavePort.
  ///
  /// In zh, this message translates to:
  /// **'保存端口'**
  String get desktopLanWebSavePort;

  /// No description provided for @desktopLanWebPortInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的端口号（1–65535）'**
  String get desktopLanWebPortInvalid;

  /// No description provided for @desktopLanWebFirewall.
  ///
  /// In zh, this message translates to:
  /// **'放行防火墙入站规则'**
  String get desktopLanWebFirewall;

  /// No description provided for @desktopLanWebFirewallBody.
  ///
  /// In zh, this message translates to:
  /// **'为 Web 端口添加或清除系统防火墙放行规则'**
  String get desktopLanWebFirewallBody;

  /// No description provided for @desktopLanWebFirewallOn.
  ///
  /// In zh, this message translates to:
  /// **'已放行防火墙 Web 端口'**
  String get desktopLanWebFirewallOn;

  /// No description provided for @desktopLanWebFirewallOff.
  ///
  /// In zh, this message translates to:
  /// **'已清除防火墙 Web 端口规则'**
  String get desktopLanWebFirewallOff;

  /// No description provided for @desktopLanWebNoFirewall.
  ///
  /// In zh, this message translates to:
  /// **'系统未检测到防火墙管理器，端口本就对外开放，无需放行规则。'**
  String get desktopLanWebNoFirewall;

  /// No description provided for @desktopLanWebCredentials.
  ///
  /// In zh, this message translates to:
  /// **'控制台凭据'**
  String get desktopLanWebCredentials;

  /// No description provided for @desktopLanWebUser.
  ///
  /// In zh, this message translates to:
  /// **'管理员：{user}'**
  String desktopLanWebUser(String user);

  /// No description provided for @desktopLanWebNoUser.
  ///
  /// In zh, this message translates to:
  /// **'尚未设置管理员'**
  String get desktopLanWebNoUser;

  /// No description provided for @desktopLanWebProtected.
  ///
  /// In zh, this message translates to:
  /// **'密码保护已启用'**
  String get desktopLanWebProtected;

  /// No description provided for @desktopLanWebUnprotected.
  ///
  /// In zh, this message translates to:
  /// **'尚未初始化密码，首次进入需设置'**
  String get desktopLanWebUnprotected;

  /// No description provided for @desktopLanWebChangePassword.
  ///
  /// In zh, this message translates to:
  /// **'修改管理员密码'**
  String get desktopLanWebChangePassword;

  /// No description provided for @desktopLanWebSetPassword.
  ///
  /// In zh, this message translates to:
  /// **'设置初始密码'**
  String get desktopLanWebSetPassword;

  /// No description provided for @desktopLanWebPasswordSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get desktopLanWebPasswordSave;

  /// No description provided for @desktopLanWebPasswordSaved.
  ///
  /// In zh, this message translates to:
  /// **'管理员密码已保存'**
  String get desktopLanWebPasswordSaved;

  /// No description provided for @desktopLanWebChangeBody.
  ///
  /// In zh, this message translates to:
  /// **'修改 {user} 的密码，保存后已有外部会话将失效。'**
  String desktopLanWebChangeBody(String user);

  /// No description provided for @desktopLanWebSetupBody.
  ///
  /// In zh, this message translates to:
  /// **'为 {user} 设置初始密码，之后访问控制台需要登录。'**
  String desktopLanWebSetupBody(String user);

  /// No description provided for @desktopLanWebOldPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get desktopLanWebOldPassword;

  /// No description provided for @desktopLanWebNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'新密码'**
  String get desktopLanWebNewPassword;

  /// No description provided for @desktopLanWebConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'确认新密码'**
  String get desktopLanWebConfirmPassword;

  /// No description provided for @desktopLanWebPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'新密码不能为空'**
  String get desktopLanWebPasswordRequired;

  /// No description provided for @desktopLanWebPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的新密码不一致'**
  String get desktopLanWebPasswordMismatch;

  /// No description provided for @desktopLanWebOldRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入当前密码'**
  String get desktopLanWebOldRequired;

  /// No description provided for @desktopLanWebFooter.
  ///
  /// In zh, this message translates to:
  /// **'凭据仅用于局域网控制台登录；桌面客户端仍通过本机接口通信。'**
  String get desktopLanWebFooter;

  /// No description provided for @desktopHubAdapters.
  ///
  /// In zh, this message translates to:
  /// **'网卡接管'**
  String get desktopHubAdapters;

  /// No description provided for @desktopHubAdaptersBody.
  ///
  /// In zh, this message translates to:
  /// **'逐网卡查看网关、DNS 与接管状态，可单个或全部接管'**
  String get desktopHubAdaptersBody;

  /// No description provided for @desktopHubLanDns.
  ///
  /// In zh, this message translates to:
  /// **'局域网 DNS 服务'**
  String get desktopHubLanDns;

  /// No description provided for @desktopHubLanDnsBody.
  ///
  /// In zh, this message translates to:
  /// **'对外监听 53 端口，供路由器与终端共享解析与拦截'**
  String get desktopHubLanDnsBody;

  /// No description provided for @desktopAdaptersPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'网卡接管'**
  String get desktopAdaptersPageTitle;

  /// No description provided for @desktopAdaptersRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新网卡列表'**
  String get desktopAdaptersRefresh;

  /// No description provided for @desktopAdaptersLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到网卡列表'**
  String get desktopAdaptersLoadFailed;

  /// No description provided for @desktopAdaptersSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络连接与保护接管'**
  String get desktopAdaptersSectionTitle;

  /// No description provided for @desktopAdaptersSectionBody.
  ///
  /// In zh, this message translates to:
  /// **'只列出当前正在使用的网络连接，虚拟与离线网卡由服务端排除。'**
  String get desktopAdaptersSectionBody;

  /// No description provided for @desktopAdaptersTakeoverAll.
  ///
  /// In zh, this message translates to:
  /// **'全部开启保护'**
  String get desktopAdaptersTakeoverAll;

  /// No description provided for @desktopAdaptersRestoreAll.
  ///
  /// In zh, this message translates to:
  /// **'恢复系统默认'**
  String get desktopAdaptersRestoreAll;

  /// No description provided for @desktopAdaptersProtecting.
  ///
  /// In zh, this message translates to:
  /// **'保护中'**
  String get desktopAdaptersProtecting;

  /// No description provided for @desktopAdaptersInactive.
  ///
  /// In zh, this message translates to:
  /// **'未开启'**
  String get desktopAdaptersInactive;

  /// No description provided for @desktopAdaptersConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get desktopAdaptersConnected;

  /// No description provided for @desktopAdaptersDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get desktopAdaptersDisconnected;

  /// No description provided for @desktopAdaptersGateway.
  ///
  /// In zh, this message translates to:
  /// **'默认网关'**
  String get desktopAdaptersGateway;

  /// No description provided for @desktopAdaptersNoGateway.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get desktopAdaptersNoGateway;

  /// No description provided for @desktopAdaptersIpMode.
  ///
  /// In zh, this message translates to:
  /// **'IP 模式'**
  String get desktopAdaptersIpMode;

  /// No description provided for @desktopAdaptersDhcp.
  ///
  /// In zh, this message translates to:
  /// **'自动 (DHCP)'**
  String get desktopAdaptersDhcp;

  /// No description provided for @desktopAdaptersStatic.
  ///
  /// In zh, this message translates to:
  /// **'固定静态 IP'**
  String get desktopAdaptersStatic;

  /// No description provided for @desktopAdaptersOriginalDns.
  ///
  /// In zh, this message translates to:
  /// **'原始系统 DNS'**
  String get desktopAdaptersOriginalDns;

  /// No description provided for @desktopAdaptersAutoDns.
  ///
  /// In zh, this message translates to:
  /// **'自动获取 (系统默认)'**
  String get desktopAdaptersAutoDns;

  /// No description provided for @desktopAdaptersEffectiveDns.
  ///
  /// In zh, this message translates to:
  /// **'当前生效 DNS'**
  String get desktopAdaptersEffectiveDns;

  /// No description provided for @desktopAdaptersEffectiveLoopback.
  ///
  /// In zh, this message translates to:
  /// **'127.0.0.1 (本机保护)'**
  String get desktopAdaptersEffectiveLoopback;

  /// No description provided for @desktopAdaptersEffectiveSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统默认未接管'**
  String get desktopAdaptersEffectiveSystem;

  /// No description provided for @desktopAdaptersEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未发现可用的网络连接'**
  String get desktopAdaptersEmpty;

  /// No description provided for @desktopAdaptersEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'请确认 Wi-Fi 或网线已连接，然后重新检测。'**
  String get desktopAdaptersEmptyBody;

  /// No description provided for @desktopAdaptersAllOn.
  ///
  /// In zh, this message translates to:
  /// **'已接管全部物理网卡'**
  String get desktopAdaptersAllOn;

  /// No description provided for @desktopAdaptersAllOff.
  ///
  /// In zh, this message translates to:
  /// **'已恢复系统默认 DNS'**
  String get desktopAdaptersAllOff;

  /// No description provided for @desktopAdaptersAdapterToggled.
  ///
  /// In zh, this message translates to:
  /// **'{name}：{state}'**
  String desktopAdaptersAdapterToggled(String name, String state);

  /// No description provided for @desktopAdaptersAdapterOn.
  ///
  /// In zh, this message translates to:
  /// **'已接管'**
  String get desktopAdaptersAdapterOn;

  /// No description provided for @desktopAdaptersAdapterOff.
  ///
  /// In zh, this message translates to:
  /// **'已恢复'**
  String get desktopAdaptersAdapterOff;

  /// No description provided for @desktopAdaptersActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopAdaptersActionFailed(String message);

  /// No description provided for @desktopLanDnsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'局域网 DNS 服务'**
  String get desktopLanDnsPageTitle;

  /// No description provided for @desktopLanDnsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新局域网 DNS 状态'**
  String get desktopLanDnsRefresh;

  /// No description provided for @desktopLanDnsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不到局域网 DNS 状态'**
  String get desktopLanDnsLoadFailed;

  /// No description provided for @desktopLanDnsServiceTitle.
  ///
  /// In zh, this message translates to:
  /// **'局域网 DNS 服务'**
  String get desktopLanDnsServiceTitle;

  /// No description provided for @desktopLanDnsServiceBody.
  ///
  /// In zh, this message translates to:
  /// **'开启后，路由器、手机、平板与 NAS 可将首选 DNS 设为本机 IP，共享加速与拦截。'**
  String get desktopLanDnsServiceBody;

  /// No description provided for @desktopLanDnsOnChip.
  ///
  /// In zh, this message translates to:
  /// **'全网监听 (0.0.0.0)'**
  String get desktopLanDnsOnChip;

  /// No description provided for @desktopLanDnsOffChip.
  ///
  /// In zh, this message translates to:
  /// **'仅本机模式'**
  String get desktopLanDnsOffChip;

  /// No description provided for @desktopLanDnsOn.
  ///
  /// In zh, this message translates to:
  /// **'局域网 DNS 服务已开启'**
  String get desktopLanDnsOn;

  /// No description provided for @desktopLanDnsOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭局域网 DNS 服务，恢复为仅本机监听'**
  String get desktopLanDnsOff;

  /// No description provided for @desktopLanDnsAddressesCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'监听与访问地址'**
  String get desktopLanDnsAddressesCardTitle;

  /// No description provided for @desktopLanDnsAddressesCardBody.
  ///
  /// In zh, this message translates to:
  /// **'服务实际绑定的地址，以及局域网内其他设备可以填写的地址'**
  String get desktopLanDnsAddressesCardBody;

  /// No description provided for @desktopLanDnsListenTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前监听地址'**
  String get desktopLanDnsListenTitle;

  /// No description provided for @desktopLanDnsNoListen.
  ///
  /// In zh, this message translates to:
  /// **'服务当前未监听任何地址'**
  String get desktopLanDnsNoListen;

  /// No description provided for @desktopLanDnsAddressesTitle.
  ///
  /// In zh, this message translates to:
  /// **'本机可用的局域网 DNS 地址'**
  String get desktopLanDnsAddressesTitle;

  /// No description provided for @desktopLanDnsNoAddresses.
  ///
  /// In zh, this message translates to:
  /// **'未检测到物理活动网卡 IP，请确认已连接 Wi-Fi 或以太网。'**
  String get desktopLanDnsNoAddresses;

  /// No description provided for @desktopLanDnsIpv4.
  ///
  /// In zh, this message translates to:
  /// **'IPv4'**
  String get desktopLanDnsIpv4;

  /// No description provided for @desktopLanDnsIpv6.
  ///
  /// In zh, this message translates to:
  /// **'IPv6'**
  String get desktopLanDnsIpv6;

  /// No description provided for @desktopLanDnsRouterHint.
  ///
  /// In zh, this message translates to:
  /// **'把 {address} 填进路由器的 DNS 设置即可覆盖全屋设备。'**
  String desktopLanDnsRouterHint(String address);

  /// No description provided for @desktopLanDnsFirewallTitle.
  ///
  /// In zh, this message translates to:
  /// **'防火墙入站放行'**
  String get desktopLanDnsFirewallTitle;

  /// No description provided for @desktopLanDnsFirewallAllowed.
  ///
  /// In zh, this message translates to:
  /// **'53 端口已放行'**
  String get desktopLanDnsFirewallAllowed;

  /// No description provided for @desktopLanDnsFirewallBlocked.
  ///
  /// In zh, this message translates to:
  /// **'未放行'**
  String get desktopLanDnsFirewallBlocked;

  /// No description provided for @desktopLanDnsFirewallNone.
  ///
  /// In zh, this message translates to:
  /// **'无需放行'**
  String get desktopLanDnsFirewallNone;

  /// No description provided for @desktopLanDnsFirewallBody.
  ///
  /// In zh, this message translates to:
  /// **'局域网设备需通过 UDP/TCP 53 端口向本机发送解析请求；被防火墙拦截会导致这些设备断网。'**
  String get desktopLanDnsFirewallBody;

  /// No description provided for @desktopLanDnsFirewallNoneBody.
  ///
  /// In zh, this message translates to:
  /// **'系统未检测到防火墙后端，53 端口已直接对外开放，无需放行规则。'**
  String get desktopLanDnsFirewallNoneBody;

  /// No description provided for @desktopLanDnsFirewallStatusOn.
  ///
  /// In zh, this message translates to:
  /// **'允许局域网设备接入 53 端口'**
  String get desktopLanDnsFirewallStatusOn;

  /// No description provided for @desktopLanDnsFirewallStatusOff.
  ///
  /// In zh, this message translates to:
  /// **'53 端口受限或被拦截'**
  String get desktopLanDnsFirewallStatusOff;

  /// No description provided for @desktopLanDnsFirewallAllow.
  ///
  /// In zh, this message translates to:
  /// **'一键放行入站 53 端口'**
  String get desktopLanDnsFirewallAllow;

  /// No description provided for @desktopLanDnsFirewallRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除防火墙入站放行'**
  String get desktopLanDnsFirewallRemove;

  /// No description provided for @desktopLanDnsFirewallOn.
  ///
  /// In zh, this message translates to:
  /// **'已放行 53 端口入站规则'**
  String get desktopLanDnsFirewallOn;

  /// No description provided for @desktopLanDnsFirewallOff.
  ///
  /// In zh, this message translates to:
  /// **'已移除 53 端口入站规则'**
  String get desktopLanDnsFirewallOff;

  /// No description provided for @desktopLanDnsRouterTitle.
  ///
  /// In zh, this message translates to:
  /// **'方案 A：路由器全局配置'**
  String get desktopLanDnsRouterTitle;

  /// No description provided for @desktopLanDnsRouterBadge.
  ///
  /// In zh, this message translates to:
  /// **'强烈推荐'**
  String get desktopLanDnsRouterBadge;

  /// No description provided for @desktopLanDnsRouterBody.
  ///
  /// In zh, this message translates to:
  /// **'登录路由器后台（通常为 192.168.1.1），在「局域网 LAN 设置」或「DHCP 服务器」里把主 DNS 改为本机 IP。'**
  String get desktopLanDnsRouterBody;

  /// No description provided for @desktopLanDnsRouterFoot.
  ///
  /// In zh, this message translates to:
  /// **'保存并重连 Wi-Fi 后，全屋设备统一生效。'**
  String get desktopLanDnsRouterFoot;

  /// No description provided for @desktopLanDnsDeviceTitle.
  ///
  /// In zh, this message translates to:
  /// **'方案 B：单终端独立配置'**
  String get desktopLanDnsDeviceTitle;

  /// No description provided for @desktopLanDnsDeviceBadge.
  ///
  /// In zh, this message translates to:
  /// **'独立体验'**
  String get desktopLanDnsDeviceBadge;

  /// No description provided for @desktopLanDnsDeviceBody.
  ///
  /// In zh, this message translates to:
  /// **'在手机或电脑的 Wi-Fi 详情里把 IP 设置改为静态，DNS 1 填入本机 IP。'**
  String get desktopLanDnsDeviceBody;

  /// No description provided for @desktopLanDnsDeviceFoot.
  ///
  /// In zh, this message translates to:
  /// **'适用于没有路由器管理权限，或只想让单台设备体验的场景。'**
  String get desktopLanDnsDeviceFoot;

  /// No description provided for @desktopLanDnsPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'192.168.x.x'**
  String get desktopLanDnsPlaceholder;

  /// No description provided for @desktopLanDnsFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopLanDnsFailed(String message);

  /// No description provided for @desktopLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'谛听 DNS 控制台'**
  String get desktopLoginTitle;

  /// No description provided for @desktopLoginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'局域网远程管理服务 · 请验证管理员凭据'**
  String get desktopLoginSubtitle;

  /// No description provided for @desktopLoginSetupSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'初始化管理员密码，守护局域网远程管理安全'**
  String get desktopLoginSetupSubtitle;

  /// No description provided for @desktopLoginUserLabel.
  ///
  /// In zh, this message translates to:
  /// **'管理员账号'**
  String get desktopLoginUserLabel;

  /// No description provided for @desktopLoginPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'管理员密码'**
  String get desktopLoginPasswordLabel;

  /// No description provided for @desktopLoginSetupPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'设置初始密码 (至少 4 位)'**
  String get desktopLoginSetupPasswordLabel;

  /// No description provided for @desktopLoginConfirmLabel.
  ///
  /// In zh, this message translates to:
  /// **'确认管理员密码'**
  String get desktopLoginConfirmLabel;

  /// No description provided for @desktopLoginSubmit.
  ///
  /// In zh, this message translates to:
  /// **'立即登录'**
  String get desktopLoginSubmit;

  /// No description provided for @desktopLoginSetupSubmit.
  ///
  /// In zh, this message translates to:
  /// **'完成初始化并进入控制台'**
  String get desktopLoginSetupSubmit;

  /// No description provided for @desktopLoginSecurity.
  ///
  /// In zh, this message translates to:
  /// **'SHA-256 加盐哈希保护 · 连续错误自动安全锁定'**
  String get desktopLoginSecurity;

  /// No description provided for @desktopLoginFooter.
  ///
  /// In zh, this message translates to:
  /// **'谛听 (DITING) DNS 解析加速与安全防护系统'**
  String get desktopLoginFooter;

  /// No description provided for @desktopLoginChecking.
  ///
  /// In zh, this message translates to:
  /// **'控制台安全载入中…'**
  String get desktopLoginChecking;

  /// No description provided for @desktopLoginShowPassword.
  ///
  /// In zh, this message translates to:
  /// **'显示密码'**
  String get desktopLoginShowPassword;

  /// No description provided for @desktopLoginHidePassword.
  ///
  /// In zh, this message translates to:
  /// **'隐藏密码'**
  String get desktopLoginHidePassword;

  /// No description provided for @desktopLoginUserRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名'**
  String get desktopLoginUserRequired;

  /// No description provided for @desktopLoginPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get desktopLoginPasswordRequired;

  /// No description provided for @desktopLoginPasswordTooShort.
  ///
  /// In zh, this message translates to:
  /// **'密码长度至少为 4 位字符'**
  String get desktopLoginPasswordTooShort;

  /// No description provided for @desktopLoginPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get desktopLoginPasswordMismatch;

  /// No description provided for @desktopLoginSuccess.
  ///
  /// In zh, this message translates to:
  /// **'身份验证成功，正在进入控制台…'**
  String get desktopLoginSuccess;

  /// No description provided for @desktopLoginSetupSuccess.
  ///
  /// In zh, this message translates to:
  /// **'管理员密码设置成功，正在进入系统…'**
  String get desktopLoginSetupSuccess;

  /// No description provided for @desktopLoginLockout.
  ///
  /// In zh, this message translates to:
  /// **'安全频控锁定中，请等待 {seconds} 秒后再试'**
  String desktopLoginLockout(int seconds);

  /// No description provided for @desktopLoginUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'连不上本机服务'**
  String get desktopLoginUnreachable;

  /// No description provided for @desktopLoginRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get desktopLoginRetry;

  /// No description provided for @desktopLoginThemeCycle.
  ///
  /// In zh, this message translates to:
  /// **'切换深浅模式'**
  String get desktopLoginThemeCycle;

  /// No description provided for @desktopLoginPaletteCycle.
  ///
  /// In zh, this message translates to:
  /// **'切换配色方案'**
  String get desktopLoginPaletteCycle;

  /// No description provided for @desktopLoginBackground.
  ///
  /// In zh, this message translates to:
  /// **'自定义背景'**
  String get desktopLoginBackground;

  /// No description provided for @desktopLoginBackgroundEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用自定义背景'**
  String get desktopLoginBackgroundEnabled;

  /// No description provided for @desktopLoginBackgroundTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录背景'**
  String get desktopLoginBackgroundTitle;

  /// No description provided for @desktopLoginBackgroundLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地上传'**
  String get desktopLoginBackgroundLocal;

  /// No description provided for @desktopLoginBackgroundUrl.
  ///
  /// In zh, this message translates to:
  /// **'网络图片'**
  String get desktopLoginBackgroundUrl;

  /// No description provided for @desktopLoginBackgroundChoose.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get desktopLoginBackgroundChoose;

  /// No description provided for @desktopLoginBackgroundNoFile.
  ///
  /// In zh, this message translates to:
  /// **'未选择图片'**
  String get desktopLoginBackgroundNoFile;

  /// No description provided for @desktopLoginBackgroundUrlLabel.
  ///
  /// In zh, this message translates to:
  /// **'图片地址'**
  String get desktopLoginBackgroundUrlLabel;

  /// No description provided for @desktopLoginBackgroundUrlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入 http:// 或 https:// 开头的图片地址'**
  String get desktopLoginBackgroundUrlInvalid;

  /// No description provided for @desktopLoginBackgroundOpacity.
  ///
  /// In zh, this message translates to:
  /// **'遮罩暗度'**
  String get desktopLoginBackgroundOpacity;

  /// No description provided for @desktopLoginBackgroundBlur.
  ///
  /// In zh, this message translates to:
  /// **'毛玻璃模糊'**
  String get desktopLoginBackgroundBlur;

  /// No description provided for @desktopLoginBackgroundSave.
  ///
  /// In zh, this message translates to:
  /// **'保存背景'**
  String get desktopLoginBackgroundSave;

  /// No description provided for @desktopLoginBackgroundReset.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认背景'**
  String get desktopLoginBackgroundReset;

  /// No description provided for @desktopLoginBackgroundSaved.
  ///
  /// In zh, this message translates to:
  /// **'登录背景已保存'**
  String get desktopLoginBackgroundSaved;

  /// No description provided for @desktopLoginBackgroundResetDone.
  ///
  /// In zh, this message translates to:
  /// **'已恢复系统默认背景'**
  String get desktopLoginBackgroundResetDone;

  /// No description provided for @desktopLoginBackgroundNeedImage.
  ///
  /// In zh, this message translates to:
  /// **'请先选择图片或填写图片地址'**
  String get desktopLoginBackgroundNeedImage;

  /// No description provided for @desktopLoginBackgroundPassword.
  ///
  /// In zh, this message translates to:
  /// **'管理员密码'**
  String get desktopLoginBackgroundPassword;

  /// No description provided for @desktopLoginBackgroundPasswordBody.
  ///
  /// In zh, this message translates to:
  /// **'局域网远程修改登录背景需要验证管理员密码。'**
  String get desktopLoginBackgroundPasswordBody;

  /// No description provided for @desktopLoginBackgroundFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{message}'**
  String desktopLoginBackgroundFailed(String message);

  /// No description provided for @desktopSettingsSessionSection.
  ///
  /// In zh, this message translates to:
  /// **'当前会话'**
  String get desktopSettingsSessionSection;

  /// No description provided for @desktopSettingsLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get desktopSettingsLogout;

  /// No description provided for @desktopSettingsLogoutBody.
  ///
  /// In zh, this message translates to:
  /// **'清除本机保存的管理员会话，返回登录页'**
  String get desktopSettingsLogoutBody;

  /// No description provided for @desktopSettingsLogoutConfirm.
  ///
  /// In zh, this message translates to:
  /// **'退出后需要重新输入管理员凭据才能进入控制台。'**
  String get desktopSettingsLogoutConfirm;

  /// No description provided for @desktopSettingsLogoutDone.
  ///
  /// In zh, this message translates to:
  /// **'已退出登录'**
  String get desktopSettingsLogoutDone;

  /// No description provided for @desktopToolsEmergencyTitle.
  ///
  /// In zh, this message translates to:
  /// **'一键恢复系统网络默认'**
  String get desktopToolsEmergencyTitle;

  /// No description provided for @desktopToolsEmergencyBody.
  ///
  /// In zh, this message translates to:
  /// **'当软件异常退出导致无法上网时，按接管前的快照还原系统 DNS，并清理残留回环 DNS 与系统缓存。'**
  String get desktopToolsEmergencyBody;

  /// No description provided for @desktopToolsEmergencyAction.
  ///
  /// In zh, this message translates to:
  /// **'一键恢复'**
  String get desktopToolsEmergencyAction;

  /// No description provided for @desktopToolsEmergencyBusy.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复…'**
  String get desktopToolsEmergencyBusy;

  /// No description provided for @desktopToolsEmergencyConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认执行应急恢复？'**
  String get desktopToolsEmergencyConfirmTitle;

  /// No description provided for @desktopToolsEmergencyConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'将按接管前落盘的快照还原系统 DNS，兜底清理指向本机的残留回环 DNS，再清空系统 DNS 缓存。'**
  String get desktopToolsEmergencyConfirmBody;

  /// No description provided for @desktopToolsEmergencyDone.
  ///
  /// In zh, this message translates to:
  /// **'网络设置已恢复默认'**
  String get desktopToolsEmergencyDone;

  /// No description provided for @desktopToolsEmergencyFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败：{message}'**
  String desktopToolsEmergencyFailed(String message);

  /// No description provided for @desktopToolsEmergencyFooter.
  ///
  /// In zh, this message translates to:
  /// **'恢复依据是接管前落盘的快照，不会改动网卡驱动本身。'**
  String get desktopToolsEmergencyFooter;

  /// No description provided for @desktopLanWebQrCaption.
  ///
  /// In zh, this message translates to:
  /// **'手机与电脑连同一 Wi-Fi，用相机扫码直达控制台'**
  String get desktopLanWebQrCaption;

  /// No description provided for @desktopLoginBackgroundPreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在压缩图片…'**
  String get desktopLoginBackgroundPreparing;

  /// No description provided for @desktopLoginChangePassword.
  ///
  /// In zh, this message translates to:
  /// **'修改管理员密码'**
  String get desktopLoginChangePassword;

  /// No description provided for @desktopLoginChangeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'更新管理员凭据，保存后其他外部会话立即失效'**
  String get desktopLoginChangeSubtitle;

  /// No description provided for @desktopLoginOldPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get desktopLoginOldPasswordLabel;

  /// No description provided for @desktopLoginNewPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'新密码 (至少 4 位)'**
  String get desktopLoginNewPasswordLabel;

  /// No description provided for @desktopLoginChangeSubmit.
  ///
  /// In zh, this message translates to:
  /// **'保存新密码'**
  String get desktopLoginChangeSubmit;

  /// No description provided for @desktopLoginChangeSuccess.
  ///
  /// In zh, this message translates to:
  /// **'管理员密码已更新，请用新密码登录'**
  String get desktopLoginChangeSuccess;

  /// No description provided for @desktopLoginBackToSignIn.
  ///
  /// In zh, this message translates to:
  /// **'返回登录'**
  String get desktopLoginBackToSignIn;

  /// No description provided for @desktopLoginOldPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入当前密码'**
  String get desktopLoginOldPasswordRequired;

  /// No description provided for @desktopTrayTooltip.
  ///
  /// In zh, this message translates to:
  /// **'谛听 (DITING) DNS 控制台'**
  String get desktopTrayTooltip;

  /// No description provided for @desktopTrayOpenWindow.
  ///
  /// In zh, this message translates to:
  /// **'打开主界面'**
  String get desktopTrayOpenWindow;

  /// No description provided for @desktopTrayHideWindow.
  ///
  /// In zh, this message translates to:
  /// **'隐藏主界面'**
  String get desktopTrayHideWindow;

  /// No description provided for @desktopTrayAutoStart.
  ///
  /// In zh, this message translates to:
  /// **'开机自启动'**
  String get desktopTrayAutoStart;

  /// No description provided for @desktopTrayServiceRunning.
  ///
  /// In zh, this message translates to:
  /// **'核心服务：运行中'**
  String get desktopTrayServiceRunning;

  /// No description provided for @desktopTrayServiceStopped.
  ///
  /// In zh, this message translates to:
  /// **'核心服务：已停止'**
  String get desktopTrayServiceStopped;

  /// No description provided for @desktopTrayServiceUnknown.
  ///
  /// In zh, this message translates to:
  /// **'核心服务：状态未知'**
  String get desktopTrayServiceUnknown;

  /// No description provided for @desktopTrayServiceStart.
  ///
  /// In zh, this message translates to:
  /// **'启动核心服务'**
  String get desktopTrayServiceStart;

  /// No description provided for @desktopTrayServiceStop.
  ///
  /// In zh, this message translates to:
  /// **'停止核心服务'**
  String get desktopTrayServiceStop;

  /// No description provided for @desktopTrayServiceRestart.
  ///
  /// In zh, this message translates to:
  /// **'重启核心服务'**
  String get desktopTrayServiceRestart;

  /// No description provided for @desktopTrayQuit.
  ///
  /// In zh, this message translates to:
  /// **'退出程序'**
  String get desktopTrayQuit;

  /// No description provided for @desktopTrayBalloonServiceTitle.
  ///
  /// In zh, this message translates to:
  /// **'核心服务'**
  String get desktopTrayBalloonServiceTitle;

  /// No description provided for @desktopTrayBalloonServiceStarted.
  ///
  /// In zh, this message translates to:
  /// **'核心服务已启动'**
  String get desktopTrayBalloonServiceStarted;

  /// No description provided for @desktopTrayBalloonServiceStopped.
  ///
  /// In zh, this message translates to:
  /// **'核心服务已停止'**
  String get desktopTrayBalloonServiceStopped;

  /// No description provided for @desktopTrayBalloonServiceRestarted.
  ///
  /// In zh, this message translates to:
  /// **'核心服务已重启'**
  String get desktopTrayBalloonServiceRestarted;

  /// No description provided for @desktopTrayBalloonAutoStartTitle.
  ///
  /// In zh, this message translates to:
  /// **'开机自启动'**
  String get desktopTrayBalloonAutoStartTitle;

  /// No description provided for @desktopTrayBalloonAutoStartOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启开机自启动'**
  String get desktopTrayBalloonAutoStartOn;

  /// No description provided for @desktopTrayBalloonAutoStartOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭开机自启动'**
  String get desktopTrayBalloonAutoStartOff;

  /// No description provided for @desktopTrayBalloonFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：'**
  String get desktopTrayBalloonFailedPrefix;

  /// No description provided for @desktopTrayBalloonMinimized.
  ///
  /// In zh, this message translates to:
  /// **'谛听已最小化到系统托盘，并在后台继续运行。\n点击托盘图标可重新打开主界面。'**
  String get desktopTrayBalloonMinimized;

  /// No description provided for @serverHubUpstreamDescription.
  ///
  /// In zh, this message translates to:
  /// **'管理解析上游与解析策略'**
  String get serverHubUpstreamDescription;

  /// No description provided for @serverHubCacheDescription.
  ///
  /// In zh, this message translates to:
  /// **'调整 DNS 缓存开关、容量与命中策略'**
  String get serverHubCacheDescription;

  /// No description provided for @serverHubRuleControlDescription.
  ///
  /// In zh, this message translates to:
  /// **'配置规则总开关与拦截响应策略'**
  String get serverHubRuleControlDescription;

  /// No description provided for @serverNavHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get serverNavHome;

  /// No description provided for @serverServiceSection.
  ///
  /// In zh, this message translates to:
  /// **'服务设置'**
  String get serverServiceSection;

  /// No description provided for @serverDomainRules.
  ///
  /// In zh, this message translates to:
  /// **'域名规则'**
  String get serverDomainRules;

  /// No description provided for @serverDomainRulesDescription.
  ///
  /// In zh, this message translates to:
  /// **'黑名单、白名单与 Hosts 覆写的快捷入口'**
  String get serverDomainRulesDescription;

  /// No description provided for @serverDashboardStatusDescription.
  ///
  /// In zh, this message translates to:
  /// **'服务运行状态、运行时长与本次运行统计'**
  String get serverDashboardStatusDescription;

  /// No description provided for @serverDashboardLanDescription.
  ///
  /// In zh, this message translates to:
  /// **'局域网接入地址、端口与复制入口'**
  String get serverDashboardLanDescription;

  /// No description provided for @integrationSection.
  ///
  /// In zh, this message translates to:
  /// **'系统集成'**
  String get integrationSection;

  /// No description provided for @integrationTitle.
  ///
  /// In zh, this message translates to:
  /// **'小组件与自动化'**
  String get integrationTitle;

  /// No description provided for @integrationSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面小组件、深链导入与自动化控制'**
  String get integrationSubtitle;

  /// No description provided for @integrationWidgetTitle.
  ///
  /// In zh, this message translates to:
  /// **'桌面小组件'**
  String get integrationWidgetTitle;

  /// No description provided for @integrationWidgetBody.
  ///
  /// In zh, this message translates to:
  /// **'长按桌面空白处，进入「小组件」，选择「谛听」即可添加。组件显示保护状态与今日拦截数，点右侧按钮可一键开启或关闭。'**
  String get integrationWidgetBody;

  /// No description provided for @integrationDeepLinkTitle.
  ///
  /// In zh, this message translates to:
  /// **'深链导入订阅'**
  String get integrationDeepLinkTitle;

  /// No description provided for @integrationDeepLinkBody.
  ///
  /// In zh, this message translates to:
  /// **'在浏览器或其它应用中打开 diting://install-config?url=<订阅地址>，即可直接导入订阅（需先接受首次使用协议）。install-sub 为等价写法。'**
  String get integrationDeepLinkBody;

  /// No description provided for @integrationAutomationTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动化控制'**
  String get integrationAutomationTitle;

  /// No description provided for @integrationAutomationBody.
  ///
  /// In zh, this message translates to:
  /// **'通过 Tasker、MacroDroid 或 adb 发送以下动作，可启动、停止或切换当前模式：'**
  String get integrationAutomationBody;

  /// No description provided for @integrationAutomationStart.
  ///
  /// In zh, this message translates to:
  /// **'启动'**
  String get integrationAutomationStart;

  /// No description provided for @integrationAutomationStop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get integrationAutomationStop;

  /// No description provided for @integrationAutomationToggle.
  ///
  /// In zh, this message translates to:
  /// **'切换'**
  String get integrationAutomationToggle;

  /// No description provided for @deepLinkImportInvalid.
  ///
  /// In zh, this message translates to:
  /// **'深链地址无效，无法导入订阅'**
  String get deepLinkImportInvalid;

  /// No description provided for @troubleshootLogsTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志管理'**
  String get troubleshootLogsTitle;

  /// No description provided for @troubleshootLogsViewLogs.
  ///
  /// In zh, this message translates to:
  /// **'查看并管理日志'**
  String get troubleshootLogsViewLogs;

  /// No description provided for @troubleshootLogsViewLogsBody.
  ///
  /// In zh, this message translates to:
  /// **'按时间查看运行日志与崩溃日志，可删除或分享'**
  String get troubleshootLogsViewLogsBody;

  /// No description provided for @troubleshootLogsAll.
  ///
  /// In zh, this message translates to:
  /// **'全部日志'**
  String get troubleshootLogsAll;

  /// No description provided for @troubleshootLogsCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个日志文件'**
  String troubleshootLogsCount(int count);

  /// No description provided for @troubleshootLogsReading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取日志…'**
  String get troubleshootLogsReading;

  /// No description provided for @troubleshootLogsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'当前设备没有日志'**
  String get troubleshootLogsEmpty;

  /// No description provided for @troubleshootLogsEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'开启运行日志记录或发生崩溃后，日志会出现在这里。'**
  String get troubleshootLogsEmptyBody;

  /// No description provided for @troubleshootLogKindRuntime.
  ///
  /// In zh, this message translates to:
  /// **'运行日志'**
  String get troubleshootLogKindRuntime;

  /// No description provided for @troubleshootLogKindCrash.
  ///
  /// In zh, this message translates to:
  /// **'崩溃日志'**
  String get troubleshootLogKindCrash;

  /// No description provided for @troubleshootLogsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get troubleshootLogsRefresh;

  /// No description provided for @troubleshootLogsShare.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get troubleshootLogsShare;

  /// No description provided for @troubleshootLogsShareAll.
  ///
  /// In zh, this message translates to:
  /// **'分享全部'**
  String get troubleshootLogsShareAll;

  /// No description provided for @troubleshootLogsClearAll.
  ///
  /// In zh, this message translates to:
  /// **'清空全部'**
  String get troubleshootLogsClearAll;

  /// No description provided for @troubleshootLogsShared.
  ///
  /// In zh, this message translates to:
  /// **'已打开系统分享'**
  String get troubleshootLogsShared;

  /// No description provided for @troubleshootLogsShareFailed.
  ///
  /// In zh, this message translates to:
  /// **'分享失败'**
  String get troubleshootLogsShareFailed;

  /// No description provided for @troubleshootLogsDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除该日志'**
  String get troubleshootLogsDeleted;

  /// No description provided for @troubleshootLogsDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败'**
  String get troubleshootLogsDeleteFailed;

  /// No description provided for @troubleshootLogsDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除日志'**
  String get troubleshootLogsDeleteTitle;

  /// No description provided for @troubleshootLogsDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确认删除“{name}”吗？该操作不可恢复。'**
  String troubleshootLogsDeleteBody(String name);

  /// No description provided for @troubleshootLogsClearAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空全部日志'**
  String get troubleshootLogsClearAllTitle;

  /// No description provided for @troubleshootLogsClearAllBody.
  ///
  /// In zh, this message translates to:
  /// **'确认删除全部运行日志与崩溃日志吗？该操作不可恢复。'**
  String get troubleshootLogsClearAllBody;

  /// No description provided for @troubleshootLogsClearedAll.
  ///
  /// In zh, this message translates to:
  /// **'已清空 {runtime} 个运行日志与 {crash} 份崩溃日志'**
  String troubleshootLogsClearedAll(int runtime, int crash);

  /// No description provided for @troubleshootLogsLogContent.
  ///
  /// In zh, this message translates to:
  /// **'日志内容'**
  String get troubleshootLogsLogContent;

  /// No description provided for @troubleshootLogsDetailInfo.
  ///
  /// In zh, this message translates to:
  /// **'日志信息'**
  String get troubleshootLogsDetailInfo;

  /// No description provided for @troubleshootLogsFileName.
  ///
  /// In zh, this message translates to:
  /// **'文件名'**
  String get troubleshootLogsFileName;

  /// No description provided for @troubleshootLogsFileType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get troubleshootLogsFileType;

  /// No description provided for @troubleshootLogsFileSize.
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get troubleshootLogsFileSize;

  /// No description provided for @troubleshootLogsModifiedAt.
  ///
  /// In zh, this message translates to:
  /// **'修改时间'**
  String get troubleshootLogsModifiedAt;

  /// No description provided for @troubleshootLogsViewContent.
  ///
  /// In zh, this message translates to:
  /// **'查看日志内容'**
  String get troubleshootLogsViewContent;

  /// No description provided for @troubleshootLogsViewContentBody.
  ///
  /// In zh, this message translates to:
  /// **'进入下一层查看完整日志'**
  String get troubleshootLogsViewContentBody;

  /// No description provided for @troubleshootLogsEmptyContent.
  ///
  /// In zh, this message translates to:
  /// **'无法读取该日志内容'**
  String get troubleshootLogsEmptyContent;

  /// No description provided for @troubleshootLogsTruncated.
  ///
  /// In zh, this message translates to:
  /// **'内容过长，仅显示开头部分'**
  String get troubleshootLogsTruncated;

  /// No description provided for @troubleshootLogsFooter.
  ///
  /// In zh, this message translates to:
  /// **'日志只保存在本机，分享前请确认其中不含敏感信息。'**
  String get troubleshootLogsFooter;

  /// No description provided for @troubleshootEventsTitle.
  ///
  /// In zh, this message translates to:
  /// **'运行事件'**
  String get troubleshootEventsTitle;

  /// No description provided for @troubleshootEventsRecentTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近运行事件'**
  String get troubleshootEventsRecentTitle;

  /// No description provided for @troubleshootEventsRecentBody.
  ///
  /// In zh, this message translates to:
  /// **'常开记录应用启动、服务与引擎的异常事件，可事后排查。'**
  String get troubleshootEventsRecentBody;

  /// No description provided for @troubleshootEventsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无运行事件'**
  String get troubleshootEventsEmpty;

  /// No description provided for @troubleshootEventsEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'应用启动、服务或引擎发生异常时会自动记录。'**
  String get troubleshootEventsEmptyBody;

  /// No description provided for @troubleshootEventsAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get troubleshootEventsAll;

  /// No description provided for @troubleshootEventsWarnPlus.
  ///
  /// In zh, this message translates to:
  /// **'警告及以上'**
  String get troubleshootEventsWarnPlus;

  /// No description provided for @troubleshootEventsErrorOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅错误'**
  String get troubleshootEventsErrorOnly;

  /// No description provided for @troubleshootEventsModuleAll.
  ///
  /// In zh, this message translates to:
  /// **'全部模块'**
  String get troubleshootEventsModuleAll;

  /// No description provided for @troubleshootEventsCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 条'**
  String troubleshootEventsCount(int count);

  /// No description provided for @troubleshootEventsAnomaly.
  ///
  /// In zh, this message translates to:
  /// **'检测到 {count} 条异常'**
  String troubleshootEventsAnomaly(int count);

  /// No description provided for @troubleshootEventsExport.
  ///
  /// In zh, this message translates to:
  /// **'导出当前筛选'**
  String get troubleshootEventsExport;

  /// No description provided for @troubleshootEventsStatTotal.
  ///
  /// In zh, this message translates to:
  /// **'事件总数'**
  String get troubleshootEventsStatTotal;

  /// No description provided for @troubleshootEventsStatError.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get troubleshootEventsStatError;

  /// No description provided for @troubleshootEventsNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有符合筛选条件的事件'**
  String get troubleshootEventsNoMatch;

  /// No description provided for @troubleshootEventsLevel.
  ///
  /// In zh, this message translates to:
  /// **'级别'**
  String get troubleshootEventsLevel;

  /// No description provided for @troubleshootEventsModule.
  ///
  /// In zh, this message translates to:
  /// **'模块'**
  String get troubleshootEventsModule;

  /// No description provided for @troubleshootEventsOpen.
  ///
  /// In zh, this message translates to:
  /// **'查看运行事件'**
  String get troubleshootEventsOpen;

  /// No description provided for @troubleshootEventsOpenBody.
  ///
  /// In zh, this message translates to:
  /// **'按级别与模块筛选启动、服务与异常事件'**
  String get troubleshootEventsOpenBody;

  /// No description provided for @troubleshootDetailMode.
  ///
  /// In zh, this message translates to:
  /// **'详细模式'**
  String get troubleshootDetailMode;

  /// No description provided for @troubleshootDetailModeNote.
  ///
  /// In zh, this message translates to:
  /// **'详细模式记录所有进程与缓冲区的完整 logcat，更全面但更耗电。'**
  String get troubleshootDetailModeNote;

  /// No description provided for @automationTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动化'**
  String get automationTitle;

  /// No description provided for @automationSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'条件-动作规则编排场景'**
  String get automationSubtitle;

  /// No description provided for @automationHubSection.
  ///
  /// In zh, this message translates to:
  /// **'场景与自动化'**
  String get automationHubSection;

  /// No description provided for @automationIntro.
  ///
  /// In zh, this message translates to:
  /// **'用触发、条件与动作把零散入口组合成场景（到家 / 会议 / 游戏 / 低电）。'**
  String get automationIntro;

  /// No description provided for @automationEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有自动化规则，点击右上角新增一条开始编排场景。'**
  String get automationEmpty;

  /// No description provided for @automationRulesSection.
  ///
  /// In zh, this message translates to:
  /// **'规则'**
  String get automationRulesSection;

  /// No description provided for @automationHistory.
  ///
  /// In zh, this message translates to:
  /// **'审计时间线'**
  String get automationHistory;

  /// No description provided for @automationHistoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无自动化事件。'**
  String get automationHistoryEmpty;

  /// No description provided for @automationRuleFallbackName.
  ///
  /// In zh, this message translates to:
  /// **'未命名规则'**
  String get automationRuleFallbackName;

  /// No description provided for @automationPriorityShort.
  ///
  /// In zh, this message translates to:
  /// **'优先级 {value}'**
  String automationPriorityShort(int value);

  /// No description provided for @automationActionCount.
  ///
  /// In zh, this message translates to:
  /// **'{value} 个动作'**
  String automationActionCount(int value);

  /// No description provided for @automationTriggerSchedule.
  ///
  /// In zh, this message translates to:
  /// **'定时'**
  String get automationTriggerSchedule;

  /// No description provided for @automationTriggerNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get automationTriggerNetwork;

  /// No description provided for @automationTriggerState.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get automationTriggerState;

  /// No description provided for @automationTriggerManual.
  ///
  /// In zh, this message translates to:
  /// **'手动'**
  String get automationTriggerManual;

  /// No description provided for @automationNewTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建规则'**
  String get automationNewTitle;

  /// No description provided for @automationEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑规则'**
  String get automationEditTitle;

  /// No description provided for @automationDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get automationDelete;

  /// No description provided for @automationSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get automationSave;

  /// No description provided for @automationEditIntro.
  ///
  /// In zh, this message translates to:
  /// **'选择触发方式与动作；保存后由自动化引擎在对应时机执行。'**
  String get automationEditIntro;

  /// No description provided for @automationRuleName.
  ///
  /// In zh, this message translates to:
  /// **'规则名称'**
  String get automationRuleName;

  /// No description provided for @automationPriority.
  ///
  /// In zh, this message translates to:
  /// **'优先级'**
  String get automationPriority;

  /// No description provided for @automationTrigger.
  ///
  /// In zh, this message translates to:
  /// **'触发方式'**
  String get automationTrigger;

  /// No description provided for @automationMatch.
  ///
  /// In zh, this message translates to:
  /// **'条件组合'**
  String get automationMatch;

  /// No description provided for @automationMatchAll.
  ///
  /// In zh, this message translates to:
  /// **'满足全部条件'**
  String get automationMatchAll;

  /// No description provided for @automationMatchAny.
  ///
  /// In zh, this message translates to:
  /// **'满足任一条件'**
  String get automationMatchAny;

  /// No description provided for @automationActions.
  ///
  /// In zh, this message translates to:
  /// **'动作'**
  String get automationActions;

  /// No description provided for @automationActionPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停拦截'**
  String get automationActionPause;

  /// No description provided for @automationMinutes.
  ///
  /// In zh, this message translates to:
  /// **'分钟'**
  String get automationMinutes;

  /// No description provided for @automationActionBlockServices.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽服务'**
  String get automationActionBlockServices;

  /// No description provided for @automationServicesUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'服务目录内核不可用'**
  String get automationServicesUnavailable;

  /// No description provided for @automationSwitchProfileNone.
  ///
  /// In zh, this message translates to:
  /// **'不切换档案'**
  String get automationSwitchProfileNone;

  /// No description provided for @automationScheduleStart.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get automationScheduleStart;

  /// No description provided for @automationScheduleEnd.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get automationScheduleEnd;

  /// No description provided for @profilesTitle.
  ///
  /// In zh, this message translates to:
  /// **'配置档案'**
  String get profilesTitle;

  /// No description provided for @profilesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'一键切换配置快照'**
  String get profilesSubtitle;

  /// No description provided for @profilesAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增档案'**
  String get profilesAdd;

  /// No description provided for @profilesIntro.
  ///
  /// In zh, this message translates to:
  /// **'一键切换工作模式 / 上游集 / 规则组与开关的快照。'**
  String get profilesIntro;

  /// No description provided for @profilesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有配置档案。'**
  String get profilesEmpty;

  /// No description provided for @profilesListSection.
  ///
  /// In zh, this message translates to:
  /// **'档案'**
  String get profilesListSection;

  /// No description provided for @profilesApply.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get profilesApply;

  /// No description provided for @profilesDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get profilesDelete;

  /// No description provided for @profilesName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get profilesName;

  /// No description provided for @profilesUpstreamSet.
  ///
  /// In zh, this message translates to:
  /// **'上游集'**
  String get profilesUpstreamSet;

  /// No description provided for @profilesCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get profilesCancel;

  /// No description provided for @profilesSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get profilesSave;

  /// No description provided for @profilesApplied.
  ///
  /// In zh, this message translates to:
  /// **'已应用 {name}'**
  String profilesApplied(String name);

  /// No description provided for @timetableTitle.
  ///
  /// In zh, this message translates to:
  /// **'分时规则'**
  String get timetableTitle;

  /// No description provided for @timetableSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按周编排拦截时段'**
  String get timetableSubtitle;

  /// No description provided for @timetableAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增时段'**
  String get timetableAdd;

  /// No description provided for @timetableIntro.
  ///
  /// In zh, this message translates to:
  /// **'按周编排分时拦截时段，到点自动收紧或恢复。'**
  String get timetableIntro;

  /// No description provided for @timetableEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有分时时段。'**
  String get timetableEmpty;

  /// No description provided for @netProfileTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络档案'**
  String get netProfileTitle;

  /// No description provided for @netProfileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按网络差异化策略'**
  String get netProfileSubtitle;

  /// No description provided for @netProfileAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增网络档案'**
  String get netProfileAdd;

  /// No description provided for @netProfileIntro.
  ///
  /// In zh, this message translates to:
  /// **'按当前网络（Wi‑Fi / 蜂窝 / 漫游 / 计费）自动选择生效的上游集与规则组。'**
  String get netProfileIntro;

  /// No description provided for @netProfileCurrentNet.
  ///
  /// In zh, this message translates to:
  /// **'当前网络'**
  String get netProfileCurrentNet;

  /// No description provided for @netProfileResolved.
  ///
  /// In zh, this message translates to:
  /// **'生效档案'**
  String get netProfileResolved;

  /// No description provided for @netProfileNone.
  ///
  /// In zh, this message translates to:
  /// **'无匹配档案'**
  String get netProfileNone;

  /// No description provided for @netProfileEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有网络档案，新增一条开始按网络切换策略。'**
  String get netProfileEmpty;

  /// No description provided for @netProfileList.
  ///
  /// In zh, this message translates to:
  /// **'网络档案'**
  String get netProfileList;

  /// No description provided for @netProfileDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get netProfileDelete;

  /// No description provided for @netProfileName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get netProfileName;

  /// No description provided for @netProfileUpstreamSet.
  ///
  /// In zh, this message translates to:
  /// **'上游集'**
  String get netProfileUpstreamSet;

  /// No description provided for @netProfilePriority.
  ///
  /// In zh, this message translates to:
  /// **'优先级'**
  String get netProfilePriority;

  /// No description provided for @netProfileCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get netProfileCancel;

  /// No description provided for @netProfileSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get netProfileSave;

  /// No description provided for @automationAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增规则'**
  String get automationAdd;

  /// No description provided for @networkDiagnosticsTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络诊断'**
  String get networkDiagnosticsTitle;

  /// No description provided for @networkDiagnosticsIntro.
  ///
  /// In zh, this message translates to:
  /// **'检查 DNS 是否经过配置上游，并识别需要登录的 Captive Portal。'**
  String get networkDiagnosticsIntro;

  /// No description provided for @dnsLeakSection.
  ///
  /// In zh, this message translates to:
  /// **'DNS 泄漏检测'**
  String get dnsLeakSection;

  /// No description provided for @dnsLeakRun.
  ///
  /// In zh, this message translates to:
  /// **'开始检测'**
  String get dnsLeakRun;

  /// No description provided for @dnsLeakPass.
  ///
  /// In zh, this message translates to:
  /// **'通过'**
  String get dnsLeakPass;

  /// No description provided for @dnsLeakLeak.
  ///
  /// In zh, this message translates to:
  /// **'发现泄漏'**
  String get dnsLeakLeak;

  /// No description provided for @dnsLeakUnknown.
  ///
  /// In zh, this message translates to:
  /// **'无法判定'**
  String get dnsLeakUnknown;

  /// No description provided for @dnsLeakReasonBypass.
  ///
  /// In zh, this message translates to:
  /// **'隧道未运行，查询未经过配置上游。'**
  String get dnsLeakReasonBypass;

  /// No description provided for @dnsLeakReasonProxied.
  ///
  /// In zh, this message translates to:
  /// **'查询经隧道转发至配置上游。'**
  String get dnsLeakReasonProxied;

  /// No description provided for @dnsLeakReasonMismatch.
  ///
  /// In zh, this message translates to:
  /// **'出口解析器与配置上游不一致。'**
  String get dnsLeakReasonMismatch;

  /// No description provided for @dnsLeakReasonPlaintext.
  ///
  /// In zh, this message translates to:
  /// **'发现明文 DNS 出站。'**
  String get dnsLeakReasonPlaintext;

  /// No description provided for @dnsLeakReasonInsufficient.
  ///
  /// In zh, this message translates to:
  /// **'探测数据不足，无法判定。'**
  String get dnsLeakReasonInsufficient;

  /// No description provided for @dnsLeakVpnActive.
  ///
  /// In zh, this message translates to:
  /// **'隧道运行中'**
  String get dnsLeakVpnActive;

  /// No description provided for @dnsLeakVpnInactive.
  ///
  /// In zh, this message translates to:
  /// **'隧道未运行'**
  String get dnsLeakVpnInactive;

  /// No description provided for @captiveSection.
  ///
  /// In zh, this message translates to:
  /// **'Captive Portal'**
  String get captiveSection;

  /// No description provided for @captiveRun.
  ///
  /// In zh, this message translates to:
  /// **'检测门户'**
  String get captiveRun;

  /// No description provided for @captiveOpen.
  ///
  /// In zh, this message translates to:
  /// **'网络正常'**
  String get captiveOpen;

  /// No description provided for @captivePortal.
  ///
  /// In zh, this message translates to:
  /// **'需要登录门户'**
  String get captivePortal;

  /// No description provided for @captiveUnknown.
  ///
  /// In zh, this message translates to:
  /// **'无法判定'**
  String get captiveUnknown;

  /// No description provided for @captiveOpenPortal.
  ///
  /// In zh, this message translates to:
  /// **'打开登录页'**
  String get captiveOpenPortal;

  /// No description provided for @networkDiagnosticsFailed.
  ///
  /// In zh, this message translates to:
  /// **'检测失败，请稍后重试。'**
  String get networkDiagnosticsFailed;

  /// No description provided for @appInsightsTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用洞察'**
  String get appInsightsTitle;

  /// No description provided for @appInsightsIntro.
  ///
  /// In zh, this message translates to:
  /// **'基于实时连接按应用汇总流量、拦截与连接地图。'**
  String get appInsightsIntro;

  /// No description provided for @appInsightsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无可展示的连接，请先启动隧道并产生流量。'**
  String get appInsightsEmpty;

  /// No description provided for @appInsightsReports.
  ///
  /// In zh, this message translates to:
  /// **'应用报告卡'**
  String get appInsightsReports;

  /// No description provided for @appInsightsMap.
  ///
  /// In zh, this message translates to:
  /// **'连接地图'**
  String get appInsightsMap;

  /// No description provided for @appInsightsStat.
  ///
  /// In zh, this message translates to:
  /// **'{connections} 连接 · {blocked} 拦截 · {bytes}'**
  String appInsightsStat(int connections, int blocked, String bytes);

  /// No description provided for @appInsightsNoDomains.
  ///
  /// In zh, this message translates to:
  /// **'暂无域名'**
  String get appInsightsNoDomains;

  /// No description provided for @localApiTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地 API'**
  String get localApiTitle;

  /// No description provided for @localApiIntro.
  ///
  /// In zh, this message translates to:
  /// **'仅绑定 127.0.0.1 且需要令牌校验的只读 HTTP 接口，供本机脚本读取运行状态。'**
  String get localApiIntro;

  /// No description provided for @localApiEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用本地 API'**
  String get localApiEnable;

  /// No description provided for @localApiToken.
  ///
  /// In zh, this message translates to:
  /// **'访问令牌'**
  String get localApiToken;

  /// No description provided for @localApiRegenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get localApiRegenerate;

  /// No description provided for @localApiCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get localApiCopy;

  /// No description provided for @localApiCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get localApiCopied;

  /// No description provided for @localApiPort.
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get localApiPort;

  /// No description provided for @localApiRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中：http://127.0.0.1:{port}'**
  String localApiRunning(int port);

  /// No description provided for @localApiStopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get localApiStopped;

  /// No description provided for @localApiEndpoints.
  ///
  /// In zh, this message translates to:
  /// **'接口'**
  String get localApiEndpoints;

  /// No description provided for @localApiEndpointStatus.
  ///
  /// In zh, this message translates to:
  /// **'GET /status'**
  String get localApiEndpointStatus;

  /// No description provided for @localApiEndpointVersion.
  ///
  /// In zh, this message translates to:
  /// **'GET /version'**
  String get localApiEndpointVersion;

  /// No description provided for @localApiHeaderHint.
  ///
  /// In zh, this message translates to:
  /// **'请求头：X-Diting-Token: <令牌>'**
  String get localApiHeaderHint;

  /// No description provided for @localApiError.
  ///
  /// In zh, this message translates to:
  /// **'启动失败：{message}'**
  String localApiError(String message);

  /// No description provided for @privacySuiteTitle.
  ///
  /// In zh, this message translates to:
  /// **'隐私套件'**
  String get privacySuiteTitle;

  /// No description provided for @privacySuiteIntro.
  ///
  /// In zh, this message translates to:
  /// **'在不影响正常解析的前提下收紧 DNS 隐私：减少可用于追踪的记录类型，并阻止域名重绑定到内网地址。'**
  String get privacySuiteIntro;

  /// No description provided for @privacyDnsSection.
  ///
  /// In zh, this message translates to:
  /// **'DNS 隐私'**
  String get privacyDnsSection;

  /// No description provided for @privacyBlockHttpsSvcb.
  ///
  /// In zh, this message translates to:
  /// **'阻断 HTTPS / SVCB 记录'**
  String get privacyBlockHttpsSvcb;

  /// No description provided for @privacyBlockHttpsSvcbDesc.
  ///
  /// In zh, this message translates to:
  /// **'对 HTTPS(65) 与 SVCB(64) 查询返回空应答，避免通过这些记录暴露访问意图。'**
  String get privacyBlockHttpsSvcbDesc;

  /// No description provided for @privacyRebinding.
  ///
  /// In zh, this message translates to:
  /// **'DNS 重绑定保护'**
  String get privacyRebinding;

  /// No description provided for @privacyRebindingDesc.
  ///
  /// In zh, this message translates to:
  /// **'拒绝把公网域名解析到私有、回环或链路本地地址，防止借 DNS 访问内网服务。'**
  String get privacyRebindingDesc;

  /// No description provided for @dns64Title.
  ///
  /// In zh, this message translates to:
  /// **'DNS64'**
  String get dns64Title;

  /// No description provided for @dns64Intro.
  ///
  /// In zh, this message translates to:
  /// **'在只有 IPv6 的网络里，许多站点仍只提供 IPv4 地址。DNS64 会用 A 记录合成 AAAA，让这些站点照常访问。'**
  String get dns64Intro;

  /// No description provided for @dns64Enable.
  ///
  /// In zh, this message translates to:
  /// **'启用 DNS64 合成'**
  String get dns64Enable;

  /// No description provided for @dns64EnableDesc.
  ///
  /// In zh, this message translates to:
  /// **'当上游没有可用 AAAA 时，用固定前缀 64:ff9b::/96 从 A 记录合成 AAAA。仅在 IPv6-only 网络开启，双栈网络开启可能导致访问异常。'**
  String get dns64EnableDesc;

  /// No description provided for @lanRateLimitTitle.
  ///
  /// In zh, this message translates to:
  /// **'LAN 客户端限速'**
  String get lanRateLimitTitle;

  /// No description provided for @lanRateLimitIntro.
  ///
  /// In zh, this message translates to:
  /// **'服务器模式面向局域网提供 DNS。这里为每个客户端设置令牌桶限速，防止单个设备耗尽解析能力。'**
  String get lanRateLimitIntro;

  /// No description provided for @lanRateLimitEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用客户端限速'**
  String get lanRateLimitEnable;

  /// No description provided for @lanRateLimitEnableDesc.
  ///
  /// In zh, this message translates to:
  /// **'按客户端地址聚合后限制每秒查询数；关闭时不做任何限速。'**
  String get lanRateLimitEnableDesc;

  /// No description provided for @lanRateLimitRate.
  ///
  /// In zh, this message translates to:
  /// **'每秒请求数'**
  String get lanRateLimitRate;

  /// No description provided for @lanRateLimitBurst.
  ///
  /// In zh, this message translates to:
  /// **'突发上限'**
  String get lanRateLimitBurst;

  /// No description provided for @lanRateLimitIpv4Prefix.
  ///
  /// In zh, this message translates to:
  /// **'IPv4 聚合前缀（位）'**
  String get lanRateLimitIpv4Prefix;

  /// No description provided for @lanRateLimitIpv6Prefix.
  ///
  /// In zh, this message translates to:
  /// **'IPv6 聚合前缀（位）'**
  String get lanRateLimitIpv6Prefix;

  /// No description provided for @lanRateLimitExempt.
  ///
  /// In zh, this message translates to:
  /// **'不限速名单'**
  String get lanRateLimitExempt;

  /// No description provided for @lanRateLimitExemptHint.
  ///
  /// In zh, this message translates to:
  /// **'逗号分隔，如 192.168.0.1, 10.0.0.0/8'**
  String get lanRateLimitExemptHint;

  /// No description provided for @ruleVersionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'订阅版本回滚'**
  String get ruleVersionsTitle;

  /// No description provided for @ruleVersionsIntro.
  ///
  /// In zh, this message translates to:
  /// **'每次订阅更新都会记录规则快照。可从历史版本对比差异或一键回滚，避免被误更新或投毒规则影响。'**
  String get ruleVersionsIntro;

  /// No description provided for @ruleVersionsPick.
  ///
  /// In zh, this message translates to:
  /// **'选择订阅'**
  String get ruleVersionsPick;

  /// No description provided for @ruleVersionsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'该订阅还没有版本记录，更新一次后即可查看。'**
  String get ruleVersionsEmpty;

  /// No description provided for @ruleVersionsNone.
  ///
  /// In zh, this message translates to:
  /// **'没有可选订阅'**
  String get ruleVersionsNone;

  /// No description provided for @ruleVersionsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'规则数据库不可用'**
  String get ruleVersionsUnavailable;

  /// No description provided for @ruleVersionsCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get ruleVersionsCurrent;

  /// No description provided for @ruleVersionsRuleCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条规则'**
  String ruleVersionsRuleCount(int count);

  /// No description provided for @ruleVersionsCompare.
  ///
  /// In zh, this message translates to:
  /// **'对比'**
  String get ruleVersionsCompare;

  /// No description provided for @ruleVersionsRollback.
  ///
  /// In zh, this message translates to:
  /// **'回滚'**
  String get ruleVersionsRollback;

  /// No description provided for @ruleVersionsDiffTitle.
  ///
  /// In zh, this message translates to:
  /// **'版本差异'**
  String get ruleVersionsDiffTitle;

  /// No description provided for @ruleVersionsDiffSummary.
  ///
  /// In zh, this message translates to:
  /// **'新增 {added} 条，移除 {removed} 条'**
  String ruleVersionsDiffSummary(int added, int removed);

  /// No description provided for @ruleVersionsAdded.
  ///
  /// In zh, this message translates to:
  /// **'新增'**
  String get ruleVersionsAdded;

  /// No description provided for @ruleVersionsRemoved.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get ruleVersionsRemoved;

  /// No description provided for @ruleVersionsRollbackConfirm.
  ///
  /// In zh, this message translates to:
  /// **'回滚到该版本？当前规则将被替换。'**
  String get ruleVersionsRollbackConfirm;

  /// No description provided for @ruleVersionsRollbackDone.
  ///
  /// In zh, this message translates to:
  /// **'已回滚到所选版本'**
  String get ruleVersionsRollbackDone;

  /// No description provided for @ruleVersionsRollbackFailed.
  ///
  /// In zh, this message translates to:
  /// **'回滚失败：{message}'**
  String ruleVersionsRollbackFailed(String message);

  /// No description provided for @webhookTitle.
  ///
  /// In zh, this message translates to:
  /// **'Webhook 通知'**
  String get webhookTitle;

  /// No description provided for @webhookIntro.
  ///
  /// In zh, this message translates to:
  /// **'把自动化与审计事件推送到你自己的 Webhook。请求体为 JSON，并用 HMAC-SHA256 对「时间戳.请求体」签名，可在服务端校验来源。'**
  String get webhookIntro;

  /// No description provided for @webhookSection.
  ///
  /// In zh, this message translates to:
  /// **'推送配置'**
  String get webhookSection;

  /// No description provided for @webhookEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用 Webhook'**
  String get webhookEnable;

  /// No description provided for @webhookEnableDesc.
  ///
  /// In zh, this message translates to:
  /// **'默认关闭。关闭时不发送任何请求。'**
  String get webhookEnableDesc;

  /// No description provided for @webhookUrl.
  ///
  /// In zh, this message translates to:
  /// **'接收地址'**
  String get webhookUrl;

  /// No description provided for @webhookUrlHint.
  ///
  /// In zh, this message translates to:
  /// **'https://example.com/diting/hook'**
  String get webhookUrlHint;

  /// No description provided for @webhookSecret.
  ///
  /// In zh, this message translates to:
  /// **'签名密钥'**
  String get webhookSecret;

  /// No description provided for @webhookSecretDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于 HMAC-SHA256 签名，请求头 X-Diting-Signature 形如 sha256=...'**
  String get webhookSecretDesc;

  /// No description provided for @webhookTest.
  ///
  /// In zh, this message translates to:
  /// **'发送测试事件'**
  String get webhookTest;

  /// No description provided for @webhookTestHint.
  ///
  /// In zh, this message translates to:
  /// **'向已配置地址发送一条 test 事件，验证签名与连通性'**
  String get webhookTestHint;

  /// No description provided for @webhookTesting.
  ///
  /// In zh, this message translates to:
  /// **'正在发送…'**
  String get webhookTesting;

  /// No description provided for @webhookTestOk.
  ///
  /// In zh, this message translates to:
  /// **'发送成功：{result}'**
  String webhookTestOk(String result);

  /// No description provided for @webhookTestFail.
  ///
  /// In zh, this message translates to:
  /// **'发送失败：{result}'**
  String webhookTestFail(String result);
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
  // Lookup logic when only language code is specified.
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
