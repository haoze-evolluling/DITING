use std::collections::HashMap;
use std::fmt;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

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

/// 传输层协议：热路径用 `Tcp`/`Udp` 零分配；FFI JSON 透传未知协议时落到 `Other`。
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum FlowProtocol {
    Tcp,
    Udp,
    Other(Box<str>),
}

impl FlowProtocol {
    pub fn parse(value: &str) -> Self {
        match value {
            "tcp" => Self::Tcp,
            "udp" => Self::Udp,
            other => Self::Other(other.into()),
        }
    }

    pub fn as_str(&self) -> &str {
        match self {
            Self::Tcp => "tcp",
            Self::Udp => "udp",
            Self::Other(text) => text,
        }
    }
}

impl fmt::Display for FlowProtocol {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// 流端点地址：数据面热路径直接存 `V4`/`V6`，创建与拷贝零堆分配；
/// 仅 FFI JSON 传入非标准地址字符串时落到 `Other`。
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum FlowAddr {
    V4(Ipv4Addr),
    V6(Ipv6Addr),
    Other(Box<str>),
}

impl FlowAddr {
    pub fn parse(value: &str) -> Self {
        match value.parse::<IpAddr>() {
            Ok(IpAddr::V4(v4)) => Self::V4(v4),
            Ok(IpAddr::V6(v6)) => Self::V6(v6),
            Err(_) => Self::Other(value.into()),
        }
    }

    pub fn from_ip(ip: IpAddr) -> Self {
        match ip {
            IpAddr::V4(v4) => Self::V4(v4),
            IpAddr::V6(v6) => Self::V6(v6),
        }
    }
}

impl From<Ipv4Addr> for FlowAddr {
    fn from(value: Ipv4Addr) -> Self {
        Self::V4(value)
    }
}

impl From<Ipv6Addr> for FlowAddr {
    fn from(value: Ipv6Addr) -> Self {
        Self::V6(value)
    }
}

impl From<IpAddr> for FlowAddr {
    fn from(value: IpAddr) -> Self {
        Self::from_ip(value)
    }
}

impl fmt::Display for FlowAddr {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::V4(v4) => write!(f, "{v4}"),
            Self::V6(v6) => write!(f, "{v6}"),
            Self::Other(text) => f.write_str(text),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FlowKey {
    pub protocol: FlowProtocol,
    pub src_ip: FlowAddr,
    pub src_port: u16,
    pub dst_ip: FlowAddr,
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

/// 持有所有权的快照，供调用方在释放表锁之后再做排序、截断和 JSON 序列化。
#[derive(Clone, Debug)]
pub struct OwnedSnapshot {
    pub base_seq: u64,
    pub next_seq: u64,
    pub total: usize,
    pub truncated: bool,
    pub sessions: Vec<FlowSession>,
}

impl OwnedSnapshot {
    pub fn from_collected(
        since_seq: u64,
        next_seq: u64,
        mut items: Vec<FlowSession>,
        limit: usize,
    ) -> Self {
        items.sort_by_key(|session| session.seq);
        let total = items.len();
        let cap = if limit == 0 { total } else { limit };
        let truncated = total > cap;
        items.truncate(cap);
        Self {
            base_seq: since_seq,
            next_seq,
            total,
            truncated,
            sessions: items,
        }
    }

    pub fn to_json(&self) -> String {
        format_snapshot_json(
            self.base_seq,
            self.next_seq,
            self.total,
            self.truncated,
            self.sessions.iter(),
        )
    }
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

    /// 锁内只做最小扫描拷贝，把排序与 JSON 序列化留给调用方释放锁之后再做。
    pub fn collect_since(&self, since_seq: u64) -> (u64, Vec<FlowSession>) {
        if self.next_seq <= since_seq {
            return (self.next_seq, Vec::new());
        }
        let items = self
            .by_key
            .values()
            .filter(|session| session.seq > since_seq)
            .cloned()
            .collect();
        (self.next_seq, items)
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
        items.truncate(cap);
        Snapshot {
            base_seq: since_seq,
            next_seq: self.next_seq,
            total,
            truncated,
            sessions: items,
        }
    }
}

impl Snapshot<'_> {
    pub fn to_json(&self) -> String {
        format_snapshot_json(
            self.base_seq,
            self.next_seq,
            self.total,
            self.truncated,
            self.sessions.iter().copied(),
        )
    }
}

fn format_snapshot_json<'a>(
    base_seq: u64,
    next_seq: u64,
    total: usize,
    truncated: bool,
    sessions: impl ExactSizeIterator<Item = &'a FlowSession>,
) -> String {
    use std::fmt::Write;

    let mut out = String::with_capacity(96 + sessions.len() * 224);
    let _ = write!(
        out,
        "{{\"baseSeq\":{},\"nextSeq\":{},\"total\":{},\"truncated\":{},\"sessions\":[",
        base_seq, next_seq, total, truncated
    );
    for (index, session) in sessions.enumerate() {
        if index > 0 {
            out.push(',');
        }
        write_session(&mut out, session);
    }
    out.push_str("]}");
    out
}

fn write_session(out: &mut String, session: &FlowSession) {
    use std::fmt::Write;

    let key = &session.key;
    out.push('{');
    write_string_field(out, "protocol", key.protocol.as_str());
    out.push(',');
    write_addr_field(out, "srcIp", &key.src_ip);
    let _ = write!(out, ",\"srcPort\":{}", key.src_port);
    out.push(',');
    write_addr_field(out, "dstIp", &key.dst_ip);
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

fn write_addr_field(out: &mut String, name: &str, addr: &FlowAddr) {
    use std::fmt::Write;

    out.push('"');
    out.push_str(name);
    out.push_str("\":");
    match addr {
        FlowAddr::V4(v4) => {
            let _ = write!(out, "\"{v4}\"");
        }
        FlowAddr::V6(v6) => {
            let _ = write!(out, "\"{v6}\"");
        }
        FlowAddr::Other(text) => write_json_string(out, text),
    }
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
mod tests;
