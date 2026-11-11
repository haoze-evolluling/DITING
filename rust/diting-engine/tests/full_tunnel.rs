//! The TUN data plane end to end: real threads, real DNS pipeline, an in-memory link.
//!
//! This is the stage 3 gate, minus the device: the same `Session` the `VpnService` descriptor feeds
//! is driven through [`MemoryLink`], so every hop is the production one —
//!
//! ```text
//! client packet → MemoryLink → reader thread → Events → stack thread → smoltcp
//!               → gate/DNS handler (tokio) → Events::Write → stack → Egress → writer thread
//!               → MemoryLink → assertions
//! ```
//!
//! The upstream is a real loopback UDP DNS server (the one `tests/support` already uses), so the
//! answer bytes are the pipeline's, not a mock's. The tests are in their own binary on purpose:
//! they install a process-wide engine each and would otherwise race the transport cases' dials.

mod support;

use std::net::SocketAddr;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};

use diting_engine::attribution::{AppUidResolver, UidResolver};
use diting_engine::engine::TrafficSink;
use diting_engine::outbound::StatusSink;
use diting_engine::tunnel::{MemoryLink, PacketLink};
use diting_engine::Engine;
use smoltcp::wire::IpEndpoint;

use support::tunnel::{wait_tcp, wait_udp, Client, WAIT};
use support::wire;

const APP: [u8; 4] = [10, 0, 0, 2];
const SERVER: [u8; 4] = [8, 8, 8, 8];
const APP_PORT: u16 = 5353;
const DNS_PORT: u16 = 53;

fn app(port: u16) -> IpEndpoint {
    wire::endpoint_v4(APP, port)
}

fn server(port: u16) -> IpEndpoint {
    wire::endpoint_v4(SERVER, port)
}

fn engine_for(upstream: SocketAddr) -> Arc<Engine> {
    let engine = Arc::new(Engine::new());
    let config = support::config_json(
        "single",
        &[support::provider_json(
            "p1",
            "PLAIN",
            &upstream.to_string(),
            "",
        )],
        None,
    );
    engine
        .apply_dns_config(&config)
        .expect("the config applies");
    engine.set_filter_dns(true);
    engine
}

/// A UDP query for `name` reaches the real upstream and the answer comes back from the original
/// destination address and port, with the client's transaction id.
#[test]
fn a_udp_dns_query_crosses_the_tunnel() {
    let (upstream, queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let engine = engine_for(upstream);
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    let query = support::query_wire("tunnel.test", 42);
    link.feed(wire::emit_udp(app(APP_PORT), server(DNS_PORT), &query));

    let answer = wait_udp(&link, |segment| {
        segment.src == server(DNS_PORT) && segment.dst == app(APP_PORT)
    })
    .expect("an answer from 8.8.8.8:53");
    assert_eq!(
        i16::from_be_bytes([answer.payload[0], answer.payload[1]]),
        42
    );
    assert_eq!(answer.payload[3] & 0x0f, 0, "NOERROR");
    assert_eq!(
        answer.payload,
        support::answer_wire(&query, [1, 2, 3, 4], 60),
        "the upstream bytes, only the transaction id may differ (it does not here)"
    );
    assert_eq!(queries.load(Ordering::Relaxed), 1);
    assert_eq!(
        engine.tun_document().expect("tun")["udpDatagrams"],
        serde_json::json!(1)
    );

    engine.stop_full();
    assert!(!engine.is_full_running());
}

/// TCP DNS: transparent accept on the destination, 2-byte framing, half-close from the client.
#[test]
fn a_tcp_dns_query_crosses_the_tunnel() {
    let (upstream, queries) = support::spawn_udp_upstream([5, 6, 7, 8], false);
    let engine = engine_for(upstream);
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    let mut client = Client::new(app(40000), server(DNS_PORT));
    client.connect(&link);

    let query = support::query_wire("tcp-tunnel.test", 7);
    let mut framed = Vec::new();
    framed.extend_from_slice(&(query.len() as u16).to_be_bytes());
    framed.extend_from_slice(&query);
    link.feed(client.data(&framed));

    let local = client.local;
    let remote = client.remote;
    let response = wait_tcp(&link, |segment| {
        !segment.payload.is_empty() && segment.src == remote && segment.dst == local
    })
    .unwrap_or_else(|| panic!("the framed answer: {:?}", engine.tun_document()));
    let length = u16::from_be_bytes([response.payload[0], response.payload[1]]) as usize;
    assert_eq!(
        length,
        response.payload.len() - 2,
        "the frame length matches"
    );
    let answer = &response.payload[2..];
    assert_eq!(i16::from_be_bytes([answer[0], answer[1]]), 7);
    assert_eq!(queries.load(Ordering::Relaxed), 1);

    // The client half-closes: the handler sees EOF and sends its own FIN, which the stack emits.
    link.feed(client.fin());
    let fin = wait_tcp(&link, |segment| {
        segment.is_fin() && segment.src == remote && segment.dst == local
    });
    assert!(fin.is_some(), "the tunnel answers the client's FIN");

    engine.stop_full();
}

/// `:853` is refused when the switch is on, and the flow never reaches the upstream.
#[test]
fn encrypted_dns_is_blocked_at_853() {
    let (upstream, queries) = support::spawn_udp_upstream([9, 9, 9, 9], false);
    let engine = engine_for(upstream);
    engine.set_block_encrypted_dns(true);
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    // `smoltcp` completes the handshake before the session can look at the flow (gVisor did the
    // same), so the client may see a SYN-ACK; what must not happen is an upstream query or an
    // answer. The session aborts the socket right after the gate says no.
    let mut client = Client::new(app(40001), server(853));
    link.feed(client.syn());
    std::thread::sleep(Duration::from_millis(200));
    assert_eq!(queries.load(Ordering::Relaxed), 0, "no upstream query");

    let tun = engine.tun_document().expect("the tun document");
    assert_eq!(tun["blockedFlows"], serde_json::json!(1));

    engine.stop_full();
}

/// A blocked UID is refused before anything is dialed; the connection log shows it.
#[test]
fn a_blocked_uid_never_reaches_the_stack() {
    struct Uid(i32);
    impl UidResolver for Uid {
        fn resolve(
            &self,
            _protocol: i32,
            _app_ip: &str,
            _app_port: u16,
            _server_ip: &str,
            _server_port: u16,
        ) -> i32 {
            self.0
        }
    }

    let (upstream, queries) = support::spawn_udp_upstream([1, 1, 1, 1], false);
    let engine = engine_for(upstream);
    engine
        .attribution()
        .install_uid_resolver(Arc::new(Uid(10123)));
    engine.set_blocked_uids("10123,20234,bogus");
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    link.feed(wire::emit_udp(
        app(APP_PORT),
        server(DNS_PORT),
        &support::query_wire("blocked-uid.test", 5),
    ));
    assert!(
        wait_udp(&link, |segment| segment.src == server(DNS_PORT)).is_none(),
        "a blocked UID gets no answer"
    );
    assert_eq!(queries.load(Ordering::Relaxed), 0);
    let tun = engine.tun_document().expect("the tun document");
    assert_eq!(tun["blockedFlows"], serde_json::json!(1));

    engine.stop_full();
}

/// Non-DNS UDP is relayed out through the direct transport (stage 4a).
#[test]
fn non_dns_udp_is_relayed_and_the_answer_comes_back() {
    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let (echo, datagrams) = support::proxies::spawn_udp_echo();
    let engine = engine_for(upstream);
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    let destination = match echo {
        std::net::SocketAddr::V4(v4) => wire::endpoint_v4(v4.ip().octets(), echo.port()),
        std::net::SocketAddr::V6(_) => unreachable!("the echo server binds IPv4"),
    };
    let client = app(40002);
    link.feed(wire::emit_udp(client, destination, b"relay-me"));

    let answer = wait_udp(&link, |segment| {
        segment.src == destination && segment.dst == client
    })
    .expect("the echo came back through the tunnel");
    assert_eq!(answer.payload, b"relay-me");
    assert_eq!(datagrams.load(Ordering::Relaxed), 1);

    let tun = engine.tun_document().expect("the tun document");
    assert_eq!(tun["relayUnavailable"], serde_json::json!(0));
    assert_eq!(tun["udpDatagrams"], serde_json::json!(1));

    engine.stop_full();
}

/// Non-DNS TCP is relayed with half-close: the client sends, shuts down its write side, and still
/// receives the echoed bytes.
#[test]
fn non_dns_tcp_is_relayed_with_half_close() {
    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let (echo, accepted) = support::proxies::spawn_tcp_echo();
    let engine = engine_for(upstream);
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    let destination = match echo {
        std::net::SocketAddr::V4(v4) => wire::endpoint_v4(v4.ip().octets(), echo.port()),
        std::net::SocketAddr::V6(_) => unreachable!("the echo server binds IPv4"),
    };
    let mut client = Client::new(app(40003), destination);
    client.connect(&link);
    link.feed(client.data(b"hello relay"));

    let local = client.local;
    let remote = client.remote;
    let echoed = wait_tcp(&link, |segment| {
        !segment.payload.is_empty() && segment.src == remote && segment.dst == local
    })
    .expect("the echo came back through the tunnel");
    assert_eq!(echoed.payload, b"hello relay");

    link.feed(client.fin());
    let fin = wait_tcp(&link, |segment| segment.is_fin() && segment.src == remote);
    assert!(fin.is_some(), "the relay answers the client's FIN");
    assert_eq!(accepted.load(Ordering::Relaxed), 1);

    engine.stop_full();
}

/// The configured SOCKS5 proxy is used for a flow, and it receives the original destination.
#[test]
fn a_proxied_tcp_flow_goes_through_socks5() {
    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let proxy = support::proxies::spawn_socks5_proxy();
    let engine = engine_for(upstream);
    let error = engine.configure_outbound_proxy(&format!(
        r#"{{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":{},"scope":"all"}}"#,
        proxy.address.port()
    ));
    assert!(error.is_empty(), "{error}");

    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    let destination = wire::endpoint_v4([10, 20, 30, 40], 443);
    let mut client = Client::new(app(40004), destination);
    client.connect(&link);
    link.feed(client.data(b"proxied"));

    let local = client.local;
    let remote = client.remote;
    let echoed = wait_tcp(&link, |segment| {
        !segment.payload.is_empty() && segment.src == remote && segment.dst == local
    })
    .expect("the proxy echoed the bytes");
    assert_eq!(echoed.payload, b"proxied");
    assert_eq!(
        proxy.targets.lock().expect("targets").as_slice(),
        &["10.20.30.40:443"]
    );

    engine.stop_full();
}

/// An HTTP proxy has no datagram mode: the flow is counted as unavailable instead of vanishing.
#[test]
fn a_flow_through_an_http_proxy_cannot_use_udp() {
    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let (proxy, _targets) = support::proxies::spawn_http_proxy("200 Connection established");
    let engine = engine_for(upstream);
    engine.configure_outbound_proxy(&format!(
        r#"{{"enabled":true,"protocol":"http","host":"127.0.0.1","port":{},"scope":"all"}}"#,
        proxy.port()
    ));
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    link.feed(wire::emit_udp(app(40005), server(443), b"datagram"));
    let deadline = Instant::now() + WAIT;
    while Instant::now() < deadline
        && engine.tun_document().expect("tun")["relayUnavailable"] != serde_json::json!(1)
    {
        std::thread::sleep(Duration::from_millis(20));
    }
    let tun = engine.tun_document().expect("the tun document");
    assert_eq!(tun["relayUnavailable"], serde_json::json!(1));

    engine.stop_full();
}

/// With an HTTP-CONNECT proxy scoped to other apps, an unproxied flow is direct and its UDP still
/// works: only a flow that actually rides the proxy is refused for the missing datagram mode.
#[test]
fn an_unproxied_udp_flow_ignores_the_http_proxys_missing_datagram_mode() {
    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let (proxy, _targets) = support::proxies::spawn_http_proxy("200 Connection established");
    let (echo, datagrams) = support::proxies::spawn_udp_echo();
    let engine = engine_for(upstream);
    engine.configure_outbound_proxy(&format!(
        r#"{{"enabled":true,"protocol":"http","host":"127.0.0.1","port":{},"scope":"apps","uids":[10123]}}"#,
        proxy.port()
    ));
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    let destination = match echo {
        std::net::SocketAddr::V4(v4) => wire::endpoint_v4(v4.ip().octets(), echo.port()),
        std::net::SocketAddr::V6(_) => unreachable!("the echo server binds IPv4"),
    };
    let client = app(40006);
    link.feed(wire::emit_udp(client, destination, b"direct-udp"));

    let answer = wait_udp(&link, |segment| {
        segment.src == destination && segment.dst == client
    })
    .expect("the unproxied flow's datagram comes back");
    assert_eq!(answer.payload, b"direct-udp");
    assert_eq!(datagrams.load(Ordering::Relaxed), 1);
    let tun = engine.tun_document().expect("the tun document");
    assert_eq!(tun["relayUnavailable"], serde_json::json!(0));

    engine.stop_full();
}

/// `StartFull` reports the proxy state through `OutboundProxyStatusCallback`.
#[test]
fn the_proxy_status_is_reported_on_start() {
    struct Recorder(std::sync::Mutex<Vec<String>>);
    impl StatusSink for Recorder {
        fn status(&self, state: &str, message: &str) {
            self.0
                .lock()
                .expect("recorder")
                .push(format!("{state}:{message}"));
        }
    }

    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let engine = engine_for(upstream);
    let recorder = Arc::new(Recorder(std::sync::Mutex::new(Vec::new())));
    engine.set_outbound_status_sink(Some(recorder.clone()));
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");
    assert_eq!(
        recorder.0.lock().expect("recorder").as_slice(),
        &["disabled:"]
    );
    engine.stop_full();

    let proxy = support::proxies::spawn_socks5_proxy();
    engine.configure_outbound_proxy(&format!(
        r#"{{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":{},"scope":"all"}}"#,
        proxy.address.port()
    ));
    engine
        .start_full_with_link(link)
        .expect("the session starts again");
    let events = recorder.0.lock().expect("recorder");
    assert_eq!(events.last().map(String::as_str), Some("connecting:"));
    drop(events);
    engine.stop_full();
}

/// The traffic ticker reports the flow's UID as the Kotlin `TrafficIngest` expects.
#[test]
fn the_traffic_ticker_reports_the_flow_uid() {
    struct Uid(i32);
    impl UidResolver for Uid {
        fn resolve(
            &self,
            _protocol: i32,
            _app_ip: &str,
            _app_port: u16,
            _server_ip: &str,
            _server_port: u16,
        ) -> i32 {
            self.0
        }
    }
    struct Names;
    impl AppUidResolver for Names {
        fn package_for(&self, _uid: i32) -> String {
            "com.test.app".to_string()
        }
    }
    struct Recorder(std::sync::Mutex<Vec<String>>);
    impl TrafficSink for Recorder {
        fn tick(&self, json: &str) {
            self.0.lock().expect("recorder").push(json.to_string());
        }
    }

    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let engine = engine_for(upstream);
    engine
        .attribution()
        .install_uid_resolver(Arc::new(Uid(10086)));
    engine.attribution().install_app_resolver(Arc::new(Names));
    let recorder = Arc::new(Recorder(std::sync::Mutex::new(Vec::new())));
    engine.set_traffic_sink(Some(recorder.clone()));
    engine.set_tick_interval_ms(100);

    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");
    link.feed(wire::emit_udp(
        app(APP_PORT),
        server(DNS_PORT),
        &support::query_wire("uid.test", 9),
    ));
    assert!(
        wait_udp(&link, |segment| segment.src == server(DNS_PORT)).is_some(),
        "the query is answered"
    );

    let deadline = Instant::now() + WAIT;
    let mut seen = false;
    while Instant::now() < deadline && !seen {
        std::thread::sleep(Duration::from_millis(50));
        seen = recorder
            .0
            .lock()
            .expect("recorder")
            .iter()
            .any(|json| json.contains("\"uid\":10086"));
    }
    assert!(seen, "a tick mentioned UID 10086: {:?}", recorder.0);

    engine.stop_full();
}

/// The `getStats` document carries `total`/`blocked`/`dropped_logs` plus the tun counters, and the
/// counters go away when the session stops.
#[test]
fn the_stats_document_gains_and_loses_the_tun_object() {
    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let engine = engine_for(upstream);
    assert!(!engine.stats_json().contains("\"tun\""));
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");
    let stats = engine.stats_json();
    assert!(stats.contains("\"total\":"), "{stats}");
    assert!(stats.contains("\"dropped_logs\":"), "{stats}");
    assert!(stats.contains("\"tun\":"), "{stats}");
    engine.stop_full();
    assert!(!engine.stats_json().contains("\"tun\""));
}

/// Reporting the reader's and writer's thread names is not enough: the session must also survive a
/// link that is closed underneath it (the VPN revoke path).
#[test]
fn stopping_survives_a_link_closed_by_the_service() {
    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let engine = engine_for(upstream);
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");
    PacketLink::close(link.as_ref());
    engine.stop_full();
    assert!(!engine.is_full_running());
}
