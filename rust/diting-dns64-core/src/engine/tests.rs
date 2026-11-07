use super::*;
use crate::addr::map_v4;
use crate::prefix::PrefixError;

fn engine(prefixes: &[&str]) -> Engine {
    let owned: Vec<String> = prefixes.iter().map(|text| (*text).to_string()).collect();
    Engine::new(true, &owned).expect("prefixes should parse")
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[test]
fn embed_places_the_ipv4_address_behind_each_prefix_length() {
    let v4 = [192, 0, 2, 1];
    for (prefix, expected) in [
        ("2001:db8::/32", "20010db8c00002010000000000000000"),
        ("2001:db8:100::/40", "20010db801c000020001000000000000"),
        ("2001:db8:1234::/48", "20010db81234c0000002010000000000"),
        (
            "2001:db8:1234:5600::/56",
            "20010db8123456c00000020100000000",
        ),
        (
            "2001:db8:1234:5678::/64",
            "20010db81234567800c0000201000000",
        ),
        ("64:ff9b::/96", "0064ff9b0000000000000000c0000201"),
    ] {
        let engine = engine(&[prefix]);
        assert_eq!(hex(&engine.map(v4)), expected, "{prefix}");
        // The `u` byte is reserved and must stay zero.
        assert_eq!(engine.map(v4)[8], 0, "{prefix}");
    }
}

#[test]
fn map_falls_back_to_the_well_known_prefix_when_nothing_is_configured() {
    let blank = engine(&["", "   "]);
    assert_eq!(blank.prefix_count(), 0);
    assert_eq!(
        hex(&blank.map([192, 0, 2, 1])),
        "0064ff9b0000000000000000c0000201"
    );

    let none = Engine::new(true, &[]).unwrap();
    assert_eq!(
        hex(&none.map([192, 0, 2, 1])),
        "0064ff9b0000000000000000c0000201"
    );
}

#[test]
fn synthesize_returns_one_address_per_prefix_in_order() {
    let engine = engine(&["64:ff9b::/96", "2001:db8::/32"]);
    let addresses = engine.synthesize(Some([192, 0, 2, 1]));
    assert_eq!(addresses.len(), 2);
    assert_eq!(hex(&addresses[0]), "0064ff9b0000000000000000c0000201");
    assert_eq!(hex(&addresses[1]), "20010db8c00002010000000000000000");
}

#[test]
fn synthesize_skips_missing_ipv4_addresses_and_a_disabled_engine() {
    let engine = engine(&["64:ff9b::/96"]);
    assert!(engine.synthesize(None).is_empty());

    let disabled: Vec<String> = vec!["64:ff9b::/96".to_string()];
    let disabled = Engine::new(false, &disabled).unwrap();
    assert!(!disabled.is_enabled());
    assert!(disabled.synthesize(Some([192, 0, 2, 1])).is_empty());
}

#[test]
fn exclusions_cover_loopback_link_local_and_synthesized_addresses() {
    let engine = engine(&["64:ff9b::/96"]);
    let mut loopback = [0u8; 16];
    loopback[15] = 1;
    assert!(engine.excluded(&loopback));
    assert!(engine.excluded(&[0u8; 16]));
    assert!(engine.excluded(&[0, 0, 0, 0]));

    let mut link_local = [0u8; 16];
    link_local[0] = 0xfe;
    link_local[1] = 0x80;
    link_local[15] = 1;
    assert!(engine.excluded(&link_local));

    // The configured prefix itself is excluded so a second pass cannot recurse.
    let synthesized = engine.map([192, 0, 2, 1]);
    assert!(engine.excluded(&synthesized));

    // A normal global address is not.
    let global = crate::addr::parse_addr("2606:4700:4700::1111").unwrap().1;
    assert!(!engine.excluded(&global));

    // Every IPv4 address matches the mapped default exclusion's collapsed network — the quirk the
    // old `IPNet.Contains` exhibited and the corpus pins.
    assert!(engine.excluded(&[1, 2, 3, 4]));
    assert!(engine.excluded(&map_v4([1, 2, 3, 4])));
    // Odd widths are neither unspecified nor inside a network.
    assert!(!engine.excluded(&[1, 2, 3, 4, 5]));
    // The non-nil empty `net.IP` is `false` here; Go handles `nil` before calling.
    assert!(!engine.excluded(&[]));
}

#[test]
fn has_valid_aaaa_survives_only_when_an_address_is_outside_the_exclusion_set() {
    let engine = engine(&["64:ff9b::/96"]);
    assert!(!engine.has_valid_aaaa(&[]));

    let mut loopback = [0u8; 16];
    loopback[15] = 1;
    assert!(!engine.has_valid_aaaa(&[&loopback]));
    // The configured prefix is excluded, so a synthesized address is never "valid" on its own.
    assert!(!engine.has_valid_aaaa(&[&engine.map([192, 0, 2, 1])]));
    let global = crate::addr::parse_addr("2606:4700:4700::1111").unwrap().1;
    assert!(engine.has_valid_aaaa(&[&loopback, &global]));
    assert!(engine.has_valid_aaaa(&[&global]));
    let address = engine.map([192, 0, 2, 1]);
    assert!(!engine.has_valid_aaaa(&[&loopback, &address]));
}

#[test]
fn rejected_prefixes_report_the_index_the_user_typed() {
    let prefixes = vec![
        "64:ff9b::/96".to_string(),
        " 2001:db8::/32 ".to_string(),
        "2001:db8::/28".to_string(),
    ];
    let rejection = Engine::new(true, &prefixes).unwrap_err();
    assert_eq!(rejection.index, 2);
    assert_eq!(rejection.error, PrefixError::Length);

    let prefixes = vec!["64:ff9b::/96".to_string(), "nonsense".to_string()];
    let rejection = Engine::new(true, &prefixes).unwrap_err();
    assert_eq!(rejection.index, 1);
    assert_eq!(rejection.error, PrefixError::Parse);
}

#[test]
fn blank_entries_are_skipped_without_shifting_the_reported_index() {
    let prefixes = vec!["   ".to_string(), "2001:db8::/28".to_string()];
    let rejection = Engine::new(true, &prefixes).unwrap_err();
    // The index is the position in the configured list, blanks included: Go quotes `Prefixes[i]`.
    assert_eq!(rejection.index, 1);
}

#[test]
fn duplicate_prefixes_are_kept() {
    let engine = engine(&["64:ff9b::/96", "64:ff9b::/96"]);
    assert_eq!(engine.prefix_count(), 2);
    assert_eq!(engine.synthesize(Some([192, 0, 2, 1])).len(), 2);
}
