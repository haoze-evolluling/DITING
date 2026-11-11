//! The HTTP/1.1 relay: hyper replaces `net/http`, and the body streams instead of buffering.
//!
//! `mitm_relay.go` + `mitm_common.go` + `engine_request_filter.go` in Rust. Both halves of the flow
//! are already established when this module runs (the client TLS session and the upstream session),
//! so what is left is the per-request decision chain:
//!
//! ```text
//! 1. local asset host?          → answer from diting-cosmetic-core, no upstream round trip
//! 2. request rule / domain rule → 403 "Blocked by DITING" (diting-request-core + diting-policy-core)
//! 3. Accept: text/html?         → drop Accept-Encoding so the page arrives uncompressed
//! 4. forward to the upstream    → hyper client conn, same `Incoming` body, no buffering
//! 5. text/html response?        → splice the cosmetic <link> in while it streams (inject.rs)
//! ```
//!
//! # Deliberate differences from Go
//!
//! * **keep-alive survives injection.** Go forced `Connection: close` because `net/http` cannot chunk
//!   a response marked `Uncompressed`; hyper frames the injected body itself, so the connection stays
//!   usable. The hop-by-hop headers Go re-framed by hand are stripped here and emitted by hyper.
//! * **the client's request line is rebuilt in origin-form** (`req.Write` did the same): a browser
//!   never sends absolute-form to a TLS origin, but a client that does must still be relayed.
//! * **WebSocket upgrades are not relayed.** `hyper::upgrade` needs an explicit `on_upgrade` splice;
//!   it is recorded as a stage 4b gap rather than half-implemented. An upgrade request is forwarded as
//!   an ordinary HTTP request and its response is relayed as-is.

use std::convert::Infallible;
use std::sync::Arc;

use bytes::Bytes;
use http::{Request, Response, StatusCode, Uri};
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::Mutex;

use crate::engine::Engine;
use crate::mitm::inject;
use crate::mitm::local;

/// Every error the relay can produce: hyper, rustls, io and the hand-written messages.
pub type BoxError = Box<dyn std::error::Error + Send + Sync>;
/// The one response body type: passthrough, injected or a generated page.
pub type ResponseBody = http_body_util::combinators::UnsyncBoxBody<Bytes, BoxError>;

/// The protocol label the HTTP log uses.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Protocol {
    Https,
    Http,
}

impl Protocol {
    /// `logHTTPEvent`'s `protocol` column.
    pub fn name(self) -> &'static str {
        match self {
            Protocol::Https => "HTTPS",
            Protocol::Http => "HTTP/1.1",
        }
    }

    /// The scheme the request rules match on.
    pub fn scheme(self) -> &'static str {
        match self {
            Protocol::Https => "https",
            Protocol::Http => "http",
        }
    }

    /// The port a `Host` header without one implies.
    pub fn default_port(self) -> u16 {
        match self {
            Protocol::Https => 443,
            Protocol::Http => 80,
        }
    }

    pub fn is_https(self) -> bool {
        matches!(self, Protocol::Https)
    }
}

/// One intercepted request/response relay over two established byte streams.
pub struct Relay {
    engine: Arc<Engine>,
    host: String,
    package: String,
    protocol: Protocol,
}

impl Relay {
    pub fn new(
        engine: Arc<Engine>,
        host: impl Into<String>,
        protocol: Protocol,
        package: impl Into<String>,
    ) -> Relay {
        Relay {
            engine,
            host: host.into(),
            package: package.into(),
            protocol,
        }
    }

    /// Runs the HTTP/1.1 relay until either side goes away.
    pub async fn serve<C, U>(self, client: C, upstream: U) -> Result<(), BoxError>
    where
        C: AsyncRead + AsyncWrite + Unpin + Send + 'static,
        U: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let (send, connection) = hyper::client::conn::http1::handshake(TokioIo::new(upstream))
            .await
            .map_err(|error| -> BoxError { Box::new(error) })?;
        let upstream = Arc::new(Mutex::new(send));
        tokio::spawn(async move {
            // The driver ends when the upstream closes; a failure is that same event.
            let _ = connection.await;
        });

        let relay = Arc::new(self);
        let service = service_fn(move |request: Request<Incoming>| {
            let relay = Arc::clone(&relay);
            let upstream = Arc::clone(&upstream);
            async move {
                let response = relay.handle(request, upstream).await;
                Ok::<Response<ResponseBody>, Infallible>(response)
            }
        });
        hyper::server::conn::http1::Builder::new()
            .keep_alive(true)
            .serve_connection(TokioIo::new(client), service)
            .await
            .map_err(|error| -> BoxError { Box::new(error) })
    }

    /// One request: the local asset check, the two rule families, then the upstream exchange.
    async fn handle(
        &self,
        mut request: Request<Incoming>,
        upstream: Arc<Mutex<hyper::client::conn::http1::SendRequest<Incoming>>>,
    ) -> Response<ResponseBody> {
        let (host, _) = target(&request, &self.host, self.protocol.default_port());
        inject::strip_accept_encoding(request.headers_mut());

        // `IsLocalAssetHost(reqHost)` inside `relayHTTPFlow`: a page can ask for the stylesheet under
        // a different authority than the flow's, and that request never leaves the device.
        if local::is_asset_host(&host) {
            return local::asset_response(&request, self.engine.mitm_state().settings());
        }

        if let Some(rule) = self.blocked_by(&host, &request) {
            self.log(&host, "blocked", &rule);
            return local::blocked_response();
        }

        let request = match normalize_request(request, &host) {
            Ok(request) => request,
            Err(_) => return local::bad_gateway("invalid request target"),
        };
        let forwarded = match upstream.lock().await.send_request(request).await {
            Ok(response) => response,
            Err(error) => {
                self.log(&host, "error", "upstream_write_failed");
                return local::bad_gateway(&error.to_string());
            }
        };
        let response = self.rewrite_response(forwarded, &host).await;
        self.log(&host, "allowed", "");
        response
    }

    /// The request-rule match first, then the domain rules (`requestFilterDecision`).
    fn blocked_by(&self, host: &str, request: &Request<Incoming>) -> Option<String> {
        let settings = self.engine.mitm_state().settings();
        let decision =
            settings.request_decision(self.protocol.scheme(), host, request.uri().path());
        let domain_host = match decision {
            Some(decision) if decision.matched => {
                return decision.blocked.then_some(decision.pattern);
            }
            Some(decision) => decision.domain_host,
            None => host.to_string(),
        };
        domain_blocked(&self.engine, &domain_host, &self.package)
    }

    /// A page worth rewriting gets the `<link>` spliced in; everything else is passed through.
    async fn rewrite_response(
        &self,
        upstream: Response<Incoming>,
        host: &str,
    ) -> Response<ResponseBody> {
        let settings = self.engine.mitm_state().settings();
        if settings.cosmetic_rules_empty() || !is_html(&upstream) {
            return inject::passthrough(upstream);
        }
        let link = diting_cosmetic_core::link_tag(host, diting_cosmetic_core::local::ASSET_HOST);
        inject::inject_html(upstream, &link).await
    }

    /// `logHTTPEvent`, through the same sink the rest of the MITM path uses.
    fn log(&self, authority: &str, outcome: &str, rule: &str) {
        self.engine.mitm_state().settings().log_http(
            &self.package,
            authority,
            self.protocol.name(),
            outcome,
            rule,
        );
    }
}

fn is_html(response: &Response<Incoming>) -> bool {
    response
        .headers()
        .get(http::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .is_some_and(inject::is_html)
}

/// `checkDomainBlockedAndReason`: an active snapshot, a non-empty host, qtype 0.
pub fn domain_blocked(engine: &Engine, host: &str, package: &str) -> Option<String> {
    let host = diting_go_compat::text::go_lower(diting_go_compat::text::go_trim_space(host));
    if host.is_empty() || !engine.policy().is_active() {
        return None;
    }
    let verdict = engine.policy().evaluate(&host, package, 0)?;
    if !verdict.blocked {
        return None;
    }
    Some(if verdict.reason.is_empty() {
        "domain_rule".to_string()
    } else {
        verdict.reason
    })
}

/// The upstream host and port for a request: absolute-form URI, then `Host`, then the flow host.
pub fn target(request: &Request<Incoming>, flow_host: &str, default_port: u16) -> (String, u16) {
    if let Some(authority) = request.uri().authority() {
        return (
            authority.host().to_string(),
            authority.port_u16().unwrap_or(default_port),
        );
    }
    if let Some(value) = request
        .headers()
        .get(http::header::HOST)
        .and_then(|value| value.to_str().ok())
    {
        return local::authority_parts(value, default_port);
    }
    (flow_host.to_string(), default_port)
}

/// `req.Write(serverConn)`: origin-form request line, no hop-by-hop headers, a `Host` header.
pub fn normalize_request(
    request: Request<Incoming>,
    host: &str,
) -> Result<Request<Incoming>, String> {
    let target = match request.uri().path_and_query() {
        Some(path_and_query) => path_and_query.as_str().to_string(),
        None => "/".to_string(),
    };
    let (mut parts, body) = request.into_parts();
    parts.uri = Uri::try_from(&target).map_err(|error| format!("request target: {error}"))?;
    strip_hop_by_hop(&mut parts.headers);
    if !parts.headers.contains_key(http::header::HOST) {
        if let Ok(value) = http::header::HeaderValue::from_str(host) {
            parts.headers.insert(http::header::HOST, value);
        }
    }
    Ok(Request::from_parts(parts, body))
}

/// Headers hyper frames itself; forwarding them would double-frame the message.
pub fn strip_hop_by_hop(headers: &mut http::HeaderMap) {
    for name in [
        "connection",
        "proxy-connection",
        "keep-alive",
        "transfer-encoding",
        "upgrade",
    ] {
        headers.remove(name);
    }
}

/// A `Full` body boxed into the relay's one body type.
pub fn full_response(
    status: StatusCode,
    content_type: &str,
    headers: &[(&str, String)],
    body: impl Into<Bytes>,
) -> Response<ResponseBody> {
    let boxed = Full::new(body.into())
        .map_err(|never| match never {})
        .boxed_unsync();
    let mut builder = Response::builder()
        .status(status)
        .header(http::header::CONTENT_TYPE, content_type);
    for (name, value) in headers {
        builder = builder.header(*name, value);
    }
    builder.body(boxed).expect("the response is well formed")
}

#[cfg(test)]
mod tests {
    use super::*;
    use http::HeaderMap;

    #[test]
    fn hop_by_hop_headers_are_dropped() {
        let mut headers = HeaderMap::new();
        headers.insert("connection", "keep-alive".parse().unwrap());
        headers.insert("transfer-encoding", "chunked".parse().unwrap());
        headers.insert("upgrade", "websocket".parse().unwrap());
        headers.insert(http::header::ACCEPT, "text/html".parse().unwrap());
        strip_hop_by_hop(&mut headers);
        assert!(headers.get("connection").is_none());
        assert!(headers.get("transfer-encoding").is_none());
        assert!(headers.get("upgrade").is_none());
        assert_eq!(headers.get(http::header::ACCEPT).unwrap(), "text/html");
    }

    #[test]
    fn the_protocol_labels_match_the_go_columns() {
        assert_eq!(Protocol::Https.name(), "HTTPS");
        assert_eq!(Protocol::Http.name(), "HTTP/1.1");
        assert_eq!(Protocol::Https.scheme(), "https");
        assert_eq!(Protocol::Http.scheme(), "http");
        assert_eq!(Protocol::Http.default_port(), 80);
    }

    #[test]
    fn a_full_response_carries_its_headers() {
        let response = full_response(
            StatusCode::FOUND,
            "text/plain",
            &[("Location", "https://example.test/".to_string())],
            "x",
        );
        assert_eq!(response.status(), StatusCode::FOUND);
        assert_eq!(
            response.headers().get("location").unwrap(),
            "https://example.test/"
        );
    }
}
