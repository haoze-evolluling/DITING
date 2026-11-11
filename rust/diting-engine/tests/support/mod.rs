//! The loopback harness the transport cases are driven by: DNS wire helpers, a plain UDP/TCP
//! upstream, a test PKI and the DoT/DoH/DoQ origins.
//!
//! Everything here is real I/O on 127.0.0.1: no mocked TLS, no injected DNS parser. Only two seams
//! are substituted, and both are the network's job in production: the certificate authority is
//! minted per test instead of loaded from `.go-mitm/ca.crt`, and the upstream DNS server answers
//! from a canned record instead of from the internet.
//!
//! [`wire`] is the raw-IP side of the TUN tests: it crafts the packets a TUN read would deliver and
//! parses the packets the stack wrote, through a checksum-verifying parser.

#![allow(dead_code)]

pub mod mitm;
pub mod proxies;
pub mod tunnel;
pub mod wire;

use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use bytes::Bytes;
use diting_engine::config::DnsConfig;
use diting_engine::logs::{BootstrapEvent, BootstrapSink};
use diting_engine::resolver::trust::{add_pem_roots, certificate_from_pem, UpstreamTrust};
use diting_engine::resolver::{Bootstrap, Resolver, ResolverDeps, StatsStore};
use http::{Request, Response, StatusCode, Version};
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper::service::service_fn;
use hyper_util::rt::{TokioExecutor, TokioIo};
use hyper_util::server::conn::auto;
use rustls::pki_types::PrivateKeyDer;
use rustls::{RootCertStore, ServerConfig};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio_rustls::TlsAcceptor;

const DNS_MESSAGE: &str = "application/dns-message";

// ---- DNS wire helpers ---------------------------------------------------------------------------

pub fn query_wire(name: &str, id: u16) -> Vec<u8> {
    let mut out = vec![0u8; 12];
    out[0..2].copy_from_slice(&id.to_be_bytes());
    out[2] = 0x01; // RD
    out[5] = 1; // QDCOUNT
    for label in name.trim_end_matches('.').split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out.extend_from_slice(&1u16.to_be_bytes()); // A
    out.extend_from_slice(&1u16.to_be_bytes()); // IN
    out
}

/// The question echoed with one A record.
pub fn answer_wire(query: &[u8], address: [u8; 4], ttl: u32) -> Vec<u8> {
    let mut out = query.to_vec();
    out[2] = 0x81;
    out[3] = 0x80;
    out[7] = 1; // ANCOUNT
    out.extend_from_slice(&[0xc0, 0x0c]);
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&ttl.to_be_bytes());
    out.extend_from_slice(&4u16.to_be_bytes());
    out.extend_from_slice(&address);
    out
}

/// A header-only answer with `TC=1`: what a small-buffer upstream sends.
pub fn truncated_wire(query: &[u8]) -> Vec<u8> {
    let mut out = query.to_vec();
    out[2] = 0x83; // QR | TC | RD
    out[3] = 0x80;
    out
}

// ---- plain UDP/TCP upstreams --------------------------------------------------------------------

/// A UDP upstream answering `answer` (or truncating) and counting the queries it saw.
pub fn spawn_udp_upstream(answer: [u8; 4], truncate: bool) -> (SocketAddr, Arc<AtomicUsize>) {
    spawn_udp_socket(
        std::net::UdpSocket::bind("127.0.0.1:0").expect("bind the fake upstream"),
        answer,
        truncate,
    )
}

/// The same on an already-bound socket, so the TCP and UDP halves of the truncation case can share
/// one port the way a real upstream does.
pub fn spawn_udp_socket(
    socket: std::net::UdpSocket,
    answer: [u8; 4],
    truncate: bool,
) -> (SocketAddr, Arc<AtomicUsize>) {
    socket
        .set_read_timeout(Some(Duration::from_millis(200)))
        .expect("timeout");
    let address = socket.local_addr().expect("local addr");
    let count = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&count);
    std::thread::spawn(move || {
        let mut buffer = [0u8; 4096];
        loop {
            let Ok((read, peer)) = socket.recv_from(&mut buffer) else {
                continue;
            };
            counter.fetch_add(1, Ordering::Relaxed);
            let query = &buffer[..read];
            let response = if truncate {
                truncated_wire(query)
            } else {
                answer_wire(query, answer, 60)
            };
            let _ = socket.send_to(&response, peer);
        }
    });
    (address, count)
}

/// A TCP upstream on an already-bound listener, so the truncation fallback can be observed.
pub fn spawn_tcp_listener(
    listener: std::net::TcpListener,
    answer: [u8; 4],
) -> (SocketAddr, Arc<AtomicUsize>) {
    listener
        .set_nonblocking(false)
        .expect("the fake upstream stays blocking");
    let address = listener.local_addr().expect("local addr");
    let count = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&count);
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            counter.fetch_add(1, Ordering::Relaxed);
            let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
            let mut header = [0u8; 2];
            if std::io::Read::read_exact(&mut stream, &mut header).is_err() {
                continue;
            }
            let length = u16::from_be_bytes(header) as usize;
            let mut query = vec![0u8; length];
            if std::io::Read::read_exact(&mut stream, &mut query).is_err() {
                continue;
            }
            let response = answer_wire(&query, answer, 60);
            let mut framed = (response.len() as u16).to_be_bytes().to_vec();
            framed.extend_from_slice(&response);
            let _ = std::io::Write::write_all(&mut stream, &framed);
        }
    });
    (address, count)
}

// ---- the test PKI -------------------------------------------------------------------------------

/// A root CA plus one leaf for `host`, minted the way the MITM path mints leaves.
pub struct TestPki {
    /// The root CA PEM the client has to trust.
    pub ca_pem: String,
    chain: Vec<rustls::pki_types::CertificateDer<'static>>,
    key: PrivateKeyDer<'static>,
}

impl TestPki {
    pub fn new(host: &str) -> Self {
        let now = unix_seconds();
        let generated =
            diting_cert_core::ca::CertAuthority::generate(now).expect("mint the test CA");
        let ca_pem = generated.authority.ca_pem().to_string();
        let leaf = generated
            .authority
            .issue(host, now)
            .expect("mint the test leaf");
        let (chain, key) =
            certificate_from_pem(&leaf.chain_pem, &leaf.key_pem).expect("parse the test PKI");
        Self { ca_pem, chain, key }
    }

    pub fn roots(&self) -> RootCertStore {
        let mut roots = RootCertStore::empty();
        assert_eq!(
            add_pem_roots(&mut roots, &[&self.ca_pem]),
            1,
            "the test CA loads"
        );
        roots
    }

    /// A TLS server config with the given ALPN list.
    pub fn server_config(&self, alpn: &[&[u8]]) -> Arc<ServerConfig> {
        let mut config =
            ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
                .with_protocol_versions(&[&rustls::version::TLS12, &rustls::version::TLS13])
                .expect("TLS 1.2 and 1.3")
                .with_no_client_auth()
                .with_single_cert(self.chain.clone(), self.key.clone_key())
                .expect("the test certificate is usable");
        config.alpn_protocols = alpn.iter().map(|protocol| protocol.to_vec()).collect();
        Arc::new(config)
    }
}

pub fn unix_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or(0)
}

// ---- DoT origin ---------------------------------------------------------------------------------

/// A DoT server: one 2-byte framed request and answer per connection, connections counted.
pub async fn spawn_dot(pki: &TestPki) -> (SocketAddr, Arc<AtomicUsize>) {
    let acceptor = TlsAcceptor::from(pki.server_config(&[]));
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind DoT");
    let address = listener.local_addr().expect("local addr");
    let connections = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&connections);
    tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                continue;
            };
            counter.fetch_add(1, Ordering::Relaxed);
            let acceptor = acceptor.clone();
            tokio::spawn(async move {
                let Ok(mut stream) = acceptor.accept(stream).await else {
                    return;
                };
                loop {
                    let mut header = [0u8; 2];
                    if stream.read_exact(&mut header).await.is_err() {
                        return;
                    }
                    let length = u16::from_be_bytes(header) as usize;
                    let mut query = vec![0u8; length];
                    if stream.read_exact(&mut query).await.is_err() {
                        return;
                    }
                    let response = answer_wire(&query, [9, 8, 7, 6], 60);
                    let mut framed = (response.len() as u16).to_be_bytes().to_vec();
                    framed.extend_from_slice(&response);
                    if stream.write_all(&framed).await.is_err() {
                        return;
                    }
                }
            });
        }
    });
    (address, connections)
}

// ---- DoH origin ---------------------------------------------------------------------------------

/// A DoH origin speaking HTTP/2 (and 1.1): `/dns-query` answers, anything else is a 403.
pub async fn spawn_doh(pki: &TestPki) -> (SocketAddr, Arc<AtomicUsize>, Arc<Mutex<Vec<Version>>>) {
    let acceptor = TlsAcceptor::from(pki.server_config(&[b"h2", b"http/1.1"]));
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind DoH");
    let address = listener.local_addr().expect("local addr");
    let connections = Arc::new(AtomicUsize::new(0));
    let versions = Arc::new(Mutex::new(Vec::new()));
    let counter = Arc::clone(&connections);
    let seen = Arc::clone(&versions);

    tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                continue;
            };
            counter.fetch_add(1, Ordering::Relaxed);
            let acceptor = acceptor.clone();
            let seen = Arc::clone(&seen);
            tokio::spawn(async move {
                let Ok(stream) = acceptor.accept(stream).await else {
                    return;
                };
                let service = service_fn(move |request: Request<Incoming>| {
                    let seen = Arc::clone(&seen);
                    async move {
                        seen.lock().unwrap().push(request.version());
                        let limited = request.uri().path().contains("limited");
                        let query = request.into_body().collect().await;
                        let query = match query {
                            Ok(collected) => collected.to_bytes(),
                            Err(_) => Bytes::new(),
                        };
                        let response = if limited {
                            Response::builder()
                                .status(StatusCode::FORBIDDEN)
                                .body(Full::new(Bytes::new()))
                        } else {
                            Response::builder()
                                .status(StatusCode::OK)
                                .header(http::header::CONTENT_TYPE, DNS_MESSAGE)
                                .body(Full::new(Bytes::from(answer_wire(
                                    &query,
                                    [4, 3, 2, 1],
                                    60,
                                ))))
                        };
                        response.map_err(|error| std::io::Error::other(error.to_string()))
                    }
                });
                let _ = auto::Builder::new(TokioExecutor::new())
                    .serve_connection(TokioIo::new(stream), service)
                    .await;
            });
        }
    });

    (address, connections, versions)
}

// ---- DoQ origin ---------------------------------------------------------------------------------

/// A DoQ server: one bidirectional stream per query, connections counted.
pub async fn spawn_doq(pki: &TestPki) -> (SocketAddr, Arc<AtomicUsize>) {
    let tls = pki.server_config(&[b"doq"]);
    let crypto = quinn::crypto::rustls::QuicServerConfig::try_from((*tls).clone())
        .expect("the DoQ server config is valid");
    let server_config = quinn::ServerConfig::with_crypto(Arc::new(crypto));
    let endpoint =
        quinn::Endpoint::server(server_config, "127.0.0.1:0".parse().expect("a valid bind"))
            .expect("bind DoQ");
    let address = endpoint.local_addr().expect("local addr");
    let connections = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&connections);

    tokio::spawn(async move {
        while let Some(incoming) = endpoint.accept().await {
            let counter = Arc::clone(&counter);
            tokio::spawn(async move {
                let Ok(connection) = incoming.await else {
                    return;
                };
                counter.fetch_add(1, Ordering::Relaxed);
                while let Ok((mut send, mut recv)) = connection.accept_bi().await {
                    let Ok(framed) = recv.read_to_end(65_535).await else {
                        return;
                    };
                    if framed.len() < 2 {
                        continue;
                    }
                    let query = &framed[2..];
                    let response = answer_wire(query, [6, 5, 4, 3], 60);
                    let mut out = (response.len() as u16).to_be_bytes().to_vec();
                    out.extend_from_slice(&response);
                    if send.write_all(&out).await.is_err() {
                        return;
                    }
                    let _ = send.finish();
                }
            });
        }
    });

    (address, connections)
}

// ---- the resolver under test --------------------------------------------------------------------

#[derive(Default)]
pub struct Recorder {
    pub events: Mutex<Vec<BootstrapEvent>>,
}

impl BootstrapSink for Recorder {
    fn bootstrap(&self, event: &BootstrapEvent) {
        self.events.lock().unwrap().push(event.clone());
    }
}

pub fn provider_json(id: &str, protocol: &str, server: &str, url: &str) -> String {
    format!(
        r#"{{"id":"{id}","protocol":"{protocol}","server":"{server}","url":"{url}","weight":1}}"#
    )
}

pub fn config_json(mode: &str, providers: &[String], bootstrap: Option<&str>) -> String {
    let bootstrap = bootstrap.unwrap_or(r#"{"enabled":false,"ips":[]}"#);
    format!(
        r#"{{"mode":"{mode}","providers":[{}],"blockResponse":"NXDOMAIN","dynamicResponse":{{"enabled":false,"requestThreshold":0,"windowSeconds":0,"nxDomainDurationSeconds":0}},"cache":{{"enabled":false,"mode":"limit_max_ttl","maxTtlSeconds":0,"fixedTtlSeconds":0,"minTtlEnabled":false,"minTtlSeconds":0,"staleFallbackEnabled":false,"staleFallbackSeconds":0,"negativeTtlEnabled":false,"negativeTtlSeconds":0}},"bootstrap":{bootstrap}}}"#,
        providers.join(",")
    )
}

pub fn resolver(config: &str, ca_pem: Option<&str>, sink: Arc<dyn BootstrapSink>) -> Resolver {
    let trust = match ca_pem {
        Some(pem) => {
            let mut roots = RootCertStore::empty();
            assert_eq!(add_pem_roots(&mut roots, &[pem]), 1, "the test CA loads");
            UpstreamTrust::from_roots(roots)
        }
        None => UpstreamTrust::platform(),
    };
    let config = DnsConfig::from_json(config).expect("the test config is valid");
    Resolver::configured(
        &config,
        ResolverDeps {
            outbound: None,
            trust: Arc::new(trust),
            bootstrap: Arc::new(Bootstrap::new(sink)),
            stats: Arc::new(StatsStore::default()),
            protector: diting_engine::protect::ProtectorHandle::new(),
        },
    )
}
