//! The network-profile evaluator of the Android app (N1 / K5).
//!
//! Wi-Fi / cellular / roaming / metered / validated each want a different upstream set, rule-group
//! state and feature-toggle set. Kotlin normalizes `ConnectivityManager` into one
//! [`profile::NetworkContext`]; this crate owns the *decision* of which configured profile that
//! context selects, and nothing else. There is no clock, no I/O and no platform call: the same
//! context and the same profile list always resolve to the same reference, so the editor's preview
//! and the runtime's apply share one implementation.
//!
//! Layout:
//! * [`profile`] — the context / match / profile types, [`profile::resolve`] and its unit tests.
//! * [`payload`] — typed reads of the JSON payload (`None` when a shape does not fit).
//! * [`ffi`] — the C ABI (`magic "DNP1" | abi` header) a `dart:ffi` caller loads.

pub mod ffi;
pub mod payload;
pub mod profile;

pub use ffi::ABI_VERSION;
pub use profile::{resolve, NetworkContext, NetworkMatch, Profile, Resolution};
