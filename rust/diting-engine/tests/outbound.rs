//! The outbound transports against fake proxies: SOCKS5, HTTP CONNECT, UDP ASSOCIATE, direct.
//!
//! All peers are the hand-written loopback servers in `tests/support`: they assert what the engine
//! asked for (`targets`) and echo, so the assertions cover both the wire format and the data path.
//! The protector cases are here too: a refused `protect` must fail the proxy dial closed.

mod support;

use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use diting_engine::outbound::{Config, Outbound, Route, StatusDispatcher, StatusSink};
use diting_engine::protect::{Protector, ProtectorHandle};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

fn make(raw: &str, protector: ProtectorHandle) -> Outbound {
    let config = Config::parse(raw).expect("the config parses");
    Outbound::new(config, protector, Arc::new(StatusDispatcher::default()))
}

fn socks5_config(proxy: std::net::SocketAddr) -> String {
    format!(
        r#"{{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":{},"scope":"all"}}"#,
        proxy.port()
    )
}

fn http_config(proxy: std::net::SocketAddr) -> String {
    format!(
        r#"{{"enabled":true,"protocol":"http","host":"127.0.0.1","port":{},"scope":"all"}}"#,
        proxy.port()
    )
}

#[tokio::test]
async fn a_direct_dial_reaches_the_target() {
    let (echo, accepted) = support::proxies::spawn_tcp_echo();
    let outbound = make("", ProtectorHandle::new());
    let mut stream = outbound
        .dial_tcp(Route::Direct, echo)
        .await
        .expect("direct dial");
    stream.write_all(b"hello").await.expect("write");
    let mut buffer = [0u8; 5];
    stream.read_exact(&mut buffer).await.expect("read");
    assert_eq!(&buffer, b"hello");
    assert_eq!(accepted.load(Ordering::Relaxed), 1);
}

#[tokio::test]
async fn socks5_connect_asks_the_proxy_for_the_original_target() {
    let proxy = support::proxies::spawn_socks5_proxy();
    let outbound = make(&socks5_config(proxy.address), ProtectorHandle::new());
    let target: std::net::SocketAddr = "10.20.30.40:443".parse().expect("target");
    let mut stream = outbound
        .dial_tcp(Route::Proxy, target)
        .await
        .expect("socks5 dial");
    stream.write_all(b"ping").await.expect("write");
    let mut buffer = [0u8; 4];
    stream.read_exact(&mut buffer).await.expect("read");
    assert_eq!(&buffer, b"ping");
    assert_eq!(
        proxy.targets.lock().expect("targets").as_slice(),
        &["10.20.30.40:443"]
    );
}

#[tokio::test]
async fn http_connect_tunnels_and_reports_the_status_on_failure() {
    let (proxy, targets) = support::proxies::spawn_http_proxy("200 Connection established");
    let outbound = make(&http_config(proxy), ProtectorHandle::new());
    let target: std::net::SocketAddr = "10.20.30.40:443".parse().expect("target");
    let mut stream = outbound
        .dial_tcp(Route::Proxy, target)
        .await
        .expect("http connect");
    stream.write_all(b"body").await.expect("write");
    let mut buffer = [0u8; 4];
    stream.read_exact(&mut buffer).await.expect("read");
    assert_eq!(&buffer, b"body");
    assert_eq!(
        targets.lock().expect("targets").as_slice(),
        &["10.20.30.40:443"]
    );

    let (forbidden, _) = support::proxies::spawn_http_proxy("403 Forbidden");
    let outbound = make(&http_config(forbidden), ProtectorHandle::new());
    let error = outbound
        .dial_tcp(Route::Proxy, target)
        .await
        .expect_err("403");
    assert_eq!(error, "HTTP proxy returned 403 Forbidden");
}

#[tokio::test]
async fn socks5_udp_associate_relays_framed_datagrams() {
    let proxy = support::proxies::spawn_socks5_proxy();
    let outbound = make(&socks5_config(proxy.address), ProtectorHandle::new());
    let target: std::net::SocketAddr = "10.0.0.1:443".parse().expect("target");
    let transport = outbound
        .dial_udp(Route::Proxy, target)
        .await
        .expect("udp associate");
    assert!(transport.is_proxied());
    assert_eq!(transport.send(b"quic").await.expect("send"), 4);

    let mut buffer = [0u8; 32];
    let read = tokio::time::timeout(Duration::from_secs(2), transport.recv(&mut buffer))
        .await
        .expect("the relay answers")
        .expect("recv");
    assert_eq!(&buffer[..read], b"quic");
}

#[tokio::test]
async fn http_proxies_have_no_udp() {
    let (proxy, _) = support::proxies::spawn_http_proxy("200 Connection established");
    let outbound = make(&http_config(proxy), ProtectorHandle::new());
    let target: std::net::SocketAddr = "10.0.0.1:443".parse().expect("target");
    let error = outbound
        .dial_udp(Route::Proxy, target)
        .await
        .err()
        .expect("no udp");
    assert_eq!(error, "outbound proxy does not support UDP");
}

#[tokio::test]
async fn a_direct_udp_transport_round_trips() {
    let (echo, count) = support::proxies::spawn_udp_echo();
    let outbound = make("", ProtectorHandle::new());
    let transport = outbound
        .dial_udp(Route::Direct, echo)
        .await
        .expect("direct udp");
    assert!(!transport.is_proxied());
    assert_eq!(transport.send(b"dns").await.expect("send"), 3);
    let mut buffer = [0u8; 16];
    let read = tokio::time::timeout(Duration::from_secs(2), transport.recv(&mut buffer))
        .await
        .expect("the echo answers")
        .expect("recv");
    assert_eq!(&buffer[..read], b"dns");
    assert_eq!(count.load(Ordering::Relaxed), 1);
}

struct Refusing;
impl Protector for Refusing {
    fn protect(&self, _fd: i64) -> bool {
        false
    }
}

#[tokio::test]
async fn a_refused_protect_never_reaches_the_proxy() {
    let proxy = support::proxies::spawn_socks5_proxy();
    let protector = ProtectorHandle::new();
    protector.install(Arc::new(Refusing));
    let outbound = make(&socks5_config(proxy.address), protector);
    let target: std::net::SocketAddr = "10.20.30.40:443".parse().expect("target");
    let error = outbound
        .dial_tcp(Route::Proxy, target)
        .await
        .expect_err("refused");
    assert!(error.contains("protect refused"), "{error}");
    assert!(proxy.targets.lock().expect("targets").is_empty());
}

#[tokio::test]
async fn the_status_callback_sees_ready_and_error() {
    struct Recorder(Mutex<Vec<String>>);
    impl StatusSink for Recorder {
        fn status(&self, state: &str, message: &str) {
            self.0
                .lock()
                .expect("recorder")
                .push(format!("{state}:{message}"));
        }
    }

    let proxy = support::proxies::spawn_socks5_proxy();
    let config = Config::parse(&socks5_config(proxy.address)).expect("config");
    let recorder = Arc::new(Recorder(Mutex::new(Vec::new())));
    let dispatcher = Arc::new(StatusDispatcher::default());
    dispatcher.set(Some(recorder.clone()));
    let outbound = Outbound::new(config, ProtectorHandle::new(), dispatcher.clone());

    let target: std::net::SocketAddr = "10.20.30.40:443".parse().expect("target");
    outbound
        .dial_tcp(Route::Proxy, target)
        .await
        .expect("socks5 dial");
    assert_eq!(recorder.0.lock().expect("recorder").as_slice(), &["ready:"]);

    // A proxy that is not listening: the next dial reports a single `error` and fails. Port 1 is
    // never a SOCKS5 proxy, and the config's loopback rule still accepts it.
    let unreachable = Config::parse(
        r#"{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1,"scope":"all"}"#,
    )
    .expect("config");
    let outbound = Outbound::new(unreachable, ProtectorHandle::new(), dispatcher);
    let _ = outbound.dial_tcp(Route::Proxy, target).await;
    let events = recorder.0.lock().expect("recorder");
    assert!(
        events.iter().any(|event| event.starts_with("error:")),
        "{events:?}"
    );
    assert_eq!(
        events
            .iter()
            .filter(|event| event.starts_with("error:"))
            .count(),
        1,
        "the dedupe keeps one error per message"
    );
}

#[tokio::test]
async fn a_proxy_scope_leaves_other_apps_direct() {
    let proxy = support::proxies::spawn_socks5_proxy();
    let raw = format!(
        r#"{{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":{},"scope":"apps","uids":[10086]}}"#,
        proxy.address.port()
    );
    let outbound = make(&raw, ProtectorHandle::new());
    assert_eq!(outbound.route_for(10086), Route::Proxy);
    assert_eq!(outbound.route_for(20000), Route::Direct);
    assert_eq!(outbound.route_for(-1), Route::Direct);

    let (echo, accepted) = support::proxies::spawn_tcp_echo();
    let transport = outbound
        .dial_tcp(outbound.route_for(20000), echo)
        .await
        .expect("direct dial");
    drop(transport);
    let deadline = std::time::Instant::now() + Duration::from_secs(2);
    while accepted.load(Ordering::Relaxed) == 0 && std::time::Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(accepted.load(Ordering::Relaxed), 1);
    assert!(proxy.targets.lock().expect("targets").is_empty());
}

/// A dialer whose own upstream queries follow `outbound`, the way the engine wires stage 4a's
/// `scope:"all"` into Go's `resolverOutbound()`.
fn resolver_dialer(outbound: &str) -> diting_engine::resolver::dial::Dialer {
    use diting_engine::logs::DiscardBootstrapSink;
    use diting_engine::resolver::bootstrap::Bootstrap;
    let protector = ProtectorHandle::new();
    diting_engine::resolver::dial::Dialer::new(
        Arc::new(Bootstrap::new(Arc::new(DiscardBootstrapSink))),
        protector.clone(),
    )
    .with_outbound(Some(Arc::new(std::sync::RwLock::new(make(
        outbound, protector,
    )))))
}

#[tokio::test]
async fn the_resolvers_udp_dial_follows_the_proxy() {
    let proxy = support::proxies::spawn_socks5_proxy();
    let (echo, _datagrams) = support::proxies::spawn_udp_echo();
    let dialer = resolver_dialer(&socks5_config(proxy.address));

    let transport = dialer.udp_transport(echo).await.expect("associate");
    assert!(transport.is_proxied(), "plain DNS goes through the proxy");
    transport.send(b"plain-dns").await.expect("send");
    let mut buffer = [0u8; 32];
    let read = transport.recv(&mut buffer).await.expect("recv");
    assert_eq!(&buffer[..read], b"plain-dns");

    let targets = proxy.targets.lock().expect("targets");
    assert_eq!(targets.len(), 1, "one UDP ASSOCIATE, one association");
    assert!(targets[0].ends_with(":0"), "{}", targets[0]);
}

#[tokio::test]
async fn the_resolvers_tcp_dial_follows_the_proxy() {
    let proxy = support::proxies::spawn_socks5_proxy();
    let (echo, _accepted) = support::proxies::spawn_tcp_echo();
    let dialer = resolver_dialer(&socks5_config(proxy.address));

    let mut stream = dialer
        .connect_tcp(&echo.ip().to_string(), &echo.port().to_string())
        .await
        .expect("proxied DoH dial");
    stream.write_all(b"dot").await.expect("write");
    let mut buffer = [0u8; 3];
    stream.read_exact(&mut buffer).await.expect("read");
    assert_eq!(&buffer, b"dot");

    // The proxy was asked for the upstream address (and echoed the bytes itself), so the query
    // left through it instead of dialing the upstream directly.
    let targets = proxy.targets.lock().expect("targets");
    assert_eq!(targets.as_slice(), [echo.to_string()]);
}

#[tokio::test]
async fn the_resolvers_dials_stay_direct_for_the_per_app_scope() {
    let proxy = support::proxies::spawn_socks5_proxy();
    let (echo, accepted) = support::proxies::spawn_tcp_echo();
    let raw = format!(
        r#"{{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":{},"scope":"apps","uids":[10086]}}"#,
        proxy.address.port()
    );
    let dialer = resolver_dialer(&raw);

    let mut stream = dialer
        .connect_tcp(&echo.ip().to_string(), &echo.port().to_string())
        .await
        .expect("direct DoH dial");
    stream.write_all(b"dot").await.expect("write");
    let mut buffer = [0u8; 3];
    stream.read_exact(&mut buffer).await.expect("read");
    assert_eq!(&buffer, b"dot");
    assert_eq!(accepted.load(Ordering::Relaxed), 1);
    assert!(proxy.targets.lock().expect("targets").is_empty());
}
