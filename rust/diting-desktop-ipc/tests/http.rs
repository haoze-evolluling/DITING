use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use futures_util::StreamExt;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

use diting_desktop_api::config::{store, Config};
use diting_desktop_app::runtime::PlatformHandles;
use diting_desktop_core::querylog::Record;
use diting_desktop_ipc::ws::Event;
use diting_desktop_ipc::{AppRuntime, Server};

fn temp_root(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "diting-ipc-{tag}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0)
    ))
}

fn test_config(root: &Path) -> Config {
    let mut config = Config::default();
    config.ipc.listen_address = "127.0.0.1:0".to_string();
    config.ipc.auth_token = String::new();
    config.dns.udp_addresses = vec!["127.0.0.1:0".to_string()];
    config.dns.tcp_addresses = vec!["127.0.0.1:0".to_string()];
    config.query_log.file_enabled = false;
    config.query_log.data_dir = root.join("querylog").to_string_lossy().into_owned();
    config.filter.data_dir = root.join("filters").to_string_lossy().into_owned();
    config.cache.persist_enabled = false;
    config
}

async fn start(tag: &str, config: Config) -> (Arc<Server>, PathBuf) {
    let root = temp_root(tag);
    std::fs::create_dir_all(&root).unwrap();
    let path = root.join("config.json");
    let runtime = Arc::new(AppRuntime::with_platform(
        config,
        path.clone(),
        PlatformHandles::default(),
    ));
    let server = Arc::new(Server::new(runtime));
    server.start().await.unwrap();
    (server, root)
}

async fn send(addr: std::net::SocketAddr, request: String) -> (u16, String) {
    let mut stream = TcpStream::connect(addr).await.unwrap();
    let _ = stream.write_all(request.as_bytes()).await;
    let mut response = Vec::new();
    let _ = tokio::time::timeout(Duration::from_secs(5), stream.read_to_end(&mut response)).await;
    let text = String::from_utf8_lossy(&response).into_owned();
    let status = text
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|code| code.parse().ok())
        .unwrap_or(0);
    (status, text)
}

fn get(addr: std::net::SocketAddr, path: &str) -> impl std::future::Future<Output = (u16, String)> {
    send(
        addr,
        format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"),
    )
}

#[tokio::test]
async fn health_uses_the_success_envelope() {
    let (server, root) = start("health", test_config(Path::new("."))).await;
    let addr = server.addr().await.unwrap();
    let (status, text) = get(addr, "/api/v1/health").await;
    assert_eq!(status, 200);
    assert!(text.contains("\"success\":true"));
    assert!(text.contains("\"data\":\"ok\""));
    server.shutdown().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn unknown_api_route_is_json_404_and_spa_routes_fall_back() {
    let (server, root) = start("routes", test_config(Path::new("."))).await;
    let addr = server.addr().await.unwrap();

    let (status, text) = get(addr, "/api/v1/does-not-exist").await;
    assert_eq!(status, 404);
    assert!(text.contains("api endpoint not found"));

    let (status, text) = get(addr, "/dashboard/settings").await;
    assert_eq!(status, 200);
    assert!(text.contains("DITING") || text.contains("谛听"));

    let (status, _) = get(addr, "/api/v1/dns/start").await;
    assert_eq!(status, 405);

    server.shutdown().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn configured_token_is_required_but_loopback_stays_trusted_when_empty() {
    let mut config = test_config(Path::new("."));
    config.ipc.auth_token = "secret".to_string();
    let (server, root) = start("auth", config).await;
    let addr = server.addr().await.unwrap();

    let (status, text) = get(addr, "/api/v1/status").await;
    assert_eq!(status, 401);
    assert!(text.contains("unauthorized"));

    let (status, _) = send(
        addr,
        "GET /api/v1/status HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer secret\r\nConnection: close\r\n\r\n"
            .to_string(),
    )
    .await;
    assert_eq!(status, 200);

    server.shutdown().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn loopback_password_reset_returns_a_session_and_replaces_credentials() {
    let mut config = test_config(Path::new("."));
    let (hash, salt) = diting_desktop_ipc::auth::hash_password("secret", "");
    config.web.password_hash = hash;
    config.web.salt = salt;
    let (server, root) = start("reset", config).await;
    let addr = server.addr().await.unwrap();

    let body = r#"{"newPassword":"new-secret"}"#;
    let (status, text) = send(
        addr,
        format!(
            "POST /api/v1/auth/reset-password HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        ),
    )
    .await;
    assert_eq!(status, 200, "{text}");
    assert!(text.contains("\"token\""));
    assert!(server.auth().verify_password("new-secret"));
    assert!(!server.auth().verify_password("secret"));

    server.shutdown().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn query_log_export_returns_csv_and_json_files() {
    let (server, root) = start("queryexport", test_config(Path::new("."))).await;
    let addr = server.addr().await.unwrap();
    server.runtime().querylog.record(Record {
        timestamp: 1_700_000_000_000,
        domain: "example.com".to_string(),
        qtype: "A".to_string(),
        client_ip: "192.168.1.10".to_string(),
        duration_ms: 12.5,
        status: "allowed".to_string(),
        ..Record::default()
    });

    let (status, text) = get(addr, "/api/v1/querylog/export?format=csv").await;
    assert_eq!(status, 200, "{text}");
    let lower = text.to_ascii_lowercase();
    assert!(lower.contains("content-type: text/csv"));
    assert!(lower.contains("content-disposition: attachment; filename=\"diting-querylog-"));
    assert!(lower.contains("x-diting-export-count: 1"));
    assert!(text.contains("example.com"));

    let (status, text) = get(addr, "/api/v1/querylog/export?format=json").await;
    assert_eq!(status, 200, "{text}");
    assert!(text.contains("\"exported\":1"));
    assert!(text.contains("\"entries\""));
    assert!(text.contains("example.com"));

    let (status, text) = get(addr, "/api/v1/querylog/export?format=xml").await;
    assert_eq!(status, 400, "{text}");

    server.shutdown().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn body_cap_rejects_oversized_payloads() {
    let (server, root) = start("body", test_config(Path::new("."))).await;
    let addr = server.addr().await.unwrap();
    let size = diting_desktop_ipc::server::MAX_BODY_BYTES + 1024;
    let mut request = format!(
        "POST /api/v1/dns/hosts/configure HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {size}\r\nConnection: close\r\n\r\n"
    )
    .into_bytes();
    request.extend(std::iter::repeat_n(b' ', size));
    let (status, text) = send(addr, String::from_utf8_lossy(&request).into_owned()).await;
    assert_eq!(status, 400);
    assert!(text.contains("4 MiB"));
    server.shutdown().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn representative_handler_persists_a_temporary_config() {
    let root = temp_root("persist");
    std::fs::create_dir_all(&root).unwrap();
    let path = root.join("config.json");
    let (server, _) = start("persist", test_config(&root)).await;
    let addr = server.addr().await.unwrap();

    let body = r#"{"ttl":123}"#;
    let (status, text) = send(
        addr,
        format!(
            "POST /api/v1/dns/hosts/configure HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        ),
    )
    .await;
    let runtime_path = server.runtime().config_path();
    assert_eq!(status, 200, "{text}");
    let saved = store::load_config(&runtime_path).unwrap();
    assert_eq!(saved.hosts.ttl, 123);

    server.shutdown().await;
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_dir_all(root);
    if let Some(parent) = runtime_path.parent() {
        let _ = std::fs::remove_dir_all(parent);
    }
}

#[tokio::test]
async fn restart_rebinds_to_the_configured_address() {
    let (server, root) = start("webrebind", test_config(Path::new("."))).await;
    let before = server.addr().await.unwrap();

    let probe = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let target = probe.local_addr().unwrap();
    drop(probe);
    server
        .runtime()
        .update_config_in_memory(|config| config.ipc.listen_address = target.to_string());
    let after = server.restart().await.unwrap();
    assert_eq!(after, target);
    assert_ne!(before, after);
    let (status, text) = get(after, "/api/v1/health").await;
    assert_eq!(status, 200, "{text}");

    server.shutdown().await;
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn websocket_handshake_receives_broadcast_events() {
    let (server, root) = start("ws", test_config(Path::new("."))).await;
    let addr = server.addr().await.unwrap();
    let url = format!("ws://{addr}/api/v1/events");
    let (mut socket, _) = tokio_tungstenite::connect_async(url).await.unwrap();

    server.hub().broadcast(&Event::new(
        "query",
        serde_json::json!({"domain": "example.com"}),
    ));

    let message = tokio::time::timeout(Duration::from_secs(2), socket.next())
        .await
        .ok()
        .flatten()
        .expect("websocket message")
        .unwrap();
    let text = message.into_text().unwrap();
    assert!(text.contains("\"type\":\"query\""));
    assert!(text.contains("example.com"));

    server.shutdown().await;
    let _ = std::fs::remove_dir_all(root);
}
