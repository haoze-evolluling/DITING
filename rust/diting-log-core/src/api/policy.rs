//! The retention sweep's plan and the crash-buffer selection.

use super::Writer;
use crate::crash;
use crate::payload::Reader;
use crate::retention::{self, StoredDays};

// ---------------------------------------------------------------------------------------------
// Retention plan
// ---------------------------------------------------------------------------------------------

/// `u8 hasLogDays | i32 logDays | u8 hasTrafficDays | i32 trafficDays | i64 nowMs`.
pub fn retention_plan(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let log_days = read_stored_days(&mut reader)?;
    let traffic_days = read_stored_days(&mut reader)?;
    let now_ms = reader.i64()?;
    if !reader.finish() {
        return None;
    }

    let planned = retention::plan(log_days, traffic_days, now_ms);
    let mut writer = Writer::new();
    writer.i32(planned.log_days);
    writer.i64(planned.log_cutoff_ms);
    writer.i32(planned.traffic_days);
    writer.i64(planned.traffic_cutoff_ms);
    writer.u32(retention::PRUNED_TABLES.len() as u32);
    for table in retention::PRUNED_TABLES {
        writer.string(table);
    }
    writer.string(retention::TRAFFIC_TABLE);
    writer.i64(retention::BATCH_ROWS);
    Some(writer.into_vec())
}

fn read_stored_days(reader: &mut Reader<'_>) -> Option<StoredDays> {
    let present = match reader.u8()? {
        0 => false,
        1 => true,
        _ => return None,
    };
    let value = reader.i32()?;
    Some(if present {
        StoredDays::present(value)
    } else {
        StoredDays::absent()
    })
}

// ---------------------------------------------------------------------------------------------
// Crash buffer selection
// ---------------------------------------------------------------------------------------------

/// `string packageName | u32 lineCount | lines`.
pub fn crash_select(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let package_name = reader.string()?;
    let count = reader.u32()? as usize;
    let mut lines = Vec::with_capacity(count.min(8192));
    for _ in 0..count {
        lines.push(reader.string()?);
    }
    if !reader.finish() {
        return None;
    }

    let selected = crash::select(&lines, &package_name);
    let mut writer = Writer::new();
    writer.u32(selected.len() as u32);
    for line in selected {
        writer.string(&line);
    }
    Some(writer.into_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retention_payload_carries_the_tables_and_the_batch_size() {
        let mut writer = Writer::new();
        writer.u8(0);
        writer.i32(0);
        writer.u8(1);
        writer.i32(60);
        writer.i64(1_000 * retention::DAY_MS);
        let payload = retention_plan(&writer.into_vec()).unwrap();
        let mut reader = Reader::new(&payload);
        // 7 is the default window; both cutoffs are `now_ms - days * DAY_MS`.
        assert_eq!(reader.i32(), Some(7));
        assert_eq!(reader.i64(), Some(993 * retention::DAY_MS));
        assert_eq!(reader.i32(), Some(60));
        assert_eq!(reader.i64(), Some(940 * retention::DAY_MS));
        assert_eq!(reader.u32(), Some(4));
        assert_eq!(reader.string().as_deref(), Some("dns_log"));
        assert_eq!(reader.string().as_deref(), Some("http_request_log"));
        assert_eq!(reader.string().as_deref(), Some("dns_race_log"));
        assert_eq!(reader.string().as_deref(), Some("bootstrap_log"));
        assert_eq!(reader.string().as_deref(), Some("app_traffic_daily"));
        assert_eq!(reader.i64(), Some(5_000));
        assert!(reader.finish());
    }

    #[test]
    fn crash_selection_round_trips() {
        let mut writer = Writer::new();
        writer.string("com.haoze.diting");
        writer.u32(3);
        writer.string("keep com.haoze.diting");
        writer.string("--------- beginning of crash");
        writer.string("drop com.other.app");
        let payload = crash_select(&writer.into_vec()).unwrap();
        let mut reader = Reader::new(&payload);
        // The header starts a new block, so only the first line's block names the package.
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("keep com.haoze.diting"));
        assert!(reader.finish());
    }
}
