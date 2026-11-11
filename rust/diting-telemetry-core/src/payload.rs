//! The binary layouts shared with `android/engine/telemetry_native*.go`.
//!
//! Log row (a push request, and one element of a drain response):
//!
//! ```text
//! u8 blocked | u8 cached | i32 query_type | i64 response_time_ms | i64 timestamp_ms | i64 ttl
//! text domain | text app_name | text resolved_ips | text blocked_by | text error_message
//! ```
//!
//! Push request: `u8 layout` then one row. Drain response: `u8 layout | u32 count` then the rows.
//! Tick response: `u8 layout | u32 count` then `(i32 uid | u64 tx | u64 rx)` per row.
//!
//! Flow key (lookup, and store with a trailing `i32 uid`):
//!
//! ```text
//! u8 layout | u8 app_len | app bytes | u8 server_len | server bytes
//! i32 app_port | i32 server_port | i32 protocol | i64 now_ns [| i32 uid]
//! ```
//!
//! `text` is `u32 length | bytes`. Every field is little-endian, a drifted version byte, a length
//! that disagrees with the payload or a trailing byte is a hard error, and text is decoded lossily:
//! Go's `encoding/json` already replaced invalid UTF-8 with U+FFFD, so a lossy decode cannot change
//! what Kotlin sees.

use crate::logagg::LogItem;
use crate::traffic::Delta;
use crate::uidcache::{Addr, FlowKey};

/// Must match `telemetryLogPayloadLayoutVersion` / `telemetryKeyPayloadLayoutVersion` in Go.
pub const LAYOUT_VERSION: u8 = 1;

struct Reader<'a> {
    payload: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(payload: &'a [u8]) -> Option<Self> {
        if payload.first().copied()? != LAYOUT_VERSION {
            return None;
        }
        Some(Self {
            payload,
            position: 1,
        })
    }

    fn take(&mut self, length: usize) -> Option<&'a [u8]> {
        if self.payload.len() - self.position < length {
            return None;
        }
        let slice = &self.payload[self.position..self.position + length];
        self.position += length;
        Some(slice)
    }

    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }

    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }

    fn i32(&mut self) -> Option<i32> {
        Some(i32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }

    fn u64(&mut self) -> Option<u64> {
        Some(u64::from_le_bytes(self.take(8)?.try_into().ok()?))
    }

    fn i64(&mut self) -> Option<i64> {
        Some(i64::from_le_bytes(self.take(8)?.try_into().ok()?))
    }

    /// `u32 length` then that many bytes, as UTF-8 with invalid sequences replaced.
    fn text(&mut self) -> Option<String> {
        let length = self.u32()? as usize;
        let bytes = self.take(length)?;
        Some(String::from_utf8_lossy(bytes).into_owned())
    }

    fn finished(&self) -> bool {
        self.position == self.payload.len()
    }

    fn item(&mut self) -> Option<LogItem> {
        let blocked = self.u8()? != 0;
        let cached = self.u8()? != 0;
        let query_type = self.i32()?;
        let response_time_ms = self.i64()?;
        let timestamp_ms = self.i64()?;
        let ttl = self.i64()?;
        let domain = self.text()?;
        let app_name = self.text()?;
        let resolved_ips = self.text()?;
        let blocked_by = self.text()?;
        let error_message = self.text()?;
        Some(LogItem {
            domain,
            blocked,
            query_type,
            response_time_ms,
            app_name,
            resolved_ips,
            blocked_by,
            error_message,
            cached,
            timestamp_ms,
            ttl,
        })
    }
}

fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

fn put_item(out: &mut Vec<u8>, item: &LogItem) {
    out.push(u8::from(item.blocked));
    out.push(u8::from(item.cached));
    out.extend_from_slice(&item.query_type.to_le_bytes());
    out.extend_from_slice(&item.response_time_ms.to_le_bytes());
    out.extend_from_slice(&item.timestamp_ms.to_le_bytes());
    out.extend_from_slice(&item.ttl.to_le_bytes());
    put_text(out, &item.domain);
    put_text(out, &item.app_name);
    put_text(out, &item.resolved_ips);
    put_text(out, &item.blocked_by);
    put_text(out, &item.error_message);
}

/// Decodes one push request (used by the FFI, and by the Go layout tests through the same shape).
pub fn decode_log_push(payload: &[u8]) -> Option<LogItem> {
    let mut reader = Reader::new(payload)?;
    let item = reader.item()?;
    if !reader.finished() {
        return None;
    }
    Some(item)
}

/// Encodes a push request; the Go layout tests build the same bytes.
pub fn encode_log_push(item: &LogItem) -> Vec<u8> {
    let mut out = Vec::with_capacity(96);
    out.push(LAYOUT_VERSION);
    put_item(&mut out, item);
    out
}

/// Encodes the rows a drain returned.
pub fn encode_log_batch(items: &[LogItem]) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + 4 + items.len() * 96);
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&(items.len() as u32).to_le_bytes());
    for item in items {
        put_item(&mut out, item);
    }
    out
}

/// Decodes a drain response.
pub fn decode_log_batch(payload: &[u8]) -> Option<Vec<LogItem>> {
    let mut reader = Reader::new(payload)?;
    let count = reader.u32()? as usize;
    let mut items = Vec::with_capacity(count.min(64));
    for _ in 0..count {
        items.push(reader.item()?);
    }
    if !reader.finished() {
        return None;
    }
    Some(items)
}

/// Encodes one tick response.
pub fn encode_traffic_tick(deltas: &[Delta]) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + 4 + deltas.len() * 20);
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&(deltas.len() as u32).to_le_bytes());
    for delta in deltas {
        out.extend_from_slice(&delta.uid.to_le_bytes());
        out.extend_from_slice(&delta.tx.to_le_bytes());
        out.extend_from_slice(&delta.rx.to_le_bytes());
    }
    out
}

/// Decodes one tick response.
pub fn decode_traffic_tick(payload: &[u8]) -> Option<Vec<Delta>> {
    let mut reader = Reader::new(payload)?;
    let count = reader.u32()? as usize;
    let mut deltas = Vec::with_capacity(count.min(64));
    for _ in 0..count {
        deltas.push(Delta {
            uid: reader.i32()?,
            tx: reader.u64()?,
            rx: reader.u64()?,
        });
    }
    if !reader.finished() {
        return None;
    }
    Some(deltas)
}

/// Decodes a flow lookup request: the key plus the caller's clock.
pub fn decode_flow_lookup(payload: &[u8]) -> Option<(FlowKey, i64)> {
    let mut reader = Reader::new(payload)?;
    let app = read_addr(&mut reader)?;
    let server = read_addr(&mut reader)?;
    let app_port = reader.i32()?;
    let server_port = reader.i32()?;
    let protocol = reader.i32()?;
    let now_ns = reader.i64()?;
    if !reader.finished() {
        return None;
    }
    Some((
        FlowKey::new(app, app_port, server, server_port, protocol),
        now_ns,
    ))
}

/// Decodes a flow store request: the lookup payload plus the resolved UID.
pub fn decode_flow_store(payload: &[u8]) -> Option<(FlowKey, i64, i32)> {
    let mut reader = Reader::new(payload)?;
    let app = read_addr(&mut reader)?;
    let server = read_addr(&mut reader)?;
    let app_port = reader.i32()?;
    let server_port = reader.i32()?;
    let protocol = reader.i32()?;
    let now_ns = reader.i64()?;
    let uid = reader.i32()?;
    if !reader.finished() {
        return None;
    }
    Some((
        FlowKey::new(app, app_port, server, server_port, protocol),
        now_ns,
        uid,
    ))
}

/// Encodes a flow lookup/store request; the Go layout tests build the same bytes.
pub fn encode_flow_key(key: &FlowKey, now_ns: i64, uid: Option<i32>) -> Vec<u8> {
    let mut out = Vec::with_capacity(64);
    out.push(LAYOUT_VERSION);
    for address in [key.app, key.server] {
        out.push(address.as_bytes().len() as u8);
        out.extend_from_slice(address.as_bytes());
    }
    out.extend_from_slice(&(key.app_port as i32).to_le_bytes());
    out.extend_from_slice(&(key.server_port as i32).to_le_bytes());
    out.extend_from_slice(&(key.protocol as i32).to_le_bytes());
    out.extend_from_slice(&now_ns.to_le_bytes());
    if let Some(uid) = uid {
        out.extend_from_slice(&uid.to_le_bytes());
    }
    out
}

fn read_addr(reader: &mut Reader<'_>) -> Option<Addr> {
    let length = reader.u8()? as usize;
    if length != 4 && length != 16 {
        return None;
    }
    Addr::from_bytes(reader.take(length)?)
}

#[cfg(test)]
mod tests;
