//! JSON request decoding for the C ABI. Requests are JSON objects; a missing or mistyped required
//! field is rejected rather than defaulted, so a drifted caller fails loudly.

use serde_json::Value;

use crate::session::{FlowEvent, FlowKey, FlowStatus};

fn text(value: &Value, field: &str) -> String {
    value
        .get(field)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

fn u64_of(value: &Value, field: &str) -> u64 {
    value.get(field).and_then(Value::as_u64).unwrap_or(0)
}

fn i64_of(value: &Value, field: &str) -> i64 {
    value
        .get(field)
        .and_then(|v| v.as_i64().or_else(|| v.as_u64().map(|n| n as i64)))
        .unwrap_or(0)
}

fn u16_of(value: &Value, field: &str) -> u16 {
    value.get(field).and_then(Value::as_u64).unwrap_or(0) as u16
}

fn i32_of(value: &Value, field: &str) -> i32 {
    value
        .get(field)
        .and_then(|v| v.as_i64().or_else(|| v.as_u64().map(|n| n as i64)))
        .unwrap_or(0) as i32
}

/// Decodes one flow event; requires the `key.protocol` field so a garbage payload is rejected.
pub fn decode_event(request: &Value) -> Option<FlowEvent> {
    let key = request.get("key")?;
    let protocol = key.get("protocol")?.as_str()?.to_string();
    Some(FlowEvent {
        key: FlowKey {
            protocol,
            src_ip: text(key, "srcIp"),
            src_port: u16_of(key, "srcPort"),
            dst_ip: text(key, "dstIp"),
            dst_port: u16_of(key, "dstPort"),
            uid: i32_of(key, "uid"),
        },
        domain: text(request, "domain"),
        package: text(request, "package"),
        up_delta: u64_of(request, "upDelta"),
        down_delta: u64_of(request, "downDelta"),
        status: FlowStatus::parse(&text(request, "status")),
        at_ms: i64_of(request, "atMs"),
    })
}

pub fn since_seq(request: &Value) -> u64 {
    u64_of(request, "sinceSeq")
}

pub fn limit(request: &Value) -> usize {
    u64_of(request, "limit") as usize
}
