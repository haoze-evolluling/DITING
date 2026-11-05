/// Native substring index over one rule table, with the Dart filter as the fallback.
///
/// The rules page narrows a whole table on every keystroke: pattern or target, case-insensitive
/// `contains`. On a subscription-sized table that is 25-35 ms of lowercasing plus scanning on the UI
/// isolate per key. [`RuleSearchIndex`] hands the rows to Rust once (folded there, exactly like
/// `String.toLowerCase`, see `rust/diting-rule-core/src/search.rs`) and then asks for row indices.
///
/// Anything that goes wrong — no artifact, an older `.so` without the search symbols, a rejected
/// payload — makes [`match`] return `null`, and the caller keeps its Dart filter, so the page can
/// never break or change what it shows. Payload layout lives in `src/search_ffi.rs`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:diting_android/data/rules/rust_rule_core.dart';

/// One searchable row: the pattern plus the optional target column the rules page matches too.
typedef RuleSearchEntry = ({String pattern, String? target});

/// `"DRS1"` read as a little-endian u32; the first field of every build payload.
const _buildMagic = 0x31535244;

/// Must match `SEARCH_ABI_VERSION` in `rust/diting-rule-core/src/search_ffi.rs`.
const _searchAbiVersion = 1;

/// `u32::MAX`, the "no target" marker on the wire.
const _noneLength = 0xFFFFFFFF;

class RuleSearchIndex {
  /// [entries] is called once, the first time a query needs the index: a table that is never
  /// searched (startup paging, a toggle with an empty search box) never pays for folding it.
  RuleSearchIndex(this._entries);

  final List<RuleSearchEntry> Function() _entries;

  int? _handle;

  /// Set when the native core refused the table, so later keystrokes do not retry the build.
  bool _unavailable = false;

  /// Row indices whose pattern or target contains [needle], ascending — the same rows, in the same
  /// order, as the Dart filter. `null` when the native index cannot serve the query.
  ///
  /// `needle` is folded natively, so it can be passed as typed.
  Uint32List? match(String needle) {
    final core = RustRuleCore.instance;
    if (core == null || !core.supportsSearch || _unavailable) return null;
    final handle = _handle ?? _build(core);
    if (handle == null) return null;
    return core.matchSearchIndex(handle, needle);
  }

  /// Releases the native rows. The provider calls this when the table it was built from changes.
  void dispose() {
    final handle = _handle;
    _handle = null;
    if (handle != null) RustRuleCore.instance?.freeSearchIndex(handle);
  }

  int? _build(RustRuleCore core) {
    final handle = core.buildSearchIndex(_encode(_entries()));
    if (handle == null) {
      _unavailable = true;
      return null;
    }
    return _handle = handle;
  }
}

/// Encodes one build payload: header, then `pattern` and `target?` per row.
Uint8List _encode(List<RuleSearchEntry> entries) {
  final writer = _PayloadWriter(12 + entries.length * 32);
  writer.u32(_buildMagic);
  writer.u32(_searchAbiVersion);
  writer.u32(entries.length);
  for (final entry in entries) {
    writer.string(entry.pattern);
    final target = entry.target;
    if (target == null) {
      writer.u32(_noneLength);
    } else {
      writer.string(target);
    }
  }
  return writer.take();
}

/// Growable little-endian writer; `BytesBuilder` would allocate a list per `u32`, which on a
/// 100k-row table is the kind of per-row garbage this module exists to avoid.
class _PayloadWriter {
  _PayloadWriter(int capacity) : _bytes = Uint8List(capacity < 64 ? 64 : capacity);

  Uint8List _bytes;
  int _length = 0;

  void u32(int value) {
    _reserve(4);
    _bytes.buffer.asByteData(_length, 4).setUint32(0, value, Endian.little);
    _length += 4;
  }

  /// Length prefix plus bytes.
  ///
  /// ASCII — which is what rule patterns are, after normalization — is copied straight from the
  /// UTF-16 code units, because `utf8.encode` allocates a `Uint8List` per string: on a 100k-row
  /// table that alone cost ~40 ms, against ~17 ms for the byte loop. The rare non-ASCII row falls
  /// back to the real encoder.
  void string(String value) {
    final units = value.codeUnits;
    _reserve(4 + units.length);
    final lengthAt = _length;
    _length += 4;
    final bytesAt = _length;
    var ascii = true;
    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      if (unit >= 0x80) {
        ascii = false;
        break;
      }
      _bytes[_length++] = unit;
    }
    if (!ascii) {
      _length = bytesAt;
      final bytes = utf8.encode(value);
      _reserve(bytes.length);
      _bytes.setRange(_length, _length + bytes.length, bytes);
      _length += bytes.length;
    }
    _bytes.buffer.asByteData(lengthAt, 4).setUint32(
      0,
      _length - bytesAt,
      Endian.little,
    );
  }

  Uint8List take() => Uint8List.sublistView(_bytes, 0, _length);

  void _reserve(int extra) {
    if (_length + extra <= _bytes.length) return;
    var size = _bytes.length * 2;
    while (size < _length + extra) {
      size *= 2;
    }
    _bytes = Uint8List(size)..setRange(0, _length, _bytes);
  }
}
