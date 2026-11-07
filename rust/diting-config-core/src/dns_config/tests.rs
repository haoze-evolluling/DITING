//! Error precedence and the normalized result.

use super::*;
use crate::dynamic::DynamicBlock;

fn provider(protocol: &str, server: &str, url: &str) -> Provider {
    Provider {
        id: String::new(),
        protocol: protocol.to_string(),
        server: server.to_string(),
        url: url.to_string(),
        weight: 0,
    }
}

fn dynamic() -> DynamicBlock {
    DynamicBlock::normalized(true, 0, 0, 0)
}

#[test]
fn a_valid_config_normalizes_every_field() {
    let providers = [
        Provider {
            id: "a".to_string(),
            protocol: "plain".to_string(),
            server: "1.1.1.1:53".to_string(),
            url: String::new(),
            weight: 7,
        },
        provider("doh", "", "https://dns.google/dns-query"),
    ];
    let config = normalize("Race", "nxdomain", dynamic(), &providers).expect("accepted");
    assert_eq!(config.mode, crate::mode::MODE_PARALLEL_RACE);
    assert_eq!(
        config.block_response,
        crate::protocol::ResponseType::NxDomain
    );
    assert_eq!(config.dynamic.request_threshold, 5);
    assert_eq!(config.providers.len(), 2);
    assert_eq!(config.providers[0].protocol, Protocol::Plain);
    assert_eq!(config.providers[0].weight, 7);
    assert_eq!(config.providers[1].protocol, Protocol::Doh);
}

#[test]
fn the_mode_is_checked_first() {
    let error = normalize("nope", "nxdomain", dynamic(), &[]).unwrap_err();
    assert_eq!(error, "unsupported DNS mode \"nope\"");
}

#[test]
fn an_empty_provider_list_is_rejected_before_the_single_mode_check() {
    assert_eq!(
        normalize("single", "", dynamic(), &[]).unwrap_err(),
        "DNS config has no providers"
    );
    assert_eq!(
        normalize("race", "", dynamic(), &[]).unwrap_err(),
        "DNS config has no providers"
    );
}

#[test]
fn single_mode_requires_exactly_one_provider() {
    let providers = [
        provider("plain", "1.1.1.1:53", ""),
        provider("plain", "1.0.0.1:53", ""),
    ];
    assert_eq!(
        normalize("single", "", dynamic(), &providers).unwrap_err(),
        "single DNS mode requires exactly one provider"
    );
    assert!(normalize("parallel_race", "", dynamic(), &providers).is_ok());
}

#[test]
fn provider_errors_carry_their_index() {
    let providers = [
        provider("plain", "1.1.1.1:53", ""),
        provider("plain", "1.1.1.1", ""),
    ];
    assert_eq!(
        normalize("race", "", dynamic(), &providers).unwrap_err(),
        "provider 1: invalid PLAIN endpoint \"1.1.1.1\": address 1.1.1.1: missing port in address"
    );
    let providers = [provider("hyper", "1.1.1.1:53", "")];
    assert_eq!(
        normalize("race", "", dynamic(), &providers).unwrap_err(),
        "provider 0: unsupported protocol \"HYPER\""
    );
}

#[test]
fn the_first_bad_provider_stops_the_pass() {
    let providers = [
        provider("hyper", "1.1.1.1:53", ""),
        provider("plain", "", ""),
    ];
    assert!(normalize("race", "", dynamic(), &providers)
        .unwrap_err()
        .starts_with("provider 0:"));
}
