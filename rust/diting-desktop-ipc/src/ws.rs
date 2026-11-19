//! WebSocket event hub and the DNS query observer.
//!
//! The hub is deliberately lock-free for DNS workers: `broadcast` takes a short `std::sync::Mutex`
//! over the client table and uses `try_send`, so a stalled browser can never back-pressure the
//! resolver. Slow clients are removed the moment their bounded queue overflows.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use serde_json::{json, Value};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;

use diting_desktop_app::AppRuntime;
use diting_desktop_core::querylog::{
    QueryLog, Record, STATUS_ALLOWED, STATUS_BLOCKED, STATUS_CACHED, STATUS_ERROR, STATUS_STALE,
};
use diting_desktop_dns::stages::metrics::QueryObserver;

/// A pushed event (`{type,timestamp,data}`).
#[derive(Debug, Clone, Serialize)]
pub struct Event {
    #[serde(rename = "type")]
    pub kind: String,
    pub timestamp: i64,
    pub data: Value,
}

impl Event {
    pub fn new(kind: impl Into<String>, data: Value) -> Self {
        Self {
            kind: kind.into(),
            timestamp: now_ms(),
            data,
        }
    }
}

/// Broadcast fan-out for connected console clients.
pub struct WsHub {
    next_id: AtomicU64,
    clients: Mutex<HashMap<u64, mpsc::Sender<Event>>>,
}

impl Default for WsHub {
    fn default() -> Self {
        Self::new()
    }
}

impl WsHub {
    pub fn new() -> Self {
        Self {
            next_id: AtomicU64::new(1),
            clients: Mutex::new(HashMap::new()),
        }
    }

    /// Registers a client; the returned receiver is bounded so overflow is observable.
    pub fn register(&self) -> (u64, mpsc::Receiver<Event>) {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (sender, receiver) = mpsc::channel(64);
        self.clients
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .insert(id, sender);
        (id, receiver)
    }

    pub fn unregister(&self, id: u64) {
        self.clients
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .remove(&id);
    }

    /// Non-blocking fan-out; slow or closed clients are dropped.
    pub fn broadcast(&self, event: Event) {
        let mut clients = self
            .clients
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let mut stale = Vec::new();
        for (id, sender) in clients.iter() {
            if sender.try_send(event.clone()).is_err() {
                stale.push(*id);
            }
        }
        for id in stale {
            clients.remove(&id);
        }
    }

    pub fn client_count(&self) -> usize {
        self.clients
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .len()
    }
}

/// Runs one WebSocket connection until it closes or stops reading.
pub async fn run_client<S>(stream: S, mut receiver: mpsc::Receiver<Event>)
where
    S: futures_util::Sink<Message, Error = tokio_tungstenite::tungstenite::Error>
        + futures_util::Stream<Item = Result<Message, tokio_tungstenite::tungstenite::Error>>
        + Unpin
        + Send,
{
    let (mut sink, mut incoming) = stream.split();
    let mut ping = tokio::time::interval(Duration::from_secs(30));
    let mut idle = tokio::time::interval(Duration::from_secs(5));
    ping.tick().await;
    idle.tick().await;
    let mut last_read = Instant::now();

    loop {
        tokio::select! {
            event = receiver.recv() => {
                let Some(event) = event else {
                    let _ = sink.send(Message::Close(None)).await;
                    break;
                };
                let payload = serde_json::to_string(&event).unwrap_or_else(|_| "{}".to_string());
                if sink.send(Message::Text(payload.into())).await.is_err() {
                    break;
                }
            }
            message = incoming.next() => {
                match message {
                    Some(Ok(Message::Close(_))) | None => break,
                    Some(Ok(_)) => last_read = Instant::now(),
                    Some(Err(_)) => break,
                }
            }
            _ = ping.tick() => {
                if sink.send(Message::Ping(Vec::new().into())).await.is_err() {
                    break;
                }
            }
            _ = idle.tick() => {
                if last_read.elapsed() > Duration::from_secs(60) {
                    break;
                }
            }
        }
    }
}

/// One query event pushed to consoles.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueryEventData {
    pub domain: String,
    pub qtype: String,
    #[serde(rename = "clientIP")]
    pub client_ip: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub client_name: String,
    pub duration_ms: f64,
    pub success: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub rcode: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub cache_hit: String,
    pub blocked: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub filter_rule: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub filter_reason: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub error_message: String,
}

/// Observer installed into the DNS pipeline by the service binary.
pub struct DesktopQueryObserver {
    hub: Arc<WsHub>,
    querylog: Arc<QueryLog>,
    runtime: Arc<AppRuntime>,
    last_metrics: Mutex<Instant>,
    last_dns: Mutex<Instant>,
}

impl DesktopQueryObserver {
    pub fn new(hub: Arc<WsHub>, querylog: Arc<QueryLog>, runtime: Arc<AppRuntime>) -> Self {
        Self {
            hub,
            querylog,
            runtime,
            last_metrics: Mutex::new(Instant::now() - Duration::from_secs(10)),
            last_dns: Mutex::new(Instant::now() - Duration::from_secs(10)),
        }
    }
}

fn attribute_bool(ctx: &diting_desktop_dns::context::DnsContext, key: &str) -> bool {
    ctx.get(key)
        .map(|value| value == "true" || value == "1")
        .unwrap_or(false)
}

fn attribute(ctx: &diting_desktop_dns::context::DnsContext, key: &str) -> String {
    ctx.get(key).unwrap_or("").to_string()
}

fn rcode_name(ctx: &diting_desktop_dns::context::DnsContext) -> String {
    let Some(response) = ctx.response.as_ref() else {
        return String::new();
    };
    // DNS header: byte 3 holds the 4-bit RCODE in its low nibble.
    if response.len() < 4 {
        return String::new();
    }
    match response[3] & 0x0f {
        0 => "NOERROR".to_string(),
        1 => "FORMERR".to_string(),
        2 => "SERVFAIL".to_string(),
        3 => "NXDOMAIN".to_string(),
        4 => "NOTIMP".to_string(),
        5 => "REFUSED".to_string(),
        other => format!("RCODE{other}"),
    }
}

/// Extracts the fields shared by the query-log record and the WebSocket event.
struct QueryProjection {
    domain: String,
    qtype: String,
    client_ip: String,
    client_name: String,
    duration_ms: f64,
    rcode: String,
    cache_hit: String,
    blocked: bool,
    filter_rule: String,
    filter_reason: String,
    error: String,
    success: bool,
    status: &'static str,
    protocol: String,
}

fn project(ctx: &diting_desktop_dns::context::DnsContext) -> QueryProjection {
    let cache_hit = attribute(ctx, "cache_hit");
    let blocked = attribute_bool(ctx, "filter_blocked")
        || attribute_bool(ctx, "rebinding_blocked")
        || attribute_bool(ctx, "access_blocked")
        || attribute_bool(ctx, "ratelimit_blocked")
        || attribute_bool(ctx, "unqualified_blocked");
    let mut filter_rule = attribute(ctx, "filter_rule");
    if filter_rule.is_empty() {
        if attribute_bool(ctx, "rebinding_blocked") {
            filter_rule = "REBIND_PROTECTION".to_string();
        } else if attribute_bool(ctx, "access_blocked") {
            filter_rule = "CLIENT_ACCESS_CONTROL".to_string();
        } else if attribute_bool(ctx, "ratelimit_blocked") {
            filter_rule = "RATE_LIMIT_EXCEEDED".to_string();
        } else if attribute_bool(ctx, "unqualified_blocked") {
            filter_rule = "BLOCK_UNQUALIFIED".to_string();
        }
    }
    let rcode = rcode_name(ctx);
    let error = ctx.error.clone().unwrap_or_default();
    let success = error.is_empty() && rcode != "SERVFAIL";
    let status = if !error.is_empty() {
        STATUS_ERROR
    } else if blocked {
        STATUS_BLOCKED
    } else if cache_hit == "stale" {
        STATUS_STALE
    } else if !cache_hit.is_empty() {
        STATUS_CACHED
    } else {
        STATUS_ALLOWED
    };

    QueryProjection {
        domain: ctx.question.name.clone(),
        qtype: diting_desktop_core::cache::qtype_name(ctx.question.qtype),
        client_ip: ctx
            .client
            .map(|address| address.ip().to_string())
            .unwrap_or_default(),
        client_name: ctx.client_name.clone(),
        duration_ms: ctx.elapsed_ms(),
        rcode,
        cache_hit,
        blocked,
        filter_rule,
        filter_reason: attribute(ctx, "filter_reason"),
        error,
        success,
        status,
        protocol: ctx.transport.as_str().to_string(),
    }
}

impl QueryObserver for DesktopQueryObserver {
    fn observe(&self, ctx: &diting_desktop_dns::context::DnsContext) {
        let event = project(ctx);

        self.querylog.record(Record {
            timestamp: now_ms(),
            domain: event.domain.clone(),
            qtype: event.qtype.clone(),
            client_ip: event.client_ip.clone(),
            client_name: event.client_name.clone(),
            duration_ms: event.duration_ms,
            rcode: event.rcode.clone(),
            status: event.status.to_string(),
            cached: !event.cache_hit.is_empty(),
            ttl: ctx
                .response
                .as_ref()
                .and_then(|wire| diting_dns_wire::parse_response(wire))
                .and_then(|meta| meta.min_ttl),
            cache_hit: event.cache_hit.clone(),
            blocked: event.blocked,
            filter_rule: event.filter_rule.clone(),
            filter_reason: event.filter_reason.clone(),
            protocol: event.protocol.clone(),
            upstream_provider: attribute(ctx, "upstream_provider"),
            error: event.error.clone(),
        });

        self.hub.broadcast(Event::new(
            "query",
            serde_json::to_value(QueryEventData {
                domain: event.domain,
                qtype: event.qtype,
                client_ip: event.client_ip,
                client_name: event.client_name,
                duration_ms: event.duration_ms,
                success: event.success,
                rcode: event.rcode,
                cache_hit: event.cache_hit,
                blocked: event.blocked,
                filter_rule: event.filter_rule,
                filter_reason: event.filter_reason,
                error_message: event.error,
            })
            .unwrap_or(Value::Null),
        ));

        self.broadcast_throttled_metrics();
        self.broadcast_throttled_dns();
    }
}

impl DesktopQueryObserver {
    fn broadcast_throttled_metrics(&self) {
        let mut last = self
            .last_metrics
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if last.elapsed() < Duration::from_secs(2) {
            return;
        }
        *last = Instant::now();
        drop(last);
        self.hub.broadcast(Event::new(
            "metrics",
            serde_json::to_value(self.runtime.metrics_status()).unwrap_or(Value::Null),
        ));
    }

    fn broadcast_throttled_dns(&self) {
        let mut last = self
            .last_dns
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if last.elapsed() < Duration::from_secs(5) {
            return;
        }
        *last = Instant::now();
        drop(last);
        let state = if self.runtime.is_dns_running() {
            "running"
        } else {
            "stopped"
        };
        self.hub.broadcast(Event::new("dns", json!(state)));
    }
}

pub fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_desktop_api::config::Config;
    use diting_desktop_core::querylog::SearchQuery;
    use diting_desktop_dns::context::{DnsContext, Transport};
    use std::net::SocketAddr;

    fn query_wire(name: &str) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&0x1234u16.to_be_bytes());
        out.extend_from_slice(&0x0100u16.to_be_bytes());
        out.extend_from_slice(&1u16.to_be_bytes());
        out.extend_from_slice(&[0u8; 6]);
        for label in name.split('.') {
            out.push(label.len() as u8);
            out.extend_from_slice(label.as_bytes());
        }
        out.push(0);
        out.extend_from_slice(&1u16.to_be_bytes());
        out.extend_from_slice(&1u16.to_be_bytes());
        out
    }

    fn runtime(temp: &std::path::Path) -> Arc<AppRuntime> {
        let mut config = Config::default();
        config.query_log.file_enabled = false;
        config.query_log.data_dir = temp.join("querylog").to_string_lossy().into_owned();
        config.filter.data_dir = temp.join("filters").to_string_lossy().into_owned();
        Arc::new(AppRuntime::new(config))
    }

    #[test]
    fn observer_maps_context_into_a_query_log_record_and_event() {
        let temp = std::env::temp_dir().join(format!(
            "diting-observer-{}-{}",
            std::process::id(),
            now_ms()
        ));
        let runtime = runtime(&temp);
        let hub = Arc::new(WsHub::new());
        let (id, mut receiver) = hub.register();
        let observer = DesktopQueryObserver::new(
            Arc::clone(&hub),
            Arc::clone(&runtime.querylog),
            Arc::clone(&runtime),
        );

        let mut ctx = DnsContext::new(
            query_wire("ads.example.com"),
            Some(SocketAddr::from(([127, 0, 0, 1], 4242))),
            Transport::Udp,
        )
        .unwrap();
        ctx.client_name = "laptop".to_string();
        ctx.set("filter_blocked", "true");
        ctx.set("filter_rule", "||ads.example.com^");
        ctx.set("filter_reason", "blacklist");
        ctx.set("cache_hit", "fresh");
        ctx.reply_with_rcode(0);

        observer.observe(&ctx);

        let event = receiver.try_recv().expect("query event");
        assert_eq!(event.kind, "query");
        assert_eq!(event.data["domain"], "ads.example.com.");
        assert_eq!(event.data["qtype"], "A");
        assert_eq!(event.data["clientIP"], "127.0.0.1");
        assert_eq!(event.data["clientName"], "laptop");
        assert_eq!(event.data["filterRule"], "||ads.example.com^");
        assert_eq!(event.data["blocked"], true);

        let result = runtime.querylog.search(SearchQuery {
            domain: "ads.example.com".to_string(),
            limit: 10,
            ..SearchQuery::default()
        });
        assert_eq!(result.entries.len(), 1);
        let record = &result.entries[0];
        assert_eq!(record.status, STATUS_BLOCKED);
        assert_eq!(record.qtype, "A");
        assert_eq!(record.cache_hit, "fresh");
        assert_eq!(record.protocol, "udp");

        hub.unregister(id);
        let _ = std::fs::remove_dir_all(temp);
    }

    #[test]
    fn slow_clients_are_dropped_without_blocking() {
        let hub = WsHub::new();
        let (_id, _receiver) = hub.register();
        for _ in 0..100 {
            hub.broadcast(Event::new("query", json!(1)));
        }
        assert_eq!(hub.client_count(), 0);
    }
}
