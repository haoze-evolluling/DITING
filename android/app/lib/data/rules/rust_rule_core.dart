/// Optional native rule core: the Rust crate in `rust/diting-rule-core`, loaded over `dart:ffi`.
///
/// The Dart parser stays the source of truth for behaviour. [`RustRuleCore.instance`] is `null`
/// whenever the artifact is missing, the platform is unsupported, the ABI version differs or the
/// environment switch turns it off — `parseCategorized` then runs the Dart implementation, so a
/// build without the native library behaves exactly like before.
///
/// Payload layout lives in `rust/diting-rule-core/src/ffi.rs`; `_abiVersion` must match
/// `ABI_VERSION` there, and the Rust tests fail on a payload change precisely so this number moves
/// with it.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:diting_android/data/rules/rule_models.dart';

/// Must match `ABI_VERSION` in `rust/diting-rule-core/src/ffi.rs`.
const _abiVersion = 1;

/// Must match `SEARCH_ABI_VERSION` in `rust/diting-rule-core/src/search_ffi.rs`.
const _searchAbiVersion = 1;

/// `"DRC1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31435244;

/// `"DRQ1"`, the first field of every search result payload.
const _searchResultMagic = 0x31515244;

/// Environment switch: `DITING_RULE_CORE=off` keeps the Dart parser even when the library exists.
const _disableSwitch = 'off';

/// Explicit library path, for a dev build or a test runner outside the app bundle.
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

/// The stateful half of the library (`search_ffi.rs`), present only in artifacts that carry it: an
/// older `.so` keeps serving the parse path, so the two symbols sets are looked up separately.
class _SearchApi {
  const _SearchApi(this.build, this.query, this.freeIndex);

  final _SearchBuildDart build;
  final _SearchQueryDart query;
  final _SearchFreeDart freeIndex;
}

/// One quiet diagnostic line: the native core is optional, so a missing or broken artifact is a
/// fallback, not an error the user has to see.
void _note(String message) {
  developer.log(message, name: 'rust_rule_core');
}

class RustRuleCore {
  RustRuleCore._(
    this._parse,
    this._alloc,
    this._free,
    this.libraryPath,
    this._search,
  );

  final _ParseDart _parse;
  final _AllocDart _alloc;
  final _FreeDart _free;

  /// `null` when this artifact predates the search index; [`supportsSearch`] then reports false and
  /// the rules page keeps its Dart filter.
  final _SearchApi? _search;

  /// Resolved library path, surfaced in the benchmark tool and tests.
  final String libraryPath;

  static RustRuleCore? _instance;
  static bool _probed = false;
  static bool _disabled = false;
  static bool _searchDisabled = false;

  /// Whether [`buildSearchIndex`] and [`matchSearchIndex`] can be used.
  bool get supportsSearch => _search != null && !_searchDisabled;

  /// `null` when the native core cannot be used on this device/build.
  static RustRuleCore? get instance {
    if (!_probed) {
      _probed = true;
      _instance = _load();
    }
    return _instance;
  }

  static RustRuleCore? _load() {
    if (Platform.environment['DITING_RULE_CORE']?.toLowerCase() == _disableSwitch) {
      return null;
    }
    for (final candidate in _libraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
          'diting_rule_core_abi_version',
        )();
        if (abiVersion != _abiVersion) {
          _note(
            'rule core at $candidate speaks abi $abiVersion, expected $_abiVersion: '
            'using the Dart parser',
          );
          continue;
        }
        return RustRuleCore._(
          library.lookupFunction<_ParseNative, _ParseDart>('diting_rule_core_parse'),
          library.lookupFunction<_AllocNative, _AllocDart>('diting_rule_core_alloc'),
          library.lookupFunction<_FreeNative, _FreeDart>('diting_rule_core_free'),
          candidate,
          _loadSearch(library),
        );
      } catch (_) {
        // Missing artifact, wrong ABI or a missing symbol: try the next candidate.
      }
    }
    return null;
  }

  /// Looks up the search symbols separately: an artifact that only speaks the parse ABI still
  /// serves rule imports, and only the rules page falls back to its Dart filter.
  static _SearchApi? _loadSearch(DynamicLibrary library) {
    try {
      final abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        'diting_rule_core_search_abi_version',
      )();
      if (abiVersion != _searchAbiVersion) {
        _note(
          'rule search speaks abi $abiVersion, expected $_searchAbiVersion: '
          'using the Dart filter',
        );
        return null;
      }
      return _SearchApi(
        library.lookupFunction<_SearchBuildNative, _SearchBuildDart>(
          'diting_rule_core_search_build',
        ),
        library.lookupFunction<_SearchQueryNative, _SearchQueryDart>(
          'diting_rule_core_search_query',
        ),
        library.lookupFunction<_SearchFreeNative, _SearchFreeDart>(
          'diting_rule_core_search_free_index',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses a whole rule document, or returns `null` when anything goes wrong: the caller then
  /// runs the Dart implementation, so a broken artifact can never fail a rule import. A payload
  /// failure disables the core for the rest of the process to keep it from retrying per import.
  CategorizedRules? tryParse(String text) {
    if (_disabled) return null;
    try {
      return _parsePayload(text);
    } catch (error) {
      _disabled = true;
      _note('rule core disabled after a payload failure: $error');
      return null;
    }
  }

  /// Parses a whole rule document; throws on a malformed payload (see [tryParse]).
  CategorizedRules _parsePayload(String text) {
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

  /// Builds a search index from `payload` (layout in `search_ffi.rs`) and returns its handle.
  ///
  /// `null` when the artifact has no search symbols or the payload was rejected; the caller then
  /// keeps its Dart filter, and a failure disables the native path for the rest of the process so
  /// a broken artifact cannot make every keystroke retry it.
  int? buildSearchIndex(Uint8List payload) {
    final api = _search;
    if (api == null || _searchDisabled) return null;
    final inputPtr = payload.isEmpty ? nullptr : _alloc(payload.length);
    try {
      if (payload.isNotEmpty) {
        inputPtr.asTypedList(payload.length).setAll(0, payload);
      }
      final handle = api.build(inputPtr, payload.length);
      if (handle == 0) {
        _searchDisabled = true;
        _note('rule search disabled: the index payload was rejected');
        return null;
      }
      return handle;
    } catch (error) {
      _searchDisabled = true;
      _note('rule search disabled after a build failure: $error');
      return null;
    } finally {
      if (inputPtr != nullptr) _free(inputPtr, payload.length);
    }
  }

  /// Row indices in `handle` whose pattern or target contains [needle], ascending.
  ///
  /// `null` when the native index cannot serve the query (see [buildSearchIndex]); the caller then
  /// falls back to the Dart filter.
  Uint32List? matchSearchIndex(int handle, String needle) {
    final api = _search;
    if (api == null || _searchDisabled) return null;
    final bytes = utf8.encode(needle);
    final inputPtr = bytes.isEmpty ? nullptr : _alloc(bytes.length);
    final outLenPtr = _alloc(sizeOf<Size>()).cast<Size>();
    Pointer<Uint8> outputPtr = nullptr;
    var outputLength = 0;
    try {
      if (bytes.isNotEmpty) {
        inputPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      outputPtr = api.query(handle, inputPtr, bytes.length, outLenPtr);
      outputLength = outLenPtr.value;
      if (outputPtr == nullptr || outputLength == 0) {
        throw StateError('rule search returned no payload');
      }
      return _decodeHits(outputPtr.asTypedList(outputLength));
    } catch (error) {
      _searchDisabled = true;
      _note('rule search disabled after a query failure: $error');
      return null;
    } finally {
      if (inputPtr != nullptr) _free(inputPtr, bytes.length);
      _free(outLenPtr.cast<Uint8>(), sizeOf<Size>());
      if (outputPtr != nullptr && outputLength > 0) _free(outputPtr, outputLength);
    }
  }

  /// Releases an index built by [buildSearchIndex]. Unknown or already freed handles are ignored.
  void freeSearchIndex(int handle) {
    try {
      _search?.freeIndex(handle);
    } catch (error) {
      _note('rule search index $handle could not be released: $error');
    }
  }

  static String? _libraryName() {    // Cargo turns `diting-rule-core` into `libditing_rule_core.so` / `.dylib` and
    // `diting_rule_core.dll`; see `[lib] name` in the crate manifest.
    if (Platform.isAndroid || Platform.isLinux) return 'libditing_rule_core.so';
    if (Platform.isWindows) return 'diting_rule_core.dll';
    if (Platform.isMacOS) return 'libditing_rule_core.dylib';
    return null;
  }

  /// Probe order: explicit path, the packaged library name, then repo build output — the last one
  /// lets `flutter test` on the desktop host exercise the real native path without an APK.
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

/// Sequential reader over the search result payload (`encode_hits` in `search_ffi.rs`).
///
/// The row indices are copied into a `Uint32List` instead of being read one by one: a broad query
/// matches most of a subscription-sized table, and a boxed `List<int>` of 100k hits costs more than
/// the scan that produced it.
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
  // The payload is what Rust's allocator returned (8-byte aligned) and the index block starts at
  // offset 12, so the view is aligned; every Flutter target is little-endian, which is the byte
  // order `encode_hits` writes. Copied because the payload is released by the caller.
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

// ParsedRule record bits (see `encode_rule` in ffi.rs).
const _flagImportant = 1;
const _flagAppInverted = 2;
const _flagWildcard = 4;
const _flagRegex = 8;

// ParsedUrlRule record bits (see `encode_url_rule` in ffi.rs): `isAllow` is bit 1, so `important`
// moves to bit 2 — reusing `_flagImportant` here read the allow bit instead.
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

/// Sequential little-endian reader over the payload Rust wrote.
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

  /// `String.fromCharCodes` for ASCII (the common case, no decode pass) and UTF-8 otherwise.
  ///
  /// `utf8.decode` drops a leading BOM, but `rawLine` must stay byte-identical to the line the
  /// user imported (a UTF-8-BOM file keeps its BOM in the first rule), so the BOM is re-attached.
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
