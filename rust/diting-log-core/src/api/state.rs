//! The counter, bucket, write-health and attribution-cache payloads.

use crate::attr::{FlowKey, PackageLookup};
use crate::health::{DropReason, HealthSnapshot};
use crate::payload::{Reader, Writer};
use crate::stats::{RequestSnapshot, Stats};
use crate::traffic::{TickRow, Traffic};

// ---------------------------------------------------------------------------------------------
// Counters and caches
// ---------------------------------------------------------------------------------------------

/// Six counters in `RequestSnapshot` field order.
pub fn stats_snapshot(stats: &Stats) -> Vec<u8> {
    let snapshot: RequestSnapshot = stats.request_snapshot();
    let mut writer = Writer::new();
    for value in [
        snapshot.total,
        snapshot.passed,
        snapshot.filtered,
        snapshot.cached,
        snapshot.rewritten,
        snapshot.failed,
    ] {
        writer.i64(value);
    }
    writer.into_vec()
}

/// The two rates, `tx_bps` then `rx_bps`; a stale link (no tick for a while) answers zeros.
pub fn rate_snapshot(stats: &Stats, now_ms: i64) -> Vec<u8> {
    let (tx_bps, rx_bps) = stats.rate_snapshot(now_ms);
    let mut writer = Writer::new();
    writer.i64(tx_bps);
    writer.i64(rx_bps);
    writer.into_vec()
}

fn decode_tick_rows(reader: &mut Reader<'_>) -> Option<Vec<TickRow>> {
    let count = reader.u32()? as usize;
    let mut rows = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        rows.push(TickRow {
            uid: reader.i32()?,
            tx: reader.i64()?,
            rx: reader.i64()?,
            package: reader.string()?,
        });
    }
    Some(rows)
}

/// `string date | u32 count | rows(uid, tx, rx, package)`.
pub fn traffic_on_tick(traffic: &Traffic, payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let date = reader.string()?;
    let rows = decode_tick_rows(&mut reader)?;
    if !reader.finish() {
        return None;
    }

    let outcome = traffic.on_tick(&date, &rows);
    let mut writer = Writer::new();
    let mut flags = 0u8;
    if outcome.flush {
        flags |= 1;
    }
    if outcome.dropped_date.is_some() {
        flags |= 2;
    }
    writer.u8(flags);
    writer.i64(outcome.tick_tx);
    writer.i64(outcome.tick_rx);
    writer.string(outcome.dropped_date.as_deref().unwrap_or(""));
    writer.u32(outcome.dropped_packages);
    Some(writer.into_vec())
}

/// The pending buckets, in the layout [`traffic_requeue`] accepts back.
pub fn traffic_take(traffic: &Traffic) -> Vec<u8> {
    let buckets = traffic.take();
    let mut writer = Writer::new();
    writer.u32(buckets.len() as u32);
    for (date, rows) in buckets {
        writer.string(&date);
        writer.u32(rows.len() as u32);
        for (package, delta) in rows {
            writer.string(&package);
            writer.i64(delta.tx);
            writer.i64(delta.rx);
        }
    }
    writer.into_vec()
}

/// Puts a failed batch back; the payload is exactly what [`traffic_take`] answered.
pub fn traffic_requeue(traffic: &Traffic, payload: &[u8]) -> Option<()> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut failed = Vec::with_capacity(count.min(64));
    for _ in 0..count {
        let date = reader.string()?;
        let row_count = reader.u32()? as usize;
        let mut rows = Vec::with_capacity(row_count.min(4096));
        for _ in 0..row_count {
            rows.push((
                reader.string()?,
                crate::traffic::Delta {
                    tx: reader.i64()?,
                    rx: reader.i64()?,
                },
            ));
        }
        failed.push((date, rows));
    }
    if !reader.finish() {
        return None;
    }
    traffic.requeue(failed);
    Some(())
}

/// `protocol | localIP | localPort | remoteIP | remotePort`, the Kotlin cache key.
fn decode_flow_key(reader: &mut Reader<'_>) -> Option<FlowKey> {
    Some(FlowKey {
        protocol: reader.i64()?,
        local_ip: reader.string()?,
        local_port: reader.i64()?,
        remote_ip: reader.string()?,
        remote_port: reader.i64()?,
    })
}

/// One cache read; answers with `u8 hit` and, on a hit, the UID.
pub fn attr_uid_lookup(attr: &crate::attr::Attr, payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let key = decode_flow_key(&mut reader)?;
    if !reader.finish() {
        return None;
    }
    let mut writer = Writer::new();
    match attr.lookup_uid(&key, now_ms) {
        Some(uid) => {
            writer.u8(1);
            writer.i32(uid);
        }
        None => writer.u8(0),
    }
    Some(writer.into_vec())
}

/// One cache write: `packed key | i32 uid`.
pub fn attr_uid_store(
    attr: &crate::attr::Attr,
    payload: &[u8],
    uid: i32,
    now_ms: i64,
) -> Option<()> {
    let mut reader = Reader::new(payload);
    let key = decode_flow_key(&mut reader)?;
    if !reader.finish() {
        return None;
    }
    attr.store_uid(key, uid, now_ms);
    Some(())
}

/// One package read; answers with `u8 status` (0 miss, 1 hit, 2 not a known UID) and the name.
pub fn attr_package_lookup(attr: &crate::attr::Attr, uid: i32) -> Vec<u8> {
    let mut writer = Writer::new();
    match attr.lookup_package(uid) {
        PackageLookup::Hit(name) => {
            writer.u8(1);
            writer.string(&name);
        }
        PackageLookup::Miss => {
            writer.u8(0);
            writer.string("");
        }
        PackageLookup::NotKnown => {
            writer.u8(2);
            writer.string("");
        }
    }
    writer.into_vec()
}

/// `i32 rows | u8 reason | string table`.
pub fn health_dropped(payload: &[u8]) -> Option<(i32, DropReason, String)> {
    let mut reader = Reader::new(payload);
    let rows = reader.i32()?;
    let reason = DropReason::from_tag(reader.u8()?)?;
    let table = reader.string()?;
    if !reader.finish() {
        return None;
    }
    Some((rows, reason, table))
}

/// `u8 hasLine | string line`: the one warning this window allows, if any.
pub fn warn_answer(answer: Option<String>) -> Vec<u8> {
    let mut writer = Writer::new();
    match answer {
        Some(line) => {
            writer.u8(1);
            writer.string(&line);
        }
        None => writer.u8(0),
    }
    writer.into_vec()
}

/// The counters the diagnostics channel exposes; the reason keys travel with their counts so the
/// Kotlin side never has to spell them a second time.
pub fn health_snapshot(snapshot: &HealthSnapshot) -> Vec<u8> {
    let mut writer = Writer::new();
    writer.i64(snapshot.dropped_rows);
    for (reason, count) in DropReason::ALL.iter().zip(snapshot.dropped_by_reason) {
        writer.string(reason.key());
        writer.i64(count);
    }
    writer.string(&snapshot.last_drop);
    writer.i64(snapshot.open_failures);
    writer.i64(snapshot.suppressed);
    writer.string(&snapshot.last_cause);
    writer.into_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn traffic_take_and_requeue_share_a_layout() {
        let traffic = Traffic::new();
        let mut writer = Writer::new();
        writer.string("2026-01-01");
        writer.u32(1);
        writer.i32(10001);
        writer.i64(10);
        writer.i64(20);
        writer.string("com.a");
        let payload = traffic_on_tick(&traffic, &writer.into_vec()).unwrap();
        let mut reader = Reader::new(&payload);
        assert_eq!(reader.u8(), Some(0)); // no flush, nothing dropped
        assert_eq!(reader.i64(), Some(10));
        assert_eq!(reader.i64(), Some(20));
        assert_eq!(reader.string().as_deref(), Some(""));
        assert_eq!(reader.u32(), Some(0));
        assert!(reader.finish());

        let taken = traffic_take(&traffic);
        assert!(traffic_requeue(&traffic, &taken).is_some());
        assert_eq!(traffic.buffered_bytes(), 30);
        assert_eq!(traffic_take(&traffic), taken);
    }

    #[test]
    fn the_health_snapshot_carries_its_reason_keys() {
        let health = crate::health::Health::new();
        // The window starts at 0, so a `now` inside the first minute would suppress the report.
        health.on_dropped(4, DropReason::TableMissing, "dns_log", 1_700_000_000_000);
        let payload = health_snapshot(&health.snapshot());
        let mut reader = Reader::new(&payload);
        assert_eq!(reader.i64(), Some(4));
        assert_eq!(reader.string().as_deref(), Some("overflow"));
        assert_eq!(reader.i64(), Some(0));
        assert_eq!(reader.string().as_deref(), Some("tableMissing"));
        assert_eq!(reader.i64(), Some(4));
        assert_eq!(reader.string().as_deref(), Some("noDatabase"));
        assert_eq!(reader.i64(), Some(0));
        assert_eq!(reader.string().as_deref(), Some("closed"));
        assert_eq!(reader.i64(), Some(0));
        assert_eq!(reader.string().as_deref(), Some("dns_log:tableMissing"));
        assert_eq!(reader.i64(), Some(0));
        assert_eq!(reader.i64(), Some(0));
        assert_eq!(reader.string().as_deref(), Some(""));
        assert!(reader.finish());
    }

    #[test]
    fn warn_answers_a_presence_flag() {
        assert_eq!(warn_answer(None), vec![0]);
        let payload = warn_answer(Some("dropped 1 row(s)".into()));
        let mut reader = Reader::new(&payload);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("dropped 1 row(s)"));
    }
}
