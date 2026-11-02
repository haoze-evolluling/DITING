/// Fetches, caches and validates the member list and avatars. Nothing is bundled; a config failing
/// validation never overwrites the cache.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_android/data/native/recognition_avatar_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/recognition/recognition_members.dart';
import 'package:flutter/foundation.dart';

class RecognitionMembersRepository {
  RecognitionMembersRepository({
    required this.store,
    RecognitionAvatarBridge? avatarBridge,
    this.timeout = const Duration(seconds: 10),
    this.userAgent = appFallbackUserAgent,
  }) : _avatars = avatarBridge ?? const RecognitionAvatarBridge();

  /// Legacy container name, so upgrades keep their cache.
  static const container = 'recognition_members';

  static const _configKey = 'config_json';
  static const _savedAtKey = 'saved_at_ms';
  static const _etagKey = 'etag';

  /// Config cap of 256KB; a real list is far smaller.
  static const maxConfigBytes = 256 * 1024;

  static const maxAvatarBytes = 1024 * 1024;

  final LegacyPrefsStore store;
  final Duration timeout;

  /// `/config/user-agents` override; the member list and avatars both use it.
  final String userAgent;
  final RecognitionAvatarBridge _avatars;

  /// In-process avatar bytes; avoids re-reading the disk on scroll.
  final Map<String, Uint8List> _avatarMemoryCache = {};

  final Map<String, Future<Uint8List?>> _avatarInFlight = {};

  Future<void> _avatarQueue = Future<void>.value();

  RecognitionMembers? loadCached() {
    final raw = store.read(container, _configKey);
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      return parseRecognitionMembers(raw);
    } on FormatException catch (error) {
      debugPrint('recognition: 本地缓存不可用（$error），等待云端刷新');
      return null;
    }
  }

  DateTime? loadCachedAt() {
    final raw = store.read(container, _savedAtKey);
    if (raw is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  /// Null means not modified (HTTP 304); any other failure throws and the caller keeps what it has.
  /// Retried, as handshake errors are intermittent.
  Future<RecognitionMembers?> refresh() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _refreshOnce();
      } on Object catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 400 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError!;
  }

  Future<RecognitionMembers?> _refreshOnce() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse(recognitionMembersUrl))
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final etag = store.read(container, _etagKey);
      if (etag is String && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(timeout);
      if (response.statusCode == HttpStatus.notModified) {
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final raw = await _readLimited(response, maxConfigBytes);
      final members = parseRecognitionMembers(raw);
      _writeCache(raw, response.headers.value(HttpHeaders.etagHeader));
      return members;
    } finally {
      client.close(force: true);
    }
  }

  /// Memory first, then disk cache, then download; null means unavailable.
  Future<Uint8List?> loadAvatarBytes(String avatarFileName) {
    final cached = _avatarMemoryCache[avatarFileName];
    if (cached != null) return Future.value(cached);
    final inFlight = _avatarInFlight[avatarFileName];
    if (inFlight != null) return inFlight;
    final future = _enqueue(() => _loadAvatar(avatarFileName));
    _avatarInFlight[avatarFileName] = future;
    return future.whenComplete(() => _avatarInFlight.remove(avatarFileName));
  }

  /// Serializes avatar downloads: a dozen concurrent TLS handshakes get dropped mid-flight on
  /// emulators and weak networks.
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final previous = _avatarQueue;
    final completer = Completer<void>();
    _avatarQueue = completer.future;
    return previous.then((_) => task()).whenComplete(completer.complete);
  }

  Future<Uint8List?> _loadAvatar(String avatarFileName) async {
    final stored = await _avatars.read(avatarFileName);
    if (stored != null && stored.isNotEmpty) {
      _avatarMemoryCache[avatarFileName] = stored;
      return stored;
    }
    final url = recognitionAvatarBaseUrl + avatarFileName;
    // TLS handshakes are occasionally cut mid-flight (`HandshakeException: ...handshake`) and an
    // immediate retry usually works.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final bytes = await _download(url);
        if (bytes.isEmpty || bytes.length > maxAvatarBytes) return null;
        _avatarMemoryCache[avatarFileName] = bytes;
        // A failed write only costs a re-download.
        await _avatars.write(avatarFileName, bytes);
        return bytes;
      } on Object catch (error) {
        if (attempt == 2) {
          debugPrint('recognition: 头像 $avatarFileName 下载失败（$error）');
          return null;
        }
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return null;
  }

  Future<Uint8List> _download(String url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.timeout(timeout)) {
        total += chunk.length;
        if (total > maxAvatarBytes) throw HttpException(currentL10n.recognitionAvatarTooLarge);
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _readLimited(
    HttpClientResponse response,
    int limit,
  ) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
      if (total > limit) throw HttpException(currentL10n.recognitionConfigTooLarge);
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }

  void _writeCache(String raw, String? etag) {
    store.putString(container, _configKey, raw);
    // Millisecond timestamps (~1.7e12) overflow 32 bits, so putLong is required; putInt truncates
    // to a 1970 date.
    store.putLong(
      container,
      _savedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (etag != null && etag.isNotEmpty) {
      store.putString(container, _etagKey, etag);
    }
  }
}
