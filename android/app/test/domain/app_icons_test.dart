import 'dart:typed_data';

import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

InstalledApp _app(String name, {bool system = false}) =>
    InstalledApp(packageName: name, label: name, isSystem: system, uid: 1);

class _IconSource implements InstalledAppsSource {
  _IconSource(this.apps);

  List<InstalledApp> apps;
  final calls = <List<String>>[];

  @override
  Future<List<InstalledApp>> list() async => apps;

  @override
  Future<Map<String, int>> resolveUids(Iterable<String> packages) async =>
      const {};

  @override
  Future<bool> isSelf(String packageName) async => false;

  @override
  Future<Map<String, Uint8List>> loadIcons(Iterable<String> packages) async {
    calls.add(packages.toList());
    return {
      for (final name in packages) name: Uint8List.fromList([1]),
    };
  }
}

/// Lets the queued batches finish.
Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _container(_IconSource source) {
  final container = ProviderContainer(
    overrides: [installedAppsSourceProvider.overrideWithValue(source)],
  );
  addTearDown(container.dispose);
  final sub = container.listen(appIconsProvider, (_, _) {});
  addTearDown(sub.close);
  return container;
}

void main() {
  test('只取被请求的图标，不因清单存在就全量预取', () async {
    final source = _IconSource([
      _app('sys.a', system: true),
      for (var i = 0; i < 400; i++) _app('user.$i'),
    ]);
    final container = _container(source);
    await _settle();

    // 清单可用，但没人要求任何图标：一次都不该调用原生。
    expect(source.calls, isEmpty);
    expect(container.read(appIconsProvider), isEmpty);

    container.read(appIconsProvider.notifier).request(['user.7']);
    await _settle();

    expect(source.calls, [
      ['user.7'],
    ]);
    expect(container.read(appIconsProvider).keys, ['user.7']);
  });

  test('同一帧内的请求合并成一批，且不超过单次上限', () async {
    final source = _IconSource([for (var i = 0; i < 200; i++) _app('p.$i')]);
    final container = _container(source);
    final notifier = container.read(appIconsProvider.notifier);

    for (var i = 0; i < 100; i++) {
      notifier.request(['p.$i']);
    }
    await _settle();

    expect(source.calls.every((c) => c.length <= appIconBatchSize), isTrue);
    expect(source.calls.expand((c) => c).toSet(), hasLength(100));
    expect(container.read(appIconsProvider), hasLength(100));
  });

  test('重复请求不重复取，已缓存的不再回源', () async {
    final source = _IconSource([_app('a')]);
    final container = _container(source);
    final notifier = container.read(appIconsProvider.notifier);

    notifier.request(['a']);
    await _settle();
    notifier.request(['a', 'a']);
    await _settle();

    expect(source.calls, [
      ['a'],
    ]);
  });

  test('缓存有上限，超出后淘汰最久未被请求的图标', () async {
    final source = _IconSource([
      for (var i = 0; i < maxCachedAppIcons + 40; i++) _app('q.$i'),
    ]);
    final container = _container(source);
    final notifier = container.read(appIconsProvider.notifier);

    for (var i = 0; i < maxCachedAppIcons + 40; i++) {
      notifier.request(['q.$i']);
    }
    await _settle();

    final icons = container.read(appIconsProvider);
    expect(icons, hasLength(maxCachedAppIcons));
    // 最早请求的已被淘汰，最近请求的一定还在。
    expect(icons.containsKey('q.0'), isFalse);
    expect(icons.containsKey('q.${maxCachedAppIcons + 39}'), isTrue);
  });
}
