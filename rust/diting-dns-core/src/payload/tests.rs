//! Boundary tests: the layout the Go decoder reads is the one written here byte for byte, and
//! every malformed frame is rejected instead of misread.

use super::*;
use crate::message::AddressRecord;
use diting_dns_wire::{ChainKind, ChainTarget};

#[test]
fn query_info_round_trips() {
    let payload = encode_query_info(true, "example.com", 28);
    assert_eq!(
        decode_query_info(&payload),
        Some((true, "example.com".to_string(), 28))
    );
    let invalid = encode_query_info(false, "", 1);
    assert_eq!(decode_query_info(&invalid), Some((false, String::new(), 1)));

    let mut wrong_layout = payload.clone();
    wrong_layout[0] = LAYOUT_VERSION + 1;
    assert_eq!(decode_query_info(&wrong_layout), None);
    assert_eq!(decode_query_info(&payload[..5]), None);
    let mut long = payload.clone();
    long.push(0);
    assert_eq!(decode_query_info(&long), None);

    let mut bad_flag = payload;
    bad_flag[1] = 2;
    assert_eq!(decode_query_info(&bad_flag), None);
}

#[test]
fn validation_round_trips() {
    let payload = encode_validation(1, 2);
    assert_eq!(decode_validation(&payload), Some((1, 2)));
    let mut broken = payload.clone();
    broken[0] = 9;
    assert_eq!(decode_validation(&broken), None);
    let mut long = payload;
    long.push(0);
    assert_eq!(decode_validation(&long), None);
}

fn sample() -> Extracted {
    Extracted {
        rcode: 0,
        blocked: true,
        question_name: "example.com.".to_string(),
        addresses: vec![
            AddressRecord {
                rrtype: 1,
                ttl: 5,
                address: vec![0, 0, 0, 0],
            },
            AddressRecord {
                rrtype: 28,
                ttl: 7,
                address: Vec::new(),
            },
        ],
        chain_targets: vec![
            ChainTarget {
                domain: "tracker.example".to_string(),
                kind: ChainKind::Cname,
            },
            ChainTarget {
                domain: "svc.example".to_string(),
                kind: ChainKind::Svcb,
            },
        ],
        ips: vec!["0.0.0.0".to_string(), "<nil>".to_string()],
        resolved_ips: "0.0.0.0,<nil>".to_string(),
    }
}

#[test]
fn extraction_round_trips_every_field() {
    let extracted = sample();
    let payload = encode_extracted(&extracted);
    assert_eq!(payload[0], LAYOUT_VERSION);
    assert_eq!(payload[3], FLAG_BLOCKED);
    assert_eq!(decode_extracted(&payload), Some(extracted));
}

#[test]
fn extraction_rejects_damaged_frames() {
    let valid = encode_extracted(&sample());

    let mut wrong_layout = valid.clone();
    wrong_layout[0] = LAYOUT_VERSION + 1;
    assert_eq!(decode_extracted(&wrong_layout), None);

    let mut unknown_flags = valid.clone();
    unknown_flags[3] |= 0x80;
    assert_eq!(decode_extracted(&unknown_flags), None);

    let mut truncated = valid.clone();
    truncated.pop();
    assert_eq!(decode_extracted(&truncated), None);

    let mut trailing = valid;
    trailing.push(b'x');
    assert_eq!(decode_extracted(&trailing), None);

    let bad_type = encode_extracted(&Extracted {
        addresses: vec![AddressRecord {
            rrtype: 5,
            ttl: 1,
            address: vec![1],
        }],
        ..Extracted::default()
    });
    assert_eq!(decode_extracted(&bad_type), None);
}
