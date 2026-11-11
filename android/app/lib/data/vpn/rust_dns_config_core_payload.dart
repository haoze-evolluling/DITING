part of 'rust_dns_config_core.dart';

/// Sequential little-endian writer over one call's request payload.
class _PayloadWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void u8(int value) => _bytes.addByte(value & 0xFF);

  void flag(bool value) => u8(value ? 1 : 0);

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void utf8(String value) {
    final encoded = const Utf8Codec().encode(value);
    u32(encoded.length);
    _bytes.add(encoded);
  }

  /// `u32::MAX` marks an absent optional string, so no separate presence bit is needed.
  void optionalUtf8(String? value) {
    if (value == null) {
      u32(0xFFFFFFFF);
    } else {
      utf8(value);
    }
  }

  void strings(List<String> values) {
    u32(values.length);
    for (final value in values) {
      utf8(value);
    }
  }

  void providerRows(List<ProviderRow> rows) {
    u32(rows.length);
    for (final row in rows) {
      utf8(row.id);
      utf8(row.name);
      utf8(row.protocolStorage);
      utf8(row.url);
      utf8(row.host);
      i32(row.port);
    }
  }

  void bootstrapEntryRows(List<BootstrapEntryRow> rows) {
    u32(rows.length);
    for (final row in rows) {
      utf8(row.id);
      utf8(row.name);
      utf8(row.ip);
    }
  }

  void bootstrapCustomRows(List<BootstrapRow> rows) {
    u32(rows.length);
    for (final row in rows) {
      utf8(row.id);
      utf8(row.name);
      utf8(row.ip);
      flag(row.enabled);
    }
  }

  void upstreamRows(List<ServerUpstreamRow> rows) {
    u32(rows.length);
    for (final row in rows) {
      utf8(row.id);
      utf8(row.name);
      utf8(row.protocolStorage);
      utf8(row.address);
      i32(row.port);
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

  bool flag() => u8() != 0;

  int u32() {
    final value = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int i32() {
    final value = _view.getInt32(_offset, Endian.little);
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

  List<ProviderRow> providerRows() => List<ProviderRow>.generate(
    u32(),
    (_) => (
      id: string(),
      name: string(),
      protocolStorage: string(),
      url: string(),
      host: string(),
      port: i32(),
    ),
  );

  List<BootstrapEntryRow> bootstrapEntryRows() =>
      List<BootstrapEntryRow>.generate(
        u32(),
        (_) => (id: string(), name: string(), ip: string()),
      );

  List<BootstrapRow> bootstrapCustomRows() => List<BootstrapRow>.generate(
    u32(),
    (_) => (id: string(), name: string(), ip: string(), enabled: flag()),
  );

  List<ServerUpstreamRow> upstreamRows() => List<ServerUpstreamRow>.generate(
    u32(),
    (_) => (
      id: string(),
      name: string(),
      protocolStorage: string(),
      address: string(),
      port: i32(),
    ),
  );
}
