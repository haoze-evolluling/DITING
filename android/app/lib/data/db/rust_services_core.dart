/// The native service-catalog core: the Rust crate in `rust/diting-services-core`, loaded over
/// `dart:ffi`.
///
/// The catalog (categories → services → domains) and the expansion to rule-group patterns live in
/// Rust so the preset list and the generated rules cannot drift. The timed blocking page (R7) and
/// the automation editor both read this single source.
///
/// Payloads are JSON with the shared kernel header — `magic "DSV1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DSV1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31565344;

class RustServicesCore {
  RustServicesCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustServicesCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustServicesCore get instance => _instance ??= _load();

  static RustServicesCore _load() => RustServicesCore._(
    KernelCore.load(
      crate: 'diting-services-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'services core',
    ),
  );

  /// The whole catalog: `{categories, services:[{id,name,category,domains}]}`.
  Map<String, Object?> catalog() => call({'op': 'services.catalog'});

  /// Expands the selected service ids to rule patterns for a `block` (or `allow`) group.
  Map<String, Object?> expand({
    required List<String> serviceIds,
    String kind = 'block',
  }) => call({'op': 'services.expand', 'serviceIds': serviceIds, 'kind': kind});

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
