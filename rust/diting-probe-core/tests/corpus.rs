//! Replays the fixtures `rust/tools/probe-reference/ProbeReference.java` generated.
//!
//! The reference is a line-for-line JVM port of the Kotlin the probes used (same
//! `java.util.regex` patterns, same `toIntOrNull` / `toDoubleOrNull` / `average()` /
//! `roundToLong()`, same `DataInputStream` walk), so these files pin the Rust kernel against the
//! implementation it replaced instead of against a hand-written expectation.
//!
//! Regenerate after changing a parse rule or a payload layout:
//!
//! ```text
//! java rust/tools/probe-reference/ProbeReference.java --corpus rust/diting-probe-core/tests/fixtures
//! ```

use std::path::PathBuf;

use diting_probe_core::api;
use diting_probe_core::payload::Writer;

fn fixture(name: &str) -> Vec<Vec<String>> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join(name);
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("{}: {error}", path.display()));
    let mut rows = Vec::new();
    for line in text.lines() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        rows.push(line.split('\t').map(unescape).collect());
    }
    assert!(!rows.is_empty(), "{} carries no rows", path.display());
    rows
}

fn unescape(field: &str) -> String {
    let mut out = String::with_capacity(field.len());
    let mut chars = field.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('t') => out.push('\t'),
            Some('\\') => out.push('\\'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

fn from_hex(field: &str) -> Vec<u8> {
    assert!(field.len().is_multiple_of(2), "odd hex length: {field}");
    (0..field.len() / 2)
        .map(|index| u8::from_str_radix(&field[index * 2..index * 2 + 2], 16).expect("hex byte"))
        .collect()
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn text_payload(text: &str) -> Vec<u8> {
    let mut writer = Writer::new();
    writer.string(text);
    writer.into_vec()
}

#[test]
fn host_fixtures_match() {
    for row in fixture("host.tsv") {
        let (input, sanitized, literal) = (&row[0], &row[1], &row[2]);
        assert_eq!(&api::sanitize_host(input), sanitized, "sanitize({input:?})");
        assert_eq!(
            api::is_ip_literal(input),
            literal == "1",
            "isIpLiteral({input:?})"
        );
    }
}

#[test]
fn dns_query_fixtures_match() {
    for row in fixture("dns_query.tsv") {
        let mut writer = Writer::new();
        writer.u16(row[0].parse::<u16>().expect("id"));
        writer.u8(row[1].parse::<u8>().expect("qtype"));
        writer.string(&row[2]);
        let built = api::build_dns_query(&writer.into_vec());
        match built {
            Some(query) => assert_eq!(to_hex(&query), row[3], "query for {:?}", row[2]),
            None => assert_eq!(row[3], "-", "query for {:?} should have been built", row[2]),
        }
    }
}

#[test]
fn dns_reply_fixtures_match() {
    for row in fixture("dns_reply.tsv") {
        let response = from_hex(&row[1]);
        let mut writer = Writer::new();
        writer.u8(if row[0] == "1" { 1 } else { 0 });
        writer.u32(response.len() as u32);
        writer.bytes(&response);
        let payload = api::parse_dns_server_reply(&writer.into_vec()).expect("payload decodes");
        assert_eq!(to_hex(&payload), row[2], "reply {}", row[1]);
    }
}

#[test]
fn dns_success_fixtures_match() {
    for row in fixture("dns_success.tsv") {
        assert_eq!(
            api::dns_response_succeeded(&from_hex(&row[0])),
            row[1] == "1",
            "isSuccess({})",
            row[0]
        );
    }
}

#[test]
fn ping_fixtures_match() {
    for row in fixture("ping.tsv") {
        let payload = api::ping_summary(&text_payload(&row[0])).expect("payload decodes");
        assert_eq!(to_hex(&payload), row[1], "ping output {:?}", row[0]);
    }
}

#[test]
fn trace_fixtures_match() {
    for row in fixture("trace.tsv") {
        let mut writer = Writer::new();
        writer.string(&row[0]);
        writer.string(&row[1]);
        let payload = api::trace_hop(&writer.into_vec()).expect("payload decodes");
        assert_eq!(to_hex(&payload), row[2], "trace output {:?}", row[1]);
    }
}

#[test]
fn latency_fixtures_match() {
    for row in fixture("latency.tsv") {
        let mut samples = Vec::new();
        if !row[0].is_empty() {
            for bits in row[0].split(',') {
                samples.push(f64::from_bits(
                    u64::from_str_radix(bits, 16).expect("sample bits"),
                ));
            }
        }
        let mut writer = Writer::new();
        writer.u32(samples.len() as u32);
        for sample in &samples {
            writer.f64(*sample);
        }
        let payload = api::latency_stats(&writer.into_vec()).expect("payload decodes");
        assert_eq!(to_hex(&payload), row[1], "samples {:?}", row[0]);
    }
}
