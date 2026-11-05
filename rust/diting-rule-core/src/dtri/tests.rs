use super::*;

fn rule<'a>(pattern: &'a str, source: &'a str) -> Rule<'a> {
    Rule {
        pattern,
        source,
        app_scope: None,
        app_inverted: false,
        is_wildcard: false,
        denyallow: None,
        is_regex: false,
        dns_type: None,
    }
}

fn header(bytes: &[u8]) -> (u32, u32, u32, u32, u32, u32, u32, u32) {
    let read = |index: usize| {
        let start = index * 4;
        u32::from_be_bytes([
            bytes[start],
            bytes[start + 1],
            bytes[start + 2],
            bytes[start + 3],
        ])
    };
    (
        read(2),
        read(3),
        read(4),
        read(5),
        read(6),
        read(7),
        read(8),
        read(0),
    )
}

#[test]
fn empty_input_writes_a_valid_root_only_file() {
    let bytes = compile(&[]);
    let (nodes, edges, sources, bloom_bits, bloom_bytes, labels, source_bytes, magic) =
        header(&bytes);
    assert_eq!(magic, MAGIC);
    assert_eq!(nodes, 1);
    assert_eq!(edges, 0);
    assert_eq!(sources, 0);
    assert_eq!(bloom_bits, 64);
    assert_eq!(bloom_bytes, 8);
    assert_eq!(labels, 0);
    assert_eq!(source_bytes, 0);
    assert_eq!(bytes.len(), HEADER_INTS * 4 + 8 + NODE_SIZE);
}

#[test]
fn skipped_rules_match_the_kotlin_filter() {
    let corpus = [
        Rule {
            is_wildcard: true,
            ..rule("ads.example.com", "a")
        },
        rule("*.example.com", "a"),
        Rule {
            app_scope: Some("com.app"),
            ..rule("ads.example.com", "a")
        },
        Rule {
            app_inverted: true,
            ..rule("ads.example.com", "a")
        },
        Rule {
            is_regex: true,
            ..rule("ads.example.com", "a")
        },
        Rule {
            denyallow: Some("safe.com"),
            ..rule("ads.example.com", "a")
        },
        Rule {
            dns_type: Some("A"),
            ..rule("ads.example.com", "a")
        },
    ];
    let bytes = compile(&corpus);
    assert_eq!(header(&bytes).0, 1, "only the root node survives");
}

#[test]
fn an_empty_optional_field_does_not_skip_a_rule() {
    let corpus = [Rule {
        app_scope: Some(""),
        denyallow: Some(""),
        dns_type: Some(""),
        ..rule("ads.example.com", "a")
    }];
    assert!(header(&compile(&corpus)).0 > 1);
}

#[test]
fn pattern_is_lowercased_and_trailing_dots_are_trimmed() {
    let plain = compile(&[rule("Ads.Example.COM", "a")]);
    let lowered = compile(&[rule("ads.example.com", "a")]);
    assert_eq!(plain, lowered);
    let dotted = compile(&[rule("ads.example.com...", "a")]);
    assert_eq!(lowered, dotted);
}

#[test]
fn a_node_keeps_the_lexicographically_smallest_source() {
    let first = compile(&[
        rule("ads.example.com", "sub_9"),
        rule("ads.example.com", "sub_1"),
    ]);
    let second = compile(&[
        rule("ads.example.com", "sub_1"),
        rule("ads.example.com", "sub_9"),
    ]);
    assert_eq!(first, second);
    let (_, _, sources, _, _, labels, _, _) = header(&first);
    assert_eq!(sources, 2);
    assert!(labels > 0);
}

#[test]
fn packed_payload_round_trips() {
    let mut payload = Vec::new();
    payload.extend_from_slice(&2u32.to_be_bytes());
    for (pattern, source, flags, extras) in [
        ("Ads.Example.com", "sub_1", 0u8, [None::<&str>, None, None]),
        ("wild.example.com", "sub_2", 1u8, [None, None, None]),
    ] {
        payload.extend_from_slice(&(pattern.len() as u32).to_be_bytes());
        payload.extend_from_slice(pattern.as_bytes());
        payload.extend_from_slice(&(source.len() as u32).to_be_bytes());
        payload.extend_from_slice(source.as_bytes());
        payload.push(flags);
        for extra in extras {
            match extra {
                Some(value) => {
                    payload.extend_from_slice(&(value.len() as u32).to_be_bytes());
                    payload.extend_from_slice(value.as_bytes());
                }
                None => payload.extend_from_slice(&u32::MAX.to_be_bytes()),
            }
        }
    }
    let compiled = compile_packed(&payload).expect("payload decodes");
    assert_eq!(compiled, compile(&[rule("Ads.Example.com", "sub_1")]));
}

#[test]
fn truncated_packed_payload_is_rejected() {
    assert!(compile_packed(&[]).is_none());
    assert!(compile_packed(&[0, 0, 0, 1]).is_none());
    assert!(compile_packed(&[0xFF, 0xFF, 0xFF, 0xFF]).is_none());
}
