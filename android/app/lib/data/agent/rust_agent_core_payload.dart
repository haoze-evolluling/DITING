part of 'rust_agent_core.dart';

/// Sequential little-endian writer over one call's request payload.
class _PayloadWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void u8(int value) => _bytes.addByte(value & 0xFF);

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void f64(double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void utf8(String value) {
    final encoded = const Utf8Codec().encode(value);
    u32(encoded.length);
    _bytes.add(encoded);
  }

  /// Unprefixed UTF-8, for the entries that take raw text instead of a payload.
  void rawUtf8(String value) => _bytes.add(const Utf8Codec().encode(value));

  /// `u32::MAX` marks an absent optional string, so no separate presence bit is needed.
  void optionalUtf8(String? value) {
    if (value == null) {
      u32(0xFFFFFFFF);
    } else {
      utf8(value);
    }
  }

  Uint8List finish() => _bytes.takeBytes();
}

/// Sequential little-endian reader over one call's answer payload. The payload is copied out of the
/// native buffer before this is used, because the caller releases it.
class _PayloadReader {
  _PayloadReader(Uint8List bytes)
    : _bytes = bytes,
      _view = ByteData.sublistView(bytes);

  final Uint8List _bytes;
  final ByteData _view;
  int _offset = 0;

  int u8() {
    final value = _view.getUint8(_offset);
    _offset += 1;
    return value;
  }

  int u32() {
    final value = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  String string() {
    final length = u32();
    final start = _offset;
    _offset += length;
    return const Utf8Codec().decode(
      Uint8List.sublistView(_bytes, start, start + length),
    );
  }

  String? optionalString() {
    final length = u32();
    if (length == 0xFFFFFFFF) return null;
    final start = _offset;
    _offset += length;
    return const Utf8Codec().decode(
      Uint8List.sublistView(_bytes, start, start + length),
    );
  }

  List<({String domain, int count})> domainCounts() {
    final count = u32();
    return List<({String domain, int count})>.generate(
      count,
      (_) => (domain: string(), count: u32()),
    );
  }
}
