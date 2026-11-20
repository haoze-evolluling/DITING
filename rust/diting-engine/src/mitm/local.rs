use std::convert::Infallible;
use std::sync::Arc;

use bytes::Bytes;
use http::{Request, Response, StatusCode};
use hyper::body::Incoming;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use tokio::io::{AsyncRead, AsyncWrite};

use crate::engine::Engine;
use crate::mitm::http::{full_response, BoxError, Protocol, ResponseBody};
use crate::mitm::settings::MitmSettings;

pub fn is_asset_host(host: &str) -> bool {
    diting_cosmetic_core::is_asset_host(host)
}

pub fn asset_response(
    request: &Request<Incoming>,
    settings: &MitmSettings,
) -> Response<ResponseBody> {
    let path = request.uri().path();
    let host_query =
        query_param(request.uri().query().unwrap_or_default(), "h").unwrap_or_default();
    let rules = settings.cosmetic();
    let response = diting_cosmetic_core::local::respond(
        path,
        &host_query,
        &rules,
        settings.cosmetic_payload_bytes(),
    );
    let headers: Vec<(&str, String)> = response
        .headers
        .iter()
        .map(|(name, value)| (*name, value.clone()))
        .collect();
    full_response(
        StatusCode::from_u16(response.status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
        response.content_type,
        &headers,
        response.body,
    )
}

pub fn blocked_response() -> Response<ResponseBody> {
    full_response(
        StatusCode::FORBIDDEN,
        "text/plain; charset=utf-8",
        &[],
        "Blocked by DITING",
    )
}

pub fn bad_gateway(reason: &str) -> Response<ResponseBody> {
    full_response(
        StatusCode::BAD_GATEWAY,
        "text/plain; charset=utf-8",
        &[("Connection", "close".to_string())],
        format!("DITING relay: {reason}\n"),
    )
}

pub async fn serve_local<C>(client: C, mode: LocalMode) -> Result<(), BoxError>
where
    C: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let mode = Arc::new(mode);
    let service = service_fn(move |request: Request<Incoming>| {
        let mode = Arc::clone(&mode);
        async move { Ok::<Response<ResponseBody>, Infallible>(mode.answer(&request)) }
    });
    hyper::server::conn::http1::Builder::new()
        .keep_alive(true)
        .serve_connection(TokioIo::new(client), service)
        .await
        .map_err(|error| -> BoxError { Box::new(error) })
}

pub enum LocalMode {
    Assets { engine: Arc<Engine> },
    Redirect {
        target: String,
        engine: Arc<Engine>,
        package: String,
        protocol: Protocol,
    },
}

impl LocalMode {
    fn answer(&self, request: &Request<Incoming>) -> Response<ResponseBody> {
        match self {
            LocalMode::Assets { engine } => asset_response(request, engine.mitm_state().settings()),
            LocalMode::Redirect {
                target,
                engine,
                package,
                protocol,
            } => {
                let mut location = format!("https://{target}");
                if let Some(path_and_query) = request.uri().path_and_query() {
                    let uri = path_and_query.as_str();
                    if !uri.is_empty() && uri != "/" {
                        location.push_str(uri);
                    }
                }
                let host = request
                    .headers()
                    .get(http::header::HOST)
                    .and_then(|value| value.to_str().ok())
                    .unwrap_or_default()
                    .to_string();
                engine.mitm_state().settings().log_http(
                    package,
                    &host,
                    protocol.name(),
                    "rewritten",
                    target,
                );
                full_response(
                    StatusCode::FOUND,
                    "text/plain; charset=utf-8",
                    &[
                        ("Location", location),
                        ("Content-Length", "0".to_string()),
                        ("Cache-Control", "no-store".to_string()),
                    ],
                    Bytes::new(),
                )
            }
        }
    }
}

pub fn authority_parts(authority: &str, default_port: u16) -> (String, u16) {
    let authority = authority.trim();
    if let Some(rest) = authority.strip_prefix('[') {
        if let Some((host, tail)) = rest.split_once(']') {
            let port = tail
                .strip_prefix(':')
                .and_then(|port| port.parse().ok())
                .unwrap_or(default_port);
            return (host.to_string(), port);
        }
        return (authority.to_string(), default_port);
    }
    match authority.rsplit_once(':') {
        Some((host, port)) if !host.contains(':') => match port.parse() {
            Ok(port) => (host.to_string(), port),
            Err(_) => (authority.to_string(), default_port),
        },
        _ => (authority.to_string(), default_port),
    }
}

pub fn query_param(query: &str, name: &str) -> Option<String> {
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (key, value) = match pair.split_once('=') {
            Some((key, value)) => (key, value),
            None => (pair, ""),
        };
        if unescape(key).as_deref() == Some(name) {
            return unescape(value);
        }
    }
    None
}

fn unescape(value: &str) -> Option<String> {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                match (hex(bytes[index + 1]), hex(bytes[index + 2])) {
                    (Some(high), Some(low)) => {
                        out.push(high * 16 + low);
                        index += 3;
                    }
                    _ => {
                        out.push(bytes[index]);
                        index += 1;
                    }
                }
            }
            byte => {
                out.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8(out).ok()
}

fn hex(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_headers_split_into_host_and_port() {
        assert_eq!(
            authority_parts("example.test", 443),
            ("example.test".to_string(), 443)
        );
        assert_eq!(
            authority_parts("example.test:8443", 443),
            ("example.test".to_string(), 8443)
        );
        assert_eq!(
            authority_parts("[::1]:8443", 443),
            ("::1".to_string(), 8443)
        );
        assert_eq!(authority_parts("[::1]", 443), ("::1".to_string(), 443));
        assert_eq!(
            authority_parts("example.test:not-a-port", 443),
            ("example.test:not-a-port".to_string(), 443)
        );
    }

    #[test]
    fn the_asset_host_matches_the_kernel_rule() {
        assert!(is_asset_host("local.pwhs.app"));
        assert!(is_asset_host("LOCAL.PWHS.APP:8443"));
        assert!(!is_asset_host("example.test"));
    }

    #[test]
    fn the_h_query_is_decoded_like_go() {
        assert_eq!(
            query_param("h=ads.example.com&x=1", "h").as_deref(),
            Some("ads.example.com")
        );
        assert_eq!(
            query_param("x=1&h=ads%2Eexample.com", "h").as_deref(),
            Some("ads.example.com")
        );
        assert_eq!(query_param("h=a+b", "h").as_deref(), Some("a b"));
        assert_eq!(query_param("", "h"), None);
        assert_eq!(query_param("h=%zz", "h").as_deref(), Some("%zz"));
    }

    #[test]
    fn the_blocked_page_is_the_go_body() {
        let response = blocked_response();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
        assert!(
            response.headers().get("content-length").is_none(),
            "hyper frames the 17-byte body itself"
        );
    }
}
