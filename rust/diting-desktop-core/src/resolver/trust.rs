//! The desktop trust store.
//!
//! Android's `UpstreamTrust::platform()` reads the Android CA directories; a desktop build must
//! read the operating system's roots instead (Windows CryptoAPI via `rustls-native-certs`, Linux
//! CA bundles), then add the two bundled ISRG roots exactly like the Go service's
//! `upstreamRootPool()` did.

use std::sync::Arc;

use diting_engine::resolver::trust::UpstreamTrust;
#[cfg(not(target_os = "android"))]
use diting_engine::resolver::trust::{add_pem_roots, BUNDLED_ROOTS};
#[cfg(not(target_os = "android"))]
use rustls::RootCertStore;

/// The process-wide root pool.
#[cfg(target_os = "android")]
pub fn os_trust() -> Arc<UpstreamTrust> {
    // Android has no `/etc/ssl/certs` bundle for `rustls-native-certs`; the engine's platform
    // loader reads the hashed `/system/etc/security/cacerts` and Conscrypt APEX directories.
    Arc::new(UpstreamTrust::platform())
}

/// The process-wide root pool.
#[cfg(not(target_os = "android"))]
pub fn os_trust() -> Arc<UpstreamTrust> {
    let mut roots = RootCertStore::empty();
    let native = rustls_native_certs::load_native_certs();
    let (accepted, _) = roots.add_parsable_certificates(native.certs);
    if accepted == 0 {
        eprintln!("[resolver] no operating-system CA certificates were loaded");
    }
    add_pem_roots(&mut roots, &BUNDLED_ROOTS);
    Arc::new(UpstreamTrust::from_roots(roots))
}
