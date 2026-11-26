library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/native/launcher_icon_bridge.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
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
