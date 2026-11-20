use std::collections::HashMap;

pub const DEFAULT_CAPACITY: usize = 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlowStatus {
    Active,
    Closed,
    Failed,
}

impl FlowStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            FlowStatus::Active => "active",
            FlowStatus::Closed => "closed",
            FlowStatus::Failed => "failed",
        }
    }

    pub fn parse(value: &str) -> FlowStatus {
        match value {
            "closed" => FlowStatus::Closed,
            "failed" => FlowStatus::Failed,
            _ => FlowStatus::Active,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FlowKey {
    pub protocol: String,
    pub src_ip: String,
    pub src_port: u16,
    pub dst_ip: String,
    pub dst_port: u16,
    pub uid: i32,
}

#[derive(Clone, Debug)]
pub struct FlowSession {
    pub key: FlowKey,
    pub domain: String,
    pub package: String,
    pub up_bytes: u64,
    pub down_bytes: u64,
    pub status: FlowStatus,
    pub first_seen_ms: i64,
    pub last_seen_ms: i64,
    seq: u64,
}

impl FlowSession {
    pub fn seq(&self) -> u64 {
        self.seq
    }

    pub fn total_bytes(&self) -> u64 {
        self.up_bytes + self.down_bytes
    }
}

#[derive(Clone, Debug)]
pub struct FlowEvent {
    pub key: FlowKey,
    pub domain: String,
    pub package: String,
    pub up_delta: u64,
    pub down_delta: u64,
    pub status: FlowStatus,
    pub at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct Snapshot<'a> {
    pub base_seq: u64,
    pub next_seq: u64,
    pub total: usize,
    pub truncated: bool,
    pub sessions: Vec<&'a FlowSession>,
}

#[derive(Debug)]
pub struct FlowTable {
    capacity: usize,
    next_seq: u64,
    by_key: HashMap<FlowKey, FlowSession>,
    dropped: u64,
}

impl FlowTable {
    pub fn new(capacity: usize) -> Self {
        let capacity = if capacity == 0 {
            DEFAULT_CAPACITY
        } else {
            capacity
        };
        FlowTable {
            capacity,
            next_seq: 0,
            by_key: HashMap::new(),
            dropped: 0,
        }
    }

    pub fn len(&self) -> usize {
        self.by_key.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_key.is_empty()
    }

    pub fn dropped(&self) -> u64 {
        self.dropped
    }

    pub fn next_seq(&self) -> u64 {
        self.next_seq
    }

    pub fn record(&mut self, event: FlowEvent) -> u64 {
        let seq = self.next_seq.wrapping_add(1);
        self.next_seq = seq;
        let at = event.at_ms;
        if let Some(session) = self.by_key.get_mut(&event.key) {
            session.up_bytes = session.up_bytes.saturating_add(event.up_delta);
            session.down_bytes = session.down_bytes.saturating_add(event.down_delta);
            if !event.domain.is_empty() {
                session.domain = event.domain;
            }
            if !event.package.is_empty() {
                session.package = event.package;
            }
            session.status = event.status;
            session.last_seen_ms = at.max(session.last_seen_ms);
            session.seq = seq;
            return seq;
        }
        if self.by_key.len() >= self.capacity {
            self.evict_oldest();
        }
        let session = FlowSession {
            key: event.key.clone(),
            domain: event.domain,
            package: event.package,
            up_bytes: event.up_delta,
            down_bytes: event.down_delta,
            status: event.status,
            first_seen_ms: at,
            last_seen_ms: at,
            seq,
        };
        self.by_key.insert(event.key, session);
        seq
    }

    fn evict_oldest(&mut self) {
        let oldest = self
            .by_key
            .values()
            .min_by_key(|session| session.last_seen_ms)
            .map(|session| session.key.clone());
        if let Some(key) = oldest {
            if self.by_key.remove(&key).is_some() {
                self.dropped = self.dropped.wrapping_add(1);
            }
        }
    }

    pub fn prune_idle(&mut self, now_ms: i64, idle_ms: i64) -> usize {
        let before = self.by_key.len();
        self.by_key.retain(|_, session| {
            session.status == FlowStatus::Active
                && now_ms.saturating_sub(session.last_seen_ms) <= idle_ms
        });
        before - self.by_key.len()
    }

    pub fn reset(&mut self) {
        self.by_key.clear();
    }

    pub fn snapshot(&self, since_seq: u64, limit: usize) -> Snapshot<'_> {
        let mut items: Vec<&FlowSession> = self
            .by_key
            .values()
            .filter(|session| session.seq > since_seq)
            .collect();
        items.sort_by_key(|session| session.seq);
        let total = items.len();
        let cap = if limit == 0 { total } else { limit };
        let truncated = total > cap;
        Snapshot {
            base_seq: since_seq,
            next_seq: self.next_seq,
            total,
            truncated,
            sessions: items.into_iter().take(cap).collect(),
        }
    }
}

impl Snapshot<'_> {
    pub fn to_json(&self) -> String {
        use std::fmt::Write;

        let mut out = String::with_capacity(96 + self.sessions.len() * 224);
        let _ = write!(
            out,
            "{{\"baseSeq\":{},\"nextSeq\":{},\"total\":{},\"truncated\":{},\"sessions\":[",
            self.base_seq, self.next_seq, self.total, self.truncated
        );
        for (index, session) in self.sessions.iter().enumerate() {
            if index > 0 {
                out.push(',');
            }
            write_session(&mut out, session);
        }
        out.push_str("]}");
        out
    }
}

fn write_session(out: &mut String, session: &FlowSession) {
    use std::fmt::Write;

    let key = &session.key;
    out.push('{');
    write_string_field(out, "protocol", &key.protocol);
    out.push(',');
    write_string_field(out, "srcIp", &key.src_ip);
    let _ = write!(out, ",\"srcPort\":{}", key.src_port);
    out.push(',');
    write_string_field(out, "dstIp", &key.dst_ip);
    let _ = write!(out, ",\"dstPort\":{},\"uid\":{}", key.dst_port, key.uid);
    out.push(',');
    write_string_field(out, "package", &session.package);
    out.push(',');
    write_string_field(out, "domain", &session.domain);
    let _ = write!(
        out,
        ",\"upBytes\":{},\"downBytes\":{},\"status\":",
        session.up_bytes, session.down_bytes
    );
    write_json_string(out, session.status.as_str());
    let _ = write!(
        out,
        ",\"firstSeenMs\":{},\"lastSeenMs\":{},\"seq\":{}}}",
        session.first_seen_ms, session.last_seen_ms, session.seq
    );
}

fn write_string_field(out: &mut String, name: &str, value: &str) {
    out.push('"');
    out.push_str(name);
    out.push_str("\":");
    write_json_string(out, value);
}

fn write_json_string(out: &mut String, value: &str) {
    use std::fmt::Write;

    out.push('"');
    for character in value.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            control if (control as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", control as u32);
            }
            other => out.push(other),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(protocol: &str, dst: &str, port: u16, uid: i32) -> FlowKey {
        FlowKey {
            protocol: protocol.to_string(),
            src_ip: "10.0.0.2".to_string(),
            src_port: 40000,
            dst_ip: dst.to_string(),
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
        assert_eq!(delta.sessions[0].key.dst_ip, "2.2.2.2");
        assert_eq!(delta.next_seq, 2);
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
            .map(|s| s.key.dst_ip.clone())
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
}
