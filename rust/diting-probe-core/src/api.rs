//! Payload codecs for the JNI entry points: decode one request, run one probe function, encode the
//! answer.
//!
//! Keeping this out of [`crate::jni_bridge`] means every layout can be unit-tested without a JVM.
//! A decoder returns None on any drift (short read, unknown tag, trailing bytes), which the bridge
//! turns into a null `ByteArray` and Kotlin turns into an `IllegalStateException`.

use crate::dns::{self, QueryType, Reply};
use crate::host;
use crate::payload::{Reader, Writer};
use crate::ping;
use crate::trace::{self, Hop};

// ---------------------------------------------------------------------------------------------
// Request layouts
// ---------------------------------------------------------------------------------------------

/// `u16 id | u8 qtype (0 = A, 1 = AAAA) | u32 domainLen | domain`.
pub fn build_dns_query(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let id = reader.u16()?;
    let qtype = QueryType::from_flag(reader.u8()?)?;
    let domain = reader.string()?;
    if !reader.finish() {
        return None;
    }
    dns::build_query(id, qtype, &domain)
}

/// `u8 ipv4 | u32 responseLen | response`.
pub fn parse_dns_server_reply(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let ipv4 = match reader.u8()? {
        0 => false,
        1 => true,
        _ => return None,
    };
    let length = reader.u32()? as usize;
    let wire = reader.bytes(length)?;
    if !reader.finish() {
        return None;
    }

    let mut writer = Writer::new();
    match dns::parse_server_reply(wire, ipv4) {
        Reply::Ok(answers) => {
            writer.u8(0);
            writer.u32(answers.len() as u32);
            for answer in answers {
                writer.u8(if answer.ipv4 { 1 } else { 2 });
                writer.u32(answer.ttl);
                writer.string(&answer.value);
            }
        }
        Reply::Invalid => writer.u8(1),
        Reply::Truncated => writer.u8(2),
        Reply::Rcode(rcode) => {
            writer.u8(3);
            writer.u8(rcode);
        }
        Reply::Incomplete => writer.u8(4),
    }
    Some(writer.into_vec())
}

/// `u32 textLen | text`.
pub fn ping_summary(payload: &[u8]) -> Option<Vec<u8>> {
    let text = read_text(payload)?;
    let mut writer = Writer::new();
    match ping::parse_summary(&text) {
        None => writer.u8(1),
        Some(summary) => {
            writer.u8(0);
            writer.i32(summary.transmitted);
            writer.i32(summary.received);
            writer.f64(summary.loss_percent);
            writer.u8(optional_flags(&[
                summary.min_ms.is_some(),
                summary.avg_ms.is_some(),
                summary.max_ms.is_some(),
                summary.jitter_ms.is_some(),
            ]));
            writer.f64(summary.min_ms.unwrap_or(0.0));
            writer.f64(summary.avg_ms.unwrap_or(0.0));
            writer.f64(summary.max_ms.unwrap_or(0.0));
            writer.f64(summary.jitter_ms.unwrap_or(0.0));
            writer.u32(summary.replies.len() as u32);
            for reply in summary.replies {
                writer.i32(reply.sequence);
                writer.u8(optional_flags(&[
                    reply.elapsed_ms.is_some(),
                    reply.ttl.is_some(),
                ]));
                writer.f64(reply.elapsed_ms.unwrap_or(0.0));
                writer.i32(reply.ttl.unwrap_or(0));
                writer.u8(if reply.timeout { 1 } else { 0 });
            }
        }
    }
    Some(writer.into_vec())
}

/// `u32 count | count * f64`.
pub fn latency_stats(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    let mut samples = Vec::with_capacity(count.min(4096));
    for _ in 0..count {
        samples.push(reader.f64()?);
    }
    if !reader.finish() {
        return None;
    }

    let stats = ping::latency_stats(&samples);
    let mut writer = Writer::new();
    writer.u8(optional_flags(&[
        stats.min_ms.is_some(),
        stats.avg_ms.is_some(),
        stats.max_ms.is_some(),
        stats.jitter_ms.is_some(),
    ]));
    writer.f64(stats.min_ms.unwrap_or(0.0));
    writer.f64(stats.avg_ms.unwrap_or(0.0));
    writer.f64(stats.max_ms.unwrap_or(0.0));
    writer.f64(stats.jitter_ms.unwrap_or(0.0));
    writer.i64(stats.rounded_average_ms);
    Some(writer.into_vec())
}

/// `u32 resolvedLen | resolved | u32 textLen | text`.
pub fn trace_hop(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let resolved = reader.string()?;
    let text = reader.string()?;
    if !reader.finish() {
        return None;
    }

    let mut writer = Writer::new();
    match trace::parse_hop(&text, &resolved) {
        Hop::Reached {
            address,
            elapsed_ms,
        } => {
            writer.u8(0);
            writer.u8(optional_flags(&[address.is_some(), elapsed_ms.is_some()]));
            if let Some(address) = address {
                writer.string(&address);
            }
            writer.f64(elapsed_ms.unwrap_or(0.0));
        }
        Hop::Answered {
            address,
            unreachable,
        } => {
            writer.u8(1);
            writer.u8(optional_flags(&[true, false, unreachable]));
            writer.string(&address);
        }
        Hop::NetUnreachable => writer.u8(2),
        Hop::NoMatch => writer.u8(3),
        Hop::Unsupported => writer.u8(4),
    }
    Some(writer.into_vec())
}

// ---------------------------------------------------------------------------------------------
// String entry points
// ---------------------------------------------------------------------------------------------

/// `NetHost.sanitize`.
pub fn sanitize_host(input: &str) -> String {
    host::sanitize(input)
}

/// `DnsLookupProbe.isIpLiteral`.
pub fn is_ip_literal(input: &str) -> bool {
    host::is_ip_literal(input)
}

/// `DnsLatencyTester.isSuccess`.
pub fn dns_response_succeeded(wire: &[u8]) -> bool {
    dns::response_succeeded(wire)
}

/// `DnsLatencyTester`'s DoH endpoint derivation.
pub fn doh_endpoint(url: &str, host_text: &str) -> String {
    dns::doh_endpoint(url, host_text)
}

/// `TraceProbe`'s streaming stamp line.
pub fn trace_response_line(line: &str) -> bool {
    trace::is_response_line(line)
}

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

fn read_text(payload: &[u8]) -> Option<String> {
    let mut reader = Reader::new(payload);
    let text = reader.string()?;
    if !reader.finish() {
        return None;
    }
    Some(text)
}

/// Packs up to eight presence bits (bit 0 is the first entry).
fn optional_flags(present: &[bool]) -> u8 {
    let mut flags = 0u8;
    for (index, value) in present.iter().enumerate().take(8) {
        if *value {
            flags |= 1 << index;
        }
    }
    flags
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text_payload(text: &str) -> Vec<u8> {
        let mut writer = Writer::new();
        writer.string(text);
        writer.into_vec()
    }

    #[test]
    fn query_request_round_trips() {
        let mut writer = Writer::new();
        writer.u16(0x1234);
        writer.u8(1);
        writer.string("example.com");
        let query = build_dns_query(&writer.into_vec()).unwrap();
        assert_eq!(query.len(), 12 + 1 + 7 + 1 + 3 + 1 + 4);
        assert_eq!(&query[..2], &[0x12, 0x34]);

        // Unknown type tag and trailing bytes are drift, not defaults.
        let mut writer = Writer::new();
        writer.u16(0);
        writer.u8(2);
        writer.string("example.com");
        assert!(build_dns_query(&writer.into_vec()).is_none());

        let mut payload = text_payload("example.com");
        payload.insert(0, 0);
        assert!(build_dns_query(&payload).is_none());
    }

    #[test]
    fn ping_summary_payload_carries_presence_bits() {
        let output = "64 bytes from 1.2.3.4: icmp_seq=1 ttl=57 time=12.5 ms\n\
2 packets transmitted, 1 received, 50% packet loss\n\
rtt min/avg/max/mdev = 12.500/12.500/12.500/0.000 ms\n";
        let payload = ping_summary(&text_payload(output)).unwrap();
        let mut reader = Reader::new(&payload);
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.i32(), Some(2));
        assert_eq!(reader.i32(), Some(1));
        assert_eq!(reader.f64(), Some(50.0));
        assert_eq!(reader.u8(), Some(0b1111));
        assert_eq!(reader.f64(), Some(12.5));
        assert_eq!(reader.f64(), Some(12.5));
        assert_eq!(reader.f64(), Some(12.5));
        assert_eq!(reader.f64(), Some(0.0));
        assert_eq!(reader.u32(), Some(2));

        assert_eq!(reader.i32(), Some(1));
        assert_eq!(reader.u8(), Some(0b11));
        assert_eq!(reader.f64(), Some(12.5));
        assert_eq!(reader.i32(), Some(57));
        assert_eq!(reader.u8(), Some(0));

        // The synthesized gap row: no elapsed, no TTL, timeout set.
        assert_eq!(reader.i32(), Some(2));
        assert_eq!(reader.u8(), Some(0b00));
        assert_eq!(reader.f64(), Some(0.0));
        assert_eq!(reader.i32(), Some(0));
        assert_eq!(reader.u8(), Some(1));
        assert!(reader.finish());
    }

    #[test]
    fn a_run_without_a_loss_line_reports_status_one() {
        let payload = ping_summary(&text_payload("ping: unknown host\n")).unwrap();
        assert_eq!(payload, vec![1]);
    }

    #[test]
    fn latency_payload_round_trips() {
        let mut writer = Writer::new();
        writer.u32(3);
        for sample in [10.0, 20.0, 30.0] {
            writer.f64(sample);
        }
        let payload = latency_stats(&writer.into_vec()).unwrap();
        let mut reader = Reader::new(&payload);
        assert_eq!(reader.u8(), Some(0b1111));
        assert_eq!(reader.f64(), Some(10.0));
        assert_eq!(reader.f64(), Some(20.0));
        assert_eq!(reader.f64(), Some(30.0));
        assert_eq!(reader.f64(), Some(20.0 / 3.0));
        assert_eq!(reader.i64(), Some(20));
        assert!(reader.finish());

        // Fewer samples than declared is drift.
        let mut writer = Writer::new();
        writer.u32(2);
        writer.f64(1.0);
        assert!(latency_stats(&writer.into_vec()).is_none());
    }

    #[test]
    fn trace_payload_carries_the_hop_shape() {
        let mut writer = Writer::new();
        writer.string("9.9.9.9");
        writer.string("From 192.168.1.1 icmp_seq=1 Destination Host Unreachable\n");
        let payload = trace_hop(&writer.into_vec()).unwrap();
        let mut reader = Reader::new(&payload);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u8(), Some(0b101));
        assert_eq!(reader.string().as_deref(), Some("192.168.1.1"));
        assert!(reader.finish());

        let mut writer = Writer::new();
        writer.string("");
        writer.string("no output here\n");
        assert_eq!(trace_hop(&writer.into_vec()).unwrap(), vec![3]);
    }
}
