//! Dynamic MITM certificates: the root CA on disk and one leaf per host, minted inside the handshake.
//!
//! This is `mitm_cert_manager.go` after migration. Go kept four things here, and all four have a
//! counterpart:
//!
//! | Go | Here |
//! |---|---|
//! | `initCA` (`ca.crt`/`ca.key`, load-or-generate-and-save) | [`CertStore::load_or_generate`] |
//! | `GetCertificate` + `GetDynamicTLSConfigForHost` | [`CertStore::server_config`] over [`HostResolver`] |
//! | a 512-entry LRU of `*tls.Certificate` | a bounded map pruned on insert ([`MAX_CACHED_LEAVES`]) |
//! | `WarmLocalAssetCert` | [`CertStore::warm`] |
//!
//! `GetCertificate` becomes [`rustls::server::ResolvesServerCert`]. `resolve` is synchronous, so
//! minting happens inline exactly like Go did (one P-256 signature plus one DER encode), and the
//! cache lock *is* the single flight: a second handshake for the same host waits for the mutex
//! instead of a `sync.WaitGroup`.
//!
//! ALPN is `http/1.1` only, like `NextProtos: []string{"http/1.1"}`: the relay speaks HTTP/1.1 and
//! does not implement the HTTP/2 framing the browsers would otherwise negotiate.
//!
//! The directory and both file names are frozen (`.go-mitm/ca.crt`, `.go-mitm/ca.key`): a root the
//! user already installed has to keep validating after the upgrade.

use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex};

use diting_cert_core::ca::{CertAuthority, IssuedLeaf};
use rustls::crypto::ring;
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls::server::{ClientHello, ResolvesServerCert};
use rustls::sign::CertifiedKey;
use rustls::ServerConfig;

/// `NextProtos: []string{"http/1.1"}`.
pub const ALPN: &[u8] = b"http/1.1";
/// `time.Now().Before(cached.expiresAt.Add(-5 * time.Minute))`.
pub const RENEW_MARGIN_SECS: i64 = 5 * 60;
/// `certCacheMaxEntries`: the cap the Go LRU was created with.
pub const MAX_CACHED_LEAVES: usize = 512;
/// `0644` for `ca.crt`, `0600` for `ca.key`.
const CA_CERT_MODE: u32 = 0o644;
const CA_KEY_MODE: u32 = 0o600;

/// How the root CA was obtained, so the caller can log what Go logged.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CaStatus {
    /// `ca.crt` and `ca.key` were on disk and validated.
    Loaded,
    /// The CA was generated and written to `cert_dir`.
    Generated,
    /// The CA was generated but could not be written (read-only directory).
    GeneratedUnsaved(String),
    /// The files existed but did not load, so the CA was regenerated over them.
    Regenerated(String),
}

impl CaStatus {
    /// The lines `initCA` printed, in the same order.
    pub fn messages(&self, cert_dir: &str) -> Vec<String> {
        match self {
            CaStatus::Loaded => vec![format!("MITM CA loaded from disk: {cert_dir}")],
            CaStatus::Generated => vec![format!("MITM CA: generated and saved to {cert_dir}")],
            CaStatus::GeneratedUnsaved(error) => {
                vec![format!(
                    "MITM CA: WARNING — failed to save to disk: {error}"
                )]
            }
            CaStatus::Regenerated(error) => vec![
                format!("MITM CA: failed to load from disk ({error}), regenerating..."),
                format!("MITM CA: generated and saved to {cert_dir}"),
            ],
        }
    }
}

struct CachedLeaf {
    key: Arc<CertifiedKey>,
    not_after_unix: i64,
}

/// The root CA plus the cache of leaves already minted for a host.
pub struct CertStore {
    authority: CertAuthority,
    leaves: Mutex<HashMap<String, CachedLeaf>>,
    minted: Mutex<u64>,
}

impl CertStore {
    /// A store over an existing authority (the tests mint one instead of reading `.go-mitm`).
    pub fn new(authority: CertAuthority) -> CertStore {
        CertStore {
            authority,
            leaves: Mutex::new(HashMap::new()),
            minted: Mutex::new(0),
        }
    }

    /// `NewCertManager(certDir)`: load `ca.crt`/`ca.key` when both exist and validate, otherwise
    /// generate a fresh root and persist it.
    ///
    /// A generation that cannot be saved is *not* an error: Go logged a warning and kept serving,
    /// because the session works fine and only the installed root would stop matching after a
    /// restart.
    pub fn load_or_generate(cert_dir: &str) -> Result<(CertStore, CaStatus), String> {
        let cert_path = Path::new(cert_dir).join(super::CA_CERT_FILE);
        let key_path = Path::new(cert_dir).join(super::CA_KEY_FILE);
        let now = super::now_ms() / 1000;

        let mut failure = None;
        if cert_path.is_file() && key_path.is_file() {
            match load(&cert_path, &key_path, now) {
                Ok(authority) => return Ok((CertStore::new(authority), CaStatus::Loaded)),
                Err(error) => failure = Some(error),
            }
        }

        let generated =
            CertAuthority::generate(now).map_err(|error| format!("generate CA: {error}"))?;
        let authority = generated.authority;
        let ca_pem = authority.ca_pem().to_string();
        let status = match save(
            cert_dir,
            &cert_path,
            &key_path,
            &ca_pem,
            &generated.ca_key_pem,
        ) {
            Ok(()) => match failure {
                Some(error) => CaStatus::Regenerated(error),
                None => CaStatus::Generated,
            },
            Err(error) => CaStatus::GeneratedUnsaved(error),
        };
        Ok((CertStore::new(authority), status))
    }

    /// The root CA, for the export/inspection paths and for the local asset server.
    pub fn authority(&self) -> &CertAuthority {
        &self.authority
    }

    /// `GetCACertPEM`.
    pub fn ca_pem(&self) -> &str {
        self.authority.ca_pem()
    }

    /// How many leaves are cached right now.
    pub fn cached_len(&self) -> usize {
        self.lock().len()
    }

    /// How many leaves have been minted since the store was created.
    pub fn minted_count(&self) -> u64 {
        *self
            .minted
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    /// `WarmLocalAssetCert`: mint the local asset host's leaf before the first page needs it.
    pub fn warm(&self, host: &str) -> Result<(), String> {
        self.leaf_for(host, super::now_ms() / 1000).map(|_| ())
    }

    /// `getCertificateWithDedup`: reuse a leaf unless it is within [`RENEW_MARGIN_SECS`] of expiry.
    pub fn leaf_for(&self, host: &str, now_unix: i64) -> Result<Arc<CertifiedKey>, String> {
        // Never mint a nameless certificate: a flow with neither SNI nor a known hostname must fail
        // the handshake instead of presenting something no client can validate.
        if host.trim().is_empty() {
            return Err("cannot mint a certificate for an empty host".to_string());
        }
        let mut cache = self.lock();
        if let Some(cached) = cache.get(host) {
            if now_unix < cached.not_after_unix - RENEW_MARGIN_SECS {
                return Ok(Arc::clone(&cached.key));
            }
            cache.remove(host);
        }

        let issued = self.authority.issue(host, now_unix)?;
        let not_after_unix = issued.not_after_unix;
        let key = Arc::new(certified_key(&issued)?);
        if cache.len() >= MAX_CACHED_LEAVES {
            // Coarse, but the Go LRU's only job was to cap memory; expired leaves are useless and
            // everything else is re-minted in one signing operation on demand.
            cache.retain(|_, leaf| now_unix < leaf.not_after_unix - RENEW_MARGIN_SECS);
            if cache.len() >= MAX_CACHED_LEAVES {
                cache.clear();
            }
        }
        cache.insert(
            host.to_string(),
            CachedLeaf {
                key: Arc::clone(&key),
                not_after_unix,
            },
        );
        *self
            .minted
            .lock()
            .unwrap_or_else(|error| error.into_inner()) += 1;
        Ok(key)
    }

    /// `GetDynamicTLSConfigForHost(defaultHost)`: the server config for one intercepted flow.
    ///
    /// `default_host` is the flow's hostname, used when the client sends no SNI (a literal IP, say).
    pub fn server_config(self: &Arc<Self>, default_host: Option<&str>) -> Arc<ServerConfig> {
        let mut config = ServerConfig::builder_with_provider(super::provider())
            .with_safe_default_protocol_versions()
            .expect("the ring provider supports the default TLS versions")
            .with_no_client_auth()
            .with_cert_resolver(Arc::new(HostResolver {
                store: Arc::clone(self),
                default_host: default_host.map(str::to_string),
            }));
        config.alpn_protocols = vec![ALPN.to_vec()];
        Arc::new(config)
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, CachedLeaf>> {
        self.leaves
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }
}

/// The resolver handed to rustls; it carries the flow hostname as the SNI fallback.
struct HostResolver {
    store: Arc<CertStore>,
    default_host: Option<String>,
}

impl std::fmt::Debug for HostResolver {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HostResolver")
            .field("default_host", &self.default_host)
            .field("cached", &self.store.cached_len())
            .finish()
    }
}

impl ResolvesServerCert for HostResolver {
    fn resolve(&self, hello: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        let host = match hello.server_name() {
            Some(name) => name.to_string(),
            None => self.default_host.clone()?,
        };
        // Failing here fails the handshake, which is what Go did when minting failed.
        self.store.leaf_for(&host, super::now_ms() / 1000).ok()
    }
}

/// `loadCA`: read both files and validate the pair.
fn load(cert_path: &Path, key_path: &Path, now_unix: i64) -> Result<CertAuthority, String> {
    let cert_pem =
        fs::read_to_string(cert_path).map_err(|error| format!("read CA cert: {error}"))?;
    let key_pem = fs::read_to_string(key_path).map_err(|error| format!("read CA key: {error}"))?;
    CertAuthority::load(&cert_pem, &key_pem, now_unix)
}

/// `saveCA`: `ca.crt` at 0644 and `ca.key` at 0600, creating the directory first.
fn save(
    cert_dir: &str,
    cert_path: &Path,
    key_path: &Path,
    cert_pem: &str,
    key_pem: &str,
) -> Result<(), String> {
    fs::create_dir_all(cert_dir).map_err(|error| format!("create {cert_dir}: {error}"))?;
    fs::write(cert_path, cert_pem).map_err(|error| format!("write CA cert: {error}"))?;
    fs::write(key_path, key_pem).map_err(|error| format!("write CA key: {error}"))?;
    set_mode(cert_path, CA_CERT_MODE);
    set_mode(key_path, CA_KEY_MODE);
    Ok(())
}

#[cfg(unix)]
fn set_mode(path: &Path, mode: u32) {
    use std::os::unix::fs::PermissionsExt;
    let _ = fs::set_permissions(path, fs::Permissions::from_mode(mode));
}

#[cfg(not(unix))]
fn set_mode(_path: &Path, _mode: u32) {
    // The host tests on Windows have no POSIX modes; the device is always unix.
}

/// The PEM pair `tls.X509KeyPair` consumed, as a rustls signing key.
fn certified_key(issued: &IssuedLeaf) -> Result<CertifiedKey, String> {
    let chain = parse_certs(&issued.chain_pem)?;
    if chain.is_empty() {
        return Err("minted chain is empty".to_string());
    }
    let key = parse_key(&issued.key_pem)?;
    let signing = ring::sign::any_ecdsa_type(&key)
        .map_err(|error| format!("minted leaf key is not usable for signing: {error}"))?;
    Ok(CertifiedKey::new(chain, signing))
}

fn parse_certs(pem: &str) -> Result<Vec<CertificateDer<'static>>, String> {
    let certs: Vec<CertificateDer<'static>> =
        rustls_pemfile::certs(&mut std::io::BufReader::new(pem.as_bytes()))
            .filter_map(Result::ok)
            .collect();
    if certs.is_empty() {
        return Err("no CERTIFICATE block in the minted chain".to_string());
    }
    Ok(certs)
}

fn parse_key(pem: &str) -> Result<PrivateKeyDer<'static>, String> {
    rustls_pemfile::private_key(&mut std::io::BufReader::new(pem.as_bytes()))
        .map_err(|error| format!("cannot read the minted leaf key: {error}"))?
        .ok_or_else(|| "no PRIVATE KEY block in the minted leaf".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> String {
        let dir = std::env::temp_dir().join(format!(
            "diting-mitm-cert-{name}-{}-{}",
            std::process::id(),
            super::super::now_ms()
        ));
        dir.to_string_lossy().into_owned()
    }

    fn store() -> Arc<CertStore> {
        Arc::new(CertStore::new(
            CertAuthority::generate(super::super::now_ms() / 1000)
                .expect("mint a CA")
                .authority,
        ))
    }

    #[test]
    fn a_generated_ca_is_written_and_reloaded() {
        let dir = scratch("persist");
        let (first, status) = CertStore::load_or_generate(&dir).expect("generate");
        assert_eq!(status, CaStatus::Generated);
        assert!(Path::new(&dir).join(super::super::CA_CERT_FILE).is_file());
        assert!(Path::new(&dir).join(super::super::CA_KEY_FILE).is_file());
        let ca_pem = first.ca_pem().to_string();

        let (second, status) = CertStore::load_or_generate(&dir).expect("reload");
        assert_eq!(status, CaStatus::Loaded);
        assert_eq!(second.ca_pem(), ca_pem, "the installed root survives");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_unreadable_pair_is_regenerated() {
        let dir = scratch("regenerate");
        fs::create_dir_all(&dir).expect("create");
        fs::write(Path::new(&dir).join(super::super::CA_CERT_FILE), "junk\n").expect("write");
        fs::write(Path::new(&dir).join(super::super::CA_KEY_FILE), "junk\n").expect("write");
        let (store, status) = CertStore::load_or_generate(&dir).expect("regenerate");
        assert!(matches!(status, CaStatus::Regenerated(_)), "{status:?}");
        assert!(!store.ca_pem().is_empty());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_host_is_minted_once_then_served_from_the_cache() {
        let store = store();
        let now = super::super::now_ms() / 1000;
        let first = store.leaf_for("example.test", now).expect("mint");
        let second = store.leaf_for("example.test", now + 60).expect("hit");
        assert!(Arc::ptr_eq(&first, &second), "the cached leaf is reused");
        assert_eq!(store.minted_count(), 1);
        assert_eq!(store.cached_len(), 1);
    }

    #[test]
    fn a_leaf_is_renewed_five_minutes_before_it_expires() {
        let store = store();
        let now = super::super::now_ms() / 1000;
        let first = store.leaf_for("example.test", now).expect("mint");
        let not_after = now + diting_cert_core::ca::LEAF_VALIDITY_AFTER_SECS;
        let renewed = store
            .leaf_for("example.test", not_after - RENEW_MARGIN_SECS + 1)
            .expect("renew");
        assert!(!Arc::ptr_eq(&first, &renewed));
        assert_eq!(store.minted_count(), 2);
    }

    #[test]
    fn an_empty_host_fails_closed() {
        let store = store();
        assert!(store.leaf_for("", super::super::now_ms() / 1000).is_err());
        assert_eq!(store.cached_len(), 0);
    }

    #[test]
    fn the_chain_carries_the_leaf_and_the_root() {
        let store = store();
        let key = store
            .leaf_for("example.test", super::super::now_ms() / 1000)
            .expect("mint");
        assert_eq!(key.cert.len(), 2, "leaf then root, like tls.X509KeyPair");
        assert_eq!(key.cert[1].as_ref(), store.authority().ca_der());
    }

    #[test]
    fn the_cache_stays_bounded() {
        let store = store();
        let now = super::super::now_ms() / 1000;
        for index in 0..(MAX_CACHED_LEAVES + 8) {
            store
                .leaf_for(&format!("host{index}.test"), now)
                .expect("mint");
        }
        assert!(
            store.cached_len() <= MAX_CACHED_LEAVES,
            "cache grew to {}",
            store.cached_len()
        );
    }

    #[test]
    fn the_server_config_offers_http11_only() {
        let store = store();
        let config = store.server_config(Some("flow.test"));
        assert_eq!(config.alpn_protocols, vec![b"http/1.1".to_vec()]);
    }
}
