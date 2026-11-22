library;

import 'dart:typed_data';

import 'package:diting_android/data/rules/rule_models.dart';
import 'package:diting_android/data/rules/rust_rule_core.dart';

CategorizedRules parseCategorized(String text) =>
    RustRuleCore.instance.parse(text);

RuleStreamParse streamParseCategorized(String text) =>
    RustRuleCore.instance.streamParse(text);

RuleStreamParse streamParseCategorizedBytes(Uint8List bytes) =>
    RustRuleCore.instance.streamParseBytes(bytes);
