library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/errors.dart';
import 'package:diting_shared/data/native/process_memory.dart';
import 'package:flutter/services.dart';

const platformChannelName = 'com.haoze.diting/platform';

class PlatformBridge {
  PlatformBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(platformChannelName);

  final MethodChannel _channel;

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

  Future<DocumentExportHandle> beginExportDocument({
    required String name,
    String mimeType = 'application/json',
  }) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('beginExportDocument', {
        'name': name,
        'mimeType': mimeType,
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

  Future<void> abortExportDocument() async {
    try {
      await _channel.invokeMethod<bool>('abortExportDocument');
    } on MissingPluginException {
      ignoreError();
    } on PlatformException {
      ignoreError();
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

  Future<void> deleteFontFile(String path) async {
    try {
      await _channel.invokeMethod<void>('deleteFontFile', {'path': path});
    } on MissingPluginException {
      ignoreError();
    } on PlatformException {
      ignoreError();
    }
  }

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

  Future<void> releasePersistedText(String uri) async {
    try {
      await _channel.invokeMethod<void>('releasePersistedText', {'uri': uri});
    } on MissingPluginException {
      ignoreError();
    } on PlatformException {
      ignoreError();
    }
  }

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

  final String? uri;
  final String? name;
  final String? text;

  final bool persisted;
  final bool cancelled;
  final String? error;

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

  final String? path;
  final String? name;
  final int bytes;
  final bool cancelled;
  final String? error;

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
