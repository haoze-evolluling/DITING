//! DNS over HTTPS (RFC 8484): a POST of `application/dns-message` over the pooled HTTP client.
//!
//! `resolver_doh.go` used `net/http` with `ForceAttemptHTTP2`, idle-connection limits, a 90 s idle
//! window and a five-second client timeout, protected sockets for the dial, a bootstrap override for
//! the hostname, one retry when the transport failed with `EOF` (an HTTP/2 connection the server had
//! already closed), a 403 read as "rate limited" and any other status as an error.
//!
//! Here:
//!
//! * the pool is `hyper-util`'s legacy client — the same shape as `http.Transport`'s pool, with an
//!   idle window and a per-host cap. ALPN decides the protocol (`h2` first, `http/1.1` second), so a
//!   provider that only speaks HTTP/2 is not a special case;
//! * the dial is a [`DohConnector`]: bootstrap-resolved address, `rustls` with the platform roots,
//!   then the ALPN result is handed to the pool so it can key the connection as HTTP/2 or HTTP/1.1;
//! * the status table (`200` / `403` / other) and the one-shot `EOF` retry rule are the kernel's
//!   ([`diting_upstream_core::doh`]), including the fact that the retry matches the *text* `EOF`:
//!   `errors.Is(err, io.EOF)` would miss the wrapped `unexpected EOF` and change which failures retry.
//!
//! `http.Transport.MaxIdleConns` (5, global) has no counterpart — the hyper pool is per host, and
//! with `MaxIdleConnsPerHost = 2` a global cap of 5 can only bind with three or more DoH providers
//! configured; the per-host cap is the one that decides reuse in practice.

use std::fmt;
use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;

use bytes::Bytes;
use diting_upstream_core::doh::{should_retry, status_kind, StatusKind};
use diting_upstream_core::tuning::TUNING;
use http::{Method, Request, Uri};
use http_body_util::{BodyExt, Full};
use hyper_util::client::legacy::connect::{Connected, Connection};
use hyper_util::client::legacy::Client;
use hyper_util::rt::{TokioExecutor, TokioIo};
use rustls::pki_types::ServerName;
use rustls::ClientConfig;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;
use tower_service::Service;

use crate::resolver::dial::Dialer;
use crate::resolver::trust::UpstreamTrust;

/// `application/dns-message`, the only media type RFC 8484 defines.
pub const DNS_MESSAGE: &str = "application/dns-message";

/// The DoH transport: one pooled HTTP client per resolver.
pub struct DohClient {
    client: Client<DohConnector, Full<Bytes>>,
    /// Set once a response advertises an HTTP/3 endpoint (`Alt-Svc: h3=…`). N7's H3 upgrade and its
    /// fallback consult this instead of re-parsing every response.
    doh3_advertised: std::sync::atomic::AtomicBool,
}

impl DohClient {
    pub fn new(trust: Arc<UpstreamTrust>, dialer: Dialer) -> Self {
        let connector = DohConnector {
            tls: trust.client_config(&crate::resolver::trust::DOH_ALPN),
            dialer,
        };
        // `buildDoHClient`'s pool settings, in `hyper-util` terms.
        let client = Client::builder(TokioExecutor::new())
            .pool_idle_timeout(Duration::from_nanos(
                TUNING.doh_idle_conn_timeout_ns.max(1) as u64
            ))
            .pool_max_idle_per_host(TUNING.doh_max_idle_conns_per_host.max(1) as usize)
            .build(connector);
        Self {
            client,
            doh3_advertised: std::sync::atomic::AtomicBool::new(false),
        }
    }

    /// Whether a DoH server has advertised an HTTP/3 endpoint. The resolver uses this as N7's
    /// negotiation signal; the H3 attempt itself is gated behind the `h3` transport.
    pub fn doh3_ready(&self) -> bool {
        self.doh3_advertised
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    /// `queryDoHContext`: the request, the one-shot `EOF` retry, the status table and the body.
    pub async fn query(&self, uri: &Uri, query: &[u8]) -> Result<Vec<u8>, String> {
        let budget = Duration::from_nanos(TUNING.query_timeout_doh_ns.max(1) as u64);
        let retry_delay = Duration::from_nanos(TUNING.doh_retry_delay_ns.max(1) as u64);

        let mut response = None;
        for attempt in 1..=2u32 {
            let request = match build_request(uri, query) {
                Ok(request) => request,
                Err(error) => return Err(error),
            };
            match tokio::time::timeout(budget, self.client.request(request)).await {
                Ok(Ok(answer)) => {
                    response = Some(answer);
                    break;
                }
                Ok(Err(error)) => {
                    let text = error.to_string();
                    if should_retry(attempt, &text) {
                        tokio::time::sleep(retry_delay).await;
                        continue;
                    }
                    return Err(format!("DoH request failed: {text}"));
                }
                Err(_) => return Err("DoH request failed: timed out".to_string()),
            }
        }
        let Some(response) = response else {
            return Err("DoH request failed: no response".to_string());
        };

        match status_kind(response.status().as_u16() as i32) {
            StatusKind::Ok => {}
            StatusKind::RateLimited => return Err("DoH rate limited (403)".to_string()),
            StatusKind::Other => return Err(format!("DoH status {}", response.status().as_u16())),
        }

        // N7 negotiation: remember an HTTP/3 advertisement for the next query.
        if let Some(value) = response
            .headers()
            .get("alt-svc")
            .and_then(|value| value.to_str().ok())
        {
            if diting_upstream_core::alt_svc::parse_alt_svc(value).is_some() {
                self.doh3_advertised
                    .store(true, std::sync::atomic::Ordering::Relaxed);
            }
        }

        let body = response
            .into_body()
            .collect()
            .await
            .map_err(|error| format!("DoH read: {error}"))?
            .to_bytes();
        // `io.LimitReader(resp.Body, maxReadBytes)`.
        let limit = TUNING.max_read_bytes.max(1) as usize;
        let body = if body.len() > limit {
            &body[..limit]
        } else {
            &body[..]
        };
        Ok(body.to_vec())
    }
}

fn build_request(uri: &Uri, query: &[u8]) -> Result<Request<Full<Bytes>>, String> {
    Request::builder()
        .method(Method::POST)
        .uri(uri.clone())
        .header(http::header::CONTENT_TYPE, DNS_MESSAGE)
        .header(http::header::ACCEPT, DNS_MESSAGE)
        .body(Full::new(Bytes::copy_from_slice(query)))
        .map_err(|error| format!("DoH request: {error}"))
}

/// The connector `buildDoHClient`'s `DialContext` was: bootstrap-resolved TCP, then TLS.
#[derive(Clone)]
struct DohConnector {
    tls: Arc<ClientConfig>,
    dialer: Dialer,
}

impl Service<Uri> for DohConnector {
    type Response = TokioIo<TlsIo>;
    type Error = io::Error;
    type Future =
        Pin<Box<dyn std::future::Future<Output = Result<Self::Response, io::Error>> + Send>>;

    fn poll_ready(&mut self, _cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        Poll::Ready(Ok(()))
    }

    fn call(&mut self, uri: Uri) -> Self::Future {
        let tls = Arc::clone(&self.tls);
        let dialer = self.dialer.clone();
        Box::pin(async move {
            let host = uri
                .host()
                .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "DoH URL has no host"))?
                .to_string();
            let port = uri.port_u16().unwrap_or(443);
            let tcp = dialer
                .connect_tcp(&host, &port.to_string())
                .await
                .map_err(io::Error::other)?;
            let name = ServerName::try_from(host)
                .map_err(|error| io::Error::new(io::ErrorKind::InvalidInput, error))?;
            let stream = TlsConnector::from(tls).connect(name, tcp).await?;
            let h2 = stream.get_ref().1.alpn_protocol() == Some(b"h2");
            Ok(TokioIo::new(TlsIo { stream, h2 }))
        })
    }
}

/// The TLS stream plus the ALPN verdict the pool keys on.
struct TlsIo {
    stream: TlsStream<TcpStream>,
    h2: bool,
}

impl AsyncRead for TlsIo {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        Pin::new(&mut self.stream).poll_read(cx, buf)
    }
}

impl AsyncWrite for TlsIo {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.stream).poll_write(cx, buf)
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.stream).poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.stream).poll_shutdown(cx)
    }
}

impl Connection for TlsIo {
    fn connected(&self) -> Connected {
        let connected = Connected::new();
        if self.h2 {
            connected.negotiated_h2()
        } else {
            connected
        }
    }
}

impl fmt::Debug for TlsIo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("TlsIo")
            .field("h2", &self.h2)
            .finish_non_exhaustive()
    }
}
