library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:diting_android/data/rules/rule_models.dart';

const _abiVersion = 2;

/// 流式解析每批的行数；导入分片与之对齐，避免产生零碎尾批。
const ruleStreamChunkLines = 2048;

const _searchAbiVersion = 1;

const _payloadMagic = 0x31435244;

const _searchResultMagic = 0x31515244;

const _pathVariable = 'DITING_RULE_CORE_LIB';

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _ParseNative = Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>);
typedef _ParseDart = Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>);
typedef _AllocNative = Pointer<Uint8> Function(Size);
typedef _AllocDart = Pointer<Uint8> Function(int);
typedef _FreeNative = Void Function(Pointer<Uint8>, Size);
typedef _FreeDart = void Function(Pointer<Uint8>, int);
typedef _SearchBuildNative = Uint64 Function(Pointer<Uint8>, Size);
typedef _SearchBuildDart = int Function(Pointer<Uint8>, int);
typedef _SearchQueryNative =
    Pointer<Uint8> Function(Uint64, Pointer<Uint8>, Size, Pointer<Size>);
typedef _SearchQueryDart =
    Pointer<Uint8> Function(int, Pointer<Uint8>, int, Pointer<Size>);
typedef _SearchFreeNative = Uint32 Function(Uint64);
typedef _SearchFreeDart = int Function(int);
typedef _StreamBeginNative = Uint64 Function(Pointer<Uint8>, Size, Size);
typedef _StreamBeginDart = int Function(Pointer<Uint8>, int, int);
typedef _StreamNextNative = Pointer<Uint8> Function(Uint64, Pointer<Size>);
typedef _StreamNextDart = Pointer<Uint8> Function(int, Pointer<Size>);
typedef _StreamFreeNative = Void Function(Uint64);
typedef _StreamFreeDart = void Function(int);

class RustRuleCore {
  RustRuleCore._(
    this._parse,
    this._alloc,
    this._free,
    this._searchBuild,
    this._searchQuery,
    this._searchFree,
    this._streamBegin,
    this._streamNext,
    this._streamFree,
    this.libraryPath,
  );

  final _ParseDart _parse;
  final _AllocDart _alloc;
  final _FreeDart _free;
  final _SearchBuildDart _searchBuild;
  final _SearchQueryDart _searchQuery;
  final _SearchFreeDart _searchFree;
  final _StreamBeginDart _streamBegin;
  final _StreamNextDart _streamNext;
  final _StreamFreeDart _streamFree;

  final String libraryPath;

  static RustRuleCore? _instance;

  static RustRuleCore get instance => _instance ??= _load();

  static RustRuleCore _load() {
    final failures = <String>[];
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
          'diting_rule_core_abi_version',
        )();
        if (abiVersion != _abiVersion) {
          failures.add('$candidate: abi $abiVersion, expected $_abiVersion');
          continue;
        }
        final searchAbiVersion =
            library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
          'diting_rule_core_search_abi_version',
        )();
        if (searchAbiVersion != _searchAbiVersion) {
          failures.add(
            '$candidate: search abi $searchAbiVersion, expected $_searchAbiVersion',
          );
          continue;
        }
        return RustRuleCore._(
          library.lookupFunction<_ParseNative, _ParseDart>('diting_rule_core_parse'),
          library.lookupFunction<_AllocNative, _AllocDart>('diting_rule_core_alloc'),
          library.lookupFunction<_FreeNative, _FreeDart>('diting_rule_core_free'),
          library.lookupFunction<_SearchBuildNative, _SearchBuildDart>(
            'diting_rule_core_search_build',
          ),
          library.lookupFunction<_SearchQueryNative, _SearchQueryDart>(
            'diting_rule_core_search_query',
          ),
          library.lookupFunction<_SearchFreeNative, _SearchFreeDart>(
            'diting_rule_core_search_free_index',
          ),
          library.lookupFunction<_StreamBeginNative, _StreamBeginDart>(
            'diting_rule_core_stream_begin',
          ),
          library.lookupFunction<_StreamNextNative, _StreamNextDart>(
            'diting_rule_core_stream_next',
          ),
          library.lookupFunction<_StreamFreeNative, _StreamFreeDart>(
            'diting_rule_core_stream_free',
          ),
          candidate,
        );
      } catch (error) {
        failures.add('$candidate: $error');
      }
    }
    throw StateError(
      'rule core unavailable (${failures.isEmpty ? 'no candidate for this platform' : failures.join('; ')}): '
      'build it with `python rust/build_android.py`',
    );
  }

  CategorizedRules parse(String text) {
    final bytes = utf8.encode(text);
    final inputPtr = bytes.isEmpty ? nullptr : _alloc(bytes.length);
    final outLenPtr = _alloc(sizeOf<Size>()).cast<Size>();
    Pointer<Uint8> outputPtr = nullptr;
    var outputLength = 0;
    try {
      if (bytes.isNotEmpty) {
        inputPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      outputPtr = _parse(inputPtr, bytes.length, outLenPtr);
      outputLength = outLenPtr.value;
      if (outputPtr == nullptr || outputLength == 0) {
        throw StateError('rule core returned no payload');
      }
      return _decodeRules(outputPtr.asTypedList(outputLength));
    } finally {
      if (inputPtr != nullptr) _free(inputPtr, bytes.length);
      _free(outLenPtr.cast<Uint8>(), sizeOf<Size>());
      if (outputPtr != nullptr && outputLength > 0) _free(outputPtr, outputLength);
    }
  }

  int buildSearchIndex(Uint8List payload) {
    final inputPtr = payload.isEmpty ? nullptr : _alloc(payload.length);
    try {
      if (payload.isNotEmpty) {
        inputPtr.asTypedList(payload.length).setAll(0, payload);
      }
      final handle = _searchBuild(inputPtr, payload.length);
      if (handle == 0) {
        throw StateError('rule core rejected the search index payload');
      }
      return handle;
    } finally {
      if (inputPtr != nullptr) _free(inputPtr, payload.length);
    }
  }

  Uint32List matchSearchIndex(int handle, String needle) {
    final bytes = utf8.encode(needle);
    final inputPtr = bytes.isEmpty ? nullptr : _alloc(bytes.length);
    final outLenPtr = _alloc(sizeOf<Size>()).cast<Size>();
    Pointer<Uint8> outputPtr = nullptr;
    var outputLength = 0;
    try {
      if (bytes.isNotEmpty) {
        inputPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      outputPtr = _searchQuery(handle, inputPtr, bytes.length, outLenPtr);
      outputLength = outLenPtr.value;
      if (outputPtr == nullptr || outputLength == 0) {
        throw StateError('rule core returned no search payload');
      }
      return _decodeHits(outputPtr.asTypedList(outputLength));
    } finally {
      if (inputPtr != nullptr) _free(inputPtr, bytes.length);
      _free(outLenPtr.cast<Uint8>(), sizeOf<Size>());
      if (outputPtr != nullptr && outputLength > 0) _free(outputPtr, outputLength);
    }
  }

  void freeSearchIndex(int handle) {
    _searchFree(handle);
  }

  static const int _streamChunkLines = ruleStreamChunkLines;

  RuleStreamParse streamParse(String text) => streamParseBytes(utf8.encode(text));

  RuleStreamParse streamParseBytes(Uint8List bytes) {
    final inputPtr = bytes.isEmpty ? nullptr : _alloc(bytes.length);
    try {
      if (bytes.isNotEmpty) {
        inputPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      final handle = _streamBegin(inputPtr, bytes.length, _streamChunkLines);
      if (handle == 0) {
        throw StateError('rule core rejected the document');
      }
      return RuleStreamParse._(this, handle);
    } finally {
      if (inputPtr != nullptr) _free(inputPtr, bytes.length);
    }
  }

  static String? _libraryName() {
    if (Platform.isAndroid) return 'libditing_native.so';
    if (Platform.isLinux) return 'libditing_rule_core.so';
    if (Platform.isWindows) return 'diting_rule_core.dll';
    if (Platform.isMacOS) return 'libditing_rule_core.dylib';
    return null;
  }

  static Iterable<String> _libraryCandidates() sync* {
    final explicit = Platform.environment[_pathVariable];
    if (explicit != null && explicit.isNotEmpty) {
      yield explicit;
    }
    final libraryName = _libraryName();
    if (libraryName == null) {
      return;
    }
    yield libraryName;
    var directory = Directory.current;
    for (var depth = 0; depth < 6; depth++) {
      for (final profile in const ['release', 'debug']) {
        yield '${directory.path}/rust/target/$profile/$libraryName';
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        return;
      }
      directory = parent;
    }
  }
}

class RuleStreamParse {
  RuleStreamParse._(this._core, this._handle);

  final RustRuleCore _core;
  int _handle;
  bool _done = false;

  CategorizedRules? next() {
    if (_done) return null;
    final outLenPtr = _core._alloc(sizeOf<Size>()).cast<Size>();
    Pointer<Uint8> outputPtr = nullptr;
    var outputLength = 0;
    try {
      outputPtr = _core._streamNext(_handle, outLenPtr);
      outputLength = outLenPtr.value;
      if (outputPtr == nullptr || outputLength == 0) {
        _done = true;
        return null;
      }
      return _decodeRules(outputPtr.asTypedList(outputLength));
    } finally {
      _core._free(outLenPtr.cast<Uint8>(), sizeOf<Size>());
      if (outputPtr != nullptr && outputLength > 0) {
        _core._free(outputPtr, outputLength);
      }
    }
  }

  void dispose() {
    if (_handle != 0) {
      _core._streamFree(_handle);
      _handle = 0;
    }
    _done = true;
  }
}

Uint32List _decodeHits(Uint8List payload) {
  final reader = _PayloadReader(payload);
  if (reader.readU32() != _searchResultMagic) {
    throw const FormatException('rule search payload magic mismatch');
  }
  final abiVersion = reader.readU32();
  if (abiVersion != _searchAbiVersion) {
    throw FormatException('rule search payload abi $abiVersion, expected $_searchAbiVersion');
  }
  final count = reader.readU32();
  final start = reader._offset;
  if (start + count * 4 > payload.length) {
    throw const FormatException('rule search payload runs past the buffer');
  }
  return Uint32List.fromList(payload.buffer.asUint32List(start, count));
}

CategorizedRules _decodeRules(Uint8List payload) {
  final reader = _PayloadReader(payload);
  if (reader.readU32() != _payloadMagic) {
    throw const FormatException('rule core payload magic mismatch');
  }
  final abiVersion = reader.readU32();
  if (abiVersion != _abiVersion) {
    throw FormatException('rule core payload abi $abiVersion, expected $_abiVersion');
  }
  final totalLines = reader.readU32();
  final duplicateCount = reader.readU32();
  final invalidCount = reader.readU32();
  final unsupportedCount = reader.readU32();
  final ignoredCount = reader.readU32();
  final badfilteredCount = reader.readU32();
  final blockCount = reader.readU32();
  final allowCount = reader.readU32();
  final rewriteCount = reader.readU32();
  final urlBlockCount = reader.readU32();
  final urlAllowCount = reader.readU32();
  final cosmeticCount = reader.readU32();

  return CategorizedRules(
    blockRules: List.generate(blockCount, (_) => _readRule(reader)),
    allowRules: List.generate(allowCount, (_) => _readRule(reader)),
    rewriteRules: List.generate(rewriteCount, (_) => _readRewriteRule(reader)),
    urlBlockRules: List.generate(urlBlockCount, (_) => _readUrlRule(reader)),
    urlAllowRules: List.generate(urlAllowCount, (_) => _readUrlRule(reader)),
    cosmeticRules: List.generate(cosmeticCount, (_) => _readCosmeticRule(reader)),
    duplicateCount: duplicateCount,
    invalidCount: invalidCount,
    unsupportedCount: unsupportedCount,
    ignoredCount: ignoredCount,
    badfilteredCount: badfilteredCount,
    totalLines: totalLines,
  );
}

const _flagImportant = 1;
const _flagAppInverted = 2;
const _flagWildcard = 4;
const _flagRegex = 8;

const _flagUrlAllow = 1;
const _flagUrlImportant = 2;

ParsedRule _readRule(_PayloadReader reader) {
  final pattern = reader.readString();
  final rawLine = reader.readString();
  final flags = reader.readU8();
  return ParsedRule(
    pattern: pattern,
    rawLine: rawLine,
    important: flags & _flagImportant != 0,
    appInverted: flags & _flagAppInverted != 0,
    isWildcard: flags & _flagWildcard != 0,
    isRegex: flags & _flagRegex != 0,
    appScope: reader.readOptionalString(),
    denyallow: reader.readOptionalString(),
    dnsType: reader.readOptionalString(),
  );
}

ParsedRewriteRule _readRewriteRule(_PayloadReader reader) {
  final pattern = reader.readString();
  final rawLine = reader.readString();
  final targetType = reader.readString();
  final targetValue = reader.readString();
  return ParsedRewriteRule(
    pattern: pattern,
    targetType: targetType,
    targetValue: targetValue,
    rawLine: rawLine,
  );
}

ParsedUrlRule _readUrlRule(_PayloadReader reader) {
  final pattern = reader.readString();
  final rawLine = reader.readString();
  final flags = reader.readU8();
  return ParsedUrlRule(
    pattern: pattern,
    rawLine: rawLine,
    isAllow: flags & _flagUrlAllow != 0,
    important: flags & _flagUrlImportant != 0,
    appScope: reader.readOptionalString(),
  );
}

ParsedCosmeticRule _readCosmeticRule(_PayloadReader reader) {
  final domain = reader.readString();
  final selector = reader.readString();
  final rawLine = reader.readString();
  return ParsedCosmeticRule(
    domain: domain,
    selector: selector,
    rawLine: rawLine,
    isException: reader.readU8() == 1,
  );
}

class _PayloadReader {
  _PayloadReader(this._bytes) : _view = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _view;
  int _offset = 0;

  int readU8() {
    final value = _view.getUint8(_offset);
    _offset += 1;
    return value;
  }

  int readU32() {
    final value = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  String readString() {
    final value = readOptionalString();
    if (value == null) {
      throw const FormatException('rule core payload has a null required string');
    }
    return value;
  }

  String? readOptionalString() {
    final length = readU32();
    if (length == 0xFFFFFFFF) {
      return null;
    }
    final start = _offset;
    _offset += length;
    if (start + length > _bytes.length) {
      throw const FormatException('rule core payload string runs past the buffer');
    }
    return _stringAt(start, length);
  }

  String _stringAt(int start, int length) {
    if (length == 0) return '';
    var isAscii = true;
    for (var index = start; index < start + length; index++) {
      if (_bytes[index] >= 0x80) {
        isAscii = false;
        break;
      }
    }
    if (isAscii) {
      return String.fromCharCodes(_bytes, start, start + length);
    }
    final end = start + length;
    const bomLength = 3;
    final hasBom = length >= bomLength &&
        _bytes[start] == 0xEF &&
        _bytes[start + 1] == 0xBB &&
        _bytes[start + 2] == 0xBF;
    final decoded = utf8.decode(
      Uint8List.sublistView(_bytes, hasBom ? start + bomLength : start, end),
    );
    return hasBom ? '\uFEFF$decoded' : decoded;
  }
}
