library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:diting_android/data/db/kernel_core.dart';

part 'rust_dns_config_core_build.dart';
part 'rust_dns_config_core_payload.dart';
part 'rust_dns_config_core_records.dart';

const _abiVersion = 4;

const _payloadMagic = 0x31434444;

const _opSplitAddress = 0;
const _opParseProviders = 1;
const _opEncodeProviders = 2;
const _opUpsertProvider = 3;
const _opJoinHostPort = 4;
const _opParseBootstrap = 5;
const _opEncodeBootstrap = 6;

class RustDnsConfigCore {
  RustDnsConfigCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustDnsConfigCore? _instance;

  static RustDnsConfigCore get instance => _instance ??= _load();

  static RustDnsConfigCore _load() => RustDnsConfigCore._(
    KernelCore.load(
      crate: 'diting-dns-config-core',
      payloadMagic: _payloadMagic,
      abiVersion: _abiVersion,
      errorPrefix: 'dns config core',
      entries: const ['tunnel', 'providers'],
    ),
  );

  ({String url, String host, int port}) splitProviderAddress(
    String protocolStorage,
    String address,
  ) {
    final reader = _call(
      'providers',
      _PayloadWriter()
        ..u8(_opSplitAddress)
        ..utf8(protocolStorage)
        ..utf8(address),
    );
    final url = reader.string();
    final host = reader.string();
    return (url: url, host: host, port: reader.i32());
  }

  List<ProviderRow> parseUserProviders(String? raw) {
    final reader = _call(
      'providers',
      _PayloadWriter()
        ..u8(_opParseProviders)
        ..optionalUtf8(raw),
    );
    return reader.providerRows();
  }

  String encodeUserProviders(List<ProviderRow> rows) {
    final reader = _call(
      'providers',
      _PayloadWriter()
        ..u8(_opEncodeProviders)
        ..providerRows(rows),
    );
    return reader.string();
  }

  List<ProviderRow> upsertUserProvider(
    List<ProviderRow> rows, {
    required String id,
    required String name,
    required String protocolStorage,
    required String address,
  }) {
    final writer = _PayloadWriter()
      ..u8(_opUpsertProvider)
      ..providerRows(rows)
      ..utf8(id)
      ..utf8(name)
      ..utf8(protocolStorage)
      ..utf8(address);
    return _call('providers', writer).providerRows();
  }

  String joinHostPort(String host, int port) {
    final reader = _call(
      'providers',
      _PayloadWriter()
        ..u8(_opJoinHostPort)
        ..utf8(host)
        ..i32(port),
    );
    return reader.string();
  }

  List<BootstrapRow> parseCustomBootstrap(String? raw) {
    final reader = _call(
      'providers',
      _PayloadWriter()
        ..u8(_opParseBootstrap)
        ..optionalUtf8(raw),
    );
    return reader.bootstrapCustomRows();
  }

  String encodeCustomBootstrap(List<BootstrapRow> rows) {
    final reader = _call(
      'providers',
      _PayloadWriter()
        ..u8(_opEncodeBootstrap)
        ..bootstrapCustomRows(rows),
    );
    return reader.string();
  }

  _PayloadReader _call(String entry, _PayloadWriter writer) {
    final reply = _core.invoke(writer.finish(), entry: entry);
    if (reply.isEmpty) {
      throw StateError('dns config core rejected the payload');
    }
    final reader = _PayloadReader(reply);
    if (reader.u32() != _payloadMagic) {
      throw const FormatException('dns config core payload magic mismatch');
    }
    final abiVersion = reader.u32();
    if (abiVersion != _abiVersion) {
      throw FormatException(
        'dns config core payload abi $abiVersion, expected $_abiVersion',
      );
    }
    return reader;
  }
}
