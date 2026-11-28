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
        ttl: reader.i64()?,
        client_ip: reader.string()?,
        client_name: reader.string()?,
        protocol: reader.string()?,
        upstream_provider: reader.string()?,
        rcode: reader.string()?,
        cache_hit: reader.string()?,
    })
}

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

pub fn dns_batch(stats: &Stats, mode: LogMode, payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let rows = classify_dns_batch(stats, mode, payload, now_ms)?;
    Some(super::rows_payload(&rows))
}

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
    writer.string(row.result.as_str());
    write_optional(&mut writer, row.message.as_deref());
    writer.u8(if row.cached { 1 } else { 0 });
    write_optional_i64(&mut writer, row.block_subscription_id);
    write_optional(&mut writer, row.package_name.as_deref());
    writer.string(&row.client_ip);
    writer.string(&row.client_name);
    writer.string(&row.protocol);
    writer.string(&row.upstream_provider);
    writer.string(&row.rcode);
    writer.string(&row.cache_hit);
    writer.i64(row.duration_ms);
    writer.i64(row.ttl);
    writer.into_vec()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::read_optional;

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
        writer.i64(30);
        for _ in 0..6 {
            writer.string("");
        }
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
        writer.i64(0);
        for _ in 0..6 {
            writer.string("");
        }
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
        for _ in 0..6 {
            assert_eq!(reader.string().as_deref(), Some(""));
        }
        assert_eq!(reader.i64(), Some(5));
        assert_eq!(reader.i64(), Some(30));
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
        for _ in 0..6 {
            assert_eq!(reader.string().as_deref(), Some(""));
        }
        assert_eq!(reader.i64(), Some(0));
        assert_eq!(reader.i64(), Some(0));
        assert!(reader.finish());

        assert_eq!(stats.request_snapshot().total, 1);
        assert_eq!(stats.request_snapshot().passed, 1);
        assert_eq!(stats.request_snapshot().cached, 1);

        let blocked_only = dns_batch(&stats, LogMode::BlockedAndErrors, &payload, 7).unwrap();
        let rows = split_rows(&blocked_only);
        assert_eq!(rows.len(), 1);
        let mut reader = Reader::new(&rows[0]);
        assert_eq!(reader.i64(), Some(100));
        assert_eq!(reader.string().as_deref(), Some("ads.example"));
        assert_eq!(stats.request_snapshot().total, 2);

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

        let answer =
            dns_batch_submit(&stats, &queue, LogMode::BlockedAndErrors, &payload, 5).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(2));
        assert_eq!(queue.pending_len(), 3);
        assert_eq!(stats.request_snapshot().total, 2);

        let answer = dns_batch_submit(&stats, &queue, LogMode::Off, &payload, 5).unwrap();
        assert_eq!(answer, vec![1]);
        assert_eq!(queue.pending_len(), 3);
        assert_eq!(stats.request_snapshot().total, 3);
    }
}
