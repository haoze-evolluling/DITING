//! The snapshot payload layout: round trip, nullable text and drift rejection.

use super::*;

fn row(pattern: &str, flags: u8) -> Row {
    Row {
        pattern: pattern.to_string(),
        source: "sub_one".to_string(),
        important: flags & 1 != 0,
        app_scope: if flags & 2 != 0 {
            Some("com.a| com.b ".to_string())
        } else {
            None
        },
        app_inverted: flags & 4 != 0,
        is_wildcard: flags & 8 != 0,
        denyallow: if flags & 16 != 0 {
            Some("keep.com".to_string())
        } else {
            None
        },
        is_regex: flags & 32 != 0,
        dns_type: if flags & 64 != 0 {
            Some("~AAAA".to_string())
        } else {
            None
        },
    }
}

fn sample() -> SnapshotInput {
    SnapshotInput {
        filter_enabled: true,
        trie_paths: [
            Some("/data/rule-index/domain/block.trie".to_string()),
            None,
            Some("/data/rule-index/domain/allow.trie".to_string()),
            None,
        ],
        app_allowlist: vec![
            ("com.a".to_string(), vec!["a.com".to_string()]),
            ("com.b".to_string(), Vec::new()),
        ],
        block: LoadInput {
            index_usable: true,
            important_usable: false,
            custom: vec![row("custom.com", 1), row("*.wc.com", 8)],
            subscription: vec![row("sub.com", 0), row("app.com", 2 | 4)],
        },
        allow: LoadInput {
            index_usable: false,
            important_usable: true,
            custom: Vec::new(),
            subscription: vec![row("allow.com", 0)],
        },
    }
}

#[test]
fn the_snapshot_request_round_trips() {
    let input = sample();
    let decoded = decode(&encode(&input)).expect("payload decodes");
    assert_eq!(decoded, input);
}

#[test]
fn empty_datasets_round_trip() {
    let input = SnapshotInput {
        filter_enabled: false,
        trie_paths: [None, None, None, None],
        app_allowlist: Vec::new(),
        block: LoadInput::default(),
        allow: LoadInput::default(),
    };
    let decoded = decode(&encode(&input)).expect("payload decodes");
    assert_eq!(decoded, input);
    assert_eq!(decode(&encode(&input)), Some(input));
}

#[test]
fn every_row_flag_round_trips() {
    let mut input = SnapshotInput::default();
    input
        .block
        .custom
        .push(row("all-flags.com", 1 | 2 | 4 | 8 | 16 | 32 | 64));
    let decoded = decode(&encode(&input)).expect("payload decodes");
    let decoded_row = &decoded.block.custom[0];
    assert!(decoded_row.important);
    assert_eq!(decoded_row.app_scope.as_deref(), Some("com.a| com.b "));
    assert!(decoded_row.app_inverted);
    assert!(decoded_row.is_wildcard);
    assert_eq!(decoded_row.denyallow.as_deref(), Some("keep.com"));
    assert!(decoded_row.is_regex);
    assert_eq!(decoded_row.dns_type.as_deref(), Some("~AAAA"));
}

#[test]
fn a_drifted_payload_is_rejected() {
    let encoded = encode(&sample());

    let mut bad_layout = encoded.clone();
    bad_layout[0] = LAYOUT_VERSION + 1;
    assert!(decode(&bad_layout).is_none());

    let mut trailing = encoded.clone();
    trailing.push(0);
    assert!(decode(&trailing).is_none());

    assert!(decode(&[]).is_none());
    assert!(decode(&encoded[..encoded.len() - 1]).is_none());

    // A length that disagrees with the payload is rejected instead of being read as a row count.
    let mut huge = Vec::new();
    huge.push(LAYOUT_VERSION);
    huge.push(0);
    for _ in 0..4 {
        huge.extend_from_slice(&NULL_TEXT.to_le_bytes());
    }
    huge.extend_from_slice(&u32::MAX.to_le_bytes());
    huge.extend_from_slice(&u32::MAX.to_le_bytes());
    assert!(decode(&huge).is_none());
}
