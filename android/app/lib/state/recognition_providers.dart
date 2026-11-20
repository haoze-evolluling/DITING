library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/recognition/recognition_members.dart';
import 'package:diting_android/data/recognition/recognition_repository.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class RecognitionState {
  const RecognitionState({
    this.members,
    this.updatedAt,
    this.isRefreshing = false,
    this.error,
    this.fromCache = false,
  });

  final RecognitionMembers? members;

  final DateTime? updatedAt;

  final bool isRefreshing;

  final String? error;

  final bool fromCache;

  bool get hasMembers => members != null;

  RecognitionState copyWith({
    RecognitionMembers? members,
    DateTime? updatedAt,
    bool? isRefreshing,
    Object? error = _keep,
    bool? fromCache,
  }) {
    return RecognitionState(
      members: members ?? this.members,
      updatedAt: updatedAt ?? this.updatedAt,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error == _keep ? this.error : error as String?,
      fromCache: fromCache ?? this.fromCache,
    );
  }

  static const _keep = Object();
}

final recognitionRepositoryProvider = Provider<RecognitionMembersRepository>((
  ref,
) {
  return RecognitionMembersRepository(
    store: ref.watch(legacyPrefsStoreProvider),
    userAgent: ref.watch(requestUserAgentProvider),
  );
});

class RecognitionController extends AsyncNotifier<RecognitionState> {
  static const freshWindow = Duration(seconds: 60);

  Future<void>? _inFlight;

  @override
  Future<RecognitionState> build() async {
    final repo = ref.watch(recognitionRepositoryProvider);
    final cached = repo.loadCached();
    return RecognitionState(
      members: cached,
      updatedAt: repo.loadCachedAt(),
      fromCache: true,
    );
  }

  void ensureFresh() {
    final current = state.value;
    if (current == null) return;
    if (current.isRefreshing || _inFlight != null) return;
    final updatedAt = current.updatedAt;
    if (current.hasMembers &&
        updatedAt != null &&
        DateTime.now().difference(updatedAt) < freshWindow) {
      return;
    }
    unawaited(refresh());
  }

  Future<void> refresh() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _runRefresh();
    _inFlight = future;
    return future;
  }

  Future<void> _runRefresh() async {
    final current = state.value ?? const RecognitionState();
    state = AsyncData(current.copyWith(isRefreshing: true, error: null));
    final repo = ref.read(recognitionRepositoryProvider);
    try {
      final fresh = await repo.refresh();
      if (fresh == null) {
        state = AsyncData(
          current.copyWith(
            isRefreshing: false,
            updatedAt: DateTime.now(),
            fromCache: false,
            error: null,
          ),
        );
        ref.invalidate(recognitionAvatarProvider);
        return;
      }
      state = AsyncData(
        RecognitionState(
          members: fresh,
          updatedAt: DateTime.now(),
          isRefreshing: false,
          fromCache: false,
        ),
      );
      ref.invalidate(recognitionAvatarProvider);
    } on Object catch (error) {
      if (!ref.mounted) return;
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(isRefreshing: false, error: _describe(error)),
      );
    } finally {
      _inFlight = null;
    }
  }

  static String _describe(Object error) {
    final text = error.toString();
    if (error is FormatException) {
      return currentL10n.recognitionInvalidConfigKept(error.message);
    }
    if (text.contains('HandshakeException')) {
      return currentL10n.recognitionGithubInterrupted;
    }
    if (text.contains('TimeoutException')) {
      return currentL10n.recognitionGithubTimeout;
    }
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup')) {
      return currentL10n.recognitionNetworkUnavailable;
    }
    if (text.contains('HttpException')) {
      return currentL10n.recognitionFetchFailed(text);
    }
    return currentL10n.recognitionUpdateFailedDetail(text);
  }
}

final recognitionMembersProvider =
    AsyncNotifierProvider<RecognitionController, RecognitionState>(
      RecognitionController.new,
    );

final recognitionAvatarProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  avatarFileName,
) async {
  final repo = ref.watch(recognitionRepositoryProvider);
  return repo.loadAvatarBytes(avatarFileName);
});
