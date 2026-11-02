/// Recognition list state: cache-first, so `build` only reads the local cache and `ensureFresh`
/// refreshes on entry.
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

  /// Displayable list; null until any data is available.
  final RecognitionMembers? members;

  /// Last successful cloud update; null if never.
  final DateTime? updatedAt;

  /// Whether a cloud fetch is in flight, driving the refresh button's spinner.
  final bool isRefreshing;

  /// Last refresh failure, cleared on success; shown in the page footer.
  final String? error;

  /// Whether the list came from the local cache rather than this session.
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

/// Repository instance; tests override it with in-memory data. Rebuilt when the
/// `/config/user-agents` selection changes.
final recognitionRepositoryProvider = Provider<RecognitionMembersRepository>((
  ref,
) {
  return RecognitionMembersRepository(
    store: ref.watch(legacyPrefsStoreProvider),
    userAgent: ref.watch(requestUserAgentProvider),
  );
});

class RecognitionController extends AsyncNotifier<RecognitionState> {
  /// Called on every page entry; a success within 60 seconds is reused.
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

  /// Called when the page mounts: starts a silent refresh if needed.
  void ensureFresh() {
    final current = state.value;
    if (current == null) return;
    if (current.isRefreshing || _inFlight != null) return;
    // Always refresh without a cached list; otherwise throttle by freshWindow.
    final updatedAt = current.updatedAt;
    if (current.hasMembers &&
        updatedAt != null &&
        DateTime.now().difference(updatedAt) < freshWindow) {
      return;
    }
    unawaited(refresh());
  }

  /// Called by the refresh button and by explicit retries.
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
        // 304: nothing changed, only the last-checked time moves.
        state = AsyncData(
          current.copyWith(
            isRefreshing: false,
            updatedAt: DateTime.now(),
            fromCache: false,
            error: null,
          ),
        );
        // An unchanged list does not mean every avatar arrived, so re-mount the family to retry the
        // failed ones.
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
      // Re-mount the family so failed downloads retry; fetched bytes are cached.
      ref.invalidate(recognitionAvatarProvider);
    } on Object catch (error) {
      // A failed refresh keeps the old list readable; the footer flags it cached.
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
      return currentL10n.recognitionInvalidConfigKept('${error.message}');
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

/// Bytes of one avatar; `null` falls back to the default image, and the family memoizes by file
/// name.
final recognitionAvatarProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  avatarFileName,
) async {
  final repo = ref.watch(recognitionRepositoryProvider);
  return repo.loadAvatarBytes(avatarFileName);
});
