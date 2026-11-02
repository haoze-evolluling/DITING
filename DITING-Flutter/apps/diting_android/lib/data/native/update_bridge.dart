/// Dart side of `com.haoze.diting/update`: downloads an update package and hands it to the system
/// installer. Neither works from Dart: the private directory is the wrong location and installing
/// needs a FileProvider `content://` URI.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/services.dart';

const _updateChannelName = 'com.haoze.diting/update';

/// Download progress; [total] is -1 when the server sent no content length.
class UpdateProgress {
  const UpdateProgress({required this.downloaded, required this.total});

  final int downloaded;
  final int total;

  double? get fraction =>
      total > 0 ? (downloaded / total).clamp(0.0, 1.0) : null;

  static UpdateProgress fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    return UpdateProgress(
      downloaded: (map['downloaded'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? -1,
    );
  }
}

class UpdateDownloadResult {
  const UpdateDownloadResult.success(this.path) : error = null;

  const UpdateDownloadResult.failed(String this.error) : path = null;

  final String? path;
  final String? error;

  bool get ok => path != null;
}

class UpdateBridge {
  UpdateBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_updateChannelName);

  final MethodChannel _channel;

  /// Downloads [url] into the app-private directory, reporting through [onProgress]. Only an
  /// Android host downloads; elsewhere it fails so the caller can say "not supported".
  Future<UpdateDownloadResult> download({
    required String url,
    required String version,
    void Function(UpdateProgress progress)? onProgress,
  }) async {
    if (onProgress != null) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'progress') {
          onProgress(UpdateProgress.fromMap(call.arguments));
        }
        return null;
      });
    }
    try {
      final path = await _channel.invokeMethod<String>('download', {
        'url': url,
        'version': version,
      });
      if (path == null || path.isEmpty) {
        return UpdateDownloadResult.failed(currentL10n.updateDownloadNoPath);
      }
      return UpdateDownloadResult.success(path);
    } on MissingPluginException {
      return UpdateDownloadResult.failed(currentL10n.updateDownloadUnsupported);
    } on PlatformException catch (error) {
      return UpdateDownloadResult.failed(
        error.message ?? currentL10n.updateDownloadFailedCode(error.code),
      );
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  Future<bool> install(String path) async {
    try {
      final result = await _channel.invokeMethod<bool>('install', {
        'path': path,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
