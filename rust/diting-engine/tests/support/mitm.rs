#![allow(dead_code)]

use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use bytes::Bytes;
use diting_cert_core::ca::CertAuthority;
use diting_engine::engine::Engine;
use diting_engine::mitm::handler;
use diting_engine::netstack::TcpKey;
use diting_engine::resolver::trust::add_pem_roots;
use diting_engine::tunnel::dnsflow::Inbound;
use diting_engine::tunnel::gate::FlowContext;
use diting_engine::tunnel::queue::{Event, Events};
use diting_engine::tunnel::stats::TunnelCounters;
use http::{HeaderMap, Request, StatusCode};
use http_body_util::{BodyExt, Empty};
use hyper::body::Incoming;
use hyper_util::rt::TokioIo;
use rustls::pki_types::{CertificateDer, ServerName};
use rustls::{ClientConfig, RootCertStore, ServerConfig};
use smoltcp::wire::{IpAddress, IpEndpoint};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::{TlsAcceptor, TlsConnector};

pub const HOST: &str = "upstream.test";

pub struct Origin {
    pub address: SocketAddr,
    pub ca_pem: String,
    pub requests: Arc<Mutex<Vec<(String, String)>>>,
    pub encodings: Arc<Mutex<Vec<String>>>,
}

impl Origin {
    pub fn request_count(&self) -> usize {
        self.requests.lock().expect("requests").len()
    }

    pub fn encoding_of(&self, index: usize) -> String {
        self.encodings
            .lock()
            .expect("encodings")
            .get(index)
            .cloned()
            .unwrap_or_default()
    }
}

fn origin_pki() -> (
    CertAuthority,
    Vec<CertificateDer<'static>>,
    rustls::pki_types::PrivateKeyDer<'static>,
) {
    let authority = CertAuthority::generate(now())
        .expect("mint the origin CA")
        .authority;
    let leaf = authority.issue(HOST, now()).expect("mint the origin leaf");
    let (chain, key) =
        diting_engine::resolver::trust::certificate_from_pem(&leaf.chain_pem, &leaf.key_pem)
            .expect("the origin leaf parses");
    (authority, chain, key)
}

fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or(0)
}

pub const PAGE: &str = "<html><head><title>t</title></head><body><p>hello</p></body></html>";

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Route {
    Html,
    GzipHtml,
    PlainText,
}

fn route_for(path: &str) -> (Route, Bytes) {
    match path {
        "/gzip" => (Route::GzipHtml, Bytes::from(gzip(PAGE.as_bytes()))),
        "/plain" => (Route::PlainText, Bytes::from_static(b"not a page")),
        _ => (Route::Html, Bytes::from_static(PAGE.as_bytes())),
    }
}

fn gzip(data: &[u8]) -> Vec<u8> {
    let mut out = vec![0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff];
    let mut remaining = data;
    while !remaining.is_empty() {
        let chunk = remaining.len().min(0xffff);
        let last = chunk == remaining.len();
        out.push(u8::from(last));
        out.extend_from_slice(&(chunk as u16).to_le_bytes());
        out.extend_from_slice(&(!(chunk as u16)).to_le_bytes());
        out.extend_from_slice(&remaining[..chunk]);
        remaining = &remaining[chunk..];
    }
    out.extend_from_slice(&crc32(data).to_le_bytes());
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for byte in data {
        crc ^= u32::from(*byte);
        for _ in 0..8 {
            let mask = (crc & 1).wrapping_neg();
            crc = (crc >> 1) ^ (0xedb8_8320 & mask);
        }
    }
    !crc
}

pub async fn spawn_origin() -> Origin {
    let (authority, chain, key) = origin_pki();
    let mut config =
        ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
            .with_safe_default_protocol_versions()
            .expect("protocol versions")
            .with_no_client_auth()
            .with_single_cert(chain, key)
            .expect("the origin certificate is usable");
    config.alpn_protocols = Vec::new();
    spawn_origin_with(config, authority.ca_pem().to_string()).await
}

pub async fn spawn_mtls_origin() -> Origin {
    let (authority, chain, key) = origin_pki();
    let mut roots = RootCertStore::empty();
    roots
        .add(chain.first().expect("the leaf certificate").clone())
        .expect("the leaf is a usable trust anchor");
    let verifier = rustls::server::WebPkiClientVerifier::builder_with_provider(
        Arc::new(roots),
        Arc::new(rustls::crypto::ring::default_provider()),
    )
    .allow_unauthenticated()
    .build()
    .expect("the client verifier builds");
    let mut config =
        ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
            .with_safe_default_protocol_versions()
            .expect("protocol versions")
            .with_client_cert_verifier(verifier)
            .with_single_cert(chain, key)
            .expect("the origin certificate is usable");
    config.alpn_protocols = Vec::new();
    spawn_origin_with(config, authority.ca_pem().to_string()).await
}

pub async fn spawn_plain_origin() -> Origin {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind the origin");
    let address = listener.local_addr().expect("local addr");
    let requests = Arc::new(Mutex::new(Vec::new()));
    let encodings = Arc::new(Mutex::new(Vec::new()));
    let recorded = Arc::clone(&requests);
    let seen = Arc::clone(&encodings);
    tokio::spawn(async move {
        loop {
            let Ok((stream, _peer)) = listener.accept().await else {
                continue;
            };
            let recorded = Arc::clone(&recorded);
            let seen = Arc::clone(&seen);
            tokio::spawn(async move {
                let service = hyper::service::service_fn(move |request: Request<Incoming>| {
                    let recorded = Arc::clone(&recorded);
                    let seen = Arc::clone(&seen);
                    async move { answer(&recorded, &seen, request).await }
                });
                let _ = hyper::server::conn::http1::Builder::new()
                    .serve_connection(TokioIo::new(stream), service)
                    .await;
            });
        }
    });
    Origin {
        address,
        ca_pem: String::new(),
        requests,
        encodings,
    }
}

async fn spawn_origin_with(config: ServerConfig, ca_pem: String) -> Origin {
    let acceptor = TlsAcceptor::from(Arc::new(config));
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind the origin");
    let address = listener.local_addr().expect("local addr");
    let requests = Arc::new(Mutex::new(Vec::new()));
    let encodings = Arc::new(Mutex::new(Vec::new()));
    let recorded = Arc::clone(&requests);
    let seen = Arc::clone(&encodings);
    tokio::spawn(async move {
        loop {
            let Ok((stream, _peer)) = listener.accept().await else {
                continue;
            };
            let acceptor = acceptor.clone();
            let recorded = Arc::clone(&recorded);
            let seen = Arc::clone(&seen);
            tokio::spawn(async move {
                let Ok(tls) = acceptor.accept(stream).await else {
                    return;
                };
                let service = hyper::service::service_fn(move |request: Request<Incoming>| {
                    let recorded = Arc::clone(&recorded);
                    let seen = Arc::clone(&seen);
                    async move { answer(&recorded, &seen, request).await }
                });
                let _ = hyper::server::conn::http1::Builder::new()
                    .serve_connection(TokioIo::new(tls), service)
                    .await;
            });
        }
    });
    Origin {
        address,
        ca_pem,
        requests,
        encodings,
    }
}

async fn answer(
    recorded: &Arc<Mutex<Vec<(String, String)>>>,
    encodings: &Arc<Mutex<Vec<String>>>,
    request: Request<Incoming>,
) -> Result<http::Response<http_body_util::Full<Bytes>>, std::convert::Infallible> {
    let host = request
        .headers()
        .get(http::header::HOST)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_string();
    let encoding = request
        .headers()
        .get(http::header::ACCEPT_ENCODING)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_string();
    recorded
        .lock()
        .expect("requests")
        .push((host, request.uri().to_string()));
    encodings.lock().expect("encodings").push(encoding);

    let (route, body) = route_for(request.uri().path());
    let _ = request.into_body().collect().await;
    let response = match route {
        Route::Html => http::Response::builder()
            .status(StatusCode::OK)
            .header(http::header::CONTENT_TYPE, "text/html; charset=utf-8")
            .body(http_body_util::Full::new(body)),
        Route::GzipHtml => http::Response::builder()
            .status(StatusCode::OK)
            .header(http::header::CONTENT_TYPE, "text/html; charset=utf-8")
            .header(http::header::CONTENT_ENCODING, "gzip")
            .body(http_body_util::Full::new(body)),
        Route::PlainText => http::Response::builder()
            .status(StatusCode::OK)
            .header(http::header::CONTENT_TYPE, "text/plain")
            .body(http_body_util::Full::new(body)),
    };
    Ok(response.expect("the origin response is well formed"))
}

pub struct Client {
    sender: hyper::client::conn::http1::SendRequest<Empty<Bytes>>,
    pub peer_certificates: Vec<CertificateDer<'static>>,
    pub alpn: Option<Vec<u8>>,
}

impl Client {
    pub async fn connect_tls(
        address: SocketAddr,
        host: &str,
        ca_pem: &str,
    ) -> Result<Client, String> {
        let mut roots = RootCertStore::empty();
        if add_pem_roots(&mut roots, &[ca_pem]) == 0 {
            return Err("the CA does not parse".to_string());
        }
        let config =
            ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
                .with_safe_default_protocol_versions()
                .map_err(|error| error.to_string())?
                .with_root_certificates(roots)
                .with_no_client_auth();
        let tcp = TcpStream::connect(address)
            .await
            .map_err(|error| error.to_string())?;
        let stream = TlsConnector::from(Arc::new(config))
            .connect(ServerName::try_from(host.to_string()).expect("host"), tcp)
            .await
            .map_err(|error| error.to_string())?;
        let (_, session) = stream.get_ref();
        let peer_certificates = session
            .peer_certificates()
            .map(|certs| certs.to_vec())
            .unwrap_or_default();
        let alpn = session.alpn_protocol().map(|value| value.to_vec());
        Ok(Client::over(stream, peer_certificates, alpn).await)
    }

    pub async fn connect_plain(address: SocketAddr) -> Client {
        let tcp = TcpStream::connect(address)
            .await
            .expect("connect the bridge");
        Client::over(tcp, Vec::new(), None).await
    }

    async fn over<T>(
        io: T,
        peer_certificates: Vec<CertificateDer<'static>>,
        alpn: Option<Vec<u8>>,
    ) -> Client
    where
        T: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        let (sender, connection) = hyper::client::conn::http1::handshake(TokioIo::new(io))
            .await
            .expect("the client handshake");
        tokio::spawn(async move {
            let _ = connection.await;
        });
        Client {
            sender,
            peer_certificates,
            alpn,
        }
    }

    pub async fn request(
        &mut self,
        host: &str,
        path: &str,
        headers: &[(&str, &str)],
    ) -> (StatusCode, HeaderMap, Vec<u8>) {
        self.try_request(host, path, headers)
            .await
            .expect("the relay answers")
    }

    pub async fn try_request(
        &mut self,
        host: &str,
        path: &str,
        headers: &[(&str, &str)],
    ) -> Result<(StatusCode, HeaderMap, Vec<u8>), String> {
        let mut builder = Request::builder()
            .method("GET")
            .uri(path)
            .header(http::header::HOST, host);
        for (name, value) in headers {
            builder = builder.header(*name, *value);
        }
        let request = builder
            .body(Empty::<Bytes>::new())
            .expect("the request is well formed");
        let response = self
            .sender
            .send_request(request)
            .await
            .map_err(|error| error.to_string())?;
        let status = response.status();
        let headers = response.headers().clone();
        let body = response
            .into_body()
            .collect()
            .await
            .map_err(|error| error.to_string())?
            .to_bytes()
            .to_vec();
        Ok((status, headers, body))
    }

    pub fn peer_issuer_common_name(&self) -> String {
        let Some(leaf) = self.peer_certificates.first() else {
            return String::new();
        };
        let Ok(certificate) = x509_cert::Certificate::from_der(leaf.as_ref()) else {
            return String::new();
        };
        use der::Decode;
        let (_, names) = diting_cert_core::ca::subject(&certificate);
        names.first().cloned().unwrap_or_default()
    }
}

pub async fn spawn_flow(
    engine: Arc<Engine>,
    counters: Arc<TunnelCounters>,
    target: SocketAddr,
    uid: i32,
    app: &str,
) -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind the bridge");
    let address = listener.local_addr().expect("bridge addr");
    let app = app.to_string();
    tokio::spawn(async move {
        let Ok((socket, peer)) = listener.accept().await else {
            return;
        };
        let key = TcpKey::new(endpoint(target), endpoint(peer));
        let context = FlowContext { uid, app };
        let (tx, rx) = tokio::sync::mpsc::channel(64);
        let events = Arc::new(Events::new(2048));
        let handler = tokio::spawn(handler::handle_tcp(
            Arc::clone(&engine),
            Arc::clone(&events),
            counters,
            key,
            context,
            rx,
        ));
        let (mut read_half, mut write_half) = socket.into_split();
        let reader = tokio::spawn(async move {
            let mut buffer = vec![0u8; 16 * 1024];
            loop {
                match read_half.read(&mut buffer).await {
                    Ok(0) => {
                        let _ = tx.send(Inbound::Eof).await;
                        return;
                    }
                    Ok(read) => {
                        if tx
                            .send(Inbound::Data(buffer[..read].to_vec()))
                            .await
                            .is_err()
                        {
                            return;
                        }
                    }
                    Err(_) => return,
                }
            }
        });

        let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
        while tokio::time::Instant::now() < deadline {
            match events.pop(Duration::ZERO) {
                Some(Event::Write(_key, data, _)) => {
                    if write_half.write_all(&data).await.is_err() {
                        break;
                    }
                }
                Some(Event::CloseWrite(_)) => {
                    let _ = write_half.shutdown().await;
                }
                Some(Event::Abort(_)) => break,
                Some(_) => {}
                None => {
                    if handler.is_finished() && events.is_empty() {
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(2)).await;
                }
            }
        }
        reader.abort();
    });
    address
}

fn endpoint(address: SocketAddr) -> IpEndpoint {
    let ip = match address.ip() {
        std::net::IpAddr::V4(v4) => {
            IpAddress::Ipv4(smoltcp::wire::Ipv4Address::from_octets(v4.octets()))
        }
        std::net::IpAddr::V6(v6) => {
            IpAddress::Ipv6(smoltcp::wire::Ipv6Address::from_octets(v6.octets()))
        }
    };
    IpEndpoint::new(ip, address.port())
}
