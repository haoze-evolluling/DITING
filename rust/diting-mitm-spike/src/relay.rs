//! The relay itself: accept a flow, terminate TLS with a minted leaf, and pipe HTTP/1.1 through.
//!
//! This is `mitmTLSFlow` + `relayHTTPFlow` with `net/http` replaced by hyper 1.x. The decision order
//! is kept:
//!
//! 1. client-first TLS handshake with a leaf minted for the SNI (a pinning client aborts here, which
//!    is the cheap outcome: no upstream radio is touched);
//! 2. upstream TLS handshake with certificate verification, then the EV/mTLS refusal check;
//! 3. per request: strip `Accept-Encoding` for HTML clients, relay the request, then splice the
//!    cosmetic `<link>` into HTML responses while they stream.
//!
//! What stays out of the spike on purpose: the TUN flow, the gate/filter decisions, connection
//! logging, UID attribution and the local asset/302 rewrite responders. They are already Rust
//! kernels or belong to stage 3/4; the spike only has to answer whether rustls + hyper reproduce the
//! HTTP and TLS semantics the Go relay depended on.

use std::net::SocketAddr;
use std::sync::{Arc, Mutex as StdMutex};

use bytes::Bytes;
use http::{Request, Response, StatusCode};
use http_body_util::BodyExt;
use hyper::body::Incoming;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Mutex as AsyncMutex;
use tokio::task::JoinHandle;
use tokio_rustls::TlsAcceptor;

use crate::cert::CertStore;
use crate::upstream::UpstreamTls;
use crate::{inject, BoxError, ResponseBody};

/// The protocol label the Go engine logged for TLS flows.
pub const PROTOCOL_HTTPS: &str = "HTTPS";
/// `logHTTPEvent(flow, host, "HTTPS", "handshake_failed", "client_tls")`.
pub const STATUS_HANDSHAKE_FAILED: &str = "handshake_failed";
/// `logHTTPEvent(flow, host, "HTTPS", "upstream_failed", "upstream_tls")`.
pub const STATUS_UPSTREAM_FAILED: &str = "upstream_failed";
/// `logHTTPEvent(flow, host, protocol, "allowed", "")`.
pub const STATUS_ALLOWED: &str = "allowed";

/// One relay observation, the `logHTTPEvent(flow, host, protocol, status, reason)` tuple.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpEvent {
    pub host: String,
    pub protocol: &'static str,
    pub status: &'static str,
    pub reason: String,
}

/// Everything the relay needs that is not part of the two TLS configs.
#[derive(Debug, Clone, Default)]
pub struct ProxyOptions {
    /// Dial this address instead of resolving the request host. The real engine dials the TUN flow's
    /// original destination (`flow.serverIP:serverPort`), which is exactly this indirection.
    pub dial_override: Option<SocketAddr>,
    /// Whether cosmetic rules exist (`cosmeticRulesEmpty()` in Go). Injection is off without them.
    pub inject_css: bool,
    /// Go's `GetDynamicTLSConfigForHost(defaultHost)`: the flow hostname for clients that omit SNI.
    pub default_host: Option<String>,
}

struct ProxyInner {
    certs: Arc<CertStore>,
    upstream: UpstreamTls,
    options: ProxyOptions,
    events: StdMutex<Vec<HttpEvent>>,
}

/// A MITM relay bound to one certificate store and one upstream trust config.
#[derive(Clone)]
pub struct Proxy {
    inner: Arc<ProxyInner>,
}

impl Proxy {
    pub fn new(certs: Arc<CertStore>, upstream: UpstreamTls, options: ProxyOptions) -> Proxy {
        Proxy {
            inner: Arc::new(ProxyInner {
                certs,
                upstream,
                options,
                events: StdMutex::new(Vec::new()),
            }),
        }
    }

    /// The listen-and-spawn loop; one task per intercepted flow.
    pub async fn serve(self, listener: TcpListener) -> std::io::Result<()> {
        loop {
            let (stream, _peer) = listener.accept().await?;
            let proxy = self.clone();
            tokio::spawn(async move {
                if let Err(err) = proxy.serve_connection(stream).await {
                    eprintln!("MITM: flow ended: {err}");
                }
            });
        }
    }

    /// One intercepted flow, start to finish.
    pub async fn serve_connection(&self, stream: TcpStream) -> std::io::Result<()> {
        let _ = stream.set_nodelay(true);

        let config = self
            .inner
            .certs
            .server_config(self.inner.options.default_host.as_deref());
        let tls = match TlsAcceptor::from(Arc::new(config)).accept(stream).await {
            Ok(tls) => tls,
            Err(err) => {
                self.record(HttpEvent {
                    host: self.default_host(),
                    protocol: PROTOCOL_HTTPS,
                    status: STATUS_HANDSHAKE_FAILED,
                    reason: format!("client_tls: {err}"),
                });
                return Ok(());
            }
        };

        let sni = tls.get_ref().1.server_name().map(str::to_string);
        let upstream = Arc::new(AsyncMutex::new(Upstream::default()));
        let proxy = self.clone();
        let service = service_fn(move |request: Request<Incoming>| {
            handle_request(proxy.clone(), upstream.clone(), sni.clone(), request)
        });
        hyper::server::conn::http1::Builder::new()
            .keep_alive(true)
            .serve_connection(TokioIo::new(tls), service)
            .await
            .map_err(std::io::Error::other)
    }

    /// The events recorded so far (the spike's stand-in for the Go log callbacks).
    pub fn events(&self) -> Vec<HttpEvent> {
        self.inner
            .events
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .clone()
    }

    fn record(&self, event: HttpEvent) {
        self.inner
            .events
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .push(event);
    }

    fn default_host(&self) -> String {
        self.inner.options.default_host.clone().unwrap_or_default()
    }

    async fn connect_upstream(
        &self,
        host: &str,
        port: u16,
    ) -> Result<crate::upstream::UpstreamFacts, BoxError> {
        let address = match self.inner.options.dial_override {
            Some(address) => address,
            None => tokio::net::lookup_host((host, port))
                .await?
                .next()
                .ok_or_else(|| format!("no upstream address for {host}:{port}"))?,
        };
        let tcp = TcpStream::connect(address).await?;
        let _ = tcp.set_nodelay(true);
        self.inner.upstream.connect(host, tcp).await
    }
}

/// One request/response exchange.
async fn handle_request(
    proxy: Proxy,
    upstream: Arc<AsyncMutex<Upstream>>,
    sni: Option<String>,
    mut request: Request<Incoming>,
) -> Result<Response<ResponseBody>, std::convert::Infallible> {
    let (host, port) = target(&request, &sni);
    inject::strip_accept_encoding(request.headers_mut());

    let mut guard = upstream.lock().await;
    let sent = guard.request(&proxy, &host, port, request).await;
    let response = match sent {
        Ok(Sent::Refused(reason)) => {
            proxy.record(HttpEvent {
                host: host.clone(),
                protocol: PROTOCOL_HTTPS,
                status: STATUS_HANDSHAKE_FAILED,
                reason: reason.to_string(),
            });
            bad_gateway(reason)
        }
        Err(err) => {
            proxy.record(HttpEvent {
                host: host.clone(),
                protocol: PROTOCOL_HTTPS,
                status: STATUS_UPSTREAM_FAILED,
                reason: err.to_string(),
            });
            bad_gateway("upstream_failed")
        }
        Ok(Sent::Response(response)) => {
            let link = proxy.inner.options.inject_css.then(|| {
                diting_cosmetic_core::link_tag(&host, diting_cosmetic_core::local::ASSET_HOST)
            });
            let injectable = link.is_some() && inject::is_html(&content_type(&response));
            let response = match link {
                Some(link) if injectable => inject::inject_html(response, &link).await,
                _ => inject::passthrough(response),
            };
            proxy.record(HttpEvent {
                host: host.clone(),
                protocol: PROTOCOL_HTTPS,
                status: STATUS_ALLOWED,
                reason: String::new(),
            });
            response
        }
    };
    Ok(response)
}

/// The upstream connection a client connection is relayed over, reused across keep-alive requests.
#[derive(Default)]
struct Upstream {
    /// `host:port` the live connection belongs to.
    key: Option<String>,
    send: Option<hyper::client::conn::http1::SendRequest<Incoming>>,
    task: Option<JoinHandle<()>>,
}

/// What one attempt produced.
enum Sent {
    Response(Response<Incoming>),
    /// The upstream must not be intercepted (EV certificate or mTLS request).
    Refused(&'static str),
}

impl Upstream {
    async fn request(
        &mut self,
        proxy: &Proxy,
        host: &str,
        port: u16,
        request: Request<Incoming>,
    ) -> Result<Sent, BoxError> {
        let key = format!("{host}:{port}");
        // Reconnect when the live connection is known to be dead (`is_ready() == false`), not when a
        // send failed: nothing has been handed over yet, so the request can still be sent as-is and
        // no body is ever replayed. Go dialled per client connection and never had to decide this.
        let stale = self.send.as_ref().is_some_and(|send| !send.is_ready());
        if self.send.is_none() || stale || self.key.as_deref() != Some(key.as_str()) {
            self.close();
            let facts = proxy.connect_upstream(host, port).await?;
            if facts.client_cert_requested {
                return Ok(Sent::Refused("client-certificate (mTLS) request"));
            }
            if facts.extended_validation {
                return Ok(Sent::Refused("EV certificate"));
            }
            let (send, connection) =
                hyper::client::conn::http1::handshake(TokioIo::new(facts.stream)).await?;
            let task = tokio::spawn(async move {
                if let Err(err) = connection.await {
                    eprintln!("MITM: upstream connection ended: {err}");
                }
            });
            self.send = Some(send);
            self.key = Some(key);
            self.task = Some(task);
        }

        let send = self
            .send
            .as_mut()
            .expect("the connection was just established");
        match send.send_request(request).await {
            Ok(response) => Ok(Sent::Response(response)),
            Err(err) => {
                // Go wrote the request and gave up when the write failed; it never replayed a body.
                self.close();
                Err(Box::new(err))
            }
        }
    }

    fn close(&mut self) {
        self.send = None;
        self.key = None;
        if let Some(task) = self.task.take() {
            task.abort();
        }
    }
}

impl Drop for Upstream {
    fn drop(&mut self) {
        self.close();
    }
}

/// The upstream host and port for a request: absolute-form URI, then `Host`, then the SNI.
fn target(request: &Request<Incoming>, sni: &Option<String>) -> (String, u16) {
    if let Some(authority) = request.uri().authority() {
        return (
            authority.host().to_string(),
            authority.port_u16().unwrap_or(443),
        );
    }
    if let Some(value) = request
        .headers()
        .get(http::header::HOST)
        .and_then(|value| value.to_str().ok())
    {
        return authority_parts(value);
    }
    (sni.clone().unwrap_or_default(), 443)
}

/// Splits a `Host` header into host and port, handling bracketed IPv6 literals.
pub fn authority_parts(authority: &str) -> (String, u16) {
    let authority = authority.trim();
    if let Some(rest) = authority.strip_prefix('[') {
        if let Some((host, tail)) = rest.split_once(']') {
            let port = tail
                .strip_prefix(':')
                .and_then(|port| port.parse().ok())
                .unwrap_or(443);
            return (host.to_string(), port);
        }
        return (authority.to_string(), 443);
    }
    match authority.rsplit_once(':') {
        Some((host, port)) if !host.contains(':') => match port.parse() {
            Ok(port) => (host.to_string(), port),
            Err(_) => (authority.to_string(), 443),
        },
        _ => (authority.to_string(), 443),
    }
}

fn content_type(response: &Response<Incoming>) -> String {
    response
        .headers()
        .get(http::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_string()
}

/// The spike's stand-in for "the relay gave up": a fixed 502 instead of Go's silent close.
fn bad_gateway(reason: &str) -> Response<ResponseBody> {
    let body = http_body_util::Full::new(Bytes::from(format!("DITING relay: {reason}\n")))
        .map_err(|never| match never {})
        .boxed_unsync();
    Response::builder()
        .status(StatusCode::BAD_GATEWAY)
        .header(http::header::CONTENT_TYPE, "text/plain; charset=utf-8")
        .header(http::header::CONNECTION, "close")
        .body(body)
        .expect("the 502 response is well formed")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_headers_split_into_host_and_port() {
        assert_eq!(
            authority_parts("example.com"),
            ("example.com".to_string(), 443)
        );
        assert_eq!(
            authority_parts("example.com:8443"),
            ("example.com".to_string(), 8443)
        );
        assert_eq!(authority_parts("[::1]:8443"), ("::1".to_string(), 8443));
        assert_eq!(authority_parts("[::1]"), ("::1".to_string(), 443));
        assert_eq!(
            authority_parts("example.com:not-a-port"),
            ("example.com:not-a-port".to_string(), 443)
        );
    }
}
