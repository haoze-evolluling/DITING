//! Replays the fixtures generated from the pre-migration Go implementation
//! (`android/engine/zz_config_fixture_gen_test.go` before it was deleted):
//!
//! | fixture | rows | what it pins |
//! | --- | --- | --- |
//! | `dns_mode.tsv` | 16 | `canonicalDNSMode` over every alias, padding, case fold and rejection |
//! | `dynamic_block.tsv` | 7 | the `< 1` defaults, including `MinInt32`/`MaxInt32` |
//! | `provider.tsv` | 26 | `validateDNSProvider`: PLAIN/DOT shapes, DoH URLs, DoQ URLs, unknown names |
//! | `doq_url.tsv` | 12 | `parseDoQURL` |
//! | `protocol.tsv` / `response_type.tsv` | 10 / 7 | the two name tables |
//! | `domain.tsv` | 11 | the lookup-key fold |
//! | `rewrite.tsv` | 18 | `parseRewriteEntry`, including the JSON shapes Go drops |
//! | `apply.tsv` | 7 | the order `ApplyDNSConfig` reports errors in |
//!
//! Quoted fields are Go `%q` output; [`unquote`] decodes the subset Go emits for these fixtures.

use std::fs;

use diting_config_core::dns_config::{normalize, Provider};
use diting_config_core::dynamic::DynamicBlock;
use diting_config_core::endpoint::{parse_doq_url, validate_provider};
use diting_config_core::mode::canonical_dns_mode;
use diting_config_core::protocol::{parse_protocol, parse_response_type};
use diting_config_core::rewrite::{classify, normalize_domain};

fn fixtures() -> String {
    format!("{}/tests/fixtures", env!("CARGO_MANIFEST_DIR"))
}

fn read(name: &str) -> String {
    let path = format!("{}/{name}", fixtures());
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("{path}: {err}"))
}

/// The fields of one TSV row, empty lines dropped.
fn rows(name: &str) -> Vec<Vec<String>> {
    read(name)
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| line.split('\t').map(unquote).collect())
        .collect()
}

/// Go `%q` output as emitted by the fixture generator: surrounding quotes and `\t`-free text.
fn unquote(field: &str) -> String {
    if !(field.starts_with('"') && field.ends_with('"') && field.len() >= 2) {
        return field.to_string();
    }
    let body = &field[1..field.len() - 1];
    let mut out = String::with_capacity(body.len());
    let mut chars = body.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('"') => out.push('"'),
            Some('\\') => out.push('\\'),
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('t') => out.push('\t'),
            Some('u') => {
                let digits: String = chars.by_ref().take(4).collect();
                let code = u32::from_str_radix(&digits, 16).unwrap_or(0xfffd);
                out.push(char::from_u32(code).unwrap_or('\u{fffd}'));
            }
            Some(other) => out.push(other),
            None => break,
        }
    }
    out
}

#[test]
fn dns_modes_match_the_old_canonicalization() {
    let mut checked = 0;
    for row in rows("dns_mode.tsv") {
        let (input, kind) = (&row[0], &row[1]);
        match kind.as_str() {
            "ok" => assert_eq!(
                canonical_dns_mode(input).unwrap(),
                row[2],
                "{input} must canonicalize to {}",
                row[2]
            ),
            "err" => assert_eq!(canonical_dns_mode(input).unwrap_err(), row[2], "{input}"),
            other => panic!("unexpected kind {other}"),
        }
        checked += 1;
    }
    assert_eq!(checked, 16);
}

#[test]
fn dynamic_block_defaults_match() {
    let mut checked = 0;
    for row in rows("dynamic_block.tsv") {
        let block = DynamicBlock::normalized(
            true,
            row[0].parse().unwrap(),
            row[1].parse().unwrap(),
            row[2].parse().unwrap(),
        );
        assert_eq!(
            format!(
                "{},{},{}",
                block.request_threshold, block.window_seconds, block.nxdomain_seconds
            ),
            format!("{},{},{}", row[3], row[4], row[5]),
            "{row:?}"
        );
        checked += 1;
    }
    assert_eq!(checked, 7);
}

#[test]
fn providers_match_the_old_validation() {
    let mut checked = 0;
    for row in rows("provider.tsv") {
        let (protocol, server, url, kind) = (&row[0], &row[1], &row[2], &row[3]);
        match kind.as_str() {
            "ok" => {
                let validated = validate_provider(protocol, server, url).expect(protocol);
                assert_eq!(validated.name(), row[4], "{protocol} {server} {url}");
            }
            "err" => assert_eq!(
                validate_provider(protocol, server, url).unwrap_err(),
                row[4],
                "{protocol} {server} {url}"
            ),
            other => panic!("unexpected kind {other}"),
        }
        checked += 1;
    }
    assert_eq!(checked, 26);
}

#[test]
fn doq_urls_split_the_same_way() {
    let mut checked = 0;
    for row in rows("doq_url.tsv") {
        assert_eq!(
            parse_doq_url(&row[0]),
            (row[1].clone(), row[2].clone()),
            "{}",
            row[0]
        );
        checked += 1;
    }
    assert_eq!(checked, 12);
}

#[test]
fn name_tables_match() {
    let mut checked = 0;
    for row in rows("protocol.tsv") {
        assert_eq!(
            parse_protocol(&row[0]).code().to_string(),
            row[1],
            "{}",
            row[0]
        );
        checked += 1;
    }
    for row in rows("response_type.tsv") {
        assert_eq!(
            parse_response_type(&row[0]).code().to_string(),
            row[1],
            "{}",
            row[0]
        );
        checked += 1;
    }
    assert_eq!(checked, 17);
}

#[test]
fn domain_keys_fold_the_same_way() {
    let mut checked = 0;
    for row in rows("domain.tsv") {
        assert_eq!(normalize_domain(&row[0]), row[1], "{:?}", row[0]);
        checked += 1;
    }
    assert_eq!(checked, 11);
}

#[test]
fn rewrite_entries_classify_the_same_way() {
    let mut checked = 0;
    for row in rows("rewrite.tsv") {
        let count: usize = row[1].parse().unwrap();
        let targets: Vec<String> = row[2..2 + count].to_vec();
        let entry = classify(&targets);
        let verdict = &row[2 + count];
        if verdict == "drop" {
            assert!(entry.is_none(), "{:?} must be dropped", row[0]);
        } else {
            let entry = entry.unwrap_or_else(|| panic!("{:?} must be kept", row[0]));
            assert_eq!(
                (&entry.cname, &entry.ip4, &entry.ip6),
                (&row[3 + count], &row[4 + count], &row[5 + count]),
                "{:?}",
                row[0]
            );
        }
        checked += 1;
    }
    assert_eq!(checked, 18);
}

#[test]
fn apply_errors_surface_in_the_old_order() {
    let mut checked = 0;
    for row in rows("apply.tsv") {
        let config: serde_free_config::Config = serde_free_config::parse(&row[0]);
        let dynamic = DynamicBlock::normalized(
            config.enabled,
            config.threshold,
            config.window,
            config.nxdomain,
        );
        let providers: Vec<Provider> = config
            .providers
            .iter()
            .map(|(protocol, server, url)| Provider {
                id: String::new(),
                protocol: protocol.clone(),
                server: server.clone(),
                url: url.clone(),
                weight: 0,
            })
            .collect();
        match normalize(&config.mode, &config.block_response, dynamic, &providers) {
            Ok(_) => assert_eq!(row[1], "ok", "{:?}", row[0]),
            Err(message) => assert_eq!(
                (row[1].as_str(), row[2].as_str()),
                ("err", message.as_str()),
                "{:?}",
                row[0]
            ),
        }
        checked += 1;
    }
    assert_eq!(checked, 7);
}

/// A tiny JSON reader for the `apply.tsv` configs: enough to pull the seven fields the kernel needs
/// out of the fixture text without pulling a JSON crate into the kernel.
mod serde_free_config {
    #[derive(Debug, Default)]
    pub struct Config {
        pub mode: String,
        pub block_response: String,
        pub enabled: bool,
        pub threshold: i64,
        pub window: i64,
        pub nxdomain: i64,
        /// `(protocol, server, url)` per provider entry.
        pub providers: Vec<(String, String, String)>,
    }

    pub fn parse(text: &str) -> Config {
        Config {
            mode: string_field(text, "\"mode\""),
            block_response: string_field(text, "\"blockResponse\""),
            enabled: text.contains("\"enabled\":true"),
            threshold: int_field(text, "\"requestThreshold\""),
            window: int_field(text, "\"windowSeconds\""),
            nxdomain: int_field(text, "\"nxDomainDurationSeconds\""),
            providers: providers_field(text),
        }
    }

    fn string_field(text: &str, key: &str) -> String {
        let Some(index) = text.find(key) else {
            return String::new();
        };
        let rest = &text[index + key.len()..];
        let Some(colon) = rest.find(':') else {
            return String::new();
        };
        let rest = rest[colon + 1..].trim_start();
        let Some(rest) = rest.strip_prefix('"') else {
            return String::new();
        };
        rest[..rest.find('"').unwrap_or(0)].to_string()
    }

    fn int_field(text: &str, key: &str) -> i64 {
        let Some(index) = text.find(key) else {
            return 0;
        };
        let rest = &text[index + key.len()..];
        let Some(colon) = rest.find(':') else {
            return 0;
        };
        let rest = rest[colon + 1..].trim_start();
        let end = rest
            .find(|c: char| !(c.is_ascii_digit() || c == '-'))
            .unwrap_or(rest.len());
        rest[..end].parse().unwrap_or(0)
    }

    fn providers_field(text: &str) -> Vec<(String, String, String)> {
        let Some(index) = text.find("\"providers\"") else {
            return Vec::new();
        };
        let rest = &text[index..];
        let Some(start) = rest.find('[') else {
            return Vec::new();
        };
        let Some(end) = rest.find(']') else {
            return Vec::new();
        };
        let body = &rest[start + 1..end];
        if body.trim().is_empty() {
            return Vec::new();
        }
        let mut providers = Vec::new();
        for entry in body.split("},{") {
            providers.push((
                string_field(entry, "\"protocol\""),
                string_field(entry, "\"server\""),
                string_field(entry, "\"url\""),
            ));
        }
        providers
    }
}
