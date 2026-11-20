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

pub struct UpstreamFacts {
    pub stream: TlsStream<TcpStream>,
    pub client_cert_requested: bool,
    pub extended_validation: bool,
    pub peer_leaf: Option<CertificateDer<'static>>,
}

pub struct UpstreamTls {
    config: Arc<ClientConfig>,
    client_cert_requested: Arc<AtomicBool>,
}

impl UpstreamTls {
    pub fn new(roots: RootCertStore) -> UpstreamTls {
        let client_cert_requested = Arc::new(AtomicBool::new(false));
        let mut config = ClientConfig::builder_with_provider(crate::provider())
            .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
            .expect("the ring provider supports TLS 1.2 and 1.3")
            .with_root_certificates(roots)
            .with_client_cert_resolver(Arc::new(NoClientCertificate {
                requested: client_cert_requested.clone(),
            }));
        config.alpn_protocols = Vec::new();
        config.resumption = rustls::client::Resumption::in_memory_sessions(256);
        UpstreamTls {
            config: Arc::new(config),
            client_cert_requested,
        }
    }

    pub fn config(&self) -> Arc<ClientConfig> {
        self.config.clone()
    }

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

    fn has_certs(&self) -> bool {
        true
    }
}
