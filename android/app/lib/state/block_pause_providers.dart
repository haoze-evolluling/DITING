import 'package:diting_android/data/native/block_pause_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final blockPauseBridgeProvider = Provider<BlockPauseBridge>(
  (ref) => BlockPauseBridge(),
);
