//! The binary layout shared with `android/engine/mitm_filter_native.go`.
//!
//! Everything is little endian and the payload starts with a layout byte, so a mismatched
//! Go/Rust pair is a loud rejection instead of a misread field. `text` is a `u32` length followed
//! by UTF-8 bytes.
//!
//! ```text
//! report: u8 layout | u8 flags | u32 count | u32 threshold | i64 ttl_ms | text host | text reason
//!         | text write_error
//! ```
//!
//! `report.flags` carries three booleans: bit 0 `recorded` (the failure streak was counted), bit 1
//! `blacklisted` (the host is blacklisted after the call) and bit 2 `added` (this call wrote the
//! entry, so `reason`/`ttl_ms`/`write_error` are filled in). The same shape is returned by both
//! entry points, so the Go side has one decoder: a `record_failure` call can set all three, a
//! `blacklist` call sets `added` and `blacklisted`, and leaves `count`/`threshold` at zero.
//!
//! `host` is the normalized (lowercased, trimmed) host the kernel used, so the Go log lines print
//! exactly what the decision was made on; `reason` is only filled in when a blacklist entry was
//! added and `ttl_ms` is the entry lifetime that was applied. `write_error` carries the reason a
//! blacklist line could not be appended to the persistent file (empty when the append worked or
//! no path is configured) so the Go side can keep logging that warning.

use crate::filter::FailureReport;

/// Layout version of every payload below; `mitmFilterPayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

const REPORT_RECORDED: u8 = 1 << 0;
const REPORT_BLACKLISTED: u8 = 1 << 1;
const REPORT_ADDED: u8 = 1 << 2;

/// Encodes one [`FailureReport`] (or a blacklist-only report).
pub fn encode_report(report: &FailureReport) -> Vec<u8> {
    let mut flags = 0u8;
    if report.recorded {
        flags |= REPORT_RECORDED;
    }
    if report.blacklisted {
        flags |= REPORT_BLACKLISTED;
    }
    if report.blacklist.is_some() {
        flags |= REPORT_ADDED;
    }
    let (ttl_ms, reason, write_error) = match &report.blacklist {
        Some(entry) => (
            entry.ttl_ms,
            entry.reason.as_str(),
            entry.write_error.as_deref().unwrap_or(""),
        ),
        None => (0, "", ""),
    };

    let mut out = Vec::with_capacity(
        2 + 4 + 4 + 8 + 4 + report.host.len() + 4 + reason.len() + 4 + write_error.len(),
    );
    out.push(LAYOUT_VERSION);
    out.push(flags);
    out.extend_from_slice(&report.count.to_le_bytes());
    out.extend_from_slice(&report.threshold.to_le_bytes());
    out.extend_from_slice(&ttl_ms.to_le_bytes());
    push_text(&mut out, &report.host);
    push_text(&mut out, reason);
    push_text(&mut out, write_error);
    out
}

fn push_text(out: &mut Vec<u8>, value: &str) {
    out.extend_from_slice(&(value.len() as u32).to_le_bytes());
    out.extend_from_slice(value.as_bytes());
}

/// Reads a report back; used by the ABI round-trip tests and by nothing else.
#[cfg(test)]
pub(crate) fn decode_report(data: &[u8]) -> Result<FailureReport, String> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(format!("report layout {layout}, expected {LAYOUT_VERSION}"));
    }
    let flags = reader.u8("flags")?;
    let count = reader.u32("count")?;
    let threshold = reader.u32("threshold")?;
    let ttl_ms = reader.i64("ttl_ms")?;
    let host = reader.text("host")?;
    let reason = reader.text("reason")?;
    let write_error = reader.text("write_error")?;
    reader.expect_end()?;
    let blacklist = if flags & REPORT_ADDED != 0 {
        Some(crate::filter::BlacklistReport {
            host: host.clone(),
            reason,
            ttl_ms,
            write_error: if write_error.is_empty() {
                None
            } else {
                Some(write_error)
            },
        })
    } else {
        None
    };
    Ok(FailureReport {
        recorded: flags & REPORT_RECORDED != 0,
        blacklisted: flags & REPORT_BLACKLISTED != 0,
        count,
        threshold,
        host,
        blacklist,
    })
}

#[cfg(test)]
struct Reader<'a> {
    data: &'a [u8],
    position: usize,
}

#[cfg(test)]
impl<'a> Reader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, position: 0 }
    }

    fn take(&mut self, count: usize, kind: &str) -> Result<&'a [u8], String> {
        let end = self.position + count;
        if end > self.data.len() {
            return Err(format!("report truncated while reading {kind}"));
        }
        let slice = &self.data[self.position..end];
        self.position = end;
        Ok(slice)
    }

    fn u8(&mut self, kind: &str) -> Result<u8, String> {
        Ok(self.take(1, kind)?[0])
    }

    fn u32(&mut self, kind: &str) -> Result<u32, String> {
        let bytes = self.take(4, kind)?;
        Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn i64(&mut self, kind: &str) -> Result<i64, String> {
        let bytes = self.take(8, kind)?;
        let mut value = [0u8; 8];
        value.copy_from_slice(bytes);
        Ok(i64::from_le_bytes(value))
    }

    fn text(&mut self, kind: &str) -> Result<String, String> {
        let length = self.u32(&format!("{kind} length"))? as usize;
        let bytes = self.take(length, kind)?;
        String::from_utf8(bytes.to_vec()).map_err(|_| format!("report {kind} is not UTF-8"))
    }

    fn expect_end(&self) -> Result<(), String> {
        if self.position == self.data.len() {
            Ok(())
        } else {
            Err(format!(
                "report has {} trailing bytes",
                self.data.len() - self.position
            ))
        }
    }
}
