library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final installedAppsSourceProvider = Provider<InstalledAppsSource>(
  (ref) => const EmptyInstalledAppsSource(),
);

class InstalledAppsSnapshot {
  const InstalledAppsSnapshot({required this.apps, this.error});

  const InstalledAppsSnapshot.empty([this.error]) : apps = const [];

  final List<InstalledApp> apps;

  final String? error;

  Set<String> get packageNames => {for (final app in apps) app.packageName};
}

class InstalledAppsRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final installedAppsRevisionProvider =
    NotifierProvider<InstalledAppsRevision, int>(InstalledAppsRevision.new);

final installedAppsProvider = FutureProvider<InstalledAppsSnapshot>((
  ref,
) async {
  ref.watch(installedAppsRevisionProvider);
  final source = ref.watch(installedAppsSourceProvider);
  try {
    final apps = await source.list();
    return InstalledAppsSnapshot(
      apps: [...apps]..sort(AppListSort.labelAsc.compare),
    );
  } on MissingPluginException catch (error) {
    return InstalledAppsSnapshot.empty(
      currentL10n.appListChannelUnavailable(
        error.message ?? currentL10n.appListNotRegistered,
      ),
    );
  } on PlatformException catch (error) {
    return InstalledAppsSnapshot.empty(_describe(error));
  }
});

final installedAppListProvider = Provider<List<InstalledApp>?>((ref) {
  return ref.watch(installedAppsProvider).value?.apps;
});

const appIconBatchSize = 24;

const maxCachedAppIcons = 240;

class AppIconsNotifier extends Notifier<Map<String, Uint8List>> {
  final Map<String, Uint8List> _icons = <String, Uint8List>{};

  final Set<String> _queued = <String>{};

  final Set<String> _inFlight = <String>{};

  bool _draining = false;
  bool _scheduled = false;

  @override
  Map<String, Uint8List> build() {
    ref.onDispose(() {
      _icons.clear();
      _queued.clear();
      _inFlight.clear();
    });
    return const {};
  }

  void request(Iterable<String> packages) {
    var added = false;
    for (final name in packages) {
      if (name.isEmpty || _inFlight.contains(name)) continue;
      final cached = _icons.remove(name);
      if (cached != null) {
        _icons[name] = cached;
        continue;
      }
      if (_queued.add(name)) added = true;
    }
    if (!added || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final source = ref.read(installedAppsSourceProvider);
      while (_queued.isNotEmpty && ref.mounted) {
        final batch = _queued.take(appIconBatchSize).toList();
        _queued.removeAll(batch);
        _inFlight.addAll(batch);
        Map<String, Uint8List> loaded;
        try {
          loaded = await source.loadIcons(batch);
        } on MissingPluginException {
          return;
        } on PlatformException {
          loaded = const {};
        } finally {
          _inFlight.removeAll(batch);
        }
        if (!ref.mounted) return;
        if (loaded.isEmpty) continue;
        for (final entry in loaded.entries) {
          _icons.remove(entry.key);
          _icons[entry.key] = entry.value;
        }
        _evict();
        state = Map<String, Uint8List>.unmodifiable(_icons);
      }
    } finally {
      _draining = false;
    }
  }

  void _evict() {
    while (_icons.length > maxCachedAppIcons) {
      _icons.remove(_icons.keys.first);
    }
  }
}

final appIconsProvider =
    NotifierProvider<AppIconsNotifier, Map<String, Uint8List>>(
      AppIconsNotifier.new,
    );

Future<Map<String, int>> resolveInstalledUids(
  InstalledAppsSource source,
  Iterable<String> packages,
) async {
  try {
    return await source.resolveUids(packages);
  } on MissingPluginException {
    return const {};
  } on PlatformException {
    return const {};
  }
}

String _describe(PlatformException error) {
  final message = (error.message ?? '').trim();
  return message.isEmpty
      ? currentL10n.appListReadFailedCode(error.code)
      : currentL10n.appListReadFailed(message);
}

enum AppListFilter {
  all('ALL'),
  system('SYSTEM'),
  user('USER'),
  selected('SELECTED');

  const AppListFilter(this.storageValue);

  final String storageValue;

  String label(AppL10n l10n) => switch (this) {
    AppListFilter.all => l10n.appListFilterAll,
    AppListFilter.system => l10n.appListFilterSystem,
    AppListFilter.user => l10n.appListFilterUser,
    AppListFilter.selected => l10n.appListFilterSelected,
  };

  static AppListFilter fromStorageValue(String? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => AppListFilter.user,
  );

  bool accept(InstalledApp app, Set<String> selected) => switch (this) {
    AppListFilter.all => true,
    AppListFilter.system => app.isSystem,
    AppListFilter.user => !app.isSystem,
    AppListFilter.selected => selected.contains(app.packageName),
  };
}

enum AppListSort {
  labelAsc('LABEL_ASC'),
  labelDesc('LABEL_DESC'),
  packageAsc('PACKAGE_ASC'),
  packageDesc('PACKAGE_DESC');

  const AppListSort(this.storageValue);

  final String storageValue;

  String label(AppL10n l10n) => switch (this) {
    AppListSort.labelAsc => l10n.appListSortLabelAsc,
    AppListSort.labelDesc => l10n.appListSortLabelDesc,
    AppListSort.packageAsc => l10n.appListSortPackageAsc,
    AppListSort.packageDesc => l10n.appListSortPackageDesc,
  };

  static AppListSort fromStorageValue(String? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => AppListSort.labelAsc,
  );

  int compare(InstalledApp a, InstalledApp b) {
    return switch (this) {
      AppListSort.labelAsc => _labelAsc(a, b, false),
      AppListSort.labelDesc => _labelAsc(a, b, true),
      AppListSort.packageAsc => _packageAsc(a, b, false),
      AppListSort.packageDesc => _packageAsc(a, b, true),
    };
  }

  static int _labelAsc(InstalledApp a, InstalledApp b, bool descending) {
    final verdict = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    if (verdict != 0) {
      return descending ? -verdict : verdict;
    }
    return a.packageName.compareTo(b.packageName);
  }

  static int _packageAsc(InstalledApp a, InstalledApp b, bool descending) {
    final verdict = a.packageName.toLowerCase().compareTo(
      b.packageName.toLowerCase(),
    );
    return descending ? -verdict : verdict;
  }
}

List<InstalledApp> visibleInstalledApps({
  required List<InstalledApp> apps,
  required String query,
  required AppListFilter filter,
  required AppListSort sort,
  required Set<String> selected,
}) {
  final needle = query.trim().toLowerCase();
  return [
    for (final app in apps)
      if (filter.accept(app, selected) && app.matches(needle)) app,
  ]..sort(sort.compare);
}
