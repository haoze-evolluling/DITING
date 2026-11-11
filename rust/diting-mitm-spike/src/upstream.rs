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
//! and `mitm_relay.go` then refused to intercept when `clientCertRequested` was set or the upstream
//! leaf carried an EV policy OID (banking/mTLS endpoints pin or expect their own chain).
//!
//! rustls has no `GetClientCertificate`; [`ResolvesClientCert`] plays that role. It is called only
//! when the server actually sent a `CertificateRequest`, which is the exact signal Go observed, so
//! the flag keeps the same meaning. `has_certs()` returns `true` and `resolve` returns `None`: that
//! produces the same empty `Certificate` message as Go's `&tls.Certificate{}`.
//!
//! Two smaller mappings: `MinVersion: TLS12` becomes an explicit protocol version list, and the
//! 256-entry session cache is rustls' own default size (`Resumption::in_memory_sessions(256)`), which
//! gives TLS 1.3 tickets and TLS 1.2 session IDs the way Go's cache did.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use rustls::client::ResolvesClientCert;
use rustls::pki_types::{CertificateDer, ServerName};
use rustls::sign::CertifiedKey;
use rustls::{ClientConfig, RootCertStore, SignatureScheme};
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;

use crate::BoxError;

/// What the relay needs to know about a finished upstream handshake.
pub struct UpstreamFacts {
    /// The TLS stream the HTTP client will speak over.
    pub stream: TlsStream<TcpStream>,
    /// The server sent a `CertificateRequest` (mTLS): do not intercept, blacklist the host.
    pub client_cert_requested: bool,
    /// The upstream leaf carries an EV policy OID: do not intercept.
    pub extended_validation: bool,
    /// The upstream leaf, for logging and for the inspection UI.
    pub peer_leaf: Option<CertificateDer<'static>>,
}

/// The one upstream `ClientConfig` the engine shares across flows.
pub struct UpstreamTls {
    config: Arc<ClientConfig>,
    client_cert_requested: Arc<AtomicBool>,
}

impl UpstreamTls {
    /// `upstreamTLSConfig("")` with the pool built by [`crate::trust::upstream_root_store`].
    pub fn new(roots: RootCertStore) -> UpstreamTls {
        let client_cert_requested = Arc::new(AtomicBool::new(false));
        let mut config = ClientConfig::builder_with_provider(crate::provider())
            .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
            .expect("the ring provider supports TLS 1.2 and 1.3")
            .with_root_certificates(roots)
            .with_client_cert_resolver(Arc::new(NoClientCertificate {
                requested: client_cert_requested.clone(),
            }));
        // Go never set NextProtos on the upstream config, so the relay must keep speaking HTTP/1.1.
        config.alpn_protocols = Vec::new();
        config.resumption = rustls::client::Resumption::in_memory_sessions(256);
        UpstreamTls {
            config: Arc::new(config),
            client_cert_requested,
        }
    }

    /// The config itself, for callers that need to hand it to another connector.
    pub fn config(&self) -> Arc<ClientConfig> {
        self.config.clone()
    }

    /// `tls.Client(rawServer, upstreamTLSConfig(hostname, &clientCertRequested)).Handshake()`.
    pub async fn connect(&self, host: &str, tcp: TcpStream) -> Result<UpstreamFacts, BoxError> {
        let server_name = ServerName::try_from(host.to_string())
            .map_err(|err| format!("upstream host '{host}' is not a TLS server name: {err}"))?;
        self.client_cert_requested.store(false, Ordering::SeqCst);
        let stream = TlsConnector::from(self.config.clone())
            .connect(server_name, tcp)
            .await?;

        let (_, session) = stream.get_ref();
        let peer_leaf = session
            .peer_certificates()
            .and_then(|certs| certs.first())
            .map(|cert| cert.to_owned());
        let extended_validation = peer_leaf
            .as_ref()
            .is_some_and(|leaf| crate::trust::is_extended_validation(leaf.as_ref()));
        Ok(UpstreamFacts {
            stream,
            client_cert_requested: self.client_cert_requested.load(Ordering::SeqCst),
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
