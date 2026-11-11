/// Sites probed by the site-latency card and its detail page. Domains let each CDN map the probe
/// to a nearby node, which is what the card reports.
library;

import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_shared/ui/icons/icons.dart';

class SiteLatencyTarget {
  const SiteLatencyTarget({
    required this.id,
    required this.name,
    required this.host,
    required this.glyph,
    required this.category,
  });

  final String id;

  final String name;

  final String host;

  final Glyph glyph;

  final SiteCategory category;
}

/// The four sites the dashboard card shows unless the user picks others.
const defaultDashboardSiteIds = <String>[
  'baidu',
  'douyin',
  'bilibili',
  'netease',
];

/// Everything the user can put on the card or probe from the detail page.
const siteLatencyTargets = <SiteLatencyTarget>[
  SiteLatencyTarget(
    id: 'baidu',
    name: '百度',
    host: 'www.baidu.com',
    glyph: AppGlyphs.baidu,
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'sogou',
    name: '搜狗',
    host: 'www.sogou.com',
    glyph: AppGlyphs.sogou,
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'google',
    name: 'Google',
    host: 'www.google.com',
    glyph: AppGlyphs.google,
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'duckduckgo',
    name: 'DuckDuckGo',
    host: 'duckduckgo.com',
    glyph: AppGlyphs.duckDuckGo,
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'wikipedia',
    name: '维基百科',
    host: 'zh.wikipedia.org',
    glyph: AppGlyphs.wikipedia,
    category: SiteCategory.search,
  ),
  SiteLatencyTarget(
    id: 'taobao',
    name: '淘宝',
    host: 'www.taobao.com',
    glyph: AppGlyphs.taobao,
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'tmall',
    name: '天猫',
    host: 'www.tmall.com',
    glyph: AppGlyphs.tmall,
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'jd',
    name: '京东',
    host: 'www.jd.com',
    glyph: AppGlyphs.jd,
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'pinduoduo',
    name: '拼多多',
    host: 'www.pinduoduo.com',
    glyph: AppGlyphs.pinduoduo,
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'meituan',
    name: '美团',
    host: 'www.meituan.com',
    glyph: AppGlyphs.meituan,
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'dianping',
    name: '大众点评',
    host: 'www.dianping.com',
    glyph: AppGlyphs.dianping,
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'ctrip',
    name: '携程',
    host: 'www.ctrip.com',
    glyph: AppGlyphs.ctrip,
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'aliexpress',
    name: 'AliExpress',
    host: 'www.aliexpress.com',
    glyph: AppGlyphs.aliexpress,
    category: SiteCategory.shopping,
  ),
  SiteLatencyTarget(
    id: 'bilibili',
    name: '哔哩哔哩',
    host: 'www.bilibili.com',
    glyph: AppGlyphs.bilibili,
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'douyin',
    name: '抖音',
    host: 'www.douyin.com',
    glyph: AppGlyphs.douyin,
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'kuaishou',
    name: '快手',
    host: 'www.kuaishou.com',
    glyph: AppGlyphs.kuaishou,
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'iqiyi',
    name: '爱奇艺',
    host: 'www.iqiyi.com',
    glyph: AppGlyphs.iqiyi,
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'youku',
    name: '优酷',
    host: 'www.youku.com',
    glyph: AppGlyphs.youku,
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'youtube',
    name: 'YouTube',
    host: 'www.youtube.com',
    glyph: AppGlyphs.youtube,
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'netflix',
    name: 'Netflix',
    host: 'www.netflix.com',
    glyph: AppGlyphs.netflix,
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'twitch',
    name: 'Twitch',
    host: 'www.twitch.tv',
    glyph: AppGlyphs.twitch,
    category: SiteCategory.video,
  ),
  SiteLatencyTarget(
    id: 'netease',
    name: '网易云音乐',
    host: 'music.163.com',
    glyph: AppGlyphs.neteaseMusic,
    category: SiteCategory.music,
  ),
  SiteLatencyTarget(
    id: 'spotify',
    name: 'Spotify',
    host: 'www.spotify.com',
    glyph: AppGlyphs.spotify,
    category: SiteCategory.music,
  ),
  SiteLatencyTarget(
    id: 'soundcloud',
    name: 'SoundCloud',
    host: 'soundcloud.com',
    glyph: AppGlyphs.soundcloud,
    category: SiteCategory.music,
  ),
  SiteLatencyTarget(
    id: 'weibo',
    name: '微博',
    host: 'weibo.com',
    glyph: AppGlyphs.weibo,
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'wechat',
    name: '微信',
    host: 'weixin.qq.com',
    glyph: AppGlyphs.wechat,
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'qq',
    name: 'QQ',
    host: 'im.qq.com',
    glyph: AppGlyphs.tencentQq,
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'xiaohongshu',
    name: '小红书',
    host: 'www.xiaohongshu.com',
    glyph: AppGlyphs.xiaohongshu,
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'zhihu',
    name: '知乎',
    host: 'www.zhihu.com',
    glyph: AppGlyphs.zhihu,
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'douban',
    name: '豆瓣',
    host: 'www.douban.com',
    glyph: AppGlyphs.douban,
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'toutiao',
    name: '今日头条',
    host: 'www.toutiao.com',
    glyph: AppGlyphs.toutiao,
    category: SiteCategory.social,
  ),
  SiteLatencyTarget(
    id: 'github',
    name: 'GitHub',
    host: 'github.com',
    glyph: AppGlyphs.github,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'gitlab',
    name: 'GitLab',
    host: 'gitlab.com',
    glyph: AppGlyphs.gitlab,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'gitee',
    name: 'Gitee',
    host: 'gitee.com',
    glyph: AppGlyphs.gitee,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'v2ex',
    name: 'V2EX',
    host: 'www.v2ex.com',
    glyph: AppGlyphs.v2ex,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'juejin',
    name: '掘金',
    host: 'juejin.cn',
    glyph: AppGlyphs.juejin,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'csdn',
    name: 'CSDN',
    host: 'www.csdn.net',
    glyph: AppGlyphs.csdn,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'stackoverflow',
    name: 'Stack Overflow',
    host: 'stackoverflow.com',
    glyph: AppGlyphs.stackOverflow,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'npm',
    name: 'npm',
    host: 'registry.npmjs.org',
    glyph: AppGlyphs.npm,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'docker',
    name: 'Docker',
    host: 'hub.docker.com',
    glyph: AppGlyphs.docker,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'cloudflare',
    name: 'Cloudflare',
    host: 'www.cloudflare.com',
    glyph: AppGlyphs.cloudflare,
    category: SiteCategory.developer,
  ),
  SiteLatencyTarget(
    id: 'steam',
    name: 'Steam',
    host: 'store.steampowered.com',
    glyph: AppGlyphs.steam,
    category: SiteCategory.game,
  ),
  SiteLatencyTarget(
    id: 'epicgames',
    name: 'Epic Games',
    host: 'www.epicgames.com',
    glyph: AppGlyphs.epicGames,
    category: SiteCategory.game,
  ),
  SiteLatencyTarget(
    id: 'mihoyo',
    name: '米哈游',
    host: 'www.mihoyo.com',
    glyph: AppGlyphs.mihoyo,
    category: SiteCategory.game,
  ),
];

/// Every known id, used to drop ids from an older install or a restored backup.
final Set<String> siteLatencyIds = {for (final t in siteLatencyTargets) t.id};

SiteLatencyTarget? siteLatencyById(String id) {
  for (final target in siteLatencyTargets) {
    if (target.id == id) {
      return target;
    }
  }
  return null;
}

/// Targets of one category, in catalog order.
List<SiteLatencyTarget> siteLatencyInCategory(SiteCategory category) => [
  for (final target in siteLatencyTargets)
    if (target.category == category) target,
];

/// The card's slots: unknown ids and duplicates drop, and nothing is padded — a card the user
/// trimmed to two sites draws two cells rather than silently refilling the empty slots.
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
