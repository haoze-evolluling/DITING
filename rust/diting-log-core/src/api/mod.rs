//! Payload codecs for the JNI entry points: decode one request, run one piece of log logic, encode
//! the answer.
//!
//! Keeping this out of [`crate::jni`] means every layout can be unit-tested without a JVM.
//! A decoder returns None on any drift (short read, unknown tag, trailing bytes), which the bridge
//! turns into a null `ByteArray` and Kotlin turns into an `IllegalStateException`.
//!
//! The modules follow the Kotlin side: this file the HTTP/race/bootstrap rows, [`dns`] the DNS
//! batch and its combined classify-and-enqueue call, [`policy`] the retention sweep and the crash
//! buffer, [`state`] the counters, buckets, write health and attribution caches, [`queue`] the
//! writer queues, and [`runtime`] the runtime-log capture, its files and the `dns_cache` projection.

pub mod dns;
pub mod policy;
pub mod queue;
pub mod runtime;
pub mod state;

pub use dns::{dns_batch, dns_batch_submit};
pub use policy::{crash_select, retention_plan};
pub use queue::{queue_requeue, queue_settings, queue_submit, queue_submit_many, queue_take};
pub use runtime::{
    capture_line, capture_plan, mirror_layout, mirror_rows, runtime_event_line, store_document,
    store_index,
};
pub use state::{
    attr_package_lookup, attr_uid_lookup, attr_uid_store, health_dropped, health_snapshot,
    rate_snapshot, stats_snapshot, traffic_on_tick, traffic_requeue, traffic_take, warn_answer,
};

use crate::payload::{Reader, Writer};
use crate::queue::Queue;
use crate::row::{
    bootstrap_row, http_row, normalized_outcome, race_row, BootstrapInput, BootstrapRow, HttpInput,
    HttpRow, LogMode, RaceInput, RaceRow,
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

/// One batch of MITM events: counters, classification and the writer queue in a single call.
///
/// The engine hands Kotlin a packed batch of `(package, authority, protocol, outcome, rule)`
/// tuples; this entry point decodes all of them before touching the counters, records the outcome
/// of every row, turns the rows the log mode keeps into queue entries and enqueues them under one
/// lock. Answers:
///
/// ```text
/// u8 0  queue closed, nothing enqueued
/// u8 1  nothing enqueued (the mode hid every row)
/// u8 2  u32 overflow | u8 batch_full | i64 flush_delay_ms
/// ```
pub fn http_event_batch(
    stats: &Stats,
    queue: &Queue,
    mode: LogMode,
    payload: &[u8],
    now_ms: i64,
) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut inputs = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        inputs.push(HttpInput {
            package_name: reader.string()?,
            authority: reader.string()?,
            protocol: reader.string()?,
            outcome: reader.string()?,
            matched_rule: reader.string()?,
        });
    }
    if !reader.finish() {
        return None;
    }

    let mut rows = Vec::with_capacity(inputs.len());
    for input in &inputs {
        stats.record_http(&normalized_outcome(&input.outcome));
        if let Some(row) = http_row(input, mode, now_ms) {
            let mut writer = Writer::new();
            write_http_row(&mut writer, &row);
            rows.push(writer.into_vec());
        }
    }
    if rows.is_empty() {
        return Some(vec![1]);
    }

    let mut writer = Writer::new();
    match queue.submit_many(rows, now_ms) {
        None => writer.u8(0),
        Some(submit) => {
            writer.u8(2);
            writer.u32(submit.overflow);
            writer.u8(if submit.batch_full { 1 } else { 0 });
            writer.i64(submit.flush_delay_ms(queue.settings()));
        }
    }
    Some(writer.into_vec())
}

fn write_http_row(writer: &mut Writer, row: &HttpRow) {
    writer.i64(row.timestamp);
    writer.string(&row.package_name);
    write_optional(writer, row.authority.as_deref());
    writer.string(&row.protocol);
    writer.string(&row.outcome);
    write_optional(writer, row.matched_rule.as_deref());
    write_optional_i64(writer, row.block_subscription_id);
}

fn decode_race_input(reader: &mut Reader<'_>) -> Option<RaceInput> {
    Some(RaceInput {
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
    })
}

/// One race result; answers with the row, or nothing when there is no query name.
pub fn race(payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let input = decode_race_input(&mut reader)?;
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

/// `u32 count` then one race input per event; answers with `u32 count | rows(u32 length | bytes)`,
/// the same row layout [`race`] answers, so the writer submits the whole batch in one call.
pub fn race_batch(payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut inputs = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        inputs.push(decode_race_input(&mut reader)?);
    }
    if !reader.finish() {
        return None;
    }
    let rows: Vec<Vec<u8>> = inputs
        .iter()
        .filter_map(|input| {
            let row = race_row(input, now_ms)?;
            let mut writer = Writer::new();
            write_race_row(&mut writer, &row);
            Some(writer.into_vec())
        })
        .collect();
    Some(rows_payload(&rows))
}

/// The `u32 count | rows(u32 length | bytes)` framing the Kotlin writer queue accepts.
pub(crate) fn rows_payload(rows: &[Vec<u8>]) -> Vec<u8> {
    let mut writer = Writer::new();
    writer.u32(rows.len() as u32);
    for row in rows {
        writer.blob(row);
    }
    writer.into_vec()
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

fn decode_bootstrap_input(reader: &mut Reader<'_>) -> Option<BootstrapInput> {
    Some(BootstrapInput {
        ip_id: reader.string()?,
        ip_name: reader.string()?,
        ip: reader.string()?,
        host: reader.string()?,
        success: reader.u8()? != 0,
        elapsed_ms: reader.i64()?,
        fallback_used: reader.u8()? != 0,
        error_message: reader.string()?,
    })
}

/// One bootstrap probe; answers with the row, or nothing when the host is blank.
pub fn bootstrap(payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let input = decode_bootstrap_input(&mut reader)?;
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

/// The bootstrap counterpart of [`race_batch`].
pub fn bootstrap_batch(payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut inputs = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        inputs.push(decode_bootstrap_input(&mut reader)?);
    }
    if !reader.finish() {
        return None;
    }
    let rows: Vec<Vec<u8>> = inputs
        .iter()
        .filter_map(|input| {
            let row = bootstrap_row(input, now_ms)?;
            let mut writer = Writer::new();
            write_bootstrap_row(&mut writer, &row);
            Some(writer.into_vec())
        })
        .collect();
    Some(rows_payload(&rows))
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
        assert_eq!(read_optional_i(&mut reader), Some(None));
        assert!(reader.finish());
    }

    #[test]
    fn http_event_batch_classifies_and_enqueues_in_one_pass() {
        use crate::queue::{Queue, HTTP};

        let stats = Stats::new();
        let queue = Queue::new(HTTP);
        let mut writer = Writer::new();
        writer.u32(2);
        for (outcome, authority) in [("allowed", "a.test"), ("blocked", "b.test")] {
            writer.string("com.app");
            writer.string(authority);
            writer.string("https");
            writer.string(outcome);
            writer.string("");
        }
        let payload = writer.into_vec();

        let answer = http_event_batch(&stats, &queue, LogMode::All, &payload, 5).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(2), "rows were enqueued");
        assert_eq!(reader.u32(), Some(0), "no overflow");
        assert_eq!(reader.u8(), Some(0), "two rows are below the http batch");
        assert_eq!(reader.i64(), Some(HTTP.flush_interval_ms));
        assert!(reader.finish());
        assert_eq!(queue.pending_len(), 2);
        assert_eq!(stats.request_snapshot().total, 2);

        // The mode filter still applies inside the batch, and the counters still see every row.
        let stats = Stats::new();
        let queue = Queue::new(HTTP);
        let answer =
            http_event_batch(&stats, &queue, LogMode::BlockedAndErrors, &payload, 5).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(2));
        assert_eq!(reader.u32(), Some(0));
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.i64(), Some(HTTP.flush_interval_ms));
        assert!(reader.finish());
        assert_eq!(queue.pending_len(), 1);
        assert_eq!(stats.request_snapshot().total, 2);

        // Nothing to enqueue: the answer is the "hidden" status, no queue write happens.
        let mut hidden = Writer::new();
        hidden.u32(1);
        hidden.string("com.app");
        hidden.string("a.test");
        hidden.string("https");
        hidden.string("allowed");
        hidden.string("");
        let answer = http_event_batch(&stats, &queue, LogMode::Off, &hidden.into_vec(), 5).unwrap();
        assert_eq!(answer, vec![1]);
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
