//! The DNS batch: counters for every row, `dns_log` rows for the ones the mode keeps.
//!
//! Both entry points share [`classify_dns_batch`], so the counters cannot see a different set of
//! rows than the writer. [`dns_batch_submit`] exists so the classification and the writer queue
//! happen in one crossing instead of handing every row back to Kotlin only to re-pack it.

use crate::payload::{Reader, Writer};
use crate::queue::Queue;
use crate::row::{dns_row, DnsInput, DnsRow, LogMode};
use crate::stats::Stats;

use super::{write_optional, write_optional_i64};

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

/// Decodes one DNS batch, feeds the counters and classifies every row the mode keeps.
///
/// The counters are fed from every row *before* the mode filter, because the notification shows
/// requests with logging switched off too. The rows are already in the layout the writer queue
/// carries (`pack_dns_row`), so no caller has to decode and re-pack them.
fn classify_dns_batch(
    stats: &Stats,
    mode: LogMode,
    payload: &[u8],
    now_ms: i64,
) -> Option<Vec<Vec<u8>>> {
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
        return Some(Vec::new());
    }

    Some(
        inputs
            .iter()
            .filter_map(|input| dns_row(input, mode, now_ms))
            .map(|row| pack_dns_row(&row))
            .collect(),
    )
}

/// `u32 count` then the rows; answers with the rows `dns_log` should receive, each one already in
/// the layout the writer queue carries.
pub fn dns_batch(stats: &Stats, mode: LogMode, payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let rows = classify_dns_batch(stats, mode, payload, now_ms)?;
    // `u32 count | rows(u32 length | bytes)`, the same packing the writer queues carry, so Kotlin
    // only unpacks each blob into `dns_log` columns.
    Some(super::rows_payload(&rows))
}

/// Classify one DNS batch and enqueue it in a single call.
///
/// Kotlin used to call `dnsBatch` (answer: one blob per row), unpack every row into a `ByteArray`,
/// hand the `List` back to `queueSubmitMany` for re-packing, and let this crate decode the blobs
/// again. The rows never need to leave the kernel: this entry point classifies them and hands them
/// to the writer queue directly, over one crossing.
///
/// Answers:
///
/// ```text
/// u8 0  queue closed, nothing enqueued
/// u8 1  nothing enqueued (logging off, or the mode hid every row)
/// u8 2  u32 overflow | u8 batch_full | i64 flush_delay_ms
/// ```
pub fn dns_batch_submit(
    stats: &Stats,
    queue: &Queue,
    mode: LogMode,
    payload: &[u8],
    now_ms: i64,
) -> Option<Vec<u8>> {
    let rows = classify_dns_batch(stats, mode, payload, now_ms)?;
    Some(super::submit_classified(queue, rows, now_ms))
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::read_optional;

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

    fn read_optional_i(reader: &mut Reader<'_>) -> Option<Option<i64>> {
        match reader.u8()? {
            0 => Some(None),
            1 => Some(Some(reader.i64()?)),
            _ => None,
        }
    }

    /// Two rows: one passed query with a cache hit, one blocked by the firewall.
    fn two_row_batch() -> Vec<u8> {
        let mut writer = Writer::new();
        writer.u32(2);
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
        writer.into_vec()
    }

    #[test]
    fn dns_batch_counts_every_row_and_keeps_the_mode_filter() {
        let stats = Stats::new();
        let payload = two_row_batch();

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

        // MODE_OFF still counts but logs nothing: the answer is an honest zero-count payload, not
        // an empty one the Kotlin reader would trip over.
        let off = dns_batch(&stats, LogMode::Off, &payload, 7).unwrap();
        assert_eq!(off, vec![0, 0, 0, 0]);
        assert_eq!(stats.request_snapshot().total, 3);
    }

    #[test]
    fn dns_batch_submit_classifies_and_enqueues_in_one_pass() {
        use crate::queue::{Queue, LOG_TABLE};

        let stats = Stats::new();
        let queue = Queue::new(LOG_TABLE);
        let payload = two_row_batch();

        let answer = dns_batch_submit(&stats, &queue, LogMode::All, &payload, 5).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(2), "rows were enqueued");
        assert_eq!(reader.u32(), Some(0), "no overflow");
        assert_eq!(reader.u8(), Some(0), "two rows are below the log batch");
        assert_eq!(reader.i64(), Some(LOG_TABLE.flush_interval_ms));
        assert!(reader.finish());
        assert_eq!(queue.pending_len(), 2);
        assert_eq!(stats.request_snapshot().total, 1);

        // The mode filter still applies inside the batch, and the counters still see every row.
        let answer =
            dns_batch_submit(&stats, &queue, LogMode::BlockedAndErrors, &payload, 5).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(2));
        assert_eq!(queue.pending_len(), 3);
        assert_eq!(stats.request_snapshot().total, 2);

        // Logging off feeds the counters and answers the "hidden" status; nothing is enqueued.
        let answer = dns_batch_submit(&stats, &queue, LogMode::Off, &payload, 5).unwrap();
        assert_eq!(answer, vec![1]);
        assert_eq!(queue.pending_len(), 3);
        assert_eq!(stats.request_snapshot().total, 3);
    }
}
