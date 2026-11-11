//! The loopback harness the MITM spike is driven by: a test PKI, an HTTPS origin, the proxy and a
//! client that actually speaks TLS + HTTP/1.1.
//!
//! Everything here is real I/O on 127.0.0.1: no mocked TLS, no injected HTTP parser. Only two seams
//! are faked, and both are the TUN device's job in the engine: the proxy dials
//! [`ProxyOptions::dial_override`] instead of a flow destination, and the two certificate authorities
//! are generated per test instead of being loaded from `.go-mitm/ca.crt` / `ca.key`.

#![allow(dead_code)]

use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use bytes::Bytes;
use diting_cert_core::ca::CertAuthority;
use diting_mitm_spike::cert::CertStore;
use diting_mitm_spike::relay::{Proxy, ProxyOptions};
use diting_mitm_spike::trust::add_pem_roots;
use diting_mitm_spike::upstream::UpstreamTls;
use diting_mitm_spike::{now_unix, provider, BoxError, ResponseBody};
use futures_util::TryStreamExt;
use http::{Request, Response, StatusCode};
use http_body_util::{BodyExt, Full, StreamBody};
use hyper::body::{Frame, Incoming};
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName};
use rustls::{ClientConfig, RootCertStore, ServerConfig};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;
use tokio_rustls::{TlsAcceptor, TlsConnector};

/// The hostname the test origin presents. The proxy's `dial_override` points at its loopback port.
pub const UPSTREAM_HOST: &str = "upstream.test";

/// The two authorities a test needs: one for the proxy's leaves, one for the "real" server.
pub struct Pki {
    origin: CertAuthority,
    store: Arc<CertStore>,
}

impl Pki {
    pub fn new() -> Pki {
        let now = now_unix();
        let mitm = CertAuthority::generate(now).expect("mint the MITM CA");
        Pki {
            origin: CertAuthority::generate(now)
                .expect("mint the origin CA")
                .authority,
            store: Arc::new(CertStore::new(mitm.authority)),
        }
    }

    /// The proxy's certificate store (the root CA the client has to trust).
    pub fn store(&self) -> Arc<CertStore> {
        self.store.clone()
    }

    /// The PEM a client installs/injects to trust the proxy.
    pub fn mitm_ca_pem(&self) -> &str {
        self.store.authority().ca_pem()
    }

    /// The origin's root CA: what the proxy's upstream trust store is built from.
    pub fn origin_ca_pem(&self) -> &str {
        self.origin.ca_pem()
    }

    pub fn roots_with(&self, pem: &str) -> RootCertStore {
        let mut roots = RootCertStore::empty();
        assert_eq!(add_pem_roots(&mut roots, &[pem]), 1, "the test CA loads");
        roots
    }
}

/// How the test origin should treat client certificates.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum OriginAuth {
    /// No `CertificateRequest` at all.
    Plain,
    /// Request a client certificate but accept none — the signal Go's `clientCertRequested` caught.
    RequestClientCert,
}

/// What the origin saw, so a test can assert on the request the proxy produced.
#[derive(Debug, Clone, Default)]
pub struct RecordedRequest {
    pub path: String,
    pub headers: Vec<(String, String)>,
}

impl RecordedRequest {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }
}

/// A response body produced by the origin (the spike's own body type).
pub type Body = ResponseBody;

pub fn html(body: &str) -> Response<Body> {
    respond(
        StatusCode::OK,
        "text/html; charset=utf-8",
        Bytes::from(body.to_string()),
    )
}

pub fn text(body: &str) -> Response<Body> {
    respond(
        StatusCode::OK,
        "text/plain; charset=utf-8",
        Bytes::from(body.to_string()),
    )
}

pub fn respond(status: StatusCode, content_type: &str, body: Bytes) -> Response<Body> {
    let body: Body = Full::new(body)
        .map_err(|never| match never {})
        .boxed_unsync();
    Response::builder()
        .status(status)
        .header(http::header::CONTENT_TYPE, content_type)
        .body(body)
        .expect("build a response")
}

/// A response with no `Content-Length`, delivered in several chunks (HTTP/1.1 chunked framing).
pub fn streamed(content_type: &str, chunks: Vec<Bytes>) -> Response<Body> {
    let frames = chunks
        .into_iter()
        .map(|chunk| Ok::<_, BoxError>(Frame::data(chunk)));
    let stream = futures_util::stream::iter(frames);
    let body: Body = StreamBody::new(stream).boxed_unsync();
    Response::builder()
        .status(StatusCode::OK)
        .header(http::header::CONTENT_TYPE, content_type)
        .body(body)
        .expect("build a streaming response")
}

/// The HTTPS origin: a TLS listener plus one hyper connection task per client.
pub struct Origin {
    pub addr: SocketAddr,
    pub requests: Arc<Mutex<Vec<RecordedRequest>>>,
    task: JoinHandle<()>,
}

impl Origin {
    /// The requests seen so far.
    pub fn seen(&self) -> Vec<RecordedRequest> {
        self.requests
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .clone()
    }
}

impl Drop for Origin {
    fn drop(&mut self) {
        self.task.abort();
    }
}

/// Spawns a TLS origin on a loopback port.
pub async fn spawn_origin(
    pki: &Pki,
    auth: OriginAuth,
    handler: impl Fn(Request<Incoming>, RecordedRequest) -> Response<Body> + Send + Sync + 'static,
) -> Origin {
    let leaf = pki
        .origin
        .issue(UPSTREAM_HOST, now_unix())
        .expect("mint the origin leaf");
    let config = origin_config(&leaf.chain_pem, &leaf.key_pem, pki, auth);
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind the origin");
    let addr = listener.local_addr().expect("origin address");
    let requests = Arc::new(Mutex::new(Vec::new()));
    let handler = Arc::new(handler);
    let acceptor = TlsAcceptor::from(Arc::new(config));
    let recorded = requests.clone();

    let task = tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                return;
            };
            let acceptor = acceptor.clone();
            let handler = handler.clone();
            let recorded = recorded.clone();
            tokio::spawn(async move {
                let Ok(tls) = acceptor.accept(stream).await else {
                    return;
                };
                let service = service_fn(move |request: Request<Incoming>| {
                    let record = RecordedRequest {
                        path: request.uri().path().to_string(),
                        headers: request
                            .headers()
                            .iter()
                            .filter_map(|(name, value)| {
                                value
                                    .to_str()
                                    .ok()
                                    .map(|value| (name.to_string(), value.to_string()))
                            })
                            .collect(),
                    };
                    recorded
                        .lock()
                        .unwrap_or_else(|err| err.into_inner())
                        .push(record.clone());
                    let response = handler(request, record);
                    async move { Ok::<_, std::convert::Infallible>(response) }
                });
                let _ = hyper::server::conn::http1::Builder::new()
                    .serve_connection(TokioIo::new(tls), service)
                    .await;
            });
        }
    });

    Origin {
        addr,
        requests,
        task,
    }
}

fn origin_config(chain_pem: &str, key_pem: &str, pki: &Pki, auth: OriginAuth) -> ServerConfig {
    let chain: Vec<CertificateDer<'static>> =
        rustls_pemfile::certs(&mut std::io::BufReader::new(chain_pem.as_bytes()))
            .filter_map(Result::ok)
            .collect();
    let key: PrivateKeyDer<'static> =
        rustls_pemfile::private_key(&mut std::io::BufReader::new(key_pem.as_bytes()))
            .expect("read the origin key")
            .expect("the origin key is present");
    let builder = ServerConfig::builder_with_provider(provider())
        .with_safe_default_protocol_versions()
        .expect("ring provider");
    match auth {
        OriginAuth::Plain => builder
            .with_no_client_auth()
            .with_single_cert(chain, key)
            .expect("origin server config"),
        OriginAuth::RequestClientCert => {
            let verifier = rustls::server::WebPkiClientVerifier::builder(Arc::new(
                pki.roots_with(pki.origin_ca_pem()),
            ))
            .allow_unauthenticated()
            .build()
            .expect("build the client certificate verifier");
            builder
                .with_client_cert_verifier(verifier)
                .with_single_cert(chain, key)
                .expect("origin server config")
        }
    }
}

/// The end of an HTTP/1.1 request head.
const REQUEST_HEAD_END: &[u8] = b"\r\n\r\n";

/// One complete HTTP/1.1 response, written by hand so it cannot be re-framed by hyper.
const RAW_RESPONSE: &[u8] =
    b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\n\r\nok";

/// A TLS origin that speaks one raw HTTP/1.1 response and then closes the socket, so the proxy's
/// upstream connection dies between two keep-alive requests.
pub struct RawOrigin {
    pub addr: SocketAddr,
    pub connections: Arc<std::sync::atomic::AtomicUsize>,
    task: JoinHandle<()>,
}

impl Drop for RawOrigin {
    fn drop(&mut self) {
        self.task.abort();
    }
}

pub async fn spawn_raw_origin(pki: &Pki) -> RawOrigin {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let leaf = pki
        .origin
        .issue(UPSTREAM_HOST, now_unix())
        .expect("mint the origin leaf");
    let config = origin_config(&leaf.chain_pem, &leaf.key_pem, pki, OriginAuth::Plain);
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind the raw origin");
    let addr = listener.local_addr().expect("raw origin address");
    let connections = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let counter = connections.clone();
    let acceptor = TlsAcceptor::from(Arc::new(config));

    let task = tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                return;
            };
            counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            let acceptor = acceptor.clone();
            tokio::spawn(async move {
                let Ok(mut tls) = acceptor.accept(stream).await else {
                    return;
                };
                let mut request = Vec::new();
                let mut chunk = [0u8; 1024];
                // Read the request head only: these tests never send a body.
                loop {
                    match tls.read(&mut chunk).await {
                        Ok(0) => return,
                        Ok(read) => {
                            request.extend_from_slice(&chunk[..read]);
                            if request.windows(4).any(|window| window == REQUEST_HEAD_END) {
                                break;
                            }
                        }
                        Err(_) => return,
                    }
                }
                let _ = tls.write_all(RAW_RESPONSE).await;
                let _ = tls.flush().await;
                let _ = tls.shutdown().await;
            });
        }
    });

    RawOrigin {
        addr,
        connections,
        task,
    }
}

/// A running proxy: its address, the instance (for events) and the accept task.
pub struct RunningProxy {
    pub addr: SocketAddr,
    pub proxy: Proxy,
    task: JoinHandle<()>,
}

impl Drop for RunningProxy {
    fn drop(&mut self) {
        self.task.abort();
    }
}

/// Spawns the MITM proxy in front of `origin`.
pub async fn spawn_proxy(
    pki: &Pki,
    origin: &Origin,
    inject_css: bool,
    trust_origin: bool,
) -> RunningProxy {
    spawn_proxy_at(pki, origin.addr, inject_css, trust_origin).await
}

/// The same proxy, dialling an arbitrary loopback address (`RawOrigin` uses this).
pub async fn spawn_proxy_at(
    pki: &Pki,
    dial: SocketAddr,
    inject_css: bool,
    trust_origin: bool,
) -> RunningProxy {
    let roots = if trust_origin {
        pki.roots_with(pki.origin_ca_pem())
    } else {
        RootCertStore::empty()
    };
    let options = ProxyOptions {
        dial_override: Some(dial),
        inject_css,
        default_host: Some(UPSTREAM_HOST.to_string()),
    };
    let proxy = Proxy::new(pki.store(), UpstreamTls::new(roots), options);
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind the proxy");
    let addr = listener.local_addr().expect("proxy address");
    let serving = proxy.clone();
    let task = tokio::spawn(async move {
        let _ = serving.serve(listener).await;
    });
    RunningProxy { addr, proxy, task }
}

/// A client that trusts the MITM CA and speaks HTTP/1.1 over one TLS connection.
pub struct TestClient {
    send: hyper::client::conn::http1::SendRequest<Full<Bytes>>,
    task: JoinHandle<()>,
    peer_certificates: Vec<CertificateDer<'static>>,
    alpn: Option<Vec<u8>>,
}

impl Drop for TestClient {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl TestClient {
    /// Connects with the given ALPN offer; `Err` is the handshake failure a pinning/h2-only client sees.
    pub async fn connect(
        addr: SocketAddr,
        sni: &str,
        ca_pem: &str,
        alpn: &[&[u8]],
    ) -> Result<TestClient, BoxError> {
        let mut roots = RootCertStore::empty();
        assert_eq!(add_pem_roots(&mut roots, &[ca_pem]), 1, "the MITM CA loads");
        let mut config = ClientConfig::builder_with_provider(provider())
            .with_safe_default_protocol_versions()
            .expect("ring provider")
            .with_root_certificates(roots)
            .with_no_client_auth();
        config.alpn_protocols = alpn.iter().map(|protocol| protocol.to_vec()).collect();

        let tcp = TcpStream::connect(addr).await?;
        let server_name = ServerName::try_from(sni.to_string())
            .map_err(|err| format!("bad server name: {err}"))?;
        let stream = TlsConnector::from(Arc::new(config))
            .connect(server_name, tcp)
            .await?;

        // The handshake facts have to be read before hyper takes the stream.
        let (_, session) = stream.get_ref();
        let peer_certificates = session
            .peer_certificates()
            .map(|certs| certs.to_vec())
            .unwrap_or_default();
        let alpn = session.alpn_protocol().map(|protocol| protocol.to_vec());

        let (send, connection) =
            hyper::client::conn::http1::handshake(TokioIo::new(stream)).await?;
        let task = tokio::spawn(async move {
            let _ = connection.await;
        });
        Ok(TestClient {
            send,
            task,
            peer_certificates,
            alpn,
        })
    }

    pub fn peer_certificates(&self) -> &[CertificateDer<'static>] {
        &self.peer_certificates
    }

    pub fn alpn(&self) -> Option<&[u8]> {
        self.alpn.as_deref()
    }

    pub async fn request(
        &mut self,
        request: Request<Full<Bytes>>,
    ) -> Result<Response<Incoming>, BoxError> {
        Ok(self.send.send_request(request).await?)
    }

    pub async fn get(&mut self, path: &str) -> Result<Response<Incoming>, BoxError> {
        let request = with_host(Request::builder().uri(path))
            .body(Full::new(Bytes::new()))
            .expect("build a GET");
        self.request(request).await
    }

    /// A GET with an `Accept` header, so the proxy's `Accept-Encoding` policy can be observed.
    pub async fn get_accepting(
        &mut self,
        path: &str,
        accept: &str,
    ) -> Result<Response<Incoming>, BoxError> {
        let request = with_host(Request::builder().uri(path))
            .header(http::header::ACCEPT, accept)
            .header(http::header::ACCEPT_ENCODING, "gzip, deflate")
            .body(Full::new(Bytes::new()))
            .expect("build a GET");
        self.request(request).await
    }
}

fn with_host(builder: http::request::Builder) -> http::request::Builder {
    builder.header(http::header::HOST, UPSTREAM_HOST)
}

/// Reads a body to the end.
pub async fn collect(response: Response<Incoming>) -> Vec<u8> {
    response
        .into_body()
        .into_data_stream()
        .try_fold(Vec::new(), |mut acc, chunk| async move {
            acc.extend_from_slice(&chunk);
            Ok(acc)
        })
        .await
        .expect("read the body")
}

/// Reads the body as text.
pub async fn collect_text(response: Response<Incoming>) -> String {
    String::from_utf8(collect(response).await).expect("the body is UTF-8")
}
