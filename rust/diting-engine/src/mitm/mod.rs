//! MITM: the TLS/HTTP interception half of the data plane (stage 4b).
//!
//! ```text
//! Go (android/engine)                     here
//! engine_mitm.go      StartStackMitm    → Mitm::start (CA on disk, filter, upstream TLS)
//! mitm_cert_manager.go                    → cert.rs
//! mitm_trust.go + upstreamTLSConfig       → upstream.rs (+ resolver::trust for the pool)
//! mitm_filter.go                          → filter.rs (diting-mitm-core behind a shared handle)
//! mitm_sniffer.go     peek + classify     → handler.rs + diting-sniffer-core
//! mitm_handler.go     the decision chain  → handler.rs
//! mitm_relay.go + mitm_common.go          → http.rs (hyper HTTP/1.1) + inject.rs
//! mitm_local_relay.go + mitm_local_server → local.rs
//! engine_request_filter.go                → http.rs (diting-request-core)
//! ```
//!
//! Every decision that already exists as a kernel stays there: the root CA and the leaf minting
//! (`diting-cert-core`), the smart filter (`diting-mitm-core`), the ClientHello/plaintext sniffer
//! (`diting-sniffer-core`), the cosmetic scanner and local asset server (`diting-cosmetic-core`) and
//! the request rules (`diting-request-core`). What this module adds is the plumbing Go wrote by
//! hand: `crypto/tls` becomes `rustls`, `net/http` becomes `hyper`, and the peek/relay becomes a
//! byte-stream adapter over the TUN flow's channel.
//!
//! # Two states, deliberately separate
//!
//! * [`Mitm`] is the *session*: it exists only between `startStackMitm` and `stopStackMitm`, owns the
//!   root CA (on disk, `.go-mitm/ca.crt` + `ca.key`), the blacklist file and the minted-leaf cache.
//!   Dropping it throws every leaf away, which is what `Release()` did.
//! * [`MitmSettings`] is *configuration*: the cosmetic rule set, the request rules and the HTTP log
//!   callback. Kotlin pushes them independently of the session, and they must survive a stop/start
//!   like they did in Go (they were engine fields there).
//!
//! # What is not here
//!
//! `setAppAllowlist` still has no Kotlin caller (migration plan §4.3), so the gate is asked with
//! "allowed". `SetExtraPassthroughSuffixes` is the same list as `SetHttpsBypassRules` and is kept as
//! an alias. WebSocket upgrades and HTTP/2 upstream are not relayed (recorded in the stage 4b notes).

pub mod cert;
pub mod filter;
pub mod handler;
pub mod http;
pub mod inject;
pub mod local;
pub mod settings;
pub mod stream;
pub mod upstream;

use std::sync::{Arc, RwLock};

use crate::resolver::UpstreamTrust;

pub use cert::{CaStatus, CertStore};
pub use filter::Filter;
pub use settings::{HttpLogSink, MitmSettings};
pub use upstream::UpstreamTls;

/// The file name `ca.crt` (kept so an installed root survives the upgrade).
pub const CA_CERT_FILE: &str = "ca.crt";
/// The file name `ca.key` (written with mode 0600 when the CA is generated).
pub const CA_KEY_FILE: &str = "ca.key";
/// The file name the auto-blacklist is appended to.
pub const BLACKLIST_FILE: &str = "mitm_blacklist.txt";
/// The directory name the Android app has used since the Go engine (`.go-mitm` under `filesDir`).
pub const DEFAULT_CERT_DIR: &str = "go-mitm";

/// One running MITM session: the root CA, the smart filter and the upstream TLS config.
pub struct Mitm {
    certs: Arc<CertStore>,
    filter: Arc<Filter>,
    upstream: Arc<UpstreamTls>,
    blacklist_path: String,
}

impl Mitm {
    /// `StartStackMitm(certDir)`: load (or generate) the root CA, open the filter, install the
    /// platform trust pool for upstream verification and pre-mint the local asset certificate.
    ///
    /// The returned lines are the ones Go logged; the error text is what Kotlin never saw because
    /// `StartStackMitm` returned an empty PEM when it failed.
    pub fn start(cert_dir: &str, trust: &UpstreamTrust) -> Result<(Mitm, Vec<String>), String> {
        let (certs, status) = CertStore::load_or_generate(cert_dir)?;
        let certs = Arc::new(certs);
        let filter = Arc::new(Filter::new());
        let blacklist_path = format!("{cert_dir}/{BLACKLIST_FILE}");
        let loaded = filter.load_persistent(&blacklist_path, now_ms());
        let upstream = Arc::new(UpstreamTls::new(trust));
        let mut messages = status.messages(cert_dir);
        messages.push(format!(
            "MITM Filter: persistent blacklist at {blacklist_path} ({loaded} active entries loaded)"
        ));
        // `WarmLocalAssetCert`: the first page load should not pay for the minting.
        let asset_host = diting_cosmetic_core::local::ASSET_HOST;
        match certs.warm(asset_host) {
            Ok(()) => messages.push(format!(
                "Local asset server: cert for {asset_host} pre-generated"
            )),
            Err(error) => {
                messages.push(format!("Local asset server: cert pre-gen failed: {error}"))
            }
        }
        Ok((
            Mitm {
                certs,
                filter,
                upstream,
                blacklist_path,
            },
            messages,
        ))
    }

    pub fn certs(&self) -> &Arc<CertStore> {
        &self.certs
    }

    pub fn filter(&self) -> &Arc<Filter> {
        &self.filter
    }

    pub fn upstream(&self) -> &Arc<UpstreamTls> {
        &self.upstream
    }

    /// `GetCACertPEM`: the root the user installed, byte for byte.
    pub fn ca_pem(&self) -> String {
        self.certs.ca_pem().to_string()
    }

    /// Where the blacklist file lives, so a test can inspect what was appended.
    pub fn blacklist_path(&self) -> &str {
        &self.blacklist_path
    }
}

/// Milliseconds since the Unix epoch, the clock every MITM kernel entry point takes explicitly.
pub fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

/// What the engine holds for MITM: the pushed settings plus the optional live session.
///
/// The two are separate on purpose (see the module docs): settings outlive a session, and a session
/// owns the root CA, the minted leaves and the blacklist file. `startStackMitm` / `stopStackMitm`
/// only touch the session, so a stop keeps the cosmetic rules and the callback installed.
pub struct MitmState {
    session: RwLock<Option<Arc<Mitm>>>,
    settings: MitmSettings,
}

impl Default for MitmState {
    fn default() -> Self {
        Self::new()
    }
}

impl MitmState {
    pub fn new() -> Self {
        Self {
            session: RwLock::new(None),
            settings: MitmSettings::new(),
        }
    }

    /// The pushed settings (cosmetic rules, request rules, HTTP log sink).
    pub fn settings(&self) -> &MitmSettings {
        &self.settings
    }

    /// The live session, or `None` while MITM is not running.
    pub fn session(&self) -> Option<Arc<Mitm>> {
        self.session
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn active(&self) -> bool {
        self.session
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .is_some()
    }

    /// `StartStackMitm(certDir)`: the CA PEM (empty on failure) plus the lines Go logged.
    pub fn start(&self, cert_dir: &str, trust: &UpstreamTrust) -> (String, Vec<String>) {
        match Mitm::start(cert_dir, trust) {
            Ok((mitm, messages)) => {
                let pem = mitm.ca_pem();
                *self
                    .session
                    .write()
                    .unwrap_or_else(|error| error.into_inner()) = Some(Arc::new(mitm));
                (pem, messages)
            }
            Err(error) => (
                String::new(),
                vec![format!("StartStackMitm: cert manager init failed: {error}")],
            ),
        }
    }

    /// `StopStackMitm`: drop the session, the minted leaves and the signing key.
    pub fn stop(&self) {
        self.session
            .write()
            .unwrap_or_else(|error| error.into_inner())
            .take();
    }
}

/// The crypto provider every MITM TLS config is built from: `ring`, like the rest of the engine.
pub fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// `GetMitmCACert(certDir)` when no session is running: the root the last session wrote.
pub fn ca_pem_from(cert_dir: &str) -> String {
    std::fs::read_to_string(std::path::Path::new(cert_dir).join(CA_CERT_FILE)).unwrap_or_default()
}
