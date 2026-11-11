//! Dynamic MITM certificates: a leaf per host, minted by `diting-cert-core` inside the handshake.
//!
//! This is `CertManager.GetDynamicTLSConfigForHost` after migration. The Go version set
//! `GetCertificate`, resolved the host from `ClientHelloInfo.ServerName` (falling back to the flow's
//! hostname), read an LRU cache that treated a leaf as expired five minutes early, and minted
//! behind a per-host single-flight wait group.
//!
//! The Rust version keeps the same shape with two substitutions:
//!
//! * `GetCertificate` becomes [`rustls::server::ResolvesServerCert`]. `resolve` is synchronous, so
//!   minting happens inline exactly like Go did (P-256 signing plus one DER encode); the cache lock
//!   *is* the single flight — a second handshake for the same host waits for the mutex instead of
//!   waiting on a `sync.WaitGroup`.
//! * the LRU becomes a bounded map pruned on insert, because the Go LRU only existed to cap memory
//!   (256 leaves); entries expire at `NotAfter - 5min` and are dropped on the way out.
//!
//! ALPN is `http/1.1` only, like `NextProtos: []string{"http/1.1"}`: the relay speaks HTTP/1.1 and
//! does not implement the HTTP/2 framing the browsers would otherwise negotiate.

use std::collections::HashMap;
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
/// The capacity `certCache` (an LRU) was created with.
pub const MAX_CACHED_LEAVES: usize = 256;

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
    pub fn new(authority: CertAuthority) -> CertStore {
        CertStore {
            authority,
            leaves: Mutex::new(HashMap::new()),
            minted: Mutex::new(0),
        }
    }

    /// The root CA, for the export/inspection paths and for the client-side tests.
    pub fn authority(&self) -> &CertAuthority {
        &self.authority
    }

    /// How many leaves are cached right now.
    pub fn cached_len(&self) -> usize {
        self.lock().len()
    }

    /// How many leaves have been minted since the store was created.
    pub fn minted_count(&self) -> u64 {
        *self.minted.lock().unwrap_or_else(|err| err.into_inner())
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
                return Ok(cached.key.clone());
            }
            cache.remove(host);
        }

        let issued = self.authority.issue(host, now_unix)?;
        let not_after_unix = issued.not_after_unix;
        let key = Arc::new(certified_key(&issued)?);
        if cache.len() >= MAX_CACHED_LEAVES {
            // Coarse, but the Go LRU's only purpose was to cap memory; the expired entries are
            // useless anyway and everything else is reminted in one signing operation on demand.
            let now = now_unix;
            cache.retain(|_, leaf| now < leaf.not_after_unix - RENEW_MARGIN_SECS);
            if cache.len() >= MAX_CACHED_LEAVES {
                cache.clear();
            }
        }
        cache.insert(
            host.to_string(),
            CachedLeaf {
                key: key.clone(),
                not_after_unix,
            },
        );
        *self.minted.lock().unwrap_or_else(|err| err.into_inner()) += 1;
        Ok(key)
    }

    /// The server config for one intercepted flow.
    ///
    /// `default_host` is Go's `defaultHost` argument: the hostname from the TUN flow, used when the
    /// client sends no SNI (a literal IP address, for instance).
    pub fn server_config(self: &Arc<Self>, default_host: Option<&str>) -> ServerConfig {
        let mut config = ServerConfig::builder_with_provider(crate::provider())
            .with_safe_default_protocol_versions()
            .expect("the ring provider supports the default TLS versions")
            .with_no_client_auth()
            .with_cert_resolver(Arc::new(HostResolver {
                store: self.clone(),
                default_host: default_host.map(str::to_string),
            }));
        config.alpn_protocols = vec![ALPN.to_vec()];
        config
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, CachedLeaf>> {
        self.leaves.lock().unwrap_or_else(|err| err.into_inner())
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
        match self.store.leaf_for(&host, crate::now_unix()) {
            Ok(key) => Some(key),
            Err(err) => {
                // Failing here fails the handshake, which is what Go did when minting failed.
                eprintln!("MITM: cannot mint a certificate for '{host}': {err}");
                None
            }
        }
    }
}

/// The PEM pair `tls.X509KeyPair` consumed, as a rustls signing key.
fn certified_key(issued: &IssuedLeaf) -> Result<CertifiedKey, String> {
    let chain = parse_certs(&issued.chain_pem)?;
    if chain.is_empty() {
        return Err("minted chain is empty".to_string());
    }
    let key = parse_key(&issued.key_pem)?;
    let signing = ring::sign::any_ecdsa_type(&key)
        .map_err(|err| format!("minted leaf key is not usable for signing: {err}"))?;
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
        .map_err(|err| format!("cannot read the minted leaf key: {err}"))?
        .ok_or_else(|| "no PRIVATE KEY block in the minted leaf".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> Arc<CertStore> {
        Arc::new(CertStore::new(
            CertAuthority::generate(crate::now_unix())
                .expect("mint a CA")
                .authority,
        ))
    }

    #[test]
    fn a_host_is_minted_once_then_served_from_the_cache() {
        let store = store();
        let now = crate::now_unix();
        let first = store.leaf_for("example.com", now).expect("mint");
        let second = store.leaf_for("example.com", now + 60).expect("hit");
        assert!(Arc::ptr_eq(&first, &second), "the cached leaf is reused");
        assert_eq!(store.minted_count(), 1);
        assert_eq!(store.cached_len(), 1);
    }

    #[test]
    fn each_host_gets_its_own_leaf() {
        let store = store();
        let now = crate::now_unix();
        let a = store.leaf_for("a.test", now).expect("mint a");
        let b = store.leaf_for("b.test", now).expect("mint b");
        assert!(!Arc::ptr_eq(&a, &b));
        assert_eq!(store.cached_len(), 2);
        assert_ne!(a.cert[0].as_ref(), b.cert[0].as_ref());
    }

    #[test]
    fn a_leaf_is_renewed_five_minutes_before_it_expires() {
        let store = store();
        let now = crate::now_unix();
        let first = store.leaf_for("example.com", now).expect("mint");
        let not_after = now + diting_cert_core::ca::LEAF_VALIDITY_AFTER_SECS;
        let inside_margin = store
            .leaf_for("example.com", not_after - RENEW_MARGIN_SECS + 1)
            .expect("renew");
        assert!(
            !Arc::ptr_eq(&first, &inside_margin),
            "renewed inside the margin"
        );
        assert_eq!(store.minted_count(), 2);
    }

    #[test]
    fn an_empty_host_fails_closed() {
        let store = store();
        assert!(store.leaf_for("", crate::now_unix()).is_err());
        assert_eq!(store.cached_len(), 0);
    }

    #[test]
    fn the_chain_carries_the_leaf_and_the_root() {
        let store = store();
        let key = store
            .leaf_for("example.com", crate::now_unix())
            .expect("mint");
        assert_eq!(key.cert.len(), 2, "leaf then root, like tls.X509KeyPair");
        assert_eq!(key.cert[1].as_ref(), store.authority().ca_der());
    }

    #[test]
    fn the_cache_stays_bounded() {
        let store = store();
        let now = crate::now_unix();
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
}
