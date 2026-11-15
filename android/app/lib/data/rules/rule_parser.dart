/// Rule document parsing. The implementation lives in Rust (`rust/diting-rule-core`); this file is
/// the Dart entry point the import paths call.
library;

import 'dart:typed_data';

import 'package:diting_android/data/rules/rule_models.dart';
import 'package:diting_android/data/rules/rust_rule_core.dart';

/// Parses a document, groups by family, dedupes by key and applies `$badfilter`.
///
/// Throws [StateError] when the native core is unavailable or rejects the document: there is no
/// second parser to fall back to.
CategorizedRules parseCategorized(String text) =>
    RustRuleCore.instance.parse(text);

/// Streams a document as bounded [CategorizedRules] chunks, so a large subscription never has to
/// exist as one whole rule-object graph. Callers must [RuleStreamParse.dispose] the session.
RuleStreamParse streamParseCategorized(String text) =>
    RustRuleCore.instance.streamParse(text);

/// Same as [streamParseCategorized] but from raw UTF-8 bytes, skipping a String re-encode.
RuleStreamParse streamParseCategorizedBytes(Uint8List bytes) =>
    RustRuleCore.instance.streamParseBytes(bytes);
