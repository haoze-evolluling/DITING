/// Dart side of `com.haoze.diting/apps`: installed-app inventory, read-only, selection state in
/// `SharedPreferences`. The migrated Manifest dropped `QUERY_ALL_PACKAGES`, so this channel
/// restores the real list.
library;

import 'package:flutter/services.dart';

const appsChannelName = 'com.haoze.diting/apps';

/// Launcher icons are encoded as PNG at this many pixels per side; 192 px covers a 48 dp tile on a
/// 4x screen with a little headroom.
const appsIconPixels = 192;

class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    required this.isSystem,
    required this.uid,
  });

  final String packageName;
  final String label;

  /// From `AppListFilter.SYSTEM`; pickers offer USER / SYSTEM / ALL / SELECTED.
  final bool isSystem;

  /// Resolves names to UIDs with `getPackageUid`, since the engine needs UIDs (`setBlockedUIDs`,
  /// `setMitmAllowedUIDs`); one round trip instead of one per toggle.
  final int uid;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final needle = query.toLowerCase();
    return label.toLowerCase().contains(needle) ||
        packageName.toLowerCase().contains(needle);
  }

  static InstalledApp fromMap(Map<Object?, Object?> map) => InstalledApp(
    packageName: map['packageName'] as String? ?? '',
    label: map['label'] as String? ?? '',
    isSystem: map['isSystem'] == true,
    uid: (map['uid'] as num?)?.toInt() ?? -1,
  );
}

abstract class InstalledAppsSource {
  Future<List<InstalledApp>> list();

  /// Package name to UID; missing packages are absent rather than -1, so callers can drop
  /// uninstalled selections.
  Future<Map<String, int>> resolveUids(Iterable<String> packages);

  /// True when [packageName] is this app. Blocking or proxying our own UID would cut the tunnel's
  /// control plane.
  Future<bool> isSelf(String packageName);

  /// Package name to encoded launcher icon (PNG). Missing entries mean "no icon available", which
  /// the UI renders as a placeholder glyph. Batched so a list refresh is one channel round trip.
  Future<Map<String, Uint8List>> loadIcons(Iterable<String> packages);
}

class MethodChannelInstalledAppsSource implements InstalledAppsSource {
  MethodChannelInstalledAppsSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(appsChannelName);

  final MethodChannel _channel;

  @override
  Future<List<InstalledApp>> list() async {
    final raw = await _channel.invokeMethod<Object?>('listInstalled');
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) InstalledApp.fromMap(Map<Object?, Object?>.from(item)),
    ]..sort((a, b) => a.label.compareTo(b.label));
  }

  @override
  Future<Map<String, int>> resolveUids(Iterable<String> packages) async {
    final values = packages.toList();
    if (values.isEmpty) return const {};
    final raw = await _channel.invokeMethod<Object?>('resolveUids', {
      'packages': values,
    });
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    };
  }

  @override
  Future<bool> isSelf(String packageName) async =>
      await _channel.invokeMethod<bool>('isSelf', {
        'packageName': packageName,
      }) ??
      false;

  @override
  Future<Map<String, Uint8List>> loadIcons(Iterable<String> packages) async {
    final values = packages.toList();
    if (values.isEmpty) return const {};
    final raw = await _channel.invokeMethod<Object?>('loadIcons', {
      'packages': values,
      'size': appsIconPixels,
    });
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is Uint8List)
          entry.key as String: entry.value as Uint8List,
    };
  }
}

/// Empty device for widget tests and non-Android hosts, keeping pickers in their "no apps" state
/// instead of crashing.
class EmptyInstalledAppsSource implements InstalledAppsSource {
  const EmptyInstalledAppsSource();

  @override
  Future<List<InstalledApp>> list() async => const [];

  @override
  Future<Map<String, int>> resolveUids(Iterable<String> packages) async =>
      const {};

  @override
  Future<bool> isSelf(String packageName) async => false;

  @override
  Future<Map<String, Uint8List>> loadIcons(Iterable<String> packages) async =>
      const {};
}
