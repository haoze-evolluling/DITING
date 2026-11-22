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

pub type BoxError = Box<dyn std::error::Error + Send + Sync>;
pub type ResponseBody = http_body_util::combinators::UnsyncBoxBody<Bytes, BoxError>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Protocol {
    Https,
    Http,
}

impl Protocol {
    pub fn name(self) -> &'static str {
        match self {
            Protocol::Https => "HTTPS",
            Protocol::Http => "HTTP/1.1",
        }
    }

    pub fn scheme(self) -> &'static str {
        match self {
            Protocol::Https => "https",
            Protocol::Http => "http",
        }
    }

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

    pub async fn serve<C, U>(self, client: C, upstream: U) -> Result<(), BoxError>
    where
        C: AsyncRead + AsyncWrite + Unpin + Send + 'static,
        U: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let (send, connection) = hyper::client::conn::http1::handshake(TokioIo::new(upstream))
            .await
            .map_err(|error| -> BoxError { Box::new(error) })?;
        let upstream = Arc::new(Mutex::new(send));
        let driver = tokio::spawn(async move {
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
        let outcome = hyper::server::conn::http1::Builder::new()
            .keep_alive(true)
            .serve_connection(TokioIo::new(client), service)
            .await
            .map_err(|error| -> BoxError { Box::new(error) });
        driver.abort();
        outcome
    }

    async fn handle(
        &self,
        mut request: Request<Incoming>,
        upstream: Arc<Mutex<hyper::client::conn::http1::SendRequest<Incoming>>>,
    ) -> Response<ResponseBody> {
        let (host, _) = target(&request, &self.host, self.protocol.default_port());
        inject::strip_accept_encoding(request.headers_mut());

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
