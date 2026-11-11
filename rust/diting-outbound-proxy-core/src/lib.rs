//! Outbound-proxy app configuration: the Dart form rules and the Kotlin storage/UID bridge.
//!
//! The engine already validates protocol, loopback host, port, credentials and scope in
//! [`diting_proxy_core::config`]; this crate imports those helpers so the UI cannot accept a value
//! the engine would reject. It adds the app package, installed-package and per-app target checks,
//! the exact engine JSON, and the Kotlin JNI entry points that normalize stored fields or resolve
//! package names to UIDs.
//!
//! HTTP, Android SharedPreferences, the Keystore and PackageManager stay in Dart/Kotlin.

mod config;
mod ffi;
mod jni_bridge;

pub use config::{
    apply_uids, filter_targets, packages_of, protocol_or_default, scope_or_default, AppConfig,
};
