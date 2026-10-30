// Release checking and the auto-update schedule: a mistake silently never updates or
// re-downloads on every foreground.

import 'dart:convert';
import 'dart:io';

import 'package:diting/data/db/subscription_models.dart';
import 'package:diting/data/update/app_update_checker.dart';
import 'package:diting/state/auto_update_runner.dart';
import 'package:diting/state/auto_update_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('版本检查', _updateChecker);
  group('订阅自动更新', _autoUpdate);
}

/// Pins the update check against a real HTTP server and 1.4.3's parsing rules.
void _updateChecker() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `flutter_test` installs an HttpOverrides answering 400; this file uses a loopback server
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  late String url;

  /// Status and body the fake GitHub endpoint should return.
  late int status;
  late String body;
  late List<String?> seenUserAgents;
  late List<String> seenPaths;

  setUp(() async {
    status = 200;
    body = '{}';
    seenUserAgents = [];
    seenPaths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/releases/latest';
    server.listen((request) async {
      seenUserAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
      seenPaths.add(request.uri.path);
      await utf8.decoder.bind(request).join();
      request.response.statusCode = status;
      request.response.write(body);
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  AppUpdateChecker checker() => AppUpdateChecker(releaseUrl: url);

  String release({
    required String tag,
    String? assetName,
    String? downloadUrl,
    String notes = '',
    bool withAssets = true,
  }) => jsonEncode({
    'tag_name': tag,
    'body': notes,
    'assets': withAssets
        ? [
            {
              'name': assetName ?? 'diting-$tag-arm64-v8a.apk',
              'browser_download_url':
                  downloadUrl ?? 'https://example.test/diting-$tag.apk',
            },
          ]
        : <Object>[],
  });

  group('版本比较（旧版 isNewerVersion）', () {
    test('逐段整数比较，不是字符串比较', () {
      // String comparison puts "1.4.10" below "1.4.9".
      expect(AppUpdateChecker.isNewerVersion('1.4.10', '1.4.9'), isTrue);
      expect(AppUpdateChecker.isNewerVersion('1.4.9', '1.4.10'), isFalse);
    });

    test('段数不同时缺失段按 0 处理', () {
      expect(AppUpdateChecker.isNewerVersion('1.5', '1.4.4'), isTrue);
      expect(AppUpdateChecker.isNewerVersion('1.4.4.1', '1.4.4'), isTrue);
      expect(AppUpdateChecker.isNewerVersion('1.4', '1.4.0'), isFalse);
    });

    test('看不懂的版本号不当作更新', () {
      // Better to report no update than to treat an unparseable tag as one.
      expect(AppUpdateChecker.isNewerVersion('latest', '1.4.4'), isFalse);
      expect(AppUpdateChecker.isNewerVersion('1.4.x', '1.4.4'), isFalse);
      expect(AppUpdateChecker.isNewerVersion('', '1.4.4'), isFalse);
    });
  });

  group('解析', () {
    test('更高版本返回 available，带版本/地址/说明', () {
      final result = AppUpdateChecker.parseLatestRelease(
        release(
          tag: 'v1.4.5',
          assetName: 'DITING-1.4.5-arm64-v8a.apk',
          downloadUrl: 'https://example.test/a.apk',
          notes: '- 修复若干问题',
        ),
        '1.4.4',
      );
      expect(result.hasUpdate, isTrue);
      final info = result.info!;
      expect(info.version, '1.4.5');
      expect(info.fileName, 'DITING-1.4.5-arm64-v8a.apk');
      expect(info.downloadUrl, 'https://example.test/a.apk');
      expect(info.releaseNotes, '- 修复若干问题');
    });

    test('相同或更低版本返回 upToDate', () {
      final same = AppUpdateChecker.parseLatestRelease(
        release(tag: 'v1.4.4'),
        '1.4.4',
      );
      expect(same.hasUpdate, isFalse);
      expect(same.failed, isFalse);
      expect(same.currentVersion, '1.4.4');

      final older = AppUpdateChecker.parseLatestRelease(
        release(tag: 'v1.4.3'),
        '1.4.4',
      );
      expect(older.hasUpdate, isFalse);
      expect(older.failed, isFalse);
    });

    test('优先挑 arm64-v8a 资产', () {
      final payload = jsonEncode({
        'tag_name': 'v2.0.0',
        'assets': [
          {
            'name': 'diting-universal.apk',
            'browser_download_url': 'https://example.test/u.apk',
          },
          {
            'name': 'diting-arm64-v8a.apk',
            'browser_download_url': 'https://example.test/a.apk',
          },
        ],
      });
      final result = AppUpdateChecker.parseLatestRelease(payload, '1.0.0');
      expect(result.info!.downloadUrl, 'https://example.test/a.apk');
    });

    test('没有 arm64 资产时回落到任意 apk', () {
      final payload = jsonEncode({
        'tag_name': 'v2.0.0',
        'assets': [
          {
            'name': 'notes.txt',
            'browser_download_url': 'https://example.test/n.txt',
          },
          {
            'name': 'diting-universal.apk',
            'browser_download_url': 'https://example.test/u.apk',
          },
        ],
      });
      final result = AppUpdateChecker.parseLatestRelease(payload, '1.0.0');
      expect(result.info!.fileName, 'diting-universal.apk');
    });

    test('没有 apk 资产时报错，而不是猜一个地址', () {
      final payload = jsonEncode({
        'tag_name': 'v2.0.0',
        'assets': [
          {
            'name': 'source.zip',
            'browser_download_url': 'https://example.test/s.zip',
          },
        ],
      });
      final result = AppUpdateChecker.parseLatestRelease(payload, '1.0.0');
      expect(result.hasUpdate, isFalse);
      expect(result.failed, isTrue);
      expect(result.error, contains('APK'));
    });

    test('非法 JSON 报错而不是红屏', () {
      final result = AppUpdateChecker.parseLatestRelease('not json', '1.0.0');
      expect(result.failed, isTrue);
      expect(result.error, contains('JSON'));
    });
  });

  group('HTTP 层', () {
    test('带 User-Agent（GitHub 对无 UA 的请求返回 403）', () async {
      body = release(tag: 'v1.4.5');
      await checker().check('1.4.4');
      expect(seenUserAgents.single, isNotNull);
      expect(seenUserAgents.single, contains('DITING'));
    });

    test('200 + 更高版本 → available', () async {
      body = release(tag: 'v9.9.9');
      final result = await checker().check('1.4.4');
      expect(result.hasUpdate, isTrue);
      expect(result.info!.version, '9.9.9');
    });

    test('限流的 403 说清是限流，而不是笼统「返回 403」', () async {
      status = 403;
      body = '{"message":"API rate limit exceeded for 1.2.3.4."}';
      final result = await checker().check('1.4.4');
      expect(result.failed, isTrue);
      expect(result.error, contains('限流'));
    });

    test('非限流的 403 保留状态码', () async {
      status = 403;
      body = '{"message":"forbidden"}';
      final result = await checker().check('1.4.4');
      expect(result.failed, isTrue);
      expect(result.error, contains('403'));
    });

    test('404 指出版本库或发布页不存在', () async {
      status = 404;
      body = '{"message":"Not Found"}';
      final result = await checker().check('1.4.4');
      expect(result.failed, isTrue);
      expect(result.error, contains('404'));
    });

    test('服务器不可达时报告无法连接', () async {
      final result = await AppUpdateChecker(
        releaseUrl: 'http://127.0.0.1:1/releases/latest',
      ).check('1.4.4');
      expect(result.failed, isTrue);
      expect(result.error, contains('无法连接'));
    });

    test('全局镜像：先请求镜像地址', () async {
      body = release(tag: 'v9.9.9');
      final result = await AppUpdateChecker(
        releaseUrl: url,
        mirrorTemplate: 'http://127.0.0.1:${server.port}/m/{url}',
      ).check('1.4.4');
      expect(result.hasUpdate, isTrue);
      expect(seenPaths.single, startsWith('/m/'));
    });

    test('全局镜像不可达时回退原始地址', () async {
      body = release(tag: 'v9.9.9');
      final result = await AppUpdateChecker(
        releaseUrl: url,
        mirrorTemplate: 'http://127.0.0.1:1/{url}',
      ).check('1.4.4');
      expect(result.hasUpdate, isTrue);
      expect(seenPaths.single, '/releases/latest');
    });
  });
}

/// Due-time logic for shipping a release; a mistake silently never updates or re-downloads each
/// foreground
void _autoUpdate() {
  SubscriptionRecord record({
    int id = 1,
    int lastAttemptAt = 0,
    bool enabled = true,
    String sourceType = 'remote',
  }) => SubscriptionRecord(
    id: id,
    url: 'https://example.com/$id.yaml',
    name: '订阅 $id',
    sourceType: SubscriptionSourceType.fromStorage(sourceType),
    kind: SubscriptionKind.normalize('normal'),
    enabled: enabled,
    ruleCount: 0,
    lastUpdated: 0,
    addedAt: 0,
    importState: SubscriptionImportState.ready,
    lastAttemptAt: lastAttemptAt,
    consecutiveFailureCount: 0,
    mirrorFallback: true,
  );

  const hour = 3600 * 1000;

  group('isDue', () {
    test('从未尝试过 → 到期', () {
      expect(AutoUpdateRunner.isDue(record(), 24, 1000), isTrue);
    });

    test('刚好满间隔 → 到期（边界含等于）', () {
      final now = 100 * hour;
      expect(
        AutoUpdateRunner.isDue(record(lastAttemptAt: now - 24 * hour), 24, now),
        isTrue,
      );
    });

    test('间隔按设置变化，不是写死 24 小时', () {
      final now = 100 * hour;
      final target = record(lastAttemptAt: now - 7 * hour);
      expect(AutoUpdateRunner.isDue(target, 6, now), isTrue);
      expect(AutoUpdateRunner.isDue(target, 12, now), isFalse);
    });
  });

  group('nextDueAt', () {
    test('取最早到期的那条', () {
      final now = 100 * hour;
      final records = [
        record(id: 1, lastAttemptAt: now - 2 * hour),
        record(id: 2, lastAttemptAt: now - 20 * hour),
        record(id: 3, lastAttemptAt: now - 10 * hour),
      ];
      expect(AutoUpdateRunner.nextDueAt(records, 24, now), now + 4 * hour);
    });

    test('从未尝试的订阅立即到期（返回 now）', () {
      final now = 100 * hour;
      final records = [
        record(id: 1, lastAttemptAt: now - 1 * hour),
        record(id: 2),
      ];
      expect(AutoUpdateRunner.nextDueAt(records, 24, now), now);
    });
  });

  group('按时刻更新（本地时间）', () {
    int at(int y, int m, int d, int h, [int min = 0]) =>
        DateTime(y, m, d, h, min).millisecondsSinceEpoch;
    AutoUpdatePlan plan(AutoUpdateSchedule schedule, int sinceMs) =>
        AutoUpdatePlan(
          schedule: schedule,
          intervalHours: 24,
          timeMinutes: 4 * 60,
          sinceMs: sinceMs,
        );

    test('每天：时刻已过且之后未尝试 → 到期；尝试过 → 等到明天', () {
      final daily = plan(AutoUpdateSchedule.daily, at(2025, 3, 1, 12));
      final now = at(2025, 3, 3, 9);
      expect(
        daily.isDue(record(lastAttemptAt: at(2025, 3, 2, 5)), now),
        isTrue,
      );
      final fresh = record(lastAttemptAt: at(2025, 3, 3, 4, 1));
      expect(daily.isDue(fresh, now), isFalse);
      expect(daily.nextDueAt([fresh], now), at(2025, 3, 4, 4));
    });

    test('新选的时刻今天已过，不会立刻触发', () {
      final since = at(2025, 3, 3, 12);
      final daily = plan(AutoUpdateSchedule.daily, since);
      final old = record(lastAttemptAt: at(2025, 3, 1, 4));
      expect(daily.isDue(old, since + 60000), isFalse);
      expect(daily.nextDueAt([old], since + 60000), at(2025, 3, 4, 4));
    });

    test('隔天：从设定后的第一个时刻起每两天一次', () {
      final since = at(2025, 3, 3, 12);
      final alternate = plan(AutoUpdateSchedule.everyOtherDay, since);
      // 3 号 04:00 已过，第一个时刻是 4 号，之后是 6 号。
      final ran = record(lastAttemptAt: at(2025, 3, 4, 4, 5));
      expect(alternate.isDue(ran, at(2025, 3, 5, 9)), isFalse);
      expect(alternate.nextDueAt([ran], at(2025, 3, 5, 9)), at(2025, 3, 6, 4));
      expect(alternate.isDue(ran, at(2025, 3, 6, 4, 1)), isTrue);
    });

    test('从未尝试过的订阅照常立即到期', () {
      final daily = plan(AutoUpdateSchedule.daily, at(2025, 3, 3, 12));
      expect(daily.isDue(record(), at(2025, 3, 3, 13)), isTrue);
    });
  });

  test('AutoUpdateRun.didRun 只在没有跳过原因时为真', () {
    expect(const AutoUpdateRun().didRun, isTrue);
    expect(const AutoUpdateRun(summary: '1 个已更新').didRun, isTrue);
    expect(const AutoUpdateRun(skip: AutoUpdateSkip.disabled).didRun, isFalse);
  });
}
