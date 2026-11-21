use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

use der::{Decode, Encode};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::client::WebPkiServerVerifier;
use rustls::crypto::CryptoProvider;
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, Error, SignatureScheme};
use sha2::{Digest, Sha256};
use x509_cert::Certificate;

pub fn parse_pin(text: &str) -> Result<[u8; 32], String> {
    let cleaned: String = text
        .chars()
        .filter(|character| !matches!(character, ':' | ' ' | '\t' | '\n' | '\r'))
        .collect();
    if cleaned.len() != 64
        || !cleaned
            .chars()
            .all(|character| character.is_ascii_hexdigit())
    {
        return Err("certificate pin must be 64 hex characters (SHA-256)".to_string());
    }
    let mut bytes = [0u8; 32];
    for (index, chunk) in cleaned.as_bytes().chunks(2).enumerate() {
        let pair = std::str::from_utf8(chunk).map_err(|error| error.to_string())?;
        bytes[index] = u8::from_str_radix(pair, 16).map_err(|error| error.to_string())?;
    }
    Ok(bytes)
}

pub fn certificate_pin(cert_der: &[u8]) -> Option<[u8; 32]> {
    let certificate = Certificate::from_der(cert_der).ok()?;
    let tbs = certificate.tbs_certificate().to_der().ok()?;
    let digest = Sha256::digest(&tbs);
    let mut pin = [0u8; 32];
    pin.copy_from_slice(&digest);
    Some(pin)
}

#[derive(Default)]
pub struct PinStore {
    pins: HashMap<String, [u8; 32]>,
}

impl PinStore {
    pub fn is_empty(&self) -> bool {
        self.pins.is_empty()
    }

    pub fn get(&self, host: &str) -> Option<[u8; 32]> {
        self.pins.get(&normalize_host(host)).copied()
    }

    pub fn insert(&mut self, host: &str, text: &str) -> Result<(), String> {
        let pin = parse_pin(text)?;
        self.insert_hash(host, pin);
        Ok(())
    }

    pub fn insert_hash(&mut self, host: &str, pin: [u8; 32]) {
        self.pins.insert(normalize_host(host), pin);
    }

    pub fn from_pairs<I, H, P>(pairs: I) -> Result<Self, String>
    where
        I: IntoIterator<Item = (H, P)>,
        H: AsRef<str>,
        P: AsRef<str>,
    {
        let mut store = Self::default();
        for (host, pin) in pairs {
            store.insert(host.as_ref(), pin.as_ref())?;
        }
        Ok(store)
    }
}

fn normalize_host(host: &str) -> String {
    host.trim()
        .trim_end_matches('.')
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_ascii_lowercase()
}

struct PinnedVerifier {
    inner: Arc<WebPkiServerVerifier>,
    pins: Arc<PinStore>,
}

impl fmt::Debug for PinnedVerifier {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PinnedVerifier")
            .field("pins", &self.pins.pins.len())
            .finish()
    }
}

impl ServerCertVerifier for PinnedVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        ocsp_response: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        let host = match server_name {
            ServerName::DnsName(name) => name.as_ref().to_string(),
            ServerName::IpAddress(address) => std::net::IpAddr::from(*address).to_string(),
            _ => String::new(),
        };
        if let Some(expected) = self.pins.get(&host) {
            let actual = certificate_pin(end_entity.as_ref()).ok_or_else(|| {
                Error::General("certificate pin: malformed server certificate".into())
            })?;
            if actual != expected {
                return Err(Error::General(format!(
                    "certificate pin mismatch for {host}"
                )));
            }
            return Ok(ServerCertVerified::assertion());
        }
        self.inner
            .verify_server_cert(end_entity, intermediates, server_name, ocsp_response, now)
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner.verify_tls12_signature(message, cert, dss)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner.verify_tls13_signature(message, cert, dss)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.inner.supported_verify_schemes()
    }
}

pub(super) fn client_config(
    roots: &rustls::RootCertStore,
    provider: Arc<CryptoProvider>,
    pins: Arc<PinStore>,
    alpn: &[&[u8]],
    tls13_only: bool,
) -> Arc<rustls::ClientConfig> {
    let versions: &[&rustls::SupportedProtocolVersion] = if tls13_only {
        &[&rustls::version::TLS13]
    } else {
        &[&rustls::version::TLS12, &rustls::version::TLS13]
    };
    let builder = rustls::ClientConfig::builder_with_provider(Arc::clone(&provider))
        .with_protocol_versions(versions)
        .expect("the ring provider supports the requested TLS versions");

    let builder = if pins.is_empty() {
        builder.with_root_certificates(roots.clone())
    } else {
        let inner = WebPkiServerVerifier::builder_with_provider(
            Arc::new(roots.clone()),
            Arc::clone(&provider),
        )
        .build()
        .expect("webpki verifier");
        builder
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(PinnedVerifier { inner, pins }))
    };

    let mut config = builder.with_no_client_auth();
    config.alpn_protocols = alpn.iter().map(|protocol| protocol.to_vec()).collect();
    Arc::new(config)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pins_are_hex_with_optional_separators() {
        let expected = [0xab; 32];
        let text = "AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB";
        assert_eq!(parse_pin(text).unwrap(), expected);
        assert!(parse_pin("nope").is_err());
    }

    #[test]
    fn host_normalization_is_case_and_dot_insensitive() {
        let mut store = PinStore::default();
        store
            .insert("DNS.Google.", &"00".repeat(32))
            .expect("valid pin");
        assert!(store.get("dns.google").is_some());
    }
}
