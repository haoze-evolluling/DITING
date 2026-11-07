//! The EV table and its comparison rules.

use super::*;

#[test]
fn every_table_entry_is_ev() {
    for oid in EV_POLICY_OIDS {
        assert!(is_extended_validation(&[oid]), "{oid}");
    }
}

#[test]
fn dv_and_ov_policies_are_not_ev() {
    for oid in [
        "2.23.140.1.2.1", // CA/Browser Forum DV
        "2.23.140.1.2.2", // CA/Browser Forum OV
        "2.5.29.32.0",    // anyPolicy
        "1.3.6.1.4.1.6449.1.2.1.5.2",
        "",
    ] {
        assert!(!is_extended_validation(&[oid]), "{oid}");
    }
    assert!(!is_extended_validation(&[]));
    assert!(!is_extended_validation_csv(""));
}

#[test]
fn one_hit_in_a_list_is_enough() {
    assert!(is_extended_validation_csv(
        "2.23.140.1.2.1,2.23.140.1.1,2.23.140.1.2.2"
    ));
    assert!(!is_extended_validation_csv("2.23.140.1.2.1,2.23.140.1.2.2"));
    assert!(is_extended_validation(&[
        "2.23.140.1.2.1",
        "1.3.6.1.4.1.34697.2.1"
    ]));
}

#[test]
fn comparison_is_numeric_arc_by_arc() {
    // Go compares ints, so a redundant leading zero is the same OID.
    assert!(is_extended_validation(&["2.23.140.1.01"]));
    assert!(!is_extended_validation(&["2.23.140.1.1.0"]));
    assert!(!is_extended_validation(&["2.23.140.1"]));
}

#[test]
fn malformed_entries_never_match() {
    for text in [
        "abc",
        "2..1",
        "2.23.x.1.1",
        ".",
        "-2.23.140.1.1",
        "2.23.140.1.1 ",
    ] {
        assert!(!is_extended_validation(&[text]), "{text}");
    }
    // A bad entry next to a good one still matches the good one.
    assert!(is_extended_validation(&["junk", "2.23.140.1.1"]));
}
