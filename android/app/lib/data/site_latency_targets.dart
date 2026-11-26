library;

import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_android/ui/icons/icons.dart';

class SiteLatencyTarget {
  const SiteLatencyTarget({
    required this.id,
    required this.name,
    required this.host,
    required this.icon,
    required this.category,
  });

  final String id;

  final String name;

  final String host;

  final SiteIcon icon;

  final SiteCategory category;
}

const defaultDashboardSiteIds = <String>[
  'baidu',
  'douyin',
  'bilibili',
  'netease',
];

const siteLatencyTargets = <SiteLatencyTarget>[
  SiteLatencyTarget(
    id: 'baidu',
    name: '百度',
    host: 'www.baidu.com',
    icon: TablerSiteIcon(TablerIcons.brand_baidu),
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'sogou',
    name: '搜狗',
    host: 'www.sogou.com',
    icon: BrandSiteIcon(BrandGlyphs.sogou),
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'google',
    name: 'Google',
    host: 'www.google.com',
    icon: TablerSiteIcon(TablerIcons.brand_google),
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'duckduckgo',
    name: 'DuckDuckGo',
    host: 'duckduckgo.com',
    icon: BrandSiteIcon(BrandGlyphs.duckDuckGo),
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'wikipedia',
    name: '维基百科',
    host: 'zh.wikipedia.org',
    icon: TablerSiteIcon(TablerIcons.brand_wikipedia),
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'taobao',
    name: '淘宝',
    host: 'www.taobao.com',
    icon: BrandSiteIcon(BrandGlyphs.taobao),
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'tmall',
    name: '天猫',
    host: 'www.tmall.com',
    icon: BrandSiteIcon(BrandGlyphs.tmall),
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'jd',
    name: '京东',
    host: 'www.jd.com',
    icon: BrandSiteIcon(BrandGlyphs.jd),
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'pinduoduo',
    name: '拼多多',
    host: 'www.pinduoduo.com',
    icon: BrandSiteIcon(BrandGlyphs.pinduoduo),
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'meituan',
    name: '美团',
    host: 'www.meituan.com',
    icon: BrandSiteIcon(BrandGlyphs.meituan),
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'dianping',
    name: '大众点评',
    host: 'www.dianping.com',
    icon: BrandSiteIcon(BrandGlyphs.dianping),
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'ctrip',
    name: '携程',
    host: 'www.ctrip.com',
    icon: BrandSiteIcon(BrandGlyphs.ctrip),
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'aliexpress',
    name: 'AliExpress',
    host: 'www.aliexpress.com',
    icon: BrandSiteIcon(BrandGlyphs.aliexpress),
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'bilibili',
    name: '哔哩哔哩',
    host: 'www.bilibili.com',
    icon: TablerSiteIcon(TablerIcons.brand_bilibili),
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'douyin',
    name: '抖音',
    host: 'www.douyin.com',
    icon: BrandSiteIcon(BrandGlyphs.douyin),
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'kuaishou',
    name: '快手',
    host: 'www.kuaishou.com',
    icon: BrandSiteIcon(BrandGlyphs.kuaishou),
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'iqiyi',
    name: '爱奇艺',
    host: 'www.iqiyi.com',
    icon: BrandSiteIcon(BrandGlyphs.iqiyi),
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'youku',
    name: '优酷',
    host: 'www.youku.com',
    icon: BrandSiteIcon(BrandGlyphs.youku),
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'youtube',
    name: 'YouTube',
    host: 'www.youtube.com',
    icon: TablerSiteIcon(TablerIcons.brand_youtube),
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'netflix',
    name: 'Netflix',
    host: 'www.netflix.com',
    icon: TablerSiteIcon(TablerIcons.brand_netflix),
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'twitch',
    name: 'Twitch',
    host: 'www.twitch.tv',
    icon: TablerSiteIcon(TablerIcons.brand_twitch),
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'netease',
    name: '网易云音乐',
    host: 'music.163.com',
    icon: BrandSiteIcon(BrandGlyphs.neteaseMusic),
    category: SiteCategory.music,
  ),
  SiteLatencyTarget(
    id: 'spotify',
    name: 'Spotify',
    host: 'www.spotify.com',
    icon: TablerSiteIcon(TablerIcons.brand_spotify),
    category: SiteCategory.music,
  ),
  SiteLatencyTarget(
    id: 'soundcloud',
    name: 'SoundCloud',
    host: 'soundcloud.com',
    icon: TablerSiteIcon(TablerIcons.brand_soundcloud),
    category: SiteCategory.music,
  ),
  SiteLatencyTarget(
    id: 'weibo',
    name: '微博',
    host: 'weibo.com',
    icon: TablerSiteIcon(TablerIcons.brand_weibo),
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'wechat',
    name: '微信',
    host: 'weixin.qq.com',
    icon: TablerSiteIcon(TablerIcons.brand_wechat),
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'qq',
    name: 'QQ',
    host: 'im.qq.com',
    icon: TablerSiteIcon(TablerIcons.brand_qq),
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'xiaohongshu',
    name: '小红书',
    host: 'www.xiaohongshu.com',
    icon: BrandSiteIcon(BrandGlyphs.xiaohongshu),
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'zhihu',
    name: '知乎',
    host: 'www.zhihu.com',
    icon: TablerSiteIcon(TablerIcons.brand_zhihu),
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'douban',
    name: '豆瓣',
    host: 'www.douban.com',
    icon: TablerSiteIcon(TablerIcons.brand_douban),
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'toutiao',
    name: '今日头条',
    host: 'www.toutiao.com',
    icon: BrandSiteIcon(BrandGlyphs.toutiao),
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'github',
    name: 'GitHub',
    host: 'github.com',
    icon: TablerSiteIcon(TablerIcons.brand_github),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'gitlab',
    name: 'GitLab',
    host: 'gitlab.com',
    icon: TablerSiteIcon(TablerIcons.brand_gitlab),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'gitee',
    name: 'Gitee',
    host: 'gitee.com',
    icon: BrandSiteIcon(BrandGlyphs.gitee),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'v2ex',
    name: 'V2EX',
    host: 'www.v2ex.com',
    icon: BrandSiteIcon(BrandGlyphs.v2ex),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'juejin',
    name: '掘金',
    host: 'juejin.cn',
    icon: TablerSiteIcon(TablerIcons.brand_juejin),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'csdn',
    name: 'CSDN',
    host: 'www.csdn.net',
    icon: BrandSiteIcon(BrandGlyphs.csdn),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'stackoverflow',
    name: 'Stack Overflow',
    host: 'stackoverflow.com',
    icon: TablerSiteIcon(TablerIcons.brand_stackoverflow),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'npm',
    name: 'npm',
    host: 'registry.npmjs.org',
    icon: TablerSiteIcon(TablerIcons.brand_npm),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'docker',
    name: 'Docker',
    host: 'hub.docker.com',
    icon: TablerSiteIcon(TablerIcons.brand_docker),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'cloudflare',
    name: 'Cloudflare',
    host: 'www.cloudflare.com',
    icon: TablerSiteIcon(TablerIcons.brand_cloudflare),
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'steam',
    name: 'Steam',
    host: 'store.steampowered.com',
    icon: TablerSiteIcon(TablerIcons.brand_steam),
    category: SiteCategory.game,
  ),
  SiteLatencyTarget(
    id: 'epicgames',
    name: 'Epic Games',
    host: 'www.epicgames.com',
    icon: BrandSiteIcon(BrandGlyphs.epicGames),
    category: SiteCategory.game,
  ),
  SiteLatencyTarget(
    id: 'mihoyo',
    name: '米哈游',
    host: 'www.mihoyo.com',
    icon: BrandSiteIcon(BrandGlyphs.mihoyo),
    category: SiteCategory.game,
  ),
];

final Set<String> siteLatencyIds = {for (final t in siteLatencyTargets) t.id};

SiteLatencyTarget? siteLatencyById(String id) {
  for (final target in siteLatencyTargets) {
    if (target.id == id) {
      return target;
    }
  }
  return null;
}

List<SiteLatencyTarget> siteLatencyInCategory(SiteCategory category) => [
  for (final target in siteLatencyTargets)
    if (target.category == category) target,
];

List<SiteLatencyTarget> resolveDashboardSites(Iterable<String> ids) {
  final picked = <SiteLatencyTarget>[];
  for (final id in ids) {
    final target = siteLatencyById(id);
    if (target != null && !picked.contains(target)) {
      picked.add(target);
    }
  }
  if (picked.isEmpty) {
    return resolveDashboardSites(defaultDashboardSiteIds);
  }
  return picked.take(dashboardSiteCount).toList();
}
