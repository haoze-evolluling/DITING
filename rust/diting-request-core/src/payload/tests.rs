//! Layout round trips.

use super::*;

fn push_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

fn push_i64(out: &mut Vec<u8>, value: i64) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn rules_payload(rules: &[(&str, &str)]) -> Vec<u8> {
    let mut payload = Vec::new();
    push_i64(&mut payload, rules.len() as i64);
    for (kind, pattern) in rules {
        push_text(&mut payload, kind);
        push_text(&mut payload, pattern);
    }
    payload
}

fn match_payload(scheme: &str, host: &str, path: &str) -> Vec<u8> {
    let mut payload = Vec::new();
    push_text(&mut payload, scheme);
    push_text(&mut payload, host);
    push_text(&mut payload, path);
    payload
}

struct Reader {
    payload: Vec<u8>,
    position: usize,
}

impl Reader {
    fn new(payload: Vec<u8>) -> Self {
        Self {
            payload,
            position: 0,
        }
    }

    fn i64(&mut self) -> i64 {
        let value = i64::from_le_bytes(
            self.payload[self.position..self.position + 8]
                .try_into()
                .unwrap(),
        );
        self.position += 8;
        value
    }

    fn text(&mut self) -> String {
        let length = u32::from_le_bytes(
            self.payload[self.position..self.position + 4]
                .try_into()
                .unwrap(),
        ) as usize;
        self.position += 4;
        let text = String::from_utf8(self.payload[self.position..self.position + length].to_vec())
            .unwrap();
        self.position += length;
        text
    }

    fn at_end(&self) -> bool {
        self.position == self.payload.len()
    }
}

#[test]
fn rule_sets_round_trip() {
    let payload = rules_payload(&[
        ("block", "https://ads.example/spy"),
        ("deny", "https://dropped.example/x"),
        ("allow", "HTTPS://CDN.Example/Assets"),
    ]);
    let decoded = decode_rules(&payload).expect("decoded");
    assert_eq!(decoded.len(), 3);
    let rules = build_rules(&decoded);
    assert_eq!(rules.len(), 2);
    assert_eq!(rules[0].pattern, "https://ads.example/spy");
    assert_eq!(rules[1].pattern, "https://cdn.example/assets");
    assert!(rules[1].allow);
}

#[test]
fn a_match_payload_encodes_the_decision() {
    let decoded = decode_rules(&rules_payload(&[("block", "https://ads.example/spy")])).unwrap();
    let rules = build_rules(&decoded);
    let request =
        decode_match(&match_payload("https", "ads.example:443", "/spy")).expect("decoded");
    let mut reader = Reader::new(encode_match(&rules, &request));
    assert_eq!(reader.i64(), 1);
    assert_eq!(reader.i64(), 1);
    assert_eq!(reader.text(), "https://ads.example/spy");
    assert_eq!(reader.text(), "ads.example");
    assert!(reader.at_end());
}

#[test]
fn malformed_payloads_are_rejected() {
    assert!(decode_rules(&[]).is_none());
    assert!(decode_rules(&[1, 0, 0, 0, 0, 0, 0, 0]).is_none());
    let mut payload = rules_payload(&[("block", "https://a.example/x")]);
    payload.push(0);
    assert!(decode_rules(&payload).is_none());
    let mut payload = Vec::new();
    push_i64(&mut payload, -1);
    assert!(decode_rules(&payload).is_none());
    let mut payload = Vec::new();
    push_i64(&mut payload, i64::MAX);
    assert!(decode_rules(&payload).is_none());

    assert!(decode_match(&[]).is_none());
    let mut payload = match_payload("https", "a.example", "/x");
    payload.push(0);
    assert!(decode_match(&payload).is_none());
    let mut payload = Vec::new();
    payload.extend_from_slice(&1000u32.to_le_bytes());
    assert!(decode_match(&payload).is_none());
}
