/// Lenient JSON accessors for legacy backup data; each returns null instead of throwing on
/// malformed input.
library;

abstract final class BackupJson {
  static Map<Object?, Object?>? map(Object? value) =>
      value is Map ? Map<Object?, Object?>.from(value) : null;

  static String? text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? integer(Object? value) => switch (value) {
    int() => value,
    num() => value.round(),
    String() => int.tryParse(value),
    _ => null,
  };

  /// Decimal from any numeric form; legacy XML stored opacity as `<float>`.
  static double? decimal(Object? value) => switch (value) {
    double() => value,
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };

  /// Trimmed non-blank string entries; non-strings and blanks are dropped.
  static List<String> strings(Object? value) {
    if (value is! List) return const [];
    final result = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) result.add(item.trim());
    }
    return result;
  }
}
