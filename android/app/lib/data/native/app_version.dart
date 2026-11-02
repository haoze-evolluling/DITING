/// App version, sourced only from `pubspec.yaml` through `versionInfo`; hosts without the channel
/// fall back to reading `pubspec.yaml` from the working directory.
library;

import 'dart:io';

import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Installed version: [name] is the display name, [code] the Android versionCode.
@immutable
class AppVersion {
  const AppVersion({required this.name, required this.code});

  /// Placeholder when neither source answers; the update check then sees every release as newer,
  /// which beats showing a fake version.
  static const unknown = AppVersion(name: '0.0.0', code: 0);

  final String name;

  final int code;

  /// Parses `version: 1.2.3+10203`; a missing build number counts as 1, null means there is no
  /// usable `version:` line.
  static AppVersion? parse(String pubspec) {
    final match = RegExp(
      r'^version:\s*([^\s+#]+)(?:\+(\d+))?',
      multiLine: true,
    ).firstMatch(pubspec);
    if (match == null) return null;
    final name = match.group(1)!.trim();
    if (name.isEmpty) return null;
    final code = int.tryParse(match.group(2) ?? '') ?? 1;
    return AppVersion(name: name, code: code);
  }

  static AppVersion? fromPubspec() {
    try {
      return parse(File('pubspec.yaml').readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && other.name == name && other.code == code;

  @override
  int get hashCode => Object.hash(name, code);

  @override
  String toString() => '$name+$code';
}

/// Reads the installed package info, falling back to the working-directory `pubspec.yaml`; a
/// failure must not break the first frame, so [AppVersion.unknown] is returned.
Future<AppVersion> loadAppVersion({
  MethodChannel channel = legacyPrefsChannel,
}) async {
  try {
    final raw = await channel.invokeMethod<Map<Object?, Object?>>(
      'versionInfo',
    );
    final name = '${raw?['name'] ?? ''}'.trim();
    final code = (raw?['code'] as num?)?.toInt();
    if (name.isNotEmpty && code != null) {
      return AppVersion(name: name, code: code);
    }
  } on MissingPluginException {
    // Not an Android host (test, desktop, very early start): fall through.
  } on PlatformException catch (error) {
    debugPrint('versionInfo read failed: $error');
  }
  return AppVersion.fromPubspec() ?? AppVersion.unknown;
}
