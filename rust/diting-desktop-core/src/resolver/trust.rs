use std::sync::Arc;

use diting_engine::resolver::trust::UpstreamTrust;
#[cfg(not(target_os = "android"))]
use diting_engine::resolver::trust::{add_pem_roots, BUNDLED_ROOTS};
#[cfg(not(target_os = "android"))]
use rustls::RootCertStore;

#[cfg(target_os = "android")]
pub fn os_trust() -> Arc<UpstreamTrust> {
    Arc::new(UpstreamTrust::platform())
}

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
