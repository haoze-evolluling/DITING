/// Checks GitHub Releases and parses the latest version: drop the `v`, cut at `-`, compare as
/// integers; APK assets prefer `arm64-v8a`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/db/rust_app_update_core.dart';
import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.fileName,
    required this.releaseNotes,
  });

  final String version;
  final String downloadUrl;
  final String fileName;

  final String releaseNotes;
}

class UpdateCheckResult {
  const UpdateCheckResult.upToDate({required this.currentVersion})
    : info = null,
      error = null;

  const UpdateCheckResult.available(
    UpdateInfo this.info, {
    required this.currentVersion,
  }) : error = null;

  const UpdateCheckResult.failed(String this.error)
    : info = null,
      currentVersion = null;

  final UpdateInfo? info;

  final String? currentVersion;

  final String? error;

  bool get failed => error != null;
  bool get hasUpdate => info != null;
}

class AppUpdateChecker {
  const AppUpdateChecker({
    this.releaseUrl = defaultReleaseUrl,
    this.timeout = const Duration(seconds: 15),
    this.userAgent = appFallbackUserAgent,
    this.mirrorTemplate,
  });

  /// The legacy `AppUpdateManager.RELEASE_URL`; the compile-time override points at a mirror or a
  /// local fake server.
  static const defaultReleaseUrl = String.fromEnvironment(
    'DITING_RELEASE_URL',
    defaultValue:
        'https://api.github.com/repos/haoze-evolluling/DITING/releases/latest',
  );

  final String releaseUrl;
  final Duration timeout;

  /// `/config/user-agents` override; GitHub 403s a request without one.
  final String userAgent;

  /// Global mirror template; the release query tries it first and falls back to direct.
  final String? mirrorTemplate;

  Future<UpdateCheckResult> check(String currentVersion) async {
    final mirrored = _mirrored(releaseUrl);
    if (mirrored != null) {
      final result = await _checkAt(mirrored, currentVersion);
      if (!result.failed) return result;
    }
    return _checkAt(releaseUrl, currentVersion);
  }

  String? _mirrored(String url) {
    final template = mirrorTemplate;
    if (template == null) return null;
    try {
      return buildMirrorUrl(template, url);
    } on FormatException {
      return null;
    }
  }

  Future<UpdateCheckResult> _checkAt(
    String releaseUrl,
    String currentVersion,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse(releaseUrl))
          .timeout(timeout);
      // GitHub 403s a request without a User-Agent; `Accept` selects the schema.
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != 200) {
        return UpdateCheckResult.failed(
          _statusMessage(response.statusCode, body),
        );
      }
      return parseLatestRelease(body, currentVersion);
    } on SocketException catch (error) {
      return UpdateCheckResult.failed(
        currentL10n.updateConnectFailed(error.message),
      );
    } on HandshakeException {
      return UpdateCheckResult.failed(currentL10n.updateTlsFailed);
    } on FormatException {
      return UpdateCheckResult.failed(currentL10n.updateBadJson);
    } finally {
      client.close(force: true);
    }
  }

  /// Turns a non-200 into something the user can act on. A GitHub 403 means rate limiting or a real
  /// refusal; the body `message` tells them apart.
  static String _statusMessage(int status, String body) {
    final answer = RustAppUpdateCore.instance.statusMessage(status, body);
    final code = (answer['status'] as num?)?.toInt() ?? status;
    return switch (answer['kind']) {
      'rateLimited' => currentL10n.updateRateLimited,
      'forbidden' => currentL10n.updateForbidden,
      'notFound' => currentL10n.updateNotFound,
      'serverError' => currentL10n.updateServerError(code),
      'unexpectedStatus' => currentL10n.updateUnexpectedStatus(code),
      final kind => throw StateError(
        'app update core: unknown status kind "$kind"',
      ),
    };
  }

  /// Parses a `releases/latest` body. Missing fields are tolerated, but a missing version is an
  /// explicit error rather than "already latest".
  static UpdateCheckResult parseLatestRelease(
    String payload,
    String currentVersion,
  ) {
    final answer = RustAppUpdateCore.instance.parseLatestRelease(
      payload,
      currentVersion,
    );
    switch (answer['kind']) {
      case 'error':
        return UpdateCheckResult.failed(
          _errorMessage(answer['code'] as String?),
        );
      case 'upToDate':
        return UpdateCheckResult.upToDate(currentVersion: currentVersion);
      case 'available':
        final version = answer['version'] as String? ?? '';
        return UpdateCheckResult.available(
          UpdateInfo(
            version: version,
            downloadUrl: answer['downloadUrl'] as String? ?? '',
            fileName:
                answer['fileName'] as String? ??
                currentL10n.updateApkFileName(version),
            releaseNotes: answer['releaseNotes'] as String? ?? '',
          ),
          currentVersion: currentVersion,
        );
      default:
        throw StateError(
          'app update core: unknown parse result "${answer['kind']}"',
        );
    }
  }

  static String _errorMessage(String? code) => switch (code) {
    'responseNotJson' => currentL10n.updateResponseNotJson,
    'unexpectedFormat' => currentL10n.updateUnexpectedFormat,
    'missingTag' => currentL10n.updateMissingTag,
    'noApk' => currentL10n.updateNoApk,
    'badDownloadUrl' => currentL10n.updateBadDownloadUrl,
    _ => throw StateError('app update core: unknown error code "$code"'),
  };

  /// Compares versions component by component as integers. Anything unparseable counts as "not
  /// newer".
  static bool isNewerVersion(String remote, String current) =>
      RustAppUpdateCore.instance.isNewerVersion(remote, current);
}
