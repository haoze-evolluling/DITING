//! End-to-end cases for the standalone server: a real UDP/TCP client, a real upstream socket on
//! loopback, and the engine in between.
//!
//! Nothing here is mocked at the boundary that matters. The fake upstream is a plain `UdpSocket` that
//! answers whatever query it is given with one canned A record, so the tests exercise the whole path
//! a phone would: wire in → DDR / rewrite / policy / cache / upstream → wire out.

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream, UdpSocket};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use diting_engine::logs::{BootstrapEvent, EventSink, RaceEvent};
use diting_engine::Engine;

/// A fake upstream that answers every query with `address` and counts the queries it saw.
struct FakeUpstream {
    address: SocketAddr,
    queries: Arc<AtomicUsize>,
    last_query: Arc<Mutex<Vec<u8>>>,
}

impl FakeUpstream {
    fn start(answer: [u8; 4], ttl: u32) -> Self {
        let socket = UdpSocket::bind("127.0.0.1:0").expect("bind fake upstream");
        socket
            .set_read_timeout(Some(Duration::from_millis(200)))
            .expect("timeout");
        let address = socket.local_addr().expect("local addr");
        let queries = Arc::new(AtomicUsize::new(0));
        let last_query = Arc::new(Mutex::new(Vec::new()));

        let counter = queries.clone();
        let last = last_query.clone();
        std::thread::spawn(move || {
            let mut buffer = [0u8; 4096];
            loop {
                let Ok((read, peer)) = socket.recv_from(&mut buffer) else {
                    continue;
                };
                let query = buffer[..read].to_vec();
                counter.fetch_add(1, Ordering::Relaxed);
                *last.lock().unwrap() = query.clone();
                let response = answer_wire(&query, answer, ttl);
                let _ = socket.send_to(&response, peer);
            }
        });

        Self {
            address,
            queries,
            last_query,
        }
    }

    fn count(&self) -> usize {
        self.queries.load(Ordering::Relaxed)
    }

    fn last(&self) -> Vec<u8> {
        self.last_query.lock().unwrap().clone()
    }
}

fn question_wire(name: &str) -> Vec<u8> {
    let mut out = Vec::new();
    for label in name.trim_end_matches('.').split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out
}

/// A one-question query for `name`, type A.
fn query_wire(name: &str, id: u16) -> Vec<u8> {
    let mut out = vec![0u8; 12];
    out[0..2].copy_from_slice(&id.to_be_bytes());
    out[2] = 0x01;
    out[5] = 1;
    out.extend(question_wire(name));
    out.extend(1u16.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out
}

/// The answer the fake upstream sends: the question echoed with one A record.
fn answer_wire(query: &[u8], address: [u8; 4], ttl: u32) -> Vec<u8> {
    let mut out = query.to_vec();
    out[2] = 0x81;
    out[3] = 0x80;
    out[7] = 1;
    out.extend_from_slice(&[0xc0, 0x0c]);
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&ttl.to_be_bytes());
    out.extend_from_slice(&4u16.to_be_bytes());
    out.extend_from_slice(&address);
    out
}

fn config_json(upstream: SocketAddr, block_response: &str, cache_ttl: u32) -> String {
    format!(
        r#"{{"mode":"single","providers":[{{"id":"p1","protocol":"PLAIN","server":"{}","url":"","weight":1}}],"blockResponse":"{block_response}","dynamicResponse":{{"enabled":false,"requestThreshold":0,"windowSeconds":0,"nxDomainDurationSeconds":0}},"cache":{{"enabled":true,"mode":"limit_max_ttl","maxTtlSeconds":{cache_ttl},"fixedTtlSeconds":0,"minTtlEnabled":false,"minTtlSeconds":0,"staleFallbackEnabled":true,"staleFallbackSeconds":60,"negativeTtlEnabled":false,"negativeTtlSeconds":0}},"bootstrap":{{"enabled":false,"ips":[]}}}}"#,
        upstream
    )
}

fn snapshot_json(block: &[&str]) -> String {
    let rules = block
        .iter()
        .map(|pattern| format!("\"{pattern}\""))
        .collect::<Vec<_>>()
        .join(",");
    format!(
        r#"{{"filterEnabled":true,"globalBlock":[{rules}],"globalAllow":[],"globalImportant":[]}}"#
    )
}

#[derive(Default)]
struct Recorder {
    batches: Mutex<Vec<String>>,
    races: Mutex<Vec<RaceEvent>>,
}

impl EventSink for Recorder {
    fn batch(&self, json: &str) {
        self.batches.lock().unwrap().push(json.to_string());
    }

    fn race(&self, event: &RaceEvent) {
        self.races.lock().unwrap().push(event.clone());
    }

    fn bootstrap(&self, _event: &BootstrapEvent) {}
}

fn engine_with(config: &str) -> Arc<Engine> {
    let engine = Arc::new(Engine::new());
    engine.apply_dns_config(config).expect("config accepted");
    engine.set_filter_dns(true);
    engine
}

fn udp_query(port: u16, query: &[u8]) -> Option<Vec<u8>> {
    let socket = UdpSocket::bind("127.0.0.1:0").expect("bind client");
    socket
        .set_read_timeout(Some(Duration::from_secs(3)))
        .expect("timeout");
    socket
        .send_to(query, format!("127.0.0.1:{port}"))
        .expect("send");
    let mut buffer = [0u8; 4096];
    let read = socket.recv(&mut buffer).ok()?;
    Some(buffer[..read].to_vec())
}

fn tcp_query(port: u16, query: &[u8]) -> Option<Vec<u8>> {
    let mut stream = TcpStream::connect(format!("127.0.0.1:{port}")).ok()?;
    stream
        .set_read_timeout(Some(Duration::from_secs(3)))
        .expect("timeout");
    stream.write_all(&(query.len() as u16).to_be_bytes()).ok()?;
    stream.write_all(query).ok()?;
    let mut length = [0u8; 2];
    stream.read_exact(&mut length).ok()?;
    let size = u16::from_be_bytes(length) as usize;
    let mut response = vec![0u8; size];
    stream.read_exact(&mut response).ok()?;
    Some(response)
}

/// Waits for a condition the server reaches asynchronously.
fn until(condition: impl Fn() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        if condition() {
            return;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn forwards_answers_and_serves_the_cache() {
    let upstream = FakeUpstream::start([1, 2, 3, 4], 60);
    let engine = engine_with(&config_json(upstream.address, "NXDOMAIN", 600));
    engine.start_standalone(0).expect("server starts");
    let port = engine.standalone_port().expect("port");

    let first = udp_query(port, &query_wire("example.test", 7)).expect("answer");
    assert_eq!(first[0..2], [0, 7], "the client's transaction id");
    assert_eq!(first[3] & 0x0f, 0, "NOERROR");
    assert_eq!(upstream.count(), 1, "one upstream round trip");

    let forwarded = upstream.last();
    assert!(
        String::from_utf8_lossy(&forwarded).contains("example"),
        "the upstream saw the question we forwarded"
    );

    let second = udp_query(port, &query_wire("example.test", 8)).expect("cached answer");
    assert_eq!(second[0..2], [0, 8], "the cache patches the id");
    assert_eq!(
        upstream.count(),
        1,
        "the second query is served from the cache"
    );
    assert_eq!(engine.total_queries(), 2);

    let stats: serde_json::Value =
        serde_json::from_str(&engine.cache_stats_json()).expect("cache stats");
    assert_eq!(stats["totalHits"], serde_json::json!(1));
    assert_eq!(stats["totalMisses"], serde_json::json!(1));
    let entries: serde_json::Value =
        serde_json::from_str(&engine.cache_entries_json(10)).expect("entries");
    assert_eq!(entries[0]["queryName"], serde_json::json!("example.test"));

    engine.stop_standalone();
}

#[test]
fn udp_and_tcp_agree() {
    let upstream = FakeUpstream::start([9, 9, 9, 9], 30);
    let engine = engine_with(&config_json(upstream.address, "NXDOMAIN", 600));
    engine.start_standalone(0).expect("server starts");
    let port = engine.standalone_port().expect("port");

    let via_udp = udp_query(port, &query_wire("tcp.test", 1)).expect("udp");
    let via_tcp = tcp_query(port, &query_wire("tcp.test", 2)).expect("tcp");
    assert_eq!(via_udp[0..2], [0, 1]);
    assert_eq!(via_tcp[0..2], [0, 2]);
    assert!(via_udp.len() >= 2 && via_tcp.len() >= 2);

    engine.stop_standalone();
}

#[test]
fn policy_blocks_with_the_configured_response() {
    let upstream = FakeUpstream::start([1, 1, 1, 1], 60);
    let engine = engine_with(&config_json(upstream.address, "NXDOMAIN", 600));
    assert_eq!(
        engine.apply_rule_snapshot(&snapshot_json(&["blocked.test"])),
        ""
    );
    engine.start_standalone(0).expect("server starts");
    let port = engine.standalone_port().expect("port");

    let answer = udp_query(port, &query_wire("blocked.test", 3)).expect("blocked answer");
    assert_eq!(answer[3] & 0x0f, 3, "NXDOMAIN");
    assert_eq!(
        upstream.count(),
        0,
        "a blocked query never reaches the upstream"
    );
    assert_eq!(engine.blocked_queries(), 1);

    engine.stop_standalone();
}

#[test]
fn filtering_switch_bypasses_the_policy() {
    let upstream = FakeUpstream::start([5, 5, 5, 5], 60);
    let engine = engine_with(&config_json(upstream.address, "NXDOMAIN", 600));
    assert_eq!(
        engine.apply_rule_snapshot(&snapshot_json(&["blocked.test"])),
        ""
    );
    engine.set_filter_dns(false);
    engine.start_standalone(0).expect("server starts");
    let port = engine.standalone_port().expect("port");

    let answer = udp_query(port, &query_wire("blocked.test", 4)).expect("answer");
    assert_eq!(answer[3] & 0x0f, 0, "NOERROR once filtering is off");
    assert_eq!(upstream.count(), 1);
    assert_eq!(engine.blocked_queries(), 0);

    engine.stop_standalone();
}

#[test]
fn ddr_and_rewrite_never_reach_the_upstream() {
    let upstream = FakeUpstream::start([1, 2, 3, 4], 60);
    let engine = engine_with(&config_json(upstream.address, "NXDOMAIN", 600));
    engine.set_rewrite_rules(r#"{"rewrite.test":"9.8.7.6"}"#);
    engine.start_standalone(0).expect("server starts");
    let port = engine.standalone_port().expect("port");

    let ddr = udp_query(port, &query_wire("_dns.resolver.arpa", 5)).expect("ddr answer");
    assert_eq!(ddr[3] & 0x0f, 3, "DDR is refused with NXDOMAIN");
    assert_eq!(engine.blocked_queries(), 1);

    let rewrite = udp_query(port, &query_wire("rewrite.test", 6)).expect("rewrite answer");
    assert_eq!(rewrite[3] & 0x0f, 0);
    assert_eq!(rewrite[6..8], [0, 1], "one answer record");
    assert_eq!(&rewrite[rewrite.len() - 4..], &[9, 8, 7, 6]);

    assert_eq!(upstream.count(), 0, "neither branch asked the upstream");
    engine.stop_standalone();
}

#[test]
fn resolve_domain_reports_the_go_document() {
    let upstream = FakeUpstream::start([7, 7, 7, 7], 120);
    let engine = engine_with(&config_json(upstream.address, "NXDOMAIN", 600));

    let document: serde_json::Value =
        serde_json::from_str(&engine.resolve_domain_blocking("example.test", true)).expect("json");
    assert_eq!(
        document["source"],
        serde_json::json!("upstream"),
        "document: {document}"
    );
    assert_eq!(document["ips"], serde_json::json!(["7.7.7.7"]));
    assert_eq!(document["ttls"], serde_json::json!([120]));

    let empty: serde_json::Value =
        serde_json::from_str(&engine.resolve_domain_blocking("", true)).expect("json");
    assert_eq!(empty["error"], serde_json::json!("empty domain"));
}

#[test]
fn log_rows_reach_the_sink() {
    let upstream = FakeUpstream::start([1, 2, 3, 4], 60);
    let engine = engine_with(&config_json(upstream.address, "NXDOMAIN", 600));
    let recorder = Arc::new(Recorder::default());
    engine.set_event_sink(Some(recorder.clone()));
    engine.start_standalone(0).expect("server starts");
    let port = engine.standalone_port().expect("port");

    udp_query(port, &query_wire("logged.test", 9)).expect("answer");
    until(|| !recorder.batches.lock().unwrap().is_empty());

    let batches = recorder.batches.lock().unwrap();
    let rows: serde_json::Value = serde_json::from_str(&batches[0]).expect("json");
    let row = &rows[0];
    assert_eq!(row["d"], serde_json::json!("logged.test"));
    assert_eq!(row["b"], serde_json::json!(false));
    assert_eq!(row["i"], serde_json::json!("1.2.3.4"));
    assert_eq!(row["c"], serde_json::json!(false));
    assert_eq!(row["a"], serde_json::json!("RootProxy"));

    let races = recorder.races.lock().unwrap();
    assert_eq!(races.len(), 1, "one race event per upstream resolution");
    assert_eq!(races[0].query_name, "logged.test");
    assert_eq!(races[0].selected_provider_id, "p1");

    engine.stop_standalone();
}

#[test]
fn stats_document_reports_the_counters() {
    let upstream = FakeUpstream::start([1, 2, 3, 4], 60);
    let engine = engine_with(&config_json(upstream.address, "NXDOMAIN", 600));
    engine.start_standalone(0).expect("server starts");
    let port = engine.standalone_port().expect("port");
    udp_query(port, &query_wire("stat.test", 10)).expect("answer");

    let document: serde_json::Value = serde_json::from_str(&engine.stats_json()).expect("json");
    assert_eq!(document["total"], serde_json::json!(1));
    assert_eq!(document["blocked"], serde_json::json!(0));
    assert_eq!(document["dropped_logs"], serde_json::json!(0));

    engine.stop_standalone();
}
