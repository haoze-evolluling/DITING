library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:diting_android/data/rules/rust_rule_core.dart';

typedef RuleSearchEntry = ({String pattern, String? target});

const _buildMagic = 0x31535244;

const _searchAbiVersion = 1;

const _noneLength = 0xFFFFFFFF;

class RuleSearchIndex {
  RuleSearchIndex(this._entries);

  final List<RuleSearchEntry> Function() _entries;

  int? _handle;

  Uint32List match(String needle) {
    final core = RustRuleCore.instance;
    final handle = _handle ??= core.buildSearchIndex(_encode(_entries()));
    return core.matchSearchIndex(handle, needle);
  }

  void dispose() {
    final handle = _handle;
    _handle = null;
    if (handle != null) RustRuleCore.instance.freeSearchIndex(handle);
  }
}

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

class _PayloadWriter {
  _PayloadWriter(int capacity) : _bytes = Uint8List(capacity < 64 ? 64 : capacity);

  Uint8List _bytes;
  int _length = 0;

  void u32(int value) {
    _reserve(4);
    _bytes.buffer.asByteData(_length, 4).setUint32(0, value, Endian.little);
    _length += 4;
  }

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
