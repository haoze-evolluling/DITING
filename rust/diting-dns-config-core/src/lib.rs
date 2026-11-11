//! Rust core for the Android DNS configuration documents: the tunnel's `ApplyDNSConfig` snapshot and
//! server mode's `applyDnsConfig` snapshot, plus the provider / bootstrap / upstream record lists and
//! the three cache presets behind them.
//!
//! This is the only implementation. `RustDnsConfigCore.instance` loads the library at runtime and
//! throws when the artifact is missing or its ABI version differs, so a build that forgot
//! `python rust/build_android.py` fails on the first config push instead of quietly pushing a
//! second, drifting document.
//!
//! The engine-side name tables (protocol, scheduling mode, block response) come from
//! [`diting_config_core`], the kernel the Go engine validates every pushed config against, so the
//! app cannot spell `PLAIN` differently from the reader.
//!
//! Layout:
//! * [`protocol`] — storage spelling (`DNS` / `DOH` / `DOT`) to document spelling, default ports,
//!   `host:port` joins and the block-response mapping.
//! * [`providers`] — the provider catalog rows and `user_providers_json`.
//! * [`bootstrap`] — the custom bootstrap rows behind `bootstrap_custom_json`.
//! * [`presets`] — the three cache presets, their derivation and server mode's negative TTLs.
//! * [`upstreams`] — server mode's custom upstream rows, validation kinds and address normalizing.
//! * [`document`] — the two documents (mode selection, provider picking, bootstrap rows, clamps).
//! * [`input`] / [`wire`] — the `dart:ffi` payload layouts.
//! * [`ffi`] — the C ABI surface.

pub mod bootstrap;
pub mod document;
pub mod ffi;
pub mod input;
pub mod presets;
pub mod protocol;
pub mod providers;
pub mod upstreams;
pub mod wire;

pub use bootstrap::BootstrapRow;
pub use document::{
    build_server, build_tunnel, BootstrapEntry, CacheInput, DynamicInput, ServerConfig,
    ServerSettings, TunnelConfig, TunnelSettings,
};
pub use ffi::ABI_VERSION;
pub use presets::{CachePolicy, CachePreset, CacheValues};
pub use protocol::Protocol;
pub use providers::Provider;
pub use upstreams::ServerUpstream;
