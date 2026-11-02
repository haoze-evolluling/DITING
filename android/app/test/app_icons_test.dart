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

/// Lets the inventory load and every queued batch finish.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('分批取图标，用户应用优先，超过原生单次上限的应用也有图标', () async {
    final source = _IconSource([
      _app('sys.a', system: true),
      for (var i = 0; i < 450; i++) _app('user.$i'),
    ]);
    final container = ProviderContainer(
      overrides: [installedAppsSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(appIconsProvider, (_, _) {});
    addTearDown(sub.close);

    await _settle();

    expect(source.calls.every((c) => c.length <= appIconBatchSize), isTrue);
    expect(source.calls.first.first, startsWith('user.'));
    expect(source.calls.last.last, 'sys.a');
    expect(container.read(appIconsProvider), hasLength(451));
  });

  test('应用清单刷新后保留已有图标，只取新安装的应用', () async {
    final source = _IconSource([_app('a'), _app('b')]);
    final container = ProviderContainer(
      overrides: [installedAppsSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(appIconsProvider, (_, _) {});
    addTearDown(sub.close);
    await _settle();
    source.calls.clear();

    source.apps = [_app('a'), _app('b'), _app('c')];
    container.read(installedAppsRevisionProvider.notifier).bump();
    await _settle();

    expect(source.calls, [
      ['c'],
    ]);
    expect(container.read(appIconsProvider).keys, containsAll(['a', 'b', 'c']));
  });
}
