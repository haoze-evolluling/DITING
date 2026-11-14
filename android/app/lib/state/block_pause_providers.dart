import 'package:diting_android/data/native/block_pause_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The R4 pause bridge; overridden in tests with a fake channel-backed instance.
final blockPauseBridgeProvider = Provider<BlockPauseBridge>(
  (ref) => BlockPauseBridge(),
);
