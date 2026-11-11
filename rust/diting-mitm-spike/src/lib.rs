//! Stage 0 Spike 2 for the Android engine migration: can `rustls` + `hyper` hold the MITM relay
//! semantics the Go engine implemented with `crypto/tls` + `net/http`?
//!
//! The Go engine's MITM path is four pieces, and this crate answers each one in Rust:
//!
//! | Go | Here |
//! | --- | --- |
//! | `CertManager.GetDynamicTLSConfigForHost` (`GetCertificate` + LRU + single flight) | [`cert::CertStore`], a `ResolvesServerCert` that mints with `diting-cert-core` |
//! | `upstreamTLSConfig` (`SystemCertPool` + ISRG roots, `GetClientCertificate`, EV check) | [`trust`] + [`upstream::UpstreamTls`] |
//! | `mitmTLSFlow` + `relayHTTPFlow` (`tls.Server`, `http.ReadRequest`/`ReadResponse`) | [`relay::Proxy`] over `hyper` HTTP/1.1 |
//! | `wrapResponseForInjection` + `injectingReader` (`compress/gzip`, `io.Reader`) | [`inject`], streaming on `AsyncRead` |
//!
//! The prototype is deliberately not in the APK and not wired to the TUN device: it is driven by real
//! loopback TCP + TLS + HTTP/1.1 in `tests/`, so every claim this crate makes is reproducible on a
//! host with no device, no root and no privileged port.

pub mod cert;
pub mod inject;
pub mod relay;
pub mod trust;
pub mod upstream;

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use http_body_util::combinators::UnsyncBoxBody;

/// The error type the relay boxes: hyper, rustls, io and hand-written messages all fit.
pub type BoxError = Box<dyn std::error::Error + Send + Sync>;

/// The single response body type of the relay: passthrough, injected or a local error page.
pub type ResponseBody = UnsyncBoxBody<bytes::Bytes, BoxError>;

/// The crypto provider every `rustls` config in the engine is built from.
///
/// `ring` rather than `aws-lc-rs`: it is pure Rust plus a small per-arch assembly build, which is
/// what the existing Android cross-compilation already produces, and it keeps `libditing_engine.so`
/// free of a second C build step. The provider is passed explicitly instead of installing a process
/// default, because a process global would make two engine instances share one policy.
pub fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// Seconds since the Unix epoch, the clock every kernel entry point takes explicitly.
pub fn now_unix() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(elapsed) => elapsed.as_secs() as i64,
        Err(_) => 0,
    }
}
