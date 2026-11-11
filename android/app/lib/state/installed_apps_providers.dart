/// The installed-app inventory every picker shares; a platform error degrades to an empty list,
/// never a throw.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in `main()`; the default gives an honest "no apps" page on non-Android hosts.
final installedAppsSourceProvider = Provider<InstalledAppsSource>(
  (ref) => const EmptyInstalledAppsSource(),
);

class InstalledAppsSnapshot {
  const InstalledAppsSnapshot({required this.apps, this.error});

  const InstalledAppsSnapshot.empty([this.error]) : apps = const [];

  /// Sorted by label (`AppListSort.LABEL_ASC`, the 1.4.3 default).
  final List<InstalledApp> apps;

  /// Non-null when enumeration failed; the picker shows the reason instead of "no apps".
  final String? error;

  /// Fast membership test for the outbound-proxy validator, which runs on every key stroke.
  Set<String> get packageNames => {for (final app in apps) app.packageName};
}

/// Bumpable revision for manual refresh; an app installed while a picker is open is rare enough.
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
    // Sort here: ordering belongs to `InstalledAppsSnapshot`, so no source can hand pages an
    // unordered list.
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

/// Convenience for pages that only need the list (null while loading).
final installedAppListProvider = Provider<List<InstalledApp>?>((ref) {
  return ref.watch(installedAppsProvider).value?.apps;
});

/// Icons asked for per channel call. Small batches keep each message (and the decode it causes on
/// the UI isolate) short and let rows fill in as batches land, instead of the whole list waiting
/// for one call that carries hundreds of PNGs.
const appIconBatchSize = 24;

/// Upper bound on icons held in memory. Only packages that were actually drawn are ever fetched,
/// so this is a safety net for a long session (scrolling every picker) rather than a working set:
/// at 192 px a PNG averages ~30 KB, so 240 entries stay under ~8 MB.
const maxCachedAppIcons = 240;

/// Package name to encoded launcher icon, fetched only when a row actually draws one.
///
/// Nothing prefetches the inventory: reading this provider for the whole installed list used to
/// mmap every installed APK into the process (400+ `Resources` objects) right after startup, which
/// pushed PSS past 700 MB before the user had opened a single picker. Widgets ask for the packages
/// they are about to paint via [AppIconsNotifier.request]; the cache is LRU-bounded by request
/// order so a long session cannot grow it without limit.
///
/// A missing entry renders as a placeholder glyph, so rows never wait on the platform.
class AppIconsNotifier extends Notifier<Map<String, Uint8List>> {
  /// Access-ordered: re-inserting on request makes iteration order "least recently asked for".
  final Map<String, Uint8List> _icons = <String, Uint8List>{};

  /// Requested but not handed to the platform yet.
  final Set<String> _queued = <String>{};

  /// Handed to the platform, awaiting a reply; must not be queued again.
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

  /// Asks for these icons. Safe to call from `initState` / `didUpdateWidget`: repeats and already
  /// cached packages are dropped, and every request in one frame is coalesced into a single batch
  /// run so a list of 20 rows does not fire 20 channel calls.
  void request(Iterable<String> packages) {
    var added = false;
    for (final name in packages) {
      if (name.isEmpty || _inFlight.contains(name)) continue;
      final cached = _icons.remove(name);
      if (cached != null) {
        // Touch: keep it, and move it to the young end of the LRU order.
        _icons[name] = cached;
        continue;
      }
      if (_queued.add(name)) added = true;
    }
    if (!added || _scheduled) return;
    _scheduled = true;
    // After the frame: `request` is called from build-phase `initState`, and a synchronous
    // channel call there would reenter the framework.
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(_drain());
    });
  }

  /// Reads the icon without scheduling a fetch; `null` means "not here (yet)".
  Uint8List? iconOf(String packageName) => _icons[packageName];

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
          // One unreadable batch must not strand the rest of the queue.
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

  /// Drops the oldest requests once the ceiling is passed. A row still on screen re-requests on
  /// its next build, so an eviction costs one channel round trip, never a permanent placeholder.
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

/// Resolves package names to engine UIDs; uninstalled packages are absent rather than -1, so
/// callers drop them.
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

/// 1.4.3 `AppListFilter` in declaration order; an unknown `storageValue` falls back to [user].
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

/// 1.4.3 `AppListSort` with the same storage values; labels compare lowercased, then by package.
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
    // The tie-break stays ascending in both directions, as in 1.4.3.
    return a.packageName.compareTo(b.packageName);
  }

  static int _packageAsc(InstalledApp a, InstalledApp b, bool descending) {
    final verdict = a.packageName.toLowerCase().compareTo(
      b.packageName.toLowerCase(),
    );
    return descending ? -verdict : verdict;
  }
}

/// Query, filter and sort in one place so every picker filters identically.
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
