library;

import 'dart:io';

import 'package:diting_android/data/errors.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class AppVersion {
  const AppVersion({required this.name, required this.code});

  static const unknown = AppVersion(name: '0.0.0', code: 0);

  final String name;

  final int code;

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
    ignoreError();
  } on PlatformException catch (error) {
    debugPrint('versionInfo read failed: $error');
  }
  return AppVersion.fromPubspec() ?? AppVersion.unknown;
}
