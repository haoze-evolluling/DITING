//! The desktop trust store.
//!
//! Android's `UpstreamTrust::platform()` reads the Android CA directories; a desktop build must
//! read the operating system's roots instead (Windows CryptoAPI via `rustls-native-certs`, Linux
//! CA bundles), then add the two bundled ISRG roots exactly like the Go service's
//! `upstreamRootPool()` did.

use std::sync::Arc;

use diting_engine::resolver::trust::{add_pem_roots, UpstreamTrust, BUNDLED_ROOTS};
use rustls::RootCertStore;

/// The process-wide root pool.
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
