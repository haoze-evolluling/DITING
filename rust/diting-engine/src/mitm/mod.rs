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

pub const CA_CERT_FILE: &str = "ca.crt";
pub const CA_KEY_FILE: &str = "ca.key";
pub const BLACKLIST_FILE: &str = "mitm_blacklist.txt";

pub struct Mitm {
    certs: Arc<CertStore>,
    filter: Arc<Filter>,
    upstream: Arc<UpstreamTls>,
    blacklist_path: String,
}

impl Mitm {
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

    pub fn ca_pem(&self) -> String {
        self.certs.ca_pem().to_string()
    }

    pub fn blacklist_path(&self) -> &str {
        &self.blacklist_path
    }
}

pub fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

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

    pub fn settings(&self) -> &MitmSettings {
        &self.settings
    }

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

    pub fn stop(&self) {
        self.session
            .write()
            .unwrap_or_else(|error| error.into_inner())
            .take();
    }
}

pub fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

pub fn ca_pem_from(cert_dir: &str) -> String {
    std::fs::read_to_string(std::path::Path::new(cert_dir).join(CA_CERT_FILE)).unwrap_or_default()
}
