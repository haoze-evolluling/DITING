library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `DRI1` 的小端序表示。
const _payloadMagic = 0x31495244;

/// 订阅原文导入内核：解析、规则表写入与事务提交全部在 Rust 内完成，
/// 规则计划不再以 JSON 形式经 FFI 与 sqflite 通道往返。
class RustRuleImportCore {
  RustRuleImportCore._(this._core);

  final KernelCore _core;

  static RustRuleImportCore? _instance;

  static RustRuleImportCore get instance => _instance ??= _load();

  static RustRuleImportCore _load() => RustRuleImportCore._(
    KernelCore.load(
      crate: 'diting-rule-import-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'rule import core',
    ),
  );

  String get libraryPath => _core.libraryPath;

  Map<String, Object?> run(Map<String, Object?> request) => _core.call(request);
}
