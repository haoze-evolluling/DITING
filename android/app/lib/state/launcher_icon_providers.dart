/// Launcher icon style state and its labels.
///
/// The choice is mirrored into legacy preferences so the appearance page can show the selected
/// tile synchronously and the app can restore it after an update reset the component flags. The
/// authoritative switch still happens in `LauncherIconBridge` (activity-alias enable/disable).
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/launcher_icon_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

extension LauncherIconStyleLabels on LauncherIconStyle {
  String label(AppL10n l10n) => switch (this) {
    LauncherIconStyle.standard => l10n.launcherIconDefault,
    LauncherIconStyle.adguard => l10n.launcherIconAdguard,
  };

  String description(AppL10n l10n) => switch (this) {
    LauncherIconStyle.standard => l10n.launcherIconDefaultDescription,
    LauncherIconStyle.adguard => l10n.launcherIconAdguardDescription,
  };
}

class LauncherIconNotifier extends Notifier<LauncherIconStyle> {
  @override
  LauncherIconStyle build() => LauncherIconStyle.fromStorageValue(
    ref.watch(legacySettingsProvider).launcherIconStyleRaw,
  );

  /// Persists the choice first (so it survives even if the platform call fails) and then asks the
  /// platform to switch the launcher entry. False means the switch was rejected, but the tile
  /// still reflects the user's pick so they can retry.
  Future<bool> select(LauncherIconStyle style) async {
    state = style;
    ref.read(legacySettingsProvider).setLauncherIconStyleRaw(style.storageValue);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
    return ref.read(launcherIconBridgeProvider).apply(style);
  }
}

final launcherIconProvider =
    NotifierProvider<LauncherIconNotifier, LauncherIconStyle>(
      LauncherIconNotifier.new,
    );

/// Re-applies the persisted style on launch. Idempotent: it reads the platform's current alias and
/// only writes when they differ, so a normal start makes no PackageManager changes.
Future<void> reconcileLauncherIcon(
  LauncherIconBridge bridge,
  String storedRaw,
) async {
  final desired = LauncherIconStyle.fromStorageValue(storedRaw);
  final current = await bridge.current();
  if (current != desired) {
    await bridge.apply(desired);
  }
}
