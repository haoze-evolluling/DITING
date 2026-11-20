use std::fs;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use diting_desktop_api::config::security::CertConfig;
use diting_desktop_core::cert::CertManager;
use diting_desktop_dns::context::DnsContext;
use diting_desktop_dns::encrypted::{EncryptedConfig, EncryptedListeners};
use diting_desktop_dns::pipeline::{Pipeline, Stage, StageResult};
use diting_desktop_dns::server::{DnsServer, ServerConfig};
use diting_dns_wire::build::MessageBuilder;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::TlsConnector;

static NEXT_ID: AtomicU64 = AtomicU64::new(0);

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new() -> Self {
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!("diting-dot-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("create temp dir");
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

struct Answer;

#[async_trait]
impl Stage for Answer {
    fn name(&self) -> &'static str {
        "forward"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        ctx.reply_with_rcode(0);
        StageResult::Stop
    }
}

#[derive(Debug)]
struct AcceptAnyCertificate;

impl ServerCertVerifier for AcceptAnyCertificate {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        vec![
            SignatureScheme::ECDSA_NISTP256_SHA256,
            SignatureScheme::ECDSA_NISTP384_SHA384,
            SignatureScheme::ED25519,
            SignatureScheme::RSA_PSS_SHA256,
            SignatureScheme::RSA_PKCS1_SHA256,
        ]
    }
}

fn client_config() -> Arc<rustls::ClientConfig> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let config = rustls::ClientConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
        .expect("ring supports TLS 1.2/1.3")
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(AcceptAnyCertificate))
        .with_no_client_auth();
    Arc::new(config)
}

#[tokio::test]
async fn dot_round_trip_on_ephemeral_port() {
    let temp = TempDir::new();
    let cert = CertManager::new(temp.path(), CertConfig::default());
    if let Err(error) = cert.ensure_self_signed(CertConfig::default()) {
        eprintln!("skip DoT integration test: {error}");
        return;
    }

    let pipeline = Arc::new(Pipeline::new(vec![Arc::new(Answer)]));
    let server = Arc::new(DnsServer::new(ServerConfig::default(), pipeline));
    let config = EncryptedConfig {
        listen_address: "127.0.0.1".to_string(),
        dot_enabled: true,
        dot_port: 0,
        server_name: "dns.lan".to_string(),
        ..EncryptedConfig::default()
    };
    let listeners = EncryptedListeners::start(server, Arc::new(cert), config)
        .await
        .expect("start DoT");
    assert!(listeners.enabled());
    let address: SocketAddr = listeners
        .addresses()
        .first()
        .expect("one address")
        .parse()
        .expect("socket address");

    let connector = TlsConnector::from(client_config());
    let name = ServerName::try_from("dns.lan").expect("server name");
    let tcp = TcpStream::connect(address).await.expect("connect DoT");
    let mut stream = tokio::time::timeout(Duration::from_secs(5), connector.connect(name, tcp))
        .await
        .expect("handshake deadline")
        .expect("handshake");

    let query = MessageBuilder::query("example.com", 1, 1)
        .finish()
        .expect("build query");
    let mut framed = Vec::with_capacity(query.len() + 2);
    framed.extend_from_slice(&(query.len() as u16).to_be_bytes());
    framed.extend_from_slice(&query);
    stream.write_all(&framed).await.expect("write query");

    let mut prefix = [0u8; 2];
    tokio::time::timeout(Duration::from_secs(5), stream.read_exact(&mut prefix))
        .await
        .expect("response deadline")
        .expect("read length");
    let length = usize::from(u16::from_be_bytes(prefix));
    assert!(length > 0);
    let mut response = vec![0u8; length];
    stream
        .read_exact(&mut response)
        .await
        .expect("read response");
    let header = diting_dns_wire::parse_header(&response).expect("parse response");
    assert!(header.is_response());
    assert_eq!(header.id, 0);

    listeners.shutdown().await;
}
