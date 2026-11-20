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

pub const DNS_MESSAGE: &str = "application/dns-message";

pub struct DohClient {
    client: Client<DohConnector, Full<Bytes>>,
    doh3_advertised: std::sync::atomic::AtomicBool,
    h3_failures: std::sync::atomic::AtomicU32,
    doh3_port: std::sync::atomic::AtomicU16,
}

const H3_MAX_FAILURES: u32 = 3;

impl DohClient {
    pub fn new(trust: Arc<UpstreamTrust>, dialer: Dialer) -> Self {
        let connector = DohConnector {
            tls: trust.client_config(&crate::resolver::trust::DOH_ALPN),
            dialer,
        };
        let client = Client::builder(TokioExecutor::new())
            .pool_idle_timeout(Duration::from_nanos(
                TUNING.doh_idle_conn_timeout_ns.max(1) as u64
            ))
            .pool_max_idle_per_host(TUNING.doh_max_idle_conns_per_host.max(1) as usize)
            .build(connector);
        Self {
            client,
            doh3_advertised: std::sync::atomic::AtomicBool::new(false),
            h3_failures: std::sync::atomic::AtomicU32::new(0),
            doh3_port: std::sync::atomic::AtomicU16::new(0),
        }
    }

    pub fn doh3_ready(&self) -> bool {
        self.doh3_advertised
            .load(std::sync::atomic::Ordering::Relaxed)
            && self.h3_failures.load(std::sync::atomic::Ordering::Relaxed) < H3_MAX_FAILURES
    }

    pub fn note_h3_success(&self) {
        self.h3_failures
            .store(0, std::sync::atomic::Ordering::Relaxed);
    }

    pub fn note_h3_failure(&self) {
        self.h3_failures
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    }

    pub fn doh3_port(&self) -> Option<u16> {
        match self.doh3_port.load(std::sync::atomic::Ordering::Relaxed) {
            0 => None,
            port => Some(port),
        }
    }

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

        if let Some(value) = response
            .headers()
            .get("alt-svc")
            .and_then(|value| value.to_str().ok())
        {
            if let Some(alt) = diting_upstream_core::alt_svc::parse_alt_svc(value) {
                self.doh3_port
                    .store(alt.port, std::sync::atomic::Ordering::Relaxed);
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
