/// Dart side of R4 (temporary pause / allowlist-only), `com.haoze.diting/block_pause`.
///
/// The pause is a wall-clock deadline persisted in the shared automation prefs; the enforcement is
/// the Rust engine's `pause` flag applied by the Kotlin `BlockPauseLink`. This file only types the
/// state, so all entry points (this page, the notification action, the control receiver) agree.
library;

import 'package:flutter/services.dart';

/// The current pause / allowlist-only state as the platform reports it.
class BlockPauseState {
  const BlockPauseState({required this.pausedUntilMs, required this.allowlistOnly});

  /// Epoch ms at which the pause ends; `0` means not paused.
  final int pausedUntilMs;

  /// Strict allowlist-only mode.
  final bool allowlistOnly;

  bool get paused => pausedUntilMs > DateTime.now().millisecondsSinceEpoch;

  Duration get remaining {
    final millis = pausedUntilMs - DateTime.now().millisecondsSinceEpoch;
    return millis > 0 ? Duration(milliseconds: millis) : Duration.zero;
  }

  static BlockPauseState fromMap(Map<Object?, Object?>? map) => BlockPauseState(
    pausedUntilMs: (map?['pausedUntilMs'] as num?)?.toInt() ?? 0,
    allowlistOnly: map?['allowlistOnly'] == true,
  );
}

/// Method-channel access to the Kotlin bridge.
class BlockPauseBridge {
  BlockPauseBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.haoze.diting/block_pause';

  final MethodChannel _channel;

  Future<BlockPauseState> read() async =>
      BlockPauseState.fromMap(await _channel.invokeMapMethod<Object?, Object?>('state'));

  Future<BlockPauseState> pause(int minutes) async => BlockPauseState.fromMap(
    await _channel.invokeMapMethod<Object?, Object?>('pause', {'minutes': minutes}),
  );

  Future<BlockPauseState> clear() async =>
      BlockPauseState.fromMap(await _channel.invokeMapMethod<Object?, Object?>('clear'));

  Future<BlockPauseState> setAllowlistOnly(bool enabled) async =>
      BlockPauseState.fromMap(
        await _channel.invokeMapMethod<Object?, Object?>('setAllowlistOnly', {
          'enabled': enabled,
        }),
      );
}
