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

pub struct UpstreamFacts {
    pub stream: TlsStream<TcpStream>,
    pub client_cert_requested: bool,
    pub extended_validation: bool,
    pub peer_leaf: Option<CertificateDer<'static>>,
}

pub struct UpstreamTls {
    config: Arc<ClientConfig>,
}

impl UpstreamTls {
    pub fn new(trust: &UpstreamTrust) -> UpstreamTls {
        let mut config = ClientConfig::builder_with_provider(trust.provider())
            .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
            .expect("the ring provider supports TLS 1.2 and 1.3")
            .with_root_certificates(trust.roots().clone())
            .with_client_cert_resolver(Arc::new(NoClientCertificate {
                requested: Arc::new(AtomicBool::new(false)),
            }));
        config.alpn_protocols = Vec::new();
        config.resumption = rustls::client::Resumption::in_memory_sessions(256);
        UpstreamTls {
            config: Arc::new(config),
        }
    }

    pub fn config(&self) -> Arc<ClientConfig> {
        Arc::clone(&self.config)
    }

    pub async fn connect(&self, host: &str, tcp: TcpStream) -> Result<UpstreamFacts, String> {
        let server_name = ServerName::try_from(host.to_string())
            .map_err(|error| format!("upstream host '{host}' is not a TLS server name: {error}"))?;
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

pub fn is_extended_validation(cert_der: &[u8]) -> bool {
    let Ok(certificate) = Certificate::from_der(cert_der) else {
        return false;
    };
    let Some(policies) = certificate
        .tbs_certificate()
        .extensions()
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
