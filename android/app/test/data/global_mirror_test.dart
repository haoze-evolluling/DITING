// Global mirror in the subscription fetcher: rows without their own template go through it and
// always fall back to direct, so a dead mirror never breaks an update.

import 'dart:io';

import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/subscriptions/subscription_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  late List<String> seenPaths;

  setUp(() async {
    seenPaths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seenPaths.add(request.uri.path);
      request.response.write('example.com\n');
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  SubscriptionRecord record({String? mirror, bool fallback = false}) =>
      SubscriptionRecord(
        id: 1,
        url: 'http://127.0.0.1:${server.port}/rules.txt',
        name: 'r',
        sourceType: SubscriptionSourceType.remote,
        kind: SubscriptionKind.domain,
        enabled: true,
        ruleCount: 0,
        lastUpdated: 0,
        addedAt: 0,
        importState: SubscriptionImportState.ready,
        lastAttemptAt: 0,
        consecutiveFailureCount: 0,
        mirrorTemplate: mirror,
        mirrorFallback: fallback,
      );

  test('无自有模板时走全局镜像', () async {
    final result = await HttpSubscriptionFetcher(
      globalMirrorTemplate: 'http://127.0.0.1:${server.port}/g/{url}',
    ).fetch(record());
    expect(result.isSuccess, isTrue);
    expect(result.usedMirror, isTrue);
    expect(seenPaths.single, startsWith('/g/'));
  });

  test('全局镜像失败时总是回退直连', () async {
    final result = await HttpSubscriptionFetcher(
      globalMirrorTemplate: 'http://127.0.0.1:1/{url}',
    ).fetch(record());
    expect(result.isSuccess, isTrue);
    expect(seenPaths.single, '/rules.txt');
  });

  test('自有模板优先于全局镜像', () async {
    final result = await HttpSubscriptionFetcher(
      globalMirrorTemplate: 'http://127.0.0.1:${server.port}/g/{url}',
    ).fetch(record(mirror: 'http://127.0.0.1:${server.port}/own/{url}'));
    expect(result.isSuccess, isTrue);
    expect(seenPaths.single, startsWith('/own/'));
  });

  test('自有模板关闭回退时，失败不改用直连', () async {
    final result = await HttpSubscriptionFetcher(
      globalMirrorTemplate: 'http://127.0.0.1:${server.port}/g/{url}',
    ).fetch(record(mirror: 'http://127.0.0.1:1/{url}'));
    expect(result.isFailure, isTrue);
    expect(seenPaths, isEmpty);
  });
}
