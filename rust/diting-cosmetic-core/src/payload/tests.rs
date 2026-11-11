//! Unit tests for the text payload.

use super::*;

#[test]
fn text_round_trips() {
    let tag = r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css?h=a.com">"#;
    let payload = encode_text(tag.as_bytes());
    assert_eq!(payload[0], LAYOUT_VERSION);
    assert_eq!(&payload[1..5], &(tag.len() as u32).to_le_bytes());
    assert_eq!(decode_text(&payload).unwrap(), tag);
}

#[test]
fn empty_text_round_trips() {
    let payload = encode_text(b"");
    assert_eq!(decode_text(&payload).unwrap(), "");
}

#[test]
fn a_drifted_layout_is_rejected() {
    let mut payload = encode_text(b"x");
    payload[0] = LAYOUT_VERSION + 1;
    assert!(decode_text(&payload).is_err());
}

#[test]
fn truncated_and_trailing_payloads_are_rejected() {
    let payload = encode_text(b"abc");
    for end in 0..payload.len() {
        assert!(
            decode_text(&payload[..end]).is_err(),
            "truncation at {end} was accepted"
        );
    }
    let mut longer = payload.clone();
    longer.push(0);
    assert!(decode_text(&longer).is_err());
}

#[test]
fn a_declared_length_past_the_end_is_rejected() {
    let mut payload = encode_text(b"abc");
    payload[1..5].copy_from_slice(&99u32.to_le_bytes());
    assert!(decode_text(&payload).is_err());
}

#[test]
fn all_three_rule_states_round_trip() {
    assert_eq!(
        decode_rules(&encode_rules(&RuleSet::Empty)).unwrap(),
        RuleSet::Empty
    );
    assert_eq!(
        decode_rules(&encode_rules(&RuleSet::Invalid)).unwrap(),
        RuleSet::Invalid
    );

    let mut domains = std::collections::HashMap::new();
    domains.insert(
        "example.com".to_string(),
        DomainRules {
            hide: vec![".banner".to_string(), "".to_string()],
            exception: vec![".site".to_string()],
        },
    );
    domains.insert(
        "com".to_string(),
        DomainRules {
            hide: Vec::new(),
            exception: Vec::new(),
        },
    );
    let loaded = RuleSet::Loaded(Rules {
        global_hide: vec![".global".to_string()],
        global_exception: Vec::new(),
        domains,
    });
    assert_eq!(decode_rules(&encode_rules(&loaded)).unwrap(), loaded);
}

#[test]
fn the_rules_payload_starts_with_its_version_and_state() {
    let empty = encode_rules(&RuleSet::Empty);
    assert_eq!(empty, vec![LAYOUT_VERSION, STATE_EMPTY]);
    assert_eq!(
        encode_rules(&RuleSet::Invalid),
        vec![LAYOUT_VERSION, STATE_INVALID]
    );
    assert_eq!(
        encode_rules(&RuleSet::Loaded(Rules::default())),
        vec![
            LAYOUT_VERSION,
            STATE_LOADED,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        ]
    );
}

#[test]
fn a_bad_rule_state_or_length_is_rejected() {
    let mut unknown = encode_rules(&RuleSet::Empty);
    unknown[1] = 9;
    assert!(decode_rules(&unknown).is_err());
    let mut truncated = encode_rules(&RuleSet::Loaded(Rules::default()));
    truncated.pop();
    assert!(decode_rules(&truncated).is_err());
    // A state byte claiming "loaded" without the counts must not be read as an empty rule set.
    assert!(decode_rules(&[LAYOUT_VERSION, STATE_LOADED]).is_err());
}

#[test]
fn a_text_list_round_trips() {
    let items = vec![
        "ads.example.com".to_string(),
        "example.com".to_string(),
        "com".to_string(),
    ];
    assert_eq!(decode_text_list(&encode_text_list(&items)).unwrap(), items);
    assert_eq!(
        decode_text_list(&encode_text_list(&[])).unwrap(),
        Vec::<String>::new()
    );
    let mut drifted = encode_text_list(&items);
    drifted[0] = LAYOUT_VERSION + 1;
    assert!(decode_text_list(&drifted).is_err());
}

#[test]
fn a_response_round_trips() {
    let response = Response {
        status: 200,
        content_type: "text/css; charset=utf-8",
        headers: vec![
            ("Content-Type", "text/css; charset=utf-8".to_string()),
            ("Content-Length", "9".to_string()),
        ],
        body: "a { b: c; }".to_string(),
    };
    let decoded = decode_response(&encode_response(&response)).unwrap();
    assert_eq!(decoded.status, 200);
    assert_eq!(decoded.content_type, "text/css; charset=utf-8");
    assert_eq!(decoded.body, "a { b: c; }");
    assert_eq!(decoded.headers.len(), 2);
    assert_eq!(decoded.headers[0].0, "Content-Type");
    let mut truncated = encode_response(&response);
    truncated.pop();
    assert!(decode_response(&truncated).is_err());
}
