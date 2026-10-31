/// Dart side of `com.haoze.diting/platform`: recents hiding, battery-optimization allowlist, crash
/// logs and text export. Notification settings bypass this channel.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/native/process_memory.dart';
import 'package:flutter/services.dart';

const platformChannelName = 'com.haoze.diting/platform';

/// Every method returns "unavailable" instead of throwing when the channel is missing, and every
/// caller has a degraded state for it.
class PlatformBridge {
  PlatformBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(platformChannelName);

  final MethodChannel _channel;

  /// Applies `excludeFromRecents` to every task of this app. False means no task list yet, not a
  /// failure: the value is persisted and reapplied on the next `onResume`.
  Future<bool> applyRecentsPrivacy({required bool hide}) async {
    try {
      final result = await _channel.invokeMethod<bool>('applyRecentsPrivacy', {
        'hide': hide,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<int> crashLogCount() async {
    try {
      final result = await _channel.invokeMethod<int>('crashLogCount');
      return result ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<String> readCrashLogs() async {
    try {
      return await _channel.invokeMethod<String>('readCrashLogs') ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  Future<int> clearCrashLogs() async {
    try {
      final result = await _channel.invokeMethod<int>('clearCrashLogs');
      return result ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<String?> exportText({
    required String name,
    required String content,
  }) async {
    try {
      return await _channel.invokeMethod<String>('exportText', {
        'name': name,
        'content': content,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Deletes downloaded update packages; [includeTemp] also clears the temp cache. Not doable
  /// through sqflite, which only sees `databases/`.
  Future<int> clearUpdateCache({bool includeTemp = true}) async {
    try {
      final result = await _channel.invokeMethod<int>('clearUpdateCache', {
        'includeTemp': includeTemp,
      });
      return result ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<int> clearCustomBackgroundCache() async {
    try {
      final result = await _channel.invokeMethod<int>(
        'clearCustomBackgroundCache',
      );
      return result ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Opens the system save picker and keeps the chosen document open, so the JSON can be streamed
  /// into it with [appendExportChunk].
  ///
  /// The single-string variant is gone on purpose: it forced the whole document through the Dart
  /// heap, the channel and a byte array at once, which is what ran the process out of memory on a
  /// subscription-sized dataset. On Android 11+ the app-private external dir is hard to reach even
  /// from a file manager, so the picker is still the way out.
  Future<DocumentExportHandle> beginExportDocument({required String name}) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('beginExportDocument', {
        'name': name,
      });
      return DocumentExportHandle.fromMap(raw);
    } on MissingPluginException {
      return DocumentExportHandle.unavailable();
    } on PlatformException catch (error) {
      return DocumentExportHandle.failed(
        currentL10n.platformNoSaveDialog(error.message ?? ''),
      );
    }
  }

  /// Writes one chunk; false means the document is gone and the export must stop.
  Future<bool> appendExportChunk({
    required int handle,
    required String chunk,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('appendExportChunk', {
            'handle': handle,
            'chunk': chunk,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<DocumentSaveResult> endExportDocument(int handle) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('endExportDocument', {
        'handle': handle,
      });
      return DocumentSaveResult.fromMap(raw);
    } on MissingPluginException {
      return DocumentSaveResult.unavailable();
    } on PlatformException catch (error) {
      return DocumentSaveResult.failed(
        currentL10n.platformNoSaveDialog(error.message ?? ''),
      );
    }
  }

  /// Closes and deletes a half-written export.
  Future<void> abortExportDocument() async {
    try {
      await _channel.invokeMethod<bool>('abortExportDocument');
    } on MissingPluginException {
      // Nothing was written, so there is nothing to clean up.
    } on PlatformException {
      // Same: the file is only a partial export the user can delete.
    }
  }

  Future<DocumentOpenResult> importDocument() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('importDocument');
      return DocumentOpenResult.fromMap(raw);
    } on MissingPluginException {
      return DocumentOpenResult.unavailable();
    } on PlatformException catch (error) {
      return DocumentOpenResult.failed(
        currentL10n.platformNoFilePicker(error.message ?? ''),
      );
    }
  }

  /// Opens the document picker and keeps a long-lived read grant, so a local-file rule
  /// subscription can be re-imported later without asking the user to pick it again.
  Future<PersistedTextFile> pickPersistableTextFile() async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'pickPersistableTextFile',
      );
      return PersistedTextFile.fromMap(raw);
    } on MissingPluginException {
      return PersistedTextFile.unavailable();
    } on PlatformException catch (error) {
      return PersistedTextFile.failed(
        currentL10n.platformNoFilePicker(error.message ?? ''),
      );
    }
  }

  /// Opens the document picker for a font file; the bytes are copied into app storage natively, so
  /// the returned path stays readable without a URI grant.
  Future<FontPickResult> pickFontFile() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('pickFontFile');
      return FontPickResult.fromMap(raw);
    } on MissingPluginException {
      return FontPickResult.unavailable();
    } on PlatformException catch (error) {
      return FontPickResult.failed(error.message ?? currentL10n.platformNoFilePickerShort);
    }
  }

  /// Deletes a font copied in by [pickFontFile]; unknown paths are ignored natively.
  Future<void> deleteFontFile(String path) async {
    try {
      await _channel.invokeMethod<void>('deleteFontFile', {'path': path});
    } on MissingPluginException {
      // Without the channel there is no copied file to delete.
    } on PlatformException {
      // A file that is already gone needs no cleanup.
    }
  }

  /// Re-reads a file picked earlier; the persisted grant is what makes this work after a restart.
  Future<PersistedTextRead> readPersistedText(String uri) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('readPersistedText', {
        'uri': uri,
      });
      return PersistedTextRead.fromMap(raw);
    } on MissingPluginException {
      return PersistedTextRead.failed(currentL10n.platformNoLocalRead);
    } on PlatformException catch (error) {
      return PersistedTextRead.failed(
        currentL10n.platformReadFailed(error.message ?? ''),
      );
    }
  }

  /// Drops the stored grant when the subscription is deleted.
  Future<void> releasePersistedText(String uri) async {
    try {
      await _channel.invokeMethod<void>('releasePersistedText', {'uri': uri});
    } on MissingPluginException {
      // Nothing to release without the channel.
    } on PlatformException {
      // A grant that is already gone needs no cleanup.
    }
  }

  /// Memory used by this process and by the device; a missing channel yields
  /// [ProcessMemory.available] false so the card shows a dash.
  Future<ProcessMemory> memoryInfo() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('memoryInfo');
      return ProcessMemory.fromMap(raw);
    } on MissingPluginException {
      return const ProcessMemory();
    } on PlatformException {
      return const ProcessMemory();
    }
  }
}

class DocumentSaveResult {
  const DocumentSaveResult({
    required this.saved,
    this.name,
    this.cancelled = false,
    this.error,
  });

  DocumentSaveResult.unavailable()
    : saved = false,
      name = null,
      cancelled = false,
      error = currentL10n.platformNoSystemPicker;

  const DocumentSaveResult.failed(String this.error)
    : saved = false,
      name = null,
      cancelled = false;

  final bool saved;
  final String? name;
  final bool cancelled;
  final String? error;

  static DocumentSaveResult fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    return DocumentSaveResult(
      saved: map['saved'] == true,
      name: map['name'] as String?,
      cancelled: map['cancelled'] == true,
      error: map['error'] as String?,
    );
  }
}

/// An open export document, ready to receive chunks.
class DocumentExportHandle {
  const DocumentExportHandle({
    this.handle,
    this.name,
    this.cancelled = false,
    this.error,
  });

  DocumentExportHandle.unavailable()
    : handle = null,
      name = null,
      cancelled = false,
      error = currentL10n.platformNoSystemPicker;

  const DocumentExportHandle.failed(String this.error)
    : handle = null,
      name = null,
      cancelled = false;

  /// Native side handle; null when the picker was cancelled or failed.
  final int? handle;
  final String? name;
  final bool cancelled;
  final String? error;

  static DocumentExportHandle fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    return DocumentExportHandle(
      handle: (map['handle'] as num?)?.toInt(),
      name: map['name'] as String?,
      cancelled: map['cancelled'] == true,
      error: map['error'] as String?,
    );
  }
}

class DocumentOpenResult {
  const DocumentOpenResult({
    this.text,
    this.name,
    this.cancelled = false,
    this.error,
  });

  DocumentOpenResult.unavailable()
    : text = null,
      name = null,
      cancelled = false,
      error = currentL10n.platformNoSystemPicker;

  const DocumentOpenResult.failed(String this.error)
    : text = null,
      name = null,
      cancelled = false;

  final String? text;
  final String? name;
  final bool cancelled;
  final String? error;

  static DocumentOpenResult fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    return DocumentOpenResult(
      text: map['text'] as String?,
      name: map['name'] as String?,
      cancelled: map['cancelled'] == true,
      error: map['error'] as String?,
    );
  }
}

/// Result of picking a rule file for a local-file subscription.
class PersistedTextFile {
  const PersistedTextFile({
    this.uri,
    this.name,
    this.text,
    this.persisted = false,
    this.cancelled = false,
    this.error,
  });

  PersistedTextFile.unavailable()
    : uri = null,
      name = null,
      text = null,
      persisted = false,
      cancelled = false,
      error = currentL10n.platformNoSystemPicker;

  const PersistedTextFile.failed(String this.error)
    : uri = null,
      name = null,
      text = null,
      persisted = false,
      cancelled = false;

  /// `content://` address stored as the subscription's `url`, so its grant can be re-read.
  final String? uri;
  final String? name;
  final String? text;

  /// False when the picker did not grant persistable access; the file then has to be re-picked.
  final bool persisted;
  final bool cancelled;
  final String? error;

  /// A cancelled pick is not an error.
  bool get isOk => cancelled || error == null;
  String get displayName => name ?? '';

  static PersistedTextFile fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    return PersistedTextFile(
      uri: map['uri'] as String?,
      name: map['name'] as String?,
      text: map['text'] as String?,
      persisted: map['persisted'] == true,
      cancelled: map['cancelled'] == true,
      error: map['error'] as String?,
    );
  }
}

/// Result of picking a TTF/OTF file the user wants to use as the app font.
class FontPickResult {
  const FontPickResult({
    this.path,
    this.name,
    this.bytes = 0,
    this.cancelled = false,
    this.error,
  });

  FontPickResult.unavailable()
    : path = null,
      name = null,
      bytes = 0,
      cancelled = false,
      error = currentL10n.platformNoSystemPicker;

  const FontPickResult.failed(String this.error)
    : path = null,
      name = null,
      bytes = 0,
      cancelled = false;

  /// Absolute path inside the app's private `files/fonts` directory.
  final String? path;
  final String? name;
  final int bytes;
  final bool cancelled;
  final String? error;

  /// A cancelled pick is not an error.
  bool get isOk => cancelled || (error == null && path != null);

  static FontPickResult fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    return FontPickResult(
      path: map['path'] as String?,
      name: map['name'] as String?,
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      cancelled: map['cancelled'] == true,
      error: map['error'] as String?,
    );
  }
}

/// Result of re-reading a previously picked rule file.
class PersistedTextRead {
  const PersistedTextRead({this.text, this.error});

  const PersistedTextRead.failed(String this.error) : text = null;

  final String? text;
  final String? error;

  bool get isOk => error == null && text != null;

  static PersistedTextRead fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    return PersistedTextRead(
      text: map['text'] as String?,
      error: map['error'] as String?,
    );
  }
}
