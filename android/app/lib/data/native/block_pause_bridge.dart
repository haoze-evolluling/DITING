library;

import 'package:flutter/services.dart';

class BlockPauseState {
  const BlockPauseState({required this.pausedUntilMs, required this.allowlistOnly});

  final int pausedUntilMs;

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
