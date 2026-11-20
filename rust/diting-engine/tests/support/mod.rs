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


pub fn query_wire(name: &str, id: u16) -> Vec<u8> {
    let mut out = vec![0u8; 12];
    out[0..2].copy_from_slice(&id.to_be_bytes());
    out[2] = 0x01;
    out[5] = 1;
    for label in name.trim_end_matches('.').split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out
}

pub fn answer_wire(query: &[u8], address: [u8; 4], ttl: u32) -> Vec<u8> {
    let mut out = query.to_vec();
    out[2] = 0x81;
    out[3] = 0x80;
    out[7] = 1;
    out.extend_from_slice(&[0xc0, 0x0c]);
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&ttl.to_be_bytes());
    out.extend_from_slice(&4u16.to_be_bytes());
    out.extend_from_slice(&address);
    out
}

pub fn truncated_wire(query: &[u8]) -> Vec<u8> {
    let mut out = query.to_vec();
    out[2] = 0x83;
    out[3] = 0x80;
    out
}


pub fn spawn_udp_upstream(answer: [u8; 4], truncate: bool) -> (SocketAddr, Arc<AtomicUsize>) {
    spawn_udp_socket(
        std::net::UdpSocket::bind("127.0.0.1:0").expect("bind the fake upstream"),
        answer,
        truncate,
    )
}

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


pub struct TestPki {
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


pub async fn spawn_doh(pki: &TestPki) -> (SocketAddr, Arc<AtomicUsize>, Arc<Mutex<Vec<Version>>>) {
    let acceptor = TlsAcceptor::from(pki.server_config(&[b"h2", b"http/1.1"]));
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind DoH");
    let address = listener.local_addr().expect("local addr");
    let h3_port = address.port();
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
                                .header("alt-svc", format!("h3=\":{h3_port}\"; ma=60"))
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


pub async fn spawn_doh3(pki: &TestPki) -> (SocketAddr, Arc<AtomicUsize>) {
    let bind: SocketAddr = "127.0.0.1:0".parse().expect("a valid bind");
    spawn_doh3_on(pki, bind).await
}

pub async fn spawn_doh3_on(pki: &TestPki, bind: SocketAddr) -> (SocketAddr, Arc<AtomicUsize>) {
    let tls = pki.server_config(&[b"h3"]);
    let crypto = quinn::crypto::rustls::QuicServerConfig::try_from((*tls).clone())
        .expect("the DoH3 server config is valid");
    let server_config = quinn::ServerConfig::with_crypto(Arc::new(crypto));
    let endpoint = quinn::Endpoint::server(server_config, bind).expect("bind DoH3");
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
                    let Ok(request) = recv.read_to_end(65_535).await else {
                        return;
                    };
                    let Some(query) = h3_data(&request) else {
                        continue;
                    };
                    let answer = answer_wire(&query, [4, 3, 2, 1], 60);
                    let mut out = Vec::new();
                    h3_frame(&mut out, 0x01, &[0x00, 0x00]);
                    h3_frame(&mut out, 0x00, &answer);
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

pub async fn spawn_doh3_silent_on(pki: &TestPki, bind: SocketAddr) -> SocketAddr {
    let tls = pki.server_config(&[b"h3"]);
    let crypto = quinn::crypto::rustls::QuicServerConfig::try_from((*tls).clone())
        .expect("the DoH3 server config is valid");
    let server_config = quinn::ServerConfig::with_crypto(Arc::new(crypto));
    let endpoint = quinn::Endpoint::server(server_config, bind).expect("bind DoH3");
    let address = endpoint.local_addr().expect("local addr");

    tokio::spawn(async move {
        let mut connections = Vec::new();
        while let Some(incoming) = endpoint.accept().await {
            if let Ok(connection) = incoming.await {
                connections.push(connection);
            }
        }
    });

    address
}

fn h3_data(bytes: &[u8]) -> Option<Vec<u8>> {
    let mut rest = bytes;
    let mut data = Vec::new();
    while !rest.is_empty() {
        let (kind, used) = h3_varint_read(rest)?;
        rest = &rest[used..];
        let (len, used) = h3_varint_read(rest)?;
        rest = &rest[used..];
        let len = len as usize;
        if rest.len() < len {
            return None;
        }
        if kind == 0x00 {
            data.extend_from_slice(&rest[..len]);
        }
        rest = &rest[len..];
    }
    (!data.is_empty()).then_some(data)
}

fn h3_frame(out: &mut Vec<u8>, kind: u64, payload: &[u8]) {
    h3_varint(out, kind);
    h3_varint(out, payload.len() as u64);
    out.extend_from_slice(payload);
}

fn h3_varint(out: &mut Vec<u8>, value: u64) {
    if value < 64 {
        out.push(value as u8);
    } else if value < 16_384 {
        out.push((0x40 | (value >> 8)) as u8);
        out.push(value as u8);
    } else {
        out.push((0x80 | (value >> 24)) as u8);
        out.push((value >> 16) as u8);
        out.push((value >> 8) as u8);
        out.push(value as u8);
    }
}

fn h3_varint_read(buf: &[u8]) -> Option<(u64, usize)> {
    let first = *buf.first()?;
    let len = 1usize << (first >> 6);
    if buf.len() < len {
        return None;
    }
    let mut value = (first & 0x3f) as u64;
    for byte in &buf[1..len] {
        value = (value << 8) | *byte as u64;
    }
    Some((value, len))
}

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
