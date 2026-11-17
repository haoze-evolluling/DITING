//! DNS over HTTPS (RFC 8484).
//!
//! HTTP/2 and HTTP/1.1 are negotiated by hyper's auto connection builder over a rustls stream.
//! Only `POST` with `application/dns-message` and `GET` with a base64url `?dns=` parameter are
//! accepted, on the configured path and on `<path>/<ClientID>`. The HTTP status carries the
//! outcome: 400 for a malformed request, 404 for a foreign path, 405 for another method, 413 for
//! an oversized body.

use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use diting_desktop_core::cert::CertManager;
use http_body_util::{BodyExt, Full, LengthLimitError};
use hyper::body::{Body, Bytes, Incoming};
use hyper::header::{CACHE_CONTROL, CONTENT_TYPE, HOST};
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode, Uri};
use hyper_util::rt::{TokioExecutor, TokioIo};
use hyper_util::server::conn::auto;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tokio_rustls::TlsAcceptor;

use super::client_id::{
    client_id_from_server_name, normalize_doh_path, path_segment_after, validate_client_id,
};
use super::realip::real_client_ip;
use super::socket_address;
use super::EncryptedConfig;
use crate::context::Transport;
use crate::server::DnsServer;

const DOH_CONTENT_TYPE: &str = "application/dns-message";
const DOH_GET_PARAM: &str = "dns";
/// DNS itself is capped at 64 KiB; the HTTP body must not be able to exceed that.
const MAX_BODY: usize = 65535;
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);

pub(super) async fn start(
    server: Arc<DnsServer>,
    cert: &CertManager,
    config: Arc<EncryptedConfig>,
    shutdown: watch::Receiver<bool>,
) -> Result<(String, JoinHandle<()>), String> {
    let tls = cert.tls_config(vec![b"h2".to_vec(), b"http/1.1".to_vec()])?;
    let address = socket_address(&config.listen_address, config.doh_port)?;
    let listener = TcpListener::bind(&address)
        .await
        .map_err(|error| format!("绑定 DoH {address} 失败: {error}"))?;
    let local = listener
        .local_addr()
        .map_err(|error| format!("读取 DoH 监听地址失败: {error}"))?
        .to_string();

    let acceptor = TlsAcceptor::from(tls);
    let mut shutdown = shutdown;
    let handle = tokio::spawn(async move {
        loop {
            tokio::select! {
                changed = shutdown.changed() => {
                    if changed.is_err() || *shutdown.borrow() {
                        break;
                    }
                }
                accepted = listener.accept() => {
                    match accepted {
                        Ok((stream, peer)) => {
                            let acceptor = acceptor.clone();
                            let server = server.clone();
                            let config = config.clone();
                            let shutdown = shutdown.clone();
                            tokio::spawn(async move {
                                serve_connection(
                                    stream, peer, acceptor, server, config, shutdown,
                                )
                                .await;
                            });
                        }
                        Err(error) => {
                            eprintln!("[加密DNS] DoH 接受连接失败: {error}");
                            tokio::time::sleep(Duration::from_millis(50)).await;
                        }
                    }
                }
            }
        }
    });
    Ok((local, handle))
}

async fn serve_connection(
    stream: TcpStream,
    peer: SocketAddr,
    acceptor: TlsAcceptor,
    server: Arc<DnsServer>,
    config: Arc<EncryptedConfig>,
    mut shutdown: watch::Receiver<bool>,
) {
    let stream = match tokio::time::timeout(HANDSHAKE_TIMEOUT, acceptor.accept(stream)).await {
        Ok(Ok(stream)) => stream,
        Ok(Err(error)) => {
            eprintln!("[加密DNS] DoH 握手失败: {error}");
            return;
        }
        Err(_) => {
            eprintln!("[加密DNS] DoH 握手超时");
            return;
        }
    };

    let service = service_fn(move |request: Request<Incoming>| {
        let server = server.clone();
        let config = config.clone();
        async move { Ok::<_, Infallible>(handle_request(&server, &config, peer, request).await) }
    });
    let builder = auto::Builder::new(TokioExecutor::new());
    let connection = builder.serve_connection(TokioIo::new(stream), service);
    tokio::pin!(connection);
    tokio::select! {
        _ = shutdown.changed() => {}
        result = &mut connection => {
            if let Err(error) = result {
                eprintln!("[加密DNS] DoH 连接异常: {error}");
            }
        }
    }
}

#[derive(Debug)]
enum PathMatch {
    Base,
    Client(String),
    NotFound,
}

fn classify_path(path: &str, base: &str) -> PathMatch {
    if path == base {
        return PathMatch::Base;
    }
    match path_segment_after(path, base) {
        Some(segment) => PathMatch::Client(segment.to_string()),
        None => PathMatch::NotFound,
    }
}

/// Handles one DoH request. Generic over the body so unit tests can drive it without a socket.
pub(crate) async fn handle_request<B>(
    server: &DnsServer,
    config: &EncryptedConfig,
    peer: SocketAddr,
    request: Request<B>,
) -> Response<Full<Bytes>>
where
    B: Body<Data = Bytes> + Send + 'static,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let method = request.method().clone();
    let base = normalize_doh_path(&config.doh_path);
    let path_client = match classify_path(request.uri().path(), &base) {
        PathMatch::Base => None,
        PathMatch::Client(segment) => match validate_client_id(&segment) {
            Some(client_id) => Some(client_id),
            None => return error_response(StatusCode::BAD_REQUEST, "ClientID 非法"),
        },
        PathMatch::NotFound => return error_response(StatusCode::NOT_FOUND, "未找到"),
    };
    if method != Method::GET && method != Method::POST {
        return error_response(StatusCode::METHOD_NOT_ALLOWED, "不支持的请求方法");
    }

    let host = request_host(request.uri(), request.headers());
    let client_ip = if config.reverse_proxy.enabled {
        real_client_ip(
            peer.ip(),
            request.headers(),
            &config.reverse_proxy.trusted_sources,
            &config.reverse_proxy.client_ip_header,
        )
    } else {
        peer.ip()
    };

    let query = if method == Method::GET {
        let Some(value) = request
            .uri()
            .query()
            .and_then(|query| query_param(query, DOH_GET_PARAM))
        else {
            return error_response(StatusCode::BAD_REQUEST, "缺少 dns 参数");
        };
        match URL_SAFE_NO_PAD.decode(value) {
            Ok(decoded) if !decoded.is_empty() && decoded.len() <= MAX_BODY => decoded,
            _ => return error_response(StatusCode::BAD_REQUEST, "dns 参数不是合法的 base64url"),
        }
    } else {
        let content_type = request
            .headers()
            .get(CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .unwrap_or("");
        if !is_doh_content_type(content_type) {
            return error_response(
                StatusCode::BAD_REQUEST,
                "Content-Type 必须是 application/dns-message",
            );
        }
        match read_body(request.into_body()).await {
            Ok(body) if !body.is_empty() => body,
            Ok(_) => return error_response(StatusCode::BAD_REQUEST, "请求正文为空"),
            Err(status) => return error_response(status, "请求正文不可用"),
        }
    };

    if !is_standard_query(&query) {
        return error_response(StatusCode::BAD_REQUEST, "只接受单题标准查询报文");
    }

    let client_id = path_client.or_else(|| client_id_from_server_name(&host, &config.server_name));
    let client = SocketAddr::new(client_ip, peer.port());
    let response = server
        .handle_with_identity(query, Some(client), Transport::Doh, client_id)
        .await;
    if response.is_empty() {
        return error_response(StatusCode::INTERNAL_SERVER_ERROR, "解析失败");
    }

    Response::builder()
        .status(StatusCode::OK)
        .header(CONTENT_TYPE, DOH_CONTENT_TYPE)
        .header(CACHE_CONTROL, "no-store")
        .body(Full::new(Bytes::from(response)))
        .unwrap_or_else(|_| error_response(StatusCode::INTERNAL_SERVER_ERROR, "应答无法封装"))
}

async fn read_body<B>(body: B) -> Result<Vec<u8>, StatusCode>
where
    B: Body<Data = Bytes> + Send + 'static,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let limited = http_body_util::Limited::new(body, MAX_BODY + 1);
    match limited.collect().await {
        Ok(collected) => {
            let bytes = collected.to_bytes();
            if bytes.len() > MAX_BODY {
                Err(StatusCode::PAYLOAD_TOO_LARGE)
            } else {
                Ok(bytes.to_vec())
            }
        }
        Err(error) if error.downcast_ref::<LengthLimitError>().is_some() => {
            Err(StatusCode::PAYLOAD_TOO_LARGE)
        }
        Err(_) => Err(StatusCode::BAD_REQUEST),
    }
}

fn query_param<'a>(query: &'a str, name: &str) -> Option<&'a str> {
    query.split('&').find_map(|pair| {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        (key == name).then_some(value)
    })
}

fn is_doh_content_type(value: &str) -> bool {
    value
        .split(';')
        .next()
        .is_some_and(|base| base.trim().eq_ignore_ascii_case(DOH_CONTENT_TYPE))
}

fn is_standard_query(wire: &[u8]) -> bool {
    let Some(header) = diting_dns_wire::parse_header(wire) else {
        return false;
    };
    let opcode = (header.flags >> 11) & 0x0f;
    !header.is_response()
        && opcode == 0
        && header.question_count == 1
        && diting_dns_wire::parse_question(wire, 12, false).is_some()
}

/// The request host, without port or trailing root dot. HTTP/2 puts it in the authority, HTTP/1.1
/// in the `Host` header.
fn request_host(uri: &Uri, headers: &hyper::HeaderMap) -> String {
    let host = uri
        .host()
        .map(|host| host.to_string())
        .or_else(|| {
            headers
                .get(HOST)
                .and_then(|value| value.to_str().ok())
                .map(|host| host.to_string())
        })
        .unwrap_or_default();
    strip_port(host.trim())
}

fn strip_port(host: &str) -> String {
    let host = host.trim();
    let without_port = if let Some(inner) = host.strip_prefix('[') {
        inner.split(']').next().unwrap_or(inner)
    } else if let Some((name, port)) = host.rsplit_once(':') {
        if !name.contains(':') && !port.is_empty() && port.bytes().all(|byte| byte.is_ascii_digit())
        {
            name
        } else {
            host
        }
    } else {
        host
    };
    without_port
        .strip_suffix('.')
        .unwrap_or(without_port)
        .to_string()
}

fn error_response(status: StatusCode, message: &str) -> Response<Full<Bytes>> {
    Response::builder()
        .status(status)
        .header(CONTENT_TYPE, "text/plain; charset=utf-8")
        .body(Full::new(Bytes::from(message.to_string())))
        .unwrap_or_else(|_| Response::new(Full::new(Bytes::new())))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::IpAddr;

    use async_trait::async_trait;
    use diting_dns_wire::build::MessageBuilder;

    use crate::context::DnsContext;
    use crate::pipeline::{Pipeline, Stage, StageResult};
    use crate::server::ServerConfig;

    struct Answer;

    #[async_trait]
    impl Stage for Answer {
        fn name(&self) -> &'static str {
            "forward"
        }

        async fn before(&self, ctx: &mut DnsContext) -> StageResult {
            ctx.reply_with_rcode(0);
            StageResult::Stop
        }
    }

    fn server() -> DnsServer {
        let pipeline = Arc::new(Pipeline::new(vec![Arc::new(Answer)]));
        DnsServer::new(ServerConfig::default(), pipeline)
    }

    fn config() -> EncryptedConfig {
        EncryptedConfig {
            listen_address: "127.0.0.1".to_string(),
            doh_enabled: true,
            doh_path: "/dns-query".to_string(),
            server_name: "dns.lan".to_string(),
            ..EncryptedConfig::default()
        }
    }

    fn query() -> Vec<u8> {
        MessageBuilder::query("example.com", 1, 1).finish().unwrap()
    }

    fn peer() -> SocketAddr {
        SocketAddr::new(IpAddr::from([127, 0, 0, 1]), 53000)
    }

    async fn post(uri: &str, content_type: &str, body: Vec<u8>) -> Response<Full<Bytes>> {
        let request = Request::builder()
            .method(Method::POST)
            .uri(uri)
            .header(CONTENT_TYPE, content_type)
            .body(Full::new(Bytes::from(body)))
            .unwrap();
        handle_request(&server(), &config(), peer(), request).await
    }

    async fn get(uri: &str) -> Response<Full<Bytes>> {
        let request = Request::builder()
            .method(Method::GET)
            .uri(uri)
            .body(Full::new(Bytes::new()))
            .unwrap();
        handle_request(&server(), &config(), peer(), request).await
    }

    #[tokio::test]
    async fn post_and_get_are_accepted() {
        let response = post("https://dns.lan/dns-query", DOH_CONTENT_TYPE, query()).await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response
                .headers()
                .get(CONTENT_TYPE)
                .and_then(|value| value.to_str().ok()),
            Some(DOH_CONTENT_TYPE)
        );
        let encoded = URL_SAFE_NO_PAD.encode(query());
        let response = get(&format!("https://dns.lan/dns-query?dns={encoded}")).await;
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn oversized_body_is_413() {
        let response = post(
            "https://dns.lan/dns-query",
            DOH_CONTENT_TYPE,
            vec![0u8; MAX_BODY + 1],
        )
        .await;
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    }

    #[tokio::test]
    async fn wrong_method_and_content_type_are_rejected() {
        let request = Request::builder()
            .method(Method::PUT)
            .uri("https://dns.lan/dns-query")
            .body(Full::new(Bytes::new()))
            .unwrap();
        let response = handle_request(&server(), &config(), peer(), request).await;
        assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);

        let response = post("https://dns.lan/dns-query", "text/plain", query()).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn paths_carry_the_client_id_and_unknown_paths_are_404() {
        let encoded = URL_SAFE_NO_PAD.encode(query());
        let response = get(&format!("https://dns.lan/dns-query/laptop?dns={encoded}")).await;
        assert_eq!(response.status(), StatusCode::OK);

        let response = get(&format!("https://dns.lan/dns-query/bad!?dns={encoded}")).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);

        let response = get(&format!("https://dns.lan/other?dns={encoded}")).await;
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn malformed_queries_and_get_parameters_are_400() {
        let mut two = query();
        two[4] = 0;
        two[5] = 2;
        let response = post("https://dns.lan/dns-query", DOH_CONTENT_TYPE, two).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);

        let response = get("https://dns.lan/dns-query").await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);

        let response = get("https://dns.lan/dns-query?dns=not*base64").await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[test]
    fn host_with_port_is_reduced_to_the_name() {
        assert_eq!(strip_port("dns.lan:443"), "dns.lan");
        assert_eq!(strip_port("dns.lan."), "dns.lan");
        assert_eq!(strip_port("[::1]:443"), "::1");
        assert_eq!(strip_port("::1"), "::1");
    }
}
