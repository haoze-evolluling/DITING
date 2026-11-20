library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diting_android/data/db/rust_recognition_core.dart';
import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_android/data/native/recognition_avatar_bridge.dart';
import 'package:diting_android/data/recognition/recognition_members.dart';
import 'package:diting_android/data/recognition/recognition_plan.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:flutter/foundation.dart';

class RecognitionMembersRepository {
  RecognitionMembersRepository({
    required this.store,
    RecognitionAvatarBridge? avatarBridge,
    this.timeout = const Duration(seconds: 10),
    this.userAgent = appFallbackUserAgent,
  }) : _avatars = avatarBridge ?? const RecognitionAvatarBridge();

  static String get container => RecognitionPlan.instance.container;

  static int get maxConfigBytes => RecognitionPlan.instance.maxConfigBytes;

  static int get maxAvatarBytes => RecognitionPlan.instance.maxAvatarBytes;

  RecognitionPlan get _plan => RecognitionPlan.instance;

  final LegacyPrefsStore store;
  final Duration timeout;

  final String userAgent;
  final RecognitionAvatarBridge _avatars;

  final Map<String, Uint8List> _avatarMemoryCache = {};

  final Map<String, Future<Uint8List?>> _avatarInFlight = {};

  Future<void> _avatarQueue = Future<void>.value();

  RecognitionMembers? loadCached() {
    final raw = store.read(_plan.container, _plan.configKey);
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      return parseRecognitionMembers(raw);
    } on FormatException catch (error) {
      debugPrint('recognition: 本地缓存不可用（$error），等待云端刷新');
      return null;
    }
  }

  DateTime? loadCachedAt() {
    final raw = store.read(_plan.container, _plan.savedAtKey);
    if (raw is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<RecognitionMembers?> refresh() async {
    Object? lastError;
    for (var attempt = 0; attempt < _plan.refreshAttempts; attempt++) {
      try {
        return await _refreshOnce();
      } on Object catch (error) {
        lastError = error;
        if (attempt < _plan.refreshAttempts - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: _plan.refreshDelayBaseMs * (attempt + 1)),
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
          .getUrl(Uri.parse(_plan.membersUrl))
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final etag = store.read(_plan.container, _plan.etagKey);
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
      final raw = await _readLimited(response, _plan.maxConfigBytes);
      final members = parseRecognitionMembers(raw);
      _writeCache(raw, response.headers.value(HttpHeaders.etagHeader));
      return members;
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List?> loadAvatarBytes(String avatarFileName) {
    final cached = _avatarMemoryCache[avatarFileName];
    if (cached != null) return Future.value(cached);
    final inFlight = _avatarInFlight[avatarFileName];
    if (inFlight != null) return inFlight;
    final future = _enqueue(() => _loadAvatar(avatarFileName));
    _avatarInFlight[avatarFileName] = future;
    return future.whenComplete(() => _avatarInFlight.remove(avatarFileName));
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final previous = _avatarQueue;
    final completer = Completer<void>();
    _avatarQueue = completer.future;
    return previous.then((_) => task()).whenComplete(completer.complete);
  }

  Future<Uint8List?> _loadAvatar(String avatarFileName) async {
    final stored = await _avatars.read(avatarFileName);
    if (stored != null &&
        RustRecognitionCore.instance.avatarAccepted(stored.length)) {
      _avatarMemoryCache[avatarFileName] = stored;
      return stored;
    }
    final url = _plan.avatarBaseUrl + avatarFileName;
    for (var attempt = 0; attempt < _plan.avatarAttempts; attempt++) {
      try {
        final bytes = await _download(url);
        if (!RustRecognitionCore.instance.avatarAccepted(bytes.length)) {
          return null;
        }
        _avatarMemoryCache[avatarFileName] = bytes;
        await _avatars.write(avatarFileName, bytes);
        return bytes;
      } on Object catch (error) {
        if (attempt == _plan.avatarAttempts - 1) {
          debugPrint('recognition: 头像 $avatarFileName 下载失败（$error）');
          return null;
        }
        await Future<void>.delayed(
          Duration(milliseconds: _plan.avatarDelayBaseMs * (attempt + 1)),
        );
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
        if (total > _plan.maxAvatarBytes) {
          throw HttpException(currentL10n.recognitionAvatarTooLarge);
        }
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
      if (total > limit) {
        throw HttpException(currentL10n.recognitionConfigTooLarge);
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }

  void _writeCache(String raw, String? etag) {
    store.putString(_plan.container, _plan.configKey, raw);
    store.putLong(
      _plan.container,
      _plan.savedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (etag != null && etag.isNotEmpty) {
      store.putString(_plan.container, _plan.etagKey, etag);
    }
  }
}
