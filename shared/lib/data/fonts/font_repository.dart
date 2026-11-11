/// User-supplied fonts: import a TTF/OTF, register it with the engine, and remember it across
/// restarts. The app bundles no fonts of its own, so this is the only source of non-system faces.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:convert';
import 'dart:io';

import 'package:diting_shared/data/native/platform_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One imported font. [family] is the `TextStyle.fontFamily` key handed to the engine; it is
/// derived from the file name at import time and stays stable, because renaming the family would
/// require re-registering the bytes under a new key.
@immutable
class ImportedFont {
  const ImportedFont({
    required this.family,
    required this.label,
    required this.path,
  });

  final String family;
  final String label;
  final String path;

  Map<String, Object?> toJson() => {
    'family': family,
    'label': label,
    'path': path,
  };

  static ImportedFont? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final family = raw['family'];
    final path = raw['path'];
    if (family is! String ||
        family.isEmpty ||
        path is! String ||
        path.isEmpty) {
      return null;
    }
    final label = raw['label'];
    return ImportedFont(
      family: family,
      label: label is String && label.isNotEmpty ? label : family,
      path: path,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ImportedFont &&
      other.family == family &&
      other.label == label &&
      other.path == path;

  @override
  int get hashCode => Object.hash(family, label, path);
}

/// Outcome of an import, so the page can tell "user backed out" from "bad file".
class FontImportResult {
  const FontImportResult({this.font, this.cancelled = false, this.error});

  const FontImportResult.cancelled()
    : font = null,
      cancelled = true,
      error = null;

  const FontImportResult.failed(String this.error)
    : font = null,
      cancelled = false;

  final ImportedFont? font;
  final bool cancelled;
  final String? error;

  bool get isOk => font != null;
}

/// Owns the imported-font list: reads it from settings, registers the bytes with the engine, and
/// keeps both in sync when the user imports or deletes.
///
/// Registration must happen before the first frame, because `ThemeData.fontFamily` is resolved
/// when the theme is built — a family the engine has never seen silently falls back to the system
/// default. [registerAll] is therefore called from `main()` before `runApp`.
class FontRepository {
  FontRepository({required this.settings, PlatformBridge? bridge})
    : _bridge = bridge ?? PlatformBridge();

  final LegacySettings settings;
  final PlatformBridge _bridge;

  /// Families currently registered with the engine, so a second call does not pay for the decode.
  static final Set<String> _registered = <String>{};

  List<ImportedFont> get fonts => settings.importedFonts;

  ImportedFont? byFamily(String? family) {
    if (family == null) {
      return null;
    }
    for (final font in fonts) {
      if (font.family == family) {
        return font;
      }
    }
    return null;
  }

  /// Registers every stored font; failures are dropped from the list so a file deleted outside the
  /// app cannot leave a dead entry behind. Returns the fonts that loaded.
  Future<List<ImportedFont>> registerAll() async {
    final fonts = this.fonts;
    if (fonts.isEmpty) {
      return const [];
    }
    final loaded = <ImportedFont>[];
    final broken = <ImportedFont>[];
    for (final font in fonts) {
      if (await _register(font)) {
        loaded.add(font);
      } else {
        broken.add(font);
      }
    }
    if (broken.isNotEmpty) {
      final remaining = [
        for (final font in fonts)
          if (!broken.contains(font)) font,
      ];
      settings.setImportedFonts(remaining);
    }
    return loaded;
  }

  /// Opens the system picker and imports the chosen file. The family name is the file's base name,
  /// de-duplicated with a numeric suffix so two `Inter.ttf` copies stay distinguishable.
  Future<FontImportResult> import() async {
    final picked = await _bridge.pickFontFile();
    if (picked.cancelled) {
      return const FontImportResult.cancelled();
    }
    if (!picked.isOk) {
      return FontImportResult.failed(picked.error ?? currentL10n.fontImportFailed);
    }
    final path = picked.path!;
    final file = File(path);
    if (!await file.exists()) {
      return FontImportResult.failed(currentL10n.fontReadFailed);
    }
    final base = _baseName(picked.name ?? file.uri.pathSegments.last);
    final font = ImportedFont(
      family: _uniqueFamily(base),
      label: base,
      path: path,
    );
    if (!await _register(font)) {
      await _bridge.deleteFontFile(path);
      return FontImportResult.failed(currentL10n.fontParseFailed);
    }
    settings.setImportedFonts([...fonts, font]);
    return FontImportResult(font: font);
  }

  /// Removes the font from the list and deletes the copied file. The engine keeps the registered
  /// bytes for the lifetime of the process; clearing the selection is what makes the UI stop using
  /// them, so callers select the system default first when the deleted font was active.
  Future<void> delete(ImportedFont font) async {
    final remaining = [
      for (final item in fonts)
        if (item != font) item,
    ];
    settings.setImportedFonts(remaining);
    _registered.remove(font.family);
    await _bridge.deleteFontFile(font.path);
  }

  Future<bool> _register(ImportedFont font) async {
    if (_registered.contains(font.family)) {
      return true;
    }
    final ByteData bytes;
    try {
      bytes = ByteData.sublistView(await File(font.path).readAsBytes());
    } on FileSystemException {
      return false;
    }
    try {
      // `FontLoader` is the supported path for registering bytes at runtime; the family it
      // registers under must match the `fontFamily` used in `TextStyle`.
      final loader = FontLoader(font.family)
        ..addFont(Future<ByteData>.value(bytes));
      await loader.load();
    } on Exception {
      return false;
    }
    _registered.add(font.family);
    return true;
  }

  String _uniqueFamily(String base) {
    final taken = {for (final font in fonts) font.family};
    if (!taken.contains(base)) {
      return base;
    }
    for (var index = 2; ; index++) {
      final candidate = '$base $index';
      if (!taken.contains(candidate)) {
        return candidate;
      }
    }
  }

  /// `Inter-Regular.ttf` → `Inter-Regular`: the extension says nothing about the face.
  static String _baseName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final trimmed = stem.trim();
    return trimmed.isEmpty ? currentL10n.fontCustomName : trimmed;
  }
}

/// Storage for the imported list: the settings layer keeps the raw JSON, the shape lives here.
extension ImportedFontSettings on LegacySettings {
  List<ImportedFont> get importedFonts {
    final raw = importedFontsRaw;
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return [for (final item in decoded) ?ImportedFont.fromJson(item)];
    } on FormatException {
      return const [];
    }
  }

  void setImportedFonts(List<ImportedFont> fonts) => setImportedFontsRaw(
    jsonEncode([for (final font in fonts) font.toJson()]),
  );
}
