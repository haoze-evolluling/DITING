//! The upstream half of the MITM: `upstreamTLSConfig` from `mitm_trust.go`.
//!
//! Go's config was small but each line mattered:
//!
//! ```text
//! ServerName: serverName, RootCAs: upstreamRootPool(), MinVersion: tls.VersionTLS12,
//! ClientSessionCache: tls.NewLRUClientSessionCache(256),
//! GetClientCertificate: func(...) { *clientCertRequested = true; return &tls.Certificate{}, nil }
//! ```
//!
//! `mitm_relay.go` then refused to intercept when `clientCertRequested` was set or the upstream leaf
//! carried an EV policy OID: banking and identity endpoints pin their chain or expect EV treatment.
//!
//! rustls has no `GetClientCertificate`; [`ResolvesClientCert`] plays that role and is only called
//! when the server actually sent a `CertificateRequest` — the exact signal Go observed, so the flag
//! keeps its meaning. `has_certs()` returns `true` and `resolve` returns `None`, which produces the
//! same empty `Certificate` message as Go's `&tls.Certificate{}`.
//!
//! The root pool is the one the resolver already built ([`crate::resolver::UpstreamTrust`]): the
//! platform CA directories plus the bundled ISRG roots, i.e. what `x509.SystemCertPool()` gave Go.
//! EV detection decodes the leaf's certificate-policies extension here (`crypto/x509` did it for
//! free) and asks `diting-cert-core::ev` for the verdict.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use der::Decode;
use rustls::client::ResolvesClientCert;
use rustls::pki_types::{CertificateDer, ServerName};
use rustls::sign::CertifiedKey;
use rustls::{ClientConfig, SignatureScheme};
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;
use x509_cert::ext::pkix::certpolicy::CertificatePolicies;
use x509_cert::Certificate;

use crate::resolver::UpstreamTrust;

/// What the relay needs to know about a finished upstream handshake.
pub struct UpstreamFacts {
    /// The TLS stream the HTTP client speaks over.
    pub stream: TlsStream<TcpStream>,
    /// The server sent a `CertificateRequest` (mTLS): do not intercept, blacklist the host.
    pub client_cert_requested: bool,
    /// The upstream leaf carries an EV policy OID: do not intercept.
    pub extended_validation: bool,
    /// The upstream leaf, for logging and for the CA-inspection screen.
    pub peer_leaf: Option<CertificateDer<'static>>,
}

/// The upstream `ClientConfig`, built once per MITM session and shared by every flow.
pub struct UpstreamTls {
    config: Arc<ClientConfig>,
}

impl UpstreamTls {
    /// `upstreamTLSConfig("")` over the engine's platform trust pool.
    pub fn new(trust: &UpstreamTrust) -> UpstreamTls {
        let mut config = ClientConfig::builder_with_provider(trust.provider())
            .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
            .expect("the ring provider supports TLS 1.2 and 1.3")
            .with_root_certificates(trust.roots().clone())
            .with_client_cert_resolver(Arc::new(NoClientCertificate {
                requested: Arc::new(AtomicBool::new(false)),
            }));
        // Go never set NextProtos on the upstream config, so the relay keeps speaking HTTP/1.1.
        config.alpn_protocols = Vec::new();
        config.resumption = rustls::client::Resumption::in_memory_sessions(256);
        UpstreamTls {
            config: Arc::new(config),
        }
    }

    /// The config itself, for a caller that needs to build its own connector (the tests do).
    pub fn config(&self) -> Arc<ClientConfig> {
        Arc::clone(&self.config)
    }

    /// `tls.Client(rawServer, upstreamTLSConfig(hostname, &clientCertRequested)).Handshake()`.
    pub async fn connect(&self, host: &str, tcp: TcpStream) -> Result<UpstreamFacts, String> {
        let server_name = ServerName::try_from(host.to_string())
            .map_err(|error| format!("upstream host '{host}' is not a TLS server name: {error}"))?;
        // Go passed a `*bool` private to this flow; the flag must not be shared, or one connection's
        // `store(false)` erases another connection's `CertificateRequest` while both handshakes run.
        let requested = Arc::new(AtomicBool::new(false));
        let mut config = (*self.config).clone();
        config.client_auth_cert_resolver = Arc::new(NoClientCertificate {
            requested: Arc::clone(&requested),
        });
        let stream = TlsConnector::from(Arc::new(config))
            .connect(server_name, tcp)
            .await
            .map_err(|error| format!("upstream TLS handshake with {host}: {error}"))?;

        let (_, session) = stream.get_ref();
        let peer_leaf = session
            .peer_certificates()
            .and_then(|certs| certs.first())
            .map(|cert| cert.to_owned());
        let extended_validation = peer_leaf
            .as_ref()
            .is_some_and(|leaf| is_extended_validation(leaf.as_ref()));
        Ok(UpstreamFacts {
            stream,
            client_cert_requested: requested.load(Ordering::SeqCst),
            extended_validation,
            peer_leaf,
        })
    }
}

/// `GetClientCertificate` that never has a certificate but remembers being asked.
#[derive(Debug)]
struct NoClientCertificate {
    requested: Arc<AtomicBool>,
}

impl ResolvesClientCert for NoClientCertificate {
    fn resolve(
        &self,
        _acceptable_issuers: &[&[u8]],
        _sigschemes: &[SignatureScheme],
    ) -> Option<Arc<CertifiedKey>> {
        self.requested.store(true, Ordering::SeqCst);
        None
    }

    /// Keep `true` so rustls sends an empty `Certificate` message, like Go's `&tls.Certificate{}`.
    fn has_certs(&self) -> bool {
        true
    }
}

/// `isExtendedValidation(leaf)`: decode the certificate-policies extension and ask the kernel.
pub fn is_extended_validation(cert_der: &[u8]) -> bool {
    let Ok(certificate) = Certificate::from_der(cert_der) else {
        return false;
    };
    let Some(policies) = certificate
        .tbs_certificate
        .extensions
        .as_ref()
        .and_then(|extensions| {
            extensions
                .iter()
                .find(|extension| {
                    extension.extn_id == const_oid::db::rfc5280::ID_CE_CERTIFICATE_POLICIES
                })
                .cloned()
        })
    else {
        return false;
    };
    let Ok(decoded) = CertificatePolicies::from_der(policies.extn_value.as_bytes()) else {
        return false;
    };
    let oids: Vec<String> = decoded
        .0
        .iter()
        .map(|policy| policy.policy_identifier.to_string())
        .collect();
    let references: Vec<&str> = oids.iter().map(String::as_str).collect();
    diting_cert_core::ev::is_extended_validation(&references)
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_cert_core::ca::CertAuthority;

    #[test]
    fn the_upstream_config_offers_no_alpn() {
        let tls = UpstreamTls::new(&UpstreamTrust::from_roots(rustls::RootCertStore::empty()));
        assert!(tls.config().alpn_protocols.is_empty());
    }

    #[test]
    fn a_plain_leaf_is_not_extended_validation() {
        let authority = CertAuthority::generate(super::super::now_ms() / 1000)
            .expect("mint a CA")
            .authority;
        let leaf = authority
            .issue("plain.test", super::super::now_ms() / 1000)
            .expect("mint a leaf");
        let der = leaf_der(&leaf.chain_pem);
        assert!(!der.is_empty(), "the minted chain parses");
        assert!(!is_extended_validation(&der));
    }

    /// The first certificate of a PEM chain, as DER.
    fn leaf_der(chain_pem: &str) -> Vec<u8> {
        rustls_pemfile::certs(&mut std::io::BufReader::new(chain_pem.as_bytes()))
            .filter_map(Result::ok)
            .next()
            .map(|cert| cert.as_ref().to_vec())
            .unwrap_or_default()
    }

    #[test]
    fn garbage_is_never_extended_validation() {
        assert!(!is_extended_validation(b"not a certificate"));
        assert!(!is_extended_validation(&[]));
    }
}
