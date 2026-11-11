//! Payload codecs for the JNI entry points: decode one request, run one piece of log logic, encode
//! the answer.
//!
//! Keeping this out of [`crate::jni`] means every layout can be unit-tested without a JVM.
//! A decoder returns None on any drift (short read, unknown tag, trailing bytes), which the bridge
//! turns into a null `ByteArray` and Kotlin turns into an `IllegalStateException`.
//!
//! The modules follow the Kotlin side: this file the four log tables, [`policy`] the retention sweep
//! and the crash buffer, [`state`] the counters, buckets, write health and attribution caches,
//! [`queue`] the writer queues, and [`runtime`] the runtime-log capture, its files and the
//! `dns_cache` projection.

pub mod policy;
pub mod queue;
pub mod runtime;
pub mod state;

pub use policy::{crash_select, retention_plan};
pub use queue::{queue_requeue, queue_settings, queue_submit, queue_take};
pub use runtime::{
    capture_line, capture_plan, mirror_layout, mirror_rows, store_document, store_index,
};
pub use state::{
    attr_package_lookup, attr_uid_lookup, attr_uid_store, health_dropped, health_snapshot,
    rate_snapshot, stats_snapshot, traffic_on_tick, traffic_requeue, traffic_take, warn_answer,
};

use crate::payload::{Reader, Writer};
use crate::row::{
    bootstrap_row, dns_row, http_row, normalized_outcome, race_row, BootstrapInput, BootstrapRow,
    DnsInput, DnsRow, HttpInput, HttpRow, LogMode, RaceInput, RaceRow,
};
use crate::stats::Stats;

// ---------------------------------------------------------------------------------------------
// Optional-field helpers (a presence byte keeps NULL apart from "")
// ---------------------------------------------------------------------------------------------

pub(crate) fn write_optional(writer: &mut Writer, value: Option<&str>) {
    match value {
        Some(text) => {
            writer.u8(1);
            writer.string(text);
        }
        None => writer.u8(0),
    }
}

#[cfg(test)]
pub(crate) fn read_optional(reader: &mut Reader<'_>) -> Option<Option<String>> {
    match reader.u8()? {
        0 => Some(None),
        1 => Some(Some(reader.string()?)),
        _ => None,
    }
}

pub(crate) fn write_optional_i64(writer: &mut Writer, value: Option<i64>) {
    match value {
        Some(number) => {
            writer.u8(1);
            writer.i64(number);
        }
        None => writer.u8(0),
    }
}

// ---------------------------------------------------------------------------------------------
// DNS batch: counters for every row, `dns_log` rows for the ones the mode keeps
// ---------------------------------------------------------------------------------------------

fn decode_dns_input(reader: &mut Reader<'_>) -> Option<DnsInput> {
    Some(DnsInput {
        timestamp: reader.i64()?,
        domain: reader.string()?,
        query_type: reader.i32()?,
        blocked: reader.u8()? != 0,
        blocked_by: reader.string()?,
        error: reader.string()?,
        cached: reader.u8()? != 0,
        app: reader.string()?,
        resolved: reader.string()?,
        elapsed_ms: reader.i64()?,
    })
}

/// `u32 count` then the rows; answers with the rows `dns_log` should receive, each one already in
/// the layout the writer queue carries.
///
/// The counters are fed from every row *before* the mode filter, because the notification shows
/// requests with logging switched off too.
pub fn dns_batch(stats: &Stats, mode: LogMode, payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut inputs = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        inputs.push(decode_dns_input(&mut reader)?);
    }
    if !reader.finish() {
        return None;
    }

    for input in &inputs {
        stats.record_dns(input);
    }
    if mode == LogMode::Off {
        // Counted, not logged: the notification still shows requests while logging is off.
        return Some(Writer::new().into_vec());
    }

    let rows: Vec<DnsRow> = inputs
        .iter()
        .filter_map(|input| dns_row(input, mode, now_ms))
        .collect();

    let mut writer = Writer::new();
    writer.u32(rows.len() as u32);
    for row in rows {
        // `u32 count | rows(u32 length | bytes)`, the same packing the writer queues carry, so
        // Kotlin only unpacks each blob into `dns_log` columns.
        writer.blob(&pack_dns_row(&row));
    }
    Some(writer.into_vec())
}

fn pack_dns_row(row: &DnsRow) -> Vec<u8> {
    let mut writer = Writer::new();
    writer.i64(row.timestamp);
    writer.string(&row.query_name);
    writer.i32(row.query_type);
    // The name, not the tag: these bytes are also the row the writer queue carries.
    writer.string(row.result.as_str());
    write_optional(&mut writer, row.message.as_deref());
    writer.u8(if row.cached { 1 } else { 0 });
    write_optional_i64(&mut writer, row.block_subscription_id);
    write_optional(&mut writer, row.package_name.as_deref());
    writer.into_vec()
}

// ---------------------------------------------------------------------------------------------
// HTTP / race / bootstrap rows
// ---------------------------------------------------------------------------------------------

/// One MITM event; answers with the row, or nothing when the mode hides it.
pub fn http_event(stats: &Stats, mode: LogMode, payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let input = HttpInput {
        package_name: reader.string()?,
        authority: reader.string()?,
        protocol: reader.string()?,
        outcome: reader.string()?,
        matched_rule: reader.string()?,
    };
    if !reader.finish() {
        return None;
    }

    // The counters see the blank-defaulted outcome even when the row is filtered.
    stats.record_http(&normalized_outcome(&input.outcome));

    match http_row(&input, mode, now_ms) {
        None => Some(Vec::new()),
        Some(row) => {
            let mut writer = Writer::new();
            write_http_row(&mut writer, &row);
            Some(writer.into_vec())
        }
    }
}

fn write_http_row(writer: &mut Writer, row: &HttpRow) {
    writer.i64(row.timestamp);
    writer.string(&row.package_name);
    write_optional(writer, row.authority.as_deref());
    writer.string(&row.protocol);
    writer.string(&row.outcome);
    write_optional(writer, row.matched_rule.as_deref());
}

/// One race result; answers with the row, or nothing when there is no query name.
pub fn race(payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let input = RaceInput {
        query_name: reader.string()?,
        query_type: reader.i32()?,
        strategy: reader.string()?,
        provider_count: reader.i32()?,
        success: reader.u8()? != 0,
        elapsed_ms: reader.i64()?,
        selected_provider_id: reader.string()?,
        selected_elapsed_ms: reader.i64()?,
        winner_provider_id: reader.string()?,
        winner_elapsed_ms: reader.i64()?,
        fallback_used: reader.u8()? != 0,
        fallback_success: reader.u8()? != 0,
        error_message: reader.string()?,
    };
    if !reader.finish() {
        return None;
    }

    match race_row(&input, now_ms) {
        None => Some(Vec::new()),
        Some(row) => {
            let mut writer = Writer::new();
            write_race_row(&mut writer, &row);
            Some(writer.into_vec())
        }
    }
}

fn write_race_row(writer: &mut Writer, row: &RaceRow) {
    writer.i64(row.timestamp);
    writer.string(&row.query_name);
    writer.i32(row.query_type);
    writer.string(&row.strategy);
    writer.i32(row.provider_count);
    writer.u8(if row.success { 1 } else { 0 });
    writer.i64(row.elapsed_ms);
    write_optional(writer, row.selected_provider_id.as_deref());
    write_optional_i64(writer, row.selected_elapsed_ms);
    write_optional(writer, row.winner_provider_id.as_deref());
    write_optional_i64(writer, row.winner_elapsed_ms);
    writer.u8(if row.fallback_used { 1 } else { 0 });
    writer.u8(if row.fallback_success { 1 } else { 0 });
    write_optional(writer, row.message.as_deref());
}

/// One bootstrap probe; answers with the row, or nothing when the host is blank.
pub fn bootstrap(payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let input = BootstrapInput {
        ip_id: reader.string()?,
        ip_name: reader.string()?,
        ip: reader.string()?,
        host: reader.string()?,
        success: reader.u8()? != 0,
        elapsed_ms: reader.i64()?,
        fallback_used: reader.u8()? != 0,
        error_message: reader.string()?,
    };
    if !reader.finish() {
        return None;
    }

    match bootstrap_row(&input, now_ms) {
        None => Some(Vec::new()),
        Some(row) => {
            let mut writer = Writer::new();
            write_bootstrap_row(&mut writer, &row);
            Some(writer.into_vec())
        }
    }
}

fn write_bootstrap_row(writer: &mut Writer, row: &BootstrapRow) {
    writer.i64(row.timestamp);
    writer.string(&row.ip_id);
    writer.string(&row.ip_name);
    writer.string(&row.ip);
    writer.string(&row.host);
    writer.u8(if row.success { 1 } else { 0 });
    writer.i64(row.elapsed_ms);
    writer.u8(if row.fallback_used { 1 } else { 0 });
    write_optional(writer, row.message.as_deref());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text_payload(values: &[&str]) -> Vec<u8> {
        let mut writer = Writer::new();
        for value in values {
            writer.string(value);
        }
        writer.into_vec()
    }

    /// Splits a `u32 count | rows(u32 length | bytes)` answer, the way Kotlin reads it.
    fn split_rows(payload: &[u8]) -> Vec<Vec<u8>> {
        let mut reader = Reader::new(payload);
        let count = reader.u32().unwrap() as usize;
        let mut rows = Vec::with_capacity(count);
        for _ in 0..count {
            rows.push(reader.blob().unwrap().to_vec());
        }
        assert!(reader.finish());
        rows
    }

    #[test]
    fn dns_batch_counts_every_row_and_keeps_the_mode_filter() {
        let stats = Stats::new();
        let mut writer = Writer::new();
        writer.u32(2);
        // Passed row.
        writer.i64(0);
        writer.string("Example.com");
        writer.i32(1);
        writer.u8(0);
        writer.string("");
        writer.string("");
        writer.u8(1);
        writer.string("com.app");
        writer.string("1.2.3.4");
        writer.i64(5);
        // Blocked row without a subscription id.
        writer.i64(100);
        writer.string("ads.example");
        writer.i32(1);
        writer.u8(1);
        writer.string("firewall:2");
        writer.string("");
        writer.u8(0);
        writer.string("");
        writer.string("");
        writer.i64(0);
        let payload = writer.into_vec();

        let all = dns_batch(&stats, LogMode::All, &payload, 7).unwrap();
        let rows = split_rows(&all);
        assert_eq!(rows.len(), 2);

        let mut reader = Reader::new(&rows[0]);
        assert_eq!(reader.i64(), Some(7));
        assert_eq!(reader.string().as_deref(), Some("example.com"));
        assert_eq!(reader.i32(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("PASSED"));
        assert_eq!(
            read_optional(&mut reader),
            Some(Some("app=com.app, resolved=1.2.3.4, elapsed=5ms".into()))
        );
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(read_optional_i(&mut reader), Some(None));
        assert_eq!(read_optional(&mut reader), Some(Some("com.app".into())));
        assert!(reader.finish());

        let mut reader = Reader::new(&rows[1]);
        assert_eq!(reader.i64(), Some(100));
        assert_eq!(reader.string().as_deref(), Some("ads.example"));
        assert_eq!(reader.i32(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("BLOCKED"));
        assert_eq!(
            read_optional(&mut reader),
            Some(Some("blocked_by=firewall:2".into()))
        );
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(read_optional_i(&mut reader), Some(None));
        assert_eq!(read_optional(&mut reader), Some(None));
        assert!(reader.finish());

        // Only the first row is a query: the counters keep `firewall:` lines out.
        assert_eq!(stats.request_snapshot().total, 1);
        assert_eq!(stats.request_snapshot().passed, 1);
        assert_eq!(stats.request_snapshot().cached, 1);

        let blocked_only = dns_batch(&stats, LogMode::BlockedAndErrors, &payload, 7).unwrap();
        let rows = split_rows(&blocked_only);
        assert_eq!(rows.len(), 1);
        let mut reader = Reader::new(&rows[0]);
        assert_eq!(reader.i64(), Some(100));
        assert_eq!(reader.string().as_deref(), Some("ads.example"));
        // Same payload again: the counters are per batch, so the query counts once more.
        assert_eq!(stats.request_snapshot().total, 2);

        // MODE_OFF still counts but logs nothing.
        let off = dns_batch(&stats, LogMode::Off, &payload, 7).unwrap();
        assert!(off.is_empty());
        assert_eq!(stats.request_snapshot().total, 3);
    }

    fn read_optional_i(reader: &mut Reader<'_>) -> Option<Option<i64>> {
        match reader.u8()? {
            0 => Some(None),
            1 => Some(Some(reader.i64()?)),
            _ => None,
        }
    }

    #[test]
    fn http_event_answers_nothing_when_the_mode_hides_it() {
        let stats = Stats::new();
        let mut writer = Writer::new();
        writer.string("");
        writer.string("");
        writer.string("");
        writer.string("allowed");
        writer.string("");
        let payload = writer.into_vec();
        assert_eq!(
            http_event(&stats, LogMode::BlockedAndErrors, &payload, 1),
            Some(Vec::new())
        );
        // The counters were fed anyway: the notification ignores the log mode.
        assert_eq!(stats.request_snapshot().passed, 1);

        let all = http_event(&stats, LogMode::All, &payload, 1).unwrap();
        let mut reader = Reader::new(&all);
        assert_eq!(reader.i64(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("unknown"));
        assert_eq!(read_optional(&mut reader), Some(None));
        assert_eq!(reader.string().as_deref(), Some(""));
        assert_eq!(reader.string().as_deref(), Some("allowed"));
        assert_eq!(read_optional(&mut reader), Some(None));
        assert!(reader.finish());
    }

    #[test]
    fn optional_helpers_reject_unknown_presence_tags() {
        let mut reader = Reader::new(&[2]);
        assert_eq!(read_optional(&mut reader), None);
        let mut reader = Reader::new(&[2]);
        assert_eq!(read_optional_i(&mut reader), None);
        let _ = text_payload(&["x"]);
    }
}
