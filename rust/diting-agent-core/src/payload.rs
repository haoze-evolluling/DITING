//! Payload codecs shared by the `summary` and `prompt` entries.
//!
//! The traffic summary crosses the boundary in both directions (the Dart side keeps the typed
//! record for the UI, the kernel renders it and folds it into a prompt), so its layout lives in one
//! place instead of being spelled out at each call site:
//!
//! ```text
//! dns | blocked | rewritten | cached | http | blockedHttp | bypassedHttp | unavailable?
//! | topCount | (domain, count) * topCount
//! ```

use crate::traffic::Summary;
use crate::wire::{Reader, Writer};

pub fn write_summary(writer: &mut Writer, summary: &Summary) {
    writer.u32(summary.dns_samples);
    writer.u32(summary.blocked_dns);
    writer.u32(summary.rewritten_dns);
    writer.u32(summary.cached_dns);
    writer.u32(summary.http_samples);
    writer.u32(summary.blocked_http);
    writer.u32(summary.bypassed_http);
    writer.opt_string(summary.unavailable_reason.as_deref());
    writer.u32(summary.top_domains.len() as u32);
    for (domain, count) in &summary.top_domains {
        writer.string(domain);
        writer.u32(*count);
    }
}

pub fn read_summary(reader: &mut Reader<'_>) -> Option<Summary> {
    let dns_samples = reader.u32()?;
    let blocked_dns = reader.u32()?;
    let rewritten_dns = reader.u32()?;
    let cached_dns = reader.u32()?;
    let http_samples = reader.u32()?;
    let blocked_http = reader.u32()?;
    let bypassed_http = reader.u32()?;
    let unavailable_reason = reader.opt_string()?;
    let count = reader.u32()?;
    let mut top_domains = Vec::with_capacity(count.min(64) as usize);
    for _ in 0..count {
        let domain = reader.string()?;
        let hits = reader.u32()?;
        top_domains.push((domain, hits));
    }
    Some(Summary {
        dns_samples,
        blocked_dns,
        rewritten_dns,
        cached_dns,
        top_domains,
        http_samples,
        blocked_http,
        bypassed_http,
        unavailable_reason,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summary_round_trips() {
        let summary = Summary {
            dns_samples: 3,
            blocked_dns: 1,
            rewritten_dns: 2,
            cached_dns: 3,
            top_domains: vec![("a.test".to_string(), 2), ("b.test".to_string(), 1)],
            http_samples: 4,
            blocked_http: 5,
            bypassed_http: 6,
            unavailable_reason: None,
        };
        let mut writer = Writer::new();
        write_summary(&mut writer, &summary);
        let bytes = writer.finish();
        let mut reader = Reader::new(&bytes);
        assert_eq!(read_summary(&mut reader), Some(summary));
    }

    #[test]
    fn a_short_payload_is_rejected() {
        let bytes = [1u8, 2, 3];
        let mut reader = Reader::new(&bytes);
        assert_eq!(read_summary(&mut reader), None);
    }
}
