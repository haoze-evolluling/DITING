use super::*;

fn key(protocol: &str, dst: &str, port: u16, uid: i32) -> FlowKey {
    FlowKey {
        protocol: FlowProtocol::parse(protocol),
        src_ip: FlowAddr::V4(Ipv4Addr::new(10, 0, 0, 2)),
        src_port: 40000,
        dst_ip: FlowAddr::parse(dst),
        dst_port: port,
        uid,
    }
}

fn event(key: FlowKey, up: u64, down: u64, status: FlowStatus, at: i64) -> FlowEvent {
    FlowEvent {
        key,
        domain: String::new(),
        package: String::new(),
        up_delta: up,
        down_delta: down,
        status,
        at_ms: at,
    }
}

#[test]
fn record_accumulates_bytes_and_bumps_sequence() {
    let mut table = FlowTable::new(8);
    let k = key("tcp", "1.1.1.1", 443, 1000);
    let s1 = table.record(event(k.clone(), 10, 20, FlowStatus::Active, 1));
    let s2 = table.record(event(k.clone(), 5, 7, FlowStatus::Active, 2));
    assert!(s2 > s1);
    assert_eq!(table.len(), 1);
    let snapshot = table.snapshot(0, 0);
    let session = &snapshot.sessions[0];
    assert_eq!(session.up_bytes, 15);
    assert_eq!(session.down_bytes, 27);
    assert_eq!(session.last_seen_ms, 2);
}

#[test]
fn domain_is_filled_but_not_erased() {
    let mut table = FlowTable::new(8);
    let k = key("tcp", "1.1.1.1", 443, 1000);
    let mut first = event(k.clone(), 1, 1, FlowStatus::Active, 1);
    first.domain = "example.com".to_string();
    table.record(first);
    table.record(event(k.clone(), 1, 1, FlowStatus::Active, 2));
    assert_eq!(table.snapshot(0, 0).sessions[0].domain, "example.com");
}

#[test]
fn incremental_snapshot_only_returns_newer_changes() {
    let mut table = FlowTable::new(8);
    let a = key("tcp", "1.1.1.1", 443, 1);
    let b = key("udp", "2.2.2.2", 53, 2);
    let seq_a = table.record(event(a, 1, 1, FlowStatus::Active, 1));
    table.record(event(b, 1, 1, FlowStatus::Active, 2));
    let delta = table.snapshot(seq_a, 0);
    assert_eq!(delta.sessions.len(), 1);
    assert_eq!(delta.sessions[0].key.dst_ip, FlowAddr::parse("2.2.2.2"));
    assert_eq!(delta.next_seq, 2);

    let (next_seq, collected) = table.collect_since(seq_a);
    let owned = OwnedSnapshot::from_collected(seq_a, next_seq, collected, 0);
    assert_eq!(owned.to_json(), delta.to_json());
    assert!(table.collect_since(next_seq).1.is_empty());
}

#[test]
fn snapshot_limit_reports_truncation() {
    let mut table = FlowTable::new(8);
    for i in 0..5u16 {
        table.record(event(
            key("tcp", "1.1.1.1", 1000 + i, 1),
            1,
            1,
            FlowStatus::Active,
            1,
        ));
    }
    let snapshot = table.snapshot(0, 2);
    assert_eq!(snapshot.total, 5);
    assert_eq!(snapshot.sessions.len(), 2);
    assert!(snapshot.truncated);

    let (next_seq, collected) = table.collect_since(0);
    let owned = OwnedSnapshot::from_collected(0, next_seq, collected, 2);
    assert_eq!(owned.to_json(), snapshot.to_json());
}

#[test]
fn new_key_at_capacity_evicts_oldest() {
    let mut table = FlowTable::new(2);
    table.record(event(
        key("tcp", "1.1.1.1", 443, 1),
        1,
        1,
        FlowStatus::Active,
        1,
    ));
    table.record(event(
        key("tcp", "2.2.2.2", 443, 2),
        1,
        1,
        FlowStatus::Active,
        2,
    ));
    table.record(event(
        key("tcp", "3.3.3.3", 443, 3),
        1,
        1,
        FlowStatus::Active,
        3,
    ));
    assert_eq!(table.len(), 2);
    assert_eq!(table.dropped(), 1);
    let ips: Vec<String> = table
        .snapshot(0, 0)
        .sessions
        .iter()
        .map(|s| s.key.dst_ip.to_string())
        .collect();
    assert!(!ips.contains(&"1.1.1.1".to_string()));
}

#[test]
fn prune_removes_closed_and_idle_active() {
    let mut table = FlowTable::new(8);
    let active = key("tcp", "1.1.1.1", 443, 1);
    let closed = key("tcp", "2.2.2.2", 443, 2);
    let idle = key("tcp", "3.3.3.3", 443, 3);
    table.record(event(active, 1, 1, FlowStatus::Active, 900));
    table.record(event(closed, 1, 1, FlowStatus::Closed, 900));
    table.record(event(idle, 1, 1, FlowStatus::Active, 10));
    let removed = table.prune_idle(1000, 500);
    assert_eq!(removed, 2);
    assert_eq!(table.len(), 1);
}

#[test]
fn snapshot_json_has_expected_shape() {
    let mut table = FlowTable::new(8);
    let mut e = event(key("tcp", "1.1.1.1", 443, 7), 3, 4, FlowStatus::Active, 42);
    e.package = "com.example".to_string();
    e.domain = "api.example.com".to_string();
    table.record(e);
    let value: serde_json::Value =
        serde_json::from_str(&table.snapshot(0, 0).to_json()).unwrap();
    assert_eq!(value["sessions"][0]["domain"], "api.example.com");
    assert_eq!(value["sessions"][0]["status"], "active");
    assert_eq!(value["sessions"][0]["uid"], 7);
    assert_eq!(value["total"], 1);
}

#[test]
fn the_direct_writer_escapes_string_fields() {
    let mut table = FlowTable::new(8);
    let mut e = event(key("tcp", "1.1.1.1", 443, 7), 3, 4, FlowStatus::Active, 42);
    e.package = "com.ex\tample".to_string();
    e.domain = "odd\"name\ntrailing\\".to_string();
    table.record(e);
    let value: serde_json::Value =
        serde_json::from_str(&table.snapshot(0, 0).to_json()).unwrap();
    assert_eq!(value["sessions"][0]["package"], "com.ex\tample");
    assert_eq!(value["sessions"][0]["domain"], "odd\"name\ntrailing\\");
    assert_eq!(value["sessions"][0]["upBytes"], 3);
}
