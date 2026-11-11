part of 'rust_dns_config_core.dart';

/// One provider row: a preset, a stored custom record, or a picked document row.
///
/// `protocolStorage` is the prefs spelling (`DNS` / `DOH` / `DOT`); the document spelling
/// (`PLAIN` / `DOH` / `DOT`) is decided by the kernel.
typedef ProviderRow = ({
  String id,
  String name,
  String protocolStorage,
  String url,
  String host,
  int port,
});

/// A bootstrap row as the document carries it (no `enabled`: only enabled rows get here).
typedef BootstrapEntryRow = ({String id, String name, String ip});

/// A `bootstrap_custom_json` row, which keeps the toggle the settings page edits.
typedef BootstrapRow = ({String id, String name, String ip, bool enabled});

/// A server-mode upstream: a preset row, a stored custom record, or the picked one.
typedef ServerUpstreamRow = ({
  String id,
  String name,
  String protocolStorage,
  String address,
  int port,
});

/// The nine values a cache preset writes into the prefs.
typedef CacheValues = ({
  String mode,
  int maxTtlSeconds,
  int fixedTtlSeconds,
  bool minTtlEnabled,
  int minTtlSeconds,
  bool staleFallbackEnabled,
  int staleFallbackSeconds,
});

/// The tunnel document plus the rows the UI shows.
typedef TunnelDocument = ({
  String mode,
  String document,
  List<ProviderRow> providers,
  List<BootstrapEntryRow> bootstrap,
});

/// The server-mode document plus the upstreams it picked (engine attempt order: one row in
/// `single`, the whole race list otherwise).
typedef ServerDocument = ({
  int port,
  String mode,
  String document,
  List<ServerUpstreamRow> providers,
});

/// Why a custom upstream was rejected. Declaration order matches `upstreams::UpstreamInvalid`.
enum UpstreamRejection {
  nameRequired,
  addressRequired,
  dohNeedsHttps,
  dohInvalidUrl,
  portRange,
  ipv6Invalid,
}
