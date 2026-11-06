//! Parser vectors, ported one for one from the Go tests the migration replaced.

use super::*;

// Test vectors are assembled per the DNS Stamps spec, mirroring the Go test helpers.
fn build_stamp(proto: u8, props: u64, parts: &[&[u8]]) -> String {
    let mut bin = vec![proto];
    bin.extend_from_slice(&props.to_le_bytes());
    for part in parts {
        bin.extend_from_slice(part);
    }
    format!("sdns://{}", URL_SAFE_NO_PAD.encode(&bin))
}

fn lp(value: &str) -> Vec<u8> {
    let mut out = vec![value.len() as u8];
    out.extend_from_slice(value.as_bytes());
    out
}

/// VLP list; an empty list is a single `0x00` terminator.
fn vlp(items: &[&[u8]]) -> Vec<u8> {
    if items.is_empty() {
        return vec![0x00];
    }
    let mut out = Vec::new();
    for (index, item) in items.iter().enumerate() {
        let vlen = item.len() | if index + 1 < items.len() { 0x80 } else { 0 };
        out.push(vlen as u8);
        out.extend_from_slice(item);
    }
    out
}

fn hash_of(fill: u8) -> [u8; HASH_LEN] {
    [fill; HASH_LEN]
}

#[test]
fn plain_stamp_gets_the_default_port() {
    let text = build_stamp(0x00, 0, &[&lp("9.9.9.9")]);
    let stamp = parse(&text).unwrap();
    assert_eq!(stamp.proto, Proto::Plain);
    assert_eq!(stamp.server_addr, "9.9.9.9:53");
    assert_eq!(stamp.server(), "9.9.9.9:53");
    assert_eq!(stamp.proto.protocol(), "PLAIN");
    assert!(stamp.url().is_empty());
}

#[test]
fn plain_stamp_keeps_props_and_explicit_port() {
    let props = 0b011u64; // DNSSEC | NoLog
    let text = build_stamp(0x00, props, &[&lp("1.1.1.1:5353")]);
    let stamp = parse(&text).unwrap();
    assert_eq!(stamp.props, props);
    assert_eq!(stamp.server_addr, "1.1.1.1:5353");
}

#[test]
fn doh_stamp_carries_hashes_path_and_bootstrap_ips() {
    let hash = hash_of(0x00);
    let text = build_stamp(
        0x02,
        0b100, // NoFilter
        &[
            &lp("1.1.1.1"),
            &vlp(&[&hash]),
            &lp("cloudflare-dns.com"),
            &lp("/dns-query"),
            &vlp(&[b"1.1.1.1", b"1.0.0.1"]),
        ],
    );
    let stamp = parse(&text).unwrap();
    assert_eq!(stamp.proto, Proto::DoH);
    assert_eq!(stamp.provider_name, "cloudflare-dns.com");
    assert_eq!(stamp.path, "/dns-query");
    assert_eq!(stamp.server_addr, "1.1.1.1:443");
    assert_eq!(stamp.hashes, vec![hash]);
    assert_eq!(stamp.bootstrap_ips, vec!["1.1.1.1", "1.0.0.1"]);
    assert_eq!(stamp.url(), "https://cloudflare-dns.com/dns-query");
    assert_eq!(stamp.server(), "cloudflare-dns.com");
}

#[test]
fn doh_stamp_falls_back_to_the_default_path() {
    let text = build_stamp(
        0x02,
        0,
        &[&lp(""), &vlp(&[]), &lp("dns.example.com"), &lp("")],
    );
    let stamp = parse(&text).unwrap();
    assert_eq!(stamp.server_addr, "");
    assert_eq!(stamp.url(), "https://dns.example.com/dns-query");
    assert!(stamp.hashes.is_empty());
    assert!(stamp.bootstrap_ips.is_empty());
}

#[test]
fn doh_stamp_prefixes_a_missing_slash() {
    let text = build_stamp(
        0x02,
        0,
        &[&lp(""), &vlp(&[]), &lp("dns.example.com"), &lp("q")],
    );
    assert_eq!(
        parse(&text).unwrap().url(),
        "https://dns.example.com/q",
        "a path without a leading slash must not produce a bare host"
    );
}

#[test]
fn dot_and_doq_stamps_share_the_layout() {
    let hash = hash_of(0xAB);
    let dot = parse(&build_stamp(
        0x03,
        0,
        &[&lp("1.1.1.1"), &vlp(&[&hash]), &lp("one.one.one.one")],
    ))
    .unwrap();
    assert_eq!(dot.proto, Proto::Tls);
    assert_eq!(dot.server(), "one.one.one.one");
    assert_eq!(dot.proto.protocol(), "DOT");

    let doq = parse(&build_stamp(
        0x04,
        0,
        &[&lp("1.1.1.1"), &vlp(&[&hash]), &lp("one.one.one.one")],
    ))
    .unwrap();
    assert_eq!(doq.proto, Proto::DoQ);
    assert_eq!(doq.proto.protocol(), "DOQ");
    assert_eq!(doq.server(), "one.one.one.one");
    assert!(doq.url().is_empty());
}

#[test]
fn unsupported_protocols_are_rejected() {
    for proto in [0x01u8, 0x05, 0x81, 0x85, 0x7f] {
        let text = build_stamp(
            proto,
            0,
            &[
                &lp("1.1.1.1"),
                &vlp(&[&hash_of(0)]),
                &lp("example.com"),
                &lp("/q"),
            ],
        );
        assert!(
            parse(&text).is_err(),
            "proto 0x{proto:02x} must be rejected"
        );
    }
}

#[test]
fn malformed_stamps_are_rejected() {
    let hash32 = hash_of(0);
    let cases = [
        ("empty", String::new()),
        ("bad scheme", "https://example.com".to_string()),
        ("bad base64", "sdns://!!!not-base64!!!".to_string()),
        (
            "truncated props",
            format!("sdns://{}", URL_SAFE_NO_PAD.encode([0x00u8, 0x01])),
        ),
        (
            "garbage after",
            build_stamp(0x00, 0, &[&lp("9.9.9.9"), &[0x00]]),
        ),
        ("non-ip addr", build_stamp(0x00, 0, &[&lp("not-an-ip")])),
        ("empty port", build_stamp(0x00, 0, &[&lp("9.9.9.9:")])),
        (
            "port out of range",
            build_stamp(0x00, 0, &[&lp("9.9.9.9:99999")]),
        ),
        (
            "short hash",
            build_stamp(
                0x03,
                0,
                &[&lp("1.1.1.1"), &vlp(&[&[0u8; 16]]), &lp("example.com")],
            ),
        ),
        (
            "empty hostname",
            build_stamp(0x03, 0, &[&lp("1.1.1.1"), &vlp(&[&hash32]), &lp("")]),
        ),
    ];
    for (name, text) in cases {
        assert!(parse(&text).is_err(), "{name}: expected an error");
    }
    // Strict base64: a one-character tail cannot decode, and padding is not part of the scheme.
    assert!(
        parse("sdns://A").is_err(),
        "length % 4 == 1 must be rejected"
    );
    assert!(
        parse("sdns://AAA=").is_err(),
        "padded base64 must be rejected"
    );
}

#[test]
fn truncated_vlp_is_rejected() {
    let mut bin = vec![0x03u8];
    bin.extend_from_slice(&[0u8; 8]);
    bin.extend_from_slice(&lp("1.1.1.1"));
    bin.push(0x80 | 32);
    bin.extend_from_slice(&[0u8; 32]);
    bin.push(0x80 | 32); // announces one more element, but the stamp ends here
    let text = format!("sdns://{}", URL_SAFE_NO_PAD.encode(&bin));
    assert!(parse(&text).is_err());
}

#[test]
fn ipv6_addr_keeps_its_brackets() {
    let text = build_stamp(0x00, 0, &[&lp("[2606:4700:4700::1111]")]);
    let stamp = parse(&text).unwrap();
    assert_eq!(stamp.server_addr, "[2606:4700:4700::1111]:53");
    assert_eq!(stamp.server(), "[2606:4700:4700::1111]:53");
}

#[test]
fn provider_port_beats_address_port_and_defaults_are_dropped() {
    // Port from the hostname wins, and the plain protocol default (53) is dropped.
    let text = build_stamp(
        0x03,
        0,
        &[&lp("1.1.1.1"), &vlp(&[]), &lp("dns.example.com:853")],
    );
    let stamp = parse(&text).unwrap();
    assert_eq!(stamp.server(), "dns.example.com");

    // A non-default port survives, and the address port fills a hostname without one.
    let text = build_stamp(
        0x02,
        0,
        &[
            &lp("1.1.1.1:8443"),
            &vlp(&[]),
            &lp("dns.example.com"),
            &lp("/q"),
        ],
    );
    let stamp = parse(&text).unwrap();
    assert_eq!(stamp.server(), "dns.example.com:8443");
    assert_eq!(stamp.url(), "https://dns.example.com:8443/q");
}

#[test]
fn port_text_is_preserved_verbatim() {
    // `0443` is a valid port and must not be rewritten, mirroring the string comparison the
    // Go implementation used to decide whether to drop the port.
    let text = build_stamp(
        0x02,
        0,
        &[&lp(""), &vlp(&[]), &lp("dns.example.com:0443"), &lp("")],
    );
    let stamp = parse(&text).unwrap();
    assert_eq!(stamp.server(), "dns.example.com:0443");
}

#[test]
fn non_utf8_string_fields_are_rejected() {
    // Known boundary: the Go reader kept raw bytes. A DNS stamp is ASCII by spec, so this only
    // changes hand-crafted input, and it fails loudly instead of producing a corrupt hostname.
    let provider = vec![0x03u8, b'a', 0xff, b'b'];
    let text = build_stamp(0x03, 0, &[&lp("1.1.1.1"), &vlp(&[]), &provider]);
    assert!(parse(&text).is_err());
}

#[test]
fn scheme_prefix_is_flexible_but_required() {
    let body = URL_SAFE_NO_PAD.encode({
        let mut bin = vec![0x00u8];
        bin.extend_from_slice(&0u64.to_le_bytes());
        bin.extend_from_slice(&lp("9.9.9.9"));
        bin
    });
    assert!(parse(&format!("sdns:{body}")).is_ok());
    assert!(parse(&format!("sdns://{body}")).is_ok());
    assert!(parse(&format!("  sdns://{body}  ")).is_ok());
    assert!(parse(&format!("sdns:/{body}")).is_err());
}

#[test]
fn plain_stamp_rejects_an_empty_address() {
    let text = build_stamp(0x00, 0, &[&lp("")]);
    assert!(
        parse(&text).is_err(),
        "an empty direct address must not parse"
    );
}

#[test]
fn split_port_handles_ipv6_literals() {
    assert_eq!(split_port("9.9.9.9"), ("9.9.9.9", ""));
    assert_eq!(split_port("9.9.9.9:53"), ("9.9.9.9", "53"));
    assert_eq!(split_port("[::1]"), ("[::1]", ""));
    assert_eq!(split_port("[::1]:853"), ("[::1]", "853"));
    // Faithful to the Go helper: a bare (unbracketed) IPv6 literal is split at its last
    // colon, which is why addresses inside stamps must be bracketed.
    assert_eq!(split_port("::1"), (":", "1"));
}
