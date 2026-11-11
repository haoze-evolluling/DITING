//! Parity corpus generated from the old Go implementation (`internal/core/dns64.go`) just before it
//! was replaced. Every row here was produced by running the Go code, not by re-deriving the RFC, so
//! a divergence shows up as a failing row instead of a silently different answer.

use std::collections::HashMap;
use std::path::Path;

use diting_dns64_core::{parse_cidr, parse_dns64_prefix, to4, Engine, PrefixError};

fn load(name: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name);
    std::fs::read_to_string(&path).unwrap_or_else(|err| panic!("{}: {err}", path.display()))
}

/// Splits a fixture into its header and rows, dropping empty lines.
fn rows(name: &str) -> Vec<Vec<String>> {
    let text = load(name);
    text.lines()
        .filter(|line| !line.is_empty())
        .map(|line| line.split('\t').map(unescape).collect())
        .collect()
}

/// Undoes the generator's escaping (`\n`, `\r`, `\t`, `\\`).
fn unescape(field: &str) -> String {
    let mut out = String::with_capacity(field.len());
    let mut chars = field.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            out.push(ch);
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

/// `4:<hex>` / `16:<hex>` / `none`, the encoding the generator used for `net.IP`.
fn address(spec: &str) -> Option<Vec<u8>> {
    if spec == "none" {
        return None;
    }
    let (width, hex) = spec.split_once(':').expect("address spec has a width");
    let width: usize = width.parse().expect("width is a number");
    assert_eq!(hex.len(), width * 2, "address hex width for {spec}");
    Some(
        (0..width)
            .map(|index| u8::from_str_radix(&hex[index * 2..index * 2 + 2], 16).expect("hex"))
            .collect(),
    )
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn prefixes(spec: &str) -> Vec<String> {
    if spec == "-" {
        return Vec::new();
    }
    spec.split('|').map(str::to_string).collect()
}

fn engine(prefixes: &[String]) -> Engine {
    Engine::new(true, prefixes)
        .unwrap_or_else(|rejection| panic!("fixture prefixes {prefixes:?} rejected: {rejection:?}"))
}

#[test]
fn prefixes_match_the_old_constructor() {
    let rows = rows("prefixes.tsv");
    assert!(rows.len() > 40, "expected a broad corpus");
    for row in &rows[1..] {
        let (input, trimmed, kind) = (&row[0], &row[1], &row[2]);
        match kind.as_str() {
            "skip" => {
                assert!(trimmed.is_empty(), "{input:?} trims to {trimmed:?}");
                let built = Engine::new(true, std::slice::from_ref(input));
                assert!(built.is_ok(), "{input:?} should be skipped, not rejected");
                assert_eq!(built.unwrap().prefix_count(), 0, "{input:?}");
            }
            "parse" => assert_eq!(
                parse_dns64_prefix(trimmed),
                Err(PrefixError::Parse),
                "{trimmed:?}"
            ),
            "length" => assert_eq!(
                parse_dns64_prefix(trimmed),
                Err(PrefixError::Length),
                "{trimmed:?}"
            ),
            other => {
                let mut parts = other.split(':');
                assert_eq!(parts.next(), Some("ok"), "{other}");
                let ones: u8 = parts.next().unwrap().parse().unwrap();
                let expected = parts.next().unwrap();
                let (prefix, _) = parse_dns64_prefix(trimmed).expect(trimmed);
                assert_eq!(prefix.ones, ones, "{trimmed:?}");
                assert_eq!(hex(&prefix.addr), expected, "{trimmed:?}");
            }
        }
    }
}

#[test]
fn cidr_parsing_keeps_go_family_and_width() {
    // `length` above means "parsed but rejected by RFC 6052"; check that `parse_cidr` itself
    // accepted exactly the rows the Go `net.ParseCIDR` accepted.
    for row in &rows("prefixes.tsv")[1..] {
        let (trimmed, kind) = (&row[1], &row[2]);
        if kind == "skip" {
            continue;
        }
        let parsed = parse_cidr(trimmed);
        if kind == "parse" {
            assert_eq!(parsed, Err(PrefixError::Parse), "{trimmed:?}");
        } else {
            assert!(parsed.is_ok(), "{trimmed:?} should parse");
        }
    }
}

#[test]
fn embedding_matches_the_old_rfc6052_math() {
    for row in &rows("embed.tsv")[1..] {
        let (prefix_text, v4_spec, expected) = (&row[0], &row[1], &row[2]);
        let (prefix, _) = parse_dns64_prefix(prefix_text).expect(prefix_text);
        let v4 = address(v4_spec).and_then(|bytes| to4(&bytes));
        let expected = expected.strip_prefix("16:").unwrap_or(expected).to_string();
        match v4 {
            Some(v4) => assert_eq!(hex(&prefix.embed(v4)), expected, "{prefix_text} {v4_spec}"),
            None => assert_eq!(expected, "none", "{prefix_text} {v4_spec}"),
        }
    }
}

#[test]
fn exclusions_match_the_old_engine() {
    let mut engines: HashMap<String, Engine> = HashMap::new();
    for row in &rows("excluded.tsv")[1..] {
        let (prefix_list, address_spec, expected) = (&row[0], &row[1], &row[2]);
        let engine = engines
            .entry(prefix_list.clone())
            .or_insert_with(|| engine(&prefixes(prefix_list)));
        let expected = expected == "true";
        match address(address_spec) {
            // Go's `IsExcluded(nil)` is true and never reaches the kernel; keep the corpus honest
            // about which side answers that case.
            None => assert!(expected, "nil is always excluded"),
            Some(bytes) => assert_eq!(
                engine.excluded(&bytes),
                expected,
                "{prefix_list} {address_spec}"
            ),
        }
    }
}

#[test]
fn has_valid_aaaa_matches_the_old_engine() {
    let mut engines: HashMap<String, Engine> = HashMap::new();
    for row in &rows("has_valid.tsv")[1..] {
        let (prefix_list, address_specs, expected) = (&row[0], &row[1], &row[2]);
        let engine = engines
            .entry(prefix_list.clone())
            .or_insert_with(|| engine(&prefixes(prefix_list)));
        let mut owned: Vec<Vec<u8>> = Vec::new();
        if address_specs != "-" {
            for spec in address_specs.split(',') {
                // An AAAA record with a nil address is excluded before it is ever asked about.
                if let Some(bytes) = address(spec) {
                    owned.push(bytes);
                }
            }
        }
        let borrowed: Vec<&[u8]> = owned.iter().map(Vec::as_slice).collect();
        assert_eq!(
            engine.has_valid_aaaa(&borrowed),
            expected == "true",
            "{prefix_list} {address_specs:?}"
        );
    }
}

#[test]
fn synthesis_matches_the_old_engine() {
    for row in &rows("synth.tsv")[1..] {
        let (prefix_list, v4_spec, expected) = (&row[0], &row[1], &row[2]);
        let engine = engine(&prefixes(prefix_list));
        let v4 = address(v4_spec).and_then(|bytes| to4(&bytes));
        let addresses = engine.synthesize(v4);
        let expected = if *expected == "-" {
            String::new()
        } else {
            expected
                .split(',')
                .map(|spec| spec.split_once(':').unwrap().1.to_string())
                .collect::<Vec<_>>()
                .join(",")
        };
        let actual = addresses
            .iter()
            .map(|bytes| hex(bytes))
            .collect::<Vec<_>>()
            .join(",");
        assert_eq!(actual, expected, "{prefix_list} {v4_spec}");
    }
}
