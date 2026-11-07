use super::*;

fn config() -> Config {
    Config {
        enabled: true,
        rate: 12.5,
        burst: 40,
        ipv4_prefix: 24,
        ipv6_prefix: 56,
        exempt: vec!["127.0.0.1".to_string(), "10.0.0.0/8".to_string()],
    }
}

#[test]
fn config_round_trips() {
    let encoded = encode_config(&config());
    assert_eq!(encoded[0], LAYOUT_VERSION);
    let decoded = decode_config(&encoded).expect("decode");
    assert!(decoded.enabled);
    assert_eq!(decoded.rate.to_bits(), 12.5f64.to_bits());
    assert_eq!(decoded.burst, 40);
    assert_eq!(decoded.ipv4_prefix, 24);
    assert_eq!(decoded.ipv6_prefix, 56);
    assert_eq!(decoded.exempt, config().exempt);
}

#[test]
fn an_empty_exemption_list_round_trips() {
    let mut config = config();
    config.exempt.clear();
    let decoded = decode_config(&encode_config(&config)).expect("decode");
    assert!(decoded.exempt.is_empty());
}

#[test]
fn a_stale_layout_or_a_truncated_config_is_rejected() {
    let mut encoded = encode_config(&config());
    encoded[0] = LAYOUT_VERSION + 1;
    assert!(decode_config(&encoded).is_err());

    let full = encode_config(&config());
    for length in 0..full.len() {
        assert!(
            decode_config(&full[..length]).is_err(),
            "truncated at {length} should be rejected"
        );
    }

    let mut extended = full.clone();
    extended.push(0);
    assert!(decode_config(&extended).is_err());
}

#[test]
fn info_round_trips() {
    let info = Info {
        config: Normalized {
            enabled: true,
            rate: 50.0,
            burst: 100,
            ipv4_prefix: 32,
            ipv6_prefix: 128,
        },
        buckets: 3,
        exempt_ips: 2,
        exempt_nets: 1,
    };
    let encoded = encode_info(&info);
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(decode_info(&encoded).expect("decode"), info);
}

#[test]
fn a_stale_info_layout_is_rejected() {
    let info = Info {
        config: Normalized {
            enabled: false,
            rate: 50.0,
            burst: 100,
            ipv4_prefix: 32,
            ipv6_prefix: 128,
        },
        buckets: 0,
        exempt_ips: 0,
        exempt_nets: 0,
    };
    let mut encoded = encode_info(&info);
    encoded[0] = LAYOUT_VERSION + 1;
    assert!(decode_info(&encoded).is_err());
    encoded[0] = LAYOUT_VERSION;
    assert!(decode_info(&encoded[..encoded.len() - 1]).is_err());
}
